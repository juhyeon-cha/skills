# Changelog

## 2.0.1 — 2026-09-06

2.0.0 뒤 `plugins/toolkit/` 의 커밋 전수(스토리 `harness-m8gg` 의 M7). 직전 태그 `toolkit-v2.0.0` 은 스쿼시 머지 전 브랜치 커밋을 가리켜 `main` 의 조상이 아니라, 훑은 범위는 2.0.0 을 실어 보낸 커밋(`648b90a`)부터다.

**폭 판단 — PATCH.** 스킬이 늘거나 줄지 않았고 이름도 그대로다. 설치본은 `claude plugin update` 하나로 끝난다.

### 에이전트 문서 정리 (`harness-m8gg.8.7`)
- `agent-doc-audit` 7기준을 이 플러그인 자신에 적용했다 — `api-spec-viewer/snapshot-schema.md` 와 `html-report/fonts/FONT-LICENSE.md` 영어화(스키마 키·타입·널 조건·정렬 규칙, 저작권자·OFL·커버리지 수치는 그대로), `html-report/SKILL.md` 의 대상 프로젝트 경로 표기, `postmortem/SKILL.md` §3 의 일화를 판단 기준으로.
- 남은 한글은 예외뿐이다 — 산출물로 나가는 본문(`plan-issue/template.md`), 사용자에게 그대로 내는 고정 문구(`html-report` 의 폰트 안내), 라이선스 표기.
- `plan-issue/SKILL.md` 의 절 표가 `template.md` 의 헤딩 여섯과 1:1 로 맞는다(회귀 검사 절이 표에 빠져 있었다). `brag/brag.py` 와 `html-report/preview.html` 의 주석이 실재하는 절을 가리킨다.

### agent-doc-audit 의 탐지 (`harness-m8gg.8.9`)
- `check.sh` 의 `4-date`·`4-line-pointer` 가 **펜스 코드 블록 밖에서만** 잡는다(`7-korean` 과 같은 처리). 예시 JSON 안의 날짜가 회귀 판정을 흔들지 않는다 — 이 탐지를 레포 게이트의 회귀 검사로 쓰기 위한 조건이다. `SKILL.md` 의 탐지 설명도 같이 맞췄다.

## 2.0.0 — 2026-09-05

**폭 판단 — MAJOR.** `pr-body` 를 부르던 사람은 스킬 이름을 바꿔야 한다(README 버전 표의 "쓰던 사람이 자기 것을 고쳐야 하는 변경"). 이 플러그인의 첫 CHANGELOG 항목이라 앞선 판(1.5.3 까지)의 이력은 없다 — 그 이전은 git 로그가 든다.

### 개명
- **`pr-body` → `writing-pull-request`.** 디렉토리 · `plugin.json` 의 `skills` 항목 · frontmatter `name` · `issue-resolution` 4절의 참조를 함께 바꿨다. `/toolkit:pr-body` 는 `/toolkit:writing-pull-request` 로.

### 새 스킬
- **`agent-doc-audit`** — 에이전트가 읽는 문서(CLAUDE.md · AGENTS.md · rules · SKILL.md · 역할 정의)를 7개 기준(정정 이력 · 행동을 바꾸지 않는 문구 · 중복·모순 · 수치·날짜·줄 번호 · 근거·사례 서술 · 죽은 포인터 · 언어)으로 훑어 제안표를 내고, 사용자 확인 뒤에만 반영한다. `check.sh <디렉토리…> [--root <디렉토리>]` 가 기계 탐지 후보를 `파일:줄:기준:문장` 으로 낸다.
