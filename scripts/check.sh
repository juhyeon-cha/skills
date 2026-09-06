#!/usr/bin/env bash
# skills 레포의 게이트. 레포 루트 기준 `bash scripts/check.sh` — 하네스 루트 repos.json 의 skills.check 가 이것이다.
#
# 네 검사를 전부 돌려 각각 보고하고, 하나라도 실패면 rc 1 이다(set -e 를 쓰지 않는다 — 첫 실패에서
# 죽으면 나머지 검사의 결과가 보고되지 않는다).
#   (a) claude plugin validate --strict — 마켓플레이스(.)와 plugins/*/ 각각
#   (b) shellcheck — plugins/ 아래 *.sh 전수(find 로 파생, 파일 수를 낸다, 0개면 실패).
#       plugins/harness/checks/shell-lint.sh 는 자기 플러그인 트리(scripts checks hooks lib)로 대상이 고정이라
#       toolkit 의 *.sh 를 덮지 못한다 — 같은 플래그(--shell=bash --severity=warning)와 같은 규칙 면제로 여기서 전수를 돈다.
#       미설치(shellcheck 가 PATH 에 없음)는 shell-lint.sh 와 같은 fail-open: 통과시키되 검사하지 못했다고 말한다.
#   (c) agent-doc-audit 회귀 — 두 플러그인과 레포 루트 스킬(.claude/skills)에서
#       1-correction · 4-date · 4-line-pointer 가 0줄. 레포 루트 스킬은 플러그인 밖에 살아
#       (a) validate 도 (b) shellcheck 도 보지 않는 자리라, 여기가 유일한 검사 자리다.
#       6-dead-path 는 harness 플러그인 docs 가 하네스 루트 상대 경로를 쓰므로 HARNESS_ROOT 가 있을 때만
#       --root 로 판정하고, 없으면 판정하지 않았다고 말한다(조용히 통과하지 않는다).
#   (d) 설명 3중 일치 — 플러그인마다 plugin.json description == marketplace.json 의 그 항목 description 이고,
#       README.md 에 그 문자열이 그대로 있다. jq 가 없으면 판정 자체가 불가능하므로 rc 1.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "✗ 레포 루트로 이동하지 못했다" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "✗ jq 가 없다 — (d) 설명 일치를 판정할 수 없다 (brew install jq)"; exit 1; }
command -v claude >/dev/null 2>&1 || { echo "✗ claude 가 없다 — (a) validate 를 돌릴 수 없다"; exit 1; }

fail=0

# ── (a) validate ─────────────────────────────────────────────────────
ok=1
targets="."
for p in plugins/*/; do targets="$targets ${p%/}"; done
for t in $targets; do
  if out=$(claude plugin validate "$t" --strict 2>&1); then :; else
    printf '%s\n' "$out"
    echo "✗ (a) claude plugin validate --strict 실패: $t"
    ok=0
  fi
done
[ "$ok" -eq 1 ] && echo "✓ (a) claude plugin validate --strict 통과 — $targets" || fail=1

# ── (b) shellcheck 전수 ──────────────────────────────────────────────
files=()
while IFS= read -r f; do files+=("$f"); done < <(find plugins -type f -name '*.sh' | sort)
n=${#files[@]}
if [ "$n" -eq 0 ]; then
  echo "✗ (b) plugins/ 아래 *.sh 가 0개다 — 빈 집합에 대한 검사는 통과가 아니라 검사 안 함이다"
  fail=1
elif ! command -v shellcheck >/dev/null 2>&1; then
  echo "⚠ (b) shellcheck 가 없다 — *.sh ${n}개를 **검사하지 못했다** (통과가 아니라 미판정이다; brew install shellcheck)"
else
  # SC2317 면제: harness 의 검사 스크립트는 함수를 정의해 두고 step 에 이름으로 넘겨 shellcheck 가 도달 불가로
  # 읽는다 — plugins/harness/checks/shell-lint.sh 의 규칙 면제와 같다.
  if out=$(shellcheck --shell=bash --severity=warning --exclude=SC2317 "${files[@]}" 2>&1); then
    echo "✓ (b) shellcheck 통과 — plugins/ 아래 *.sh ${n}개 · severity=warning 이상 0건 (규칙 면제 SC2317)"
  else
    printf '%s\n' "$out"
    echo "✗ (b) shellcheck 실패 — plugins/ 아래 *.sh ${n}개 중 지적이 있다 (위)"
    fail=1
  fi
fi

# ── (c) agent-doc-audit 회귀 ─────────────────────────────────────────
AUDIT=plugins/toolkit/skills/agent-doc-audit/check.sh
SCAN='plugins/harness plugins/toolkit .claude/skills'
crit='1-correction|4-date|4-line-pointer'
[ -n "${HARNESS_ROOT:-}" ] && crit="$crit|6-dead-path"
# shellcheck disable=SC2086  # SCAN 은 낱말 분리가 의도다; HARNESS_ROOT 가 있을 때만 --root <값> 두 낱말을 붙인다
if out=$(bash "$AUDIT" $SCAN ${HARNESS_ROOT:+--root "$HARNESS_ROOT"} 2>&1); then
  hits=$(printf '%s\n' "$out" | grep -E ":($crit):" || true)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
    echo "✗ (c) agent-doc-audit 회귀 — 위 줄이 0 이어야 한다 (기준 $crit)"
    fail=1
  else
    echo "✓ (c) agent-doc-audit 회귀 없음 — ${SCAN// / · } 에서 $crit 0줄"
  fi
else
  printf '%s\n' "$out"
  echo "✗ (c) agent-doc-audit check.sh 가 죽었다 (위 stderr)"
  fail=1
fi
if [ -n "${HARNESS_ROOT:-}" ]; then
  echo "  · 6-dead-path 는 --root $HARNESS_ROOT 로 판정했다"
else
  echo "  · 6-dead-path 는 판정하지 않았다 — HARNESS_ROOT 가 없다 (harness 플러그인 docs 는 하네스 루트 상대 경로를 쓴다; HARNESS_ROOT=<하네스루트> 로 돌리면 판정한다)"
fi

# ── (d) 설명 3중 일치 ────────────────────────────────────────────────
for p in plugins/*/; do
  name=$(basename "$p")
  d_plugin=$(jq -r '.description // empty' "$p.claude-plugin/plugin.json")
  d_market=$(jq -r --arg n "$name" '.plugins[] | select(.name == $n) | .description // empty' .claude-plugin/marketplace.json)
  if [ -z "$d_plugin" ]; then
    echo "✗ (d) $name: plugin.json 에 description 이 없다"; fail=1; continue
  fi
  if [ "$d_plugin" != "$d_market" ]; then
    echo "✗ (d) $name: plugin.json 과 marketplace.json 의 description 이 다르다 — plugin.json 이 원본이다"
    echo "    plugin.json:      $d_plugin"
    echo "    marketplace.json: ${d_market:-(항목 없음)}"
    fail=1; continue
  fi
  if ! grep -qF -- "$d_plugin" README.md; then
    echo "✗ (d) $name: README.md 에 plugin.json 의 description 문자열이 그대로 없다"; fail=1; continue
  fi
  echo "✓ (d) $name 설명 3중 일치 — plugin.json == marketplace.json, README.md 에 있음"
done

if [ "$fail" -ne 0 ]; then
  echo "✗ skills 게이트 실패 — 위 ✗ 항목을 고쳐라"
  exit 1
fi
echo "✓ skills 게이트 통과 — validate · shellcheck · agent-doc-audit 회귀 · 설명 3중 일치"
