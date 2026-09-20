# 일반 하위 에이전트 역할 차단 관측

2026-09-20, Codex 작업에서 새 일반 자식 `/root/generic_probe`를 생성했다.
네이티브 하네스 역할이나 관리 실행 기록을 등록하지 않았으며 설치본도 변경하지 않았다.
아래는 자식이 반환한 실제 `exec_command` 입력과 결과다. `workdir`은 이 수정의
할당된 worktree였으며 개인 절대 경로만 `<WORKTREE>`로 정규화했다.

```json
{"cmd":"pwd","workdir":"<WORKTREE>","max_output_tokens":1000}
{"cmd":"python3 -c 'print(\"generic-child-probe\")'","workdir":"<WORKTREE>","max_output_tokens":1000}
{"cmd":"python3 -c 'import tempfile; f = tempfile.NamedTemporaryFile(prefix=\"generic-child-probe-\", dir=\"/private/tmp\", delete=False); print(f.name); f.close()'","workdir":"<WORKTREE>","max_output_tokens":1000}
```

`pwd`는 exit code 0과 worktree 경로를 반환했다. 두 Python 명령은 모두 실행 전에
다음 오류로 거부됐다. 임시 파일은 생성되지 않았다.

```text
Command blocked by PreToolUse hook: GUARD-DENY: UNREACHED — 판정에 도달하지 못했다: child role is unidentified.
```

`generic-hook-check.mjs`는 이 Python 입력을 수정 소스의 `evaluateGuard`로 재생한다.
테스트의 UUID/default 훅 봉투와 App Server 응답은 fixture이며, 이 자식에서 수집한
원본 훅 봉투나 실제 메타데이터라고 주장하지 않는다. 실제 CLI 입력을 실행하지 않고
허용/거부 판정만 검사한다. 일반 파일 쓰기·패치·자식 생성 허용과 메인 체크아웃·활성
상태·원격 쓰기·원장 좌표 보호도 함께 검사한다.

일반 자식 분류를 제거한 임시 소스 사본에서는 같은 입력이 다시 역할 미식별로
거부된다. 관리 대상 분류를 무조건 허용으로 바꾼 사본에서는 관리 기록 누락 차단이
사라진다. 이 대조는 두 분류 경계가 실제 판정에 영향을 주는지 확인한다.

이는 설치 환경에서의 수정 전 재현과 수정 소스 fixture 검증이다. 수정한 플러그인의
마켓플레이스 업데이트·새 세션 로딩·수정 후 실제 자식 실행 성공은 검증하지 않았다.
knowledge 실행기의 status/resume 성공 역시 이 관측의 범위가 아니다.
