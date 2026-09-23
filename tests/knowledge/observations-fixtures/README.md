# SAP 객체 export 예제

`sap-show-id-v1.json`과 `sap-show-id-v2.json`은 실제 고객 데이터가 아닌 합성 입력이다.
2026-09-24 확인한 sap-harness `189fc239`의 `graph show-id` 반환 구조를 따른다.
v1은 complete이고 v2는 같은 객체의 이전 성공 구조를 보존한 partial/stale 관측이다.
이를 SAP 실측이나 실제 업무 동작의 증거로 사용하지 않는다.

작성·갱신 예제에서는 같은 source/object를 유지하며 원 관측 상태를 그대로 가져온다.
완료된 지식의 독립 검토를 테스트 안에서 구성한 synthetic review와 구분한다.
