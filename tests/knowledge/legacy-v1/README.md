# 실제 구버전 v1 재개 자료

`a1d5e15be20a9e1fa838809b09ae3b445dafc55f`의 실제 CLI로 foundation Git 이력과 고정 리뷰를 처리했다. 문서 반영을 끝낸 `workflow.finish`가 반환하기 직전 프로세스를 rc91로 종료하여 DB가 `applying`, baseline이 이전 커밋인 상태를 보존했다. 현재 구현으로 구버전을 모사한 자료가 아니다.

`database.json`은 SQLite `iterdump`의 손실 없는 SQL과 별도 `user_version`이며, `runs/`와 `docs/`는 구버전이 만든 바이트다. manifest는 출처 커밋, run/commit ID, 원본 설정 경로와 각 자료의 SHA-256을 기록한다. 기본 회귀는 먼저 체크섬을 검사하고 임시 DB에 복원한다. 실행 위치에 따라 `project.config.repo`와 `project.config.docs`만 재배치한다. run·current·packet·review·context·completion은 재작성하지 않는다.

회귀는 현재 설치본을 임시 위치에 복사하고 `foundation-observation/source-history.fi`만으로 Git을 복원한다. 과거 git 객체나 네트워크를 사용하지 않는다. 지원 범위는 이 고정 v1 중단 상태의 완료·반복 재개 및 지원하지 않는 DB 버전 거절이며 모든 과거 버전의 보장은 아니다.

재생성이 필요한 경우 jsonschema 4.26.0이 설치된 Python으로 아래 도구를 명시적으로 실행한다. 대상은 존재하지 않는 새 디렉터리여야 하며 기존 자료를 덮어쓰지 않는다. 이 작업만 과거 커밋 객체가 있는 로컬 저장소를 요구한다.

```sh
python tests/knowledge/generate-legacy-v1.py --repository /path/to/skills --output /tmp/new-legacy-v1
```

재생성 결과의 출처·스키마·중단 시점·바이트를 검토한 뒤에만 fixture 갱신을 판단한다. 일반 검사는 이 도구를 실행하거나 자료를 갱신하지 않는다. 생성 도구가 출력하는 임시 trace 경로에는 실제 구버전 명령과 종료 코드가 남는다.
