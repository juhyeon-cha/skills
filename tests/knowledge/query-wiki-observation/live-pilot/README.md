# 실제 2개 저장소 관측

이 디렉터리는 생산자·소비자가 `amount`에서 `total` 필드로 함께 변경될 때 문서 bootstrap, 독립 검토, 적용, 부분 검증 및 읽기 상태를 관측한 로컬 증거다. 설치된 플러그인이나 원격 서비스를 변경하지 않았다.

`frozen.json`은 문서 작성 전 질문·정답·C1–C4·결함 사본 기준을 고정했다. `input-*.json`은 초기 커밋의 실제 소스 바이트다. 외부 toolkit writing-for-humans의 BE/문서 구조 지침으로 작성한 문서를 정상/결함 fresh reader에게 각각 제공했고, `bootstrap-review.json`의 독립 판정 후에만 `init`했다. 정상은 C1–C4 통과, 결함은 C2 실패다. 독자는 결함의 잘못된 기본값을 그대로 인용했고, 독립 판정은 소스의 KeyError와 충돌함을 검출했다.

`update-freeze.json`은 코드 변경 전에 기대 동작과 읽기 상태를 고정했다. `prepare-*.json`이 가리키는 전체 packet을 실제 별도 reviewer가 검토한다. `review-*.json`은 작성자가 만든 합격 응답이 아니다. `import-review-*`, `resume-*`, `status-final-*`은 해당 응답을 적용한 공개 CLI의 결과다. 호출별 실제 argv/stdout/stderr/경과 시간은 `trace-*.json`에 남았다.

첫 관계 설정은 project의 `pilot/producer`와 관계의 `producer` 식별자 불일치로 실패했다. 원래 `relations`와 실패 trace를 보존하고, DB를 수정하지 않은 채 식별자를 맞춘 `relations-v2`를 새로 만들었다. 현재 좌표는 `host.json`, `relations-v2`, goal `exchange`, principal `operator`다. `reader`는 전체 읽기, `restricted`는 소비자 접근이 없다. 이 설정은 로컬 host 선언이며 인증 서버나 OS 권한 강제를 뜻하지 않는다.

`operate-recovery.py`는 이미 최신인 동일 커밋 이벤트를 제출하고 첫 `next` 응답을 후속 제어에서 일부러 사용하지 않는다. `status`와 같은 상태의 `next`로 재조회해 completed/unchanged 및 idle을 확인했다. 이는 응답 누락을 주입한 실제 로컬 재진입 관측이며, 새 모델 작성이나 분산 서비스 장애를 재현한 것은 아니다.

비용은 실제 명령 시간과 host agent 호출 수만 관측한다. 모델명·토큰·금액·provider 호출 ID는 제공되지 않았다. attestation의 call_id는 실제 host가 반환한 canonical agent task ID다. bootstrap reader의 도구 접근 분리는 prompt 수준이었다. 배포와 실제 사용자 사용성은 미검증이다.

재현은 보존된 두 Git 저장소와 trace argv, `driver.py` 및 단계별 Python 스크립트를 따른다. 기존 상태를 덮어쓰거나 init을 재실행하지 않는다. 새로운 실행은 별도 절대 경로로 입력을 고정하고 독립 reader/reviewer를 다시 호출해야 한다. 저장된 합격 응답은 새 문서나 새 packet의 합격 근거로 재사용할 수 없다.
