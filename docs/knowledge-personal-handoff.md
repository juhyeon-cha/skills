# 개인 업무 지식 호스트 연동 인계

기술 객체가 없어도 개인 업무 정의를 기록하고 자연어 분석 요청에 재사용하는 로컬 CLI를 구현했다. 정식 소스는 `skills/plugins/knowledge`이며, 변경은 `codex/personal-knowledge` linked worktree에 있다. main과 설치 캐시는 수정하지 않았다. 아래 계약은 구현되어 fixture로 실행한 동작이며, 제안용 API는 포함하지 않는다.

## 무엇을 사용할 수 있나

- `define`: 원문, AI 요약과 요약자, 출처, 개인·업무 범위, 용어·확인된 별칭·관련 검색어, 정의·예외, 근거 ID, 개정과 적용 기간을 저장한다. 기술 객체나 관측을 만들 필요가 없다. 자동 기억 기록은 추가하지 않았다.
- `retrieve`: 분석 LLM이 자연어 요청과 호스트가 제공한 범위로 자동 호출한다. 사용자가 지식을 먼저 선택할 필요가 없다. 등록 용어와 별칭으로 바꿔 쓴 질문을 검색한다. 같은 개념의 다른 정의를 함께 반환하며, 출처·사용자·업무 범위가 다른 정의는 적용하지 않는다. 개인 주장, 설명, 근거와 독립 검토를 구분한다.
- 정정은 이력을 남기는 새 개정이다. `change=correction`은 이전 타임라인 전체를 정정하고, `change=period`는 지정일부터 새 정의를 적용한다. 근거 관측 시각과 업무 적용 기간은 별도다.
- 근거가 변경되면 `stale`, 수집이 불완전하면 `evidence_pending`을 반환한다. 검토를 통과해도 `assertion=personal`은 유지되고 조직 승인은 항상 `not_asserted`다.

벡터 검색 없이 구현했다. 예제 원문과 두 paraphrase(바꿔 쓴 질문)는 기존 전체 단어 일치 방식으로 모두 누락됐고, 새 검색은 등록 용어·확인된 별칭·관련 검색어의 일치 이유를 구별해 반환했다. 임의의 모든 자연어 표현을 이해한다는 의미는 아니다. [평가 질문](../tests/knowledge/personal-knowledge/questions.json)에 검색 누락과 명시적 개념 ID 사용 사례도 있다.

## 호스트에서 어떻게 호출하나

아래는 새 테스트 notebook을 사용하는 실제 공개 호출 형태다. `NOTEBOOK`은 호스트가 정한 **새 경로**로 바꾼다. 기존 운영 데이터에 실행한 명령이 아니다.

```sh
WORKTREE=/private/tmp/skills-personal-knowledge
KNOWLEDGE_ROOT="$WORKTREE/plugins/knowledge"
NOTEBOOK=/absolute/new-personal-notebook
python3 "$KNOWLEDGE_ROOT/scripts/knowledge.py" --version
python3 "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project "$NOTEBOOK" notebook capabilities
python3 "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project "$NOTEBOOK" notebook init --source business:demo --audience user
python3 "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project "$NOTEBOOK" notebook define --input "$WORKTREE/tests/knowledge/personal-knowledge/personal.json"
python3 "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project "$NOTEBOOK" notebook define --input "$WORKTREE/tests/knowledge/personal-knowledge/sales-quantity.json"
python3 "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project "$NOTEBOOK" notebook retrieve --input "$WORKTREE/tests/knowledge/personal-knowledge/request.json"
python3 "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project "$NOTEBOOK" notebook get --source business:demo --id RECORD_ID
```

[정의 입력 v2](../tests/knowledge/personal-knowledge/personal.json)와 [판매량 정의](../tests/knowledge/personal-knowledge/sales-quantity.json)는 그대로 전송할 수 있다. 정의 저장 응답 v1의 `id`가 정확한 개정 ID이고, 후속 개정의 `previous`에 사용한다. `revision`은 1씩 증가한다.

조회 요청 v1:

```json
{
  "version": 1,
  "source": "business:demo",
  "audience": "user",
  "user": "owner",
  "context": {
    "company": "demo"
  },
  "as_of": "2026-10-01",
  "query": "10월 윤활유 판매량을 판매처별 제품별로 보고 현재 재고도 볼 거예요."
}
```

개인 정의 하나만 넣은 fixture의 실제 응답 v1에서 주요 필드를 발췌했다. 전체 `value`, 범위, 출처, 의존성과 제한을 포함한 응답은 [personal transcript](../tests/knowledge/personal-knowledge/responses/personal.json)의 마지막 `calls[].response`에 있다.

```json
{
  "version": 1,
  "outcome": "matched",
  "absence_established": false,
  "items": [
    {
      "id": "owner-lubricants",
      "revision": 1,
      "record_id": "748eccd97d2c77323d13fac405783ae1aeae602338fe1fc3c1dca35661320cf8",
      "kind": "personal_definition",
      "matching_reasons": [
        {
          "kind": "term",
          "term": "윤활유"
        }
      ],
      "applicability": "applicable",
      "assertion": "personal",
      "evidence_state": "unsupported",
      "independent_review": null,
      "organizational_approval": "not_asserted"
    }
  ]
}
```

반환 상태는 `matched`, `conflicting`, `ambiguous`, `stale`, `out_of_scope`, `no_match`, `unavailable`이다. 정상적인 조회 상태는 `unavailable`도 stdout JSON과 exit 0으로 반환하므로 `outcome`을 반드시 검사한다. 잘못된 입력은 stderr의 기존 CLI JSON 오류와 nonzero exit다. `absence_established=false`는 검색 실패가 업무 개념의 부재를 증명하지 않는다는 뜻이다.

전체 필드·기간·충돌·오류 규칙은 [공개 계약](../plugins/knowledge/references/personal-knowledge.md)에 있다. 개인 범위가 없는 기존 설명·관측·메모는 `scope_unconfirmed` 후보로 반환한다. 호스트는 이를 사용자의 승인된 개인 정의로 자동 적용하면 안 된다. 관련 검색어만 일치하거나 동일 표현이 여러 개념에 연결되면 `ambiguous`와 이유·후보 ID를 반환한다. 대화 진행과 의미 확정은 호스트가 담당하며 `concepts`는 선택 사항이다.

## 호환성과 도입 조건은 무엇인가

`capabilities`에서 `personal_note_versions: [2]`, `retrieval_versions: [1]` 지원을 확인한다. 이 명령은 저장소를 열지 않는다. 구버전의 명령 미지원은 unavailable로 처리하며 기존 `read`를 의미가 같은 대체 수단으로 사용하지 않는다. 실제 저장소 모드는 `notebook inspect --source SOURCE`로 확인한다. 실행 파일 식별에는 `--version`의 `implementation_id`를 함께 사용한다. 릴리스 버전은 아직 올리지 않았다.

SQLite 스키마 변경과 기존 데이터 마이그레이션은 없다. 새 디렉터리형 notebook의 초기 DB 게시에는 로컬 파일시스템의 hard link 지원이 필요하며, 지원하지 않으면 기존 경로를 덮어쓰지 않고 실패한다. 명시적 설정 파일을 쓰는 SQLite 저장소의 초기화는 기존 절차를 유지한다. **v2 note가 기록된 notebook은 구버전 reader에서 읽을 수 없다.** 첫 기록 전에 모든 reader를 업데이트하거나 별도 notebook을 사용한다. 설치된 0.1.1 reader가 fixture v2 note를 명시적으로 거부하고 DB 바이트를 변경하지 않는 것도 확인했다. 기존 형식만 있는 notebook의 회귀 검사는 통과했다.

이 구현은 DB 관리형 notes만 지원한다. 파일 관리형 notes는 기존 동작을 유지하고 `define`을 거부한다. 복원·백업에는 새 개정도 포함되며, 공유 SQLite의 host 테이블과 user_version은 보존된다. 호스트는 인증·인가, 원천별 파싱·수집, 실시간 조회와 업무 실행 검증을 소유한다. 플러그인 내부 테이블을 직접 읽는 연동은 공개 계약이 아니다.

## 어떤 fixture로 확인했나

다음 파일은 합성 입력과 공개 CLI의 실제 응답을 함께 보관한다. `initialize`로 새 notebook을 만들고 `calls`의 명령·입력을 순서대로 실행하면 재현된다. 검토 기록도 **합성 테스트 기록**이며 실제 독립 검토나 조직 승인을 증명하지 않는다.

| 상태 | 입력·실제 응답 |
|---|---|
| 기술 근거 없는 개인 정의 | [personal.json](../tests/knowledge/personal-knowledge/responses/personal.json) |
| 완전한 관측에 연결된 개인 정의·검토 | [supported.json](../tests/knowledge/personal-knowledge/responses/supported.json) |
| 동일 개념의 충돌하는 두 정의 | [conflicting.json](../tests/knowledge/personal-knowledge/responses/conflicting.json) |
| 후속 불완전 관측으로 재확인 필요 | [stale.json](../tests/knowledge/personal-knowledge/responses/stale.json) |
| 관련 검색어만 일치하는 모호한 질문 | [ambiguous.json](../tests/knowledge/personal-knowledge/responses/ambiguous.json) |
| 등록 표현과 맞지 않는 질문 | [missing.json](../tests/knowledge/personal-knowledge/responses/missing.json) |

재생 결과를 새 디렉터리에 생성하려면:

```sh
python3 -B tests/knowledge/personal-knowledge-fixtures.py --output /absolute/new-fixture-output
```

## 검증 범위와 남은 일

- 새 공개 CLI 수용 테스트: 17개 통과. 무근거 기록, 복수 개념 검색, paraphrase, 충돌, 사용자·출처·context 격리, 정정과 미래 적용 기간, 자기 검토 거부, 근거 변경·미완료, 공유 DB/이력 복원, 첫 저장 실패·초기화 잠금 실패 후 재시도, 경쟁 DB 보존, wiki 구조화 이력 보존과 비실행 렌더링을 확인했다.
- 기존 `observations-check`: 20개, `notebook-storage-check`: 16개, `notebook-publication-check`: 4개 통과. 로컬 MarkdownIt 런타임을 제공한 최종 실행에서 skip은 0개다.
- `bash scripts/check.sh`: plugin validate, shellcheck 67개, 설명 일치 검사 모두 통과.
- 독립 리뷰에서 확인한 최초 저장 실패 후 재시도 불가와 wiki 구조화 이력 누락을 수정했다. 개인 notebook 조회 후 Git 절차로 넘어가지 않도록 스킬 분기도 명확히 했다. 두 결함의 수정 전 코드를 임시 복사본에 넣으면 해당 회귀 테스트가 실패하는 것을 확인했다.

위 검사는 합성 데이터와 로컬 Python/SQLite/Node 환경을 검증한다. 실제 판매량·재고의 정확성, 실제 host 통합, 대규모 성능 및 다른 OS는 미검증이다. 전체 `tests/run-all.sh`는 실행하지 않았고 변경된 notebook 경로의 관련 suite를 실행했다.

조직 승인 기록·검증, 임의 의미 검색, 파일형 정의 저장은 미지원이다. 독립 검토는 caller가 제공하는 기록이며 인증된 조직 결정이 아니다. 기존 저장소를 옮기거나 데이터를 변환해야 한다면 별도 명시적 승인이 필요하다. 이번 작업은 실사용 저장소를 마이그레이션하지 않았다.

사용자가 요청한 PR로 변경을 전달한다. 릴리스·설치 캐시 업데이트는 별도 작업이며, 배포를 진행하려면 저장소 release 절차에 따른 버전 결정과 해당 원격 작업의 명시적 지시가 필요하다. 설치본을 직접 수정하지 말고 marketplace 업데이트 절차를 사용한다. SAP Harness 수정·SAP 호출·개인 파일 자동 수집은 수행하지 않았다.
