# Changelog

## 2.0.0 — 2026-09-05

**폭 판단 — MAJOR.** `pr-body` 를 부르던 사람은 스킬 이름을 바꿔야 한다(README 버전 표의 "쓰던 사람이 자기 것을 고쳐야 하는 변경"). 이 플러그인의 첫 CHANGELOG 항목이라 앞선 판(1.5.3 까지)의 이력은 없다 — 그 이전은 git 로그가 든다.

### 개명
- **`pr-body` → `writing-pull-request`.** 디렉토리 · `plugin.json` 의 `skills` 항목 · frontmatter `name` · `issue-resolution` 4절의 참조를 함께 바꿨다. `/toolkit:pr-body` 는 `/toolkit:writing-pull-request` 로.

### 새 스킬
- **`agent-doc-audit`** — 에이전트가 읽는 문서(CLAUDE.md · AGENTS.md · rules · SKILL.md · 역할 정의)를 7개 기준(정정 이력 · 행동을 바꾸지 않는 문구 · 중복·모순 · 수치·날짜·줄 번호 · 근거·사례 서술 · 죽은 포인터 · 언어)으로 훑어 제안표를 내고, 사용자 확인 뒤에만 반영한다. `check.sh <디렉토리…> [--root <디렉토리>]` 가 기계 탐지 후보를 `파일:줄:기준:문장` 으로 낸다.
