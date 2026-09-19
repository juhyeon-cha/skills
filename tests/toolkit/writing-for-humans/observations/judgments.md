# Independent judgments

Parent-recorded returns from `/root/doc_judge`. The initial compound read was denied
(`GUARD-DENY: UNREACHED — child role is unidentified`). Subsequent single literal
`cat` commands were permitted and the judge completed the specified read scope.
These are ordinary collaboration observations, not native role receipts.

## A, B, C — returned judgment

소스 실행 분기와 문서 인용을 대조한 결과입니다. 답변과 인용을 합쳐 필수 명제 충족 여부를 판단했습니다.

| 질문 | A: normal | B: missing-exception | C: resend |
|---|---|---|---|
| q1 | PASS | PASS | PASS |
| q2 | PASS | PASS | PASS |
| q3 | PASS | PASS | **FAIL** |
| q4 | PASS | PASS | PASS |
| q5 | PASS | **FAIL** | PASS |
| q6 | PASS | PASS | PASS |
| q7 | PASS | PASS | PASS |
| q8 | PASS | PASS | PASS |
| q9 | PASS | PASS | PASS |
| q10 | PASS | PASS | PASS |

- **B/q5 — 문서 완결성 실패:** 500 이후 입력창 재개방 여부는 읽을 수 있지만, 질문 초안 삭제와 제공자 확인 상태를 추가하지 않는다는 필수 정보가 빠져 있습니다. 독자의 “정보 부족”은 정직한 응답이지만 인수 기준을 충족하지 않습니다.
- **C/q3 — 사실 정확성 실패:** 독자는 문서를 정확히 읽었지만, “인증 확인 결과이므로 질문을 추가 전송한다”는 문서 내용이 소스와 모순됩니다. `submitPasswordModal`은 실제 질문을 한 번 보내고, 최종 200에서 확인 상태·암호 저장과 입력 정리만 수행합니다.
- **인용 검증:** 확인한 모든 인용은 해당 문서에 있습니다. C의 q3·q6·q7·q10은 여러 발췌를 줄바꿈으로 연결했으며, 이를 잘못된 인용으로 판정하지 않았습니다. B/C q7의 중단 요청 명제는 인용에 명시되어 있습니다.

| 역할별 안내 | 공통 정책 일관성 | 소스 근거 |
|---|---|---|
| FE | PASS | PASS |
| 서비스 기획 | PASS | PASS |
| UI/UX | PASS | PASS |

역할별 안내는 원본 `documents/policy.md`를 공통 기준으로 사용하며, 실제 화면 검증·접근성·사용자 이해도는 수행할 과제나 미확인 범위로 구분합니다. 확인된 동작처럼 꾸민 추가 주장은 발견하지 못했습니다.

**근거 없는 주장:** C 문서의 “최종 200 응답은 인증 확인 결과이며 별도 분석 요청으로 재전송한다”는 주장. A·B 및 원본 역할 안내에서 추가로 발견한 근거 없는 사실 주장은 없습니다.

범위는 제공된 정적 소스·문서·독자 응답에 한정하며 브라우저 동작이나 원격 저장소 원본 해시는 검증하지 않았습니다.

## D — returned repair judgment

D 문서는 필수 동작을 모두 포함하지만, 독자 응답의 인용은 3개 질문에서 부족합니다.

| 질문 | 문서 정확성·완결성 | 독자 인용 충족 |
|---|---|---|
| q1 | PASS | PASS |
| q2 | PASS | PASS |
| q3 | PASS | **FAIL** |
| q4 | PASS | PASS |
| q5 | PASS | PASS |
| q6 | PASS | **FAIL** |
| q7 | PASS | PASS |
| q8 | PASS | PASS |
| q9 | PASS | PASS |
| q10 | PASS | **FAIL** |

- **q3:** 답변은 정확하지만 반환한 인용에 “같은 제공자의 다음 질문에는 암호 입력창을 다시 열지 않는다”는 근거가 없습니다. 최종 200 및 기타 실패 행만 인용했습니다.
- **q6:** 답변은 정확하지만 인용에 `turn-error`의 최종 상태를 **502**로 해석한다는 필수 명제가 없습니다.
- **q10:** 인용은 정책 결정 배경을 알 수 없다는 점만 뒷받침합니다. 정적 소스 분석이며 브라우저 실측이 아니라는 필수 명제의 인용이 빠졌습니다.

q7은 중단 요청이 답변 본문에는 없지만 반환한 인용에 명시되어 있어 충족합니다. 모든 인용 자체는 문서에 실제 존재하며 잘못된 인용은 없습니다.

**결론:** B/q5의 문서 누락은 수정되었습니다. D 문서에서 근거 없는 사실 주장은 발견하지 못했습니다. 엄격한 인용 기준에 따른 D 독자 응답은 **7/10 PASS**입니다.

## E — returned final judgment

E는 **10/10 PASS**입니다. 문서 정확성·완결성과 반환 인용의 필수 명제 충족을 각각 확인했습니다.

| 질문 | 문서 | 독자 응답·인용 |
|---|---|---|
| q1 | PASS | PASS |
| q2 | PASS | PASS |
| q3 | PASS | PASS |
| q4 | PASS | PASS |
| q5 | PASS | PASS |
| q6 | PASS | PASS |
| q7 | PASS | PASS |
| q8 | PASS | PASS |
| q9 | PASS | PASS |
| q10 | PASS | PASS |

D에서 빠졌던 q3의 다음 질문 처리, q6의 최종 502, q10의 정적 분석·실환경 미검증 근거가 모두 반환 인용에 포함되었습니다. q7의 진행 요청 중단 명제 역시 인용에서 확인됩니다. 각 인용은 문서의 정확한 발췌이며, 근거 없는 사실 주장은 발견하지 못했습니다.

한계: 제공된 고정 소스와 문서에 대한 단일 독자 관찰입니다. 브라우저·서버 실제 동작이나 반복 실행의 재현성까지 입증하지는 않습니다.
