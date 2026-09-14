# Document shapes and multiple audiences

Choose a starting point that fits the reader's task. These sequences are ingredients, not fixed outlines. When a format is specified, adjust information order and density within it.

| Reader's task | Starting point and useful sequence | Completion criterion |
|---|---|---|
| Choose or approve | Decision request/recommendation → problem and evidence → differences between alternatives → remaining judgment | Understands the options and the recommendation's tradeoffs |
| Implement or receive a handoff | Target behavior → scope → contracts, rules, and states → exceptions and acceptance cases | Can determine behavior at important branches without guessing |
| Apply a change | What changes and who is affected → required action → compatibility and transition conditions | Knows whether the change applies and what to do |
| Understand progress | Current results → deviation from plan → impact → needed help | Can distinguish completed, planned, and blocked work |
| Use or troubleshoot | Applicable situation → action → expected result → next action on failure | Can follow the procedure and identify success |

Do not invent an approval request for an update that needs no decision. Do not create commitments when deadlines or owners have not been supplied. Long-lived documents need links for tracing sources and decision status; short messages focus on immediate impact and action.

## Multiple audiences

State the shared conclusion first, then add only information that differs by reader. Define a shared policy once; role-specific parts address the actions or unresolved decisions that follow from it.

Fictional collaboration memo:

> 저장 실패 뒤 현재 화면의 입력을 유지하는 안을 검토합니다. 화면 이탈 뒤 복원은 범위 미정입니다.
>
> - 기획·PO: 현재 화면 내 재시도까지로 범위를 한정할지 결정이 필요합니다.
> - UI/UX·FE: 실패 안내와 재시도 동작을 설계해야 합니다.
> - BE: 시간 초과 뒤 재요청 시 중복 저장 가능성을 확인해야 합니다.

Retain only relevant roles in the actual document. Roles are listed here because their handoff points differ. If they do not differ, a shared paragraph is sufficient.

If the primary reader is a PO and developers are secondary readers, keep the investment decision in the body and detailed contracts in a linked specification. For a development handoff, keep contracts in the body and include only the necessary product context beforehand. Multiple audiences are not a reason to merge every reference into the body.
