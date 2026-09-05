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
  local push="" fail=0 verdict="" db dolt_root dbdir n count
  while [ $# -gt 0 ]; do
    case "$1" in
      --push) push=1; shift ;;
      *) echo "ledger-beads sync-check: 모르는 인자 '$1' (사용: sync-check [--push])" >&2; exit 1 ;;
    esac
  done
  warn() { echo "⚠ 원장 게이트: $*" >&2; }
  bad()  { echo "✗ $*"; fail=1; }

  db="$(bd -C "$LEDGER_ROOT" where 2>/dev/null | sed -n 's/^[[:space:]]*database:[[:space:]]*//p' | head -1)"
  if ! command -v dolt >/dev/null 2>&1; then
    warn "dolt 미설치 — 원장 반영 여부를 판정할 수 없다. 미반영 원장이 그대로 남을 수 있다"
    verdict="skip"
  elif dolt_root="$db"; [ -z "$dolt_root" ] || [ ! -d "$dolt_root" ]; then
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
esac

exec bd -C "$LEDGER_ROOT" "$@"
