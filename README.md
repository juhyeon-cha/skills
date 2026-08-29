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

3. `claude plugin validate . --strict` 와 `claude plugin validate ./plugins/<이름> --strict`
   를 돌린다 — **둘 다** 종료 코드 0 이어야 한다.

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

## 커밋

Conventional Commits 를 쓰고 본문은 한국어로 쓴다. 범위는 플러그인 이름이다 —
`feat(toolkit): …`. 실행해 보지 않은 숫자·주장을 커밋 메시지에 쓰지 않는다.

## 플러그인

- `toolkit` — 여러 스킬을 담는 도구 상자. 보고·공유용 HTML 자료 한 장 만들기, 소스에서 API 스펙을 뽑아 카탈로그 화면 만들기
