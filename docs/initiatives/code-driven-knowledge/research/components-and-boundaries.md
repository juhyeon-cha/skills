# 라이브러리·CLI·에이전트의 책임 경계

코드 기반 지식 자동화를 모두 스킬로 구현하면 반복 가능한 파일 처리와 실행 상태까지 모델 판단에 의존한다. **기존 부품으로 표준 처리를 재사용하고, 작은 CLI로 근거 버전과 반영 조건을 관리하며, 에이전트에는 의미 해석·작성·독립 리뷰를 맡기는 구성을 권장한다.** CLI는 명령줄에서 실행하는 프로그램이며 라이브러리와 에이전트를 연결할 수 있다. 세 가지는 서로 배타적인 선택지가 아니다.

조사 기준일: 2026-09-20. 공식 문서·저장소와 현재 평가 코드를 읽었다. 제품 기능은 출처에서 확인한 사실이고, 우선순위와 책임 분리는 이 프로젝트에 대한 제안이다. 설치·성능 비교·유료 서비스 호출은 하지 않았다. 성숙한 후보를 찾은 것이며 우리 환경의 적합성을 실증한 것은 아니다.

## 기존 부품으로 커버할 영역

“상용”은 유료 관리형 제품과 상용 서비스에서 사용할 오픈소스를 구분했다. 라이선스는 확인한 프로젝트의 표시이며 도입 버전의 부속 파서·플러그인·모델·서비스 약관까지 포괄하지 않는다.

| 영역 | 후보와 확인한 기능 | 자체 책임으로 남는 것 | 권고 |
|---|---|---|---|
| 변경 파일·원본 확보 | Git CLI: 커밋 간 diff, 파일 상태, 이름 변경 탐지 | 기준 커밋·근거 ID·삭제 이후 문서 처리 | 바로 재사용 |
| 코드 구조 추출 | Tree-sitter: 구문 트리와 언어별 파서 | 도메인 단위·심벌의 지속 식별·정책 영향 | 다언어 함수·구간 추출 시 검토 |
| Markdown 해석 | markdown-it-py 또는 remark: 표준 문법 파싱 | 근거 연결·문서 규약 | 현재 Python 평가 코드에는 markdown-it-py 우선 비교 |
| 자료 계약 검사 | jsonschema / check-jsonschema: JSON 구조 검사 | hash·파일 간 ID 참조·버전 일치 | 다음 단계 우선 후보 |
| 링크 검사 | lychee: 로컬·URL 검사, 오프라인 모드 | 게시 환경의 앵커 규칙·원격 검사 정책 | 자체 범용 구현 전에 비교 |
| 평가 실행 | Promptfoo: 사용자 정의 검사·모델 판정·기존 출력 평가 | 원본 기반 정답·독립 입력·필수 통과 조건 | 평가 실행기 자체 구현 전에 비교 |
| 검색용 수집·색인 | LlamaIndex: 변환 캐시·문서 ID/hash 기반 중복 처리 | 코드 의미·도메인 문서 갱신·폐기 | 검색 요구가 생길 때 |
| PDF·Office 입력 | Unstructured OSS / 관리형 API: 문서 요소 추출 | 추출 오류·코드 관계·도메인 의미 | 비정형 입력이 범위에 들어올 때 |
| 장시간 작업 복구 | Temporal OSS / Cloud: 실행 이력·재시도 | 외부 쓰기 중복 방지·Worker 운영 | 복구 운영이 실제 병목일 때 |

Git은 `--name-status`, `-z`, 이름 변경 탐지를 제공한다. 이름 변경 탐지는 유사도 기반이므로 같은 도메인 개념이라는 판정으로 확대하지 않는다. Tree-sitter는 구문 구조를 제공하며, TypeScript의 타입·심벌 관계가 필요하면 Compiler API도 후보이다. 제품 정책의 의도는 별도 근거가 필요하다. [Git diff](https://git-scm.com/docs/git-diff), [Tree-sitter](https://tree-sitter.github.io/tree-sitter/), [TypeScript Compiler API](https://github.com/microsoft/TypeScript/wiki/Using-the-Compiler-API)

markdown-it-py는 CommonMark 기반 파서이고, remark는 Markdown 구문 트리와 CLI를 제공한다. jsonschema는 구조 검증, check-jsonschema는 그 명령줄 실행을 맡는다. lychee의 `--offline`은 네트워크 요청을 막고 로컬 파일을 검사한다. 한국어 중복 제목과 게시 시스템의 앵커 규칙까지 기대와 일치하는지는 우리 사례로 확인해야 한다. [markdown-it-py](https://markdown-it-py.readthedocs.io/en/latest/), [remark](https://github.com/remarkjs/remark), [jsonschema](https://github.com/python-jsonschema/jsonschema), [check-jsonschema](https://check-jsonschema.readthedocs.io/en/latest/), [lychee](https://github.com/lycheeverse/lychee)

Tree-sitter, markdown-it-py, remark, jsonschema, Promptfoo는 MIT를 표시한다. lychee는 MIT 또는 Apache-2.0 선택이다. 유료 SaaS 구매 없이 평가할 수 있지만, 별도 모델 호출·서비스 사용 비용은 구분해야 한다. [Tree-sitter 라이선스](https://github.com/tree-sitter/tree-sitter/blob/master/LICENSE), [markdown-it-py 라이선스](https://github.com/executablebooks/markdown-it-py/blob/master/LICENSE), [remark](https://github.com/remarkjs/remark), [jsonschema](https://github.com/python-jsonschema/jsonschema), [Promptfoo](https://github.com/promptfoo/promptfoo), [lychee 라이선스](https://github.com/lycheeverse/lychee#license)

### 평가 도구가 정답을 대신 소유하지 않는다

Promptfoo는 Python·JavaScript 사용자 정의 검사와 `llm-rubric` 같은 모델 판정을 지원한다. `providerOutput`에 기존 응답을 넣으면 생성 provider 호출을 생략한다. 따라서 저장된 독자 응답으로 연동부터 비교할 수 있다. 단, 모델 판정 assertion에는 별도 grader 호출이 필요하므로 기존 출력 평가가 곧 모델 호출 없음은 아니다. [Assertions](https://www.promptfoo.dev/docs/configuration/expected-outputs/), [모델 판정](https://www.promptfoo.dev/docs/configuration/expected-outputs/model-graded/), [providerOutput](https://www.promptfoo.dev/docs/configuration/reference/)

평가 도구를 도입해도 필수 명제와 결함 사례는 우리 자산이다. 원본에서 기대 결과를 먼저 정하고, 독자에게는 문서·질문만, 판정자에게는 근거·기대 명제·문서·독자 반환을 전달한다. 평균 점수가 높아도 필수 예외 하나의 실패를 가리지 않는다. 별도 모델 호출은 독립 검토 기록이지 오류의 통계적 독립성 보장이 아니다.

Promptfoo의 기본 telemetry와 업데이트 확인은 끌 수 있다. 원격 모델·grader 전송은 별개다. 최초 비교는 저장된 출력과 결정적 검사로 한정하고, 현재 앱의 서브에이전트 호출을 외부 CLI가 그대로 사용할 수 있다고 가정하지 않는다. [Telemetry 설정](https://www.promptfoo.dev/docs/configuration/telemetry/)

### 관리형 제품은 요구가 생기는 지점에서 도입한다

LlamaIndex는 MIT 프레임워크다. IngestionPipeline은 문서 저장소와 vector store를 연결하면 동일 ID의 hash 변경에 따라 재처리·upsert하고, 동일 hash는 건너뛴다. vector store 없이 사용하는 경우의 문서 관리는 중복 제거에 한정된다. 안정적인 ID가 필요하고, 실행 간 캐시를 재사용하려면 영속화가 필요하다. 모델·임베딩·저장소 구성에 따라 외부 전송이 발생할 수 있다. 이 기능은 검색용 데이터 처리이며 도메인 문서의 사실·예외를 정확히 갱신했다는 보장은 아니다. 현재는 Git과 manifest로 시작하고 검색 요구가 생길 때 검토한다. [공식 파이프라인](https://developers.llamaindex.ai/python/framework/module_guides/loading/ingestion_pipeline/), [라이선스](https://github.com/run-llama/llama_index/blob/main/LICENSE)

Unstructured OSS는 Apache-2.0이며 관리형 API/Pipelines와 기능·운영 방식이 다르다. PDF·Office 입력에는 가치가 있지만 지금의 Git 코드·Markdown에는 우선순위가 낮다. 로컬 실행에는 파서·OCR 의존성 관리가 남고, 관리형 호출에는 문서 전송과 서비스 비용이 따른다. 데이터 보존·지역·추가 모델의 조건은 도입 시 별도 확인해야 한다. [OSS와 API 비교](https://docs.unstructured.io/open-source/introduction/overview), [라이선스](https://github.com/Unstructured-IO/unstructured/blob/main/LICENSE.md)

Temporal 서버는 MIT이고 Cloud는 별도 관리형 서비스다. Cloud도 애플리케이션 Worker를 대신 운영하지 않는다. Activity 재시도가 있으므로 외부 쓰기에는 멱등성, 즉 같은 요청을 반복해도 효과가 중복되지 않는 처리가 필요하다. 하네스를 당장 교체하기보다 긴 작업 복구가 병목일 때 하위 실행 엔진으로 검토한다. [Activities](https://docs.temporal.io/activities), [Cloud 실행·데이터 경계](https://docs.temporal.io/evaluate/cloud/security), [서버 라이선스](https://github.com/temporalio/temporal/blob/main/LICENSE), [Cloud 과금](https://docs.temporal.io/cloud/pricing)

검색도 처음부터 vector DB를 전제하지 않는다. 식별자·파일·근거 ID 검색으로 시작하고 전문 검색이 필요하면 SQLite FTS5 등을 비교할 수 있다. 한국어 검색 품질과 임베딩의 추가 효과는 실제 질문으로 판단한다. [SQLite FTS5](https://www.sqlite.org/fts5.html)

## 별도 CLI로 구현할 영역

자체 CLI는 우리 자료 계약과 반영 규칙을 맡는 작은 연결부로 제한한다. 아래 명령 이름은 제안이며 아직 구현되지 않았다.

| 제안 작업 | 입력 → 출력 | 보장할 조건 |
|---|---|---|
| `capture` | 저장소·고정 커밋·범위 → 근거 묶음 | 원본 hash·경로·심벌·추출기 버전 기록 |
| `diff` | 이전·이후 근거 → 변경과 영향 후보 | 추가·삭제·이름 변경 처리, 명시적 참조 영향과 미확정 의미 영향 구분 |
| `prepare` | 근거·질문·문서 → 역할별 입력 | 독자 입력에서 코드·정답 분리, 전달 바이트 보존 |
| `check` | 문서·독자 반환·독립 판정 → 검사 결과 | 구조·링크·인용 존재·버전 확인, 필수 의미 판정의 누락·실패 검출 |
| `apply` | 통과한 변경·기준 버전 → 로컬 반영 결과 | 검토한 문서 hash·현재 기준 재확인, 중복 반영 방지, 실패 시 기존 지식 유지 |

manifest는 입력 버전·도구·프롬프트·모델 설정·산출물 hash·실패 사유를 담는 실행 명세다. 실제 모델 ID를 모르면 unknown으로 기록한다. 담당·승인·스토리 완료 상태는 기존 하네스 원장이 소유한다. 실행 manifest를 또 하나의 업무 원장으로 만들지 않는다.

재실행에서는 같은 근거·변환 버전의 중복 반영을 막되 LLM이 같은 문장을 다시 만든다고 가정하지 않는다. 원래 출력과 재시도 출력을 보존하고 오래된 기준의 결과는 반영 전에 거절한다. CLI 성공은 원격 게시·PR·삭제 등의 승인 경계를 대신하지 않는다.

현재 [check.py](../../../../tests/knowledge/document-ac/check.py)는 Markdown 링크·앵커를 정규식으로 처리한다. 범위를 넓힐 때 문법 처리는 기존 파서·링크 도구로 넘기고, 근거 hash와 사례별 식별자 일치 규칙을 남기는 편이 적절하다. [packets.py](../../../../tests/knowledge/document-ac/packets.py)의 결함 주입은 특정 문장·표 행에 결합된 실험 자료이므로 범용 문서 편집 CLI로 그대로 승격하지 않는다.

## 에이전트의 영역과 완료 경계

| 판단 | 주 담당 | 산출물과 한계 |
|---|---|---|
| 코드 변화가 정책·사용자 행동에 미치는 영향 | 에이전트 + 정적 분석 | 출처가 연결된 영향 설명. 실환경 동작은 실행 검증 필요 |
| 기존 지식의 유지·수정·통합 | 에이전트 | 변경 제안과 미확정 항목. 제품 정책 변경 승인을 대체하지 않음 |
| 독자에게 필요한 설명 | 작성 에이전트 + writing-for-humans | 공통 정책과 직무별 설명 |
| 원본·필수 예외·인용의 의미 일치 | 작성자와 분리된 판정 에이전트 | 항목별 판단과 근거. 문서만 읽는 독자는 별도 입력을 받음 |
| 파일·스키마·hash·인용 문자열의 일치 | CLI·라이브러리 | 재현 가능한 검사. 인용이 주장을 뒷받침하는지는 의미 판정 |
| 검토 결과의 현재 버전 반영 | CLI 조건 검사 + 승인 정책 | 판정 누락·실패·입력 변경 시 반영 거절 |
| 근거로 해결할 수 없는 정책 선택 | 사용자 | 실제 충돌과 승인 범위 변경에 한정해 개입 |

에이전트가 명령을 실행해도 정확성이 자기 보고에 달려서는 안 된다. 에이전트는 근거를 해석해 변경안을 만들고, 기록·검사·반영은 명시적 계약을 통과한다. 스킬은 판단과 도구 사용 절차를 설명하고 반복 처리는 CLI를 호출한다. 역할마다 새 스킬을 하나씩 만들 필요는 없다.

일반 문장 수정·누락 인용 보완·근거로 해소 가능한 충돌은 내부에서 처리한다. 실패를 통과로 바꾸기 위해 기대 결과를 완화하지 않는다. 새 근거에 따라 기대 결과를 바꿀 때는 별도 버전과 독립 검토를 남긴다.

## 권장 도입 순서와 다음 실험

1. **자료 계약:** 근거·변경·주장·문서·판정을 연결하는 ID와 버전 규칙을 정하고 JSON Schema로 형태를 검사한다.
2. **검사 교체 비교:** 참조형 링크, 코드 블록 속 가짜 링크, 한국어 중복 제목, 파일 삭제 사례로 기존 파서·링크 도구를 비교한다. 확인한 범위만 교체한다.
3. **평가 실행기 비교:** 저장된 A–E 응답을 Promptfoo의 기존 출력 평가와 사용자 정의 검사에 연결한다. 기대 명제를 유지하고 인용 누락 실패가 보존되는지 확인한다. 외부 모델 호출 없는 부분부터 진행한다.
4. **변경 전후 사례:** 정상 변경, 같은 변경 재실행, 삭제·이름 변경, 오래된 기준, 중간 실패 후 재개에서 영향 목록·수정안·판정·반영을 확인한다.

완료 조건은 도구 설치가 아니다. 기존 정상·결함 판정이 유지되고 추가 문법 사례의 오판이 드러나며, 중복·실패·오래된 결과가 현재 지식을 훼손하지 않아야 한다. 실행 시간·모델 호출 수·수동 개입 횟수도 측정한 뒤 운영 부담과 함께 선택한다.

권장 출발점은 **기존 Git + 계약 검사 라이브러리 + 작은 CLI + 제한된 에이전트 판단**이다. Promptfoo는 비교 실험 후보이고, LlamaIndex·Unstructured·Temporal은 검색·입력·복구 요구가 생길 때 채택한다. 라이브러리 버전과 최종 선택은 아직 확정하지 않았다.
