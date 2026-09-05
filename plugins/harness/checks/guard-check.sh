#!/usr/bin/env bash
# guard.sh(PreToolUse 훅) 골격 게이트 — Claude 세션 없이 합성 stdin JSON 으로 검증한다.
#
#   ① 3종 도구 입력(Bash·Write·Agent)에 종료 코드가 나온다
#   ② 얹힌 규칙이 다루지 않는 입력은 차단되지 않는다 — 아직 규칙이 없는 강제 지점의
#      명령도 rc=0. 이후 태스크의 차단이 "규칙 때문"임을 증명하는 기반선이다
#   ③ agent_type 을 읽어 분기할 수 있다 (있는 입력 vs 없는 입력)
#   ④ GUARD_ROOT 가 **CLAUDE_PLUGIN_ROOT, 없으면 스크립트 자신의 위치**로 해석된다 — CWD 도 게이트 루트도 아니다
#   ⑤ jq 가 없어도 훅이 죽지 않는다 — 통과 + 경고
#   ⑥ 깨진 JSON 입력에도 죽지 않는다
#   ⑦ 등록부가 양방향으로 온전하다 — 침묵이 통과로 읽히지 않는다
#      정방향: 등록부 키가 가리키는 함수가 없으면 차단된다
#      역방향: 소스에 정의된 규칙 함수(r_ 접두)가 전부 등재됐고, 모든 RULES+= 가
#              RULES=() 뒤에 있다. 등재를 빠뜨리거나 규칙 블록이 RULES=() 위로 가면
#              차단이 통째로 꺼지는데 rc 는 0 이라 정방향만으로는 보이지 않는다
#   ⑧-값옵션 — 하위 명령 추출이 건너뛰는 값-받는 전역 옵션 목록(git·bd)이 `--help` 파생과
#      갈리지 않았다 (파생 ⊆ 훅 목록). 종전 ⑧ 본체(git worktree 차단)는 r_worktree 와 함께 뺐다
#   ⑨ C3 — 대상 레포 본 체크아웃 쓰기가 차단되고(도구 경로 + 셸 경로), 같은 레포의
#      .claude/worktrees/<스토리ID>/ 아래 쓰기는 통과한다. **상대 경로는 payload 의 cwd 로
#      접어 판정한다** — cwd 가 없으면 종전대로 판정하지 않는다. **막지 못하는 경로도 rc=0 으로
#      박아 둔다** — 한계를 주석에만 두면 조용히 사라진다
#   ⑩ A4 — 서브에이전트의 `bd` 쓰기가 하네스 루트 지정(-C·--directory·--db) 없이는 차단되고,
#      지정하면 통과하며, 오케스트레이터(부모 세션)는 판정 대상이 아니다. 면제(읽기) 목록은
#      훅 소스에서 파생하고, `bd --help` 의 하위 명령 집합에서 면제를 뺀 나머지를 **전수** 시험한다
#   ⑪ A3/C2 — 서브에이전트의 원격 반영(`push` 토큰)과 GitHub 조작(`gh` 의 비-읽기 하위 명령)이
#      차단되고, 읽기(`gh pr view`·`gh pr list` 등)와 오케스트레이터는 통과한다. gh 하위 명령
#      집합은 `gh --help`·`gh pr --help`·`gh issue --help` 에서 파생해 면제를 뺀 나머지를 전수 시험한다.
#      **⑪ 은 `gh` 가 PATH 에 있어야 돈다** — 없으면 파생이 비어 단언이 깨지고 rc=1 이다(조용히
#      통과하지는 않는다). 즉 코드가 아니라 환경 사유로 게이트가 깨질 수 있다는 뜻이다
#   ⑫ A1/A2 — 채점자(agent_type 이 harness:reviewer·harness:evaluator)의 파일 수정(Write·Edit·
#      NotebookEdit)·커밋(`commit` 토큰)·bd 쓰기가 차단되고, 검증용 명령(게이트 재실행·git status·
#      bd 읽기)과 implementer·오케스트레이터는 통과한다. 역할 목록은 `agents/*.md` 에서 파생한다 —
#      agent_type 은 `harness:<이름>` 형식(M0 실측)이고 접두 없는 값은 이 하네스의 역할이 아니다
#   ⑬ A5 — implementer 의 bd 쓰기가 `note` 하나로 좁혀진다. note 와 읽기는 통과하고 나머지
#      쓰기는 `-C` 를 붙여도 차단된다. 허용 목록은 훅 소스에서 파생해 `bd --help` 의 하위 명령
#      집합을 전수 시험하고, **허용 대조군(note 가 실제로 통과하는가)이 이 절의 안전 요건**이다
#      (⑫ 와 같은 판정 지점에 다른 허용 목록이 붙는다 — 겹침은 등재 순서로 메시지를 고른다).
#      전수 시험 위에 **대상 단언**이 하나 더 붙는다 — 정정 보존이 기대는 하위 명령들을
#      이름으로 못박는다. 전수 시험은 개수의 하한만 지키므로 파생이 얇아지면 그 경로만
#      조용히 빠지는데 rc 는 그대로 0 이다 (근거는 docs/guardrails.md 1-2 절)
#   (⑭ A6·⑭-2 R23·⑮ A7·⑰ A8 은 그 규칙들 — r_bd_body·r_core_write·r_bead_leak — 과 함께 뺐다.
#    플러그인 재구조화가 남긴 규칙은 앵커와 무관한 불변식 넷뿐이다. 근거는 훅 머리주석.)
#   ⑯ S16 — 규칙 발화가 **규칙 이름과 함께** 로그에 남고, 통과도 한 줄 남아 "발화 0" 과
#      "훅 미실행" 이 갈린다(후자는 계수 명령 scripts/guard-log.sh 의 rc=1). 회차별 계수가
#      기계값(TSV)이며, 로깅 호출만 뺀 사본에서 그 단언이 무너지는 것으로 귀속한다
#   ⑱ S16-b — 로그 **부재의 원인 둘**이 갈린다: "훅 미실행"(rc=1)과 "로깅 없는 guard.sh 가
#      발화 중"(rc=3). 두 상태를 각각 재현해 문구·rc 로 확인하고, 계수 명령에서 구분
#      로직만 뺀 사본이 가르지 못하는 것으로 귀속한다. 사본이 죽어서 못 가른 것이
#      아님은 정상 대조군(로그가 있을 때 원본과 같은 계수)이 든다
#
# ③④⑦ 은 훅 **사본**에 검사 전용 규칙을 끼워 확인한다. 규칙 없이 필드가 "읽힌다"만
# 주장하면 근거가 없다 — 실제 디스패치까지 돌려 rc 로 본다.
#
# 사본을 쓰는 이유: 배포되는 훅에 소싱 주입 지점(과거의 GUARD_EXTRA_RULES)을 두면
# 규칙을 **더하는** 파일뿐 아니라 **빼는** 파일도 똑같이 소싱된다. `RULES=()` 와
# `deny() { return 0; }` 를 담은 파일 하나를 주면 git push 차단 규칙이 있어도 rc=0,
# 출력 없음이 되는 것을 실측했다. 사본 방식은 배포물에 그 구멍을 남기지 않는다.
#
# 한계(스파이크와 동일): 이 게이트는 **훅 스크립트의 로직**만 본다. "Claude Code 가
# 이 훅을 실제로 발화시키는가"(hooks.json 배선·이벤트명)는 검증하지 못한다 — 배선은
# checks/guardrail-check.sh S2 가 본다.
#
# 대상은 이 플러그인 트리 자신이다. 하네스 루트는 필요 없다 — 훅은 합성 JSON 만 먹고 원장을 읽지
# 않는다(lib/harness-root.sh 를 부르는 것은 r_bd_root 의 차단 메시지뿐이고 ⑩ 이 HARNESS_ROOT 로 물린다).
set -uo pipefail
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || { echo "✗ 플러그인 루트로 이동하지 못했다: $ROOT" >&2; exit 1; }
# 훅 사본을 다른 앵커에 두고 GUARD_ROOT 를 재는 절(③④)이 있다 — 세션이 이 변수를 내보낸 채 돌리면
# 사본이 전부 그 값을 앵커로 읽어 ④ 가 거짓 실패한다. 아래에서는 명시적으로 넘길 때만 쓴다.
unset CLAUDE_PLUGIN_ROOT

HOOK="$ROOT/hooks/guard.sh"
# 심볼릭 링크를 미리 푼다 — 훅의 GUARD_ROOT 는 `cd && pwd` 로 실경로를 내므로
# macOS 의 /var → /private/var 차이가 ④ 를 거짓 실패로 만든다.
TMP=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$TMP"' EXIT

# 발화 로그를 임시 경로로 돌린다. 이 게이트는 훅을 수백 번 먹이므로 기본 경로
# (~/.claude/harness-guard-log.tsv — guard.sh 의 GUARD_LOG 기본값)에 그대로 쓰면 실사용 계수가 합성 입력으로
# 오염된다. runh 의 `env "$@"` 는 환경을 상속하므로 export 하나로 전 호출에 걸린다.
export HARNESS_GUARD_LOG="$TMP/guard-log.tsv"
# 세션→actor 매핑도 같은 이유로 돌린다 — 훅이 $HOME 아래에 쓰는 둘째 상태 파일이고,
# 정지 가드가 그것을 읽어 사거리를 정한다. 이 요구는 손목록이 아니라
# checks/guard-check.sh 가 훅 소스에서 판 집합이 낸다.
export HARNESS_SESSION_ACTOR_LOG="$TMP/session-actor.tsv"


fail=0
step() {
  local label="$1"; shift
  if "$@"; then echo "  ✓ ${label}"; else echo "  ✗ FAILED: ${label}"; fail=1; fi
}
differs()   { [ "$1" != "$2" ]; }
has_text()  { case "$2" in *"$1"*) return 0;; *) return 1;; esac; }
lacks_text(){ ! has_text "$1" "$2"; }
# `! cmp -s` 하나로는 "다르다"가 되지 않는다 — 한쪽이 없거나 비면 cmp 가 rc=2 로 죽고
# 그 비-0 이 "다르다"로 읽혀, 사본을 못 만든 A/B·부정 대조군이 조용히 ✓ 로 통과한다
# (harness-erf). 실재·비어있지 않음을 먼저 통과해야 내용 차이를 근거로 쓴다.
not_same()  { [ -s "$1" ] && [ -s "$2" ] && ! cmp -s "$1" "$2"; }

# ── 합성 픽스처 ────────────────────────────────────────────────────────
# 이 게이트는 bd 도 git 도 실행하지 않는다 — 아래 값은 전부 합성 JSON 안의 문자열이라
# 실재할 필요가 없다. 그런데도 리터럴로 적지 않는 이유가 둘 있다.
#   ① 이 파일은 플러그인의 일부라 설치되는 모든 머신에서 그대로 돈다. 타 머신의
#      절대경로·특정 프로젝트의 bead id·repo: 라벨을 담으면 이식 경계("플러그인에 프로젝트
#      고유 값을 넣지 않는다")를 깬다.
#   ② 리터럴 경로가 우연히 클론 루트 아래 놓이는 환경에서는 r_main_shell 이 먼저 잡아,
#      guard.sh 의 판정과 무관한 이유로 rc=0 통과 단언이 rc=2 로 뒤집힌다. ②는 픽스처가
#      클론 루트 **밖**임이 보장돼야 사라진다 — 바로 아래에서 단언한다.
FX_ROOT="$TMP/fx-harness"          # 하네스 루트로 읽히는 경로 (bd -C · --db 의 인자)
FX_CLONE="$TMP/fx-clone"           # 대상 클론 루트로 읽히는 경로
FX_STORY="fx-story"                # 스토리 bead id
FX_TASK="fx-story.1.2"             # 태스크 bead id
FX_TASK_OTHER="fx-story.9.9"       # 남의 태스크 (구현자 범위 시험용)
FX_LABEL="repo:fx"                 # repo: 라벨

outside_clone() {  # outside_clone <경로> — 클론 루트 밖이면 0
  case "$1/" in "${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}"/*) return 1;; *) return 0;; esac
}
echo "── ⓪ 픽스처 전제 ──"
step "FX_ROOT 가 클론 루트 밖이다 (안이면 아래 rc=0 통과 단언이 r_main_shell 때문에 뒤집힌다)" outside_clone "$FX_ROOT"
step "FX_CLONE 이 클론 루트 밖이다 (같은 사유)" outside_clone "$FX_CLONE"

# ── 인용 픽스처 — 규칙 토큰이 **실행 위치가 아닌** 자리에 있을 때 통과하는가 ──────
# 실재하는 플러그인 파일을 쓴다 — **실재하지 않는 경로는 검사가 죽어도 통과하는 형태**다.
# 경로 실재만으로는 부족하다 — 그 파일이 토큰을 실제로 담지 않으면 명령 문자열에 판정 재료가
# 없어 픽스처가 공허하게 통과하므로, **낱말이 그 파일에 실제로 있다**까지 여기서 단언한다.
QUOTE_FX=(
  "bd note|agents/implementer.md"
  "bd -C|skills/develop/SKILL.md"
  "gh pr create|skills/develop/SKILL.md"
  "bd close|skills/develop/SKILL.md"
  "bd create|hooks/session-context.md"
  "bd update|skills/develop/SKILL.md"
)
qfx_cmd=()
for e in "${QUOTE_FX[@]}"; do
  qw="${e%%|*}"; qp="${e#*|}"
  step "인용 픽스처의 경로가 실재한다: $qp" test -f "$ROOT/$qp"
  step "그 파일이 낱말 '$qw' 를 실제로 담는다: $qp" grep -qF -- "$qw" "$ROOT/$qp"
  qfx_cmd+=("grep -c '$qw' $qp")
done
step "인용 픽스처가 6개 전부 만들어졌다 (0개면 아래 통과 단언이 공허해진다)" [ "${#qfx_cmd[@]}" -eq 6 ]
FX_Q_BDNOTE="${qfx_cmd[0]}"
FX_Q_BDC="${qfx_cmd[1]}"
FX_Q_GHPR="${qfx_cmd[2]}"
FX_Q_BDCLOSE="${qfx_cmd[3]}"
FX_Q_BDCREATE="${qfx_cmd[4]}"
FX_Q_BDUPDATE="${qfx_cmd[5]}"

# rc 는 파이프 밖에서 채집한다 (docs/development.md "셸 함정").
GUARD_RC=0
GUARD_OUT=""
runh() {  # runh <훅경로> <json> [env...]
  local hook="$1" json="$2"; shift 2
  GUARD_OUT=$(printf '%s' "$json" | env "$@" "$hook" 2>&1); GUARD_RC=$?
}
run() { runh "$HOOK" "$@"; }

# 훅 사본을 <앵커>/hooks/guard.sh 로 만들고 규칙 파일을 RULES=() 바로 뒤에
# 끼운다(플러그인 배치와 같은 형태 — GUARD_ROOT 가 앵커가 된다). 위치가 중요하다 — 디스패처의 `exit 0` 뒤에 붙이면 실행되지 않아 게이트가
# 조용히 통과한다 (골격 커밋에서 실제로 한 번 그렇게 속았다).
HOOK_COPY=""
mkhook() {  # mkhook <앵커디렉토리> <규칙파일>
  local anchor="$1" rules="$2"
  HOOK_COPY="$anchor/hooks/guard.sh"
  mkdir -p "$anchor/hooks"
  awk -v f="$rules" '
    { print }
    /^RULES=\(\)$/ && !ins { while ((getline l < f) > 0) print l; ins = 1 }
  ' "$HOOK" > "$HOOK_COPY"
  chmod +x "$HOOK_COPY"
  # 앵커 줄(`RULES=()`)이 바뀌면 awk 가 조용히 원본을 복사한다 — 그러면 이후 단언이
  # 전부 공허해진다. 삽입이 실제로 일어났음을 먼저 못박는다.
  step "규칙 삽입됨: ${anchor##*/}" not_same "$HOOK" "$HOOK_COPY"
}

j_bash()  { jq -n --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",tool_input:{command:$c}}'; }
j_bash_cwd() { jq -n --arg c "$1" --arg d "$2" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }   # cwd 를 고르는 형태 — 상대 경로 판정
j_bash_nocwd() { jq -n --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }               # cwd 키 없음
j_write_cwd() { jq -n --arg p "$1" --arg d "$2" '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:$d,tool_input:{file_path:$p,content:"hi"}}'; }
j_write() { jq -n --arg p "$1" '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:"/x",tool_input:{file_path:$p,content:"hi"}}'; }
j_agent() { jq -n --arg d "$1" '{hook_event_name:"PreToolUse",tool_name:"Agent",cwd:"/x",tool_input:{description:$d,prompt:"p"}}'; }
j_edit()  { jq -n --arg p "$1" '{hook_event_name:"PreToolUse",tool_name:"Edit",cwd:"/x",tool_input:{file_path:$p,old_string:"a",new_string:"b"}}'; }
j_nb()    { jq -n --arg p "$1" '{hook_event_name:"PreToolUse",tool_name:"NotebookEdit",cwd:"/x",tool_input:{notebook_path:$p,new_source:"x"}}'; }
# 임의의 도구 이름 + file_path. 쓰기 규칙이 **도구 이름 목록에 등재된 것만** 검사하던
# 허용 목록 극성을 뒤집었는지 보려면, 등재되지 않은 이름으로 물어봐야 한다.
j_path_tool() { jq -n --arg t "$1" --arg p "$2" '{hook_event_name:"PreToolUse",tool_name:$t,cwd:"/x",tool_input:{file_path:$p}}'; }
j_sub()   { jq -n --arg c "$1" --arg t "$2" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",agent_id:"aa306a4edf39e7dfe",agent_type:$t,tool_input:{command:$c}}'; }

echo "── ①② 3종 도구 + 위험 명령: 전부 통과해야 한다 (기반선) ──"
declare -a LABELS=() JSONS=()
LABELS+=("Bash: echo ok");                        JSONS+=("$(j_bash 'echo ok')")
LABELS+=("Bash: git push origin master");         JSONS+=("$(j_bash 'git push origin master')")
LABELS+=("Bash: bd note x hi (-C 없음)");          JSONS+=("$(j_bash 'bd note x hi')")
# 본 체크아웃 Write 는 기반선에서 뺐다 — 이제 ⑨(C3)가 막는 대상이라 rc=2 다. 여기 두면
# 게이트를 돌리는 사용자의 $HOME 에 따라 통과/차단이 갈려 단언이 우연에 기댄다.
LABELS+=("Write: 클론 루트 밖 경로");               JSONS+=("$(j_write "/tmp/guard-check-plain.txt")")
LABELS+=("Agent: 서브에이전트 위임");               JSONS+=("$(j_agent 'delegate task')")
# 옛 기반선 줄 `Bash(sub, agent_type=implementer): gh pr create` 는 여기서 뺐다 —
# ⑪(A3/C2)이 막는 대상이라 이제 rc=2 다. 위 92·93행과 달리 **오케스트레이터로 바꿔서
# 남길 수도 없어** 그냥 뺐다면 "서브에이전트 입력의 기반선"이 통째로 사라진다. 그래서
# ⑪ 이 막지 않는 명령으로 자리를 대신 채운다 — 서브에이전트 입력이 규칙 없이는 통과한다는
# 골격 기반선의 주장은 이 줄이 계속 진다. 92·93행이 rc=0 인 이유도 바뀌었다(규칙이 없어서가
# 아니라 agent 필드가 없어 오케스트레이터로 판정되기 때문) — ⑪ 의 오케스트레이터 대조가
# 그 사실을 못박는다.
LABELS+=("Bash(sub, agent_type=harness:implementer): git status"); JSONS+=("$(j_sub 'git status' 'harness:implementer')")

for i in "${!LABELS[@]}"; do
  run "${JSONS[$i]}"
  printf '  rc=%d  %s\n' "$GUARD_RC" "${LABELS[$i]}"
  step "차단 없음: ${LABELS[$i]}" [ "$GUARD_RC" -eq 0 ]
done

echo "── ③④ 훅 사본에 규칙을 끼워 필드 파싱·디스패치·앵커를 실측 ──"
cat > "$TMP/probe.sh" <<'EOF'
# 게이트 전용 검사 규칙 — 배포되는 훅에는 없다.
probe_agent_type() {
  [[ "$AGENT_TYPE" = "harness:implementer" ]] && deny "probe agent_type=$AGENT_TYPE"
  return 0
}
probe_root() {
  [[ "$GUARD_ROOT" = "${GUARD_EXPECT_ROOT:-}" ]] || deny "probe GUARD_ROOT=$GUARD_ROOT"
  return 0
}
RULES+=("Bash:probe_agent_type" "*:probe_root")
EOF
mkhook "$TMP/anchor" "$TMP/probe.sh"
PROBE="$HOOK_COPY"

# ④ 의 기대값은 게이트가 **사본을 놓은 자리**다 — CLAUDE_PLUGIN_ROOT 가 없을 때의 폴백이다.
# 사본을 게이트 밖에 두면 "루트가 무엇인가"와 "BASH_SOURCE 해석이 되는가"가 분리된다.
# 변수가 있으면 그것이 앵커다 — hooks.json 이 주는 값이고, 그 우선순위도 함께 잰다.
step "사본 앵커가 게이트 루트와 다르다 (④ 가 정의상 참이 되지 않는 전제)" \
  differs "$TMP/anchor" "$ROOT"

runh "$PROBE" "$(j_agent 'x')" "GUARD_EXPECT_ROOT=$TMP/anchor"
step "GUARD_ROOT = 사본이 놓인 앵커 → rc=0" [ "$GUARD_RC" -eq 0 ]

runh "$PROBE" "$(j_agent 'x')" "GUARD_EXPECT_ROOT=$ROOT"
echo "  rc=$GUARD_RC  stderr: $GUARD_OUT"
step "GUARD_ROOT ≠ 게이트 루트 → rc=2 (CWD·호출자 트리를 따르지 않는다)" [ "$GUARD_RC" -eq 2 ]

runh "$PROBE" "$(j_agent 'x')" "GUARD_EXPECT_ROOT=/nonexistent"
step "GUARD_ROOT 불일치 → rc=2 (공허한 통과 아님)" [ "$GUARD_RC" -eq 2 ]
runh "$PROBE" "$(j_agent 'x')" "GUARD_EXPECT_ROOT=$TMP/elsewhere" "CLAUDE_PLUGIN_ROOT=$TMP/elsewhere"
step "CLAUDE_PLUGIN_ROOT 가 있으면 그것이 GUARD_ROOT 다 (hooks.json 배선 값이 자기 위치보다 앞선다) → rc=0" [ "$GUARD_RC" -eq 0 ]

# agent_type 있는 입력 → 규칙이 차단 (rc=2). 없는 입력 → 통과 (rc=0).
runh "$PROBE" "$(j_sub 'echo ok' 'harness:implementer')" "GUARD_EXPECT_ROOT=$TMP/anchor"
step "agent_type=implementer → rc=2"      [ "$GUARD_RC" -eq 2 ]
step "차단 사유에 agent_type 값이 실린다" [ "$GUARD_OUT" = "GUARD-DENY: probe agent_type=harness:implementer" ]

runh "$PROBE" "$(j_bash 'echo ok')" "GUARD_EXPECT_ROOT=$TMP/anchor"
step "agent_type 없음 → rc=0 (허용 대조군)" [ "$GUARD_RC" -eq 0 ]

# 사본 없이는 같은 입력이 통과한다 — 차단이 규칙 때문임을 못박는다.
run "$(j_sub 'echo ok' 'harness:implementer')"
step "배포되는 훅은 같은 입력에 rc=0 (사본의 검사 규칙 때문임을 못박는다)" [ "$GUARD_RC" -eq 0 ]

echo "── ⑦ 등록부 키에 함수가 없으면 차단된다 ──"
cat > "$TMP/typo.sh" <<'EOF'
r_push() { has_token 'push' && deny "probe git push"; return 0; }
RULES+=("Bash:r_pusk")
EOF
mkhook "$TMP/typo" "$TMP/typo.sh"
runh "$HOOK_COPY" "$(j_bash 'git push origin master')"
echo "  rc=$GUARD_RC  stderr: $GUARD_OUT"
step "오타 키 Bash:r_pusk → rc=2 (침묵 통과 아님)" [ "$GUARD_RC" -eq 2 ]

# 매처가 이번 호출에 안 맞는 항목의 오타도 잡아야 한다. 디스패치될 때만 검사하면
# Write 규칙의 오타는 Write 호출이 올 때까지 아무도 모른 채 꺼져 있다.
cat > "$TMP/typo2.sh" <<'EOF'
RULES+=("Write:r_nonexistent")
EOF
mkhook "$TMP/typo2" "$TMP/typo2.sh"
runh "$HOOK_COPY" "$(j_bash 'echo ok')"
step "매처 불일치 항목의 오타 키 → rc=2" [ "$GUARD_RC" -eq 2 ]

# 대조군: 키가 실재하면 통과한다 (⑦ 이 "전부 차단"으로 통과하는 것이 아님).
cat > "$TMP/ok.sh" <<'EOF'
r_noop() { return 0; }
RULES+=("Bash:r_noop")
EOF
mkhook "$TMP/okrule" "$TMP/ok.sh"
runh "$HOOK_COPY" "$(j_bash 'git push origin master')"
step "실재 키 Bash:r_noop → rc=0 (대조군)" [ "$GUARD_RC" -eq 0 ]

echo "── ⑦-역 등록부 붕괴: 정의됐는데 등재되지 않은 규칙이 없다 ──"
# 위 정방향(등록부 키 → 함수 존재)은 rc 로 잡히는 형태만 본다. 반대 방향은 rc 로 잡히지
# **않는다** — 규칙 블록이 `RULES=()` 위로 가면 등재가 통째로 지워지고, 남는 것은 빈
# 등록부라 모든 입력이 rc=0 으로 통과한다. 차단이 사라진 훅과 원래부터 규칙이 없는 훅은
# 실행 결과가 구별되지 않으므로, 여기서는 **소스를 읽어** 단언한다.
# .claude/rules/agile.md 의 극성 반전이 요구하는 자리다 — 검사 대상을 손으로 열거하지 않고
# 소스의 함수 집합에서 파생하므로, 새 규칙의 기본값이 "검사됨"이 된다.
registry_intact() {  # registry_intact <훅파일> — 어긋난 항목을 stdout 에 적고 1 을 낸다
  local f="$1" anchor fn ln n=0 bad=0
  anchor=$(grep -n '^RULES=()$' "$f" | head -1 | cut -d: -f1)
  if [ -z "$anchor" ]; then echo "    RULES=() 앵커가 없다"; return 1; fi
  # ① 정의된 규칙 함수가 전부 등재됐는가 (역방향 본체)
  while read -r fn; do
    [ -n "$fn" ] || continue
    n=$((n + 1))
    grep -Eq "^RULES\+=\(.*\"[^\"]*:${fn}\"" "$f" \
      || { echo "    규칙 함수 ${fn} 이 RULES+= 에 등재되지 않았다"; bad=1; }
  done < <(grep -Eo '^r_[A-Za-z0-9_]+\(\)' "$f" | sed 's/()$//')
  # ② 모든 RULES+= 가 RULES=() 뒤에 오는가. 앞에 오면 그 등재는 지워진다.
  while read -r ln; do
    [ -n "$ln" ] || continue
    [ "$ln" -gt "$anchor" ] \
      || { echo "    RULES+= 가 ${ln}행 — 등록부 선언(${anchor}행)보다 앞이라 등재가 지워진다"; bad=1; }
  done < <(grep -n '^RULES+=' "$f" | cut -d: -f1)
  # ③ 등재된 함수 이름이 전부 r_ 접두인가. ① 의 파생이 이 접두에 기대고 있으므로,
  #    접두를 벗어난 규칙이 하나 생기면 ① 이 그것을 못 본 채 조용히 공허해진다.
  while read -r fn; do
    [ -n "$fn" ] || continue
    case "$fn" in r_*) ;; *) echo "    등재된 함수 ${fn} 이 r_ 접두가 아니다 — ①의 파생이 놓친다"; bad=1;; esac
  done < <(grep -Eo '^RULES\+=\(.*' "$f" | grep -Eo '"[^"]*:[^"]*"' | sed 's/.*://; s/"//')
  # ④ 파생된 집합이 비면 ①③ 이 공허하게 통과한다. 배포되는 훅에는 규칙이 최소 1개 있다.
  [ "$n" -ge 1 ] || { echo "    규칙 함수를 하나도 파생하지 못했다 — 단언이 공허하다"; bad=1; }
  return $bad
}
broken() { ! registry_intact "$1" >/dev/null; }   # 음성 대조군용 — 사유는 삼킨다

step "배포되는 훅: 정의된 규칙 함수가 전부 등재됐다" registry_intact "$HOOK"
echo "  등재 현황: RULES+= $(grep -c '^RULES+=' "$HOOK")줄 · 규칙 함수 $(grep -cE '^r_[A-Za-z0-9_]+\(\)' "$HOOK")개"

# 음성 대조군 3종 — 이 단언이 실제로 무언가를 잡는다는 근거. 전부 훅 **사본**을 변조한다.
# (a) 함수는 정의돼 있는데 등재 줄이 없다
grep -v '^RULES+=' "$HOOK" > "$TMP/no-reg.sh"
step "음성: 등재 줄 삭제 → 미등재로 검출" broken "$TMP/no-reg.sh"

# (b) 리뷰어가 사본으로 재현한 붕괴 — 등재가 RULES=() **위로** 간다.
#     이 사본은 실행해도 rc=0(빈 등록부)이라 훅을 돌리는 검사로는 영영 잡히지 않는다.
awk '/^RULES=\(\)$/ && !d { print "RULES+=(\"Bash:r_remote\")"; d=1 }
     !/^RULES\+=\("Bash:r_remote"\)$/ { print }' "$HOOK" > "$TMP/before-anchor.sh"
chmod +x "$TMP/before-anchor.sh"   # 실행 권한이 없으면 아래 rc 가 126 이라 단언이 헛돈다
step "음성: 등재가 RULES=() 위 → 순서 역전으로 검출" broken "$TMP/before-anchor.sh"
runh "$TMP/before-anchor.sh" "$(j_sub 'git push origin x' 'harness:implementer')"
step "음성(b) 는 훅 실행으로는 안 잡힌다 — 차단이 꺼졌는데 rc=0" [ "$GUARD_RC" -eq 0 ]

# (c) 접두 규약 이탈 — ① 의 파생이 놓치는 형태를 ③ 이 잡는다
sed 's/r_remote/no_remote/g' "$HOOK" > "$TMP/no-prefix.sh"
step "음성: 함수 이름이 r_ 접두를 벗어남 → 파생 공허로 검출" broken "$TMP/no-prefix.sh"

# (d) 통과 대조군 — 손대지 않은 사본은 통과해야 한다 ("전부 실패"로 통과하는 것이 아님)
cp "$HOOK" "$TMP/intact.sh"
step "대조군: 손대지 않은 사본 → 통과" registry_intact "$TMP/intact.sh"

echo "── ⑤ jq 없는 환경 ──"
mkdir -p "$TMP/nojq"
for t in cat dirname grep env; do ln -s "$(command -v "$t")" "$TMP/nojq/$t"; done
GUARD_OUT=$(printf '%s' "$(j_bash 'git push')" | PATH="$TMP/nojq" "$HOOK" 2>&1); GUARD_RC=$?
echo "  rc=$GUARD_RC  stderr: $GUARD_OUT"
step "jq 없음 → 죽지 않고 rc=0" [ "$GUARD_RC" -eq 0 ]
step "jq 없음 → 경고를 남긴다"  [ "${GUARD_OUT#*jq}" != "$GUARD_OUT" ]

echo "── ⑥ 깨진 입력 ──"
run 'not json at all'
echo "  rc=$GUARD_RC  stderr: $GUARD_OUT"
step "비-JSON 입력 → rc=0"      [ "$GUARD_RC" -eq 0 ]
run ''
step "빈 입력 → rc=0"           [ "$GUARD_RC" -eq 0 ]
run '[1,2]'
step "비객체 JSON → rc=0 (SKIP)" [ "$GUARD_RC" -eq 0 ]
step "비객체 JSON → 건너뛴다고 밝힌다" has_text 'JSON 객체가 아니다' "$GUARD_OUT"

# ── 내부 오류는 fail-open 이 아니다 (리뷰 #7). Claude Code 는 rc=2 만 차단으로 읽으므로
#    unbound 변수로 rc=1 에 죽는 훅은 그 호출을 통과시킨다. set -u 직후에 unbound 참조를
#    끼운 사본으로 EXIT trap 이 rc=2 로 바꾸는지 보고, trap 줄을 뺀 사본으로 귀속한다.
mkdir -p "$TMP/ub/hooks"
UB_PROBE="$TMP/ub/hooks/guard.sh"
awk '{print} /^set -uo pipefail$/{print ": \"$GUARD_UNBOUND_PROBE\""}' "$HOOK" > "$UB_PROBE"; chmod +x "$UB_PROBE"
step "unbound 사본이 원본과 다르다"    bash -c '[ -s "$1" ] && ! cmp -s "$1" "$2"' _ "$UB_PROBE" "$HOOK"
runh "$UB_PROBE" "$(j_bash 'echo ok')"
echo "  rc=$GUARD_RC  stderr: $GUARD_OUT"
step "내부 오류(unbound) → rc=2"        [ "$GUARD_RC" -eq 2 ]
step "내부 오류 → 미도달을 밝힌다"       has_text '판정에 도달하지 못했다' "$GUARD_OUT"
UB_AB="$TMP/ub/hooks/guard-ab.sh"
grep -vF "trap '[ \"\$GUARD_DONE\" = 1 ]" "$UB_PROBE" > "$UB_AB"; chmod +x "$UB_AB"
step "A/B 사본이 원본과 다르다"          bash -c '[ -s "$1" ] && ! cmp -s "$1" "$2"' _ "$UB_AB" "$UB_PROBE"
runh "$UB_AB" "$(j_bash 'echo ok')"
step "A/B: trap 없으면 rc=2 가 아니다 (귀속)" [ "$GUARD_RC" -ne 2 ]

echo "── ⑧-값옵션 하위 명령 추출의 값-받는 전역 옵션 목록이 낡지 않았다 ──"
# subcmds_after 는 값-받는 전역 옵션의 **값도 함께** 건너뛴다. 목록에서 빠진 옵션이
# 있으면 그 값이 하위 명령으로 읽혀 진짜 하위 명령이 가려진다 — 미탐이다
# (실측 harness-9tf: `bd -C <H> --actor note create "x"` → 하위 명령이 note 로 읽혀 rc=0).
# **say_fail 은 이 절이 처음 쓰는 자리라 여기서 정의한다** — 종전에는 ⑧ 본체가 들었다.
say_fail() { echo "      $*"; }
#
# 훅은 목록을 손으로 든다(모든 도구 호출마다 도는데 `bd --help` 32ms·`git --help` 5ms 라
# 매 호출 파생은 훅 1회 56ms 를 배로 늘린다 — 실측). 대신 **여기서 낡음을 검출한다.**
# 단언은 두 방향이 아니다: **파생 ⊆ 훅 목록**만 실패로 읽는다. 파생에 있는데 훅에 없으면
# 미탐이지만, 훅에 있는데 파생에 없는 것은 과차단 방향이라 구멍을 만들지 않는다
# (다른 git 버전의 옵션을 미리 담아 둘 수 있어야 한다 — 훅의 GIT_VALUE_OPTS 주석).
#
# **파생 집합이 비면 실패로 읽는다.** 빈 집합은 "값-받는 옵션이 없다"가 아니라 "파싱이
# 깨졌다"이고, 그 상태로 통과시키면 이 절 전체가 공허해진다(0건 통과 = 실패, agile.md).
# 로케일을 C 로 고정한다 — git 의 usage 는 번역되고, 번역된 출력에서 앵커를 찾으면
# 파생이 환경에 따라 조용히 빈다 [실측: ko_KR 에서 "사용법:" 으로 나온다].
hook_vopts() {  # hook_vopts <변수명> → 훅 소스의 목록을 낱말마다 한 줄로
  grep -E "^$1=" "$HOOK" | sed "s/^$1=\"//; s/\"$//" | tr ' ' '\n' | grep -v '^$' | sort -u
}
# 파생: git 은 usage 줄의 `[-C <path>]`·`[--git-dir=<path>]`, bd 는 cobra `Flags:` 절의
# `--name TYPE` (이름 뒤 **공백 하나** 다음에 타입 토큰 — 공백이 여럿이면 설명이다).
derive_git_vopts() {
  LC_ALL=C git --help 2>/dev/null | sed -n '1,/<command>/p' \
    | grep -oE '\-\-?[A-Za-z][A-Za-z0-9-]*(\[?=|[[:space:]]+<)' \
    | sed -E 's/(\[?=|[[:space:]]+<)$//' | sort -u
}
derive_bd_vopts() {
  LC_ALL=C bd --help 2>/dev/null | sed -n '/^Flags:/,/^$/p' \
    | sed -nE 's/^[[:space:]]+(-([A-Za-z]), )?(--[A-Za-z0-9-]+) [a-z]+ .*/\2\n\3/p' \
    | sed -E '/^$/d; s/^([A-Za-z])$/-\1/' | sort -u
}
check_vopts() {  # check_vopts <라벨> <훅 변수명> <파생 함수> <최소 개수> <도구>
  local label="$1" var="$2" fn="$3" minn="$4" tool="$5"
  if ! command -v "$tool" >/dev/null 2>&1; then
    say_fail "$tool 이 PATH 에 없어 $label 의 목록 신선도를 판정하지 못했다 — 목록이 낡아도 알 수 없다"
    step "$label: 파생 가능" false
    return
  fi
  local derived hooked missing dn
  derived=$("$fn"); hooked=$(hook_vopts "$var")
  dn=$(printf '%s\n' "$derived" | grep -c . || true)
  step "$label: $tool --help 에서 파생했다 (${minn}개 이상, 실제 ${dn}개)" [ "$dn" -ge "$minn" ]
  step "$label: 훅 목록이 비어 있지 않다" [ -n "$hooked" ]
  missing=$(comm -23 <(printf '%s\n' "$derived") <(printf '%s\n' "$hooked") | tr '\n' ' ' | sed 's/ $//')
  [[ -n "$missing" ]] && say_fail "$var 에 없는 값-받는 옵션: $missing — 그 값이 하위 명령으로 읽혀 진짜 하위 명령이 가려진다(미탐). hooks/guard.sh 의 $var 에 추가하라"
  step "$label: 파생 ⊆ 훅 목록 (빠진 옵션 없음)" [ -z "$missing" ]
  local extra
  extra=$(comm -13 <(printf '%s\n' "$derived") <(printf '%s\n' "$hooked") | tr '\n' ' ' | sed 's/ $//')
  [[ -n "$extra" ]] && echo "  · 훅에만 있는 항목(과차단 방향이라 실패로 읽지 않는다): $extra"
}
check_vopts "git 값옵션" GIT_VALUE_OPTS derive_git_vopts 5 git
check_vopts "bd 값옵션"  BD_VALUE_OPTS  derive_bd_vopts  3 bd

# 미탐이 실제로 닫혔는가 — 이슈가 든 두 형태를 차단으로 못박는다. 위 목록 대조가
# "낡지 않았다"만 말하므로, 그 목록이 판정에 실제로 쓰이는지는 여기서 본다.
declare -a VO_DENY_LABEL=() VO_DENY_JSON=()
VO_DENY_LABEL+=("[implementer] bd -C <H> --actor note create — 값이 하위 명령을 가리던 형태")
VO_DENY_JSON+=("$(j_sub "bd -C $FX_ROOT --actor note create \"x\" -t task" 'harness:implementer')")
VO_DENY_LABEL+=("[reviewer] bd -C <H> --actor list create")
VO_DENY_JSON+=("$(j_sub "bd -C $FX_ROOT --actor list create x" 'harness:reviewer')")
VO_DENY_LABEL+=("[implementer] bd -C <H> --dolt-auto-commit note close")
VO_DENY_JSON+=("$(j_sub "bd -C $FX_ROOT --dolt-auto-commit note close x" 'harness:implementer')")
VO_DENY_LABEL+=("[implementer] git -c core.bare=false push — 값-받는 옵션(-c) 뒤의 push 를 읽는다")
VO_DENY_JSON+=("$(j_sub 'git -c core.bare=false push origin x' 'harness:implementer')")
for i in "${!VO_DENY_LABEL[@]}"; do
  run "${VO_DENY_JSON[$i]}"
  printf '  rc=%d  %s\n' "$GUARD_RC" "${VO_DENY_LABEL[$i]}"
  step "차단: ${VO_DENY_LABEL[$i]}" [ "$GUARD_RC" -eq 2 ]
done
# 과차단 대조군 — 값 건너뛰기가 하위 명령까지 삼키면 정상 경로가 죽는다.
run "$(j_sub "bd -C $FX_ROOT --actor harness note $FX_TASK \"메모\"" 'harness:implementer')"
printf '  rc=%d  [implementer] --actor <값> note (note 는 허용)\n' "$GUARD_RC"
step "통과: --actor 값을 건너뛰어도 note 는 그대로 허용된다" [ "$GUARD_RC" -eq 0 ]

echo "── ⑨ C3: 본 체크아웃 쓰기 차단 (도구 경로 + 셸 경로) ──"
# 클론 루트를 임시 디렉토리로 돌린다. 진짜 ~/.harness-workspace 를 기준으로 삼으면
# 시험 경로가 실재하는 본 체크아웃을 가리키고, 판정이 게이트를 돌리는 사람의 홈 상태에
# 따라 흔들린다. 판정은 합성 JSON 이라 대부분 파일을 만들지 않지만, 아래 한계 2 단언만은
# 실제 심볼릭 링크를 이 임시 트리 안에 만든다 — 트리째 trap 으로 지워진다.
MCROOT="$TMP/clone"
runm() { runh "$HOOK" "$1" "HARNESS_CLONE_ROOT=$MCROOT"; }
# 기본값 경로 — 환경에 HARNESS_CLONE_ROOT 가 있어도 지우고 돌린다.
rund() { runh "$HOOK" "$1" -u HARNESS_CLONE_ROOT; }

# ── 차단: 도구 경로 (Write·Edit·NotebookEdit). 쓰기임이 확정된 층이라 예외가 가장 좁다.
declare -a MC_TD_LABEL=() MC_TD_JSON=()
MC_TD_LABEL+=("Write: 본 체크아웃 직속");                   MC_TD_JSON+=("$(j_write "$MCROOT/repo/main.txt")")
MC_TD_LABEL+=("Write: 본 체크아웃 하위 디렉토리");           MC_TD_JSON+=("$(j_write "$MCROOT/repo/src/a.js")")
MC_TD_LABEL+=("Write: 본 체크아웃의 .claude/settings.json"); MC_TD_JSON+=("$(j_write "$MCROOT/repo/.claude/settings.json")")
MC_TD_LABEL+=("Write: worktrees 직속 (워크트리가 아니다)");  MC_TD_JSON+=("$(j_write "$MCROOT/repo/.claude/worktrees/notes.txt")")
MC_TD_LABEL+=("Write: 워크트리에서 .. 로 탈출");             MC_TD_JSON+=("$(j_write "$MCROOT/repo/.claude/worktrees/story-a/../../../esc.txt")")
MC_TD_LABEL+=("Write: 레포 체크아웃 루트 자체");             MC_TD_JSON+=("$(j_write "$MCROOT/repo")")
MC_TD_LABEL+=("Write: 클론 루트 직속 파일");                 MC_TD_JSON+=("$(j_write "$MCROOT/stray.txt")")
MC_TD_LABEL+=("Write: ~ 표기 (HOME 확장 후 판정)")
# 이 줄만 `;` 로 잇지 않고 나눈다 — 아래 disable 은 **바로 다음 명령**에만 걸리는데,
# 한 줄에 둘을 이으면 뒤엣것이 별개 명령이라 지시어가 닿지 않는다.
# shellcheck disable=SC2088  # 확장되면 안 된다 — 훅에 **리터럴 `~/`** 를 먹여 그쪽의 확장을 시험하는 픽스처다.
MC_TD_JSON+=("$(j_write "~/x/repo/main.txt")")
# 대소문자만 다른 표기 — macOS 기본 FS 는 같은 디렉토리다(리뷰 #8). mc_locate 의 소문자
# 접기를 빼면 이 한 건만 rc=0 이 된다(A/B 귀속은 그 줄 하나라 여기서는 이 항목이 맡는다).
MC_TD_LABEL+=("Write: 대소문자만 다른 표기");                 MC_TD_JSON+=("$(j_write "$(printf '%s' "$MCROOT" | tr '[:lower:]' '[:upper:]')/repo/main.txt")")
MC_TD_LABEL+=("Edit: 본 체크아웃 직속");                     MC_TD_JSON+=("$(j_edit "$MCROOT/repo/main.txt")")
MC_TD_LABEL+=("NotebookEdit: 본 체크아웃 (notebook_path)");  MC_TD_JSON+=("$(j_nb "$MCROOT/repo/nb.ipynb")")
# ── 극성: 도구 **이름 목록에 없는** 쓰기 도구도 검사된다.
# 종전에는 r_main_write 가 Write·Edit·NotebookEdit 세 이름에만 등재돼, 그 밖의 도구는
# 기본값이 "검사 안 됨" 이었다 (실측 2026-08-22: MultiEdit 입력 rc=0). 허용 목록 검사는
# 침묵이 통과로 읽히므로 .claude/rules/agile.md 가 금지한다. 이 두 줄이 그 극성을 못박는다
# — 이름을 늘리는 것이 아니라, 새 이름의 기본값이 "검사됨"인지를 묻는다.
MC_TD_LABEL+=("MultiEdit: 본 체크아웃 (미등재 이름)");       MC_TD_JSON+=("$(j_path_tool MultiEdit "$MCROOT/repo/main.txt")")
MC_TD_LABEL+=("가상의 MCP 쓰기 도구: 본 체크아웃");          MC_TD_JSON+=("$(j_path_tool mcp__fs__write_file "$MCROOT/repo/main.txt")")
for i in "${!MC_TD_LABEL[@]}"; do
  # ~ 표기 항목만 클론 루트를 HOME 아래로 바꿔 돌린다 (확장이 실제로 일어나는지 본다).
  case "${MC_TD_LABEL[$i]}" in
    *"~ 표기"*) runh "$HOOK" "${MC_TD_JSON[$i]}" "HARNESS_CLONE_ROOT=$HOME/x" ;;
    *) runm "${MC_TD_JSON[$i]}" ;;
  esac
  printf '  rc=%d  %s\n' "$GUARD_RC" "${MC_TD_LABEL[$i]}"
  step "차단: ${MC_TD_LABEL[$i]}" [ "$GUARD_RC" -eq 2 ]
done

# ── 통과: 워크트리 안과 클론 루트 밖. 이게 없으면 "전부 막는 규칙"도 위를 통과한다.
declare -a MC_TA_LABEL=() MC_TA_JSON=()
MC_TA_LABEL+=("Write: 워크트리 직속");             MC_TA_JSON+=("$(j_write "$MCROOT/repo/.claude/worktrees/story-a/wt.txt")")
MC_TA_LABEL+=("Write: 워크트리 깊은 경로");         MC_TA_JSON+=("$(j_write "$MCROOT/repo/.claude/worktrees/story-a/checks/x.sh")")
MC_TA_LABEL+=("Write: 워크트리 안에서 .. 로 제자리"); MC_TA_JSON+=("$(j_write "$MCROOT/repo/.claude/worktrees/story-a/checks/../x.sh")")
MC_TA_LABEL+=("Edit: 워크트리");                   MC_TA_JSON+=("$(j_edit "$MCROOT/repo/.claude/worktrees/story-a/f.txt")")
MC_TA_LABEL+=("NotebookEdit: 워크트리");           MC_TA_JSON+=("$(j_nb "$MCROOT/repo/.claude/worktrees/story-a/n.ipynb")")
# "Write: 클론 루트 자체" 는 종전 이 목록(통과해야 하는 것)에 있었다. mc_locate 가
# 루트 자체를 후보로 잡지 못하던 시절의 동작을 정상으로 굳힌 자리였다 — harness-iwj.
# 지금은 차단되며 그 단언은 아래 MC_ROOT_SELF 뒤에 있다. 이 목록의 목적(과차단 검출)은
# 남은 워크트리 5건이 계속 수행한다.
MC_TA_LABEL+=("Write: 클론 루트 밖");               MC_TA_JSON+=("$(j_write "/tmp/guard-check-elsewhere.txt")")
# 읽기는 금지가 아니다. 아래 극성 단언이 "경로를 받으면 전부 검사"로 뒤집었으므로,
# 그 뒤집기가 읽기까지 삼키지 않았는지를 같은 자리에서 본다 — 없으면 과차단이 조용히 산다.
MC_TA_LABEL+=("Read: 본 체크아웃 (읽기는 금지가 아니다)"); MC_TA_JSON+=("$(j_path_tool Read "$MCROOT/repo/main.txt")")
MC_TA_LABEL+=("Grep: 본 체크아웃");                 MC_TA_JSON+=("$(j_path_tool Grep "$MCROOT/repo/main.txt")")
for i in "${!MC_TA_LABEL[@]}"; do
  runm "${MC_TA_JSON[$i]}"
  printf '  rc=%d  %s\n' "$GUARD_RC" "${MC_TA_LABEL[$i]}"
  step "통과: ${MC_TA_LABEL[$i]}" [ "$GUARD_RC" -eq 0 ]
done

# ── 차단: 셸 경로. acceptance ① 이 요구하는 리다이렉션·sed -i 가 여기 있다.
declare -a MC_SH_DENY=(
  "echo hi > $MCROOT/repo/main.txt"
  "printf x >>$MCROOT/repo/main.txt"
  "sed -i '' 's/a/b/' $MCROOT/repo/main.txt"
  "sed -i.bak s/a/b/ \"$MCROOT/repo/main.txt\""
  "printf x | tee $MCROOT/repo/main.txt"
  "cp /tmp/x $MCROOT/repo/main.txt"
  "rm -f $MCROOT/repo/main.txt"
  "cd $MCROOT/repo && echo x > f"
  "mkdir -p $MCROOT/repo/newdir"
  "cat <<'EOF' > $MCROOT/repo/main.txt"
)
for c in "${MC_SH_DENY[@]}"; do
  runm "$(j_bash "$c")"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "차단(셸): $c" [ "$GUARD_RC" -eq 2 ]
done
# 8번째가 상대 경로 우회를 닫는 자리다 — `echo x > f` 자체는 판정할 수 없지만
# 앞의 `cd <본 체크아웃>` 이 걸린다. 9번째(mkdir)는 규칙이 "쓰기 명령 열거"가 아니라
# "경로 존재"임을 보여준다 — mkdir 을 아는 분기는 어디에도 없다.

# ── 읽기 전용 명령만으로 된 명령은 본 체크아웃 경로가 있어도 통과한다 — 조각 전부의 첫 실행
#    낱말이 읽기 명령이거나 git 의 읽기 하위 명령이고, 파일 리다이렉션이 없을 때다.
declare -a MC_SH_READ_PASS=(
  "cat $MCROOT/repo/README.md"
  "git -C $MCROOT/repo status"
  "diff $MCROOT/repo/a $MCROOT/repo/.claude/worktrees/story-a/a"
  "echo '$MCROOT/repo 는 건드리지 않는다'"
  "ls $MCROOT/repo 2>/dev/null | head -3"
  "cd $MCROOT/repo && git log --oneline -3"
  # git 의 읽기 하위 명령. 모든 형태가 읽기인 것만 면제 목록에 있다.
  "git -C $MCROOT/repo grep -n foo"
  "git -C $MCROOT/repo merge-base main HEAD"
  "git -C $MCROOT/repo ls-tree -r HEAD --name-only"
  "git -C $MCROOT/repo rev-list --count HEAD"
  # 변수 대입만 있는 조각은 명령이 아니다 — 대입 접두형과 같은 결론이어야 한다.
  "R=$MCROOT/repo; cat \$R/README.md"
  "R=$MCROOT/repo cat \$R/README.md"
  "R=$MCROOT/repo; git -C \$R log --oneline -1; echo done"
)
for c in "${MC_SH_READ_PASS[@]}"; do
  runm "$(j_bash "$c")"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "통과(읽기 전용 명령만): $c" [ "$GUARD_RC" -eq 0 ]
done
# 읽기 명령에 쓰기 조각이나 파일 리다이렉션이 하나라도 섞이면 종전대로 막힌다.
declare -a MC_SH_READ_MIX=(
  "cat $MCROOT/repo/a > /tmp/b"
  "ls $MCROOT/repo && rm -rf $MCROOT/repo/src"
  "find $MCROOT/repo -name x -delete"
  "git -C $MCROOT/repo checkout -- ."
  # 대입만 있는 조각을 건너뛰어도 **실행하는 조각**은 그대로 판정된다.
  "R=$MCROOT/repo; rm -rf \$R/src"
  "R=$MCROOT/repo; echo x > \$R/f.txt"
  # 읽기 형태가 있어도 쓰기 형태가 있는 git 하위 명령은 면제 목록 밖이다. 목록이 옵션을
  # 보지 않으므로, 등재하면 아래 쓰기가 함께 통과한다 — 그래서 읽기 쪽까지 막는 쪽을 택했다.
  "git -C $MCROOT/repo branch -D tmp"
  "git -C $MCROOT/repo tag -d v1"
  "git -C $MCROOT/repo config user.name x"
  "git -C $MCROOT/repo remote add o u"
)
for c in "${MC_SH_READ_MIX[@]}"; do
  runm "$(j_bash "$c")"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "차단(읽기+쓰기 혼합): $c" [ "$GUARD_RC" -eq 2 ]
done

# ── 의도된 오탐. 진짜 차단과 **다른 배열**로 가른다 (⑧ 의 WT_FALSEPOS 선례).
# 아래는 쓰기 명령의 **인자 텍스트** 안에 경로가 든 형태다 — 판정이 경로의 존재라 막힌다.
declare -a MC_SH_FALSEPOS=(
  # ── 인자로 실린 **텍스트** 안의 경로 (harness-qp1). 위 echo 와 같은 갈래지만 비용이
  # 다르다: 이쪽은 **결함을 기록하는 행위 자체**가 막힌다. harness-483 을 등재하는 동안
  # 3회 났고(bead 생성 · note 1차 · note 2차), **차단 메시지를 인용하면 그 인용이 다시
  # 차단된다.** 기록이 세 번 막히는 동안 본문의 정밀도가 계속 낮아졌다.
  #
  # 판정을 좁히지 않기로 했다 (2026-08-22 사용자 결정, harness-qp1 의 (B)안).
  # harness-2ga 는 워크트리 규칙의 축을 'git 의 하위 명령' 으로 옮겨 같은 종류를 풀었지만
  # **이 규칙의 판정 대상은 하위 명령이 아니라 경로 자체**라 그 해법이 안 된다. 좁히려면
  # 텍스트 옵션의 인용된 값을 후보에서 빼야 하는데, 그것은 셸 인용 파싱이고 harness-uhy.1.1 note ② 가
  # 3연속으로 샌 형태 열거로 돌아가는 길이며 미탐을 들인다(`rm -d "<경로>"`).
  # 대신 **표준 우회가 이미 있다** — 아래 통과 배열이 그것을 못박는다.
  "bd create \"제목\" -d \"경로 $MCROOT/repo 를 설명하는 본문\""
  "gh pr create --body \"$MCROOT/repo 를 다루는 PR\""
  "git commit -m \"fix: $MCROOT/repo 경로 처리\""
)
for c in "${MC_SH_FALSEPOS[@]}"; do
  runm "$(j_bash "$c")"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "의도된 오탐(차단): $c" [ "$GUARD_RC" -eq 2 ]
done

# 표준 우회 — 본문을 **파일로 넘기면** 명령 문자열에 경로가 남지 않아 통과한다.
# 이 세 줄이 위 오탐의 대가를 감당 가능하게 만드는 근거다. 여기가 깨지면 우회가 사라진
# 것이므로 위 오탐 등재도 함께 재검토해야 한다 — 출구 없는 금지가 되기 때문이다
# (agents/reviewer.md 절차 5 "새 제약이 출구를 막지 않는지 본다").
declare -a MC_SH_ESCAPE=(
  'bd create "제목" -d "$(cat /tmp/body.txt)"'
  'gh pr create --body-file /tmp/body.md'
  'git commit -F /tmp/msg.txt'
)
for c in "${MC_SH_ESCAPE[@]}"; do
  runm "$(j_bash "$c")"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "표준 우회(통과): $c" [ "$GUARD_RC" -eq 0 ]
done

# ── 통과: 워크트리 경로와 클론 루트 밖. 3번째가 결정적이다 — 워크트리 목록 조회
# `ls <클론>/.claude/worktrees/` 가 막히면 워크트리를 고르는 일 자체가 막힌다.
declare -a MC_SH_ALLOW=(
  "cd $MCROOT/repo/.claude/worktrees/story-a && git status"
  "echo hi > $MCROOT/repo/.claude/worktrees/story-a/f.txt"
  "ls $MCROOT/repo/.claude/worktrees/"
  "ls $MCROOT/repo/.claude/worktrees"
  # "ls $MCROOT" 는 종전 여기(통과)에 있었다. 클론 루트 **자체**를 후보로 잡지 못하던
  # 시절의 동작이다(harness-iwj). 지금은 막힌다 — 규칙의 극성이 "경로 문자열의 존재"라
  # 읽기와 파괴를 가를 수단이 없고, 레포 경로에 대해서는 이미 읽기까지 막고 있었다.
  # 루트만 예외로 두면 그 일관성이 깨진다. 목록 조회 대안은 scripts/repo.sh list 다.
  "echo hi > /tmp/guard-check-elsewhere.txt"
  "git status"
  "bash scripts/workspace.sh $FX_STORY"
)
for c in "${MC_SH_ALLOW[@]}"; do
  runm "$(j_bash "$c")"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "통과(셸): $c" [ "$GUARD_RC" -eq 0 ]
done

# ── 막지 못하는 것. rc=0 을 **단언으로 박아 둔다** — acceptance ① 이 요구하는
# "차단되지 않은 경로는 한계로 명시" 를 문서가 아니라 게이트에 고정하는 자리다.
# 여기가 rc=2 로 바뀌면(= 누가 규칙을 넓혔으면) 게이트가 깨지고 한계 문서를 함께
# 고치게 된다. harness-uhy.3.3 note "한계" 와 1:1 대응한다.
# 라벨의 번호는 harness-uhy.3.3 note "한계" 의 항목 번호다. 그 문서가 목록과 이 단언들의
# 1:1 대응을 주장하므로, 항목을 늘리면 여기도 늘어나야 한다.
#
# 한계 2(심볼릭 링크)만은 **실제 링크를 만들어** 단언한다. 링크를 클론 루트 **안**의
# 워크트리 계층에 두고 본 체크아웃을 가리키게 하면, 어휘적 경로는 워크트리 예외에 걸려
# 통과하지만 물리적 경로는 본 체크아웃이다 — "훅이 링크를 따라가지 않는다"가 이 한 줄에
# 실제로 걸린다.
#   정정: 초판은 `/tmp/guard-check-symlink/main.txt` 라는 **아무도 만들지 않는** 경로의
#   rc=0 을 단언하며 "물리적 해석을 넣으면(realpath) 이 줄이 rc=2 로 바뀐다"고 적었다.
#   거짓이었다 — 그 경로는 클론 루트 밖이라 물리 해석을 주입해도 여전히 밖이고, mc_norm 에
#   물리 해석을 넣은 훅 사본으로 게이트 전체를 돌려도 rc=0·FAILED 0 이었다(리뷰 실측).
#   링크 성질을 전혀 검사하지 않는 줄이 라벨만 "한계 2" 였다. 같은 절의 일반 통과 케이스
#   (`echo hi > /tmp/…`)와 구별되지 않았다는 뜻이다.
MCLINK="$MCROOT/repo/.claude/worktrees/link"
mkdir -p "$MCROOT/repo/.claude/worktrees"
ln -sfn "$MCROOT/repo" "$MCLINK"
# 링크 생성이 실패해도 경로 문자열은 그대로 예외에 걸려 rc=0 이다 — 즉 단언이 공허하게
# 통과한다. 물리 해석이 실제로 본 체크아웃에 닿는지를 먼저 못박는다.
step "한계 2 준비: 링크가 본 체크아웃으로 실제 해석된다" \
  [ "$(cd "$MCLINK" 2>/dev/null && pwd -P)" = "$(cd "$MCROOT/repo" 2>/dev/null && pwd -P)" ]

declare -a MC_LIMIT_N=() MC_LIMIT_CMD=()
# 한계 1 은 **좁아졌다** — 상대 경로는 이제 payload 의 cwd 로 접어 판정한다(아래 "상대 경로" 절이
# 차단 단언을 든다). 남는 것은 **명령 안의 cd** 다: 훅은 cwd 를 페이로드에서 읽을 뿐 명령의 cd 를
# 따라가지 않으므로, cwd 가 /x 인 이 픽스처에서 `cd <워크트리> && echo ESC > ../../../esc.txt` 의
# 상대 경로는 /x 기준으로 접혀 클론 루트 밖이 된다. 그 rc=0 을 여기 고정한다.
MC_LIMIT_N+=(1); MC_LIMIT_CMD+=("cd $MCROOT/repo/.claude/worktrees/story-a && echo ESC > ../../../esc.txt")
MC_LIMIT_N+=(2); MC_LIMIT_CMD+=("echo x > $MCLINK/main.txt")
MC_LIMIT_N+=(3); MC_LIMIT_CMD+=('R="$HOME/.harness-workspace/repo"; echo x > "$R/main.txt"')
MC_LIMIT_N+=(4); MC_LIMIT_CMD+=('bash /tmp/writer.sh')
for i in "${!MC_LIMIT_CMD[@]}"; do
  runm "$(j_bash "${MC_LIMIT_CMD[$i]}")"
  printf '  rc=%d  [한계 %s] %s\n' "$GUARD_RC" "${MC_LIMIT_N[$i]}" "${MC_LIMIT_CMD[$i]}"
  step "한계(못 막음, rc=0 고정) ${MC_LIMIT_N[$i]}: ${MC_LIMIT_CMD[$i]}" [ "$GUARD_RC" -eq 0 ]
done
# 2번은 위에서 만든 실제 링크를 통과한다 — mc_norm 이 어휘적이라 `link` 를 그냥 한 칸으로
# 세고, 경로가 `.claude/worktrees` 아래라 셸 예외에 걸린다. mc_norm 에 물리적 해석을
# 주입한 사본에서는 이 줄이 rc=2 로 바뀐다(실측, harness-uhy.3.3 note "한계" 2번).
# 셸 경유 .claude/worktrees 계층 조작도 못 막는다 — 셸 규칙의 예외가 그 아래 **전부**라
# 파일 쓰기뿐 아니라 워크트리 디렉토리 자체의 삭제·이동까지 통과한다. harness-uhy.3.3 note
# "한계" 5번이 이 네 줄이다. 워크트리 정리의 정규 경로는 scripts/workspace-cleanup.sh 이고
# 수동 조작을 막던 r_worktree 는 뺐다. 여기가 rc=2 로 바뀌면 그 절을 함께 고쳐야 한다.
declare -a MC_WT_LIMIT=(
  "echo x > $MCROOT/repo/.claude/worktrees/notes.txt"
  "rm -rf $MCROOT/repo/.claude/worktrees/story-a"
  "rm -rf $MCROOT/repo/.claude/worktrees"
  "mv $MCROOT/repo/.claude/worktrees/story-a /tmp/gone"
)
for c in "${MC_WT_LIMIT[@]}"; do
  runm "$(j_bash "$c")"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "한계(못 막음, rc=0 고정) 5: $c" [ "$GUARD_RC" -eq 0 ]
done
# 심각도 역전의 대조군. 커밋으로 복구되는 소스 삭제는 막히는데, 복구 경로가 없는
# 워크트리 삭제는 위에서 통과한다. 이 두 줄이 나란히 있어야 역전이 보인다.
runm "$(j_bash "rm -rf $MCROOT/repo/src")"
printf '  rc=%d  %s\n' "$GUARD_RC" "대조: rm -rf <본 체크아웃>/src"
step "대조: 복구 가능한 rm -rf <본 체크아웃>/src 는 차단된다 (심각도 역전 확인)" [ "$GUARD_RC" -eq 2 ]
runm "$(j_write "$MCROOT/repo/.claude/worktrees/notes.txt")"
step "대조: 같은 경로를 Write 도구로 하면 차단된다 (층 차이 확인)" [ "$GUARD_RC" -eq 2 ]

# ── 상대 경로 — payload 의 cwd 로 접어 판정한다 (acceptance ②). 워크트리 안에서 `../../../f` 는
# 본 체크아웃이다. cwd 가 없으면 종전대로 판정하지 않는다(rc=0) — 그 두 상태를 함께 고정한다.
MC_CWD_WT="$MCROOT/r/.claude/worktrees/s"
runm "$(j_bash_cwd 'echo 1 > ../../../f' "$MC_CWD_WT")"
printf '  rc=%d  [cwd=워크트리] echo 1 > ../../../f\n' "$GUARD_RC"
step "상대 쓰기(cwd 있음): 워크트리에서 ../../../f 는 본 체크아웃 → rc=2" [ "$GUARD_RC" -eq 2 ]
runm "$(j_bash_cwd 'cat ../../../f' "$MC_CWD_WT")"
step "상대 읽기(cwd 있음): cat ../../../f 는 읽기라 통과 → rc=0" [ "$GUARD_RC" -eq 0 ]
runm "$(j_bash_cwd 'echo 1 > ./f' "$MC_CWD_WT")"
step "상대 쓰기(cwd 있음): 워크트리 안의 ./f 는 통과 → rc=0" [ "$GUARD_RC" -eq 0 ]
runm "$(j_bash_nocwd 'echo 1 > ../../../f')"
step "상대 쓰기(cwd 없음): 판정하지 않는다 → rc=0 (실패 경로 고정)" [ "$GUARD_RC" -eq 0 ]
runm "$(j_bash_nocwd "echo 1 > $MCROOT/r/f")"
step "절대 쓰기(cwd 없음): 종전대로 막힌다 → rc=2" [ "$GUARD_RC" -eq 2 ]
runm "$(j_write_cwd '../../../f' "$MC_CWD_WT")"
step "Write 도구의 상대 경로도 cwd 로 접는다 → rc=2" [ "$GUARD_RC" -eq 2 ]
runm "$(j_write_cwd 'src/a.js' "$MC_CWD_WT")"
step "Write 도구의 워크트리 안 상대 경로는 통과 → rc=0" [ "$GUARD_RC" -eq 0 ]
# A/B 귀속 — cwd 를 접는 한 줄(mc_norm 의 상대 분기)을 옛 형태로 되돌린 사본은 같은 입력을 통과시킨다.
NEG_CWD="$TMP/guard-no-cwd.sh"
step "부정 대조군 전제: 상대 분기가 훅에 1줄 실재한다" \
  [ "$(grep -cF 'p="$CWD/$p"' "$HOOK")" -eq 1 ]
sed 's|\*) \[ -n "\$CWD" \] \|\| return 1; p="\$CWD/\$p" ;;|*) return 1 ;;|' "$HOOK" > "$NEG_CWD"; chmod +x "$NEG_CWD"
step "부정 대조군 사본이 원본과 다르다" not_same "$HOOK" "$NEG_CWD"
runh "$NEG_CWD" "$(j_bash_cwd 'echo 1 > ../../../f' "$MC_CWD_WT")" "HARNESS_CLONE_ROOT=$MCROOT"
step "부정 대조군: 상대 분기를 빼면 같은 입력이 통과한다 (rc=0)" [ "$GUARD_RC" -eq 0 ]

# ── 클론 루트 **자체** (harness-iwj). 위 MC_WT_LIMIT 과 같은 종류의 심각도 역전이었다 —
# 레포 하나를 지우는 `rm -rf <루트>/<레포>` 는 막히는데 전부를 지우는 `rm -rf <루트>` 가
# 통과했다. mc_locate 가 `"$root"/?*` 만 매칭해 루트 자체를 후보로 잡지 못했기 때문이다.
declare -a MC_ROOT_SELF=(
  "rm -rf $MCROOT"
  "rm -rf $MCROOT/"
  "mv $MCROOT /tmp/gone"
)
for c in "${MC_ROOT_SELF[@]}"; do
  runm "$(j_bash "$c")"
  step "클론 루트 자체가 차단된다: $c" [ "$GUARD_RC" -eq 2 ]
done
# 도구 층도 같이 막힌다 — 셸만 고치면 Write 로 같은 경로를 지정하는 길이 남는다.
runm "$(j_write "$MCROOT")"
step "클론 루트 자체가 Write 도구로도 차단된다" [ "$GUARD_RC" -eq 2 ]
# 거짓 양성 대조군 — 루트와 **접두만** 같은 형제 경로까지 막으면 과차단이다.
runm "$(j_bash "rm -rf ${MCROOT}-other")"
step "대조: 루트와 접두만 같은 형제 경로는 통과한다" [ "$GUARD_RC" -eq 0 ]

# ── `$HOME` 표기 (harness-0ig). mc_norm 은 `~/` 만 확장하는데 후보 추출 grep 이 `$HOME`
# 뒤 슬래시부터 잡아 `/.harness-workspace/...` 라는 엉뚱한 절대 경로를 만들었다 — 틸드는
# 막히고 `$HOME` 은 새는 비대칭. 이 검사는 CLONE_ROOT 가 `$HOME` 아래여야 성립하므로
# runm(고정 MCROOT)을 쓰지 않는다. 경로는 문자열로만 판정되므로 실재할 필요가 없다.
HPROBE="$HOME/hprobe-clone"
declare -a HOME_FORMS=(
  'echo x > $HOME/hprobe-clone/repo/README.md'
  'echo x > ${HOME}/hprobe-clone/repo/README.md'
  'sed -i "" s/a/b/ $HOME/hprobe-clone/repo/README.md'
  'tee ~/hprobe-clone/repo/README.md < /tmp/x'
)
for c in "${HOME_FORMS[@]}"; do
  runh "$HOOK" "$(j_bash "$c")" "HARNESS_CLONE_ROOT=$HPROBE"
  step "홈 표기가 모두 차단된다: $c" [ "$GUARD_RC" -eq 2 ]
done

# ── 부정 대조군. 통과(rc=0)는 "검사했고 문제없음"과 "검사가 실행되지 않음"을 구분하지
# 못한다 (docs/development.md "검사가 죽었는지 검사한다"). 각 수정만 뺀 사본에서 같은 입력이
# 통과하는지 본다. 제거 전에 대상 줄이 실재하는지 먼저 단언한다 — 오타로 0줄을 지우면
# 사본이 원본과 같아져 대조군이 조용히 무의미해진다.
NEG_ROOT="$TMP/guard-no-rootself.sh"
step "부정 대조군 전제: 루트 자체 분기가 훅에 1줄 실재한다" \
  [ "$(grep -cF '"$lr")    MC_PATH=' "$HOOK")" -eq 1 ]
grep -vF '"$lr")    MC_PATH=' "$HOOK" > "$NEG_ROOT"; chmod +x "$NEG_ROOT"
runh "$NEG_ROOT" "$(j_bash "rm -rf $MCROOT")" "HARNESS_CLONE_ROOT=$MCROOT"
step "부정 대조군: 그 분기를 빼면 rm -rf <루트> 가 통과한다 (rc=0)" [ "$GUARD_RC" -eq 0 ]

NEG_HOME="$TMP/guard-no-homeexp.sh"
step "부정 대조군 전제: 홈 치환이 훅에 2줄 실재한다" \
  [ "$(grep -cF 'cmd="${cmd//' "$HOOK")" -eq 2 ]
grep -vF 'cmd="${cmd//' "$HOOK" > "$NEG_HOME"; chmod +x "$NEG_HOME"
runh "$NEG_HOME" "$(j_bash 'echo x > $HOME/hprobe-clone/repo/README.md')" "HARNESS_CLONE_ROOT=$HPROBE"
step "부정 대조군: 치환을 빼면 홈 표기가 통과한다 (rc=0)" [ "$GUARD_RC" -eq 0 ]

# ── 차단 메시지 — acceptance ③ (워크트리 경로를 대안으로 지시).
runm "$(j_write "$MCROOT/repo/main.txt")"
echo "  write  → $GUARD_OUT"
step "도구 메시지가 워크트리 경로를 대안으로 지시" \
  has_text "$MCROOT/repo/.claude/worktrees/<스토리ID>/" "$GUARD_OUT"
step "도구 메시지가 워크트리 생성 명령을 지시" has_text 'scripts/workspace.sh' "$GUARD_OUT"
step "도구 메시지에 문제의 경로가 실린다"     has_text "$MCROOT/repo/main.txt" "$GUARD_OUT"

runm "$(j_bash "echo hi > $MCROOT/repo/main.txt")"
echo "  shell  → $GUARD_OUT"
step "셸 메시지도 워크트리 경로를 대안으로 지시" \
  has_text "$MCROOT/repo/.claude/worktrees/<스토리ID>/" "$GUARD_OUT"
step "셸 메시지가 읽기 전용 면제를 밝힌다" has_text '읽기 전용 명령만으로 된 명령' "$GUARD_OUT"
step "셸 메시지는 도구 전용 문구를 쓰지 않는다 (분기 확인)" \
  lacks_text '쓰기는 스토리 워크트리 안에서만 한다' "$GUARD_OUT"

runm "$(j_write "$MCROOT/stray.txt")"
echo "  root   → $GUARD_OUT"
step "클론 루트 직속 메시지는 '레포 <파일명>' 헛소리를 하지 않는다" \
  lacks_text "대상 레포 'stray.txt'" "$GUARD_OUT"
step "클론 루트 직속 메시지도 워크트리를 대안으로 지시" has_text 'scripts/workspace.sh' "$GUARD_OUT"

# ── 기본 클론 루트가 $HOME/.harness-workspace 인가. 위 시험이 전부 MCROOT 재정의라
# 이것이 없으면 "재정의했을 때만 도는 규칙" 이어도 게이트가 통과한다.
# 합성 JSON 이므로 이 경로에 파일을 만들지 않는다.
rund "$(j_write "$HOME/.harness-workspace/__guard_probe__/main.txt")"
printf '  rc=%d   기본 루트: $HOME/.harness-workspace/__guard_probe__/main.txt\n' "$GUARD_RC"
step "기본 클론 루트는 \$HOME/.harness-workspace → rc=2" [ "$GUARD_RC" -eq 2 ]
rund "$(j_write "$HOME/.harness-workspace/__guard_probe__/.claude/worktrees/story-a/f.txt")"
step "기본 클론 루트에서도 워크트리 아래는 통과 → rc=0" [ "$GUARD_RC" -eq 0 ]
rund "$(j_write "$ROOT/checks/guard-check.sh")"
printf '  rc=%d  기본 루트: 게이트가 도는 트리 자신의 파일 (%s)\n' "$GUARD_RC" "$ROOT"
step "기본 루트 기준: 이 게이트가 도는 트리 자신의 쓰기는 통과" [ "$GUARD_RC" -eq 0 ]


echo "── ⑩ A4: bd 쓰기의 하네스 루트 지정 누락 차단 ──"
# 판정 대상은 **서브에이전트 호출뿐**이다. 오케스트레이터(부모 세션)의 무-C bd 는 정상이라
# 통과해야 하고, 그 통과가 "규칙이 꺼져서"가 아님을 같은 명령의 서브에이전트판 rc=2 로 못박는다.
j_agentfields() {  # j_agentfields <명령> <agent_id> <agent_type>
  jq -n --arg c "$1" --arg i "$2" --arg t "$3" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",agent_id:$i,agent_type:$t,tool_input:{command:$c}}'
}
runsub() { run "$(j_sub "$1" 'harness:implementer')"; }
# **agent_type 이 없는 서브에이전트.** ⑬(A5)이 얹힌 뒤 implementer 의 bd 쓰기는 note 하나로
# 좁혀졌다 — 그래서 "원장 지정 표기가 인정된다"를 create·update·close 로 보이려면 A4 의
# 판정 대상이면서 A5·A1/A2 의 판정 대상은 아닌 입력이 필요하다. r_bd_root 는 agent_id
# **또는** agent_type 으로 판정하고 r_impl_bd·r_grader_* 는 agent_type 값 자체로 판정하므로,
# agent_id 만 실은 입력이 정확히 그 자리다. 이 줄이 없으면 A4 의 통과 대조군이 A5 의 차단에
# 덮여, "A4 가 -C 를 인정한다"는 주장이 게이트에서 사라진다.
runsub_anon() { run "$(j_agentfields "$1" 'aa306a4edf39e7dfe' '')"; }

# ── 차단: 쓰기 계열. acceptance ① 이 요구하는 create·update·note·close·label 5종이 여기 있다.
declare -a BD_DENY=(
  'bd create "새 태스크" -t task'
  "bd update $FX_TASK --status open"
  "bd note $FX_TASK \"메모\""
  "bd close $FX_TASK --reason done"
  "bd label add $FX_TASK $FX_LABEL"
  "bd delete $FX_TASK"
  'bd dep add a b'
  'bd remember "무언가"'
  'timeout 5 bd create "래퍼를 씌워도"'
  "cd /tmp && bd note $FX_TASK \"hi\""
  'B=bd; $B create x'
  "bd -C /h show $FX_TASK && bd note $FX_TASK \"hi\""
)
for c in "${BD_DENY[@]}"; do
  runsub "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "차단: $c" [ "$GUARD_RC" -eq 2 ]
done
# 끝에서 둘째는 변수 치환이라 `bd` 뒤 토큰을 뽑지 못한다. 뽑지 못한 것을 통과로 읽으면
# 침묵이 통과가 되므로 훅이 그 경우도 차단한다 — 메시지가 갈리는지는 아래에서 본다.
# 마지막 것은 원장 지정을 **occurrence 마다** 봐야 잡힌다. 명령 전체 문자열에서 -C 를 한 번만
# 찾는 판정으로 바꾸면 앞의 지정이 뒤의 무-C 쓰기를 덮어 준다 (변조 (d) 로 실측).

# ── 통과: 원장 지정 표기 3종. `-C` 만 보면 다른 표기로 우회된다 (bd --help 실측:
#    `-C, --directory` 는 같은 플래그이고 `--db` 는 DB 경로를 직접 준다).
#    `--db` 의 통과 예시는 **하네스 원장 경로**로 쓴다 — 이 표기는 임의 DB 를 직접 겨눌 수 있어
#    /tmp 를 통과 예시로 두면 "임의 DB 도 정상"으로 읽힌다. 그 형태는 아래 한계 3 배열에 있다.
#    (게이트는 bd 를 실행하지 않는다 — 합성 JSON 의 문자열이라 이 경로의 실재는 판정에 무관하다)
#    쓰기 3종(create·update·close)은 **agent_type 없는 서브에이전트**로 돌린다 — implementer
#    로 돌리면 ⑬(A5)이 note 외의 쓰기를 막아 rc=2 가 되고, 이 절이 주장하려는 "A4 는 -C 를
#    인정한다"가 A5 의 차단에 덮인다. 두 규칙이 겹치는 자리는 ⑬ 에서 따로 본다.
declare -a BD_ALLOW=(
  "bd -C $FX_ROOT note $FX_TASK \"메모\""
  "bd show $FX_TASK"
  'bd list -l harness'
  'bd ready'
  'echo ok'
  'git status'
  'beads list'
)
for c in "${BD_ALLOW[@]}"; do
  runsub "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "통과: $c" [ "$GUARD_RC" -eq 0 ]
done
declare -a BD_ALLOW_ANON=(
  "bd --directory $FX_ROOT create \"x\" -t task"
  "bd --db $FX_ROOT/.beads/beads.db update $FX_TASK --status open"
  "bd -C /h close $FX_TASK && bd -C /h note $FX_TASK \"끝\""
)
for c in "${BD_ALLOW_ANON[@]}"; do
  runsub_anon "$c"
  printf '  rc=%d  [agent_type 없는 서브에이전트] %s\n' "$GUARD_RC" "$c"
  step "통과(agent_type 없는 서브에이전트): $c" [ "$GUARD_RC" -eq 0 ]
done

# ── 오케스트레이터는 막히지 않는다 (acceptance ③). 같은 명령을 두 형태로 돌려 대조한다.
declare -a BD_ORCH=(
  'bd create "새 태스크" -t task'
  "bd note $FX_TASK \"메모\""
  "bd close $FX_TASK"
)
for c in "${BD_ORCH[@]}"; do
  run "$(j_bash "$c")"
  printf '  rc=%d  [오케스트레이터] %s\n' "$GUARD_RC" "$c"
  step "통과(오케스트레이터, agent 필드 없음): $c" [ "$GUARD_RC" -eq 0 ]
  runsub "$c"
  step "대조(같은 명령, 서브에이전트): $c → rc=2" [ "$GUARD_RC" -eq 2 ]
done

# agent_id·agent_type 중 **하나만** 실려도 서브에이전트로 본다. 한쪽에만 기대면 그 필드가
# 비는 위임(유형 없는 Agent 호출 등)에서 규칙이 조용히 꺼진다.
run "$(j_agentfields 'bd create x' 'aa306a4edf39e7dfe' '')"
step "agent_id 만 있어도 차단" [ "$GUARD_RC" -eq 2 ]
run "$(j_agentfields 'bd create x' '' 'harness:implementer')"
step "agent_type 만 있어도 차단" [ "$GUARD_RC" -eq 2 ]
run "$(j_agentfields 'bd create x' '' '')"
step "둘 다 비면 통과 (오케스트레이터)" [ "$GUARD_RC" -eq 0 ]

# ── 극성 반전의 역방향 단언. 검사 대상을 손으로 고르지 않는다:
#    ① 면제 목록은 훅 **소스에서** 파생한다 (게이트에 다시 적지 않는다)
#    ② 면제 키가 실제 bd 하위 명령 집합에 존재하는지 `bd --help` 로 확인한다
#    ③ 그 집합에서 면제를 뺀 나머지가 **전부** 차단되는지 본다 — bd 에 새 하위 명령이
#       생기면 기본값이 "차단됨"이고, 그것을 이 단언이 증명한다
BD_EXEMPT_SRC=$(grep -E '^BD_READ_EXEMPT=' "$HOOK" | sed 's/^BD_READ_EXEMPT="//; s/"$//')
step "면제 목록을 훅 소스에서 파생했다 (비어 있지 않다)" [ -n "$BD_EXEMPT_SRC" ]
echo "  면제 목록($(printf '%s' "$BD_EXEMPT_SRC" | wc -w | tr -d ' ')개): $BD_EXEMPT_SRC"

BD_ALL=$(bd --help 2>/dev/null | grep -E '^  [a-z][a-z-]+ {2,}' | awk '{print $1}' | sort -u)
BD_ALL_N=$(printf '%s\n' "$BD_ALL" | grep -c . || true)
step "bd --help 에서 하위 명령 집합을 파생했다 (30개 이상)" [ "$BD_ALL_N" -ge 30 ]
echo "  bd 하위 명령 ${BD_ALL_N}개"
# 파생이 아무 낱말이나 긁어 오는 것이 아님을 못박는다 — 이게 없으면 위 단언이 공허해진다.
bd_in_all() { printf '%s\n' "$BD_ALL" | grep -qx -- "$1"; }
not_in_all() { ! bd_in_all "$1"; }
step "양성: 파생 집합에 create 가 있다"      bd_in_all create
step "음성: 없는 이름은 파생 집합에 없다"    not_in_all __notasubcmd__

bd_missing=""
for e in $BD_EXEMPT_SRC; do
  printf '%s\n' "$BD_ALL" | grep -qx -- "$e" || bd_missing="$bd_missing $e"
done
step "면제 키가 전부 실제 bd 하위 명령이다 (역방향 단언)" [ -z "$bd_missing" ]
[ -n "$bd_missing" ] && echo "    실재하지 않는 면제 키:$bd_missing"

# 면제 항목은 전부 통과해야 한다 — 목록에서 파생하므로 항목을 늘리면 시험도 함께 는다.
bd_exempt_blocked=""
for e in $BD_EXEMPT_SRC; do
  runsub "bd $e"
  [ "$GUARD_RC" -eq 0 ] || bd_exempt_blocked="$bd_exempt_blocked $e"
done
step "면제된 읽기 하위 명령이 전부 통과한다" [ -z "$bd_exempt_blocked" ]
[ -n "$bd_exempt_blocked" ] && echo "    막힌 면제 항목:$bd_exempt_blocked"

# 나머지 전부가 차단되는가. 목록을 손으로 적지 않으므로 새 하위 명령의 기본값이 "차단됨"이다.
bd_leaked=""; bd_checked=0
for s in $BD_ALL; do
  case " $BD_EXEMPT_SRC " in *" $s "*) continue ;; esac
  bd_checked=$((bd_checked + 1))
  runsub "bd $s"
  [ "$GUARD_RC" -eq 2 ] || bd_leaked="$bd_leaked $s"
done
echo "  비면제 하위 명령 ${bd_checked}개를 전수 시험했다"
step "비면제 하위 명령이 전부 차단된다 (새 명령의 기본값 = 차단)" [ -z "$bd_leaked" ]
[ -n "$bd_leaked" ] && echo "    샌 하위 명령:$bd_leaked"
step "전수 시험이 공허하지 않다 (비면제가 20개 이상)" [ "$bd_checked" -ge 20 ]

# ── 의도된 오탐. 진짜 차단과 **다른 배열**로 가른다 (⑧ WT_FALSEPOS·⑨ MC_SH_FALSEPOS 선례).
# 원장 지정 표기는 하위 명령 **앞**에서만 인정한다 — 뒤에 둔 -C 는 누락으로 읽힌다.
# (옵션을 앞세운 `bd --json create x` 는 오탐이 아니다 — 옵션을 건너뛰고 create 를 읽어 막는다. ⑬ 의 harness-2a5.3.1 절.)
declare -a BD_FALSEPOS=(
  "bd note $FX_TASK \"hi\" -C /h"    # 하위 명령 뒤의 -C 는 인정하지 않는다
)
# 실행 위치가 아닌 bd — 산문·검색 패턴·경로·스크립트 이름 — 는 판정에 들지 않는다.
declare -a BD_NOT_EXEC=(
  'git commit -m "bd note 를 추가"'
  'echo "bd create 를 쓰지 마라"'
  'bash /tmp/bd-writer.sh'
  "$FX_Q_BDNOTE"
  'grep -rn "bd note" docs/'
)
for c in "${BD_NOT_EXEC[@]}"; do
  runsub "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "통과(실행 위치 아님): $c" [ "$GUARD_RC" -eq 0 ]
done
for c in "${BD_FALSEPOS[@]}"; do
  runsub "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "의도된 오탐(차단): $c" [ "$GUARD_RC" -eq 2 ]
done

# ── 차단 메시지 (acceptance ④). 대안이 없으면 에이전트는 더 창의적인 우회를 찾는다.
# **agent_type 없는 서브에이전트로 돌린다.** implementer 로 돌리면 ⑬(A5)이 먼저 답해
# 이 메시지가 아니라 A5 의 메시지가 나온다 — 그 겹침은 ⑬ 에서 따로 단언한다.
runsub_anon 'bd create "x" -t task'
echo "  deny → $GUARD_OUT"
step "메시지가 -C <하네스루트> 를 대안으로 지시" has_text "bd -C <하네스루트>" "$GUARD_OUT"
step "메시지가 다른 표기(--directory·--db)도 인정한다고 밝힌다" has_text '--directory·--db' "$GUARD_OUT"
step "메시지에 문제의 하위 명령이 실린다"     has_text 'create' "$GUARD_OUT"
step "메시지가 조용한 실패를 근거로 든다"     has_text '조용히 성공' "$GUARD_OUT"
step "메시지가 읽기 면제를 알린다"            has_text '읽기(' "$GUARD_OUT"

runsub 'B=bd; $B create x'
echo "  subst → $GUARD_OUT"
step "치환 우회는 대입문으로 잡는다 (rc=2)" [ "$GUARD_RC" -eq 2 ]
step "치환 우회는 별도 메시지로 갈린다" has_text '변수에 담아 부르는 형태' "$GUARD_OUT"
runsub "$FX_Q_BDC"
step "규칙을 서술한 문서를 읽는 명령은 통과한다 (bd 가 실행 위치가 아니다)" [ "$GUARD_RC" -eq 0 ]

# 하네스 루트 값의 출처. 훅은 lib/harness-root.sh 를 **이 호출의 cwd** 에서 불러 값을 얻는다 —
# 찾으면 제시하고 못 찾으면 위임 메시지를 출처로 지시한다. 두 분기를 모두 돌린다.
# 찾는 쪽은 HARNESS_ROOT 로 물린다(헬퍼의 첫 출처) — 판별자(.beads/embeddeddolt)만 갖춘 합성 루트다.
mkdir -p "$FX_ROOT/.beads/embeddeddolt"
runh "$HOOK" "$(j_agentfields 'bd create x' 'aa306a4edf39e7dfe' '')" "HARNESS_ROOT=$FX_ROOT"
echo "  찾음 → ${GUARD_OUT: -140}"
step "헬퍼가 하네스 루트를 찾으면 그 절대 경로를 제시한다" has_text "하네스 루트는 $FX_ROOT 다" "$GUARD_OUT"
runh "$HOOK" "$(j_agentfields 'bd create x' 'aa306a4edf39e7dfe' '')" "HARNESS_ROOT=$TMP/not-a-root"
echo "  못 찾음 → ${GUARD_OUT: -140}"
step "헬퍼가 못 찾으면 값을 제시하지 않는다" has_text '하네스 루트를 찾지 못했다' "$GUARD_OUT"
step "그 경우 위임 메시지를 출처로 지시한다" has_text 'DECISION_NEEDED' "$GUARD_OUT"

# ── 막지 못하는 것. rc=0 을 단언으로 박아 둔다 (⑨ 선례) — harness-uhy.3.2 note "한계" 와 1:1.
declare -a BD_LIMIT_N=() BD_LIMIT_CMD=() BD_LIMIT_JSON=()
BD_LIMIT_N+=(1); BD_LIMIT_CMD+=('bd create "오케스트레이터의 무-C 쓰기"'); BD_LIMIT_JSON+=("$(j_bash 'bd create "오케스트레이터의 무-C 쓰기"')")
BD_LIMIT_N+=(2); BD_LIMIT_CMD+=('bd ready');            BD_LIMIT_JSON+=("$(j_sub 'bd ready' 'harness:implementer')")
BD_LIMIT_N+=(3); BD_LIMIT_CMD+=('bd -C /wrong/ledger note x "hi"'); BD_LIMIT_JSON+=("$(j_sub 'bd -C /wrong/ledger note x "hi"' 'harness:implementer')")
# 아래 줄은 **agent_type 없는 서브에이전트**다 — implementer 로 두면 ⑬(A5)이 update 를 막아
# rc=2 가 되고, A4 가 "-C 값의 옳고 그름을 보지 않는다"는 이 한계가 게이트에서 사라진다.
BD_LIMIT_N+=(3); BD_LIMIT_CMD+=("[agent_type 없음] bd --db /tmp/x.db update $FX_TASK --status open"); BD_LIMIT_JSON+=("$(j_agentfields "bd --db /tmp/x.db update $FX_TASK --status open" 'aa306a4edf39e7dfe' '')")
BD_LIMIT_N+=(4); BD_LIMIT_CMD+=('bash /tmp/ledger-writer.sh'); BD_LIMIT_JSON+=("$(j_sub 'bash /tmp/ledger-writer.sh' 'harness:implementer')")
for i in "${!BD_LIMIT_CMD[@]}"; do
  run "${BD_LIMIT_JSON[$i]}"
  printf '  rc=%d  [한계 %s] %s\n' "$GUARD_RC" "${BD_LIMIT_N[$i]}" "${BD_LIMIT_CMD[$i]}"
  step "한계(못 막음, rc=0 고정) ${BD_LIMIT_N[$i]}: ${BD_LIMIT_CMD[$i]}" [ "$GUARD_RC" -eq 0 ]
done

echo "── ⑪ A3/C2: 서브에이전트의 원격 반영·GitHub 조작 차단 ──"
# ⑩ 과 같은 구조다 — 판정 대상은 서브에이전트뿐이고, 통과가 "규칙이 꺼져서"가 아님을
# 같은 명령의 대조쌍으로 못박는다. runsub·j_agentfields 는 ⑩ 에서 정의됐다.
#
# **이 절은 `gh` 가 PATH 에 있어야 돈다.** 아래 역방향 단언이 하위 명령 집합을 `gh --help` 에서
# 파생하므로, gh 가 없으면 집합이 비고 "최상위 15개 이상" 단언이 깨져 rc=1 이 된다. 조용히
# 통과하지 않으니 방향은 안전하지만 **코드가 아니라 환경 사유로 깨질 수 있다**. `gh` 는 `bd` 와
# 달리 하네스 의존으로 등재돼 있지 않다(플러그인 문서 어디에도 없다) —
# 등재는 이 태스크의 범위 밖이라 사실만 남긴다.

# ── 차단: push 토큰. 형태를 열거하지 않으므로 래퍼·옵션 위치·다른 CLI 가 한 자리에서 걸린다.
declare -a RM_DENY=(
  'git push origin master'
  'git push'
  'git -C /tmp/r push'
  'timeout 5 git push'                     # 래퍼 (harness-uhy.1.1 ② 의 3연속 누출 지점)
  'git push --dry-run'                     # 시늉이어도 막는다 — 가르려면 형태 열거로 돌아간다
  'git push --force-with-lease'
  'cd /tmp/r && git push'
  'dolt push'
  # `push` 를 하위 명령으로 쓰는 실행형 로컬 명령 중 **진짜로 원격에 반영하는** 쪽. 오탐이 아니라
  # 정탐이고 차단이 옳다 — 그래서 RM_FALSEPOS 가 아니라 여기다. 로컬 대안(`git subtree split`)의
  # 통과는 RM_ALLOW 가 못박는다.
  'git subtree push --prefix x origin y'
  'gh pr create --title x'
  'gh pr merge 3 --squash'
  'gh pr close 3'
  'gh issue create --title x'
  'gh issue close 3'
  'gh issue comment 3 -b hi'
  'gh repo create o/r'
  'gh api -X POST repos/o/r/issues'        # 면제하지 않는다 — -X POST 를 읽기와 가를 수 없다
  'gh pr'                                  # 그룹만 있고 동사가 없다 → 면제어가 없으므로 차단
  'timeout 5 gh pr create'                 # 래퍼
  'gh pr list && gh pr create'             # occurrence 마다 본다 — 앞의 읽기가 뒤를 덮지 않는다
  'G=gh; $G pr create'                     # 치환은 대입문(tool_aliased)으로 잡는다 → 차단
  # URL 속 gh 는 실행 위치가 아니라 판정에 들지 않지만(RM_ALLOW 의 URL 통과 4건), 같은 줄의
  # 다음 조각에서 gh 가 실행되면 그 조각은 그대로 걸린다.
  'curl https://x.test/gh/a && gh pr create'
)
for c in "${RM_DENY[@]}"; do
  runsub "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "차단: $c" [ "$GUARD_RC" -eq 2 ]
done

# ── 통과: 읽기 계열. **이 배열이 이 규칙의 어려운 지점이다** — 여기가 막히면 리뷰어가 PR 을
#    못 읽고 정상 작업이 멈춘다. gh 를 토큰 하나로 막지 않고 두 토큰을 보는 이유가 이것이다.
declare -a RM_ALLOW=(
  'gh pr view 12'
  'gh pr list --state open'
  'gh pr diff 12'
  'gh pr checks 12'
  'gh pr status'
  'gh issue view 3'
  'gh issue list --label bug'
  'gh repo view'
  'gh run view 99'
  'gh release view v1'
  'gh auth status'
  'gh browse'
  'gh search prs --author me'
  'gh pr list && gh pr view 12'
  'git fetch origin'
  'git pull --rebase'
  'git status'
  'git log --oneline -5'
  'git commit -m "feat: x"'
  'git ls-remote origin'
  # deny 메시지가 제시하는 대안이 실제로 통과하는지 못박는다 — 막히는 대안을 권하면 받은
  # 에이전트가 두 번 막히고, 메시지가 있으나 마나가 된다.
  'git stash -m wip'                       # `git stash push -m wip` 의 대안
  'git subtree split --prefix x -b y'      # `git subtree push` 의 로컬 대안
  'echo ok'
  # 인용 픽스처 — gh 가 인용 부호 안에만 있고 실행 낱말은 grep 이다. 그 낱말이 그 파일에
  # 실제로 있다는 것까지 ⓪ 절이 단언한다 — 없으면 판정 재료가 없어 이 줄이 공허해진다.
  "$FX_Q_GHPR"
  # ── URL 오탐 회귀 (harness-bmu). 낱말 존재 판정 시절 `-w` 의 단어 경계에 `/` 가 포함돼 URL
  #    **경로의 세그먼트**가 명령 토큰으로 읽혀 막혔다 — 앞은 폰트를 받는 순수 읽기(harness-64a.1.1),
  #    뒤는 그 URL 을 원장에 인용하는 기록(harness-64a.2.1). 뒤엣것이 특히 나쁘다: 고칠 명령이 없는
  #    게 아니라 **기록할 내용을 왜곡해야** 통과한다. 지금은 gh 판정이 실행 위치(exec_segments gh)라
  #    URL 속 gh 는 조각의 첫 실행 낱말이 아니어서 구조적으로 판정에 들지 않는다 — 종전의 URL
  #    걷어내기(strip_urls)는 그래서 없다. 아래 넷은 그 회귀 고정이다.
  'curl -sL -o x.woff2 https://cdn.jsdelivr.net/gh/projectnoonnu/2408-3@1.0/Paperlogy-4Regular.woff2'
  "bd -C $FX_ROOT note $FX_TASK \"받은 곳: https://cdn.jsdelivr.net/gh/o/r@1.0/f.woff2\""
  # `?`·`,` 처럼 tr 이 끊는 문자로 이어진 URL 은 낱말 판정에서 `gh gh pr` 유령 쌍을 만들어
  # **읽기인데** rc=2 였다 [실측 2026-08-23]. 실행 위치 판정에서는 curl 조각에 gh 실행이 없다.
  'curl "https://x.test/a?gh" && gh pr view 1'
  'curl "https://x.test/a,gh" && gh pr view 1'
)
for c in "${RM_ALLOW[@]}"; do
  runsub "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "통과: $c" [ "$GUARD_RC" -eq 0 ]
done

# ── 오케스트레이터는 막히지 않는다 (acceptance ②). 사용자 지시를 받으면 실제로 해야 한다.
declare -a RM_ORCH=(
  'git push origin master'
  'gh pr create --title x'
  'gh issue close 3'
  'bd dolt push'
)
for c in "${RM_ORCH[@]}"; do
  run "$(j_bash "$c")"
  printf '  rc=%d  [오케스트레이터] %s\n' "$GUARD_RC" "$c"
  step "통과(오케스트레이터, agent 필드 없음): $c" [ "$GUARD_RC" -eq 0 ]
  runsub "$c"
  step "대조(같은 명령, 서브에이전트): $c → rc=2" [ "$GUARD_RC" -eq 2 ]
done

# 필드 하나만 실려도 서브에이전트로 본다 (⑩ 과 같은 이유 — 한쪽에만 기대면 그 필드가 비는
# 위임에서 규칙이 조용히 꺼진다).
run "$(j_agentfields 'git push origin master' 'aa306a4edf39e7dfe' '')"
step "agent_id 만 있어도 차단"   [ "$GUARD_RC" -eq 2 ]
run "$(j_agentfields 'git push origin master' '' 'harness:reviewer')"
step "agent_type 만 있어도 차단" [ "$GUARD_RC" -eq 2 ]
run "$(j_agentfields 'git push origin master' '' '')"
step "둘 다 비면 통과 (오케스트레이터)" [ "$GUARD_RC" -eq 0 ]

# ── 인용부호·백슬래시 우회. 셸은 `pu\sh`·`p""ush`·`p''ush` 를 push 로 실행한다(리뷰 #6).
#    판정 전 정규화(guard.sh 의 COMMAND 재대입)가 없으면 -w 낱말 판정이 그 글자에 막혀
#    rc=0 이었다 [실측 2026-08-28]. 그 줄을 빼면 아래 셋이 실패한다(A/B 귀속).
runsub 'git pu\sh origin x'
step "git pu\\sh (백슬래시 우회) → rc=2"         [ "$GUARD_RC" -eq 2 ]
runsub 'git p""ush origin x'
step "git p\"\"ush (빈 큰따옴표 우회) → rc=2"     [ "$GUARD_RC" -eq 2 ]
runsub "git p''ush origin x"
step "git p''ush (빈 홑따옴표 우회) → rc=2"        [ "$GUARD_RC" -eq 2 ]

# ── r_bd_root 와의 겹침. `bd dolt push` 는 두 규칙에 함께 걸린다(`dolt` 는 bd 읽기 면제가
#    아니다). 중복 차단은 두되 **등재 순서로 메시지를 고른다** — 진짜 문제는 -C 누락이 아니라
#    원격 반영이다. `-C` 를 붙인 형태가 여전히 막히는 것이 겹침을 순서로 다뤘다는 증거다:
#    A4 만 있었다면 그 줄은 통과한다.
runsub 'bd dolt push'
echo "  겹침 → $GUARD_OUT"
step "bd dolt push → rc=2"                     [ "$GUARD_RC" -eq 2 ]
step "겹침의 메시지는 원격 반영 쪽이다"          has_text '원격 반영 금지' "$GUARD_OUT"
step "겹침의 메시지가 -C 누락으로 오도하지 않는다" lacks_text 'bd 원장 지정 누락' "$GUARD_OUT"
runsub "bd -C $FX_ROOT dolt push"
echo "  겹침(-C 있음) → $GUARD_OUT"
step "-C 를 붙여도 막힌다 (A4 만으로는 통과하는 줄)" [ "$GUARD_RC" -eq 2 ]
step "그 메시지도 원격 반영 쪽이다"                 has_text '원격 반영 금지' "$GUARD_OUT"

# ── 극성 반전의 역방향 단언. 검사 대상을 손으로 고르지 않는다:
#    ① 면제 목록은 훅 **소스에서** 파생한다  ② 면제 키가 실제 gh 하위 명령인지 확인한다
#    ③ 파생 집합에서 면제를 뺀 나머지가 **전부** 차단되는지 본다 — gh 에 새 하위 명령이
#       생기면 기본값이 "차단됨"이고, 그것을 이 단언이 증명한다
GH_EXEMPT_SRC=$(grep -E '^GH_READ_EXEMPT=' "$HOOK" | sed 's/^GH_READ_EXEMPT="//; s/"$//')
step "면제 목록을 훅 소스에서 파생했다 (비어 있지 않다)" [ -n "$GH_EXEMPT_SRC" ]
echo "  면제 목록($(printf '%s' "$GH_EXEMPT_SRC" | wc -w | tr -d ' ')개): $GH_EXEMPT_SRC"

# gh 는 `gh <그룹> <동사>` 구조라 층마다 따로 파생한다. 최상위와, 이 규칙이 겨냥하는 두 그룹.
gh_cmds() { gh ${1:+"$1"} --help 2>/dev/null | grep -E '^  [a-z][a-z-]+: ' | sed 's/^  //; s/:.*//' | sort -u; }
GH_TOP=$(gh_cmds); GH_PR=$(gh_cmds pr); GH_ISSUE=$(gh_cmds issue)
# release·run 은 `download` 면제(harness-u9n.3.2)가 사는 그룹이라 함께 판다. 파생에 넣지
# 않으면 아래 역방향 단언이 `download` 를 "실재하지 않는 면제 키"로 잡고, 무엇보다 그 그룹의
# 쓰기 동사(`release create`·`upload`·`run rerun`)가 여전히 막히는지를 아무도 보지 않는다.
GH_RELEASE=$(gh_cmds release); GH_RUN=$(gh_cmds run)
gh_n() { printf '%s\n' "$1" | grep -c . || true; }
echo "  gh 하위 명령: 최상위 $(gh_n "$GH_TOP")개 · pr $(gh_n "$GH_PR")개 · issue $(gh_n "$GH_ISSUE")개 · release $(gh_n "$GH_RELEASE")개 · run $(gh_n "$GH_RUN")개"
step "gh --help 에서 최상위 집합을 파생했다 (15개 이상)" [ "$(gh_n "$GH_TOP")" -ge 15 ]
step "gh pr --help 에서 파생했다 (10개 이상)"           [ "$(gh_n "$GH_PR")" -ge 10 ]
step "gh issue --help 에서 파생했다 (8개 이상)"         [ "$(gh_n "$GH_ISSUE")" -ge 8 ]
step "gh release --help 에서 파생했다 (5개 이상)"       [ "$(gh_n "$GH_RELEASE")" -ge 5 ]
step "gh run --help 에서 파생했다 (5개 이상)"           [ "$(gh_n "$GH_RUN")" -ge 5 ]
# 파생이 아무 낱말이나 긁어 오는 것이 아님을 못박는다 — 없으면 위 단언이 공허해진다.
GH_ALL=$(printf '%s\n%s\n%s\n%s\n%s\n' "$GH_TOP" "$GH_PR" "$GH_ISSUE" "$GH_RELEASE" "$GH_RUN" | grep -v '^$' | sort -u)
gh_in_all()  { printf '%s\n' "$GH_ALL" | grep -qx -- "$1"; }
gh_not_all() { ! gh_in_all "$1"; }
step "양성: 파생 집합에 create 가 있다"   gh_in_all create
step "양성: 파생 집합에 merge 가 있다"    gh_in_all merge
step "음성: 없는 이름은 파생 집합에 없다" gh_not_all __notasubcmd__

gh_missing=""
for e in $GH_EXEMPT_SRC; do
  gh_in_all "$e" || gh_missing="$gh_missing $e"
done
step "면제 키가 전부 실제 gh 하위 명령이다 (역방향 단언)" [ -z "$gh_missing" ]
[ -n "$gh_missing" ] && echo "    실재하지 않는 면제 키:$gh_missing"

# 전수 시험. 최상위는 `gh <명령>`, 그룹은 `gh pr <동사>`·`gh issue <동사>` 로 돌린다.
# 면제어면 rc=0, 아니면 rc=2 — 목록을 손으로 적지 않으므로 새 명령의 기본값이 "차단됨"이다.
gh_is_exempt() { case " $GH_EXEMPT_SRC " in *" $1 "*) return 0 ;; esac; return 1; }
gh_leaked=""; gh_blocked_read=""; gh_checked=0
# 파이프로 먹이면 함수가 서브셸에서 돌아 아래 카운터가 전부 버려진다(빈 문자열 = 통과).
# here-string 으로 먹여 현재 셸에서 돌린다 (docs/development.md "셸 함정").
gh_sweep() {  # gh_sweep <접두>  — stdin 으로 하위 명령 목록을 받는다
  local prefix="$1" s
  while read -r s; do
    [ -n "$s" ] || continue
    gh_checked=$((gh_checked + 1))
    runsub "$prefix $s"
    if gh_is_exempt "$s"; then
      [ "$GUARD_RC" -eq 0 ] || gh_blocked_read="$gh_blocked_read $prefix-$s"
    else
      [ "$GUARD_RC" -eq 2 ] || gh_leaked="$gh_leaked $prefix-$s"
    fi
  done
}
gh_sweep 'gh'         <<< "$GH_TOP"
gh_sweep 'gh pr'      <<< "$GH_PR"
gh_sweep 'gh issue'   <<< "$GH_ISSUE"
gh_sweep 'gh release' <<< "$GH_RELEASE"
gh_sweep 'gh run'     <<< "$GH_RUN"
echo "  gh 하위 명령 ${gh_checked}개를 전수 시험했다"
step "비면제 gh 하위 명령이 전부 차단된다 (새 명령의 기본값 = 차단)" [ -z "$gh_leaked" ]
[ -n "$gh_leaked" ] && echo "    샌 하위 명령:$gh_leaked"
step "면제된 읽기 하위 명령이 전부 통과한다" [ -z "$gh_blocked_read" ]
[ -n "$gh_blocked_read" ] && echo "    막힌 면제 항목:$gh_blocked_read"
step "전수 시험이 공허하지 않다 (40개 이상)" [ "$gh_checked" -ge 40 ]

# ── `download` 면제 (harness-u9n.3.2). 난간을 넓히는 변경이라 **양쪽**을 시험한다 —
#    넓힌 쪽만 두면 면제 목록에 아무 낱말이나 넣어도 이 절이 녹색이다. 전수 시험은 동사만
#    붙인 형태라, 실제로 쓰이는 인자 배열(-R·--pattern·-D)도 통과하는지 따로 본다.
declare -a GH_DL_PASS=(
  'gh release download v0.1.0 -R o/r --pattern *.state -D /tmp/x'   # 릴리스 아티팩트를 받는 형태
  'gh release view v0.1.0 -R o/r --json tagName -q .tagName'        # 〃 (종전부터 면제)
  'gh run download 99 -n dist'
)
for c in "${GH_DL_PASS[@]}"; do
  runsub "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "받기는 통과: $c" [ "$GUARD_RC" -eq 0 ]
done
# 짝인 쓰기 동사. 낱말이 달라 그대로 차단이어야 한다 — 이 4건이 깨지면 면제가 그룹 전체를
# 열어젖힌 것이다.
declare -a GH_DL_DENY=(
  'gh release create v0.1.0 -R o/r'
  'gh release upload v0.1.0 harness.state -R o/r'
  'gh release delete v0.1.0 -R o/r'
  'gh run rerun 99'
)
for c in "${GH_DL_DENY[@]}"; do
  runsub "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "짝인 쓰기 동사는 여전히 차단: $c" [ "$GUARD_RC" -eq 2 ]
done
# 면제어 하나가 **무엇을 새로 통과시키는지** 열거한다. 판정은 `gh` 다음 두 토큰이라 통과가
# 늘어나는 것은 `download` 를 동사로 가진 그룹뿐이다 — 그 집합을 gh 에서 파생해 출력한다.
# `grep -qx` 는 첫 일치에서 즉시 끝나 앞의 `gh_cmds` 에 SIGPIPE 를 준다 — `set -o pipefail`
# 아래에서 그 그룹이 집합에서 조용히 빠질 수 있다. 출력만 버리고 끝까지 읽는다.
GH_DL_GROUPS=$(for g in $GH_TOP; do gh_cmds "$g" | grep -x download >/dev/null && printf '%s ' "$g"; done)
GH_DL_NORM=$(printf '%s\n' $GH_DL_GROUPS | grep -v '^$' | sort -u | tr '\n' ' '); GH_DL_NORM="${GH_DL_NORM% }"
echo "  download 동사를 가진 그룹: ${GH_DL_NORM:-(없음)}"
# **정확 집합**으로 단언한다. 하한(release·run 이 들어 있는가)만 보면 gh 에 `download` 를 가진
# 그룹이 하나 더 생겨도 rc=0 이라, 면제가 조용히 넓어지고 docs/guardrails.md 의 "셋뿐이고 전부
# 받기만 한다"가 거짓이 된 채로 남는다. 이 변경의 안전 논거 전체가 그 "셋뿐" 위에 서 있으므로
# 늘어나면 **시끄럽게 깨지는** 쪽이 맞다 — 깨지면 새 그룹이 정말 받기만 하는지 확인하고
# 이 기대값과 문서를 함께 고쳐라. (빈 집합도 이 단언에 걸리므로 공허한 통과가 없다.)
GH_DL_EXPECT='attestation release run'
step "download 동사를 가진 그룹이 정확히 [$GH_DL_EXPECT] 이다 (상·하한 단언)" \
  [ "$GH_DL_NORM" = "$GH_DL_EXPECT" ]
[ "$GH_DL_NORM" = "$GH_DL_EXPECT" ] || echo "    실제: [${GH_DL_NORM:-(없음)}] — 기대와 다르다"

# ── 의도된 오탐. 진짜 차단과 **다른 배열**로 가른다 (⑧⑨⑩ 선례).
declare -a RM_FALSEPOS=(
  'gh --repo o/r pr view 12'               # 선행 옵션은 건너뛰지만 그 값(o/r)은 못 건너뛴다 — 두 토큰이 o/r·pr 이다
)
for c in "${RM_FALSEPOS[@]}"; do
  runsub "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "의도된 오탐(차단): $c" [ "$GUARD_RC" -eq 2 ]
done
# gh 가 실행 위치가 아닌 낱말은 판정에 들지 않는다 — 종전 낱말 판정의 오탐(harness-uhy.1.1 ⑤·harness-fz1).
for c in 'echo "gh pr create 를 쓰지 마라"' 'bash /tmp/gh-runner.sh' 'chmod +x /tmp/x/gh'; do
  runsub "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "통과(gh 가 실행 위치가 아니다): $c" [ "$GUARD_RC" -eq 0 ]
done
# push 는 git·dolt·bd 가 **실행하는** 하위 명령으로 판정한다 — 낱말 인용과 로컬 명령은 통과한다.
declare -a RM_PUSH_PASS=(
  'git log --grep push'
  'grep -rn "git push" docs/'
  'cat /tmp/push-notes.md'
  'git stash push -m wip'
)
for c in "${RM_PUSH_PASS[@]}"; do
  runsub "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "통과(push 가 실행 위치가 아니다): $c" [ "$GUARD_RC" -eq 0 ]
done
# 실행 형태는 래퍼·옵션 위치·조각 안 어디든 막힌다.
for c in 'timeout 5 git push' 'cd x && git -C /tmp/r push' 'bash -c "git push origin x"' 'dolt push' 'bd dolt push' 'git subtree push --prefix a origin b' 'G=git; $G push'; do
  runsub "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "차단(push 실행): $c" [ "$GUARD_RC" -eq 2 ]
done

# ── 차단 메시지 (acceptance ③). 대안이 없으면 에이전트는 더 창의적인 우회를 찾는다.
runsub 'git push origin master'
echo "  deny(push) → $GUARD_OUT"
step "push: 오케스트레이터·사람의 몫임을 밝힌다" has_text '오케스트레이터·사람의 몫' "$GUARD_OUT"
step "push: 서브에이전트가 대신 할 일을 지시한다" has_text 'IMPLEMENTATION_COMPLETE' "$GUARD_OUT"
step "push: 근거 문서를 인용한다"                 has_text 'implementer.md' "$GUARD_OUT"
step "push: 오탐 가능성을 밝힌다"                 has_text '오탐' "$GUARD_OUT"
# 오탐의 성격이 하나가 아니다. 초판 메시지는 "그 경우는 오탐이고 고칠 명령이 없다" 한 줄이라
# `git stash push` 로 막힌 에이전트가 있는 대안(`git stash`)을 못 찾고 멈춘다. 갈래 3종이
# 메시지에 남아 있는지 5건으로 못박는다 (⑩ 에서 같은 종류의 오진 메시지를 고칠 때와 같은 방식).
step "push: 낱말 인용이 걸리지 않음을 밝힌다"    has_text '낱말 인용' "$GUARD_OUT"
step "push: (2) 실행형 로컬 명령 갈래를 가른다"   has_text 'git stash push' "$GUARD_OUT"
step "push: 로컬 명령이 걸리지 않음을 밝힌다"    has_text '로컬 명령' "$GUARD_OUT"
step "push: (3) 진짜 원격 반영 갈래를 가른다"     has_text 'git subtree push' "$GUARD_OUT"
step "push: (3) 의 로컬 대안을 준다"              has_text 'git subtree split' "$GUARD_OUT"

runsub 'gh pr create --title x'
echo "  deny(gh) → $GUARD_OUT"
step "gh: 오케스트레이터·사람의 몫임을 밝힌다"  has_text '오케스트레이터·사람의 몫' "$GUARD_OUT"
step "gh: 문제의 하위 명령이 실린다"            has_text "'gh pr create'" "$GUARD_OUT"
step "gh: 읽기 면제 목록을 알린다"              has_text "$GH_EXEMPT_SRC" "$GUARD_OUT"
step "gh: 통과하는 읽기 예시를 준다"            has_text 'gh pr view' "$GUARD_OUT"
step "gh: 서브에이전트가 대신 할 일을 지시한다" has_text 'IMPLEMENTATION_COMPLETE' "$GUARD_OUT"

runsub 'G=gh; $G pr create'
echo "  deny(치환) → $GUARD_OUT"
step "치환 우회는 대입문으로 잡는다 (rc=2)"   [ "$GUARD_RC" -eq 2 ]
step "치환 우회는 별도 메시지로 갈린다"       has_text '변수에 담아 부르는 형태' "$GUARD_OUT"
step "그 메시지가 직접 부르는 형태를 지시한다" has_text "gh <그룹> <하위명령>" "$GUARD_OUT"

# ── deny 메시지의 인용구가 **출처 문서의 문구와 일치하는가** (harness-dg0.6.8).
#    인용구를 훅 소스에 적기만 하고 끝내면 출처가 바뀌어도 아무것도 울지 않고, 출처에서만 확인하면
#    deny 가 바뀌어도 울지 않는다. 아래는 같은 문자열을 **양쪽에서** 찾는다.
#    출처는 플러그인 안이다 — 인용구 1 은 세션 블록(hooks/session-context.md "절대 금지"), 인용구 2
#    (액터 경계)는 harness:develop "사이클 종결". 하중을 지는 변환은 마크업 제거 하나다(`**`).
CM_FLAT=$(tr -d '*' < "$ROOT/hooks/session-context.md" | tr -s ' ')
AG_FLAT=$(tr -d '*' < "$ROOT/skills/develop/SKILL.md" | tr -s ' ')
step "세션 블록 마크업 제거 사본이 비어 있지 않다" [ -n "$CM_FLAT" ]
step "develop 스킬 마크업 제거 사본이 비어 있지 않다"  [ -n "$AG_FLAT" ]
RM_Q1='원격 반영은 사용자 명시 지시 시에만'
RM_Q2='서브에이전트는 범위 밖이다 — 로컬 커밋까지'
step "인용구 1 이 세션 블록에 실재한다 (역방향 단언)" has_text "$RM_Q1" "$CM_FLAT"
step "인용구 2 가 develop 스킬에 실재한다 (역방향 단언)"  has_text "$RM_Q2" "$AG_FLAT"
# 음성 대조 — 한 글자만 흔든 문자열은 안 잡혀야 한다. 없으면 위 두 줄이 "아무거나 통과"인지
# 구분되지 않는다.
step "음성 대조: 한 글자 바꾼 인용구는 develop 스킬에 없다" \
  lacks_text '서브에이전트는 범위 밖이다 — 로컬 커밋까진' "$AG_FLAT"
# 세 자리 전부다. 하나만 보면 나머지 둘이 낡아도 통과한다.
for c in 'git push origin master' 'gh pr create --title x' 'G=gh; $G pr create'; do
  runsub "$c"
  step "deny 가 세션 블록 인용구 1 을 그대로 담는다: $c" has_text "$RM_Q1" "$GUARD_OUT"
  step "deny 가 develop 인용구 2(액터 경계)를 그대로 담는다: $c" has_text "$RM_Q2" "$GUARD_OUT"
  step "deny 가 인용구 2 의 출처(harness:develop '사이클 종결')를 가리킨다: $c" has_text "harness:develop '사이클 종결'" "$GUARD_OUT"
done

# ── 한계 1 은 **재분류됐다 — 단언은 그대로 두고 라벨만 바꾼다** (harness-dg0.6.8).
#    6.7 이 CLAUDE.md 에 예외 둘을 붙여, 오케스트레이터의 원격 반영은 "못 막는 것"이 아니라
#    **설계상 허용**이 됐다(조건부로 미리 승인된 동작이다). 해소가 아니라 성격의 변경이므로
#    .claude/rules/agile.md 의 "한계로 못박은 rc=0 이 해소되면 지우지 말고 차단 단언으로
#    옮긴다" 를 따라 **rc=0 단언 자체는 유지**한다 — 지우면 누가 이 규칙을 오케스트레이터까지
#    넓혀도 아무 게이트도 울지 않는다. harness-uhy.3.4 note 는 번호 1 을 그대로 두고 그 자리에
#    재분류 한 줄을 더했다(기존 서술은 지우지 않는다 — 정정 보존).
run "$(j_bash 'git push origin master')"
printf '  rc=%d  [설계상 허용 1] [오케스트레이터] git push origin master\n' "$GUARD_RC"
step "설계상 허용(rc=0 고정) 1: [오케스트레이터] git push origin master — 넓히면 이 줄이 깨진다" \
  [ "$GUARD_RC" -eq 0 ]

# ── 막지 못하는 것. rc=0 을 단언으로 박아 둔다 — harness-uhy.3.4 note "한계" 와 1:1.
declare -a RM_LIMIT_N=() RM_LIMIT_CMD=() RM_LIMIT_JSON=()
RM_LIMIT_N+=(2); RM_LIMIT_CMD+=('bash /tmp/remote-writer.sh')
RM_LIMIT_JSON+=("$(j_sub 'bash /tmp/remote-writer.sh' 'harness:implementer')")
# 2b — **Bash 밖의 도구.** 이 규칙은 Bash 에만 등재돼 있고 판정 대상이 명령 문자열이라,
#      그 문자열이 없는 도구에는 걸릴 것이 없다. 쓰기 규칙(A1/A2·C3)은 harness-qpx 에서
#      "대상 경로를 받는가"로 극성을 뒤집어 해소했지만 여기에는 그 해법이 없다 —
#      WebFetch 의 url 이 원격 **반영**인지 읽기인지 가를 신호가 입력에 없다.
#      그 신호가 생기면 이 두 줄이 rc=2 로 바뀌며 깨진다. 그것이 박아 두는 이유다.
RM_LIMIT_N+=(2b); RM_LIMIT_CMD+=('[Bash 밖의 도구] WebFetch → GitHub API')
RM_LIMIT_JSON+=("$(jq -n '{hook_event_name:"PreToolUse",tool_name:"WebFetch",cwd:"/x",agent_id:"aa306a4edf39e7dfe",agent_type:"harness:implementer",tool_input:{url:"https://api.github.com/repos/o/r/pulls",prompt:"p"}}')")
RM_LIMIT_N+=(2b); RM_LIMIT_CMD+=('[Bash 밖의 도구] 가상 GitHub MCP 의 PR 생성')
RM_LIMIT_JSON+=("$(jq -n '{hook_event_name:"PreToolUse",tool_name:"mcp__github__create_pull_request",cwd:"/x",agent_id:"aa306a4edf39e7dfe",agent_type:"harness:implementer",tool_input:{title:"x",body:"y"}}')")
RM_LIMIT_N+=(3); RM_LIMIT_CMD+=('curl -X POST https://api.github.com/repos/o/r/issues')
RM_LIMIT_JSON+=("$(j_sub 'curl -X POST https://api.github.com/repos/o/r/issues' 'harness:implementer')")
RM_LIMIT_N+=(4); RM_LIMIT_CMD+=('git remote set-url origin git@github.com:o/other.git')
RM_LIMIT_JSON+=("$(j_sub 'git remote set-url origin git@github.com:o/other.git' 'harness:implementer')")
for i in "${!RM_LIMIT_CMD[@]}"; do
  run "${RM_LIMIT_JSON[$i]}"
  printf '  rc=%d  [한계 %s] %s\n' "$GUARD_RC" "${RM_LIMIT_N[$i]}" "${RM_LIMIT_CMD[$i]}"
  step "한계(못 막음, rc=0 고정) ${RM_LIMIT_N[$i]}: ${RM_LIMIT_CMD[$i]}" [ "$GUARD_RC" -eq 0 ]
done

# ── A/B 귀속. 위 rc=2 들이 **r_remote 등재 때문**임을, 등재만 뺀 사본으로 못박는다.
#    사본 방식은 guardrail-check.sh 의 mk_without 과 같다 — 함수 정의는 남기고 RULES+= 의
#    그 항목만 지워, 등록부 무결성(⑦)의 관심사와 섞이지 않게 한다.
AB_DIR="$TMP/wo-r_remote"
AB="$AB_DIR/hooks/guard.sh"      # GUARD_ROOT 파생이 배포본과 같은 형태가 되게
mkdir -p "$AB_DIR/hooks"
sed -E '/^RULES\+=/ s/"[^"]*:r_remote"//g' "$HOOK" > "$AB"
chmod +x "$AB"
step "A/B 사본이 원본과 다르다 (sed 가 실제로 등재를 지웠다)" not_same "$HOOK" "$AB"
step "A/B 사본에 r_remote 등재가 없다" \
  [ "$(grep -c '"Bash:r_remote"' "$AB")" -eq 0 ]
step "A/B 사본에 r_remote 함수 정의는 남아 있다 (등재만 뺐다)" \
  [ "$(grep -cE '^r_remote\(\)' "$AB")" -eq 1 ]

# 케이스 2 (acceptance ②) — 실제 GitHub 쓰기. 원본은 rc=2, 등재를 빼면 rc=0.
for c in 'gh pr create --title x' 'gh issue create --title x'; do
  runsub "$c"
  step "A/B 대조(원본): $c → rc=2" [ "$GUARD_RC" -eq 2 ]
  runh "$AB" "$(j_sub "$c" 'harness:implementer')"
  printf '  rc=%d  [r_remote 등재 없음] %s\n' "$GUARD_RC" "$c"
  step "A/B 귀속: r_remote 등재를 빼면 통과한다 → 그 차단은 이 규칙 때문이다: $c" \
    [ "$GUARD_RC" -eq 0 ]
done

# 케이스 1 (acceptance ①, URL 통과) 은 A/B 의 대상이 아니다 — 통과가 **어느 규칙 때문도 아님**을
# 보이는 것이라 등재를 빼도 rc 가 같다. 종전에는 strip_urls 를 무력화한 사본이 "수리 전에는
# 차단이었다"를 졌는데, gh 판정이 실행 위치로 옮겨지며(harness-2a5.3.1) URL 속 gh 는 구조적으로
# 판정에 들지 않게 되어 그 사본은 원본과 판정이 같아졌다 — 그래서 없다. gh 판정 축의 A/B 는
# ⑬ 의 harness-2a5.3.1 절이 든다(실행 위치 → 낱말 존재로 되돌린 사본에서 `chmod +x /tmp/x/gh` 가 막힌다).

echo "── ⑫ A1/A2: 채점자(reviewer·evaluator)의 쓰기 차단 ──"
# ⑩⑪ 과 구조는 같지만 **판정 술어가 다르다** — "서브에이전트인가"가 아니라 "agent_type 이
# reviewer·evaluator 인가"다. 그래서 implementer 대조군이 이 절의 핵심이다: 구현자를 함께
# 막으면 개발이 통째로 멈추는데 rc 만 보면 "잘 막힌다"로 읽힌다.
#
# 시험 경로는 **클론 루트 밖**(/tmp)을 쓴다. 본 체크아웃 경로를 쓰면 C3 도 함께 걸려
# rc=2 가 어느 규칙 때문인지 갈리지 않는다. 겹침은 아래에서 따로 본다.
GR_PATH="/tmp/guard-check-grader.txt"

j_tool_agent() {  # j_tool_agent <도구> <경로> <agent_type>
  jq -n --arg t "$1" --arg p "$2" --arg a "$3" '
    {hook_event_name:"PreToolUse", tool_name:$t, cwd:"/x",
     agent_id:"aa306a4edf39e7dfe", agent_type:$a,
     tool_input: (if   $t == "NotebookEdit" then {notebook_path:$p, new_source:"x"}
                  elif $t == "Edit"         then {file_path:$p, old_string:"a", new_string:"b"}
                  else                           {file_path:$p, content:"hi"} end)}'
}
runrole() { run "$(j_sub "$1" "$2")"; }   # <명령> <agent_type>

# ── 차단: 파일 쓰기 (acceptance ①).
# 목록의 뒤 둘은 **규칙에 이름이 등재되지 않은** 도구다. 종전에는 r_grader_write 가 세
# 이름에만 등재돼 그 밖의 쓰기 도구는 기본값이 "검사 안 됨"이었다 — 허용 목록 극성이라
# 새 도구가 붙는 순간 A1/A2 가 게이트 실패 없이 커버를 잃는다 (.claude/rules/agile.md).
# 이 두 줄은 이름을 늘리는 것이 아니라 **새 이름의 기본값이 "검사됨"인지**를 묻는다.
GR_R=harness:reviewer; GR_E=harness:evaluator; IMPL_T=harness:implementer
for role in $GR_R $GR_E; do
  for tool in Write Edit NotebookEdit MultiEdit mcp__fs__write_file; do
    run "$(j_tool_agent "$tool" "$GR_PATH" "$role")"
    printf '  rc=%d  [%s] %s %s\n' "$GUARD_RC" "$role" "$tool" "$GR_PATH"
    step "차단(도구): $tool · agent_type=$role" [ "$GUARD_RC" -eq 2 ]
  done
  # 과차단 대조군 — 읽기는 금지가 아니다. 두 역할 정의가 "검증용 명령 실행은 허용"을
  # 명시하고, 읽지 못하면 리뷰·판정 자체가 불가능하다. 위 극성 반전이 읽기까지 삼키면
  # 채점자는 아무것도 못 하는데 rc 만 보면 "잘 막힌다"로 읽힌다.
  for tool in Read Grep; do
    run "$(jq -n --arg t "$tool" --arg p "$GR_PATH" --arg a "$role" \
      '{hook_event_name:"PreToolUse",tool_name:$t,cwd:"/x",agent_id:"aa306a4edf39e7dfe",agent_type:$a,tool_input:{file_path:$p}}')"
    printf '  rc=%d  [%s] %s %s\n' "$GUARD_RC" "$role" "$tool" "$GR_PATH"
    step "통과(읽기): $tool · agent_type=$role" [ "$GUARD_RC" -eq 0 ]
  done
done

# ── 차단: 셸 (acceptance ②). commit 토큰과 bd 쓰기 하위 명령.
declare -a GR_DENY=(
  'git commit -m "fix: x"'
  'git commit --amend --no-edit'
  'git -C /tmp/r commit -m x'
  'timeout 5 git commit -m x'                  # 래퍼 (harness-uhy.1.1 ② 의 3연속 누출 지점)
  'cd /tmp/r && git commit -m x'
  "bd note $FX_TASK \"메모\""
  # 아래 넷이 이 규칙과 r_bd_root 를 가르는 자리다 — **원장을 지정해도 쓰기는 금지**다.
  "bd -C $FX_ROOT note $FX_TASK \"메모\""
  "bd --directory $FX_ROOT create \"x\" -t task"
  "bd --db $FX_ROOT/.beads/beads.db update $FX_TASK --status open"
  "timeout 5 bd -C /h close $FX_TASK --reason done"
  "bd label add $FX_TASK $FX_LABEL"
  'bd remember "무언가"'
  'bd --json create x'                         # 옵션을 앞세워도 하위 명령을 읽어낸다
  "bd -C /h show $FX_TASK && bd -C /h note $FX_TASK hi"  # occurrence 마다 본다
  'B=bd; $B note x'                            # 치환이라 하위 명령을 못 읽는다 → 차단
)
for role in $GR_R $GR_E; do
  for c in "${GR_DENY[@]}"; do
    runrole "$c" "$role"
    printf '  rc=%d  [%s] %s\n' "$GUARD_RC" "$role" "$c"
    step "차단(셸, $role): $c" [ "$GUARD_RC" -eq 2 ]
  done
done

# ── 통과: 검증용 명령 (acceptance ③). **이 배열이 이 규칙의 어려운 지점이다** — 두 역할
#    정의가 "검증용 명령 실행은 허용된다"를 명시하므로, 여기가 막히면 리뷰·판정 자체가
#    불가능해진다. 게이트 명령 두 줄('npm test' · check-all)은 게이트 명령의 예시다 — repos.json
#    은 하네스 루트의 프로젝트 맥락이라 플러그인 검사가 대조하지 않는다.
declare -a GR_ALLOW=(
  'git status'
  'git status --short'
  'git diff HEAD~1'
  'git show --stat HEAD'
  'git log --oneline -5'
  'git branch --show-current'
  "bd -C $FX_ROOT show $FX_TASK"
  "bd -C $FX_ROOT list -l harness"
  "bd show $FX_TASK"
  'bd ready'
  'npm test'
  'bash scripts/check-all.sh'
  'bash checks/guard-check.sh'
  'pwd'
  'ls -l hooks/'
)
for role in $GR_R $GR_E; do
  for c in "${GR_ALLOW[@]}"; do
    runrole "$c" "$role"
    printf '  rc=%d  [%s] %s\n' "$GUARD_RC" "$role" "$c"
    step "통과(검증용, $role): $c" [ "$GUARD_RC" -eq 0 ]
  done
done

# ── acceptance ④ — 같은 입력을 agent_type 네 가지로 돌린다. 차등이 실제로 갈리는지는
#    차단만으로는 보이지 않는다. implementer 는 파일을 고치고 커밋하고 bd note 를 쓴다.
echo "  ── 같은 입력 · agent_type 4종 (reviewer·evaluator 차단 / implementer·없음 통과) ──"
declare -a GR_MATRIX=(
  'git commit -m "feat: x"'
  "bd -C $FX_ROOT note $FX_TASK \"메모\""
)
for c in "${GR_MATRIX[@]}"; do
  for role in $GR_R $GR_E; do
    runrole "$c" "$role"
    printf '  rc=%d  [%s] %s\n' "$GUARD_RC" "$role" "$c"
    step "차단(agent_type=$role): $c" [ "$GUARD_RC" -eq 2 ]
  done
  runrole "$c" "$IMPL_T"
  printf '  rc=%d  [implementer] %s\n' "$GUARD_RC" "$c"
  step "통과(agent_type=implementer): $c" [ "$GUARD_RC" -eq 0 ]
  run "$(j_bash "$c")"
  printf '  rc=%d  [오케스트레이터] %s\n' "$GUARD_RC" "$c"
  step "통과(오케스트레이터, agent 필드 없음): $c" [ "$GUARD_RC" -eq 0 ]
done
for role in $GR_R $GR_E; do
  run "$(j_tool_agent Write "$GR_PATH" "$role")"
  step "차단(도구, agent_type=$role): Write $GR_PATH" [ "$GUARD_RC" -eq 2 ]
done
run "$(j_tool_agent Write "$GR_PATH" "$IMPL_T")"
printf '  rc=%d  [implementer] Write %s\n' "$GUARD_RC" "$GR_PATH"
step "통과(도구, agent_type=implementer): Write $GR_PATH" [ "$GUARD_RC" -eq 0 ]
run "$(j_write "$GR_PATH")"
step "통과(도구, 오케스트레이터): Write $GR_PATH" [ "$GUARD_RC" -eq 0 ]

# ── 극성 반전의 역방향 단언. 역할 목록을 게이트에 다시 적지 않는다:
#    ① 훅 소스에서 파생  ② 그 값이 실제 역할 정의 파일과 일치하는지 **역방향**으로 본다
#    ③ 역할 정의 전수(3종)를 돌려 채점자만 막히는지 본다 — 새 역할이 생기면 ② 가 깨진다
GR_ROLES_SRC=$(grep -E '^GR_ROLES=' "$HOOK" | sed 's/^GR_ROLES="//; s/"$//')
step "역할 목록을 훅 소스에서 파생했다 (비어 있지 않다)" [ -n "$GR_ROLES_SRC" ]
echo "  GR_ROLES: $GR_ROLES_SRC"
# 채점자의 표지는 역할 정의 자신의 문장이다 — reviewer.md "파일 수정·커밋은 금지다",
# evaluator.md "파일 수정·커밋 금지". 손으로 고르지 않고 이 문장에서 파생한다.
# **파생한 이름에 접두 `harness:` 를 붙인다** — 플러그인 에이전트의 agent_type 은 그 형식이다(M0 실측).
GR_AGENTS=$(ls agents/*.md 2>/dev/null | sed 's|.*/||; s|\.md$||; s|^|harness:|' | sort)
GR_DECLARED=$(grep -lE '파일 수정·커밋' agents/*.md 2>/dev/null | sed 's|.*/||; s|\.md$||; s|^|harness:|' | sort)
echo "  역할 정의 $(printf '%s\n' "$GR_AGENTS" | grep -c .)종 · 그중 '파일 수정·커밋 금지'를 선언한 것: $(printf '%s' "$GR_DECLARED" | tr '\n' ' ')"
step "역할 정의에서 채점자 집합을 파생했다 (비어 있지 않다)" [ -n "$GR_DECLARED" ]
step "파생이 전부를 긁어 오지 않는다 (역할 정의 수 > 채점자 수)" \
  [ "$(printf '%s\n' "$GR_AGENTS" | grep -c .)" -gt "$(printf '%s\n' "$GR_DECLARED" | grep -c .)" ]
step "훅의 GR_ROLES 가 역할 정의에서 파생한 집합과 일치한다 (역방향 단언)" \
  [ "$(printf '%s\n' $GR_ROLES_SRC | sort | tr '\n' ' ')" = "$(printf '%s\n' "$GR_DECLARED" | tr '\n' ' ')" ]

# 역할 정의 전수 시험 — 채점자면 차단, 아니면 통과. 목록을 손으로 적지 않으므로
# 역할이 늘면 시험도 함께 는다.
gr_leaked=""; gr_blocked=""; gr_checked=0
while read -r a; do
  [ -n "$a" ] || continue
  gr_checked=$((gr_checked + 1))
  run "$(j_tool_agent Write "$GR_PATH" "$a")"
  if printf '%s\n' "$GR_DECLARED" | grep -qx -- "$a"; then
    [ "$GUARD_RC" -eq 2 ] || gr_leaked="$gr_leaked $a"
  else
    [ "$GUARD_RC" -eq 0 ] || gr_blocked="$gr_blocked $a"
  fi
done <<< "$GR_AGENTS"
echo "  역할 ${gr_checked}종을 전수 시험했다"
step "채점자 역할이 전부 차단된다"           [ -z "$gr_leaked" ]
[ -n "$gr_leaked" ] && echo "    샌 역할:$gr_leaked"
step "채점자가 아닌 역할이 전부 통과한다"     [ -z "$gr_blocked" ]
[ -n "$gr_blocked" ] && echo "    막힌 역할:$gr_blocked"
step "전수 시험이 공허하지 않다 (역할 3종 이상)" [ "$gr_checked" -ge 3 ]

# ── 겹침: r_bd_root · r_remote · C3 와 어떻게 갈리나 (등재 순서로 메시지를 고른다).
echo "  ── 겹침 ──"
runrole "bd note $FX_TASK \"메모\"" "$GR_R"
echo "  겹침(A4) → $GUARD_OUT"
step "무-C bd 쓰기(reviewer) → rc=2" [ "$GUARD_RC" -eq 2 ]
step "그 메시지는 채점자 쪽이다"       has_text '채점자의 bd 쓰기 금지' "$GUARD_OUT"
step "메시지가 -C 를 붙이라고 오도하지 않는다" lacks_text 'bd 원장 지정 누락' "$GUARD_OUT"
runrole "bd note $FX_TASK \"메모\"" "$IMPL_T"
echo "  대조(implementer) → $GUARD_OUT"
step "대조: 같은 명령이 implementer 에게는 r_bd_root 메시지로 간다" \
  has_text 'bd 원장 지정 누락' "$GUARD_OUT"

runrole 'bd dolt push' "$GR_E"
echo "  겹침(A3/C2) → $GUARD_OUT"
step "bd dolt push(evaluator) → rc=2"      [ "$GUARD_RC" -eq 2 ]
step "그 메시지는 원격 반영 쪽이다 (r_remote 가 앞이다)" has_text '원격 반영 금지' "$GUARD_OUT"
step "그 메시지는 채점자 쪽이 아니다"        lacks_text '채점자의 bd 쓰기 금지' "$GUARD_OUT"

runh "$HOOK" "$(j_tool_agent Write "$MCROOT/repo/main.txt" "$GR_R")" "HARNESS_CLONE_ROOT=$MCROOT"
echo "  겹침(C3) → $GUARD_OUT"
step "본 체크아웃 Write(reviewer) → rc=2"  [ "$GUARD_RC" -eq 2 ]
step "그 메시지는 C3 쪽이다 (등재가 앞이다)" has_text '본 체크아웃 쓰기 금지' "$GUARD_OUT"
# 이 줄이 겹침을 순서로 다뤘다는 증거다 — C3 는 워크트리를 통과시키므로, 여기서 막는 것은
# 채점자 규칙뿐이다.
runh "$HOOK" "$(j_tool_agent Write "$MCROOT/repo/.claude/worktrees/story-a/f.txt" "$GR_R")" "HARNESS_CLONE_ROOT=$MCROOT"
echo "  워크트리 Write(reviewer) → $GUARD_OUT"
step "워크트리 Write(reviewer) → rc=2 (C3 만이면 통과하는 줄)" [ "$GUARD_RC" -eq 2 ]
step "그 메시지는 채점자 쪽이다"                                has_text '채점자의 파일 수정 금지' "$GUARD_OUT"

# ── 의도된 오탐. 진짜 차단과 **다른 배열**로 가른다 (⑧⑨⑩⑪ 선례).
# 실행 위치가 아닌 commit·bd 는 판정에 들지 않는다.
declare -a GR_NOT_EXEC=(
  'git log --grep commit'
  'grep -rn "git commit" docs/'
  'echo "commit 하지 마라"'
  'cat /tmp/commit-notes.md'
  'bash /tmp/bd-writer.sh'
  "$FX_Q_BDCLOSE"
)
for c in "${GR_NOT_EXEC[@]}"; do
  runrole "$c" "$GR_R"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "통과(실행 위치 아님): $c" [ "$GUARD_RC" -eq 0 ]
done
# 옵션만 있는 호출은 도움말·버전 출력이라 읽기다 (harness-2a5.3.1 — 종전에는 하위 명령이 빈 문자열이라 차단됐다).
for c in 'bd --help' 'bd --version' 'bd --help > /dev/null 2>&1'; do
  runrole "$c" "$GR_R"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "통과(옵션만 있는 호출은 읽기): $c" [ "$GUARD_RC" -eq 0 ]
done

# ── 차단 메시지 (acceptance ⑤ — 그 역할이 **무엇만 할 수 있는지**가 적힌다).
run "$(j_tool_agent Write "$GR_PATH" "$GR_R")"
echo "  deny(Write/reviewer) → $GUARD_OUT"
step "reviewer: 검증용 명령이 허용됨을 밝힌다" has_text '검증용 명령 실행은 허용된다' "$GUARD_OUT"
step "reviewer: 할 수 있는 것을 역할 이름으로 연다" has_text 'reviewer 가 할 수 있는 것' "$GUARD_OUT"
step "reviewer: 대신 낼 신호를 지시한다"       has_text 'SIGNAL: CHANGES_REQUESTED' "$GUARD_OUT"
step "reviewer: 산출물 형태를 지시한다"        has_text 'MUST FIX' "$GUARD_OUT"
step "reviewer: 근거 문서를 인용한다"          has_text 'agents/reviewer.md' "$GUARD_OUT"
step "reviewer: 문제의 도구 이름이 실린다"     has_text 'Write 도구' "$GUARD_OUT"
step "reviewer: evaluator 용 문구가 섞이지 않는다" lacks_text 'SIGNAL: MATCH' "$GUARD_OUT"

run "$(j_tool_agent Edit "$GR_PATH" "$GR_E")"
echo "  deny(Edit/evaluator) → $GUARD_OUT"
step "evaluator: 할 수 있는 것을 역할 이름으로 연다" has_text 'evaluator 가 할 수 있는 것' "$GUARD_OUT"
step "evaluator: 대신 낼 신호를 지시한다"      has_text "SIGNAL: MATCH" "$GUARD_OUT"
step "evaluator: 산출물 형태를 지시한다"       has_text 'MET/NOT_MET' "$GUARD_OUT"
step "evaluator: 기록이 오케스트레이터의 몫임을 밝힌다" has_text '오케스트레이터가 남긴다' "$GUARD_OUT"
step "evaluator: 근거 문서를 인용한다"         has_text 'agents/evaluator.md' "$GUARD_OUT"
step "evaluator: reviewer 용 문구가 섞이지 않는다" lacks_text 'MUST FIX' "$GUARD_OUT"
step "evaluator: 문제의 도구 이름이 실린다"    has_text 'Edit 도구' "$GUARD_OUT"

runrole 'git commit -m "fix"' "$GR_R"
echo "  deny(commit) → $GUARD_OUT"
step "commit: 하위 명령 판정임을 밝힌다" has_text 'git 이 실행하는 하위 명령' "$GUARD_OUT"
step "commit: 오탐 가능성을 밝힌다"      has_text '오탐' "$GUARD_OUT"
step "commit: 문제의 하위 명령이 실린다" has_text "'git commit'" "$GUARD_OUT"
step "commit: 읽기 면제 목록을 알린다"   has_text '읽기 면제:' "$GUARD_OUT"
step "commit: 함께 막히는 형태를 예시한다" has_text 'revert' "$GUARD_OUT"
step "commit: 오탐의 예를 준다"        has_text 'git log --grep commit' "$GUARD_OUT"
step "commit: 할 수 있는 것을 함께 적는다" has_text '검증용 명령 실행은 허용된다' "$GUARD_OUT"

runrole "bd -C /h note $FX_TASK \"메모\"" "$GR_E"
echo "  deny(bd) → $GUARD_OUT"
step "bd: 문제의 하위 명령이 실린다"        has_text "'bd note'" "$GUARD_OUT"
step "bd: -C 가 면죄부가 아님을 밝힌다"      has_text '붙여도 쓰기는 금지' "$GUARD_OUT"
step "bd: r_bd_root 와의 차이를 밝힌다"      has_text 'r_bd_root 와 다르다' "$GUARD_OUT"
step "bd: 읽기 면제 목록을 알린다"           has_text "$BD_EXEMPT_SRC" "$GUARD_OUT"
step "bd: 기록이 오케스트레이터의 몫임을 밝힌다" has_text '오케스트레이터의 몫' "$GUARD_OUT"

runrole 'B=bd; $B note x' "$GR_R"
echo "  deny(치환) → $GUARD_OUT"
step "치환 우회는 대입문으로 잡는다 (rc=2)"  [ "$GUARD_RC" -eq 2 ]
step "치환 우회는 별도 메시지로 갈린다"      has_text '변수에 담아 부르는 형태' "$GUARD_OUT"
# **이 두 줄이 없으면 위 넷이 공허하다.** r_bd_root 의 같은 자리 메시지가 위 세 문구를 전부
# 담고 있어, 채점자 규칙의 found 검사를 통째로 지워도 r_bd_root 가 대신 막고 같은 문자열을
# 낸다 (실측: 변조 (f) 가 FAILED 0건 · rc=0 으로 통과했다). 두 규칙을 가르는 것은 역할 꼬리다.
step "그 메시지가 채점자 쪽이다 (r_bd_root 의 같은 문구와 갈린다)" \
  has_text 'reviewer 가 할 수 있는 것' "$GUARD_OUT"
step "그 메시지가 채점자는 읽기만 가능함을 밝힌다" has_text '채점자는 읽기만 가능하다' "$GUARD_OUT"

# ── 채점자의 git 은 읽기 면제 목록 밖이면 전부 막힌다 — 커밋을 만들지 않는 쓰기(add·reset)와
#    commit 낱말 없는 커밋 생성(revert·cherry-pick·merge·rebase)이 함께 닫혔다.
for c in 'git add -A' 'git reset --hard HEAD~1' 'git revert HEAD' 'git cherry-pick abc123 --no-edit' 'git merge --no-ff x' 'git rebase main' 'git clean -fd' 'git checkout -- .' 'git stash'; do
  runrole "$c" "$GR_E"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "차단(채점자 git 쓰기): $c" [ "$GUARD_RC" -eq 2 ]
done
for c in 'git status' 'git log --oneline -3' 'git diff HEAD~1' 'git show HEAD' 'git branch --show-current' 'git rev-parse HEAD'; do
  runrole "$c" "$GR_R"
  step "통과(채점자 git 읽기): $c" [ "$GUARD_RC" -eq 0 ]
done

# ── 막지 못하는 것. rc=0 을 단언으로 박아 둔다 — harness-uhy.5.1 note "한계" 와 1:1.
declare -a GR_LIMIT_N=() GR_LIMIT_JSON=() GR_LIMIT_CMD=()
GR_LIMIT_N+=(1); GR_LIMIT_CMD+=('echo x > /tmp/guard-check-grader.txt')
GR_LIMIT_JSON+=("$(j_sub 'echo x > /tmp/guard-check-grader.txt' "$GR_R")")
GR_LIMIT_N+=(1); GR_LIMIT_CMD+=("sed -i '' s/a/b/ /tmp/guard-check-grader.txt")
GR_LIMIT_JSON+=("$(j_sub "sed -i '' s/a/b/ /tmp/guard-check-grader.txt" "$GR_R")")
# 2a — 커밋을 만들지 **않는** git 쓰기. 심각도 역전의 자리다(reset --hard 가 커밋보다 비싸다).
# 2b — **커밋을 만드는데 `commit` 토큰이 없는 것.** 2a 와 성격이 다르다: 2a 는 차단 목록의
# 범위 밖이지만 이쪽은 범위 **안**(A1 의 "파일 수정·커밋")인데도 새는, 토큰 판정 자체의
# 미탐이다. 이 두 줄이 없으면 나중에 토큰 집합을 넓힐 때 깨질 자리가 게이트에 없다 —
# 넓히는 쪽이 옳다고 판단되면 이 rc=0 단언을 rc=2 로 바꾸는 것이 그 변경의 시작점이다.
GR_LIMIT_N+=(3); GR_LIMIT_CMD+=('bash /tmp/grader-writer.sh')
GR_LIMIT_JSON+=("$(j_sub 'bash /tmp/grader-writer.sh' "$GR_R")")
GR_LIMIT_N+=(4); GR_LIMIT_CMD+=('[agent_type 없는 위임] git commit -m x')
GR_LIMIT_JSON+=("$(j_agentfields 'git commit -m x' 'aa306a4edf39e7dfe' '')")
# 한계 5(목록 밖 쓰기 도구가 rc=0 으로 샌다)는 **해소됐다** — harness-qpx. r_grader_write 가
# 도구 이름 목록이 아니라 w_path(대상 경로를 받는가)로 발동하도록 극성을 뒤집었고, 그
# 차단 단언은 위 "차단(도구)" 루프의 MultiEdit·mcp__fs__write_file 두 줄이 든다.
# 등재를 지우기만 하면 해소가 게이트에서 사라지므로 차단 쪽으로 옮긴 것이다.
for i in "${!GR_LIMIT_CMD[@]}"; do
  run "${GR_LIMIT_JSON[$i]}"
  printf '  rc=%d  [한계 %s] %s\n' "$GUARD_RC" "${GR_LIMIT_N[$i]}" "${GR_LIMIT_CMD[$i]}"
  step "한계(못 막음, rc=0 고정) ${GR_LIMIT_N[$i]}: ${GR_LIMIT_CMD[$i]}" [ "$GUARD_RC" -eq 0 ]
done
# 한계 4 가 이 규칙만의 것이다. r_bd_root·r_remote 는 agent_id **또는** agent_type 으로
# 판정하지만 이 규칙은 agent_type 값 자체가 판정 근거라, 유형 없이 위임된 채점자에게는
# 규칙이 통째로 꺼진다. 열 방법이 없다 — agent_id 만으로는 그 호출이 채점자인지 알 수 없다.

echo "── ⑬ A5: implementer 의 bd 쓰기 범위 제한 (note 하나만 허용) ──"
# ⑫ 와 같은 판정 지점(gr_bd_subcmds 로 뽑은 하위 명령)에 **다른 허용 목록**이 붙는다.
# 채점자는 bd 쓰기가 전부 금지, implementer 는 note 만 허용이다. 그래서 이 절의 핵심은
# **허용 대조군**이다 — note 가 막히면 구현자가 알게 된 사실을 원장에 남길 통로가 끊기는데,
# 차단만 세면 rc 는 "잘 막힌다"로 읽힌다 (harness-uhy.1.1 note 설계 함의 5).
#
# 차단 시험은 **전부 `-C` 를 붙여서** 돌린다. 무-C 로 돌리면 r_bd_root 도 함께 걸려
# rc=2 가 어느 규칙 때문인지 갈리지 않는다. 겹침은 아래에서 따로 본다.
IMPL_H="$FX_ROOT"
runimpl() { run "$(j_sub "$1" "$IMPL_T")"; }

# ── 차단: note 아닌 bd 쓰기 (acceptance ①). -C 를 붙여도 막힌다.
declare -a IMPL_DENY=(
  "bd -C $IMPL_H create \"새 태스크\" -t task"
  "bd -C $IMPL_H update $FX_TASK --status open"
  "bd -C $IMPL_H label add $FX_TASK $FX_LABEL"
  "bd -C $IMPL_H close $FX_TASK --reason done"
  "bd -C $IMPL_H remember \"무언가\""
  "bd -C $IMPL_H delete $FX_TASK"
  "bd -C $IMPL_H dep add a b"
  "bd -C $IMPL_H sql \"update issues set status='closed'\""   # 원장 구조 변경의 최단 경로
  "bd -C $IMPL_H batch"                                        # 트랜잭션으로 묶어도 같다
  "bd -C $IMPL_H import --file /tmp/x.jsonl"
  "bd --directory $IMPL_H create x"                            # 지정 표기가 달라도 같다
  "bd --db $IMPL_H/.beads/beads.db update $FX_TASK --status open"
  "timeout 5 bd -C $IMPL_H create x"                           # 래퍼 (harness-uhy.1.1 ② 의 3연속 누출 지점)
  "cd /tmp && bd -C $IMPL_H close $FX_TASK"
  "bd --json -C $IMPL_H create x"                              # 옵션을 앞세워도 하위 명령을 읽어낸다
  "bd -C $IMPL_H show $FX_TASK && bd -C $IMPL_H create x"  # occurrence 마다 본다
  'bd create x'                                                # 무-C — 아래 겹침에서 메시지를 본다
)
for c in "${IMPL_DENY[@]}"; do
  runimpl "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "차단(implementer): $c" [ "$GUARD_RC" -eq 2 ]
done

# ── 통과: note 와 읽기 (acceptance ②③). **이 배열이 이 규칙의 안전 요건이다.**
#    implementer.md 절차 8 이 `bd -C <하네스루트> note <태스크ID> "…"` 를 **요구**한다 —
#    여기가 막히면 스토리의 학습이 응답 본문에만 남고 원장에서 사라진다.
declare -a IMPL_ALLOW=(
  "bd -C $IMPL_H note $FX_TASK \"메모\""
  "bd --directory $IMPL_H note $FX_TASK \"메모\""
  "bd --db $IMPL_H/.beads/beads.db note $FX_TASK \"메모\""
  "bd -C $IMPL_H note $FX_TASK --file /tmp/n.txt"
  "bd -C $IMPL_H note $FX_TASK --stdin"
  "bd -C $IMPL_H note $FX_TASK \"RETRY: verify-code 1/2\""
  "bd -C $IMPL_H show $FX_TASK && bd -C $IMPL_H note $FX_TASK \"끝\""
  "bd -C $IMPL_H show $FX_TASK"
  "bd -C $IMPL_H list -l harness"
  "bd show $FX_TASK"
  'bd ready'
  'git status'
  'git commit -m "feat: x"'          # 구현자는 로컬 커밋을 한다 (채점자와 갈리는 자리)
  'beads list'
  'bash checks/guard-check.sh'
)
for c in "${IMPL_ALLOW[@]}"; do
  runimpl "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "통과(implementer): $c" [ "$GUARD_RC" -eq 0 ]
done

# ── acceptance ④ — 같은 입력을 agent_type 4종으로 돌린다. 역할별 허용 목록이 실제로
#    갈리는지는 한 역할만 보아서는 알 수 없다: note 는 implementer 만 통과하고,
#    create 계열은 오케스트레이터만 통과한다.
echo "  ── 같은 입력 · agent_type 4종 ──"
impl_matrix() {  # impl_matrix <명령> <implementer 기대rc>
  local c="$1" want="$2" role
  for role in $GR_R $GR_E; do
    run "$(j_sub "$c" "$role")"
    printf '  rc=%d  [%s] %s\n' "$GUARD_RC" "$role" "$c"
    step "차단(agent_type=$role): $c" [ "$GUARD_RC" -eq 2 ]
  done
  runimpl "$c"
  printf '  rc=%d  [implementer] %s\n' "$GUARD_RC" "$c"
  step "agent_type=implementer → rc=$want: $c" [ "$GUARD_RC" -eq "$want" ]
  run "$(j_bash "$c")"
  printf '  rc=%d  [오케스트레이터] %s\n' "$GUARD_RC" "$c"
  step "통과(오케스트레이터, agent 필드 없음): $c" [ "$GUARD_RC" -eq 0 ]
}
impl_matrix "bd -C $IMPL_H note $FX_TASK \"메모\"" 0
for w in create update label close remember; do
  impl_matrix "bd -C $IMPL_H $w $FX_TASK" 2
done

# ── 극성 반전의 역방향 단언 ①: 허용 목록. 게이트에 다시 적지 않고 훅 소스에서 파생한다.
IMPL_ALLOW_SRC=$(grep -E '^IMPL_BD_WRITE_ALLOW=' "$HOOK" | sed 's/^IMPL_BD_WRITE_ALLOW="//; s/"$//')
step "허용 목록을 훅 소스에서 파생했다 (비어 있지 않다)" [ -n "$IMPL_ALLOW_SRC" ]
echo "  IMPL_BD_WRITE_ALLOW: $IMPL_ALLOW_SRC"
# 허용 키가 실제 bd 하위 명령인가 (BD_ALL 은 ⑩ 이 `bd --help` 에서 파생했다).
impl_missing=""
for e in $IMPL_ALLOW_SRC; do
  printf '%s\n' "$BD_ALL" | grep -qx -- "$e" || impl_missing="$impl_missing $e"
done
step "허용 키가 전부 실제 bd 하위 명령이다 (역방향 단언)" [ -z "$impl_missing" ]
[ -n "$impl_missing" ] && echo "    실재하지 않는 허용 키:$impl_missing"
# 허용 목록과 읽기 면제가 겹치지 않는가. 겹치면 "쓰기 중 무엇이 허용됐나"가 흐려지고,
# 읽기 면제만 늘려도 쓰기가 열리는 경로가 생긴다.
impl_overlap=""
for e in $IMPL_ALLOW_SRC; do
  case " $BD_EXEMPT_SRC " in *" $e "*) impl_overlap="$impl_overlap $e" ;; esac
done
step "허용 목록이 읽기 면제와 겹치지 않는다" [ -z "$impl_overlap" ]
[ -n "$impl_overlap" ] && echo "    겹치는 키:$impl_overlap"
# 전수 시험 — 면제(읽기) ∪ 허용(쓰기) 은 통과, 나머지는 전부 차단. `-C` 를 붙여 돌리므로
# r_bd_root 가 아니라 이 규칙이 판정한다. bd 에 새 하위 명령이 생기면 기본값이 "차단됨"이다.
impl_leaked=""; impl_blocked=""; impl_checked=0; impl_denied=0
for s in $BD_ALL; do
  impl_checked=$((impl_checked + 1))
  runimpl "bd -C $IMPL_H $s"
  if case " $BD_EXEMPT_SRC $IMPL_ALLOW_SRC " in *" $s "*) true ;; *) false ;; esac; then
    [ "$GUARD_RC" -eq 0 ] || impl_blocked="$impl_blocked $s"
  else
    impl_denied=$((impl_denied + 1))
    [ "$GUARD_RC" -eq 2 ] || impl_leaked="$impl_leaked $s"
  fi
done
echo "  bd 하위 명령 ${impl_checked}개를 전수 시험했다 (차단 기대 ${impl_denied}개)"
step "면제·허용 밖의 하위 명령이 전부 차단된다" [ -z "$impl_leaked" ]
[ -n "$impl_leaked" ] && echo "    샌 하위 명령:$impl_leaked"
step "면제·허용된 하위 명령이 전부 통과한다"   [ -z "$impl_blocked" ]
[ -n "$impl_blocked" ] && echo "    막힌 항목:$impl_blocked"
step "전수 시험이 공허하지 않다 (차단 기대가 20개 이상)" [ "$impl_denied" -ge 20 ]

# ── 대상 단언: 정정 보존이 무엇에 기대고 있는지를 **이름으로** 못박는다.
#    `.claude/rules/agile.md` 의 정정 보존은 원장의 note 가 덮이지 않는다를 전제하는데,
#    실측상 그것은 원장 도구의 성질이 아니라 이 규칙의 결과다 — bd 에는 notes 를 고치고
#    지우는 하위 명령이 여럿 있고 append 전용인 것은 `note` 뿐이다 (근거 명령과 측정
#    환경은 docs/guardrails.md 1-2 절).
#
#    위 전수 시험만으로는 부족하다. 그것은 BD_ALL(= `bd --help` 파생)을 돌며 **개수**의
#    하한만 지키므로, bd 가 이름을 바꾸거나 도움말 서식이 달라져 아래 이름들이 파생
#    집합에서 빠져도 하한은 살아 있고 절은 그대로 초록이다 — 그때 조용히 열리는 것이
#    정확히 정정 보존의 경로다. 그래서 "무엇을 보는가"를 여기서 따로 단언한다.
# `restore` 는 인자 없이는 표시만 하는 읽기지만 `--apply` 가 압축 스냅샷의 원본을 이슈에
# 되쓴다 (`bd help restore`: "Write the restored content back into the issue"). 되쓰는 대상에
# notes 가 포함되므로 여기 든다.
BD_NOTE_MUTATORS="update edit sql delete import restore"
step "대상 목록이 비어 있지 않다 (공허한 참을 실패로 읽는다)" [ -n "$BD_NOTE_MUTATORS" ]
nm_absent=""; nm_open=""
for s in $BD_NOTE_MUTATORS; do
  bd_in_all "$s" || nm_absent="$nm_absent $s"
  case " $BD_EXEMPT_SRC $IMPL_ALLOW_SRC " in *" $s "*) nm_open="$nm_open $s" ;; esac
done
step "note 를 고치는 하위 명령이 전부 파생 집합 안에 있다 (전수 시험이 실제로 이들을 본다)" \
  [ -z "$nm_absent" ]
[ -n "$nm_absent" ] && echo "    파생 집합에서 사라진 이름:$nm_absent"
step "그중 면제·허용에 든 것이 없다 (전부 차단 기대다)" [ -z "$nm_open" ]
[ -n "$nm_open" ] && echo "    면제·허용에 들어 있다:$nm_open"

# 부정 대조군 — note 를 실제로 고치는 형태를 서브에이전트 3역할에 먹인다. 위 전수 시험은
# `bd -C <루트> <하위명령>` 만 돌리므로 **필드를 지정한 형태**(--notes)는 여기서만 본다.
declare -a NM_DENY=(
  "bd -C $IMPL_H update $FX_TASK --notes \"덮어쓴다\""
  "bd -C $IMPL_H update $FX_TASK --append-notes \"덧붙인다\""
  "bd -C $IMPL_H edit $FX_TASK --notes"
  "bd -C $IMPL_H sql \"update issues set notes='' where id='$FX_TASK'\""
  "bd -C $IMPL_H delete $FX_TASK"
  "bd -C $IMPL_H import --file /tmp/x.jsonl"
)
step "부정 대조군이 비어 있지 않다" [ "${#NM_DENY[@]}" -gt 0 ]
for role in $IMPL_T $GR_R $GR_E; do
  for c in "${NM_DENY[@]}"; do
    run "$(j_sub "$c" "$role")"
    printf '  rc=%d  [%s] %s\n' "$GUARD_RC" "$role" "$c"
    step "차단($role): $c" [ "$GUARD_RC" -eq 2 ]
  done
done
# 정상 대조군 — 같은 자리에서 append 통로(note)는 implementer 에게 열려 있어야 한다.
# 이것이 ✗ 면 위 차단들은 "잘 막는다"가 아니라 "bd 가 통째로 막혔다"는 뜻이다.
runimpl "bd -C $IMPL_H note $FX_TASK --file /tmp/n.txt"
printf '  rc=%d  [정상 대조군] %s\n' "$GUARD_RC" "bd -C $IMPL_H note $FX_TASK --file /tmp/n.txt"
step "정상 대조군: implementer 의 note(append 통로)는 통과한다" [ "$GUARD_RC" -eq 0 ]

# ── 극성 반전의 역방향 단언 ②: 역할 목록. ⑫ 의 GR_ROLES 와 같은 형태다.
IMPL_ROLES_SRC=$(grep -E '^IMPL_ROLES=' "$HOOK" | sed 's/^IMPL_ROLES="//; s/"$//')
step "역할 목록을 훅 소스에서 파생했다 (비어 있지 않다)" [ -n "$IMPL_ROLES_SRC" ]
echo "  IMPL_ROLES: $IMPL_ROLES_SRC"
# 표지는 역할 정의 자신의 문장이다 — implementer.md "**`bd note` 외의 bd 쓰기**".
# 손으로 고르지 않고 이 문장에서 파생한다. 접두 `harness:` 는 ⑫ 와 같은 이유로 붙인다.
IMPL_DECLARED=$(grep -lF 'bd note` 외의 bd 쓰기' agents/*.md 2>/dev/null | sed 's|.*/||; s|\.md$||; s|^|harness:|' | sort)
echo "  'bd note 외의 bd 쓰기' 를 금지한 역할 정의: $(printf '%s' "$IMPL_DECLARED" | tr '\n' ' ')"
step "역할 정의에서 대상 집합을 파생했다 (비어 있지 않다)" [ -n "$IMPL_DECLARED" ]
step "훅의 IMPL_ROLES 가 역할 정의에서 파생한 집합과 일치한다 (역방향 단언)" \
  [ "$(printf '%s\n' $IMPL_ROLES_SRC | sort | tr '\n' ' ')" = "$(printf '%s\n' "$IMPL_DECLARED" | tr '\n' ' ')" ]
# 채점자 집합(⑫ 의 GR_DECLARED)과 서로소인가. 겹치면 두 규칙이 같은 역할에 다른 허용
# 목록을 걸어 등재 순서가 곧 정책이 된다 — 그 상태는 문서로 드러나지 않는다.
impl_both=""
for a in $IMPL_DECLARED; do
  printf '%s\n' "$GR_DECLARED" | grep -qx -- "$a" && impl_both="$impl_both $a"
done
step "채점자 집합과 서로소다 (한 역할이 두 허용 목록을 갖지 않는다)" [ -z "$impl_both" ]
[ -n "$impl_both" ] && echo "    양쪽에 든 역할:$impl_both"
# 역할 정의 전수 시험 — 대상이면 차단(note 아닌 쓰기), 아니면 이 규칙이 답하지 않는다.
impl_leak2=""; impl_checked2=0
while read -r a; do
  [ -n "$a" ] || continue
  impl_checked2=$((impl_checked2 + 1))
  run "$(j_sub "bd -C $IMPL_H note $FX_TASK \"메모\"" "$a")"
  if printf '%s\n' "$IMPL_DECLARED" | grep -qx -- "$a"; then
    # note 는 이 역할에게 허용이다 — 여기가 막히면 절차 8 이 통째로 불가능해진다.
    [ "$GUARD_RC" -eq 0 ] || impl_leak2="$impl_leak2 note-blocked:$a"
  else
    # 나머지는 채점자라 ⑫ 가 막는다. 이 줄은 "note 통과"가 역할 전체에 퍼지지 않음을 본다.
    [ "$GUARD_RC" -eq 2 ] || impl_leak2="$impl_leak2 note-leaked:$a"
  fi
done <<< "$GR_AGENTS"
echo "  역할 ${impl_checked2}종에 note 를 돌렸다"
step "note 통과가 implementer 에만 걸린다" [ -z "$impl_leak2" ]
[ -n "$impl_leak2" ] && echo "    어긋난 역할:$impl_leak2"
step "전수 시험이 공허하지 않다 (역할 3종 이상)" [ "$impl_checked2" -ge 3 ]

# ── 겹침: 등재 순서로 메시지를 고른다. **이 절이 이 규칙의 설계 판단을 증명하는 자리다.**
echo "  ── 겹침 ──"
runimpl 'bd create x'
echo "  겹침(A4, 무-C 쓰기) → $GUARD_OUT"
step "무-C bd create(implementer) → rc=2" [ "$GUARD_RC" -eq 2 ]
step "그 메시지는 A5 쪽이다 (등재가 r_bd_root 앞이다)" has_text 'implementer 의 bd 쓰기 금지' "$GUARD_OUT"
# 순서가 뒤집히면 r_bd_root 가 "'bd -C <하네스루트> create …' 로 부르라"고 **금지된 행동을
# 지시**한다. 이 줄이 그 오도를 막는다.
step "메시지가 -C 를 붙이라고 오도하지 않는다"        lacks_text 'bd 원장 지정 누락' "$GUARD_OUT"
runimpl "bd note $FX_TASK \"메모\""
echo "  겹침(A4, 무-C note) → $GUARD_OUT"
step "무-C bd note(implementer) → rc=2" [ "$GUARD_RC" -eq 2 ]
# 이 줄이 "A5 를 앞에 두어도 A4 의 메시지가 죽지 않는다"의 근거다 — note 는 A5 가
# 통과시키고 A4 가 받는다. implementer 에게 그 지시(-C 를 붙여라)는 옳다.
step "note 는 A5 를 통과해 A4 메시지로 간다"          has_text 'bd 원장 지정 누락' "$GUARD_OUT"
step "그 메시지에 A5 문구가 섞이지 않는다"            lacks_text 'implementer 의 bd 쓰기 금지' "$GUARD_OUT"

runimpl 'bd dolt push'
echo "  겹침(A3/C2) → $GUARD_OUT"
step "bd dolt push(implementer) → rc=2"                [ "$GUARD_RC" -eq 2 ]
step "그 메시지는 원격 반영 쪽이다 (r_remote 가 앞이다)" has_text '원격 반영 금지' "$GUARD_OUT"
step "그 메시지는 A5 쪽이 아니다"                        lacks_text 'implementer 의 bd 쓰기 금지' "$GUARD_OUT"

run "$(j_sub "bd -C $IMPL_H note $FX_TASK \"메모\"" "$GR_R")"
echo "  겹침(A1/A2) → $GUARD_OUT"
step "같은 note 가 reviewer 에게는 차단된다"  [ "$GUARD_RC" -eq 2 ]
step "그 메시지는 채점자 쪽이다"              has_text '채점자의 bd 쓰기 금지' "$GUARD_OUT"
step "그 메시지는 A5 쪽이 아니다"             lacks_text 'implementer 의 bd 쓰기 금지' "$GUARD_OUT"

# ── 하위 명령을 못 읽는 입력의 위임. **r_impl_bd 는 그 자리를 스스로 막지 않고
#    r_bd_root 에 넘긴다** (두 함수가 같은 tr 문자 클래스로 같은 `bd` 토큰을 찾으므로
#    "occurrence 0개"인 입력 집합이 동일하다). 넘긴 자리가 실제로 막히는지, 그리고
#    **어느 규칙이 답했는지**를 함께 단언한다 — 5.1 변조 (f)가 무너진 자리가 여기다.
echo "  ── 하위 명령을 못 읽는 입력 (r_bd_root 에 위임) ──"
# 마지막 줄(절대 경로 호출)은 **한계가 아니다.** 초판은 한계 1(다른 이름·경로로 부르는 길)에
# 넣었는데 실측이 rc=2 였다 — 경로가 통째로 한 토큰이라 occurrence 가 0이 되고, 위임받은
# r_bd_root 가 막는다. `beads create x`(rc=0)와 갈리는 자리라 함께 둔다.
runimpl 'B=bd; $B create x'
step "차단(치환 우회 — 대입문): B=bd; \$B create x" [ "$GUARD_RC" -eq 2 ]
step "그 메시지는 치환을 지목한다" has_text '변수에 담아 부르는 형태' "$GUARD_OUT"
runimpl '/opt/homebrew/bin/bd create x'
step "차단(절대 경로 호출 — basename 이 bd 다): /opt/homebrew/bin/bd create x" [ "$GUARD_RC" -eq 2 ]
step "답한 것은 A5 다: /opt/homebrew/bin/bd create x" has_text "implementer 의 bd 쓰기 금지" "$GUARD_OUT"
for c in 'bash /tmp/bd-writer.sh' "$FX_Q_BDCREATE"; do
  runimpl "$c"
  step "통과(bd 가 실행 위치가 아니다): $c" [ "$GUARD_RC" -eq 0 ]
done
# **하위 명령 자리가 빈** 입력 — 옵션만 있거나(`bd --help`) 맨 `bd` — 는 도움말·버전 출력이라
# 읽기로 통과한다 (harness-2a5.3.1. 종전에는 "빈 하위 명령" 으로 A5 가 막았다 — harness-dj4 1·2·5번).
for c in 'bd --help' 'bd --version' "bd -C $IMPL_H" 'echo hi; bd'; do
  runimpl "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "통과(옵션만 있는 호출은 읽기): $c" [ "$GUARD_RC" -eq 0 ]
done

# ── harness-2a5.3.1 — 옵션만 있는 bd 호출과 gh 토큰 판정을 실행 위치 축으로 옮긴다.
#    acceptance 의 9건을 그대로 둔다: 통과 5건(종전 rc=2 — harness-dj4 1·2·5번, harness-fz1 의
#    `gh --version`·경로 끝 gh)과 차단 4건(옵션 뒤의 진짜 쓰기 하위 명령을 놓치지 않는다).
#    A/B 는 세 사본 — 각각 **한 수리만 종전 판정으로 되돌려** 통과 5건 중 어느 것이 그 수리 덕인지 귀속한다.
echo "── ⑬-2 harness-2a5.3.1: 옵션만 있는 호출은 읽기, gh 는 실행 위치로 판정 ──"
declare -a A31_PASS_ROLE=("$IMPL_T" "$IMPL_T" "$IMPL_T" "$GR_R" "$IMPL_T")
declare -a A31_PASS_CMD=(
  'bd --version; echo done'                # 1 옵션만 → 빈 하위 명령 → 읽기
  'bd --help > /dev/null 2>&1'             # 2 리다이렉션 대상(/dev/null)은 하위 명령이 아니다
  'bd --help | head -3'                    # 3 파이프 뒤 조각은 별개다
  'gh --version'                           # 4 선행 옵션만 → 빈 첫 토큰 → 읽기
  'chmod +x /tmp/x/gh'                     # 5 경로 끝의 gh 는 실행 위치가 아니다
)
for i in "${!A31_PASS_CMD[@]}"; do
  runrole "${A31_PASS_CMD[$i]}" "${A31_PASS_ROLE[$i]}"
  printf '  rc=%d  [%s] %s\n' "$GUARD_RC" "${A31_PASS_ROLE[$i]}" "${A31_PASS_CMD[$i]}"
  step "통과 $((i+1)): [${A31_PASS_ROLE[$i]}] ${A31_PASS_CMD[$i]}" [ "$GUARD_RC" -eq 0 ]
done
declare -a A31_DENY_ROLE=("$IMPL_T" "$IMPL_T" "$GR_R" "$IMPL_T")
declare -a A31_DENY_CMD=(
  'bd create x'                            # 6 r_impl_bd
  'bd --json create x'                     # 7 옵션 뒤의 진짜 쓰기 하위 명령을 놓치지 않는다
  'gh pr create --title x'                 # 8 r_remote
  'gh api repos/x/y --method POST'         # 9 r_remote 면제 밖
)
declare -a A31_DENY_MSG=("'bd create'" "'bd create'" "'gh pr create'" "'gh api repos/x/y'")
for i in "${!A31_DENY_CMD[@]}"; do
  runrole "${A31_DENY_CMD[$i]}" "${A31_DENY_ROLE[$i]}"
  printf '  rc=%d  [%s] %s\n' "$GUARD_RC" "${A31_DENY_ROLE[$i]}" "${A31_DENY_CMD[$i]}"
  step "차단 $((i+6)): [${A31_DENY_ROLE[$i]}] ${A31_DENY_CMD[$i]}" [ "$GUARD_RC" -eq 2 ]
  step "차단 $((i+6)) 의 메시지가 읽어낸 하위 명령을 싣는다: ${A31_DENY_MSG[$i]}" has_text "${A31_DENY_MSG[$i]}" "$GUARD_OUT"
done
# A/B 사본. 훅의 그 줄이 실재하는지(사본이 원본과 다른지)를 먼저 단언한다 — 줄이 없으면 sed 가
# 조용히 원본을 복사해 "되돌려도 통과" 가 되고, 그것이 수리의 부재가 아니라 A/B 의 부재로 읽힌다.
a31_copy() {  # a31_copy <이름> <sed 식> → 경로를 A31_AB 에
  local d="$TMP/wo-$1"; mkdir -p "$d/hooks"; A31_AB="$d/hooks/guard.sh"
  sed -E "$2" "$HOOK" > "$A31_AB"; chmod +x "$A31_AB"
  step "A/B 사본($1)이 원본과 다르다" not_same "$HOOK" "$A31_AB"
}
# (a) r_impl_bd 의 "옵션만 있는 호출은 읽기" 한 줄을 뺀다 → 1·3 이 종전대로 막힌다.
a31_copy 'bd-optonly' '/^r_impl_bd\(\)/,/^}/{/^    \[ -n "\$sub" \] \|\| continue$/d;}'   # r_bd_root 의 같은 줄은 남긴다 — 범위를 r_impl_bd 로 좁힌다
for c in 'bd --version; echo done' 'bd --help | head -3'; do
  runh "$A31_AB" "$(j_sub "$c" "$IMPL_T")"
  step "A/B(a) 되돌리면 다시 막힌다: $c" [ "$GUARD_RC" -eq 2 ]
done
runh "$A31_AB" "$(j_sub 'bd show x' "$IMPL_T")"
step "A/B(a) 사본도 읽기는 통과한다 (사본이 죽지 않았다)" [ "$GUARD_RC" -eq 0 ]
# (b) subcmds_after 의 리다이렉션 표지를 뺀다 → 2 의 /dev/null 이 다시 하위 명령으로 읽힌다.
a31_copy 'redir' 's/ __REDIR__ / /'
runh "$A31_AB" "$(j_sub 'bd --help > /dev/null 2>&1' "$IMPL_T")"
step "A/B(b) 되돌리면 다시 막힌다: bd --help > /dev/null 2>&1" [ "$GUARD_RC" -eq 2 ]
step "A/B(b) 의 메시지가 /dev/null 을 하위 명령으로 실었다 (종전 오탐의 재현)" has_text "'bd /dev/null'" "$GUARD_OUT"
# (c) gh 판정을 낱말 존재 축으로 되돌린다 — 실행 조각 대신 모든 조각을 보고, 빈 첫 토큰을 읽기로 보지 않는다
#     → 4(선행 옵션)·5(경로 끝 gh)가 종전대로 막힌다.
a31_copy 'gh-word' 's/done < <\(exec_segments gh\)/done < <(cmd_segments)/; /옵션만 있는 호출\(gh --version · gh --help\) — 읽기다/d'
step "A/B(c) 사본이 두 자리를 모두 바꿨다" [ "$(grep -cE 'exec_segments gh|gh --version · gh --help' "$A31_AB")" -eq 0 ]
runh "$A31_AB" "$(j_sub 'gh --version' "$GR_R")"
step "A/B(c) 되돌리면 다시 막힌다: [reviewer] gh --version" [ "$GUARD_RC" -eq 2 ]
runh "$A31_AB" "$(j_sub 'chmod +x /tmp/x/gh' "$IMPL_T")"
step "A/B(c) 되돌리면 다시 막힌다: chmod +x /tmp/x/gh" [ "$GUARD_RC" -eq 2 ]
runh "$A31_AB" "$(j_sub 'gh pr view 1' "$IMPL_T")"
step "A/B(c) 사본도 읽기는 통과한다 (사본이 죽지 않았다)" [ "$GUARD_RC" -eq 0 ]
# ── 옵션만 있는 bd 조각 **뒤에** bd 조각이 또 오는 형태. gr_bd_subcmds 가 조각을 이어 붙이면
#    첫 조각의 하위 명령 자리에 둘째 조각의 bd 가 들어와 'bd bd' 로 막힌다 [실측 2026-08-28, 배치
#    reviewer 가 `bd --version; bd list --status in_progress --limit 0 --json | jq …` 에서 rc=2].
#    r_grader_shell·r_impl_bd 가 그 함수를 공유하므로 두 역할로 본다.
for c in 'bd --version; bd show x' 'bd --version; bd list --status in_progress --limit 0 --json | jq -r .[].id'; do
  for role in $IMPL_T $GR_R; do
    runrole "$c" "$role"
    printf '  rc=%d  [%s] %s\n' "$GUARD_RC" "$role" "$c"
    step "통과(조각마다 읽는다): [$role] $c" [ "$GUARD_RC" -eq 0 ]
  done
done
# (d) gr_bd_subcmds 를 이어 붙이는 형태로 되돌린다 → 위 형태가 'bd bd' 로 다시 막힌다.
a31_copy 'bd-joined' '/^gr_bd_subcmds\(\)/,/^}/{s/^  while IFS= read -r seg; do subcmds_after bd "\$BD_VALUE_OPTS" "\$seg"; done < <\(exec_segments bd\)$/  subcmds_after bd "$BD_VALUE_OPTS" "$(exec_segments bd)"/;}'
runh "$A31_AB" "$(j_sub 'bd --version; bd show x' "$IMPL_T")"
step "A/B(d) 되돌리면 다시 막힌다: bd --version; bd show x" [ "$GUARD_RC" -eq 2 ]
step "A/B(d) 의 메시지가 다음 조각의 bd 를 하위 명령으로 실었다 (종전 오탐의 재현)" has_text "'bd bd'" "$GUARD_OUT"
runh "$A31_AB" "$(j_sub 'bd show x' "$IMPL_T")"
step "A/B(d) 사본도 읽기는 통과한다 (사본이 죽지 않았다)" [ "$GUARD_RC" -eq 0 ]

# ── 의도된 오탐. 진짜 차단과 **다른 배열**로 가른다 (⑧⑨⑩⑪⑫ 선례).
# 실행 위치가 아닌 bd 는 판정에 들지 않는다.
declare -a IMPL_NOT_EXEC=(
  'echo "bd create 를 쓰지 마라"'
  'grep -rn "bd close" docs/'
  'git log --grep "bd update"'
  "$FX_Q_BDUPDATE"
)
for c in "${IMPL_NOT_EXEC[@]}"; do
  runimpl "$c"
  printf '  rc=%d  %s\n' "$GUARD_RC" "$c"
  step "통과(실행 위치 아님): $c" [ "$GUARD_RC" -eq 0 ]
done

# ── 차단 메시지 (acceptance ⑤ — note 만 허용된다는 **사실**과 그 **이유**가 함께 적힌다).
runimpl "bd -C $IMPL_H create \"x\" -t task"
echo "  deny → $GUARD_OUT"
step "문제의 하위 명령이 실린다"              has_text "'bd create'" "$GUARD_OUT"
step "허용 목록을 훅 소스 값 그대로 알린다"    has_text "'$IMPL_ALLOW_SRC' 뿐이고" "$GUARD_OUT"
step "-C 가 면죄부가 아님을 밝힌다"            has_text '붙여도 그 밖의 쓰기는 금지' "$GUARD_OUT"
step "r_bd_root 와의 차이를 밝힌다"            has_text 'r_bd_root 와 다르다' "$GUARD_OUT"
step "읽기 면제 목록을 알린다"                 has_text "$BD_EXEMPT_SRC" "$GUARD_OUT"
step "이유(원장 구조의 소유)를 밝힌다"         has_text '오케스트레이터의 몫' "$GUARD_OUT"
step "막혔을 때의 대안을 지시한다"             has_text 'SIGNAL: DECISION_NEEDED' "$GUARD_OUT"
step "열려 있는 통로(note)를 함께 알린다"      has_text 'note <태스크ID>' "$GUARD_OUT"
step "note 의 우회 형태도 막힘을 밝힌다"       has_text '--append-notes' "$GUARD_OUT"
step "근거 문서를 인용한다"                    has_text 'agents/implementer.md' "$GUARD_OUT"
step "채점자용 문구가 섞이지 않는다"           lacks_text '채점자' "$GUARD_OUT"

# ── 막지 못하는 것. rc=0 을 **단언으로 박아 둔다** — harness-uhy.5.2 note "한계" 와 1:1.
declare -a IMPL_LIMIT_N=() IMPL_LIMIT_CMD=() IMPL_LIMIT_JSON=()
# 1 — 스크립트 경유 밀수. 훅은 `bash x.sh` 안의 명령을 이벤트로 보지 못한다 (harness-uhy.1.1 note).
IMPL_LIMIT_N+=(1); IMPL_LIMIT_CMD+=('bash /tmp/ledger-writer.sh')
IMPL_LIMIT_JSON+=("$(j_sub 'bash /tmp/ledger-writer.sh' "$IMPL_T")")
# 1 — 다른 이름으로 부르는 경로. 판정이 `bd` 토큰이라 이름이 다르면 규칙이 통째로 꺼진다.
IMPL_LIMIT_N+=(1); IMPL_LIMIT_CMD+=('beads create x')
IMPL_LIMIT_JSON+=("$(j_sub 'beads create x' "$IMPL_T")")
# 2 — 원장을 **bd 없이** 고치는 경로. 이 규칙은 bd 명령만 본다.
IMPL_LIMIT_N+=(2); IMPL_LIMIT_CMD+=("echo '{...}' >> $IMPL_H/.beads/issues.jsonl")
IMPL_LIMIT_JSON+=("$(j_sub "echo '{...}' >> $IMPL_H/.beads/issues.jsonl" "$IMPL_T")")
# 3 — `-C` 값의 옳고 그름을 보지 않는다. note 는 통과하므로 **아무 원장에나** 쓸 수 있다.
IMPL_LIMIT_N+=(3); IMPL_LIMIT_CMD+=('bd -C /wrong/ledger note x "hi"')
IMPL_LIMIT_JSON+=("$(j_sub 'bd -C /wrong/ledger note x "hi"' "$IMPL_T")")
IMPL_LIMIT_N+=(3); IMPL_LIMIT_CMD+=('bd --db /tmp/x.db note x "hi"')
IMPL_LIMIT_JSON+=("$(j_sub 'bd --db /tmp/x.db note x "hi"' "$IMPL_T")")
# 4 — note 의 **대상 이슈**를 보지 않는다. 남의 태스크·스토리에도 붙일 수 있다.
IMPL_LIMIT_N+=(4); IMPL_LIMIT_CMD+=("bd -C $IMPL_H note $FX_TASK_OTHER \"남의 태스크에 메모\"")
IMPL_LIMIT_JSON+=("$(j_sub "bd -C $IMPL_H note $FX_TASK_OTHER \"남의 태스크에 메모\"" "$IMPL_T")")
# 2 — 도구 경로로도 같다. Write 는 클론 루트 아래만 C3 가 보므로 하네스 원장 파일은 무방비다.
IMPL_LIMIT_N+=(2); IMPL_LIMIT_CMD+=("[Write 도구] $IMPL_H/.beads/issues.jsonl")
IMPL_LIMIT_JSON+=("$(j_tool_agent Write "$IMPL_H/.beads/issues.jsonl" "$IMPL_T")")
# 5 — 등록부 밖의 도구. 이 규칙은 Bash 에만 등재돼 있어 bd 를 감싼 MCP 도구가 생기면 꺼진다.
#     지금 그런 도구는 없지만, 생겼을 때 기본값이 "통과"임을 박아 둔다.
#     **쓰기 규칙(A1/A2·C3)은 같은 층에 있었으나 harness-qpx 에서 해소됐다** — 그쪽은
#     판정을 도구 이름이 아니라 "대상 경로를 받는가"로 옮길 수 있었다. 여기는 그럴 수 없다:
#     판정 대상이 경로가 아니라 **명령 문자열의 bd 하위 명령**이라 Bash 밖에는 그 문자열이
#     없다. 같은 해법이 안 되는 이유가 이것이고, 그래서 이 줄은 한계로 남는다.
IMPL_LIMIT_N+=(5); IMPL_LIMIT_CMD+=('[Bash 밖의 도구] mcp__bd__create')
IMPL_LIMIT_JSON+=("$(jq -n '{hook_event_name:"PreToolUse",tool_name:"mcp__bd__create",cwd:"/x",agent_id:"aa1",agent_type:"harness:implementer",tool_input:{title:"x",type:"task"}}')")
# 5 — agent_type 없는 위임. 판정 근거가 agent_type 값 자체라 규칙이 통째로 꺼진다 (⑫ 한계 4).
IMPL_LIMIT_N+=(5); IMPL_LIMIT_CMD+=("[agent_type 없는 위임] bd -C $IMPL_H create x")
IMPL_LIMIT_JSON+=("$(j_agentfields "bd -C $IMPL_H create x" 'aa306a4edf39e7dfe' '')")
# 6 은 **해소됐다** (harness-9tf). "허용·면제 목록의 낱말을 값으로 갖는 모르는 값-받는
#   옵션이 추출을 속인다" — `--actor note create` 의 값 `note` 가 하위 명령으로 읽혀
#   진짜 하위 명령(create)이 가려지던 형태다. 값-받는 전역 옵션 목록에 `--actor`·
#   `--dolt-auto-commit` 이 빠져 있던 것이 원인이었고, 지금은 목록이 `bd --help` 파생과
#   대조된다(⑧-값옵션 절). 차단 단언은 그 절이 든다 — 등재를 지우기만 하면 해소가
#   게이트에서 사라지므로 차단 쪽으로 옮긴 것이다.
for i in "${!IMPL_LIMIT_CMD[@]}"; do
  run "${IMPL_LIMIT_JSON[$i]}"
  printf '  rc=%d  [한계 %s] %s\n' "$GUARD_RC" "${IMPL_LIMIT_N[$i]}" "${IMPL_LIMIT_CMD[$i]}"
  step "한계(못 막음, rc=0 고정) ${IMPL_LIMIT_N[$i]}: ${IMPL_LIMIT_CMD[$i]}" [ "$GUARD_RC" -eq 0 ]
done
# 값이 하위 명령이 아닌 낱말일 때도 차단된다 — `--actor` 를 건너뛰면 그 다음이 진짜
# 하위 명령(create)이므로 A5 가 곧바로 잡는다. 종전에는 값 `bob` 이 하위 명령으로 읽혀
# 차단됐고(우연히 맞은 결과), 지금은 create 를 읽고 차단한다. 메시지가 그 차이를 낸다.
runimpl "bd -C $IMPL_H --actor bob create x"
printf '  rc=%d  --actor bob create x\n' "$GUARD_RC"
step "차단: --actor 값이 하위 명령이 아닌 낱말이어도 진짜 하위 명령을 읽는다" [ "$GUARD_RC" -eq 2 ]
step "읽어낸 하위 명령이 값이 아니라 create 다" has_text "'bd create'" "$GUARD_OUT"
# **한계가 아닌 것을 여기 적지 않는다.** `bd note` 로 위장한 원장 구조 변경은 확인해 보니
# 불가능하다 — `bd note --help` 가 "Shorthand for 'bd update <id> --append-notes'" 라고
# 밝히고, 플래그는 --file·--stdin(둘 다 note 본문의 출처)뿐이다. 그래서 note 를 연 것이
# 구조 변경 통로를 여는 것은 아니다. 대신 **대상 이슈를 못 고른다**는 것이 실제 폭이고,
# 그것이 위 한계 4 다.

# ── ⑯ 발화 로그 (S16) ────────────────────────────────────────────────
# 막는 것: **"발화 0" 과 "훅이 안 돌았다" 가 둘 다 무기록으로 보이는 상태.** 그 구분이
# 없으면 규칙의 값어치를 재는 계수가 사람의 기억뿐이다 (harness-pl7 S16).
# 그래서 통과도 한 줄 남기고, 로그 자체가 없으면 계수 명령이 비-0 으로 끝난다.
echo "── ⑯ 발화 로그 — 규칙 이름·회차별 계수·발화 0 대 훅 미실행 ──"
LG="$TMP/s16-log.tsv"
LOGSH="$ROOT/scripts/guard-log.sh"
FX_SESS="fx-sess-1"
TAB=$'\t'
LOG_CLONE="$TMP/log-clone"                      # 발화 프로브용 합성 클론 루트
WT_PROBE="echo x > $LOG_CLONE/repo/f.txt"        # r_main_shell 을 발화시키는 프로브 (오케스트레이터 입력에도 발화한다)
LOG_RULE="r_main_shell"
j_sess() {  # j_sess <명령> <session_id>
  jq -n --arg c "$1" --arg s "$2" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:"/x",session_id:$s,tool_input:{command:$c}}'
}
runlog() { runh "$1" "$2" "HARNESS_GUARD_LOG=$LG" "HARNESS_CLONE_ROOT=$LOG_CLONE"; }
# 열은 **위치로** 읽는다. `$NF` 로 읽으면 차단 줄에 6열(차단된 입력)이 붙는 순간 규칙
# 단언이 명령 문자열을 보게 되어 조용히 뒤집힌다 — 두 소비자(이 검사와 guard-log.sh)가
# 위치로 읽는다는 것이 그 열을 붙일 수 있게 하는 조건이다.
rulecol()  { awk -F'\t' 'END { print $5 }' "$LG"; }
evcol()    { awk -F'\t' 'END { print $6 }' "$LG"; }
ncols()    { awk -F'\t' 'END { print NF }' "$LG"; }
roundcol() { awk -F'\t' 'END { print $2 }' "$LG"; }

step "계수 명령이 실행 가능하다" test -x "$LOGSH"

# 기본 로그 경로가 두 파일에서 갈라지면 계수 명령이 빈 로그를 보고 "훅 미실행" 이라고
# 거짓말한다 — 아래 (a) 의 rc=1 이 그 순간 거짓 근거가 된다. 표현을 각각 파생해 맞춘다.
default_log_path() { sed -n 's/.*HARNESS_GUARD_LOG:-\([^}]*\)}.*/\1/p' "$1" | head -1; }
DEF_H=$(default_log_path "$HOOK"); DEF_L=$(default_log_path "$LOGSH")
echo "  기본 로그 경로: 훅=[$DEF_H] 계수=[$DEF_L]"
step "기본 로그 경로 파생이 공허하지 않다" [ -n "$DEF_H" ]
step "기본 로그 경로가 훅과 계수 명령에서 같다" [ "$DEF_H" = "$DEF_L" ]

# 훅을 합성 입력으로 돌리는 검사는 **전부** 훅이 $HOME 아래에 쓰는 상태 파일을 임시 경로로
# 돌려야 한다. 하나라도 빠지면 실사용 상태가 합성 발화로 위조되고, 이 커밋의 존재 이유가
# 그 자리에서 무너진다.
# 실측 2026-08-27: 이 절을 넣기 전 guardrail-check 가 커밋마다 18줄, session-cleanup-check
# 가 4줄을 실사용 로그에 넣고 있었다(둘 다 규칙별 차단 프로브라 "발화한 적 있다"로 읽힌다).
# 집합은 훅 경로를 언급하는 checks/*.sh 에서 파생한다 — 손으로 고른 목록은 새 검사가
# 늘 때 조용히 빠진다 (.claude/rules/agile.md 극성 반전).
HOOKRUNNERS=$(grep -l 'hooks/guard\.sh' "$ROOT"/checks/*.sh)
step "훅을 실행하는 검사 파생이 공허하지 않다" [ -n "$HOOKRUNNERS" ]

# **돌려야 할 변수도 손으로 적지 않는다** — 훅 소스에서 판다. 초판은 발화 로그 하나만
# 요구했고, 훅에 두 번째 $HOME 쓰기(세션→actor 매핑, harness-qih)가 생겼을 때 그 격리가
# 검사 한 곳에만 손으로 들어갔는데도 이 단언은 조용히 통과했다. 새 상태 파일의 기본값을
# "격리 요구됨" 으로 만드는 것이 이 파생의 목적이다 (극성 반전).
HOOKENVS_ALL=$(sed -n 's/.*{\(HARNESS_[A-Z_]*\):-\$HOME[^}]*}.*/\1/p' "$HOOK" | sort -u)
# 면제 — 훅이 **파일로 쓰지 않는** 값. 클론 루트는 경로 판정의 기준값이라 격리할 것이 없다.
HOOKENV_EXEMPT="HARNESS_CLONE_ROOT"
step "면제 키가 실제 파생 집합에 있다 (역방향 — 사라진 키를 면제해 두면 그 면제가 곧 침묵이다)" \
  bash -c 'printf "%s\n" $1 | grep -qx "$2"' _ "$HOOKENVS_ALL" "$HOOKENV_EXEMPT"
HOOKENVS=$(printf '%s\n' $HOOKENVS_ALL | grep -vx "$HOOKENV_EXEMPT" || true)
echo "  훅이 \$HOME 에 쓰는 상태 파일의 환경 변수: [$(printf '%s ' $HOOKENVS)] (면제: $HOOKENV_EXEMPT)"
step "그 환경 변수 파생이 공허하지 않다" [ -n "$HOOKENVS" ]
# 면제 — 훅 경로를 실행이 아니라 **데이터로만** 드는 검사(rules-check 의 R-REM 면제표 항목).
# 역방향 단언: 언급이 정확히 1건이고 그 줄이 배열 리터럴이다. 실행 줄이 생기면 면제가 깨진다.
HOOKRUNNER_DATA_ONLY="rules-check.sh"
for g in $HOOKRUNNERS; do
  if [ "$(basename "$g")" = "$HOOKRUNNER_DATA_ONLY" ]; then
    step "$(basename "$g") 는 훅 경로를 데이터로만 든다 (면제 역방향)" \
      bash -c '[ "$(grep -c "hooks/guard\.sh" "$1")" -eq 1 ] && grep -q "^ *\"hooks/guard\.sh\"" "$1"' _ "$g"
    continue
  fi
  for v in $HOOKENVS; do
    step "$(basename "$g") 가 $v 를 임시 경로로 돌린다" grep -q "^export $v=" "$g"
  done
done

# (a) 로그가 없으면 계수 명령은 비-0 — 빈 출력 rc=0 이면 "발화 0" 과 다시 섞인다.
#     아래 rc·문구는 **로깅이 있는 훅을 볼 때**의 값이다 — 대상을 CLAUDE_PLUGIN_ROOT 로 이 트리에
#     못박는다(계수 명령이 훅을 고르는 그 변수. 세션이 다른 값을 내보낸 채 돌리면 rc=3 이 나온다).
LOG_OUT=$(CLAUDE_PLUGIN_ROOT="$ROOT" HARNESS_GUARD_LOG="$TMP/s16-absent.tsv" "$LOGSH" 2>&1); LOG_RC=$?
step "훅 미실행(로그 부재) → 계수 명령 rc=1" [ "$LOG_RC" -eq 1 ]
step "훅 미실행 → 사유가 stderr 에 남는다" has_text "훅이 한 번도" "$LOG_OUT"

# (b) 통과 호출도 한 줄 남는다 — 이것이 "발화 0" 의 근거다
: > "$LG"
runlog "$HOOK" "$(j_sess 'git status' "$FX_SESS")"
step "통과 호출 rc=0" [ "$GUARD_RC" -eq 0 ]
step "통과 호출도 로그에 한 줄 남는다 (발화 0 의 근거)" [ "$(wc -l < "$LG")" -eq 1 ]
step "통과 줄의 규칙 열은 - 다" [ "$(rulecol)" = "-" ]
step "통과 줄은 5열이다 (차단 입력 열이 붙지 않는다 — 통과가 98% 라 줄 길이가 여기서 정해진다)" \
  [ "$(ncols)" -eq 5 ]
step "회차 열이 페이로드의 session_id 다" [ "$(roundcol)" = "$FX_SESS" ]
step "통과는 stdout 을 오염시키지 않는다" [ -z "$GUARD_OUT" ]

# (c) 차단은 **규칙 이름과 함께** 남는다. 차단 메시지에는 규칙 이름이 없으므로 로그가
#     유일한 귀속 경로다 (guard.sh 의 deny 주석 · harness-uhy.2.1 note 의 결론).
#     6열(차단된 입력)이 함께 남는 이유는 그 파일의 deny 주석이 든다 — 규칙 이름만으로는
#     정탐·오탐을 사후에 가릴 수 없다.
runlog "$HOOK" "$(j_sess "$WT_PROBE" "$FX_SESS")"
step "차단 호출 rc=2" [ "$GUARD_RC" -eq 2 ]
step "차단 줄에 규칙 이름이 남는다" [ "$(rulecol)" = "$LOG_RULE" ]
step "차단 줄은 6열이다" [ "$(ncols)" -eq 6 ]
step "그 6열이 차단된 입력이다 (오탐률 판정의 유일한 재료)" [ "$(evcol)" = "$WT_PROBE" ]

# (d) 계수가 기계값이다 — 회차 × 규칙 별 횟수 TSV
runlog "$HOOK" "$(j_sess 'git status' "$FX_SESS")"
LOG_OUT=$(CLAUDE_PLUGIN_ROOT="$ROOT" HARNESS_GUARD_LOG="$LG" "$LOGSH"); LOG_RC=$?
echo "  계수: $(printf '%s' "$LOG_OUT" | tr '\n' '|')"
step "계수 명령 rc=0" [ "$LOG_RC" -eq 0 ]
step "계수: 통과 2회가 <회차> - 2 로 나온다"        has_text "${FX_SESS}${TAB}-${TAB}2" "$LOG_OUT"
step "계수: 차단 1회가 <회차> $LOG_RULE 1 로 나온다" has_text "${FX_SESS}${TAB}${LOG_RULE}${TAB}1" "$LOG_OUT"
step "계수 출력이 두 행뿐이다 (여분의 행이 섞이지 않는다)" \
  [ "$(printf '%s\n' "$LOG_OUT" | wc -l)" -eq 2 ]

# (e) 한계 ② 를 박제한다 — session_id 없는 페이로드는 회차 열이 `-` 로 무너진다.
#     조용히 무너지지 않는다는 것이 요점이라 그 값을 여기 고정해 둔다.
: > "$LG"
runlog "$HOOK" "$(j_bash 'git status')"
step "[한계] session_id 없는 페이로드 → 회차 열이 - (계수가 총계로 무너지되 보인다)" \
  [ "$(roundcol)" = "-" ]

# (f) 상한 1 에서 회전이 로그를 비우면 안 된다. tail -n 0 이 통째로 비우고, 그 빈 로그는
#     (a) 에서 "훅이 한 번도 돌지 않았다"로 읽힌다 — 이 절이 없애려는 혼동 그 자체가
#     상한 값 하나로 되살아난다.
: > "$LG"
for _i in 1 2 3; do
  runh "$HOOK" "$(j_sess 'git status' "$FX_SESS")" "HARNESS_GUARD_LOG=$LG" "HARNESS_GUARD_LOG_MAX=1"
done
step "상한 1 에서도 로그가 비지 않는다 (회전이 '훅 미실행' 을 위조하지 않는다)" \
  [ "$(wc -l < "$LG")" -eq 3 ]

# (g) A/B 귀속 — 로깅 호출만 뺀 사본에서 (c) 가 무너진다. 차단(rc=2)은 그대로여야
#     차이의 원인이 로깅임이 귀속된다.
NO_LOG="$TMP/no-log.sh"
sed '/^[[:space:]]*log_guard /d' "$HOOK" > "$NO_LOG"; chmod +x "$NO_LOG"
step "A/B 전제: 사본이 원본과 다르다 (사본이 없거나 같으면 귀속이 공허하다)" \
  not_same "$HOOK" "$NO_LOG"
denies_without_log() {  # <훅> — 차단은 그대로인데 로그를 남기지 않는다
  : > "$LG"
  runlog "$1" "$(j_sess "$WT_PROBE" "$FX_SESS")"
  [ "$GUARD_RC" -eq 2 ] && [ ! -s "$LG" ]
}
step "A/B: 로깅을 뺀 사본은 차단은 그대로인데 로그가 비었다" denies_without_log "$NO_LOG"
: > "$LG"
runlog "$HOOK" "$(j_sess "$WT_PROBE" "$FX_SESS")"
step "A/B 대조: 원본은 같은 입력에서 로그를 남긴다" [ -s "$LG" ]

# ── ⑱ 부재의 두 원인 (S16-b) ────────────────────────────────────────
# 막는 것: **로그가 비었을 때 "훅 미실행" 과 "로깅 없는 guard.sh 가 발화 중" 이 같은
# 문구로 나오는 상태.** ⑯ (a) 는 앞의 하나만 본다. 뒤의 하나는 이 스토리에서 실제로
# 났다 — 로깅이 story 브랜치에만 있어 배선된 다른 트리의 훅이 아무것도 안 남겼고,
# 계수 명령은 그것을 "훅이 한 번도 돌지 않았다" 로 냈다 (harness-dg0.6.33). 전역 원장과
# 달리 **훅 코드는 트리 안에 있어 브랜치를 탄다.** 두 상태를 각각 재현해 문구로 가른다.
# 계수를 근거로 쓸 수 있는 조건은 docs/guardrail-verification.md 11절이 든다.
echo "── ⑱ 계수 명령의 부재 판정 — 훅 미실행 vs 로깅 없는 판 발화 ──"
S17="$TMP/s17"
mkdir -p "$S17/withlog/hooks" "$S17/nolog/hooks"
S17_WITH="$S17/withlog/hooks/guard.sh"
S17_NO="$S17/nolog/hooks/guard.sh"
cp "$HOOK" "$S17_WITH"
sed '/^[[:space:]]*log_guard /d' "$HOOK" > "$S17_NO"
S17_ABSENT="$TMP/s17-absent.tsv"        # 만들지 않는다 — 부재가 이 절의 입력이다

has_log_calls()  { grep -q '^[[:space:]]*log_guard ' "$1"; }
lacks_log_calls(){ ! has_log_calls "$1"; }

# 재현 전제. 사본이 원본과 같거나 없으면 아래 두 상태가 사실 한 상태라 귀속이 공허하다.
step "재현 전제: 로깅 뺀 사본이 원본과 다르다"        not_same "$HOOK" "$S17_NO"
step "재현 전제: 로깅 있는 판에 로깅 호출이 있다"      has_log_calls "$S17_WITH"
step "재현 전제: 로깅 없는 판에 로깅 호출이 없다"      lacks_log_calls "$S17_NO"
step "재현 전제: 로그가 실제로 없다"                   [ ! -e "$S17_ABSENT" ]

# 계수 명령을 두 상태에 각각 돌린다. 어느 훅을 보는지는 배선과 같은 변수로 정해진다
# (hooks.json 이 `${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh` 를 부른다).
runlogsh() {  # runlogsh <플러그인 루트> <계수 명령 경로> — LOGSH_OUT/LOGSH_RC 를 채운다
  LOGSH_OUT=$(CLAUDE_PLUGIN_ROOT="$1" HARNESS_GUARD_LOG="$S17_ABSENT" "$2" 2>&1); LOGSH_RC=$?
}
runlogsh "$S17/withlog" "$LOGSH"; A_OUT="$LOGSH_OUT"; A_RC="$LOGSH_RC"
runlogsh "$S17/nolog"   "$LOGSH"; B_OUT="$LOGSH_OUT"; B_RC="$LOGSH_RC"
echo "  훅 미실행: rc=$A_RC / 로깅 없는 판: rc=$B_RC"
step "훅 미실행 재현 → rc=1"                          [ "$A_RC" -eq 1 ]
step "훅 미실행 재현 → 사유가 '훅이 한 번도'"          has_text "훅이 한 번도" "$A_OUT"
step "로깅 없는 판 재현 → rc=3 (미실행의 1 과 다르다)" [ "$B_RC" -eq 3 ]
step "로깅 없는 판 재현 → 사유가 '로깅 없는 guard.sh'" has_text "로깅 없는 guard.sh" "$B_OUT"
step "로깅 없는 판 문구에 '훅이 한 번도' 가 없다"      lacks_text "훅이 한 번도" "$B_OUT"
step "훅 미실행 문구가 비어 있지 않다 (0건 통과를 실패로)"    [ -n "$A_OUT" ]
step "로깅 없는 판 문구가 비어 있지 않다 (0건 통과를 실패로)" [ -n "$B_OUT" ]
# 검사한 훅 경로를 문구가 밝혀야 한다 — 밝히지 않으면 "내 트리를 봤다" 와 "배선된 트리를
# 봤다" 가 구분되지 않아, 읽는 사람이 rc 를 근거로 쓸 수 있는지 판단할 수 없다.
step "훅 미실행 문구가 검사한 훅 경로를 밝힌다"        has_text "$S17_WITH" "$A_OUT"
step "로깅 없는 판 문구가 검사한 훅 경로를 밝힌다"     has_text "$S17_NO" "$B_OUT"

# A/B 귀속 — **구분 로직만** 뺀 사본에서 두 상태가 다시 한 문구로 합쳐진다.
S17_AB="$TMP/s17-nodisc.sh"
sed '/^  if \[ ! -r /,/^  fi$/d' "$LOGSH" > "$S17_AB"; chmod +x "$S17_AB"
step "A/B 전제: 사본이 원본과 다르다 (사본이 없거나 같으면 귀속이 공허하다)" \
  not_same "$LOGSH" "$S17_AB"
# 사본의 두 출력도 **경로 문자열 때문에** 완전히 같지는 않다 — 갈랐는지의 판정은 rc 가 진다.
discriminates() {  # <계수 명령> — 두 상태가 rc 로도 문구로도 갈리면 0
  local d_a_out d_a_rc
  runlogsh "$S17/withlog" "$1"; d_a_out="$LOGSH_OUT"; d_a_rc="$LOGSH_RC"
  runlogsh "$S17/nolog"   "$1"
  [ "$d_a_rc" -ne "$LOGSH_RC" ] && differs "$d_a_out" "$LOGSH_OUT"
}
no_discriminate() { ! discriminates "$1"; }  # step 의 첫 인자에 `!` 를 두면 그것이 명령
                                            # 이름으로 읽혀 "없는 명령"으로 실패한다
step "원본은 두 상태를 가른다"                          discriminates "$LOGSH"
step "A/B: 구분 로직을 뺀 사본은 가르지 못한다 (같은 단언이 비-0)" no_discriminate "$S17_AB"
# no_discriminate 는 "두 rc 가 같다" 만 요구한다 — 사본이 다른 이유로 죽어 양쪽에 같은 rc 를
# 내도 통과한다. 그것이 **고치기 전 판정으로 돌아간 것**인지까지 rc 로 박는다: 구분 로직이
# 없으면 로깅 없는 판도 rc=1 "훅 미실행" 으로 합쳐지는 것이 이 절이 막는 상태다.
runlogsh "$S17/nolog" "$S17_AB"
step "A/B: 사본의 rc 가 고치기 전 판정인 1 이다 (죽어서 같은 것이 아니다)" [ "$LOGSH_RC" -eq 1 ]
step "A/B: 사본이 두 상태를 '훅이 한 번도' 한 문구로 합친다" has_text "훅이 한 번도" "$LOGSH_OUT"
# 정상 대조군 — 사본이 **죽어서** 못 가른 것이 아니다. 죽음과 검출은 rc 만 보면 같은
# 값을 낼 수 있다(이 스토리에서 실측). 로그가 있을 때 원본과 같은 계수를 내는지로 가른다.
S17_LOG="$TMP/s17-fixture.tsv"
printf 't1\tfx-s17\ta\tBash\t-\nt2\tfx-s17\ta\tBash\tr_x\n' > "$S17_LOG"
S17_ORIG_CNT=$(CLAUDE_PLUGIN_ROOT="$ROOT" HARNESS_GUARD_LOG="$S17_LOG" "$LOGSH"); S17_ORIG_RC=$?
S17_AB_CNT=$(CLAUDE_PLUGIN_ROOT="$ROOT" HARNESS_GUARD_LOG="$S17_LOG" "$S17_AB"); S17_AB_RC=$?
step "정상 대조군: 원본이 픽스처 로그를 rc=0 으로 센다"  [ "$S17_ORIG_RC" -eq 0 ]
step "정상 대조군: 계수가 비어 있지 않다"                [ -n "$S17_ORIG_CNT" ]
step "정상 대조군: 사본도 픽스처 로그를 rc=0 으로 센다 (사본은 살아 있다)" \
  [ "$S17_AB_RC" -eq 0 ]
step "정상 대조군: 사본의 계수가 원본과 같다" [ "$S17_AB_CNT" = "$S17_ORIG_CNT" ]
exit $fail
