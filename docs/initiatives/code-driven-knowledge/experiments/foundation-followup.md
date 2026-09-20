# 1단계 후속 검증 기록

[고정 수용 기준](../stages/01-foundation.md#승인된-고정-수용-기준)의 현재 판정과 새 관측을 기록하는 자리다. 기존 #332의 완료 판정과 원본은 [기존 최종 검증](foundation-verification.md)에 보존한다.

skills#333의 로컬 수정은 접수 원문의 리뷰 패킷 결합과 context 재진입 검증을 다룬다. 자동 회귀는 해당 경로의 실행 결과만 입증한다. foundation 재생은 접수 없는 버전 1 패킷에서 과거 실제 리뷰를 그대로 사용하며, 별도의 버전 2 접수 실행에서 과거 응답 거절을 확인한다. 새 패킷에 대한 모델의 의미 검증을 대신하지 않는다.

수정본 `27e1714cbe23d15b6dacf07a0501c98ec78c08bd`에서 실제 관측을 마쳤다. 아래는 오케스트레이터의 증거 대조 결과이며 **독립 최종 판정 전까지 전체 완료는 보류한다.** [원본 묶음](../../../../tests/knowledge/foundation-followup/README.md)의 `observation.json`에 역할 입력·응답·명령·손상 대조·해시·완료 기록을 보존했다. 독립 최종 판정은 skills#339의 acceptance에 기록한다.

## 관측 결과

macOS/Codex, Python 3.14.7, jsonschema 4.26.0, Git 2.55.0, SQLite 3.53.4에서 toolkit 61개 파일의 소스/설치 해시가 모두 일치했다. 같은 사본으로 설정, 코드 AC 누락 반려, 작성자 수정, 새 독립 리뷰, B 적용, C 변경, 적용 중 종료와 새 컨텍스트의 직접 완료를 수행했다. 최종 문서 바이트가 검토된 수정안과 같고 active는 null, 기준은 C 커밋 `e9aac096b0d8b01ef3f2aae55f9bf0006fd527e0`이다.

정상 문서 5개 AC는 모두 통과했다. 예외 누락·거짓 완료 변형은 각각 CUR-2/TGT-2에서 실패했고, 복원본은 새 독자와 독립 재판정에서 5개 모두 통과했다. 분류 결과는 코드=문서 갱신 대기, 표현=코드 작업 불필요, 문서 동작/사용자 목표=구현 대기다. 네 입력 모두 문서 품질·구현·배포 완료를 분류 결과로 주장하지 않았다.

## 고정 기준별 증거

아래 `roles/…`, `state/…`는 원본 묶음 내 키다. 테스트는 [source-contract](../../../../tests/knowledge/source-contract/)의 실제 실행 결과이며 모델 관측으로 계산하지 않는다.

| ID | 현재 판정 | 증거와 경계 |
|---|---|---|
| S1-01-a | pass | 같은 복사 설치의 doctor/init/start 명령 원본. `test_missing_skill_dependency_blocks_before_mutation`의 변경 전 거절. |
| S1-01-b | pass | `roles/writer-b.json`, `review-initial.json`, `review-b.json`, `handoff.json`의 실제 설치 지침 읽기와 도구 실행. |
| S1-02-a | pass | `roles/classifier.json`, 접수 원문과 결과, `test_intake.py` 4개 검사. |
| S1-02-b | pass | `test_intake_binds_packet_and_legacy_ready_cannot_apply`; AC/권위 각각 변경 및 이전 리뷰 거절. M1 독립 대조는 수정 전 동일 ID/잘못된 리뷰 수용을 확인. |
| S1-02-c | pass | foundation 재생 통과. 과거 v1 원본 불변, v2 접수에 과거 리뷰 거절을 별도 검사. 새 v2 의미 리뷰는 이번 실제 응답. |
| S1-03-a | pass | B의 의도적 결함 수정안 → 실제 독립 반려 → 새 작성자 수정 → 새 리뷰 → 적용 → C 작성/리뷰. |
| S1-03-b | pass | 실제 `classifier`의 원문 해석·표현 비교, `state/classification-results.json`의 4개 경로 및 완료 경계. |
| S1-03-c | pass | `state/before-handoff.json`은 applying. 새 child가 공개 CLI를 직접 실행하여 완료한 `roles/handoff.json`; 부모 대리 실행 없음. |
| S1-04-a | pass | `test_two_distinct_changes_advance_baseline_and_repeat`, `test_active_run_and_database_lock_block_competing_writes`. |
| S1-04-b | pass | context 4종×6경로, packet/completion 손상·원본 보존 검사. 수정 전 24경로의 잘못된 수용을 독립 재현. |
| S1-04-c | pass | 실제 종료 rc91 → 새 child resume → 검토 문서와 정확히 일치. 독립 편집 거절과 기준 단일 전진은 source-contract 검사. |
| S1-04-d | pass | `test_terminate_retire_and_successor_preserve_evidence`, 손상 DB/지원하지 않는 스키마/손상 context 종료 검사. |
| S1-05-a | pass | 실행 전 frozen 설치 manifest와 문서 authority/AC/질문/입력 해시. 수정본은 별도 version 2 기록. |
| S1-05-b | pass | 새 normal/variant/repair 독자와 `document-judge`, `document-repair-judge`. 변형의 2개 실패 보존, 복원본 새 응답으로 전부 통과. |
| S1-05-c | pass | `review-initial`의 source_fidelity=pass, decision_coverage/uncertainty=fail, verdict=revise. |
| S1-06-a | pass | 설치 61개 해시 일치, 같은 프로젝트의 B/C 명령·응답·적용/중단/인계 기록. |
| S1-06-b | pass | 같은 설치의 새 classifier와 fresh handoff. 준비된 접수 JSON 수용 검사만으로 대체하지 않음. |
| S1-06-c | 독립 판정 대기 | 이 표와 원본을 독립 evaluator가 대조한 뒤 원장 acceptance 및 현재 상태에 반영. |

## 검증과 제한

M1 독립 판정은 MATCH다. source-contract 52개, document-ac 7개, measurement 10개, foundation 재생, 저장소 게이트와 diff 검사를 통과했다. 전체 `tests/run-all.sh`는 실행하지 않았다. M1 회귀 결과와 이번 실제 모델 응답은 별도 근거다.

한 리뷰어의 복합 읽기 명령이 역할 식별 가드에 거절되어 실패를 보존하고, 허용된 단순 파일별 읽기로 회복했다. 가드를 바꾸지 않았다. 한 독자 생성은 동시 실행 한도로 실패해 빈 응답으로 보존하지 않고, 여유가 생긴 뒤 새 실행을 관측했다. 추가 사용자 결정은 필요하지 않았다.

관측은 합성 로컬 프로젝트와 prompt-only child 분리에 한정된다. marketplace 자동 로딩, 앱 재시작·새 최상위 작업, 다른 OS, native 강제, 인간 사용성, 실제 서버·배포, 3단계 구현은 여전히 미검증/제외다. 초기 결함과 과거 관측을 지우거나 현재 버전의 성공 근거로 바꿔 쓰지 않았다.
