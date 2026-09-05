#!/bin/bash
# 게이트: 원장의 구조가 등록부·규약과 맞는가.
#   · 스프린트 ID 형식(YYYY-SNN)
#   · rail:* 라벨의 rails.json 등재 (원장 전수)
#   · sprint:* 라벨 ↔ sprints.json 등록부의 양방향 일치 (+status 값)
#   · 스프린트 라벨의 하위 상속·조상 존재
#   · 스프린트 태스크의 acceptance 존재
# 극성: 검사 집합은 **원장 전수**에서 파생한다 — 라벨이 있는 것만 보지 않는다.
#
# 투영(docs/sprints/·docs/backlog/)은 검사하지 않는다. 그 트리는 git 밖의 생성물이라 낡을
# 수는 있어도 커밋될 수는 없다 — 다시 그리는 것은 scripts/board.sh all 이고, post-merge·
# post-checkout 훅이 그것을 부른다.
#
# set -e 를 쓰지 않는다 — 검사 스크립트는 첫 실패에서 죽으면 안 된다. 실패는 fail=1 로
# 모아서 전부 보고한다.
set -uo pipefail

# 하네스 루트(원장·등록부의 자리)는 lib/harness-root.sh 가 낸다 — 못 찾으면 여기서 rc=1 로 멈춘다.
# 조용히 건너뛰지 않는다: 원장 없이 통과한 원장 검사는 검사가 아니다.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ROOT="$(bash "$PLUGIN_ROOT/lib/harness-root.sh")" || exit 1
cd "$ROOT" || { echo "✗ 하네스 루트로 이동하지 못했다: $ROOT" >&2; exit 1; }

[ $# -eq 0 ] || { echo "✗ 인자를 받지 않는다 (사용법: board-check.sh)" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "✗ jq 가 없다 — 이 게이트는 jq 없이는 판정할 수 없다 (없으면 빈 질의 결과가 '라벨 없음' 오진이 된다)" >&2; exit 1; }

# 원장 스냅샷은 **한 번만** 뜬다 — 질의를 나누면 스냅샷 사이에 시차가 생긴다.
FULL_JSON=$(HARNESS_ROOT="$ROOT" bash "$PLUGIN_ROOT/scripts/ledger.sh" list --all --json -n 0) || { echo "✗ ledger.sh list 실패 — 원장 미가용" >&2; exit 1; }
[[ "$(printf '%s' "$FULL_JSON" | jq 'length')" -gt 0 ]] || { echo "✗ 원장이 0건이다 — 빈 집합에 대한 검사는 통과가 아니라 검사 안 함이다" >&2; exit 1; }

# JSON 은 printf 로 파이프한다 — echo 는 backslash 확장 셸에서 jq 를 깨뜨린다 (board.sh 주석 참조).
BD_SPRINTS=$(printf '%s' "$FULL_JSON" \
  | jq -r '[.[] | (.labels // [])[] | select(startswith("sprint:")) | sub("sprint:";"")] | unique | .[]')

fail=0

# ── 종료 상태 면제 목록 ─────────────────────────────────────────────
# 끝난 일(closed)과 안 하기로 한 일(deferred)에는 **남은 일의 조건**을 요구하지 않는다
# (.claude/rules/agile.md "결정 상태"). blocked 은 면제하지 않는다 — 막힌 것은 재개할 일이라
# 착수 전 acceptance 가 필요하다는 요구가 그대로 성립한다.
# 면제가 걸리는 자리는 둘뿐이다: acceptance 존재, 상속 ORPHAN. MISMATCH 는 좁히지 않는다 —
# 그 해악은 `bd list -l sprint:<ID>` 집계이고 닫힌 하위에도 그대로 성립한다.
# 역방향 단언: 면제 키가 원장에 0건이면 면제는 아무것도 안 하면서 참이 된다 — 실패로 읽는다.
TERMINAL_STATUS='["closed","deferred"]'
MISSING_STATUS=$(printf '%s' "$FULL_JSON" \
  | jq -r --argjson t "$TERMINAL_STATUS" '($t - [.[].status]) | .[]')
for st in $MISSING_STATUS; do
  echo "✗ 면제 목록의 status '$st' 가 원장에 0건이다 — 실재하지 않는 키의 면제는 검사를 조용히 지운다"
  fail=1
done

# ── 스프린트 ID 형식 ────────────────────────────────────────────────
for id in $BD_SPRINTS; do
  if [[ ! "$id" =~ ^[0-9]{4}-S[0-9]{2}$ ]]; then
    echo "✗ sprint:$id — 스프린트 ID 형식 위반 (YYYY-SNN)"
    fail=1
  fi
done

# ── 레일 등록부 대조 (원장 **전수**의 rail 라벨) ────────────────────
# 백로그 스토리도 렌더 대상이라 등록부 밖 레일은 렌더를 죽인다 — 검사가 렌더보다 좁으면
# 게이트가 아니라 렌더 실패로 알게 된다.
if [[ -f rails.json ]]; then
  BAD_RAILS=$(printf '%s' "$FULL_JSON" \
    | jq -r --slurpfile rails rails.json \
      '[.[] | (.labels // [])[] | select(startswith("rail:")) | sub("rail:";"")] | unique
       | map(select(. as $r | $rails[0].rails | has($r) | not)) | .[]')
  for r in $BAD_RAILS; do
    echo "✗ rail:$r — rails.json 에 등재되지 않은 레일"
    fail=1
  done
else
  echo "✗ rails.json 이 없다"
  fail=1
fi

# ── 스프린트 등록부 대조 (양방향) ────────────────────────────────────
# 스프린트 종료 여부의 원본은 sprints.json 의 status 다. 라벨→등록부만 보면 원장에 없는
# 유령 등재가 침묵으로 통과하고, 등록부→라벨만 보면 미등재 스프린트가 통과한다.
if [[ -f sprints.json ]]; then
  # -e 를 쓰지 않는다. 빈 등록부({"sprints":{}})는 **정상**인데 -e 는 빈 스트림에 rc=4 를 낸다.
  if ! REG_SPRINTS=$(jq -r '.sprints | keys[]' sprints.json 2>/dev/null); then
    echo "✗ sprints.json 에서 sprints 객체를 읽을 수 없다 (구문 오류이거나 sprints 키가 없다)"
    fail=1
  else
    for id in $BD_SPRINTS; do
      if ! grep -qx "$id" <<< "$REG_SPRINTS"; then
        echo "✗ sprint:$id — sprints.json 에 등재되지 않은 스프린트 (개설했다면 status 와 함께 등재하라)"
        fail=1
      fi
    done
    for id in $REG_SPRINTS; do
      if ! grep -qx "$id" <<< "$BD_SPRINTS"; then
        echo "✗ sprints.json 의 '$id' — 원장에 sprint:$id 라벨이 하나도 없다 (오타이거나 이관 후 잔존이다)"
        fail=1
      fi
    done
    # status 는 두 값뿐이다. 키만 보고 값을 안 보면 오타난 상태가 등재된 채로 통과한다.
    BAD_STATUS=$(jq -r '.sprints | to_entries[]
      | select((.value.status // "") != "active" and (.value.status // "") != "closed")
      | "\(.key)\t\(.value.status // "")"' sprints.json)
    if [[ -n "$BAD_STATUS" ]]; then
      while IFS=$'\t' read -r sid st; do
        [[ -z "$sid" ]] && continue
        echo "✗ sprints.json 의 '$sid' — status 가 active·closed 가 아니다 ('$st')"
        fail=1
      done <<< "$BAD_STATUS"
    fi
  fi
else
  echo "✗ sprints.json 이 없다 — 스프린트 종료 여부의 원본이다"
  fail=1
fi

# ── 스프린트 라벨의 하위 상속 + 조상 존재 ───────────────────────────
# bd 는 이슈를 만들 때만 부모 라벨을 물려준다. 분해된 백로그 스토리를 나중에 편입하면
# 하위에 라벨이 없고, 사람과 스킬이 `bd list -l sprint:<ID>` 로 세는 집계가 조용히 틀린다.
# 반대로 sprint 라벨은 있는데 조상 epic 이 없는 이슈는 어디에도 렌더되지 않는다. 둘 다 잡는다.
# ORPHAN 은 종료 상태를 면제한다 — 렌더되지 않는 것이 해악인데 끝난 일은 렌더될 것이 없다.
# MISMATCH 는 면제하지 않는다 (위 면제 목록 주석).
VIOLATIONS=$(printf '%s' "$FULL_JSON" | jq -r --argjson terminal "$TERMINAL_STATUS" '
  (map({key: .id, value: .}) | from_entries) as $byid
  | def sprint_label: (.labels // []) | map(select(startswith("sprint:"))) | first // null;
    def not_terminal: (.status // "") as $s | ($terminal | index($s)) == null;
    def ancestor_sprint:
      . as $start
      | [limit(8; recurse(if .parent then $byid[.parent] else empty end))]
      | map(select(.issue_type == "epic") | sprint_label)
      | map(select(. != null)) | first // null;
    map(select(.issue_type != "epic"))
    | map(. as $i | ($i | ancestor_sprint) as $exp | ($i | sprint_label) as $own
        | if $exp != null and $own != $exp then
            "MISMATCH\t\($i.id)\t\($exp)\t\($i.title)"
          elif $exp == null and $own != null and ($i | not_terminal) then
            "ORPHAN\t\($i.id)\t\($own)\t\($i.title)"
          else empty end)
    | .[]
')
if [[ -n "$VIOLATIONS" ]]; then
  while IFS=$'\t' read -r kind iid lbl title; do
    [[ -z "$iid" ]] && continue
    if [[ "$kind" == "MISMATCH" ]]; then
      echo "✗ $iid — 상위 스토리는 $lbl 인데 이 이슈에 라벨이 없다 ($title)"
      echo "    조치: ledger.sh tag $iid $lbl  (beads — 하위 전체에 붙인 뒤 scripts/board.sh all 재실행. 다른 백엔드는 label add 를 하위마다)"
    else
      echo "✗ $iid — $lbl 라벨이 있는데 조상에 스프린트 epic 이 없다 ($title) — 어디에도 렌더되지 않는다"
      echo "    조치: 스토리(epic) 밑으로 옮기거나 라벨을 떼라"
    fi
    fail=1
  done <<< "$VIOLATIONS"
fi

# ── 태스크 acceptance 존재 (규약: --acceptance 필수) ────────────────
# 요구의 문면이 "착수 전에 채워라" 다 — 종료 상태는 착수할 일이 남지 않았으므로 면제한다.
NO_ACC=$(printf '%s' "$FULL_JSON" | jq -r --argjson terminal "$TERMINAL_STATUS" '
  (map({key: .id, value: .}) | from_entries) as $byid
  | def not_terminal: (.status // "") as $s | ($terminal | index($s)) == null;
    def in_sprint:
      . as $start
      | [limit(8; recurse(if .parent then $byid[.parent] else empty end))]
      | any(.[]; (.labels // []) | any(startswith("sprint:")));
    map(select(.issue_type == "task" and ((.acceptance_criteria // "") == "") and in_sprint and not_terminal))
    | .[] | "\(.id)\t\(.title)"')
if [[ -n "$NO_ACC" ]]; then
  while IFS=$'\t' read -r tid title; do
    [[ -z "$tid" ]] && continue
    echo "✗ $tid — acceptance 가 비어 있다 ($title). 착수 전에 채워라 (ledger.sh update $tid --acceptance ...)"
    fail=1
  done <<< "$NO_ACC"
fi

[[ $fail -eq 0 ]] && echo "✓ 원장 구조 검사 통과 — 형식·레일 등재·스프린트 등록부·상속·acceptance"
exit $fail
