#!/usr/bin/env bash
# 원장 어댑터의 경계. 하위 명령·인자·JSON 키는 bd 와 같다 — 스킬·검사·훅은 `bd -C <루트> …` 를
# `ledger.sh …` 로 바꾸는 것으로 끝난다. 백엔드는 `<하네스루트>/ledger.json` 의 `backend` 하나로
# 정하고, 없으면 rc≠0 이다. **폴백 없음** — 파일이 없다고 조용히 beads 로 가면 원장을 잘못 짚은
# 채로 쓰기가 성공한다.
#
# 사용: ledger.sh <하위 명령> [인자…]      ledger.sh --help
#
# 하네스 루트는 HARNESS_ROOT → lib/harness-root.sh 순서로 찾는다. HARNESS_ROOT 가 있으면 bd 를
# 부르지 않는다(검사가 픽스처를 물리는 통로이고, github·notion 백엔드에는 bd 가 없다).
#
# 백엔드 파일은 같은 디렉토리의 ledger-<backend>.sh 이고 아래 환경 변수로 받는다:
#   LEDGER_ROOT   하네스 루트 절대 경로
#   LEDGER_CONFIG ledger.json 절대 경로
#
# 하위 명령 집합의 출처: 플러그인이 실제 부르는 bd 하위 명령 전수(측정 명령과 결과는 원장
# harness-m8gg.4.1 의 note). 모든 백엔드가 받는 것과 beads 에만 있는 것으로 가른다 — beads 전용
# 명령을 github·notion 에 주면 rc≠0 이다(bd 의 dolt·where 같은 것은 다른 백엔드에 대응물이 없다).
set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BACKENDS="beads github notion"

usage() {
  cat <<'EOF'
사용: ledger.sh <하위 명령> [인자…]   (인자 규약은 bd 와 같다)

모든 백엔드 (beads · github · notion):
  init                       백엔드별 원장 초기화 (setup 이 부른다)
  create <제목> [-t <type>] [-l <라벨,…>] [--parent <id>] [--acceptance <문>] [--body-file <f>|-d <문>] [--silent] [-p <n>]
                             --parent 를 받으면 **부모의 sprint:·rail:·repo: 라벨을 물려받는다**(백엔드 무관 —
                             이 파일이 한다). slug: 는 물려받지 않는다: 스토리 고유라 물려주면 문서 경로가 겹친다.
                             -l 로 같은 접두사의 라벨을 명시하면 그쪽이 이기고(그 접두사만 상속을 건너뛴다),
                             부모에 없는 라벨은 그대로 남는다.
                             -t epic 이고 rail:<ID> 가 있으면 **그 레일의 owner 가 assignee 로 들어간다**
                             (출처는 `rails --json`). 그 레일의 첫 epic 이라 owner 를 낼 수 없으면
                             assignee 없이 만들어지되 stderr 한 줄로 그 사실을 말한다
  show <id> [--json]
  list [-l <라벨,…>] [--label-pattern <glob>] [--status <s,…>] [-t <type>] [--parent <id>] [--all] [-n <N>] [--json]
  ready [-l <라벨,…>] [-t <type>] [-n <N>] [--json]
  children <id> [--json]
  note <id> <본문> | --file <f> | --stdin
  close <id>… [--reason <문>|--reason-file <f>] [--force]
  update <id> [--status <s>] [--claim --actor <값>] [-a|--assignee <값>] [--parent <id>] [-t <type>] [--acceptance <문>]
                             --assignee 는 assignee 만 바꾼다(빈 문자열이면 지운다) — 실행자를 넣고 status 를
                             옮기는 --claim 과 다른 경로다
                             (github·notion: --claim 과 같이 주면 rc≠0 · beads: 가드가 없다 — bd 가 두
                              플래그를 다 받고(`bd help update` 실측) 남는 값은 bd 가 정한다, 확인하지 않았다)
                             (github: 그 이슈가 사는 레포에 assign 할 수 없는 login 이면 rc≠0 ·
                              notion: Assignee 가 rich_text 라 값을 검증하지 않는다 — 없는 사람 이름도
                              그대로 들어간다 · beads: 확인하지 않았다)
  dep add <id> <의존 대상 id> | --file - (JSONL {"from","to"})
  label add|remove <id> <라벨>
  wire-worktree <워크트리 절대 경로>   워크트리에 원장을 배선한다 — hooks/enter-worktree.sh 가 부른다
                             (beads: <워크트리>/.beads/redirect · github·notion: 배선할 것이 없다, rc 0)
  has-ui                     이 백엔드가 **사람이 읽는 자기 UI** 를 갖는가 — scripts/board.sh 가 부른다.
                             갖는 백엔드는 그 UI 이름을 stdout 한 줄로 내고, 갖지 않는 백엔드는 아무것도
                             내지 않는다 (둘 다 rc 0 · rc≠0 은 "답하지 못했다" 다). 답이 상수라 백엔드에
                             닿지 않는다 — gh·토큰 없이도 답한다
                             (beads: 없음 — 로컬 Dolt DB 라 사람이 읽는 화면이 board.sh 의 투영뿐이다 ·
                              github: 이슈·Projects 화면 · notion: 데이터베이스 화면)
  sync-check [--push]        원장이 원격과 어긋났는가 — checks/ledger-check.sh 가 부른다
                             (beads: Dolt 원격 대조, --push 면 앞선 커밋 반영 · github·notion: "원격 반영 대상 없음" rc 0)
  rails --json               레일 전체 — 출력 JSON 은 [{id, owner}] 배열. owner 는 레일 담당자
                             (beads: <루트>/rails.json · github: epic 의 rail: 라벨 + 그 epic 의 assignee · notion: Assignee(rich_text))
  sprints --json             스프린트 전체 — 출력 JSON 은 [{id, status}] 배열. status 는 active | closed
                             (beads: <루트>/sprints.json · github: Projects v2 Iteration 필드, id 는 iteration 의 title ·
                              notion: Type 이 sprint 인 페이지, id 는 Name 이고 status 는 Status select)
  sprint-add <YYYY-SNN>      스프린트를 등록부에 세운다 — 등재 **뒤** `sprints --json` 이 그 id 를 낸다.
                             세 백엔드가 같은 인자 하나(스프린트 ID)를 받는다. 출력은 stdout 한 줄
                             ("✓ 스프린트 등재: <ID> …" — 뒤에 백엔드가 무엇에 썼는지가 붙는다).
                             **이미 있는 ID 를 다시 주면 rc≠0** 이고 stderr 가 그 ID 를 든다(덮어쓰지 않는다).
                             **마감(active→closed)은 이 명령이 하지 않는다** — 백엔드의 몫이고 `sprints` 는
                             읽기만 한다 (github: 종료일이 지나면 completedIterations 로 자동 · notion:
                             `update <스프린트 페이지 id> --status closed` · beads: <루트>/sprints.json 의 status)
                             (beads: <루트>/sprints.json 에 키 · github: ITERATION 필드에 iteration 하나
                              (title 이 ID) — 필드가 없으면 rc≠0 이고 `ledger.sh init` 을 가리킨다 ·
                              notion: Type 이 sprint 인 페이지 한 장)
  help | --help

beads 전용 (github · notion 은 rc≠0):
  delete · edit · tag · search · supersede · remember · notes · counts · batch ·
  export · import · bootstrap · root · sql · dolt · where

이 목록은 플러그인의 bd 호출 전수(grep)에서 파생했다. 그 측정에 섞인 하위 명령 아닌 토큰
(- · --actor · --db · --directory · --dolt-auto-commit · --help · --json · --version · bd · call · do · hands · has · role)은 뺐다.
EOF
}

case "${1:-}" in
  --help|-h|help) usage; exit 0 ;;
  "") usage >&2; exit 1 ;;
esac

if [ -n "${HARNESS_ROOT:-}" ]; then
  ROOT="$HARNESS_ROOT"
else
  ROOT="$(bash "$PLUGIN_ROOT/lib/harness-root.sh")" || exit 1
fi

CFG="$ROOT/ledger.json"
[ -f "$CFG" ] || { echo "ledger: $CFG 이 없다 — 하네스 루트에 ledger.json 을 두어라 ({\"backend\": \"beads|github|notion\"})" >&2; exit 1; }
backend="$(jq -r '.backend // empty' "$CFG" 2>/dev/null)"
case " $BACKENDS " in
  *" $backend "*) ;;
  *) echo "ledger: $CFG 의 backend '$backend' 는 허용값($BACKENDS) 밖이다" >&2; exit 1 ;;
esac

run_backend() { LEDGER_ROOT="$ROOT" LEDGER_CONFIG="$CFG" bash "$PLUGIN_ROOT/scripts/ledger-$backend.sh" "$@"; }
ldie() { echo "ledger: $*" >&2; exit 1; }

# ── create 의 상속 (스토리 skills#175 결정 1) ─────────────────────────
# **상속은 어댑터의 것이다** — 백엔드마다 다르게 하지 않는다. beads 는 bd 가 만들 때 부모 라벨을
# 통째로 물려주고 github·notion 은 하나도 물려주지 않아, 코어와 절차가 백엔드마다 다른 규칙을
# 알아야 했다(그 구멍의 값: skills#105 분해에서 하위 23개가 라벨 0개, 이 스토리 등재에서 하위
# 10개에 sprint: 라벨을 손으로 붙였다). 여기 한 자리에 두면 규칙이 하나다.
# 물려받는 것은 **sprint:·rail:·repo: 셋뿐**이다. slug: 는 스토리 고유(문서 디렉토리 이름)라
# 물려주면 하위가 스토리의 문서 경로를 함께 주장한다.
# ponytail: 부모를 읽는 `show` 한 번이 create 마다 는다. --parent 가 있을 때만이고 분해는 세션당
# 몇 번뿐이라 감당한다.
csv_has_prefix() { # <라벨 csv> <접두사(콜론 앞)> — 그 접두사의 라벨이 하나라도 있는가
  local l
  for l in $(printf '%s' "$1" | tr ',' ' '); do
    case "$l" in "$2":*) return 0 ;; esac
  done
  return 1
}
csv_has() { # <라벨 csv> <라벨> — 정확히 같은 라벨이 있는가
  local l
  for l in $(printf '%s' "$1" | tr ',' ' '); do
    [ "$l" = "$2" ] && return 0
  done
  return 1
}

if [ "${1:-}" = create ]; then
  shift
  # 값을 먹는 옵션과 먹지 않는 옵션을 갈라 읽는다 — 목록의 출처는 위 usage 의 create 줄이다.
  # 모르는 옵션은 그대로 흘려보낸다(백엔드가 자기 문면으로 죽는다).
  c_args=(); c_lbl=""; c_parent=""; c_type="task"; c_silent=""; c_title=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -l|--labels|--label) c_lbl="${c_lbl:+$c_lbl,}${2:-}"; shift 2 ;;
      --parent) c_parent="${2:-}"; c_args+=("$1" "${2:-}"); shift 2 ;;
      -t|--type) c_type="${2:-}"; c_args+=("$1" "${2:-}"); shift 2 ;;
      --silent) c_silent=1; c_args+=("$1"); shift ;;
      --acceptance|--body-file|-d|--description|-p|--priority) c_args+=("$1" "${2:-}"); shift 2 ;;
      --stdin|--json) c_args+=("$1"); shift ;;
      -*) c_args+=("$1"); shift ;;
      *) [ -n "$c_title" ] || c_title="$1"; c_args+=("$1"); shift ;;
    esac
  done

  inherited=""; p_labels=""
  if [ -n "$c_parent" ]; then
    p_json="$(run_backend show "$c_parent" --json)" \
      || ldie "create: 부모 '$c_parent' 를 읽지 못했다 — 상속할 라벨의 출처다 (위 stderr 가 사유다)"
    p_labels="$(printf '%s' "$p_json" | jq -r '.[0].labels[]? // empty')" \
      || ldie "create: 부모 '$c_parent' 의 labels 를 읽지 못했다"
    for l in $p_labels; do
      case "$l" in
        sprint:*|rail:*|repo:*)
          # -l 로 그 접두사를 명시했으면 그쪽이 이긴다 — 접두사 단위다. 태스크가 여러 repo: 를
          # 물려받는 스토리에서 `-l repo:<하나>` 로 좁혀 만드는 길이 이것이다.
          csv_has_prefix "$c_lbl" "${l%%:*}" && continue
          csv_has "$inherited" "$l" && continue
          inherited="${inherited:+$inherited,}$l" ;;
      esac
    done
  fi
  [ -n "$inherited" ] && c_lbl="${c_lbl:+$c_lbl,}$inherited"

  # beads 는 **bd 가** 만들 때 부모 라벨을 통째로 물려준다 — 여기서 안 붙여도 따라간다. 계약은
  # "물려받는 것은 세 접두사뿐" 이므로, 만든 뒤 **실제로 붙은 라벨**을 읽어 최종 집합 밖의 것을
  # 떼어 낸다. 그래야 slug: 가 하위로 새지 않고(문서 경로 충돌), `-l` 로 좁힌 접두사도 실제로
  # 좁혀진다. 부모의 라벨 목록이 아니라 **만들어진 것**을 읽는 이유: bd 가 무엇을 물려주는지를
  # 이 코드가 가정하지 않는다 — 하나도 안 물려주면 뗄 것이 0개이고 그대로 지나간다.
  # 다른 두 백엔드는 애초에 물려주지 않으므로 이 읽기도 하지 않는다.
  needs_strip=""
  [ "$backend" = beads ] && [ -n "$c_parent" ] && needs_strip=1

  # ── epic 의 assignee = 그 레일의 owner. 출처는 원장 자신(`rails --json`)이다.
  # 레일 owner 가 epic 의 assignee 에서 파생되게 된 뒤(skills#144) epic 을 만들 때마다 손으로
  # 붙여야 했다 — 이 스토리를 등재할 때도 그랬다.
  owner=""
  if [ "$c_type" = epic ] && csv_has_prefix "$c_lbl" rail; then
    rail=""
    for l in $(printf '%s' "$c_lbl" | tr ',' ' '); do case "$l" in rail:*) rail="${l#rail:}"; break ;; esac; done
    if r_json="$(run_backend rails --json)"; then
      owner="$(printf '%s' "$r_json" | jq -r --arg r "$rail" 'map(select(.id == $r)) | first.owner // empty')"
      [ -n "$owner" ] || echo "ledger: create: 레일 '$rail' 의 owner 를 등록부에서 찾지 못했다 — 그 레일의 첫 epic 이면 정상이다. assignee 없이 만든다 (뒤에 'ledger.sh update <id> --assignee <owner>')" >&2
    else
      echo "ledger: create: 레일 등록부(rails --json)를 읽지 못해 assignee 를 넣지 못한다 — 위 stderr 가 사유다. epic 은 그대로 만든다" >&2
    fi
  fi

  # -l 은 하나로 합쳐 맨 뒤에 붙인다 — 세 백엔드가 다 쉼표 목록을 받는다.
  final=(create ${c_args[@]+"${c_args[@]}"})
  [ -n "$c_lbl" ] && final+=(-l "$c_lbl")
  if [ -z "$owner" ] && [ -z "$needs_strip" ]; then
    # 만든 뒤에 할 일이 없다 — 출력도 rc 도 백엔드의 것 그대로다.
    LEDGER_ROOT="$ROOT" LEDGER_CONFIG="$CFG" exec bash "$PLUGIN_ROOT/scripts/ledger-$backend.sh" "${final[@]}"
  fi
  # 만든 뒤 손댈 것이 있으면 id 가 필요하다. `--silent` 는 세 백엔드가 다 id 한 줄만 내는
  # 유일한 형태라 그것으로 받고, 사람이 읽는 줄은 여기서 다시 낸다.
  [ -n "$c_silent" ] || final+=(--silent)
  new_id="$(run_backend "${final[@]}")" || exit 1
  [ -n "$new_id" ] || ldie "create: 백엔드가 새 id 를 내지 않았다"
  [ -n "$owner" ] && { run_backend update "$new_id" --assignee "$owner" >/dev/null || ldie "create: $new_id 는 만들었지만 assignee 를 '$owner' 로 넣지 못했다 (위 stderr 가 사유다)"; }
  if [ -n "$needs_strip" ]; then
    a_json="$(run_backend show "$new_id" --json)" \
      || ldie "create: $new_id 는 만들었지만 실제로 붙은 라벨을 읽지 못했다 (계약 밖의 상속을 떼어 낼 수 없다)"
    for l in $(printf '%s' "$a_json" | jq -r '.[0].labels[]? // empty'); do
      csv_has "$c_lbl" "$l" && continue
      run_backend label remove "$new_id" "$l" >/dev/null \
        || ldie "create: $new_id 에서 백엔드가 물려준 '$l' 를 떼지 못했다 (상속하는 것은 sprint:·rail:·repo: 셋뿐이다)"
    done
  fi
  if [ -n "$c_silent" ]; then printf '%s\n' "$new_id"; else printf '✓ Created issue: %s — %s\n' "$new_id" "$c_title"; fi
  exit 0
fi

# ── sprint-add 의 경계 (스토리 skills#175 결정 2) ─────────────────────
# 형식 판정과 중복 판정은 여기 한 자리다 — 백엔드는 쓰기만 한다. 중복을 백엔드마다 보면
# "덮어쓰지 않는다" 가 셋 중 하나에서 조용히 빠질 수 있고, 그 판은 등록부가 틀린 채로 통과한다.
# **마감(active→closed)은 이 명령이 하지 않는다.** github 에는 iteration 을 닫는 조작 자체가 없고
# (종료일이 지나면 GitHub 이 completedIterations 로 옮긴다), 그것을 세 백엔드 공통 명령으로
# 흉내 내려면 날짜를 거꾸로 고쳐 써야 한다 — 그 쓰기는 iterations 전체 대체라 되돌리기 비용이 크다.
# 그래서 `sprints` 는 읽기만 하고 마감은 백엔드의 몫으로 둔다(usage 의 sprint-add 줄이 그 셋을 든다).
if [ "${1:-}" = sprint-add ]; then
  [ $# -eq 2 ] || ldie "sprint-add: 인자는 스프린트 ID 하나다 (사용: sprint-add <YYYY-SNN>)"
  case "$2" in
    [0-9][0-9][0-9][0-9]-S[0-9][0-9]) ;;
    *) ldie "sprint-add: 스프린트 ID 형식은 YYYY-SNN 이다: '$2'" ;;
  esac
  cur="$(run_backend sprints --json)" \
    || ldie "sprint-add: 지금 등재를 읽지 못해 중복인지 판정할 수 없다 — 위 stderr 가 사유다 (덮어쓸 위험이 있으므로 쓰지 않는다)"
  if printf '%s' "$cur" | jq -e --arg s "$2" 'any(.[]; .id == $s)' >/dev/null 2>&1; then
    ldie "sprint-add: '$2' 는 이미 등재돼 있다 — 조용히 덮어쓰지 않는다 (지금 등재: $(printf '%s' "$cur" | jq -r 'map(.id) | join(", ")'))"
  fi
fi

LEDGER_ROOT="$ROOT" LEDGER_CONFIG="$CFG" exec bash "$PLUGIN_ROOT/scripts/ledger-$backend.sh" "$@"
