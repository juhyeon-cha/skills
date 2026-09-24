# 근거와 검증 경계

합성 입력 v1을 정적으로 읽은 기록이다. 실제 서비스 정책·사용자 관측·API 실행·배포 증거가 아니다. 문서의 독립 검토 상태는 대기이며, 렌더링과 브라우저 관찰도 이 작성 단계에서는 수행하지 않았다. [안내 본문](guide.md#주문-취소를-구현하고-판단하기)으로 돌아갈 수 있다.

## 입력 분류

- `service.py`, `screen.py`: 현재 합성 구현의 정적 근거. 운영 보장이나 사업 결정 이유를 입증하지 않는다.
- `decisions.md` P1: 가상 확정 범위. 실제 서비스 승인이 아니다.
- `decisions.md` O1: 합성 제보와 미측정 사항. 실제 고객 관측이나 효과 측정이 아니다.
- `decisions.md` D1: 우선 검토안·대안 의존성·지표 후보 및 미정 사항. 출시 승인이 아니다.
- `questions.json`: FE·BE·기획·PO의 읽기 과제 12개. 정책 근거는 아니다.

## 버전

문서 manifest의 revision은 `synthetic-order-cancellation-input-v1`이다. 이는 합성 입력을 지칭하는 논리 버전이며 소스 Git 커밋이나 최신 운영 배포가 아니다. 정확한 파일 바이트는 아래 SHA-256으로 식별한다.

| 입력 경로 | SHA-256 |
|---|---|
| `tests/knowledge/reader-content/fixture/service.py` | `df8132595fa2c47dfa980418d30caf37cb9c153be4c4cb1721bf383168d7e068` |
| `tests/knowledge/reader-content/fixture/screen.py` | `f5f11cee9e38d28d42fa738a328c300934e731425b3d9d3589b6954d8022e434` |
| `tests/knowledge/reader-content/fixture/decisions.md` | `32c1547a8592aab0566f6b69b490d433f34f105076e0e9ce2dafe93e0e0c36f1` |
| `tests/knowledge/reader-content/questions.json` | `b6cb4a4cbfb8fa6df5856394c522c433a4bc862298b653dbab33057140db531e` |

## 서비스 원문

검사한 위치: `tests/knowledge/reader-content/fixture/service.py`. 아래는 파일 전체 원문이다.

```python
"""Synthetic cancellation service: static evidence, not a deployed API."""
from threading import Lock


class Orders:
    def __init__(self, orders):
        self.orders = orders
        self.lock = Lock()

    def cancel(self, order_id, actor):
        # One in-memory process only; no payment provider or durable storage.
        with self.lock:
            order = self.orders[order_id]
            if order['owner'] != actor:
                return {'status': 403, 'code': 'FORBIDDEN'}
            if order['state'] == 'cancelled':
                return {'status': 200, 'state': 'cancelled'}
            if order['state'] != 'paid':
                return {'status': 409, 'code': 'NOT_CANCELLABLE'}
            order['state'] = 'cancelled'
            return {'status': 200, 'state': 'cancelled'}
```


## 화면 원문

검사한 위치: `tests/knowledge/reader-content/fixture/screen.py`. 아래는 파일 전체 원문이다.

```python
"""Synthetic FE state model; response loss is separate from cancellation failure."""


def can_cancel(state, owner, viewer, pending):
    return state == 'paid' and owner == viewer and not pending


def outcome(response):
    if response is None:
        return {'message': '처리 결과 확인 필요', 'action': '주문 다시 조회'}
    if response['status'] == 200:
        return {'message': '주문 취소 완료', 'action': '목록으로 이동'}
    if response['status'] == 403:
        return {'message': '취소 권한 없음', 'action': '계정 확인'}
    if response['status'] == 409:
        return {'message': '취소 가능한 상태가 아님', 'action': '주문 다시 조회'}
    return {'message': '처리 결과 확인 필요', 'action': '주문 다시 조회'}
```


## 의사결정 원문

검사한 위치: `tests/knowledge/reader-content/fixture/decisions.md`. 아래는 파일 전체 원문이다.

```text
# 주문 취소 — 평가용 가상 의사결정 자료 v1

이 자료의 승인·제보는 모두 합성 평가 시나리오의 입력이다. 실제 서비스의 정책이나 사용자 관측이 아니다.

## 확정 범위 P1

이번 단계는 본인 주문의 결제 완료 상태에서 주문 취소 상태로 바꾸는 기능이다.
이미 취소된 본인 주문의 반복 요청은 취소 완료로 응답한다. 출고 이후 취소는 제외한다.
화면에서 응답을 받지 못한 경우 성공 여부를 단정하지 않고 주문을 다시 조회하도록 안내한다.

취소 상태 변경과 결제 환불은 다른 작업이다. 결제사 연동과 실제 환불은 이번 범위 밖이다.
취소 화면의 완료 문구는 환불 완료를 뜻하지 않는다. 환불 제공 시점과 운영 처리 주체는 미정이다.
환불 정책이 정해지기 전에는 이 기능만으로 고객에게 환불 완료를 약속할 수 없다.

## 문제 근거 O1

평가 시나리오에서 고객 두 명이 주문 취소 여부를 상담원에게 물었다는 제보만 있다.
발생 빈도·전체 고객 비율·상담 비용·기존 전환율은 측정하지 않았다.

## 제품 결정 D1

자기 주문의 취소 상태를 직접 확인하는 제한된 기능을 우선 검토한다.
결제 환불까지 한 번에 제공하는 대안은 외부 결제사 연동과 정책 결정이 필요하다.
성과를 판단할 지표 후보는 취소 결과 관련 문의 비율이다. 지표의 분모·관측 기간·목표치는 미정이다.
상담 문의 감소 효과는 입증되지 않았다. 출시 일정과 출시 승인은 이 자료에 없다.
```


## 읽기 과제

검사한 위치: `tests/knowledge/reader-content/questions.json`. ID별 질문은 다음과 같다.

- **FE1 · FE · 취소 화면 구현** — 취소 요청은 언제 허용하며 진행 중 추가 클릭은 어떻게 처리하나요?
- **FE2 · FE · 취소 화면 구현** — 응답을 받지 못했다면 사용자에게 어떤 상태와 다음 행동을 안내하나요?
- **FE3 · FE · 취소 화면 구현** — 403과 409 응답의 안내와 다음 행동은 어떻게 다른가요?
- **BE1 · BE · 취소 계약 구현** — 타인 주문과 이미 취소된 본인 주문에 대한 요청은 각각 어떻게 처리하나요?
- **BE2 · BE · 취소 계약 구현** — 취소할 수 있는 상태와 결과는 무엇이며 동시성 보장은 어디까지인가요?
- **BE3 · BE · 취소 계약 구현** — 취소 성공은 환불 성공을 뜻하나요? 저장·연동과 실행 검증의 범위는 어디까지인가요?
- **PL1 · 기획 · 정책과 수용 시나리오 정의** — 신규 취소, 반복 요청, 출고 이후 요청의 기대 결과를 어떻게 구분하나요?
- **PL2 · 기획 · 정책과 수용 시나리오 정의** — 응답이 유실되었을 때 정책과 관찰 가능한 수용 조건은 무엇인가요?
- **PL3 · 기획 · 정책과 수용 시나리오 정의** — 이번 범위에서 제외되거나 결정되지 않은 것은 무엇이며 어떤 약속을 막나요?
- **PO1 · PO · 범위와 성과 판단** — 이 문제의 실제 입력 근거는 무엇이며 규모와 효과까지 입증됐나요?
- **PO2 · PO · 범위와 성과 판단** — 현재 검토 범위와 대안의 차이 및 의존성은 무엇인가요?
- **PO3 · PO · 범위와 성과 판단** — 성과·출시를 판단하기 위해 무엇을 더 결정하거나 확인해야 하나요?
