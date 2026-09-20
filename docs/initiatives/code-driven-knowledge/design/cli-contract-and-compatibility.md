# 1단계 후속: CLI 계약과 구버전 재개

호출자가 오류 문장이나 설치 경로에 의존하지 않고 실행본을 식별하며, 구버전 프로젝트를 이어갈 수 있도록 `knowledge.py`의 명령 계약을 고정한다. 스토리 [#345](https://github.com/juhyeon-cha/skills/issues/345)의 상세 설계이며, 구현·판정 상태는 원장에서 관리한다.

## 범위와 전제

기준 구현은 PR #344의 `215526b`다. 기존 CLI·상태 처리·저장 모듈 분리를 유지한다. 공개 계약은 `refresh-knowledge/scripts/knowledge.py`에 적용하며 `cli.py`, `impact.py`, `update.py`, `workflow.py`의 독립 명령 계약을 일괄 변경하지 않는다.

Python 배포를 유지한다. 실행 파일 배포는 지원 OS와 설치 요구가 정해질 때 별도로 판단한다. JSON 기능이 포함된 SQLite와 제외된 SQLite의 실물 검증은 실행 환경 진단의 근거이며, 자체 런타임을 제품에 번들해야 한다는 근거는 아니다.

DB 마이그레이션, 자동 재시도, 새 목표 상태, 이벤트 처리, 다중 저장소 저장 모델은 이번 범위에 없다. 현재 Python/Git/스킬 의존성 정책과 기존 승인 경계를 유지한다.

## 버전의 의미

| 이름 | 의미 | 변경 규칙 |
|---|---|---|
| `cli_contract` | 명령 입출력과 오류의 호환 계열 | 이번에 1을 부여한다. 기존 필드·코드의 제거, 타입/의미 변경은 호환 변경으로 간주하지 않는다. 추가 필드는 허용하며 소비자는 알 수 없는 필드를 무시한다. |
| `toolkit_version` | 배포된 플러그인의 버전 | 기존 `.claude-plugin/plugin.json`에서 읽는다. 이번 작업에서 릴리스 번호를 바꾸지 않는다. |
| `implementation_id` | 같은 배포 버전 안에서도 실제 CLI 소스 묶음을 식별하는 내용 해시 | scripts 아래 정렬된 상대 파일명과 `.py`·`requirements.txt` 바이트를 길이 구분해 SHA-256으로 계산한다. 경로·mtime·pycache는 제외한다. 인증 서명이나 전체 스킬 패키지 무결성 증명은 아니다. |
| DB·산출물 버전 | 저장 자료를 해석하는 형식 | SQLite user_version=1과 intake/packet 등의 기존 버전은 각각 유지한다. CLI 버전으로 자료 버전을 대체하거나 자동 마이그레이션하지 않는다. |

`--version`은 프로젝트 없이 stdout JSON/rc0로 `toolkit_version`, `implementation_id`, `_meta.cli_contract`를 반환한다. Python 표준 라이브러리로만 실행하고 Git 실행·jsonschema import·프로젝트 I/O를 하지 않는다. manifest 누락/손상은 오류이며 추정 버전을 반환하지 않는다. 런타임 의존성 검사는 `doctor`가 맡는다.

## 출력과 종료 코드

성공 결과의 기존 최상위 필드를 유지하고 `_meta: {"cli_contract": 1}`을 추가한다. 계약 메타데이터는 출력할 때만 붙이며 run/packet/review의 해시 입력이나 DB에 저장하지 않는다. `intake` 조기 반환도 같은 출력 경로를 사용한다.

| 결과 | stdout | stderr | 종료 코드 |
|---|---|---|---|
| 정상 명령·`--version` | JSON 객체 하나 | 비어 있음 | 0 |
| `--help`, 하위 명령 도움말 | 사용법 텍스트 | 비어 있음 | 0 |
| 잘못된 명령·옵션·필수 인자 누락 | 비어 있음 | 오류 JSON 하나 | 2 |
| 자료·환경·실행 실패 | 비어 있음 | 오류 JSON 하나 | 1 |

오류 응답은 기존 `error` 문자열과 `command`를 보존하며 `code`와 `_meta`를 추가한다. `command`는 인자 해석이 완료된 명령명이고 해석 전 실패는 null이다. 임의의 토큰을 명령명으로 추정하지 않는다. `error`는 설명이고 호출자의 분기는 `code`를 사용한다.

`{"_meta":{"cli_contract":1},"command":"status","code":"PROJECT_REQUIRED","error":"PROJECT_REQUIRED: supply --project"}`

기존 출력에 `_meta`가 없으면 이 계약 도입 전 CLI로 취급한다. 기존 error 문자열은 유지하지만 새 호출자가 문자열 파싱으로 후퇴하도록 권장하지 않는다. stderr와 stdout을 합쳐 JSON으로 읽는 방식은 지원하지 않는다. OS에 의한 강제 종료, Python 자체가 시작하지 못한 경우, stdout 파이프 소실은 정상 오류 응답 보장의 범위 밖이다.

## 오류 분류

| code | 판정 근거 |
|---|---|
| `USAGE_ERROR` | argparse가 거절한 입력 |
| 기존 도메인 코드 | 프로그램이 발생시킨 등록된 `PROJECT_REQUIRED`, `RUN_PHASE`, `CONTEXT_INVALID` 등의 기존 의미 |
| `DEPENDENCY` / `DEPENDENCY_UNREACHED` | 기존 진단 정책 또는 필수 모듈 부재 |
| `VALIDATION_ERROR` | JSON Schema 검증 실패 |
| `INPUT_ERROR` | 코드가 없는 일반 입력 ValueError |
| `NOT_FOUND` / `PERMISSION_DENIED` / `IO_ERROR` | 파일 오류의 실제 예외 타입 |
| `SQLITE_BUSY` | SQLite의 BUSY/LOCKED 오류 코드; 문장 비교로 분류하지 않음 |
| `DATABASE_ERROR` | 나머지 SQLite 오류 |
| `INTERNAL_ERROR` | 위 분류에 속하지 않는 예기치 않은 실패 |

도메인 코드가 현재 ValueError 문자열의 고정 접두사에 들어 있으므로, 이번에는 중앙 호환 어댑터에서 프로그램 소유 코드의 명시적 목록만 인정한다. 외부 오류·schema 예외·일반 사용자 문자열의 임의 접두사를 새로운 코드로 만들지 않는다. 예외 타입 우선순위와 코드 목록을 테스트한다. 모든 모듈을 새 예외 계층으로 재작성하는 변경은 필요하지 않다.

코드는 재시도 허가가 아니다. 예를 들어 SQLITE_BUSY는 다른 실행이 끝난 뒤 현재 상태를 조회할 근거이고, 반영 도중 실패는 `status --run`과 해당 복구 계약을 먼저 따른다. 이번 응답에는 추측한 `retryable`을 넣지 않는다.

## 구현 책임

- `knowledge.py`: 인자 처리, 필요한 모듈의 지연 import, 명령 연결, stdout/stderr/종료 코드 결정.
- 작은 `cli_contract.py`: 표준 라이브러리 기반 출력 메타데이터, 오류 분류, 배포/소스 식별. 상태 전이나 SQL을 알지 않는다.
- `project_service.py`·`project_store.py`: 기존 상태 전이와 v1 저장 의미 유지. 응답 메타데이터를 영속 자료에 넣지 않는다.
- 설치 참조 `references/cli-contract.md`: 현재 호출 계약의 단일 원본. 이 설계는 선택 이유·검증 범위를 설명하며 구현 완료 후 현재 계약을 중복 복사하지 않는다.

jsonschema가 없는 경우에도 `--version`, `--help`, 오류 직렬화가 작동해야 한다. 현재 `cli.py`의 import 실패 시 SystemExit를 public CLI 밖으로 유출하지 않도록 public 명령의 의존성 준비를 예외 경계 안에 둔다. 저수준 CLI 직접 실행의 기존 동작은 보존한다.

## 구버전 호환성 자료

구버전 `a1d5e15be20a9e1fa838809b09ae3b445dafc55f`를 사용해 실제 문서 반영 뒤 프로세스가 종료된 `applying` 프로젝트를 만든다. 기존 foundation Git 이력과 고정 packet/review를 입력으로 사용하고, 생성한 SQLite 데이터·산출물과 출처·체크섬을 개발 테스트 자료로 보존한다. 현재 코드로 옛 상태를 흉내 내 생성한 자료로 대체하지 않는다.

자료는 `tests/knowledge/` 아래에 둔다. 설치 패키지는 이를 포함하지 않는다. 원시 DB 또는 손실 없는 행/스키마 직렬화 중 테스트에서 검토 가능한 표현을 선택한다. 구버전 생성 절차는 명시적 재생성 도구로 두고 일반 검사에서 실행하지 않는다. 일반 검사는 네트워크나 옛 git 객체를 요구하지 않는다.

복원은 임시 디렉터리에만 한다. 로컬 이동에 필요한 설정의 repo/docs 절대 경로만 현재 fixture 위치로 바꾸며 원본 근거, run ID, packet, review, context 및 completion은 재작성하지 않는다. 경로를 바꾼 필드와 이유를 manifest에 명시한다. 구버전이 생성한 artifact 바이트의 체크섬을 먼저 검사한다.

현재 복사 설치본으로 다음을 검사한다.

1. 구버전 DB 스키마·user_version·applying 및 이미 반영된 문서를 확인한다.
2. resume이 완료되고 baseline만 검토한 다음 커밋으로 전진한다.
3. 기존 원본 근거·리뷰·산출물 바이트와 schema가 바뀌지 않는다.
4. 완료 후 다시 resume해도 논리 상태와 문서/산출물이 변하지 않는다.
5. 복제한 DB의 지원하지 않는 user_version을 명확히 거절하고 기존 자료를 바꾸지 않는다.

이 검사는 모든 역사적 버전 지원을 뜻하지 않는다. 고정 자료의 v1 중단 상태를 지원하는 회귀이며 fixture를 최신 코드 출력으로 자동 덮어써 검사를 통과시키지 않는다.

## 검증과 작업 순서

상세 설계·후속 단계 노트 → 명령 계약과 오류 회귀 → 실제 구버전 자료 고정과 재개 회귀 → 설치 계약 문서 정합성 → 독립 코드/수용 판정 순으로 진행한다. 명령 계약은 외부 호출자가 의존할 영역이므로 고정 base/head를 독립 평가자가 검토한다.

`KNOWLEDGE_PYTHON=<검증 환경 Python> bash tests/knowledge/source-contract-check.sh`가 새 계약·호환성 검사까지 실행해야 한다. 저장소 게이트는 `bash scripts/check.sh`다. 새 모델 실행, 다른 OS, 실행 파일 배포까지 검증했다고 확대하지 않는다.

2~5단계의 준비 사항은 각 [단계 문서](../roadmap.md#단계와-현재-위치)에 둔다. 이번 설계의 완료는 해당 기능의 구현 완료가 아니다.
