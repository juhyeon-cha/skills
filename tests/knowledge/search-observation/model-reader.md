# 실제 독립 독자 응답

실제 호출: `/root/search_reader`, 별도 모델 context, 구현/정답표 미제공. 입력은 실제 HTTP `reader-packet.json`과 도착 HTML 5개만이다. 2026-09-23 13:45:59 UTC 직후 호출, 응답 수신은 13:47:53 UTC 시각 관측 이전이다. 정확한 모델 서비스 처리 시간·토큰·금액은 도구가 제공하지 않아 미측정이다. 질문 추가·사용자 개입은 0회다. 아래는 실제 반환 내용이다. fixture의 합성 검토 영수증과 구분한다.

제공된 검색 응답과 도착 문서 5개에서 다음을 확인했습니다. 답변 범위는 로컬 예제이며 운영 환경을 확인한 결과가 아닙니다.

1. **금액 필드 이름과 단위:** `total`, `KRW`, 정수입니다. 근거는 `producer` 저장소 `contract.md`의 **금액** 절입니다. URL: `/documents/producer/contract.md/#doc-%EA%B8%88%EC%95%A1`

2. **계약 변경 시 소비자 변경:** `amount`를 읽던 소비자 코드를 `total`을 읽도록 변경합니다. 근거는 `consumer` 저장소 `guide.md`의 **변경 영향** 절입니다. URL: `/documents/consumer/guide.md/#doc-%EB%B3%80%EA%B2%BD-%EC%98%81%ED%96%A5`

3. **운영 배포를 보장하는 검사:** 제공된 근거에는 없습니다. 로컬 계약 검사는 필드 전달과 정수 처리를 확인하며, 문서가 운영 배포는 검증하지 않았다고 명시합니다. 근거는 `consumer/guide.md`의 **검증** 절입니다. URL: `/documents/consumer/guide.md/#doc-%EA%B2%80%EC%A6%9D`
   응답의 `validation=verified`, `integration=verified`, `completion=complete`를 운영 배포 보장으로 해석할 수 없습니다. 모든 결과는 `review_synthetic=true`이고, 패킷은 검토 기록이 합성 자료라고 명시합니다.

4. **재시도 상한:** 최대 3회입니다. 근거는 `producer/contract.md`의 두 번째 **정책** 절입니다. URL: `/documents/producer/contract.md/#doc-%EC%A0%95%EC%B1%85-2`
   첫 번째 정책 절의 보관 기간 30일과 구분됩니다.

5. **JSON 예제:** `{"total":120}`입니다. 필드는 `total`, 값은 숫자 `120`입니다. 근거는 `producer/contract.md`의 **예제** 절입니다. URL: `/documents/producer/contract.md/#doc-%EC%98%88%EC%A0%9C`

6. **숨겨진 저장소나 오래된 본문에서 답할 수 있는가:** 해당 자료를 현재의 허용된 근거로 삼을 수 없습니다. `revoked` 응답은 `withheld_count=1`, `completion=incomplete`, `served=unavailable_or_partial`, 결과 0건입니다. `drift`도 불완전 상태이며 결과 0건입니다. 숨겨진 본문의 내용이나 저장소 이름은 추정하지 않습니다.
   다만 **오래된 색인과 오래된 본문은 다릅니다.** `stale_index` 응답은 `index=stale`이지만 `served=current`, `completion=complete`이며 금액 절을 반환합니다. 이 경우 응답이 현재 자료라고 표시한 반환 본문을 근거로 사용할 수 있습니다. 도착 페이지에는 요청 시 권한·근거를 재확인하고 이미 읽거나 저장한 내용은 회수하지 못한다고 명시돼 있습니다.

7. **`METADATA_ONLY_771`이 문서 근거로 검색되는가:** 제공된 해당 검색 결과는 0건입니다. 따라서 이 검색에서 문서 근거로 반환되지 않았습니다. 문자열이 모든 자료에 존재하지 않는다고까지 결론 내릴 근거는 없습니다.

8. **양자결제를 지원하는가:** 판단할 근거가 없습니다. 해당 검색은 결과 0건이고 도착 문서에도 지원 설명이 없습니다. 검색 실패를 미지원의 증명으로 해석하지 않습니다.

추가로 구분해야 할 근거와 모호함은 다음과 같습니다.

- `current`에 제공된 생산자·소비자 `app.py`는 각각 `value = 'total'`만 보여 줍니다. 현재 소스가 `total` 문자열을 사용한다는 점은 확인되지만, KRW 처리·재시도 구현·실제 필드 전달까지 이 코드로 증명되지는 않습니다.
- `goal=contract`, `version=v1`과 `target`은 목표 정보입니다. 목표 문구를 현재 구현이나 문서 본문의 사실로 사용하지 않았습니다.
- “최대 3회”가 최초 요청을 포함하는 전체 시도 횟수인지는 문서가 설명하지 않습니다. 재시도 상한 문구 그대로 답했습니다.
- 숨김·변경 감지 사례는 검색 응답만 제공됐으므로 직접 문서 URL 요청의 거부 동작까지 관찰한 것은 아닙니다.
- 문서의 외부 생산자 링크와 `/evidence/` 페이지는 열지 않았습니다. 지정된 패킷과 도착 HTML 외 자료는 읽지 않았고, 파일 변경·원격 호출은 하지 않았습니다.
