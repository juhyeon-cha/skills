# skills

juhyeon-cha 의 Claude Code 스킬 플러그인 마켓플레이스. 플러그인은 둘이다 — 개발 진행을
자율화하는 `harness`, 낱개 스킬을 모은 `toolkit`.

## 설치

```
/plugin marketplace add juhyeon-cha/skills
/plugin install <플러그인이름>@skills
```

## 플러그인

설명은 각 플러그인의 `plugins/<이름>/.claude-plugin/plugin.json` 이 원본이다.

- `harness` — 애자일 계층(스프린트→레일→스토리→마일스톤→태스크)으로 멀티 레포 개발을 자율 진행하는 에이전트 하네스 — 원장은 어댑터(github·beads·notion), 보완 스킬 triage(백로그 정리)·status(현황)
- `toolkit` — 여러 스킬을 담는 도구 상자. 보고·공유용 HTML 자료 한 장 만들기, 소스에서 API 스펙을 뽑아 카탈로그 화면 만들기, 두 스냅샷의 API 계약 변경 화면 만들기, 성과 기록을 쌓아 대시보드로 뽑기, 사고 기록을 회고 문서로 만들기, PR 본문 쓰기, 발견한 것을 GitHub 이슈로 등재하기, 열린 이슈를 골라 닫기, 에이전트가 읽는 문서를 훑어 낡은 문장 걷어내기

## harness 사용법

하네스가 도는 데 필요한 절차는 둘뿐이다 — **플러그인 설치**와 **`.harness.json` 이 있는 레포 클론**.
하네스 전용 디렉토리도, 머신 로컬 설정 파일도 없다. 대상 레포 루트에 커밋된 `.harness.json` 하나가
게이트 명령·기본 브랜치·부트스트랩과 **원장 좌표**를 담고, 그 파일의 존재가 곧 하네스 루트의 표지다
(`lib/harness-root.sh` 가 CWD 에서 위로 거슬러 찾는다). 클론은 아무 데나 두어도 된다.
플러그인은 **user scope 에 한 번만** 설치한다 — 레포마다 등록하지 않는다.

```
claude plugin marketplace add juhyeon-cha/skills   # 머신당 한 번
claude plugin install harness@skills               # scope 인자 없이 — 기본이 user
```

**진입점은 `/harness:setup`** 이다(새 하네스 세우기 · 이미 선 하네스에 합류 · 설치본 갱신). 그 뒤의 한 사이클은 절차 스킬 순서대로다:

`/harness:plan-sprint`(스프린트 편성) → `/harness:plan-story`(스토리를 마일스톤·태스크로
분해하고 acceptance 를 쓴다) → `/harness:develop`(워크스페이스 생성 → 마일스톤 단위 구현→검증
사이클 → 스토리 마무리) → `/harness:verify-code`(코드 품질 리뷰) → `/harness:verify-implement`
(acceptance 판정과 마감) → `/harness:retrospective`(회고 — 실행 중 쌓인 피드백을 플러그인
수정 제안으로).

보완 스킬 둘은 순서 밖에서 부른다:

- `/harness:triage` — 스프린트에 속하지 않은 열린 항목을 훑어 중복·폐기·후보 순위를 표로 제안하고, 확인한 행만 적용한다. plan-sprint 앞에.
- `/harness:status` — 활성 스프린트 · 스토리별 열린/닫힌 태스크 수 · 진행 중·막힘·미결정 항목을 한 화면으로. 읽기 전용.

구현·리뷰·판정은 서브에이전트 역할 셋(`harness:implementer` · `harness:reviewer` ·
`harness:evaluator`)에 위임된다. 무인 반복이 필요할 만큼 태스크가 많으면 develop 이 Claude Code
내장 `/loop` 을 제안한다 — 사이클 상태가 원장에 있어 웨이크업이 다시 들어와도 이어진다.

**원장**(스프린트·스토리·태스크를 기록하는 이슈 저장소)은 어댑터 `scripts/ledger.sh` 로만 부르고,
백엔드는 `.harness.json` 의 `ledger.backend` 하나가 정한다 — 파일이 없거나 값이 셋 밖이면
모든 원장 명령이 rc≠0 으로 죽는다(폴백 없음). 한 하네스에 속한 레포들은 **같은 `ledger` 객체**를
저마다 커밋해 들고 있고, 그것이 그들을 한 하네스로 묶는다.

| backend | 원장이 사는 곳 | `ledger` 가 더 담는 것 |
|---|---|---|
| `github` (기본) | 대상 레포들의 GitHub 이슈 + 그것을 묶는 Projects v2 | `owner`(프로젝트를 소유하는 로그인) · `project`(init 이 써 넣는 번호) |
| `beads` | `.harness.json` 을 가진 레포의 `.beads/` 로컬 Dolt DB | 없음 — 접두사는 init 인자, 원격은 Dolt remote 로 따로 |
| `notion` | 통합에 공유된 페이지 아래의 데이터베이스 | `database_id`(init 이 써 넣는다) — 토큰은 `NOTION_TOKEN` 환경 변수 |

플러그인이 거는 훅은 넷이다 — SessionStart(상시 규율 블록 주입) · PreToolUse(가드 — 본 체크아웃
수정·원격 반영 등을 막는다) · PostToolUse(EnterWorktree 뒤 새 워크트리의 원장 배선) ·
Stop(원장에 진행 중인 일이 남았는데 세션이 멈추려 하면 되민다).

## toolkit 사용법

스킬 9종은 서로 독립이다. 발화 예처럼 요청하면 Claude Code 가 스킬을 고르고, 표의 첫 열
이름으로 직접 부를 수도 있다.

| 스킬 | 용도 | 트리거 발화 예 |
|---|---|---|
| `/toolkit:html-report` | 사내 보고·공유용 HTML 한 장을 `template.html` 의 프리셋(분석·재무·현황·제안)에서 만든다 | "보고서 만들어줘" |
| `/toolkit:api-spec-viewer` | 소스 트리를 정적으로 읽어 API 스펙 스냅샷 JSON 을 뽑고, 검색·필터·스키마 트리가 있는 카탈로그 HTML 로 만든다(Spring Boot · FastAPI) | "이 레포 API 뭐뭐 있는지 뽑아줘" |
| `/toolkit:api-contract-diff` | 스냅샷 JSON 둘(전·후)을 받아 추가·삭제된 엔드포인트와 필드를 색으로 구분한 HTML 로 만든다 | "API 뭐가 바뀌었는지 정리해줘" |
| `/toolkit:brag` | 한 일을 [문제 - 해결 - 결과] 항목으로 `~/.brag/` 에 쌓고, 분기 성과 대시보드 HTML 로 뽑는다 | "이번 분기 한 일 정리해줘" |
| `/toolkit:postmortem` | 사고 기록 하나를 타임라인 · [원인 - 조치 - 예방] 카드 · 액션 아이템의 회고 HTML 로 만든다 | "장애 회고 써줘" |
| `/toolkit:writing-pull-request` | PR 본문을 쓴다 — 필수 4절(What / Why / Verification / What the green run does not establish)과 조건부 3절 | "PR 본문 써줘" |
| `/toolkit:plan-issue` | 발견한 결함이나 미결 결정을 GitHub 이슈로 등재한다 — 이슈가 되는 것과 안 되는 것, 본문 골격, 라벨 규칙 | "이슈 등록해줘" |
| `/toolkit:issue-resolution` | 열린 GitHub 이슈 중 막히지 않은 하나를 골라 고치고, 되돌려 증명하고, 닫는다 | "이슈 해결해줘" |
| `/toolkit:agent-doc-audit` | 에이전트가 읽는 문서(CLAUDE.md · AGENTS.md · rules · SKILL.md · 역할 정의)를 7기준으로 훑어 낡은 문장을 제안 표로 내고, 확인한 것만 적용한다 | "문서 정리해줘" |

## 플러그인 추가

1. `plugins/<이름>/` 아래에 플러그인을 만든다 (`skills/`, `agents/`, `commands/` 등).
2. `.claude-plugin/marketplace.json` 의 `plugins` 배열에 항목을 추가한다.

```json
{ "name": "<이름>", "source": "./plugins/<이름>", "description": "<한 줄 설명>" }
```

3. `bash scripts/check.sh` 를 돌린다 — 종료 코드 0 이어야 한다. 이것이 이 레포의 게이트다: `claude plugin validate --strict`(마켓플레이스와 `plugins/*/` 각각) · `plugins/`·`tests/` 아래 `*.sh` 전수 shellcheck · agent-doc-audit 회귀(기준 1·4, `HARNESS_ROOT` 가 있으면 6 도) · 플러그인 설명이 `plugin.json` · `marketplace.json` · 이 README 에서 같은지.

설명은 `plugin.json` 이 원본이다. `marketplace.json` 과 README 의 설명은 거기에 맞춘다.

## 버전

버전은 플러그인마다 따로 매긴다. `plugins/<이름>/.claude-plugin/plugin.json` 의 `version`
하나뿐이고, **레포 전체 버전은 두지 않는다.**

| 무엇을 했나                                        | 어디를 올리나 |
| :------------------------------------------------- | :------------ |
| 플러그인에 **새 스킬**을 추가했다                  | 마이너 (`0.1.0` → `0.2.0`) |
| 기존 스킬을 고쳤다 — 개선·문서 수정·버그 수정      | 패치 (`0.1.0` → `0.1.1`) |
| 쓰던 사람이 자기 것을 고쳐야 하는 변경을 했다      | 메이저 (`0.9.0` → `1.0.0`) |

- 새 플러그인의 첫 버전은 `0.1.0` 이다. 레포에 플러그인이 하나 늘어도 다른 플러그인의
  버전은 건드리지 않는다.
- **아직 아무도 쓰지 않는 플러그인은 버전을 올리지 않는다.** 첫 사용자가 생기기 전의
  변경은 전부 `0.1.0` 에 쌓는다. 올려 봐야 아무에게도 알리는 바가 없다.
- **릴리스는 `/release` 로 한다** (`.claude/skills/release/SKILL.md`). 폭과 CHANGELOG 항목은
  사람이 정하고, 그 뒤의 버전 갱신·validate·커밋·로컬 태그는
  `bash scripts/release.sh <플러그인> <patch|minor|major>` 가 한다.

## 커밋

Conventional Commits 를 쓰고 본문은 한국어로 쓴다. 범위는 플러그인 이름이다 —
`feat(toolkit): …`. 실행해 보지 않은 숫자·주장을 커밋 메시지에 쓰지 않는다.
