# 스냅샷 JSON 스키마

`extract-spring.py` 와 `extract-fastapi.py` 가 내는 JSON 의 형태다. **두 추출기의 출력 형태는
같다** — 이 형태가 프레임워크 중립 diff 의 인터페이스이기 때문이다. 프레임워크마다 다른 것은
값뿐이고 키는 다르지 않다.

값은 전부 **소스에 적힌 문자열 그대로**다. 타입을 해석하거나 정규화하지 않는다 —
`List<Pet>` · `ItemPublic` · `str | None` 은 그 프레임워크가 쓴 표기 그대로 담긴다.

## 최상위 키 (넷 다 항상 있다)

| 키 | 타입 | 내용 |
|---|---|---|
| `framework` | string | 추출기 식별자. `"spring"` 또는 `"fastapi"` |
| `endpoints` | array | 엔드포인트 목록. **1건 이상** — 0건이면 추출기가 종료 코드 0 을 내지 않는다 |
| `models` | array | 요청·응답에 쓰이는 구조 목록. **1건 이상** |
| `enums` | array | 열거형 목록. **빈 배열일 수 있다** |

## `endpoints[]` 의 키 (넷 다 항상 있다)

| 키 | 타입 | 내용 |
|---|---|---|
| `method` | string | HTTP 메서드 대문자. Spring 은 `GET` · `POST` · `PUT` · `PATCH` · `DELETE`, FastAPI 는 여기에 `HEAD` · `OPTIONS` · `TRACE` 가 더 나올 수 있다 |
| `path` | string | 접두사를 이어 붙인 경로. 항상 `/` 로 시작하고 끝의 `/` 는 떼어낸다 |
| `request` | string \| null | 요청 본문 타입 이름. 본문이 없으면 `null` |
| `response` | string \| null | 응답 타입 이름. 알 수 없으면 `null` |

- `path` 의 접두사: Spring 은 클래스 레벨 `@RequestMapping`, FastAPI 는 `APIRouter(prefix=...)`.
- `request` 의 출처: Spring 은 `@RequestBody` 가 붙은 파라미터, FastAPI 는 타입이 `models` 에
  있는 파라미터.
- `response` 의 출처: Spring 은 메서드 반환 타입(`void` 도 그대로 담긴다), FastAPI 는
  `response_model=` 이고 없으면 함수 반환 애노테이션.

## `models[]` 의 키

| 키 | 타입 | 내용 |
|---|---|---|
| `name` | string | 선언 이름 |
| `fields` | array | `{"name": string, "type": string}` 의 목록. 필드가 없으면 빈 배열 |

대상: Spring 은 `record` 와 `@Entity` 클래스, FastAPI 는 `SQLModel`·`BaseModel` 을 상속으로
이어받은 클래스 전부.

**`name` 은 유일하지 않다.** 멀티 모듈 레포는 모듈마다 같은 이름의 DTO 를 따로 선언한다
(예: 이 샘플의 `PetDetails`). 필드가 다르면 서로 다른 항목으로 둘 다 담긴다.

## `enums[]` 의 키

| 키 | 타입 | 내용 |
|---|---|---|
| `name` | string | 선언 이름 |
| `values` | array | 상수 이름 문자열의 목록 |

## 순서와 결정론

같은 입력에 두 번 돌린 출력은 **바이트로 같다.** 세 목록은 각 항목의 정렬된 JSON 표기를
키로 정렬하고 중복은 지운다. 최상위 키도 정렬한다. 파일 경로·시각·절대 경로는 담지 않는다 —
담으면 실행 위치가 달라질 때 diff 가 흔들린다.

## 예

```json
{
  "framework": "spring",
  "endpoints": [
    { "method": "POST", "path": "/owners/{ownerId}/pets", "request": "PetRequest", "response": "Pet" }
  ],
  "models": [
    { "name": "PetType", "fields": [ { "name": "name", "type": "String" } ] }
  ],
  "enums": []
}
```

이 스키마를 만족하는지는 같은 폴더의 `check.sh` 가 단언한다.
