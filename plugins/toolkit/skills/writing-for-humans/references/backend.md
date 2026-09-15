# BE: contracts and failure handling

Help backend (BE) implementers understand the behavior guaranteed to callers and the conditions data must preserve. Lead with the external contract for API consumers; lead with the choice rationale and operational tradeoffs for implementation proposals.

## What to retain

- **Contract:** Who calls under which conditions, and what inputs, results, and errors mean. Distinguish absent and empty fields when their effects differ.
- **Data:** Conditions that must hold under duplicate or concurrent requests and partial failures. State which operations must succeed or be canceled together.
- **Operations:** Latency, compatibility, observability, and recovery conditions relevant to this change. For adoption or transition documents, include the application order and the extent to which the change can be reversed.

Include each item only when it changes the outcome of this task. Link the code, schema, or execution evidence supporting the contract instead of copying a list of functions available in the code. Do not supply unverified response codes or performance figures merely because they are conventional.

## Depth of contract explanation

"재시도 지원" alone does not let a caller retry safely. Where duplicate handling matters, establish how the same request is identified, what a duplicate returns, and the validity scope. If these remain undecided, name the implementation decision they block.

Fictional review memo:

> 요청 시간이 초과되면 호출자는 저장 성공 여부를 알 수 없다. 같은 요청을 다시 보낼 때 중복 레코드가 생길 수 있는지 확인이 필요하다. 중복을 하나로 처리할 식별 기준과 결과 조회 방식이 정해져야 자동 재시도를 확정할 수 있다.

This memo exposes the needed contract without fixing an implementation. If a design is requested, add alternatives and a recommendation, labeled as proposals.

During review, check whether callers and implementers understand success, failure, and repeat calls to have the same outcomes.
