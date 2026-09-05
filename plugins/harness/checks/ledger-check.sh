#!/bin/bash
# 게이트: 원장(beads/Dolt)의 상태가 원격·git 과 어긋난 채로 push 되는 것을 막는다.
#
# 하나를 본다. "조용한 실패"라 사람이 알아챌 계기가 없다:
#   ① 원장이 원격보다 앞서 있다 — 로컬 유일본이 된다. 이 머신이 죽으면 이슈·판정 근거가 사라진다.
#      **이 경우 막지 않고 `bd dolt push` 로 함께 반영한다.** git push 는 그 자체가 사용자
#      명시 지시를 요구하는 동작이라, 그 순간은 이미 승인된 순간이다 — 거기 묶인 원장 반영은
#      "승인 없는 원격 반영"이 아니라 같은 승인의 범위 안이다. 막기만 하면 사람이 손으로 같은
#      명령을 치게 되고, 안 치는 쪽과 `--no-verify` 로 뚫는 쪽이 남는다. 조용한 소실을 막으려던
#      게이트가 소실 경로를 하나 더 만든다. 자동 반영이 **해소하지 못하면** 그때는 막는다.
#
# 종전에는 감사 로그 사이드카(.beads/ 아래 JSONL)의 미커밋도 함께 봤다. 2026-08-29 에
# 걷어냈다 — 그 이력은 Dolt events 테이블에 있고(실측: events 2916행), 사이드카는 upstream
# 이 audit.enabled 로 끄는 방향으로 갔다(PR #4688 · 이슈 #5905 · #5906). 파일 자체가 이제
# git 추적 대상이 아니라 이 검사는 언제나 건너뛰게 되어 있었고, 그 침묵이 통과로 읽혔다.
# 근거 전문은 스토리 harness-x0i 와 harness-bjj 의
# "2026-08-29 뒤집힘" 절이다.
#
# 극성: 판정을 손으로 나열한 조건에서 하지 않는다. 원장 위치는 .beads/embeddeddolt 아래
# 실제 디렉토리에서 파생하고, ahead 여부는 dolt 의 추적 참조에서 파생한다.
#
# **쓰기 모드: LEDGER_CHECK_PUSH=1. 기본값은 반영하지 않는 것이다.** 이 스크립트에는
# 원격 쓰기 지점이 하나 있고(아래 ①), 그것을 **부르는 자리가 명시적으로 켤 때만** 실행된다.
# 켜는 자리는 `pre-push` 훅 블록 하나뿐이며 그 자리가 CLAUDE.md 예외 하나가 미리 승인한
# 자리다 — 손으로 치는 `git push` 가 곧 그 승인이다.
#
# **극성이 이 방향인 이유**: 스위치를 빠뜨린 호출이 승인 밖의 원격 반영이 되면 안 된다.
# 안전한 쪽이 기본값이어야 한다는 것은 이 레포가 게이트에 요구하는 극성 반전
# (.claude/rules/agile.md)과 같은 요구다. 빠뜨림을 규율로 막으면 규율이 지켜지지 않는
# 순간이 곧 원격 반영이고, 구조로 막으면 그 순간이 없다. 근거는 harness-x0i.2.1.
#
# 켜지 않고 돌렸는데 원장이 앞서 있으면 통과 문구가
# **"원격 반영 앞서 있음(반영하지 않음 — 쓰기 모드 아님)"** 이 된다 — `확인됨`(원래 앞서
# 있지 않았다)과 글자로 갈린다. 침묵시키는 것이 아니라 말만 하는 모드다.
# 인자가 아니라 환경 변수인 이유: $1 은 이미 ROOT 이고, 자기 검사(guardrail-check S6)가
# 동작을 환경 변수로 갈아끼우는 관례를 이미 쓴다(BD_STUB_MISS·BD_PUSH_FAIL).
#
# fail-open 경계: dolt 미설치·임베디드 원장 부재·원격 미설정은 **통과시키되 크게 경고**한다.
# 원장 없는 클론이나 서버 모드 설치본에서 무관한 push 까지 막으면 게이트가 통째로 꺼진다
# (기존 pre-commit 하네스 블록의 bd 분기와 같은 규율). 반대로 원장이 **있는데** 앞서 있으면
# 그것은 미가용이 아니라 실패다 — 막는다.
#
# set -e 를 쓰지 않는다 — 첫 실패에서 죽으면 나머지 사유가 보고되지 않는다.
set -uo pipefail

# 인자로 하네스 루트를 받는다. 생략하면 lib/harness-root.sh 가 내는 하네스 루트다(운영 경로 —
# 못 찾으면 rc=1 로 멈춘다). 인자를 받는 이유는 자기 검사(checks/guardrail-check.sh)가 합성
# 픽스처를 물려 실패 경로와 fail-open 경로를 실제로 밟아 보기 위함이다.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ROOT="${1:-$(bash "$PLUGIN_ROOT/lib/harness-root.sh")}" || exit 1

fail=0
# 검사가 **판정에 도달했는지**를 따로 추적한다. 검사 본문이 도중에 죽어도(없는 명령,
# unbound 변수) 셸은 함수만 중단하고 스크립트는 계속 가므로, fail 이 0 인 것만 보면
# "검사했는데 통과"와 "검사가 죽었다"가 구분되지 않는다 — 침묵이 통과로 읽힌다.
# (실측 2026-08-22: mapfile 이 macOS bash 3.2 에 없어 원장 반영 검사가 통째로 죽었는데도
#  스크립트는 나머지 사유만 보고해 rc=0 거짓 통과였다.)
SYNC_VERDICT=""

# 원장 위치는 **bd 자신에게** 묻는다. `$ROOT/.beads/embeddeddolt` 만 보면 격리 작업
# 공간에서 원장을 놓친다(harness-js9) — 자세한 근거는 check_ledger_sync 안의 주석이다.
#   database: = 임베디드 DB 경로 → 원격 반영 판정의 대상.
# 없을 수 있다(원장 없는 레포). 그 경우는 fail-open 으로 다룬다.
BD_WHERE=$( (cd "$ROOT" && bd where) 2>/dev/null )
LEDGER_DB=$(printf '%s\n' "$BD_WHERE" | sed -n 's/^[[:space:]]*database:[[:space:]]*//p')
warn() { echo "⚠ 원장 게이트: $*" >&2; }
bad()  { echo "✗ $*"; fail=1; }

# --- ① 원장이 원격에 반영됐는가 -------------------------------------------------
check_ledger_sync() {
  local dolt_root dbdir count

  command -v dolt >/dev/null 2>&1 || {
    warn "dolt 미설치 — 원장 반영 여부를 판정할 수 없다. 미반영 원장이 그대로 남을 수 있다"
    SYNC_VERDICT="skip"; return 0
  }

  # 원장 위치는 **bd 자신에게 묻는다.** `$ROOT/.beads/embeddeddolt` 만 보면 격리 작업
  # 공간에서 원장을 놓친다 — 워크트리에는 embeddeddolt 가 없고(gitignore) 원장은 상위
  # 체크아웃에 있는데, bd 는 상위로 올라가 그것을 정상적으로 읽고 쓴다. 그러면 이 게이트만
  # "원장 없음 → 건너뜀"으로 통과시켜 자동 반영이 실행되지 않고, 문서는 원격에 올라갔는데
  # 원장은 로컬에만 남는다. 침묵이 통과로 읽히는 형태다 (실측 2026-08-22, harness-js9).
  #
  # 무조건 상위로 올라가지 않는 이유: 무관한 상위 레포의 원장을 잡을 수 있다. 판정 규칙이
  # bd 와 갈리면 **게이트가 보는 원장과 bd 가 쓰는 원장이 달라진다** — 그때 이 검사는
  # 자기가 무엇을 판정했는지 모르는 채로 통과한다. bd 에게 물으면 규칙이 하나로 남는다.
  # `bd where` 는 원장이 정말 없으면 rc=1 로 끝나므로 fail-open 경계도 그대로 선다.
  dolt_root="$LEDGER_DB"
  [[ -n "$dolt_root" && -d "$dolt_root" ]] || {
    warn "임베디드 원장 없음(bd where 가 로컬 DB 경로를 내지 않았다; ROOT=$ROOT) — 서버 모드이거나 원장을 갖지 않는 레포로 본다"
    SYNC_VERDICT="skip"; return 0
  }

  # DB 디렉토리는 이름을 박지 않고 실제 집합에서 파생한다 — 레포마다 DB 이름이 다르다.
  # 배열·mapfile 을 쓰지 않는다: 이 레포의 기준선은 macOS 기본 bash 3.2 다.
  local n
  n=$(find "$dolt_root" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | wc -l | tr -d '[:space:]')
  if [ "$n" -ne 1 ]; then
    warn "$dolt_root 아래 DB 디렉토리가 ${n}개다(1개를 기대) — 판정을 건너뛴다"
    SYNC_VERDICT="skip"
    return 0
  fi
  dbdir=$(find "$dolt_root" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort | head -1)

  # 원격이 없으면 올릴 곳이 없다. 정책 위반이 아니라 구성이므로 통과시키되 알린다.
  if ! (cd "$dbdir" && dolt remote -v 2>/dev/null) | grep -q .; then
    warn "원장에 Dolt 원격이 없다 — 이 원장은 이 머신에만 존재한다"
    SYNC_VERDICT="skip"; return 0
  fi

  # 추적 참조가 없다 = 한 번도 반영된 적 없다. 이것은 미가용이 아니라 실패다.
  if ! (cd "$dbdir" && dolt branch -a 2>/dev/null) | grep -q 'remotes/origin/main'; then
    bad "원장이 원격에 한 번도 반영된 적이 없다 (remotes/origin/main 없음)"
    SYNC_VERDICT="fail"; return 0
  fi

  # 계보가 갈라졌는가 — ahead 카운트보다 **먼저** 본다. 갈라진 상태에서는 ahead 가 로컬
  # 이력 전체가 되어 숫자만 보면 "많이 앞섰다" 로 읽히고, 자동 반영이 non-fast-forward 로
  # 실패한 뒤에야 원인이 드러난다. 공통 조상이 없으면 bd dolt pull 로 머지되지 않는다.
  # 각자 bd init 을 하면 이렇게 된다 (실측: PR #5 — 원격 44건·로컬 30건, 이슈 ID 교집합 0).
  if ! (cd "$dbdir" && dolt merge-base main remotes/origin/main) >/dev/null 2>&1; then
    bad "원장 계보가 원격과 갈라졌다 — main 과 remotes/origin/main 의 공통 조상이 없다. bd dolt pull 로 머지되지 않고 자동 반영도 실패한다. 해소는 JSONL 경유 병합이다: bd export → bd bootstrap → bd import (실측 PR #5). 새 클론에서는 bd init 대신 기존 계보를 받아야 이 상태를 만들지 않는다."
    SYNC_VERDICT="fail"; return 0
  fi

  # rc 는 파이프 밖에서 채집한다. 색 코드가 파이프에서도 나오므로 걷어낸다.
  count=$( (cd "$dbdir" && dolt log remotes/origin/main..main --oneline 2>/dev/null) \
           | sed 's/\x1b\[[0-9;]*m//g' | grep -c '[^[:space:]]' )
  if [ "$count" -gt 0 ]; then
    # **여기가 이 스크립트의 유일한 원격 쓰기 지점이고, 스위치가 그 앞에 선다.**
    # 켜는 자리는 하네스 루트의 pre-push 훅 블록 하나다(.beads/hooks/pre-push — 하네스 레포 자신이
    # 배선한다. 플러그인은 어느 레포에도 git 훅을 심지 않는다).
    # 그 밖의 호출 — 판정·대조·문서 확인 — 은 켜지 않으므로 여기서 돌아간다.
    if [ -z "${LEDGER_CHECK_PUSH:-}" ]; then
      warn "원장이 원격보다 ${count}개 커밋 앞서 있다 — 쓰기 모드가 아니라 반영하지 않는다. 반영하려면 git push (pre-push 훅이 켠다) 또는 bd dolt push 를 직접 실행하라"
      SYNC_VERDICT="ahead_noop"; return 0
    fi
    warn "원장이 원격보다 ${count}개 커밋 앞서 있다 — bd dolt push 로 함께 반영한다"
    (cd "$ROOT" && bd dolt push) >&2 || warn "bd dolt push 가 비-0 으로 끝났다"

    # 자동 반영을 **시도했다는 사실**로 통과시키지 않는다. push 의 종료 코드가 아니라
    # 추적 참조의 상태가 근거다 — 같은 방법으로 다시 센다.
    count=$( (cd "$dbdir" && dolt log remotes/origin/main..main --oneline 2>/dev/null) \
             | sed 's/\x1b\[[0-9;]*m//g' | grep -c '[^[:space:]]' )
    if [ "$count" -gt 0 ]; then
      bad "원장이 여전히 원격보다 ${count}개 커밋 앞서 있다 — 자동 반영이 해소하지 못했다"
      SYNC_VERDICT="fail"
    else
      SYNC_VERDICT="pushed"
    fi
  else
    SYNC_VERDICT="ok"
  fi
}

check_ledger_sync

# 침묵을 통과로 읽지 않는다 — 검사가 판정에 도달했는지 역방향으로 단언한다.
[ -n "$SYNC_VERDICT" ]  || { echo "✗ 내부 오류: 원장 반영 검사가 판정에 도달하지 못했다 (검사가 도중에 죽었다)"; fail=1; }

if [[ $fail -ne 0 ]]; then
  cat >&2 <<'HINT'

해소 방법:
  · 원장 자동 반영 실패 → bd dolt push 를 직접 실행해 원인을 본다 (원격 인증·접근 문제일 수 있다)
  · 이번만 넘기려면 → git push --no-verify   (넘긴 사실이 명령에 남는다)
HINT
  exit 1
fi

# 통과 문구는 **실제로 판정한 것만** 말한다. 건너뛴 검사를 "확인됨"으로 적으면
# 게이트가 꺼진 상태와 통과한 상태가 같은 문장으로 보인다.
say() { case "$1" in ok) echo -n "확인됨";; pushed) echo -n "이번에 수행함";; skip) echo -n "건너뜀";; ahead_noop) echo -n "앞서 있음(반영하지 않음 — 쓰기 모드 아님)";; *) echo -n "?";; esac; }
printf '✓ 원장 게이트 통과 — 원격 반영 %s\n' "$(say "$SYNC_VERDICT")"
