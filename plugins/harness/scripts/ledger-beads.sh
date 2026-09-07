#!/usr/bin/env bash
# beads 백엔드 — 인자를 그대로 bd 에 넘긴다. ledger.sh 가 부른다(직접 부르지 않는다).
# 원장은 언제나 LEDGER_ROOT 의 것이다: `bd -C "$LEDGER_ROOT"` — 루트에 .beads/redirect 가 있으면
# bd 가 그것을 따라간다(워크트리와 같은 배선).
#
# 여기서 직접 처리하는 것은 셋이다:
#   init          `bd init --prefix <p>`. 그 뒤 원격 배선은 setup 스킬 1.6 의 몫이다 — 원격 반영이라
#                 이 스크립트가 대신 하지 않는다.
#   wire-worktree <워크트리>/.beads/redirect 에 <루트>/.beads 절대 경로를 쓴다 (멱등). 이것이 없으면
#                 워크트리의 bare bd 가 "bd init 으로 새 DB 를 만들라" 고 권하고, 따르면 원장이
#                 이원화된다. 부르는 자리는 hooks/enter-worktree.sh 이고, lib/harness-root.sh 가 이
#                 파일을 둘째 출처로 읽는다. **redirect 를 아는 파일은 이것 하나다.**
#   sync-check    원장(Dolt)이 원격과 어긋난 채 남는 것을 막는다 — checks/ledger-check.sh 가 부른다.
#                 `--push` 가 있을 때만 앞선 커밋을 `bd dolt push` 로 반영한다(기본값은 반영하지
#                 않는 것 — 스위치를 빠뜨린 호출이 승인 밖의 원격 반영이 되면 안 된다. 근거는
#                 harness-x0i.2.1). 판정·문구는 종전 checks/ledger-check.sh 의 것 그대로다.
set -u
: "${LEDGER_ROOT:?ledger.sh 를 통해 불러라}"

# ── sync-check ────────────────────────────────────────────────────────
# ① 원장이 원격보다 앞서 있다 — 로컬 유일본이 된다. 이 머신이 죽으면 이슈·판정 근거가 사라진다.
#    쓰기 모드(--push)면 막지 않고 `bd dolt push` 로 함께 반영한다: git push 는 그 자체가 사용자
#    명시 지시를 요구하는 동작이라 그 순간은 이미 승인된 순간이고, 거기 묶인 원장 반영은 같은
#    승인의 범위 안이다. 자동 반영이 **해소하지 못하면** 그때는 막는다.
# 극성: 원장 위치는 **bd 자신에게** 묻는다(`bd where` 의 database 줄) — LEDGER_ROOT 아래 경로를
# 손으로 조립하면 redirect 로 배선된 루트(워크트리·사본 루트)에서 원장을 놓치고 **건너뜀으로
# 통과**한다(harness-js9). ahead 여부는 dolt 의 추적 참조에서 파생한다.
# fail-open 경계: dolt 미설치·임베디드 원장 부재·원격 미설정은 **통과시키되 크게 경고**한다.
# 원장이 **있는데** 앞서 있으면 그것은 미가용이 아니라 실패다 — 막는다.
# 통과 문구는 **실제로 판정한 것만** 말한다. 건너뛴 검사를 "확인됨"으로 적으면 게이트가 꺼진
# 상태와 통과한 상태가 같은 문장으로 보인다.
sync_check() {
  local push="" fail=0 verdict="" dolt_root dbdir n count
  while [ $# -gt 0 ]; do
    case "$1" in
      --push) push=1; shift ;;
      *) echo "ledger-beads sync-check: 모르는 인자 '$1' (사용: sync-check [--push])" >&2; exit 1 ;;
    esac
  done
  warn() { echo "⚠ 원장 게이트: $*" >&2; }
  bad()  { echo "✗ $*"; fail=1; }

  dolt_root="$(bd -C "$LEDGER_ROOT" where 2>/dev/null | sed -n 's/^[[:space:]]*database:[[:space:]]*//p' | head -1)"
  if ! command -v dolt >/dev/null 2>&1; then
    warn "dolt 미설치 — 원장 반영 여부를 판정할 수 없다. 미반영 원장이 그대로 남을 수 있다"
    verdict="skip"
  elif [ -z "$dolt_root" ] || [ ! -d "$dolt_root" ]; then
    warn "임베디드 원장 없음(bd where 가 로컬 DB 경로를 내지 않았다; ROOT=$LEDGER_ROOT) — 서버 모드이거나 원장을 갖지 않는 레포로 본다"
    verdict="skip"
  else
    # DB 디렉토리는 이름을 박지 않고 실제 집합에서 파생한다 — 레포마다 DB 이름이 다르다.
    # 배열·mapfile 을 쓰지 않는다: 기준선은 macOS 기본 bash 3.2 다.
    n=$(find "$dolt_root" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | wc -l | tr -d '[:space:]')
    if [ "$n" -ne 1 ]; then
      warn "$dolt_root 아래 DB 디렉토리가 ${n}개다(1개를 기대) — 판정을 건너뛴다"
      verdict="skip"
    else
      dbdir=$(find "$dolt_root" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort | head -1)
      if ! (cd "$dbdir" && dolt remote -v 2>/dev/null) | grep -q .; then
        warn "원장에 Dolt 원격이 없다 — 이 원장은 이 머신에만 존재한다"
        verdict="skip"
      elif ! (cd "$dbdir" && dolt branch -a 2>/dev/null) | grep -q 'remotes/origin/main'; then
        bad "원장이 원격에 한 번도 반영된 적이 없다 (remotes/origin/main 없음)"
        verdict="fail"
      elif ! (cd "$dbdir" && dolt merge-base main remotes/origin/main) >/dev/null 2>&1; then
        # 계보가 갈라졌는가 — ahead 카운트보다 먼저 본다. 각자 bd init 을 하면 이렇게 된다(실측 PR #5).
        bad "원장 계보가 원격과 갈라졌다 — main 과 remotes/origin/main 의 공통 조상이 없다. bd dolt pull 로 머지되지 않고 자동 반영도 실패한다. 해소는 JSONL 경유 병합이다: bd export → bd bootstrap → bd import (실측 PR #5). 새 클론에서는 bd init 대신 기존 계보를 받아야 이 상태를 만들지 않는다."
        verdict="fail"
      else
        # rc 는 파이프 밖에서 채집한다. 색 코드가 파이프에서도 나오므로 걷어낸다.
        count=$( (cd "$dbdir" && dolt log remotes/origin/main..main --oneline 2>/dev/null) \
                 | sed 's/\x1b\[[0-9;]*m//g' | grep -c '[^[:space:]]' )
        if [ "$count" -gt 0 ]; then
          if [ -z "$push" ]; then
            warn "원장이 원격보다 ${count}개 커밋 앞서 있다 — 쓰기 모드가 아니라 반영하지 않는다. 반영하려면 git push (pre-push 훅이 켠다) 또는 ledger.sh dolt push 를 직접 실행하라"
            verdict="ahead_noop"
          else
            warn "원장이 원격보다 ${count}개 커밋 앞서 있다 — bd dolt push 로 함께 반영한다"
            # **여기가 이 스크립트의 유일한 원격 쓰기 지점이고, 스위치(--push)가 그 앞에 선다.**
            (cd "$LEDGER_ROOT" && bd dolt push) >&2 || warn "bd dolt push 가 비-0 으로 끝났다"
            # 자동 반영을 **시도했다는 사실**로 통과시키지 않는다 — 추적 참조의 상태를 같은 방법으로 다시 센다.
            count=$( (cd "$dbdir" && dolt log remotes/origin/main..main --oneline 2>/dev/null) \
                     | sed 's/\x1b\[[0-9;]*m//g' | grep -c '[^[:space:]]' )
            if [ "$count" -gt 0 ]; then
              bad "원장이 여전히 원격보다 ${count}개 커밋 앞서 있다 — 자동 반영이 해소하지 못했다"
              verdict="fail"
            else
              verdict="pushed"
            fi
          fi
        else
          verdict="ok"
        fi
      fi
    fi
  fi

  # 침묵을 통과로 읽지 않는다 — 검사가 판정에 도달했는지 역방향으로 단언한다.
  [ -n "$verdict" ] || { echo "✗ 내부 오류: 원장 반영 검사가 판정에 도달하지 못했다 (검사가 도중에 죽었다)"; fail=1; }
  if [ "$fail" -ne 0 ]; then
    cat >&2 <<'HINT'

해소 방법:
  · 원장 자동 반영 실패 → ledger.sh dolt push 를 직접 실행해 원인을 본다 (원격 인증·접근 문제일 수 있다)
  · 이번만 넘기려면 → git push --no-verify   (넘긴 사실이 명령에 남는다)
HINT
    exit 1
  fi
  case "$verdict" in
    ok) verdict="확인됨" ;; pushed) verdict="이번에 수행함" ;; skip) verdict="건너뜀" ;;
    ahead_noop) verdict="앞서 있음(반영하지 않음 — 쓰기 모드 아님)" ;; *) verdict="?" ;;
  esac
  printf '✓ 원장 게이트 통과 — 원격 반영 %s\n' "$verdict"
  exit 0
}

case "${1:-}" in
  init)
    shift
    prefix=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --prefix) prefix="${2:-}"; shift 2 ;;
        *) echo "ledger-beads init: 모르는 인자 '$1' (사용: init --prefix <접두사>)" >&2; exit 1 ;;
      esac
    done
    [ -n "$prefix" ] || { echo "ledger-beads init: --prefix <접두사> 가 필요하다" >&2; exit 1; }
    if [ -d "$LEDGER_ROOT/.beads/embeddeddolt" ]; then
      echo "ledger-beads init: $LEDGER_ROOT/.beads/embeddeddolt 가 이미 있다 — 다시 초기화하지 않는다" >&2
      exit 1
    fi
    exec bd -C "$LEDGER_ROOT" init --prefix "$prefix"
    ;;
  has-ui)
    # 사람이 읽는 자기 UI — 갖지 않는다. 원장이 로컬 Dolt DB 라 사람이 읽을 화면이 없고,
    # scripts/board.sh 의 투영이 그 자리를 메운다. 빈 출력이 "없다" 다 (rc 0).
    # bd 로 흘리지 않으려고 여기서 잡는다 — 아래 exec 로 가면 `bd has-ui` 가 되어 rc≠0 이다.
    exit 0
    ;;
  wire-worktree)
    wt="${2:-}"
    [ -n "$wt" ] && [ -d "$wt" ] || { echo "ledger-beads wire-worktree: 실재하는 <워크트리 절대 경로> 가 필요하다 ('${wt}')" >&2; exit 1; }
    mkdir -p "$wt/.beads" && printf '%s\n' "$LEDGER_ROOT/.beads" > "$wt/.beads/redirect" \
      || { echo "ledger-beads wire-worktree: $wt/.beads/redirect 를 쓸 수 없다" >&2; exit 1; }
    echo "$wt/.beads/redirect → $LEDGER_ROOT/.beads"
    exit 0
    ;;
  sync-check)
    shift
    sync_check "$@"
    ;;
  sprint-add)
    # 스프린트 등재 — 이 백엔드의 등록부는 <루트>/sprints.json 이라 키를 하나 더한다.
    # ID 형식 판정과 중복 판정은 ledger.sh 가 이미 했다(세 백엔드 공통 경계) — 여기는 쓰기만 한다.
    # **파일이 없으면 만들지 않는다**: 등록부가 통째로 없는 판을 쓰기가 조용히 메우면, sprints 가
    # 그 부재를 rc≠0 으로 드는 계약(아래 rails|sprints 주석)이 무의미해진다.
    # status 는 active 다. **마감은 이 명령이 하지 않는다** — 이 파일의 status 를 손으로 고치는 것이
    # 이 백엔드의 마감이고, sprints 는 읽기만 한다.
    sid="${2:-}"
    f="$LEDGER_ROOT/sprints.json"
    [ -r "$f" ] && [ -w "$f" ] || { echo "ledger-beads sprint-add: $f 가 없다(또는 쓸 수 없다) — 이 백엔드에서 등록부의 원본이 그 파일이다. 없는 등록부를 등재가 만들지는 않는다(setup 5절이 만든다)" >&2; exit 1; }
    tmp="$(mktemp)" || { echo "ledger-beads sprint-add: 임시 파일을 만들지 못했다" >&2; exit 1; }
    jq --arg s "$sid" '.sprints[$s] = {status: "active"}' "$f" > "$tmp" \
      || { rm -f "$tmp"; echo "ledger-beads sprint-add: $f 를 갱신하지 못했다 (JSON 이 깨졌는가)" >&2; exit 1; }
    mv "$tmp" "$f" || { rm -f "$tmp"; echo "ledger-beads sprint-add: $f 를 바꿔치지 못했다" >&2; exit 1; }
    echo "✓ 스프린트 등재: $sid (beads: $f 에 status=active)"
    exit 0
    ;;
  rails|sprints)
    # 등록부 질의 — bd 하위 명령이 아니라 이 백엔드가 자기 계층으로 답한다(스토리 skills#105 결정 2).
    # 이 백엔드의 자기 계층은 **원장 루트의 JSON 파일 둘**이다: <루트>/rails.json · sprints.json.
    # bd(Dolt)에는 레일도 스프린트도 없어 대응물이 없고, 그래서 결정 2 가 "파일은 사라지는 것이
    # 아니라 beads 백엔드의 구현 세부가 된다" 로 정했다. 파일의 계약은 그 파일 자신의 doc 키가 든다.
    #
    # **파일이 없으면 rc≠0 이다.** 빈 배열 rc 0 으로 삼키면 "등재가 하나도 없다" 와 구별되지 않고,
    # 소비자(board-check)는 원장의 rail:·sprint: 라벨을 전부 미등재로 읽는다 — 등록부가 통째로
    # 사라진 판이 정상 상태와 같은 문면이 된다.
    #
    # 계약을 깨는 값도 흘리지 않는다. owner 없는 레일(레일 담당자는 1명이 원본이다)과 active·closed
    # 밖의 status(sprints.json 의 doc 이 그 둘뿐이라고 못박는다)는 jq 의 error() 로 죽인다 —
    # `{id, owner:null}` 이나 낯선 status 를 그대로 내면 소비자가 그것을 등재로 읽는다.
    sub="$1"; shift
    for a in "$@"; do
      [ "$a" = --json ] || { echo "ledger-beads $sub: 모르는 인자 '$a' (사용: $sub --json)" >&2; exit 1; }
    done
    f="$LEDGER_ROOT/$sub.json"
    [ -r "$f" ] || { echo "ledger-beads $sub: $f 가 없다(또는 읽을 수 없다) — 이 백엔드에서 등록부의 원본이 그 파일이다. 빈 배열로 답하면 '등재가 없다' 와 구별되지 않는다" >&2; exit 1; }
    case "$sub" in
      rails)
        q='[(.rails // error("최상위 rails 키가 없다")) | to_entries[]
            | {id: .key, owner: (.value.owner // error("레일 \(.key) 에 owner 가 없다 — 레일은 사람이고 담당자 1명이 등록부의 계약이다"))}]' ;;
      sprints)
        q='[(.sprints // error("최상위 sprints 키가 없다")) | to_entries[]
            | {id: .key, status: (.value.status as $s
                | if $s == "active" or $s == "closed" then $s
                  else error("스프린트 \(.key) 의 status 가 \($s | tojson) 다 — active|closed 둘뿐이다") end)}]' ;;
    esac
    # jq 의 실패 문면을 그대로 물어 나른다 — 어느 키가 왜 문제인지는 jq 가 이미 이름으로 든다.
    # 성공하면 stderr 가 비므로 2>&1 로 합쳐 받아도 출력이 섞이지 않는다.
    out=$(jq "$q" "$f" 2>&1) || { echo "ledger-beads $sub: $f 를 읽지 못했다 — $(printf '%s' "$out" | sed 's/^jq: //' | head -1)" >&2; exit 1; }
    printf '%s\n' "$out"
    exit 0
    ;;
esac

# ── JSON 읽기 경로만 jq 한 겹 ─────────────────────────────────────────
# 어댑터의 계약은 "백엔드가 무엇이든 같은 JSON 키" 다. 이 백엔드에는 "항목을 잡은 세션" 이
# assignee 하나뿐이지만, 키가 셋 중 둘에만 있으면 소비자가 `// .assignee` 폴백을 잊는 순간
# beads 에서 **조용히** 어긋난다. 그래서 값이 같더라도 키를 싣는다 (harness-kw0l.3.1).
# 값은 assignee 그대로다 — 대응표는 ledger-github.sh 머리 주석이 든다. bd 는 비어 있는 필드를
# 아예 빼므로 assignee 가 없는 항목도 있다: 그때 actor 는 null 이다(키는 그래도 싣는다 — 계약이
# 요구하는 것은 "키가 늘 있다" 이고, 없는 키를 조건부로 빼면 소비자가 다시 폴백을 알아야 한다).
# 이미 actor 가 실린 항목은 **덮지 않는다** — bd 는 지금 그 키를 내지 않지만, 덮는 판을 쓰면
# 값이 있는 actor 를 assignee 로 지우게 된다(guardrail-check S7 사거리 ⑤ 가 그 판을 잡는다).
# 쓰기·비-JSON 출력은 아래 exec 그대로다: jq 를 태우는 것은 `--json` 이 붙은 호출뿐이다.
# 대가(실측 2026-09-06, 하네스 원장 1089건 · 출력 8.4 MB, 이 스크립트를 5회 돌린 평균):
#   최악(`list --all --json -n 0`)  445 ms → 629 ms (+184 ms, +41%)
#   정지 가드 경로(`list --status in_progress --json`)  357 ms → 353 ms (차이가 잡히지 않는다)
#   그중 대부분은 jq 의 파싱·직렬화 자체다 — `jq .` 만 태워도 618 ms 이고 actor 를 더하는 map 이
#   32 ms 다. 전수 스캔은 세션당 몇 번뿐(board·rules-check)이라 감당한다.
# 파이프로 잇는 이유: `out="$(bd …)"` 로 받아 두면 8.4 MB 의 명령 치환·printf 왕복만으로
# 1009 ms 가 된다(같은 방법으로 실측) — 파이프의 두 배 가까이다. bd 의 rc 는 pipefail 로 산다.
# bd 는 실패해도 stdout 에 온전한 JSON 을 내므로 jq 의 파싱 오류가 stderr 에 겹치지 않는다 —
# `show <없는 id> --json` 실측(2026-09-06, 이 어댑터 경유): rc=1, stdout 은 빈 배열이 아니라
# `{"error":…,"schema_version":1}` 객체 하나이고, stderr 는 네 줄(beads.role 미설정 경고 세 줄 +
# bd 의 오류 한 줄)이다. 유효 JSON 이라 jq 가 파싱에 죽지 않는다는 결론은 그대로다.
#
# jq 를 태울 호출의 판별은 **읽기 하위 명령 한정**과 **argv 원소 완전 일치** 둘 다다 — 한쪽만으로는
# 새는 형태가 남는다:
#  · 문자열 훑기(`case " $* " in *" --json "*`)는 인자 **값** 안의 토큰까지 잡는다. develop 의
#    "원장에 본문을 넘기는 형태" 는 본문을 `--acceptance "$(cat …)"` 로 인자에 실으라고 정하고,
#    실측(2026-09-06) 하네스 원장 1089건 중 **31건**이 title·acceptance·description 에 ` --json `
#    을 갖고 있다. 그런 note·close 는 **쓰기가 이미 일어난 뒤** 출력이 jq 파싱 오류로 죽어 rc 가
#    5 가 되고(jq 실측) stdout 이 사라진다 — `create --silent` 의 id 를 잃은 채 실패하니 재시도가
#    중복 생성이 된다.
#  · 완전 일치만으로는 `note <id> --json` 같은 쓰기 호출이 남고, `history --json`(커밋 레코드 배열)·
#    `graph --json`(객체)처럼 이슈가 아닌 출력에 actor 를 심게 된다.
# 두 형태 모두 checks/ledger-adapter-check.sh ③ 이 단언으로 든다.
case "${1:-}" in
  show|list|ready|blocked|children|search|query)
    for a in "$@"; do
      [ "$a" = --json ] || continue
      set -o pipefail
      bd -C "$LEDGER_ROOT" "$@" | jq 'if type == "array" then map(if has("actor") then . else .actor = .assignee end) else . end'
      exit $?
    done
    ;;
esac

exec bd -C "$LEDGER_ROOT" "$@"
