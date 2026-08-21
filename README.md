# skills

juhyeon-cha 의 Claude Code 스킬 플러그인 마켓플레이스.

## 설치

```
/plugin marketplace add juhyeon-cha/skills
/plugin install <플러그인이름>@skills
```

## 플러그인 추가

1. `plugins/<이름>/` 아래에 플러그인을 만든다 (`skills/`, `agents/`, `commands/` 등).
2. `.claude-plugin/marketplace.json` 의 `plugins` 배열에 항목을 추가한다.

```json
{ "name": "<이름>", "source": "./plugins/<이름>", "description": "<한 줄 설명>" }
```

3. `claude plugin validate . --strict` 로 검증한다 — 종료 코드 0 이어야 한다.

현재 등록된 플러그인은 없다.
