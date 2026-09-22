# 여러 저장소의 목표·구현·근거를 연결한 로컬 관측

두 저장소의 `amount`→`total` 계약 변경을 코드 선행과 문서 선행으로 각각 끝까지 실행했다. 저장소별 현재 소스·목표·검증 근거를 분리해 조회했고, 한 곳만 완료되거나 근거가 오래됐을 때 전체 완료를 표시하지 않았다. 고정한 여섯 질문은 기존 자료 조회와 관리 조회의 서로 다른 독자가 모두 정답과 근거를 제시했으며 별도 평가자가 통과로 판정했다.

범위는 **두 흐름에 사용하는 네 로컬 Git 실험 저장소**다. 운영 서비스와 계정 연결은 수행하지 않았다. 관측 소스는 `6d64aec55f2cff443792c998e16e7886d5f9d47c`이며, 최종 전달 head의 독립 품질 리뷰·수용 판정·CI·병합 결과는 [태스크 #395](https://github.com/juhyeon-cha/skills/issues/395)와 그 전달 PR을 참조한다. 이 문서는 그 판정을 대신하지 않는다.

원본 [S5-01~06](../stages/05-feedback.md)을 축소하지 않았다. [사전 고정 입력·기대 결과](../../../../tests/knowledge/multi_repo/observation/frozen-plan.json), [비교 절차](../../../../tests/knowledge/multi_repo/observation/comparison-protocol.json), [질문별 관측 시점과 정답](../../../../tests/knowledge/multi_repo/observation/live/comparison-checkpoints.json)을 고정한 뒤 실행했다. [증거 안내](../../../../tests/knowledge/multi_repo/observation/README.md)에서 원문·검증기를 찾을 수 있다.

## 전체 흐름과 실패 상태

논리적 저장소 ID는 `svc-producer`와 `svc-consumer`, 공유 목표는 `contract-total`이다. 목표 `v2`는 생산자가 `total=10`을 반환하고 소비자가 `total`을 읽는 계약이다. 경로와 표시용 URL은 ID를 대신하지 않는다. 출발점 접수와 사용자 지시의 출처는 [origins.json](../../../../tests/knowledge/multi_repo/observation/live/origins.json)에 보존했다.

| 관측 | 확인한 결과 | 원문 |
|---|---|---|
| 코드 선행·문서 선행 | 두 흐름 모두 사전 예측→생산자만 구현·문서 반영→소비자 구현·문서 반영→각 검사와 통합 검사→독립 의미 리뷰→검색·위키를 실행 | [코드 선행 최종 조회](../../../../tests/knowledge/multi_repo/observation/live/code-first/complete-query-output.json), [문서 선행 최종 조회](../../../../tests/knowledge/multi_repo/observation/live/document-first/complete-query-output.json) |
| 한 저장소만 완료 | 생산자 검증은 통과했지만 소비자와 통합 검사는 exit 1. 조회는 전체 `incomplete`, 위키는 본문 제공 불가 | [부분 검사](../../../../tests/knowledge/multi_repo/observation/live/code-first/producer-only-checks-output.json), [Q1](../../../../tests/knowledge/multi_repo/observation/live/checkpoints/Q1/candidate.json) |
| 현재와 목표 | 문서 선행 구현 전 소비자는 `amount`, 목표는 `total v2`. 목표 확정만으로 구현·검증 완료를 주장하지 않음 | [Q2](../../../../tests/knowledge/multi_repo/observation/live/checkpoints/Q2/candidate.json) |
| 사용자 출발점·예측 누락 | 사용자 접수로도 양 저장소 사전 예측을 등록. 고의로 남긴 생산자 단독 예측은 소비자 누락으로 비교하고 기존 intake에 누락·결정 근거를 연결 | [사용자 예측](../../../../tests/knowledge/multi_repo/observation/live/code-first/prediction-user-input.json), [후속 비교](../../../../tests/knowledge/multi_repo/observation/live/code-first/comparison-feedback-input.json), [Q3](../../../../tests/knowledge/multi_repo/observation/live/checkpoints/Q3/candidate.json) |
| 권한 철회 | 재조회에서 숨긴 구성원의 ID·내용·경로·URL을 제공하지 않음. 필수 2개 중 1개 숨김을 표시하고 전체 완료를 막음 | [Q4](../../../../tests/knowledge/multi_repo/observation/live/checkpoints/Q4/candidate.json) |
| 한 저장소 갱신·게시 실패 | 소비자 소스 경로를 일시 이동했을 때 생산자는 게시되고 소비자는 실패해 `partial`. 경로 복구 후 다시 게시됨. 앞선 이력 보존 | [실패](../../../../tests/knowledge/multi_repo/observation/live/code-first/source-unavailable-publish-output.json), [복구](../../../../tests/knowledge/multi_repo/observation/live/code-first/source-restored-wiki-output.json) |
| 오래된 색인 | 게시 후 새 생산자 커밋을 만들자 `stale`과 검증 대기를 표시. 과거 게시 이력을 현재 본문으로 제공하지 않음 | [Q5](../../../../tests/knowledge/multi_repo/observation/live/checkpoints/Q5/candidate.json) |
| 목표 철회 | 철회한 `v3` 목표와 현재 `total` 코드를 별도 표시. 코드 롤백이나 전체 완료로 해석하지 않음 | [Q6](../../../../tests/knowledge/multi_repo/observation/live/checkpoints/Q6/candidate.json) |
| 저장소 복제·경로 변경 | 동일 이력의 복제 경로로 바꿔도 논리 ID와 검증 근거 유지 | [복제 경로 조회](../../../../tests/knowledge/multi_repo/observation/live/code-first/relocated-query-output.json) |

최종 정상 위키 본문도 [코드 선행](../../../../tests/knowledge/multi_repo/observation/live/rendered/code-first-complete.md)과 [문서 선행](../../../../tests/knowledge/multi_repo/observation/live/rendered/document-first-complete.md)으로 보존했다. 이후 실패 실험 때문에 마지막 디스크 상태가 정상 완료 상태와 같다고 주장하지 않는다. 각 결과는 해당 관측 시점의 근거다. 누락 feedback의 intake 등록은 후속 자동 구현까지 완료됐다는 뜻이 아니다.

## 원본 조건별 결과

| 조건 | 실측 결과와 한계 |
|---|---|
| S5-01 저장소 간 근거 | 두 흐름에서 소스 커밋·문서 바인딩·검사·실제 리뷰를 연결했다. 부분 구현·접근 불가·서로 다른 관측 시점을 전체 최신 완료로 합치지 않았다. |
| S5-02 검색과 위키 | 현재 커밋, 목표 버전, 검증 상태와 근거 ID를 제공했다. 색인은 재생성 가능한 자료이며 stale·철회 때 현재 본문을 제공하지 않았다. 검색은 리터럴 문자열 조회이고 의미 검색 엔진은 아니다. |
| S5-03 개발 전후 연결 | 코드·문서·사용자 출발점을 사전 예측과 사후 비교에 연결했다. 잘못된 예측과 수정 근거를 보존했다. 최초 모델 입력에 없던 `check.py`까지 파일별 영향을 빠짐없이 예측했다고 주장하지 않는다. |
| S5-04 권한과 게시 | 호스트의 source/query/publish 권한 관계와 목표 메타데이터 범위를 적용했다. 권한 철회·부분 게시·목표 철회를 관측했다. 계정 인증이나 이미 복사된 정적 문서 회수는 범위 밖이다. |
| S5-05 품질과 비용 | 같은 여섯 질문에서 양쪽 독자의 정답·인용·비공개 처리 모두 통과했다. 실제 호출과 시간·자료 조회 작업 수를 기록했다. 제공되지 않은 토큰·금액은 `null`이다. |
| S5-06 도구 도입 판단 | 아래 실측 병목과 기존 방식 비교를 근거로 파일 기반 집계를 유지했다. 중앙 DB·검색 엔진·Promptfoo의 도입을 완료 조건으로 삼지 않았다. |

## 같은 질문으로 비교한 결과

기존 방식은 허용된 저장소별 소스·문서·목표·검사·리뷰·비교 기록을 제공했다. 관리 방식은 동일 시점과 권한의 실제 query+wiki 결과를 제공했다. 서로 다른 새 독자는 정답표를 보지 않고 답했으며, 별도 독립 평가자는 두 응답과 원문을 대조했다. [실제 평가 원문](../../../../tests/knowledge/multi_repo/observation/live/comparison-grader-raw.json)에서 각 질문의 판정 이유를 확인할 수 있다.

| 질문 | 기존 방식 정답·근거·비공개 처리 | 관리 방식 정답·근거·비공개 처리 | 준비 조회 작업 수 기존/관리 |
|---|---|---|---|
| Q1 전체 사용 가능 여부 | 모두 통과 | 모두 통과 | 19 / 2 |
| Q2 현재 소비자와 목표 | 모두 통과 | 모두 통과 | 14 / 2 |
| Q3 실제 영향과 예측 누락 | 모두 통과 | 모두 통과 | 25 / 2 |
| Q4 접근 불가 구성원의 완료 여부 | 모두 통과 | 모두 통과 | 7 / 2 |
| Q5 과거 위키의 현재성 | 모두 통과 | 모두 통과 | 27 / 2 |
| Q6 목표 철회와 소스 복구 | 모두 통과 | 모두 통과 | 28 / 2 |

필수 조건의 실패를 평균으로 상쇄하지 않았다. 입력 준비에 실제 사용한 조회 작업은 합계 120회와 12회, 제공한 입력 파일의 바이트 수는 316,482와 58,963이었다. 이 감소를 근거로 관리 집계를 선택한다. 자료 형태가 다르므로 같은 정보를 같은 형식으로 준 실험은 아니며, 사람의 클릭·모델의 사고 횟수·일반적인 탐색 효율 개선을 측정한 것도 아니다. 권한 선별 등 준비 중 제외 작업은 [조회 기록](../../../../tests/knowledge/multi_repo/observation/live/checkpoints/Q1/retrieval.json)에 명시했다.

실험의 실제 호스트 호출은 12회다. 최초 기준 리뷰, 그 오류 수정 재호출, 기준 문서 독자, 기준 문서 판정, 영향 리뷰, 생산자 문서 리뷰, 부분 구현 리뷰, 소비자 문서 리뷰, 전체 구현 리뷰, 비교 독자 2회, 비교 판정 1회다. 하네스의 별도 품질·수용 판정 호출은 이 수에 포함하지 않았다. 추가 사용자 정책·범위·권한 결정은 0회였고, 응답 수정과 파일명 충돌 복구는 에이전트의 조율·수정으로 구분했다.

비교 독자의 호출 의도 기록부터 응답 보존까지는 기존 방식 284.997초, 관리 방식 200.435초였고 별도 판정은 174.491초였다. 이 시간에는 준비 복구·조율·대기·수동 전사가 포함되며 순수 모델 실행 시간이나 공급자 지연이 아니다. 비용·속도 우월성이나 통계적 차이를 주장하지 않는다. 토큰·금액·공급자 지연은 [관측 범위](../../../../tests/knowledge/multi_repo/observation/live/validation-scope.json)처럼 미제공 `null`이다.

## 실패 보존과 추가 도구 판단

기준 문서 리뷰의 첫 응답은 소비자 커밋을 잘못 적어 거절했다. [실패 원문](../../../../tests/knowledge/multi_repo/observation/live/baseline-review-raw-1.json)과 [거절 기록](../../../../tests/knowledge/multi_repo/observation/live/baseline-review-result-1.json)을 보존하고 정확한 입력으로 다시 받은 응답만 사용했다. 비교 자료 준비에서는 과거 독자 prompt 파일명을 재사용한 실수를 실제 비교 호출 전에 발견했다. 원래 dispatch 기록에서 복구하고 새 이름으로 분리한 [복구 기록](../../../../tests/knowledge/multi_repo/observation/live/reader-preparation-recovery.json)을 남겼다. 과거 실패를 첫 시도 성공으로 바꾸지 않았다.

| 후보 | 관측한 병목과 대안 | 이번 판단 |
|---|---|---|
| 중앙 DB | 기존 방식의 여러 근거 대조를 파일 기반 관계와 불변 기록으로 묶었다. 이 실험에서는 해결되지 않은 분산 조정 충돌을 관측하지 않았다. | 도입하지 않음. 다중 호스트·동시 쓰기 규모는 별도 관측 필요. |
| 검색 엔진 | 실제 로컬 query 14회는 각 0.191~0.584초, refresh 6회는 각 0.216~0.397초였다. 두 저장소에서 색인·조회가 해결되지 않은 지연 병목이라는 근거가 없다. | 도입하지 않음. 이 수치는 대규모 성능이나 의미 검색 정확성을 보장하지 않음. |
| Promptfoo 등 평가 플랫폼 | 12회 호스트 호출의 입력·응답 보존과 별도 판정에 조율이 필요했고 두 수정 사건이 있었다. 같은 질문 재사용과 기록 검증기로 증거 누락을 확인할 수 있다. | 이번에는 기록 검증기를 사용. 공급자별 반복 평가 비용·플랫폼 비교를 관측하지 않아 추가 플랫폼의 이득은 미확인. |

## 재확인과 미검증 범위

`bash tests/knowledge/multi-repo-observation-check.sh`는 보존한 496개 원문의 파일집합·SHA-256, 172개 명령 기록, 불변 객체, 질문·권한·입력 동일성, 실제 actor/응답 연결과 필수 상태 결과를 확인한다. 모델 호출을 재현하거나 새 의미 판정을 만들어내는 검사가 아니다. [합성 회귀](../../../../tests/knowledge/multi_repo/test_multi_repo.py)는 시험용 receipt를 명시하며 실제 모델 품질 증거와 분리한다.

관측 환경은 macOS ARM64, Git 2.55.0, Python 3.14.7, jsonschema 4.26.0, Codex 호스트다. 모델 ID와 공급자 청구 자료는 반환되지 않았다. 독자에게 다른 자료를 열지 말라는 지시는 prompt 제한이며 도구 차원의 격리는 아니다. receipt는 호스트 기록이고 공급자의 인증 서명이 아니다.

운영 저장소·검색 서비스·위키 계정, 설치본 활성화, 릴리스·배포, DB 마이그레이션은 검증하지 않았다. 호스트 권한 설정은 신뢰하는 로컬 경계이며 운영 인증을 대신하지 않는다. 이미 복사된 정적 결과는 회수할 수 없다. 두 저장소·짧은 Python 계약의 관측을 일반 규모·언어·제품의 의미 정확성이나 완전 무인 운영으로 확대하지 않는다.
