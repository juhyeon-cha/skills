# 하네스 세션 컨텍스트

harness 플러그인이 SessionStart 에 주입하는 상시 블록이다. 여기 없는 규율은 그것을 쓰는 스킬이 든다 — 맨 아래 표.

## 절대 금지

게이트가 있어도 금지는 그대로다 — 게이트는 우회 가능하고, "못 막는 것"은 "해도 되는 것"이 아니다. 강제 장치의 전수 목록·한계는 하네스 루트 `docs/guardrails.md`.

- **원격 반영은 사용자 명시 지시 시에만** — 머지 · 태그 push · 릴리스 발행 · GitHub 이슈 조작 · 원격 구성 변경 · 기본 브랜치 직접 push · `repos.json` 에 등재되지 않은 원격 · `bd dolt push`. 예외 둘은 사용자 결정이다.
  - 예외 하나 — 대상 레포 push 에 묶인 원장 반영은 자동이다. 손으로 치는 push 가 곧 명시 지시이고, 사이클 종결 2단계의 작업 브랜치 push 도 같은 승인이다 — 그 승인 안에서 오케스트레이터가 `bd dolt push` 를 명시 단계로 돈다(대상 레포에 git 훅을 심지 않으므로 pre-push 가 대신하지 않는다). 절차는 `harness:develop` "사이클 종결".
  - 예외 둘 — 사이클 종결의 작업 브랜치 push·PR 생성은 **미해결 결정이 없을 때만** 자동이다. 범위는 `repos.json` 등재 레포 — 등재가 곧 승인 표면이다.

    | 사이클이 끝난 상태 | 작업 브랜치 push·PR 생성 |
    |---|---|
    | 결정 필요 사항이 하나도 안 나왔다 | **한다** (지시 없이) |
    | 나왔고 사용자가 지시·승인했다 | **한다** |
    | 나왔는데 사용자 지시·승인이 없다 | **하지 않는다** |

    표가 "한다" 로 나와도 **대상 레포가 자기 push·PR 규칙을 가지면 그 규칙이 앞선다.** 미해결 결정 = 사람 대기 신호가 나왔는데 사람이 아직 정하지 않은 태스크 + `status` 가 `blocked` 인 태스크. 신호 목록은 `harness:develop` "사람 대기", 단계와 실패 처리는 같은 스킬 "사이클 종결".
- **대상 레포의 본 체크아웃(`~/.harness-workspace/<레포>` 자체)을 직접 수정하지 않는다** — 작업은 그 안의 `.claude/worktrees/<story-id>/` 워크트리에서만.
- **플러그인 코어(스킬·역할·훅)의 개선을 사용자 명시 지시 없이 설치본에서 수행하지 않는다** — 고칠 곳은 skills 레포 `plugins/harness/` 이고, 설치본은 마켓플레이스 갱신으로 받는다. 프로젝트 맥락(`repos.json`·`rails.json`·`sprints.json`·`CLAUDE.md`·`.beads`)은 하네스 루트의 소유다.
- **완료 판정을 소감으로 하지 않는다** — 근거는 게이트 종료 코드와 acceptance 대조뿐. 만든 주체가 채점하지 않는다.

## 원장

- 원장은 어댑터 `${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh` 로만 부른다 — 이 블록과 스킬 본문의 `ledger.sh …` 는 전부 그 경로다. 하위 명령·인자·JSON 키는 `bd` 의 것과 같다(`ledger.sh --help`). 백엔드는 하네스 루트 `ledger.json` 의 `backend`(`github`·`beads`·`notion`) 하나가 정하고, 파일이 없거나 값이 셋 밖이면 rc≠0 이다 — 폴백 없음.
- 하네스 루트 탐색은 `HARNESS_ROOT` → 워크트리의 `.beads/redirect`(beads 배선) → `~/.harness-workspace/` 의 루트 포인터(`scripts/repo.sh` 가 쓴다) 순서이고, 판별자는 그 자리의 `ledger.json` 이다. 탐색기는 플러그인 `lib/` 에 있다 — `harness:develop` 1절.
- 서브에이전트에게 위임할 때는 하네스 루트 절대 경로를 첫 줄에 주고, 서브에이전트는 `HARNESS_ROOT=<하네스루트> ledger.sh …` 로만 부른다 — 변수 없는 호출은 루트 탐색이 다른 하네스의 원장에 닿을 수 있다.
- 원장이 SSOT 다. `docs/sprints/`·`docs/backlog/`·`docs/adr/` 는 `scripts/board.sh all` 의 투영이라 손으로 고치지 않는다.
- 본문(note·description·acceptance·close reason)은 셸 명령 문자열에 두지 않고 파일 옵션으로 넘긴다 — 형태는 `harness:develop` "원장에 본문을 넘기는 형태".

## 절차 스킬 7종

`harness:plan-sprint`(스프린트 편성) → `harness:plan-story`(분해·acceptance) → `harness:develop`(구현 사이클 — 운영 규율의 소유자) → `harness:verify-code`(리뷰) → `harness:verify-implement`(판정·마감) → `harness:retrospective`(회고) + `harness:setup`(최초 세팅).

역할 정의 3종(서브에이전트, Agent 도구의 `subagent_type`): `harness:implementer` · `harness:reviewer` · `harness:evaluator`.

## 애자일 계층 ↔ 원장 매핑 규약

| 계층 | 원장 표현 | 규약 |
|---|---|---|
| 스프린트 | 라벨 `sprint:<ID>` | ID 형식은 `YYYY-SNN`. 기간은 각 스토리 bead 의 `--due` 로. **상태(`active`/`closed`)의 원본은 루트 `sprints.json`** — 종료 여부를 닫힌 이슈 개수로 판정하지 않는다. 등록부와 라벨의 양방향 일치는 `board-check` 이 본다 |
| 레일 | 라벨 `rail:<ID>` | **사람이다.** 담당자 1명당 레일 1개, 한 레일이 여러 레포를 넘나든다. 레포 경계는 `repo:` 라벨. **루트 `rails.json` 에 등재된 ID 만** 쓰며 형식은 `r1`·`r2` 번호다. 하위 이슈가 상속 |
| 스토리 | `--type epic` | 관련 레포를 라벨 `repo:<이름>` 으로 명시(복수 가능). 문서 디렉토리명이 될 슬러그를 라벨 `slug:<레일ID>-<이름>` 으로 필수 부여 — 레일 ID 접두사로 사람이 달라도 충돌하지 않는다. 유일성은 스프린트 안에서 요구되며 렌더가 단언한다 |
| 마일스톤 | `--type feature --parent <스토리ID>` | 스토리 안의 단계. 순서는 `blocks` 의존성으로 |
| 태스크 | `--type task --parent <마일스톤ID>` | 실행 단위. `--acceptance` 필수. **`repo:` 라벨은 정확히 1개** — 상속으로 여러 개를 받으면 plan-story 가 실제로 건드리는 하나만 남긴다(`ledger.sh label remove`). 여러 개면 develop 이 착수를 거부한다 |

생성 형태:

```bash
ledger.sh create "<스토리 제목>" -t epic -l sprint:<스프린트ID>,rail:<레일ID>,slug:<레일ID>-<슬러그>,repo:<레포>[,repo:<레포>]
ledger.sh create "<마일스톤 제목>" -t feature --parent <스토리ID>
ledger.sh create "<태스크 제목>" -t task --parent <마일스톤ID> --acceptance "<기계 판정 가능한 완료 조건>"
```

## 다른 곳이 소유하는 규율

상시 로드에서 내린 규율이다. 그 절차를 실행할 때만 필요하므로 소유자가 든다 — 여기에 문면을 다시 적지 않는다.

| 규율 | 소유자 |
|---|---|
| 운영 규율 · 원장에 본문을 넘기는 형태 · 상태 주장의 근거 · 결정 상태 · 진단 가설 규율 · 사람 대기 · 대상 레포의 관례 · 사이클 종결 · 멀티 레포 | `harness:develop` (같은 제목의 절) |
| 위임 메시지의 환경 스냅샷 · 장기 실행 | `harness:develop` |
| 여러 개를 한 번에 등재할 때 — id 를 예측하지 않는다 | `harness:plan-story` |
| 재시도 카운터 | `harness:verify-code` |
| 검사가 죽었는지 검사한다 | 하네스 루트 `docs/development.md` |
