# 1단계 고정 기준의 실제 후속 관측

[observation.json](observation.json)은 `27e1714cbe23d15b6dacf07a0501c98ec78c08bd`의 toolkit 61개 파일을 복사한 하나의 설치 사본에서 새로 실행한 관측이다. 기존 관측의 모델 응답을 새 입력의 응답으로 사용하지 않았다. [기준별 판정](../../../docs/initiatives/code-driven-knowledge/experiments/foundation-followup.md)에서 테스트와 실제 관측을 구분한다.

| 키 | 원본과 해석 |
|---|---|
| `installation`, `state` | 실행 전 설치 전체 해시, 소스와 61개 파일 일치, 중단 전후 상태와 최종 기준 |
| `inputs`, `document_fixture` | 접수·분류 원문, 고정 문서/권위/질문/필수 명제, 수정 버전 |
| `roles` | 실제 dispatch 식별자, 정확한 역할 입력, 새 응답, 실패와 재시도. classifier는 관측 JSON의 필드를 보존하고 표기 공백을 재구성했다. |
| `commands` | 부모가 실행한 공개 CLI·준비·중단 명령의 argv/rc/stdout/stderr. 인계자의 직접 실행은 `roles/handoff.json` 응답에 별도로 보존한다. |
| `application`, `final_documents` | 접수·context·packet·리뷰·완료 기록과 최종 문서 |
| `managed_delegation`, `m1_independent_verdict` | M0, 구현, 독립 판정, 실제 인계의 부모 관측 영수증과 M1의 음성 대조 결과 |
| `driver` | 이 관측에서 사용한 일회성 실행 보조 코드의 정확한 원문. 재실행 도구나 제품 진입점이 아니다. |

첫 B 수정안은 코드와 일치하지만 새 접수 AC의 미검증 고지를 빠뜨린 의도적 결함 입력이다. 실제 독립 리뷰의 반려 뒤 설치된 writing-for-humans를 읽은 작성자가 수정하고 새 독립 리뷰가 통과시켰다. C 변경도 새 작성·리뷰를 거쳤다. 적용 직후 프로세스 종료(rc 91)를 주입하여 `applying`으로 남긴 뒤, 이전 대화가 없는 child가 프로젝트/run/설치 진입점과 실행 환경만 받아 직접 `status → resume → status`를 실행했다. 부모가 대신 완료하지 않았다.

문서 평가는 정상·예외 누락/거짓 완료 변형·복원본에 각각 새 독자를 사용했다. 정상과 복원본 내용은 같지만 응답은 별개다. 독립 판정자는 변형의 CUR-2/TGT-2를 실패로 유지했고, 복원본은 새 독자 응답으로 다시 판정했다.

이 자료의 신뢰 수준은 부모가 관측한 도구 반환이며 인증된 provider 기록은 아니다. 역할 분리는 prompt-only다. 도구 호출 수·토큰·실제 모델 식별·접근 강제는 미측정이다. 앱 재시작, 새 최상위 작업, marketplace 자동 로딩, 다른 OS, 실제 서버·배포, 인간 사용성, 문서→코드 구현은 관측하지 않았다. 임시 절대 경로는 당시 실제 경로로 보존하며 현재 파일 존재를 보장하지 않는다.
