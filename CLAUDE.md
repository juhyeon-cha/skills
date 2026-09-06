# skills 레포를 고칠 때

이 레포는 플러그인 마켓플레이스다. 여기서 세션을 열었을 때 지켜야 하는 규칙 넷.

- **고칠 자리는 설치본이 아니라 이 레포의 `plugins/<이름>/` 이다.** user scope 에 설치된 복사본
  (`~/.claude/plugins/…`)을 고치면 다음 마켓플레이스 갱신이 덮어쓴다. 설치본에서 발견한 문제도
  여기서 고치고, 설치본은 갱신으로 받는다.
- **게이트는 레포 루트에서 `bash scripts/check.sh` 다.** 종료 코드 0 이어야 한다. 무엇을 검사하는지는
  그 스크립트 머리말 주석이 원본이다.
- **플러그인 설명은 세 자리가 같아야 한다** — `plugins/<이름>/.claude-plugin/plugin.json` 의
  `description` 이 원본이고, `.claude-plugin/marketplace.json` 의 그 항목과 `README.md` 가 그것을
  그대로 따른다. 게이트의 (d) 가 이걸 본다.
- **릴리스 절차의 소유자는 루트 `.claude/skills/release/SKILL.md`(`/release`) 다.** 버전을 올리거나
  릴리스할 때는 그 스킬을 따른다. 플러그인으로 배포하지 않는 이유와 버전 정책은 각각
  `plugins/harness/docs/development.md` "Release" 절과 `README.md` "버전" 절에 있다.
