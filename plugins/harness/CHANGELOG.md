# Changelog

## Unreleased — 하네스 루트 레포 폐기 (스토리 `skills#105`)

**폭 판단 — MAJOR.** 설치본이 손으로 할 일이 있다(아래 "설치본이 할 일"). 하네스 루트가 git 레포에서 **클론 루트 직속의 평범한 디렉토리**로 내려갔고, 등록부가 원장 어댑터 뒤로 들어갔으며, 하네스가 심던 git 훅 넷이 사라졌다. 옛 배치 그대로 두면 `lib/harness-root.sh` 가 루트를 못 찾아 **모든 원장 호출이 rc≠0** 이 된다.

### 등록부가 어댑터 인터페이스 뒤로 갔다 (`skills#141`~`#150`)
- **`ledger.sh rails --json` → `[{id, owner}]` · `ledger.sh sprints --json` → `[{id, status}]`.** 코어(`board.sh`·`board-check.sh`·`status` 스킬)는 이 둘만 알고 등록부 파일을 열지 않는다. 파생은 백엔드의 몫이다 — `github` 은 epic 의 `rail:` 라벨 + assignee 와 Projects v2 Iteration 필드, `notion` 은 페이지 속성, `beads` 는 하네스 루트의 `rails.json`·`sprints.json`.
- **`repos.json` 이 셋으로 갈렸다.** 클론 목록(`name`·`url`)만 클론 루트 직속 머신 로컬로 남고, **게이트 명령·기본 브랜치·부트스트랩은 대상 레포 자신의 `.harness.json`** 이 소유한다. 이슈 라우팅은 없앴다 — `repo:` 라벨과 `ledger.json` 의 `owner` 로 `owner/name` 이 파생된다.
- **`ledger.json` 이 클론 루트 직속 머신 로컬 한 파일**이고 `{backend, owner, project}` 셋이다. 그 자리에 있다는 사실이 곧 하네스 루트의 표지이며, `scripts/repo.sh root` 만 쓴다(가드가 손으로 쓰는 것을 막는다).

### 하네스 루트가 클론 루트가 됐다 (`skills#151`·`#153`)
- **`lib/harness-root.sh` 의 탐색이 두 단계다** — `HARNESS_ROOT` → `${HARNESS_CLONE_ROOT:-~/.harness-workspace}` 직속의 `ledger.json`. CWD 를 거슬러 올라가지 않으므로 어디서 불러도 답이 같고, 못 찾으면 rc 1 과 stderr 한 줄이다(조용한 폴백 없음). `<클론루트>/.harness-root` 포인터 파일과 `repo.sh apply` 는 없앴다.
- **`.beads/redirect` 는 beads 백엔드 안에서만 산다** — `ledger.sh wire-worktree` 가 쓰고 `bd` 가 읽는다. 루트 판별에는 쓰이지 않는다.
- **`rules-check` 의 S12(하네스 루트 `.gitignore` 규약)가 폐기됐다** — 하네스 루트가 git 트리가 아니라 대조할 대상이 없다.

### 투영과 git 훅 (`skills#152`·`#153`)
- **자기 UI 를 갖는 백엔드에서는 `board.sh` 가 아무것도 그리지 않는다.** 판단은 어댑터의 새 하위 명령 `has-ui` 가 하고, 코어는 백엔드 이름을 알지 않는다. `github`·`notion` 에서는 rc 0 과 "무엇을 하지 않았는지" 한 줄이다.
- **하네스는 이제 어디에도 git 훅을 심지 않는다.** 하네스 루트의 `pre-commit`(board-check) · `pre-push`(사라지는 추적 파일 + ledger-check 쓰기 모드) · `post-merge`·`post-checkout`(투영 렌더) 넷이 존재 이유와 함께 사라졌다. `board-check`·`ledger-check` 와 원장 반영은 **사이클 종결의 명시 단계**다(`harness:develop` "사이클 종결"). `LEDGER_CHECK_PUSH=1` 은 남지만 자동으로 켜는 자리가 없다.

### 워크트리 이름 (`skills#172`)
- **`lib/worktree-name.sh` 가 스토리 ID → 워크트리 이름 변환의 유일한 자리다.** `EnterWorktree` 의 `name` 이 `#` 을 받지 않아 github 형식 ID(`<repo>#<번호>`)를 그대로 쓰면 도구가 거부한다. 허용 문자 밖을 전부 `-` 로 바꾼다(`skills#105` → `skills-105`, 브랜치 `worktree-skills-105`). 가드의 차단 문구와 문서의 경로 표기도 `<워크트리 이름>` 으로 맞췄다.

### 문서 (`skills#154`·`#155`)
- **`docs/architecture.md` 가 플러그인 `docs/` 로 왔다.** 구성 요소 표에서 하네스 루트 레포에 묶여 소멸한 넷(`plugin-root.sh` · harness root 전용 git 훅 · 하네스 루트 `.claude/settings.json` · beads 아카이브)이 빠지고, 대상 레포의 `.harness.json` 행과 `lib/worktree-name.sh` 행이 새로 섰다.
- 플러그인 전역에서 등록부를 "하네스 루트의 파일" 로 서술하던 자리, 하네스 루트를 git 레포로 전제하던 자리, 투영을 무조건 그린다고 말하던 자리를 걷었다.

### 설치본이 할 일 — 이 순서대로

1. **머신 로컬 원장 지정 파일을 만든다.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh root --backend <github|beads|notion> [--owner <소유자>] [--project <번호>]` → `~/.harness-workspace/ledger.json`. **손으로 쓰지 않는다** — 가드가 클론 루트 직속 쓰기를 막는다. 이 파일이 없으면 `lib/harness-root.sh` 가 rc 1 이고 모든 원장 호출이 죽는다.
2. **등록부를 새 자리로 옮긴다.** 대상 레포마다 `bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh add <url>` — `~/.harness-workspace/repos.json` 에 `name`·`url` 로만 등재된다. 이미 클론이 있으면 그 자리를 그대로 쓴다.
3. **대상 레포에 `.harness.json` 을 만든다.** 그 레포 루트에 `{"check": "<게이트 명령>", "default_branch": "<기본 브랜치>"}`(필요하면 `bootstrap`). **그 레포에 커밋한다** — 하네스가 소유하는 파일이 아니다. 없으면 `repo.sh check <이름>` 이 경로를 들고 rc≠0 이다(폴백 없음).
4. **옛 하네스 루트를 정리한다.** 그 디렉토리의 `ledger.json`·`repos.json`·`rails.json`·`sprints.json`·`.claude/settings.json`·`scripts/plugin-root.sh` 와 `.beads/hooks/` 의 git 훅 넷은 이 판이 읽지 않는다. `beads` 를 계속 쓴다면 `.beads/` 의 원장 자체는 남긴다. `core.hooksPath` 를 그 훅 디렉토리로 물려 뒀다면 해제한다(`git config --unset core.hooksPath`).
5. **`permissions.deny` 를 옮긴다.** 옛 하네스 루트의 `.claude/settings.json` 에 있던 비밀 파일 차단 10줄은 하네스가 들어 줄 자리가 없어졌다 — 세션을 여는 트리(대상 레포 클론) 자신의 `.claude/settings.json` 에 넣는다.

**전환 기간에는 양쪽 자리가 함께 선다.** 새 자리의 파일을 만들어도 옛 자리를 지우지 않으면 이전 판 설치본과 새 판이 같은 원장을 함께 본다 — 그것이 이 개편을 수행한 스토리가 실제로 돈 방식이다. **옛 자리는 이 판이 설치본이 된 것을 확인한 뒤 4번으로 한 번에 치운다.** 무엇을 언제 치울지의 목록은 원장 `skills#151` 의 note 에 있다.

## 2.0.2 — 2026-09-06

직전 태그 `harness-v2.0.1` 뒤 `plugins/harness/` 의 커밋 하나 — `189f46c`(PR #120).

**폭 판단 — PATCH.** 설치본이 손으로 할 일이 없다. 새 스킬·검사·하위 명령이 없고, `harness:setup` 의 업데이트 절도 이 범위에서 바뀌지 않았다(diff 0). `claude plugin update` 하나면 끝난다.

### github 원장으로 이전한 직후 커밋이 막히던 것 (`harness-kw0l.3.2`)
- **`checks/board-check.sh` 가 종료 상태 면제(`TERMINAL_STATUS`)에 걸던 역방향 단언을 걷어냈다.** 그 단언은 면제 키가 원장에 1건 이상 실재하는지 확인하는데, 열린 항목만 옮기는 이전 직후에는 `closed` 가 정당하게 0건이라 그 한 줄로 `board-check` 가 rc 1 이 됐다. `board-check` 는 하네스 루트의 pre-commit 게이트이므로, 첫 태스크를 닫기 전 구간의 커밋이 전부 막힌다 — 실제로 이전을 수행한 커밋 자신이 그 구간에 있었고, `core.hooksPath` 가 옛 beads 루트를 가리킨 덕에 우연히 통과했다(그 세션이 스스로 "게이트 근거로 인용하지 않는다"고 기록했다). 지워서 사라진 보호는 없다 — 넓히는 쪽(과폭 면제)은 단언이 있던 때에도 잡히지 않았다.
- **`harness:develop` 의 "게이트는 면제 목록 형태로 쓴다" 규율에 그 예외를 박았다.** 역방향 단언이 성립하는 것은 면제 키가 **정적 산출물**(파일 경로·검사 이름)일 때뿐이고, 키가 런타임 데이터의 값(원장 상태·라벨)이면 개수 0 이 정당하므로 단언하지 않는다. 코드 주석에만 두면 다음 사람이 규율 위반으로 읽고 지운 줄을 되살린다.

## 2.0.1 — 2026-09-06

직전 태그 `harness-v2.0.0`(= `main` 의 `5f867c0`) 뒤 `plugins/harness/` 의 커밋 둘 — `c5bfa12`(회고 4건, PR #33) · `bcdead3`(이전 도구 보강, PR #34).

**폭 판단 — PATCH.** 설치본이 손으로 할 일이 없다. 새 스킬·검사·하위 명령이 없고, `harness:setup` 의 업데이트 절도 이 범위에서 바뀌지 않았다(diff 0). `claude plugin update` 하나면 끝난다.

### 회고 반영 (`harness-x7tb` · `harness-k4wg` · `harness-flm`)
- **전사 축이 통째로 죽어 있던 것을 살렸다.** `checks/transcript-check.sh` 의 VOCAB 키는 `agents/*.md` 의 파일명(`implementer`)인데 전사의 `attributionAgent` 는 플러그인 접두를 달고 온다(`harness:implementer`) — 모든 위임이 조용히 건너뛰어져 회고의 전사 축이 판정 0건이었다. 접두를 벗겨 맞추고, 알아보지 못한 역할은 침묵 대신 세어 미달 문구에 싣는다. 실측: 한 세션 전사에서 판정 0건 → 82/82.
- **`VERIFY_PENDING` 표시가 뒤따르는 note 에 풀리지 않는다.** 정지 가드(`hooks/stop-resume.sh`)·`checks/rules-check.sh` S22·`harness:develop` 3-2 의 판정 대상이 notes 의 마지막 줄에서 마지막 **표시 줄**로 바뀌었다. 같은 절차가 LGTM 수령과 판정 근거를 note 로 남기라 요구하므로, 마지막 줄로 읽으면 그 산문이 표시를 덮어 매번 손으로 보충해야 했다. `checks/guardrail-check.sh` 의 정지 가드 픽스처도 새 규칙으로 옮겼다(재작업 픽스처 1개 추가).
- `harness:develop` 의 "인용 대신 자리를 가리킨다"에 **명령의 형태와 옵션 의미**도 같은 규율임을 이었다 — 기억으로 쓴 `-F`/`-f` 의미가 위임에 실려 구현자가 되받아친 일이 있었다.
- `harness:plan-story` 5절(수 규율)에 **완료 조건은 측정한 값이 아니라 측정하는 명령을 적는다** 한 줄. 계획 시점의 수를 얼려 넣으면 판정 시점에는 트리와 원장이 움직인 뒤라 아무도 다투지 않는 수에서 항목이 떨어진다.

### 원장 이전 도구 (`harness-kw0l.2.3`)
전수 이전(열린 항목 129건) 직전 실측으로 `scripts/ledger-migrate.sh` 를 셋 고쳤다. 총 gh 호출이 약 2311 → 약 560 이 된다.

- **`plan` 도 `apply` 도 원장 note 블롭을 줄 단위로 쪼개지 않는다** — 이슈당 코멘트 하나다(코멘트 1585 → 49). 가장 큰 블롭이 41001자로 GitHub 코멘트 한도 65536 안에 들어간다. `-F` 로 넘겨 41001자가 argv 를 타지 않는다.
- **`apply` 의 멱등 단위가 "이슈 생성"에서 "항목 완주"로 바뀌었다.** map 줄이 두 형태다 — 이슈 생성 직후 미완 줄 `<id> <repo>#<번호> PENDING`, 코멘트·Project 항목·부모·의존까지 끝난 뒤에만 완료 줄. 재실행은 미완 줄의 이슈를 지우고 그 항목을 처음부터 다시 만든다. 종전에는 코멘트 도중 죽으면 재실행이 그 항목을 통째로 건너뛰어 코멘트가 모자란 채 남고 `verify` 가 실패했으며, 도구 안에 복구 경로가 없었다.
- **지운 이슈의 되조회는 404 가 아니라 410 이다** — `gh: This issue was deleted (HTTP 410)`(실측 gh 2.98.0). 404 만 "이슈가 없다"로 읽으면 `delete` 에 성공하고 map 줄을 버리기 전에 죽은 재실행이 그 자리에서 영구히 멈춘다. 한 번도 없던 번호(404)와 지워진 번호(410)를 둘 다 "없다"로 읽고, 통신·인증 장애는 그대로 죽는다.
- **라벨을 (레포, 라벨) 합집합으로 모아 루프 앞에서 한 번씩 만든다** — 이슈마다 부르던 542회가 56회가 된다.
- `checks/ledger-migrate-check.sh` 에 미완 줄 청소 절이 생겼다. 가짜 gh 에 묘비(`<n>.gone`)를 넣어 지운 번호의 되조회가 410, 되삭제가 GraphQL `Could not resolve…` 를 실측 문구 그대로 내게 했다.

### 곁들여
- `harness-kw0l.2.3` 의 `repo:` 라벨 2개를 1개로 줄였다(`rules-check` R5 rc 1 → 0) — 사이클 중 만든 태스크가 `harness:plan-story` 2절의 좁히기를 건너뛴 자국이다.

## 2.0.0 — 2026-09-06

1.0.0 뒤 `plugins/harness/` 의 커밋 전수(스토리 `harness-m8gg` 의 M7 과 `harness-kw0l` 의 M0·M1·M2). 직전 태그 `harness-v1.0.0` 은 스쿼시 머지 전 브랜치 커밋을 가리켜 `main` 의 조상이 아니라, 훑은 범위는 1.0.0 을 실어 보낸 커밋(`648b90a`)부터다.

**폭 판단 — MAJOR.** 설치본이 손으로 할 일이 있다: 하네스 루트 `.gitignore` 에서 다섯 줄(`.claude/ralph-loop.local.md` · `.claude/ralph-cancel` · `.claude/stop-resume.log` · `.claude/stop-resume-cancel*` · `*.harness-bak`)을 지워야 한다. 이 판이 `harness:setup` 의 `.gitignore` 규약 문장에서 그것들을 뺐고 `rules-check` S12 는 규약과 실물을 **양방향**으로 대조하므로, 그대로 두면 S12 가 실패하고 커밋 게이트가 막힌다. 권고(필수는 아니다): 하네스 루트 `docs/` 의 `development.md` · `guardrails.md` · `guardrail-verification.md` · `operations.md` · `usecases.md` 를 지운다 — 이 판부터 플러그인이 자기 `docs/` 를 들고 있어 루트의 것은 낡은 사본이다(`architecture.md` 는 루트 소유로 남는다).

### 원장을 GitHub 로 옮기는 도구 (`harness-kw0l.2`)
- **새 스크립트 `scripts/ledger-migrate.sh`** — beads 원장의 열린 항목을 github 백엔드로 옮긴다. `plan`(읽기: 이슈 본문 첫 줄 `beads: <원 id>`, 부모가 계획 밖이면 둘째 줄 `beads-parent:`) · `apply`(쓰기: 위상 순으로 이슈 → Project 항목 → 코멘트 → sub-issue → blocked_by, map 파일로 멱등) · `verify`(map 의 id 마다 이슈를 읽어 전수 대조). 이슈 규약은 `scripts/ledger-github.sh` 머리 주석이 단일 소유이고 이 도구는 따른다.
- **새 검사 `checks/ledger-migrate-check.sh`** — 가짜 bd·gh 픽스처. 가짜의 응답은 실측 payload 형태를 낸다(코드가 기대하는 모양을 흉내 내면 결함을 못 잡는다). 세 하위 명령의 stderr 에 셸 오류가 없다는 단언을 포함한다.
- 검증은 검색·목록으로 하지 않는다 — 이슈 생성 직후 `gh issue list -l <라벨>` 은 5 중 3 만 냈고 `gh project item-list` 도 새 항목을 즉시 내지 않았다(실측). id 별 조회만 쓴다.

### 원장의 경계와 사거리 (`harness-kw0l.3`)
- **github 백엔드의 읽기가 Projects v2 소속으로 좁혀졌다.** 종전에는 `repos.json` 등재 레포의 이슈 전수를 훑어 그 레포의 하네스와 무관한 이슈가 원장으로 읽혔다. 소속은 이슈 쪽 `projectItems{project{number}}` 로 판정한다 — 프로젝트 쪽 목록과 달리 생성 직후에도 지연이 없다(실측).
- **정규화 JSON 에 `actor` 키**(세 백엔드) — github 는 마지막 `ACTOR:` 코멘트의 값, beads·notion 은 assignee. `hooks/stop-resume.sh` 가 `.actor // .assignee` 로 사거리를 좁힌다. github 의 assignee 는 로그인명이라 그것만으로는 세션을 가릴 수 없었다.
- `scripts/board.sh` 가 **닫힌 스프린트의 0건**을 실패로 읽지 않는다(활성 스프린트의 0건과 등재 없음은 종전대로 실패). **새 검사 `checks/board-render-check.sh`**.
- `harness:setup` 의 합류(B) github 분기, `harness:develop` 사이클 종결의 원장 반영, `harness:plan-sprint`·`harness:plan-story` 의 계획 채널이 백엔드 모양으로 갈린다(`bd dolt push` 직접 언급 0). `docs/operations.md` 에 "원장 이전" 절.

### 가드 (`harness-m8gg.8.5` · `harness-kw0l.3.4`)
- `r_main_shell` 의 읽기 전용 목록이 넓어졌다(`sed`·`jq`·`awk`·`sort`·`wc`·`find`·`git worktree list|config --get|branch --show-current|rev-parse|archive` 등)고, 인용 안의 괄호·파이프를 조각 경계로 읽던 결함, `sed`·`awk` 스크립트 본문의 쓰기 기능(`w`·`system`·`|`·`getline`)과 결합 옵션(`-I`·`-ro`·`--out=`)이 새던 자리를 막았다.
- **서브에이전트에게 `gh api` 는 통째로 차단이다** — 하위 명령이 아니라 임의 요청이라 명령 문자열로 읽기·쓰기를 가를 수 없다(파일 경유·치환 경유·평문 미끼로 세 번 우회가 났다). 원장은 `ledger.sh` 로 읽는다. 하위 명령이 곧 연산인 형태(`pr view`·`issue list`·`project item-list`·`field-list` 등)의 읽기 면제는 그대로다. 한계: 엔드포인트 토큰이 면제어와 겹치는 `gh api list`·`gh api search` 는 통과한다(닿는 것이 없어 악용 가치가 없다).

### 검사가 어느 트리를 보는가 (`harness-m8gg.8.1` · `.8.2` · `.8.4` · `.8.14`)
- `checks/rules-check.sh` 가 **원장은 하네스 루트에서, 트리 검사는 호출 CWD 의 트리에서** 읽는다. 시작 줄에 두 자리를 낸다. 머리의 검사 목록에 `[트리]`·`[하네스 루트]` 표지가 붙었다.
- `R-REM` 이 스캔 대상을 `git ls-files` 가 아니라 `find` 로 파생한다 — 설치 캐시처럼 git 트리가 아닌 플러그인 루트에서 0건이 되어 조용히 통과하던 것을 막는다. 0건이면 실패한다.
- `scripts/check-all.sh` 가 호출자 CWD 를 보존해 각 검사를 부른다 — 하네스 워크트리에서 돌린 게이트가 그 워크트리를 판정한다.
- `checks/workspace-check.sh`·`checks/workspace-cleanup-check.sh` 가 `scripts/workspace-cleanup.sh` 에 `HARNESS_ROOT` 를 넘긴다.

### 문서와 잔재 (`harness-m8gg.8.6` · `.8.11` · `.8.12` · `.8.15` · `.8.3`)
- **하네스 루트의 문서 다섯이 플러그인 안으로 들어왔다** — `docs/development.md` · `guardrails.md` · `guardrail-verification.md` · `operations.md` · `usecases.md`. 플러그인이 하네스 루트 문서를 가리키던 포인터 35줄이 자기 `docs/` 를 가리킨다.
- 설치되지 않은 루프 플러그인(`ralph-loop`)의 잔재를 걷어냈다 — `hooks/ralph-cancel.sh` 삭제, **Stop 훅이 둘에서 하나로**(훅 항목 5 → 4), `harness:develop` 의 "장기 실행" 이 `/loop` 하나를 든다. 규율 넷(사용자만 시작 · 안에서 멈추기는 재무장 안 함 · 밖에서 멈추기는 `stop-resume-cancel` 마커 · 재시도 상한은 note)은 그대로다.
- 스킬 10 · 역할 정의 3 · 주입 블록 · 옮겨온 docs 를 `toolkit:agent-doc-audit` 7기준으로 정리했다(역할 정의와 주입 블록의 영어화 포함). 실측·정정 이력·죽은 경로가 걷혔다.
- `harness:setup` 0절 분기표의 원본 판별자가 `VERSION` 에서 `ledger.json` 으로 바뀌었다(1.0.0 이 `VERSION` 을 걷어내 판별이 성립하지 않았다). 빈 디렉토리는 1절로 보내지 않고 사용자에게 묻는다 — 1절이 아직 tarball·`scripts/install.sh` 전제다.
- `checks/rdup-language-probe.sh` 삭제 — 그 프로브가 대조군으로 쓰던 "원천이 한국어라 한글 없는 파일은 못 옮긴다" 는 전제가 영어화로 사라졌다.

## 1.0.0 — 2026-09-05

발행 시점의 변경은 아래와 같다(skills 레포 `plugins/harness/`, 0.2.0 뒤 커밋 전수 + 스토리 `harness-m8gg`). 이 판부터 CHANGELOG 는 이 파일 하나이고 버전 원본은 `.claude-plugin/plugin.json` 하나다 — 0.2.0 까지의 항목은 하네스 루트에 있던 것을 그대로 옮겼다.

**폭 판단 — MAJOR.** 설치본이 손으로 할 일이 있다: 하네스 루트에 새 컨텍스트 파일 `ledger.json`({"backend": "beads|github|notion"})을 만들어야 하고(없으면 어댑터가 rc≠0, 폴백 없음), 하네스 루트 탐색의 판별자가 `.beads` 에서 `ledger.json` 으로 바뀌었으며, 플러그인 설치 범위가 user scope 하나로 옮겨져 프로젝트·로컬 등록을 걷어내야 한다(`harness:setup` 3.5). 절차는 `harness:setup` C 절.

### 원장 어댑터 — 코어가 beads 에서 떨어진다 (`harness-m8gg.4` · `.5`)
- **`scripts/ledger.sh`** 가 원장의 유일한 경계다. 하위 명령·인자·JSON 키는 `bd` 의 것과 같다(`ledger.sh --help`). 백엔드는 하네스 루트 `ledger.json` 의 `backend` 하나가 정한다 — `beads`(`scripts/ledger-beads.sh`, bd 위임) · `github`(`ledger-github.sh` — 이슈 · sub-issue 계층 · blocked-by 순서 · 라벨 · 코멘트 · Projects v2) · `notion`(`ledger-notion.sh` — REST + `NOTION_TOKEN`). 파일이 없거나 값이 셋 밖이면 rc≠0.
- 스킬 7 · 역할 정의 3 · 주입 블록 · 훅(`enter-worktree.sh` · `stop-resume.sh` · `guard.sh`) · `lib/harness-root.sh` · 검사 · 스크립트가 전부 `HARNESS_ROOT=<루트> ledger.sh …` 로 원장을 부른다. `bd` 를 직접 부르는 파일은 beads 백엔드뿐이다.
- `lib/harness-root.sh` 는 `bd where` 를 쓰지 않는다 — `HARNESS_ROOT` → CWD 위로 첫 `.beads/redirect` → `~/.harness-workspace/.harness-root` 순서, 판별자는 `ledger.json`.
- 워크트리 배선은 `ledger.sh wire-worktree`(beads 만 `.beads/redirect` 를 둔다), 원격 대조는 `ledger.sh sync-check [--push]`(`checks/ledger-check.sh` 가 부른다; github·notion 은 "원격 반영 대상 없음" rc 0).
- **새 검사 `checks/ledger-adapter-check.sh`** — 경계 · beads 동등성 · beads 왕복 · github 오프라인(가짜 gh) · notion 오프라인(가짜 curl).
- `hooks/guard.sh` 가 `ledger.sh` 쓰기도 본다(경로 접두 별칭 포함) — `r_bd_root` · `r_impl_bd` · `r_grader_shell` · `r_remote`(`sync-check --push` 차단).

### 설치 범위 — user scope 하나 (`harness-m8gg.2`)
- `scripts/repo.sh` 가 클론에 플러그인을 등록하지 않는다. 설치는 `claude plugin install harness@skills` 한 번(user scope)이고 `harness:setup` 이 그것을 지시한다.

### setup (`harness-m8gg.5.2`)
- 새 하네스는 `ledger.json` 을 만들고 백엔드별 원장 초기화로 갈라진다 — 기본은 `github`. 기존 하네스는 `backend: beads` 로 그대로 굴러간다.

### 보완 스킬 3종 (`harness-m8gg.6`)
- **`harness:triage`** — 스프린트 라벨 없는 열린 항목을 훑어 중복 쌍(제목 동일 · "문제" 첫 문장 동일) · 성립 안 하는 항목 · 스프린트 후보 순위를 제안표로 내고, 사용자 확인 뒤에만 반영한다.
- **`harness:status`** — 읽기 전용 한 화면: 활성 스프린트 · 스토리별 열린/닫힌 태스크 · in_progress 와 actor · blocked · 미해결 결정 · 종결 미완 스토리.
- **`harness:release`** — 플러그인 하나의 릴리스: 이전 태그부터 훑기 → 폭(PATCH/MINOR/MAJOR) → CHANGELOG 항목 + `plugin.json` version → validate → `chore(<name>): release <ver>` 커밋 → 로컬 태그 `<name>-v<ver>`. 태그 push · `gh release` 는 명시 지시.
- `harness:develop` "상태 주장의 근거" 에서 턴 종료 시 주체를 명시하라는 문단을 뺐다(`harness-m8gg.6.5`).
- 주입 블록의 절차 스킬 목록이 10종이다.

## 0.2.0 — 2026-09-05

발행 시점의 변경은 아래와 같다(`v0.1.2..HEAD`, PR #26~#55 + 스토리 `harness-lzs3`). `VERSION` 을 올리는 시점과 폭은 `docs/development.md` "릴리스" 절이 정한다. 이 판부터 코어는 Claude Code 플러그인 `harness@skills` 이고 그 버전(`plugin.json`)이 이 번호와 같다.

**폭 판단 — MINOR 로 둔다.** 규칙 문면으로는 MAJOR 다 — 설치 경로가 tarball 에서 마켓플레이스로 바뀌고, 하네스 루트에서 코어 트리(`.claude/skills`·`agents`·`hooks`·`rules`·`checks`·`scripts`)가 사라지며, 클론 루트에 새 파일(`~/.harness-workspace/.harness-root` · 클론마다 `.claude/settings.local.json`)이 필요하다. 넓히지 않는 이유: 릴리스를 받은 파생본이 0개이고 1.0 이전이라 부담을 질 대상이 없다. 사용자 결정(2026-09-05, 스토리 `harness-lzs3` "결정됨"). 파생본이 생긴 뒤 같은 종류의 변경은 MAJOR 다.

### 플러그인화 — 코어가 하네스 레포를 떠난다 (`harness-lzs3`)
- **코어는 플러그인 `harness@skills`** (skills 레포 `plugins/harness/`, 마켓플레이스 `skills`). 절차 스킬 7종(`harness:*`) · 역할 정의 3종(`harness:implementer`·`reviewer`·`evaluator`) · 훅(SessionStart 주입 블록 · PreToolUse `guard.sh` · PostToolUse(EnterWorktree) `enter-worktree.sh` · Stop `ralph-cancel.sh`·`stop-resume.sh`) · 검사 10종 · 스크립트(`board.sh`·`check-all.sh`·`guard-log.sh`·`repo.sh`·`workspace-cleanup.sh`) · `lib/harness-root.sh` 가 전부 거기 있다
- **하네스 레포는 하네스 루트만 남는다** — 원장(`.beads`) · 등록부(`repos.json`·`rails.json`·`sprints.json`) · `CLAUDE.md` · `docs/` · git 훅(`.beads/hooks/`) · `scripts/plugin-root.sh`. 삭제: `.claude/skills`·`.claude/agents`·`.claude/hooks`·`.claude/rules/agile.md`·`checks/` 전부·`scripts/`(install.sh·session-cleanup.sh·workspace.sh·board.sh·check-all.sh·guard-log.sh·repo.sh·workspace-cleanup.sh)·release-check
- **상시 로드는 주입 블록 하나** — `.claude/rules/agile.md`(24KB) 대신 플러그인 SessionStart 훅이 `hooks/session-context.md`(절대 금지 · 원장 위치 · 스킬·역할 목록 · 계층↔beads 매핑 · 나머지 규율의 소유자 표)를 싣는다. 절차 규율(운영 규율 · 상태 주장의 근거 · 사람 대기 · 사이클 종결 · 대상 레포의 관례 등)은 `harness:develop` 안으로 내렸다. `bd prime` SessionStart 훅은 뺐다
- **가드는 앵커와 무관한 불변식 넷만 남긴다** — 작업은 워크트리에서만(`r_main_write`·`r_main_shell`, 상대 경로는 payload cwd 로 판정) · 만든 주체가 채점하지 않는다(`r_grader_write`·`r_grader_shell`·`r_impl_bd`, 역할은 `harness:<이름>` 형식만 대조) · 원격은 사람이 연다(`r_remote`) · 원장 하나(`r_bd_root`). `r_worktree`·`r_core_write`·`r_bead_leak`·`r_bd_body` 삭제. 런타임 상태(정지 가드 로그·취소 마커)는 `${HARNESS_DATA_DIR:-~/.claude/plugins/data/harness}` 로 — 프로젝트 디렉토리에 아무것도 떨어뜨리지 않는다
- **파생 하네스 배포 장치 삭제** — `install.sh`(init·sync·check·update·pack·manifest) · `.harness-state` · `release-check` · `ensure-hookspath.sh`. 파생본이 할 일은 마켓 설치 하나다: `claude plugin marketplace add juhyeon-cha/skills` → `claude plugin install harness@skills --scope project`, 갱신은 `claude plugin marketplace update skills` + `claude plugin update harness@skills`
- 하네스 루트의 게이트(`repos.json` 의 `harness.check` · `.beads/hooks/pre-commit`·`pre-push`·`post-merge`·`post-checkout`)는 플러그인 루트를 `scripts/plugin-root.sh` 한 곳에서 해석해 부른다(`HARNESS_PLUGIN_ROOT` → 설치 캐시 → rc≠0). pre-commit 은 플러그인 `board-check`, pre-push 는 플러그인 `ledger-check`(쓰기 모드), 렌더는 플러그인 `board.sh all`

### 세션 단위와 워크트리 흐름
- **세션 단위는 (스토리, 레포)다.** 계획·회고 세션은 하네스 루트에서, 개발 세션은 대상 레포의 클론 루트(`~/.harness-workspace/<레포>`)에서 연다 — 대상 레포의 CLAUDE.md·규칙·스킬·훅이 그대로 로드된다. 멀티 레포 스토리는 레포마다 세션 하나, 조율은 원장(`ACTOR: <레포> <값>`). 하네스 자신의 개발도 같은 흐름이다
- **워크트리 생성은 네이티브 `EnterWorktree`** (`scripts/workspace.sh` 삭제). 브랜치는 도구가 정하는 `worktree-<스토리ID>`(`story/<ID>` 는 더 쓰지 않는다). 플러그인 PostToolUse 훅이 `.beads/redirect` 와 클론 `.git/info/exclude` 를 쓰고, 대상 레포에 자기 EnterWorktree 훅이 없을 때만 `repos.json` 의 `bootstrap` 을 1회 돌린다. 훅 실패는 exit 2 로 응답에 실린다
- **대상 레포에 하네스 git 훅을 심지 않는다** (`harness-v8n` 접음). 원장 검사(`board-check`·`ledger-check` 읽기 모드)와 원장 반영(`bd dolt push`)은 사이클 종결에서 오케스트레이터가 명시 단계로 돈다 — 대상 레포 push 가 지시인 순간이 승인 범위다
- 하네스 루트 발견은 `lib/harness-root.sh` 하나 — `HARNESS_ROOT` → `bd where`(redirect) → `~/.harness-workspace/.harness-root`(클론 루트 세션의 자리, `repo.sh` 가 쓴다)
- 정리는 `workspace-cleanup.sh`(worktree-<ID> 기준) · 하네스 루트의 세션 워크트리 정리(`session-cleanup.sh`)는 삭제

### 플러그인화 이전 0.1.2 이후의 변경 (PR #26~#55)
- 스프린트 2026-S01 종료 · 2026-S02 개시 · 레일 r2 등재 (#26 #27)
- `plan-story` 를 정밀 분해 절차로 — M0 스파이크 · 마일스톤 상한 5 · 착수 전 질문 라운드 · 스토리 본문에 담당자가 착수할 만큼 요구 (#28 #40)
- 정지 가드의 사거리를 원장 전체에서 **이 세션이 claim 한 actor** 로 좁히고 상태를 세션 단위로 가른다 (#30 #32) · 회고의 `transcript-check` 에 세션 한정(`--session`) (#43) · 1회성 관측은 백로그로 (#42)
- 감사 로그 사이드카(`.beads/interactions.jsonl`)를 git 추적에서 뺀다 (#29) · `board-check` 이 끝난 일에 남은 일의 조건을 요구하지 않는다 (#34)
- 스킬 7종을 writing-for-agents 규율로 영어화 (#49) · 상시 로드 17% 축소, 투영이 태스크 목록을 다시 읽힌다 (#38) · 코어 문서의 계수·정정 이력 17건 정리 (#46) · 주석·문서는 정정 이력 대신 현재 사실만 (#44)
- 대상 레포의 관례를 읽는 자리를 단일 소유로 세우고 plan-story·implementer·reviewer·사이클 종결에 배선 (67603e7) · sap-harness 워크트리의 에이전트가 원장·PR·기록처의 소유를 안다 (#39)
- `r_main_shell` 읽기 판정의 오탐 둘 제거 · 읽기 전용 명령 17종 승인 (#52 #53) · 게이트 미배선 안내 정정 (#54) · 갈라질 목록을 소유자·상수로 가리키게 (#55)
- 재발한 조용한 실패 셋에 최소 장치 (#37) · 머지가 만든 게이트 정합 구멍 둘 (#50) · 측정 공백을 메우고 게이트 배선을 전수로 뒤집음 (#48) · `docs/reviews` 를 원장과 코어 문서로 흘려보내고 삭제 (#36) · 원장 관리 문서(`dolt gc`·pull/push) (#44)

## 0.1.2 — 2026-08-28

발행 시점의 변경은 아래와 같다(`v0.1.1..HEAD`, PR #21~#25 + 직접 커밋 2). `VERSION` 을 올리는 시점과 폭은 `docs/development.md` "릴리스" 절이 정한다.

**폭 판단 — PATCH 로 둔다.** 1단계 ②의 setup diff 가 비어 있지 않다: `sprints.json`(스프린트 등록부)이 파생본이 새로 만들어야 하는 맥락 파일로 추가됐고 `setup` 3.3 에 그 손 작업이 생겼다 — 규칙 문면으로는 MAJOR 다. 넓히지 않는 이유: 릴리스를 받은 파생본이 아직 하나도 없어(`.harness-state` 를 가진 트리 0개, 2026-08-28 실측) 부담을 질 대상이 없고, 다음 설치는 A 분기라 5절이 `sprints.json` 을 만든다. 사용자 결정(2026-08-28). 파생본이 생긴 뒤 같은 종류의 변경은 MAJOR 다.

### 투영과 게이트
- **투영(`docs/sprints/`·`docs/backlog/`)을 git 밖으로** — `.gitignore` 된 생성물이고 `scripts/board.sh all` 을 post-merge·post-checkout 훅이 부른다. 커밋 게이트 = 강제 장치 검사 + 원장 구조 검사, push 게이트 = 원장 반영 + 사라지는 추적 파일(gitignore 무시 경로 제외). `plan-channel-check`·`board-drift-check`·`board-hash.sh` 삭제. ledger-check ↔ board-check 교착(`harness-zss`) 해소 (#24)
- **스프린트 등록부 `sprints.json`** — 스프린트 종료 여부의 유일한 원본(active/closed). board-check 이 원장 `sprint:` 라벨과 양방향 대조. 닫힌 이슈 개수로 종료를 판정하지 않는다 (#22)
- `guard.sh` 판정 축을 **낱말 존재 → 실행 위치의 하위 명령**으로 — `r_remote`·`r_worktree`·`r_main_shell`·`r_grader_shell`·bd 규칙 넷. 읽기 명령·인용문 오탐과 채점자 git 쓰기 미탐을 닫음. 옵션만 있는 `bd` 호출과 `gh` 토큰 판정도 같은 축 (#24, #25)
- `guard.sh` 인용부호·백슬래시 정규화 · 대소문자 접기 · 훅 내부 오류를 rc=2 로(fail-open 제거) · 정지 가드 마커를 세션 귀속형으로 (#24)
- **정지 가드·rules-check S22 가 검증 대기(`VERIFY_PENDING`) 태스크를 알아본다** — 배치 모드에서 구현 완료·검증 대기 태스크가 in_progress 로 쌓여도 가드가 막지 않고, S22 는 같은 actor 의 순차 작업을 한 레인으로 센다 (#25)
- M6 게이트: rules-check 에 R-ACC·R-REM·C6·R40·S22·S24·R-DATE·R-BEAD·R-WAIT, `checks/transcript-check.sh`(전사를 읽는 자리), `docs/usecases.md` UC-1~UC-11 (#22)

### 개발 루프
- **verify 의 단위를 태스크에서 마일스톤으로** — 배치 조건(단일 레포·태스크 4건 안팎)이면 마일스톤의 태스크 전부를 구현한 뒤 reviewer·evaluator 를 1회씩. 구현도 implementer 한 명에게 태스크 목록으로 위임(태스크마다 커밋 + `VERIFY_PENDING` note). 실측: verify 에이전트 11→3, verify 토큰 −63% (#25)
- `plan-story` 에 1절 끝 승인 관문 · 스토리 크기 상한(한 스토리 = 한 PR = 마일스톤 3개 안팎) · 태스크 크기 규칙 (#25)
- 병렬 도구 호출 규율을 역할 정의에 · 게이트 1회 실행과 rc 를 커밋에 묶기 · 재검토는 새 reviewer 인스턴스 · 위임 메시지에 환경 스냅샷(HEAD·워킹 트리) · 재검토 상한 3→2 (#21)
- 역할 최종 응답 30줄 상한 · 위임 메시지 25줄 상한 · evaluator 모델을 sonnet 으로(A/B 실측: 판정 동일, 토큰 수는 티어 무관) (#23)
- `retrospective` 입력에 서브에이전트 전사 집계(`transcript-check.sh` 호출) 추가 (#25)
- 사이클 종결: 클론 워크트리 push 에 `BEADS_DIR=<하네스루트>/.beads` — 조상에 원장이 없어 원장 반영이 건너뛰어지던 것 (69f34c3)

### 지시문
- `agile.md` 44.7KB→22.6KB, `CLAUDE.md` 14.5KB→6.9KB — 규칙 문장만, 근거는 bead 포인터. BEADS INTEGRATION 관리 블록 제거 (#24)
- implementer 의 "인용 숫자는 세고 쓴다"·확인 여부 명시를 주석·문서까지로 확장 (bd7ee31)
- 백로그 정리: `harness-zss`·`mzt`·`k08`·`fnv`·`1e7`·`dj4`·`fz1`·`8m2`·`94g`·`ud4` 닫음, 죽은 브랜치 7개 삭제

## 0.1.1 — 2026-08-27

발행 시점의 변경은 아래와 같다. `VERSION` 을 올리는 시점과 폭은 `docs/development.md` "릴리스" 절이 정한다.

- **`setup` 스킬 A 분기에 "설치 절차는 implementer 서브에이전트에게 통째로 위임할 수 없다" 를 명시** — 원장 초기화(1.6)와 원장을 요구하는 검사가 `guard.sh` 의 `r_impl_bd` 에 rc=2 로 막힌다. 난간의 정상 동작이므로 이 절차는 사람 또는 오케스트레이터 세션이 수행한다 (실측 2026-08-27, `harness-u9n.5.1`)
- **정정 (2026-08-27)**: 아래 0.1.0 항목의 "**개발 중이며 아직 어떤 프로젝트도 설치하지 않았다** — 발행 전까지 변경은 이 항목에 누적한다" 는 발행 전 시점의 서술이라 지금은 참이 아니다. 0.1.0 은 2026-08-27 에 발행됐고 그것으로 파생 하네스를 세웠다. 발행된 이력이라 원문은 고치지 않고 여기에 정정만 남긴다

## 0.1.0 — 2026-08-27

첫 이식 가능 버전. **개발 중이며 아직 어떤 프로젝트도 설치하지 않았다** — 발행 전까지 변경은 이 항목에 누적한다. `VERSION` 을 올리는 시점과 폭은 `docs/development.md` "릴리스" 절이 정한다.

### 애자일 계층과 실행

- 애자일 계층(스프린트→레일→스토리→마일스톤→태스크)을 beads 라벨·타입 규약으로 표현 (`.claude/rules/agile.md`)
- 절차 스킬 7종: plan-sprint · plan-story · develop · verify-code · verify-implement · retrospective · setup
- 역할 정의 3종: implementer · reviewer · evaluator (첫 줄 `SIGNAL:` 프로토콜)
- **재시도 카운터를 `bd note` 에 영속** — 형식 `RETRY: <단계> <n>/<상한>`. 상한이 스킬 세 곳에 있었으나 카운터를 어디 남기는지가 없었다. 오케스트레이터의 기억에만 두면 세션 압축·루프 재시작에서 0 으로 돌아가 같은 지적으로 무한히 도는 경로가 열린다
- **상태 주장의 근거** — "게이트가 통과했다"와 "일이 됐다"는 다르다. 주장 유형별로 근거가 될 수 없는 신호(부분 실행의 rc, 명령 호출 자체)와 실제로 확인할 것(범위 전체의 rc, 재생성본 diff, 원격 tip SHA, `bd show` 상태)을 표로 고정했다. 확인할 수 없으면 낙관적으로 쓰지 않고 확인하지 못했다고 쓴다
- **결정 상태** — 사용자가 "안 한다"로 명시적으로 닫은 항목은 완료도 미완도 아닌 제3의 상태(beads `deferred`)다. 남은 작업 목록에서 제외하고 완료 판정을 막지 않는다. pending 으로 뭉개면 같은 정정을 반복하게 만든다
- **진단 가설 규율** — 검증 전에는 "가설"로 쓰고, 대조군을 쓰기 전에 동등성을 확인하며, 진단 시도는 2회까지. 재시도 카운터가 재작업 상한인 것과 달리 이것은 진단 상한으로 별개로 센다
- ralph 루프 종료 규율과 취소 마커 훅 (`.claude/hooks/ralph-cancel.sh`)

### 멀티 레포

- **레포 등록·클론 도구 `scripts/repo.sh`** — `add <url>` 이 클론과 `repos.json` 등재를 함께 한다. 클론 위치는 `~/.harness-workspace/<이름>` 으로 고정하고 경로를 손으로 적지 않는다. (계기: 손으로 적어둔 `~/workspace/sap-harness` 가 실제로는 없었다 — "등재됐다"와 "클론이 있다"가 조용히 갈라진다.) `list` 는 둘을 함께 보이고, `remove` 는 등록만 해제하며 클론 디렉토리는 남긴다
- 스토리 워크트리: `~/.harness-workspace/<레포>/.claude/worktrees/<story-id>/`, 브랜치 `story/<id>`, 기준은 **원격 기본 브랜치의 최신 커밋**(낡은 로컬 HEAD 에서 분기하지 않는다). 그 경로는 클론의 `.git/info/exclude` 에 넣는다 — `.gitignore` 는 대상 레포가 소유한 추적 파일이라 하네스가 고치지 않는다
- `workspace.sh` stdout 은 `<레포이름>\t<절대경로>` 목록. 멀티 레포 스토리는 워크트리가 레포별로 흩어져 단일 루트가 존재하지 않는다
- **워크트리가 하네스 밖에 있으므로 하네스 루트를 위임 메시지로 전달한다** — 하위 에이전트의 `bd -C <하네스루트>` 유일한 출처. 역할 정의에 "워크트리의 부모가 곧 본 체크아웃" 경고를 함께 둔다
- 레일 등록부 `rails.json` · 대상 레포 등록부 `repos.json`(name·url·default_branch·check)
- **태스크의 `repo:` 라벨은 정확히 1개** — 멀티 레포 스토리의 태스크는 상속으로 라벨 여러 개를 받아 어느 워크트리로 위임할지 판정할 수 없다. plan-story 가 좁히고(두 레포를 다 고치는 태스크는 레포 경계로 쪼갠다), develop 은 여러 개면 착수를 거부한다
- **태스크 선점은 `bd update --claim`** — `--status in_progress` 는 두 세션이 동시에 성공해 중복 작업이 된다. claim 은 원자적으로 한쪽만 성공하고 assignee 까지 기록한다 (실측: 두 번째 선점이 `already claimed` 로 거부). 거부되면 그 태스크를 건너뛰고 다음으로
- **하위 에이전트의 bd 규약** — `-C <하네스루트>` 없는 호출 금지(워크트리 부모가 자체 beads 를 쓰면 bare `bd` 가 조용히 그쪽 원장에 붙는다 — `create` 는 엉뚱한 원장에 조용히 성공한다, 실측), implementer 쓰기는 `note` 만, reviewer·evaluator 는 읽기만. 세션은 하네스 루트에서 열고 워크트리는 경로로 다룬다

### 문서와 게이트

- **핵심 가치 usecase 카탈로그 `docs/usecases.md`** — 멀티 레포 · 멀티 워크트리/세션 · 원장 공동 관리 · 자가개선 4축을 사람이 밟는 순서(UC-1~UC-11)로 못박고, 각 usecase 에 액터·단계·성립 판정 기준을 붙였다. 판정 기준은 "명령 + 기대 종료 코드" 또는 "파일·상태의 존재" 두 형태로만 적는다 — 구조가 핵심 가치를 지탱하는지 판정할 기준이 없으면 같은 뿌리의 결함이 다른 얼굴로 반복 등재된다
- 스프린트 문서 렌더러 `scripts/board.sh` — beads → `docs/sprints/<YYYY-SNN>/` 결정론적 투영(같은 bd 상태 = 같은 바이트), frontmatter 메타데이터. **스토리 디렉토리는 슬러그** — 레일 ID 를 경로에 넣으면 레일 개명 시 과거 경로·외부 링크가 전부 바뀐다. 접두사가 사라진 대신 스프린트 안 슬러그 유일성을 렌더가 단언한다 (충돌 시 rc=1)
- **태스크 note 도 렌더한다** — reviewer 의 NIT, evaluator 의 판정 근거, `RETRY:` 카운터가 전부 태스크 note 에 쌓이는데, 스토리 note 만 렌더하면 하네스의 주요 기록이 사람용 투영에서 통째로 빠진다
- **JSON 은 `printf '%s' |` 로 jq 에 파이프** — `echo "$var" |` 는 backslash 확장 셸(sh·xpg_echo)에서 필드 안 `\n` 을 raw 제어문자로 바꿔 jq 가 rc=5 로 죽는다 (실측). 셸 함정 규율은 `docs/development.md`
- `checks/workspace-check.sh` — 워크트리 생성·재사용·부트스트랩의 핵심 경로 (위치·브랜치·기준 커밋·멱등·재사용 거부·마커 재시도·등록부 누락)
- `checks/board-check.sh` — 문서 신선도 양방향 대조 + **스프린트 라벨의 하위 상속**. bd 는 이슈를 **만들 때만** 부모 라벨을 물려주므로, 이미 분해된 백로그 스토리를 나중에 편입하면 하위에 라벨이 붙지 않고 `board.sh` 가 **마일스톤 0개로 렌더하면서 종료 코드 0 으로 성공한다.** 신선도 대조는 같은 board.sh 로 재생성해 diff 하므로 이 누락을 잡지 못한다 — 조용한 실패라 별도 단언을 둔다
- `checks/guardrail-check.sh` — **강제 장치 자체의 검사**. 게이트가 없어진 상태와 통과한 상태는 둘 다 "아무 일 없음"으로 보이므로, 난간(훅 규칙 9종·훅 배선·`permissions.deny`·플러그인·검사 스크립트 실물·커밋 게이트 블록)이 조용히 사라졌는지를 다섯 표면에서 본다. 존재 확인이 아니라 **차단 동작**을 본다 — 규칙마다 막혀야 할 입력을 실제로 먹여 rc=2 를 요구하고, 그 차단이 그 규칙 때문임을 등재만 뺀 사본과의 A/B 로 귀속한다. 훅 배선은 `matcher` 까지 대조한다(경로·명령이 다 맞아도 `matcher` 가 좁혀져 있으면 규칙이 전부 무력인데 나머지 검사는 전부 통과한다 — 실측)
- 게이트는 **예외 목록 방식**(극성 반전)으로 쓴다. pre-commit 이 **강제 장치 검사와 문서 신선도**를 강제한다 — **단, `core.hooksPath` 가 `.beads/hooks` 를 가리킬 때만이다** (정정 2026-08-22, harness-6of: 미설정이면 git 이 `.git/hooks` 로 해소해 게이트가 조용히 돌지 않는다. 배선은 이제 `merge_git_hook` 이 훅을 붙인 직후 함께 건다)

- **울트라 리뷰 반영 (2026-08-19, CONFIRMED 19건 전부 수정).** 요지: ralph 플러그인 식별자 교정(`ralph-loop@claude-plugins-official` — 옛 값은 실재하지 않아 무인 루프 전체가 동작 근거가 없었다) · claim 은 **세션 고유 actor** 필수(같은 actor 는 멱등 통과라 선점이 안 된다, 실측) · workspace.sh 재사용 경로 검증(깨진 잔존 디렉토리의 본 체크아웃 폴스루 차단, 물리 경로 비교) · workspace.sh·repo.sh 의 루트를 스크립트 위치에서 파생(워크트리에서 절대 경로 호출 시 대상 레포 실행 차단) · merge_settings 가 같은 엔트리의 대상 훅을 지우던 결함 수정 · pre-commit 하네스 블록에 bd 가용성 가드(fail-open+경고) + SessionStart 에 core.hooksPath 자가 복구 · `repo.sh restore`(새 머신에서 등록부로 클론 복구, check 보존) · repos.json 에 `bootstrap` 필드(워크트리 준비 명령, workspace.sh 가 실행) · SIGNAL 완결(IMPLEMENTATION_BLOCKED·DECISION_NEEDED 처리 정의, evaluator 의 유령 값 SKIP 제거) · 멀티 레포 스토리 마감 전 통합 검증 단계 · board.sh 원자 스왑 + dotted id 자연 정렬 + `.source-hash` 지문으로 board-check 재렌더 생략 · RETRY 상한 숫자를 agile.md 단일 소유로 · AGENTS.md 3중 중복 축소 · 코어 파일의 프로젝트 고유 bead id 제거 · `.codex/`·`.agents/` 를 bd 소유물로 명시

- **비판 리뷰 반영 (2026-08-20, 병렬 워커 4명 · 지적 ~70건 전부 또는 기각 판정).** 관통 주제는 "성공 신호가 실제 상태를 보증하지 않음"과 "산출물·입력에 대한 신뢰 가정" 둘이었다. 요지:
  - **지문 빠른 경로를 입력+출력 동시 서명으로** — 입력 해시만 보던 판은 산출물의 손상·삭제·직접 수정·지문 조작이 전부 "문서 최신"으로 통과했고, 렌더 무관 필드(updated_at·priority)까지 해시에 넣어 거짓 stale 도 냈다. 렌더 기여 필드 투영 + rails.json 을 입력 지문으로, 산출물 트리를 출력 지문으로 서명하고 레시피는 `scripts/lib/board-hash.sh` 가 단일 소유한다
  - **hooksPath 자가 복구가 대상의 기존 `.git/hooks` 를 죽이던 것** — `.claude/hooks/ensure-hookspath.sh` 로 교체: 기존 실훅이 있으면 설정하지 않고 크게 안내, 없을 때만 배선
  - **claim actor 영속** — 셸 변수 규약은 Bash 호출 간 증발해 기본 actor 폴백(=선점 무효)을 재발시켰다. actor 의 원본은 스토리 note 의 `ACTOR:` 줄, 모든 호출에 리터럴 인라인, 같은 스토리 동시 2세션 금지, 전 태스크 타 actor claim 이면 루프 절단(고아 claim 의심 — 회수는 사람 지시로)
  - **재사용 검증 완결** — git-common-dir 로 클론과의 연결 확인(브랜치명만 맞춘 고아 레포 차단), 부트스트랩 완료 마커(형제 파일)로 실패 후 재실행이 부트스트랩부터 재시도, 기존 브랜치 재개 시 "기준 최신" 허위 로그 제거
  - **install/sync 정직성** — 깨진 settings.json 이면 성공 보고 대신 즉시 실패, VERSION 을 코어에서 제외(대상 소유 파일과 충돌 — 버전은 `.harness-state` 헤더로 전달), `# source:` 헤더로 원본 위치 기록(setup 의 "sync 재실행" 지시가 실행 가능해짐 — **2026-08-23 `# upstream <소유자>/<레포>` 로 대체됐다**: 릴리스가 원본이 되면서 로컬 경로 의존이 사라졌다), 삭제 드리프트 복원·개명 잔존을 보고, jq 폴백 안내를 유효 JSON 으로
  - **게이트 자체 수리** — board-check 에서 set -e 제거(첫 stale 즉사로 "양방향 완전 일치"가 부분 실행이 되던 것), 조상 없는 sprint 라벨·acceptance 부재·직속 정체불명 파일 검출 추가, workspace-check 를 스크립트 위치 기준으로 + 재사용 거부·부트스트랩 시나리오 17항목으로 확장
  - **신뢰 경계** — slug `[a-z0-9-]` 단언(`../` 경로 탈출 실측 차단), repo 이름 검증, 표 셀 `|` 이스케이프, 자유 텍스트 echo→printf, 렌더 잠금 + 숨김 임시 디렉토리(병렬 세션 오탐·잔존물 영구 차단 해소), repos.json 쓰기 잠금
  - **절차 정리** — deferred 를 스토리 마감 조건에 편입(+전이 명령), reviewer 위임 계약에 하네스 루트, 루프 절단 목록 완결(DEVIATION·상한 초과·전 태스크 claim), retrospective "직접 수정" 범위를 행동 불변 수정으로 한정, evaluator 더러운 트리 → DECISION_NEEDED, restore 부분 실패 진행(die 격리), 스킬 수·게이트 규모 표기 통일
  - 기각 2건: `.gitignore` 의 `.claude/worktrees/` 는 죽은 참조가 아니다(Claude Code 자체 워크트리가 그 경로를 쓴다) · bd 관리 블록 2중은 bd 소유라 손대지 않는다

- **훅 명령을 프로젝트 루트에 앵커** — 훅은 세션의 현재 디렉토리에서 실행되므로 CWD 가 워크트리 등으로 이동해 있으면 상대 경로 스크립트가 ENOENT 로 죽고 bd 는 엉뚱한 원장에 붙는다. 모든 훅 명령을 `cd "${CLAUDE_PROJECT_DIR:-.}" &&` 로 감싼다 (변수 미제공 환경은 종전 동작)
- **repo.sh 가 클론 확보 시 하네스 레포의 커밋 신원을 복사** — 전역 신원은 레포마다 다를 수 있어, 하네스에 로컬 user.name/email 이 있으면 add·restore 양 경로에서 클론에 복사해 저자를 일치시킨다

- **머지 전 최종 리뷰(high) 반영 — 확인 16건 전부 수정.** 요지: pre-commit 게이트가 워킹 트리만 보던 것을 **인덱스 일치까지 단언**(렌더 후 git add 누락이 낡은 투영을 커밋하던 구멍) · bd "미설치/미부트스트랩"(fail-open+경고)과 "실행 실패"(잠금·손상 — **fail-closed**)를 분리 · 배포된 install.sh 사본이 VERSION 부재로 즉사하던 것을 상태 파일 헤더 폴백으로 · jq 폴백 JSON 의 따옴표 비이스케이프 재발 수정(PATH 에서 jq 제거하고 실측) · **`[[ ]]` 규칙 사실 정정** — `=`/`==` 모두 미인용 우변을 glob 해석하므로 처방은 연산자가 아니라 **우변 인용** · 지문 화이트리스트-렌더러 필드의 드리프트를 board-check 가 극성 반전으로 단언 · 부트스트랩 마커가 워크트리 재생성 시 잔존하던 것(신규 생성 시 제거 + 정리 절차 등재) · repo.sh 중복 검사를 잠금 안에서 재수행 · board-check 의 jq 부재 오진 가드 · 빠른 경로의 스프린트별 bd 재호출 제거(전체 스냅샷에서 파생) · 이 레포 settings 의 ralph-loop 재등록 + 손사본 미러링 규율 명문화 · operations 의 원장 경로 오기(`.beads/dolt/`→`embeddeddolt/`)·hooksPath 수동 명령 · ralph-cancel 의 플러그인 내부 계약 주석 · setup 의 repos.json doc 예시 동기화. 렌더러 단일 jq 패스화는 백로그(harness-k0s)
- **강제 장치 한 장 요약 `docs/guardrails.md` 신설 (코어 4번째 문서).** 규칙 8종·deny 10종·검사 6종이 각각 무엇을 막고 무엇을 **못** 막는지, 검증은 어떻게 하는지(`guardrail-check.sh` 의 A/B 귀속), 배포가 자동으로 닿지 않는 수동 단계 7건, 게이트 없는 규율의 현재 상태를 한자리에 모았다. 그전까지 이 내용은 `docs/reviews/guardrails/` 10편에 흩어져 있었고 요약하는 자리가 없었다. `docs/development.md` 에 얹혀 있던 "수동 단계" 표와 배선 결정문은 이 문서로 옮겼다(삭제가 아니라 이전). `CLAUDE.md` 의 "절대 금지" 3항목에는 **그것을 강제하는 게이트의 유무**를 항목마다 붙였다 — 원격 반영은 절반(서브에이전트만), 본 체크아웃 쓰기는 있음, 완료 판정은 **없음**. 게이트가 생겨도 규율 문장은 지우지 않는다: 게이트는 우회 가능하고 규율은 왜 그런지를 설명한다

### 설치와 이식

- `scripts/install.sh init | sync | check | update | version | manifest | pack`. **설치는 in-place 다** — 릴리스 tarball 을 푼 그 자리가 곧 새 하네스이고, 대상 경로를 받아 코어를 심는 하위 명령(`install <대상경로>`)은 폐기했다(2026-08-23, harness-u9n). 미출시 판이라 폐기 비용은 0 이다 — 릴리스 0개·설치 0건
- **릴리스·갱신 하위 명령 4종** — `pack <출력디렉토리>` 가 릴리스 아티팩트 2개를 만들고(`harness-<버전>.tar.gz` = 코어 + `.harness-state`, `harness-<버전>.state` = tarball 안의 것과 **같은 파일**을 한 번만 생성해 옆에 복사 — 두 번 만들면 갈라지고 갈라진 state 는 받는 쪽에서 "손댄 코어"로 오탐된다), `init` 이 푼 자리를 새 하네스로 세우며, 파생본 쪽에서 `check` 가 upstream 최신 릴리스와 대조하고 `update` 가 그것을 받아 제자리에서 갱신한다. `init`·`check`·`update` 는 인자를 받지 않는다 — 대상은 언제나 그 스크립트가 있는 트리다(조용히 버리면 다른 자리를 지정한 호출이 rc=0 으로 끝나면서 실제로는 CWD 트리를 배선한다). `manifest`·`pack` 은 **원본 전용**, `check`·`update` 는 **파생본 전용**이고 판별은 `.harness-state` 의 존재다. 발행 절차는 `docs/development.md` "릴리스"
- `checks/release-check.sh` — pack 산출물이 CORE 목록과 갈라졌는지 본다(tarball 내용·state 경로·state sha ↔ tarball 실물·두 아티팩트 동일성 4종, 부정 대조군 + 대조별 A/B 귀속). `install.sh manifest` 는 **원본의 실물**만 보므로 tar 가 실제로 담은 바이트를 못 본다. **커밋 게이트에는 넣지 않는다** — 원본 전용이라 배선하면 파생 하네스의 커밋이 전부 막힌다. 부를 자리는 릴리스 발행 절차다
- **설치 기록** `.harness-state` — 루트에 코어 버전, 갱신처(`# upstream <소유자>/<레포>`), 파일별 sha256. 레포에 커밋한다. upstream 의 출처는 둘이고 **우선순위가 있다**: ① 그 트리의 `.harness-state` 기록 ② `git remote origin`. 둘 다 없으면 죽는다 — 기본값으로 덮으면 파생 하네스가 엉뚱한 레포를 보거나 조용히 갱신되지 않는다. ①이 앞선 것이 두 가지를 닫는다: 릴리스 tarball 을 푼 트리는 `.git` 이 없어도 갱신처를 알고(`update` 가 정확히 그 경로다 — tarball 을 임시 디렉토리에 풀어 그 트리의 install.sh 로 sync 를 돌린다), 포크를 클론해 sync 를 돌려도 갱신처가 sync 를 돌린 사람의 포크로 바뀌지 않는다. 원본에는 설치 기록이 없어 ②로 떨어지며, 그때 origin 이 GitHub 이 아니면 만드는 자리에서 죽인다 — 갱신 경로가 `gh release` 하나뿐이라 다른 호스트의 슬러그는 파생본에서 반드시 실패한다
- **드리프트 감지** — `sync` 가 그 기록과 대조해 대상에서 손댄 코어 파일을 `.harness-bak` 으로 백업한 뒤 덮고 목록으로 보고한다. 조용히 지우지 않는다
- **훅 자동 병합** — `.claude/settings.json`(Claude Code 훅·플러그인)과 `.beads/hooks/pre-commit`(강제 장치 검사 + 문서 신선도 게이트) 양쪽에 멱등 삽입. 소유 키가 명확해 재실행해도 중복되지 않고, 대상이 넣은 훅·권한·검사는 보존된다. 코어가 훅 파일을 배포해도 선언되지 않으면 실행되지 않는다 — 그 배선이 여기다
- **난간의 배포 경로** — `PreToolUse` 훅(`guard.sh`)을 `HOOKS` 에 등재하고, `permissions.deny` 규칙 10종을 `DENY` 배열로 `merge_settings` 가 대상에 실어 보낸다. 그전까지 훅 파일은 복사되나 배선되지 않았고 deny 블록은 하네스 자신에게만 적용됐다. deny 병합은 **합집합**이다 — 없으면 덧붙이고 있으면 손대지 않아 대상 소유 규칙의 내용도 순서도 보존된다(문자열 집합이라 소유자를 구별할 표시가 없고, 구별할 수 없으면 지우지 않는 쪽을 고른다). 대가인 "철회가 전파되지 않음"과 `sync` 가 `settings.json` 드리프트를 **복구는 하되 보고하지 않는다**는 실측을 `docs/guardrails.md` "수동 단계"에 표로 등재했다
- ~~**pre-commit 자동 배선은 board-check 하나로 유지** (결정). `guard-check.sh` 50초 + `gh` 의존, `workspace-cleanup-check.sh` 9.5초 + 실제 bead 생성 — 커밋 게이트가 원장에 쓰거나 환경 사유로 모든 커밋을 막으면 안 된다~~ → **정정: 자동 배선은 `board-check` 와 `guardrail-check` 둘이다.** 위 결정은 "그 시점에 배선할 만한 것이 없다"는 뜻이었고 같은 문장이 커밋 시점의 난간 검사를 뒤 태스크에 넘겨 두었다. 그 자리를 `checks/guardrail-check.sh` 가 채운다 — 위 세 기준(런타임·외부 명령 의존·원장 쓰기)을 전부 만족한다: 1.16~1.26초, 원장 쓰기 없음, `bd`·`gh` 미호출. **`jq` 는 쓴다** — 없으면 경고를 내고 통과한다(fail-open). 그래야 "환경 사유로 모든 커밋을 막지 않는다"는 기준이 지켜진다. 판단 근거는 `docs/guardrails.md` 3절
- **코어 목록 양방향 대조** (극성 반전) — `SCAN_PATHS` 범위의 파일은 `CORE` 이거나 `EXEMPT` 여야 한다. 한쪽만 잡으면 코어 파일을 추가하고 등재를 잊었을 때 조용히 설치에서 빠진다
- **의존 도구 preflight** — 설치에 필요한 것이 없으면 즉시 실패, 운용에 필요한 것이 없으면 경고. 조용한 skip 금지
- `setup` 스킬이 프로젝트 맥락(`repos.json`·`rails.json`·`CLAUDE.md`·beads)을 대화로 세팅한다. 세 파일은 대상이 소유해 설치에 딸려오지 않으므로, **명세를 스킬 안에 인라인**해 다른 파일을 참고하지 않아도 되게 했다
- **새 클론의 업무 원장 복원 절차** — `.beads/dolt/` 는 gitignore 대상이라 클론에 딸려오지 않고, 그 상태에서는 `bd list` 부터 실패해 스킬·게이트가 전부 죽는다. `bd bootstrap` 분기와 원격에 원장이 없을 때의 판단을 절차에 넣었다
