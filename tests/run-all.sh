#!/usr/bin/env bash
# 이 레포의 개발 검사 러너. 사용: bash tests/run-all.sh
#
# 두 집합을 돈다. **자리가 다른 이유가 곧 이 파일이 두 집합을 가지는 이유다.**
#   ① `tests/**/*.sh` — 배포되지 않는 검사. 플러그인 자기 코드를 픽스처로 때린다.
#      설치본은 이것들을 부르지 않으므로 플러그인 안에 두면 설치본이 쓰지 않는 코드를 받는다.
#   ② `plugins/harness/checks/*.sh` — 배포되는 검사. 스킬이 설치본에서 부른다(setup 의 설치 검증
#      표 · plan-sprint · verify-implement · retrospective · 하네스 루트 pre-push). 개발 중에도
#      돌려야 하므로 여기서 함께 판정한다.
#
# **극성 반전** (harness:develop "운영 규율" — 게이트는 예외 목록 방식으로 쓴다): 돌릴 검사를
# 손으로 고르지 않는다. 두 집합 모두 **실물 전수**에서 파생하고, 여기서 돌릴 수 없는 것만
# 사유와 함께 SKIP 에 등재한다. 새 검사의 기본값은 "돈다" 이고, 면제 키가 실재하지 않으면
# 그 자체를 실패로 읽는다.
#
# 검사를 이름으로 고르면 새로 만든 검사가 아무 데도 배선되지 않은 채 남는데, **배선되지 않은
# 검사는 없는 것과 같다** — 실패하고 있어도 아무도 모른다. 근거는 harness-guau.2.1.
#
# 하네스 루트: 이 러너 자신은 필요 없지만 원장을 보는 검사(board-check · rules-check 의
# 원장 절 · workspace-check)는 lib/harness-root.sh 로 찾고 못 찾으면 rc≠0 이다 — 여기서 그
# 값을 먼저 찍어 실패의 원인이 코드인지 자리인지 읽는 사람이 가를 수 있게 한다.
#
# 호출자 CWD 를 보존한다: 검사는 저마다 **호출자의 CWD 에서** 절대 경로로 부른다(위 하네스 루트
# 진단 줄도 같다). 하네스 루트는 CWD 에서 위로 `.harness.json` 을 찾아 나오므로, 이 스크립트가
# 다른 자리로 cd 한 채 부르면 대상 레포가 아니라 **그 자리**가 루트로 잡힌다. 검사들은 전부
# 자기 위치(BASH_SOURCE)에서 대상 트리를 파생하므로 호출자 CWD 에 기대지 않는다.
#
# set -e 를 쓰지 않는다 — 첫 실패에서 죽으면 나머지 검사의 결과가 보고되지 않는다. 실패는
# 모아서 전부 보고하고 마지막에 비-0 으로 끝난다.
set -uo pipefail

CALLER_PWD="$PWD"   # 호출자 CWD — 검사는 여기서 부른다(아래 cd 뒤에는 잃는다)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || { echo "✗ 레포 루트로 이동하지 못했다: $REPO_ROOT" >&2; exit 1; }
PLUGIN_ROOT="$REPO_ROOT/plugins/harness"

# ── 면제 ─────────────────────────────────────────────────────────────
# 형식: "<레포 상대 경로>|<사유>". **사유 없는 면제는 등재로 치지 않는다.**
# 면제한 검사는 사라지지 않는다 — 부르는 자리가 여기가 아닐 뿐이고, 그 자리를 사유에 적는다.
SKIP="
tests/harness/guard-check.sh|전수 자리라 여기 통째로 넣으면 이 게이트가 두 배가 된다 — 실측(skills#223, 깨끗한 직렬 1회) 이 검사 159.5초 대 여기서 도는 나머지 합계 163.3초. 느려서가 아니다: 76.6초짜리 검사가 면제 없이 여기서 돈다. 임계 아래 절은 tests/harness/guard-fast-check.sh 가 여기서 돌리므로 그 절들은 매 커밋 보인다. 전수는 plugins/harness/lib/guard/ 아래 판정을 고치는 커밋에서 손으로 돌린다 (hooks/guard.sh 는 transport 6줄이다) (bash tests/harness/guard-check.sh). 임계와 절 배정은 tests/harness/guard-check.sh 의 「절 범위」 주석이 단일 소유한다.
tests/toolkit/api-spec-viewer-check.sh|네트워크로 샘플 레포 둘을 고정 커밋에서 받는다. 오프라인에서 거짓 실패하므로 게이트에 넣으면 게이트가 거짓말을 한다. 두 추출기나 render.py 를 고치는 커밋에서 손으로 돌린다.
plugins/harness/checks/transcript-check.sh|판정 대상이 트리 밖(~/.claude/projects 의 전사)이라 이 커밋과 무관하게 rc 가 흔들린다. 다른 세션이 남긴 위반으로 이 트리의 게이트가 깨지면 게이트가 거짓말을 한다. 부르는 자리는 harness:retrospective 1-2 다.
plugins/harness/checks/ledger-check.sh|원격·원장 상태에 의존한다. 부르는 자리는 사이클 종결 단계(harness:develop 사이클 종결)다 — 여기서 부르면 네트워크 실패를 커밋 게이트의 실패로 만든다.
"

fail=0
ran=0
skipped=0

# 대상 전수. 이름을 손으로 적지 않는다. 두 집합을 각각 파생하고 **각각 공허하지 않은지** 본다 —
# 합쳐서 세면 한쪽이 통째로 비어도 다른 쪽의 수에 묻힌다.
TEST_FILES=$(find tests -type f -name '*.sh' ! -name 'run-all.sh' 2>/dev/null | sort)
[ -n "$TEST_FILES" ] || { echo "✗ tests 아래 *.sh 가 0개다 — 빈 집합에 대한 검사는 통과가 아니라 검사 안 함이다"; exit 1; }
SHIPPED_FILES=$(find plugins/harness/checks -maxdepth 1 -type f -name '*.sh' 2>/dev/null | sort)
[ -n "$SHIPPED_FILES" ] || { echo "✗ plugins/harness/checks/*.sh 가 0개다 — 빈 집합에 대한 검사는 통과가 아니라 검사 안 함이다"; exit 1; }
FILES="$TEST_FILES
$SHIPPED_FILES"

# 역방향 단언 — 면제 키가 **파생 집합에 있는가**. 실재만 보면 파생 밖으로 나간 파일의 면제가
# 살아 있는 것처럼 보이고(그 파일은 애초에 돌지 않는다), 면제 수와 실제 건너뛴 수가 갈린다.
skip_paths=""
while IFS='|' read -r path why; do
  [ -n "${path:-}" ] || continue
  if ! printf '%s\n' "$FILES" | grep -qxF -- "$path"; then
    if [ -f "$path" ]; then
      echo "✗ 면제 목록의 '$path' 가 파생 집합 밖이다 — 면제할 것도 없이 이미 안 돌고 있다. 파생을 고치거나 면제를 빼라"
    else
      echo "✗ 면제 목록의 '$path' 가 실재하지 않는다 — 실재하지 않는 키의 면제는 검사를 조용히 지운다"
    fi
    fail=1
    continue
  fi
  if [ -z "${why:-}" ]; then
    echo "✗ 면제 '$path' 에 사유가 없다"
    fail=1
  fi
  skip_paths="$skip_paths$path
"
done <<EOF
$SKIP
EOF

echo "── 트리 ($REPO_ROOT) ──"

# ⓪ 하네스 루트 — 원장 검사의 자리. 못 찾으면 **여기서 첫 실패**를 낸다 — 원장을 보는 검사가 아래에서
# 저마다의 문구로 죽기 전에, 원인(판별자 .harness.json 이 없는 자리)이 첫 줄에 오게 한다. 나머지 검사는
# 그래도 돌린다(set -e 를 쓰지 않는 이유와 같다 — 실패를 모아 전부 보고한다).
hroot_err=$(mktemp)
if hroot=$(cd "$CALLER_PWD" && bash "$PLUGIN_ROOT/lib/harness-root.sh" 2>"$hroot_err"); then
  echo "  · 하네스 루트: $hroot"
else
  echo "✗ 하네스 루트를 찾지 못했다 — $(head -1 "$hroot_err") (스토리 워크트리 안에서 돌리거나 HARNESS_ROOT 를 지정하라; 원장을 보는 검사는 아래에서도 실패한다)"
  fail=1
fi
rm -f "$hroot_err"

# ① 문법 — shellcheck 가 없는 환경에서도 이것만은 돈다(shellcheck 전수는 레포 게이트 scripts/check.sh (b) 다).
# 대상은 **실물 전수**에서 파생한다. 손으로 적은 디렉토리 목록은 새 자리가 생길 때 조용히 빠지고,
# 빈 디렉토리를 적어 두면 확장되지 않은 글롭이 그대로 bash -n 에 넘어가 엉뚱한 문구로 죽는다.
SH_ALL=$(find plugins tests -type f -name '*.sh' 2>/dev/null | sort)
n_sh=$(printf '%s' "$SH_ALL" | grep -c .)
if [ "$n_sh" -eq 0 ]; then
  echo "✗ plugins·tests 아래 *.sh 가 0개다 — 빈 집합에 대한 문법 검사는 통과가 아니라 검사 안 함이다"
  fail=1
else
  for f in $SH_ALL; do
    bash -n "$f" || { echo "✗ 문법 오류: $f"; fail=1; }
  done
  echo "  ✓ 문법 (bash -n) — plugins·tests 아래 *.sh ${n_sh}개"
fi

# ② 플러그인 JSON 의 유효성 — 훅 배선과 매니페스트.
if jq empty plugins/harness/hooks/hooks.json plugins/harness/.claude-plugin/plugin.json 2>&1; then
  echo "  ✓ hooks/hooks.json · .claude-plugin/plugin.json 유효"
else
  echo "✗ hooks.json 또는 plugin.json 이 유효한 JSON 이 아니다"
  fail=1
fi

echo "── 검사 전수 (tests/**/*.sh · plugins/harness/checks/*.sh) ──"
for f in $FILES; do
  case "$skip_paths" in
    *"$f"$'\n'*)
      skipped=$((skipped + 1))
      echo "  · 면제: $f"
      continue
      ;;
  esac
  ran=$((ran + 1))
  if (cd "$CALLER_PWD" && bash "$REPO_ROOT/$f"); then
    :
  else
    echo "✗ $f 실패 (rc=$?)"
    fail=1
  fi
done

[ "$ran" -gt 0 ] || { echo "✗ 실제로 돌린 검사가 0개다 — 면제가 집합을 통째로 지웠다"; exit 1; }

if [ "$fail" -ne 0 ]; then
  echo "✗ 개발 검사 실패 — 위 항목을 고쳐라 (돌린 검사 ${ran}개 · 면제 ${skipped}개)"
  exit 1
fi
echo "✓ 개발 검사 통과 — 돌린 검사 ${ran}개 · 면제 ${skipped}개 (면제 사유는 이 파일의 SKIP)"
