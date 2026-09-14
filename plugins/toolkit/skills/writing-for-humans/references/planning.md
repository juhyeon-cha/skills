# Planning: rules and exceptions

Service specifications let engineering, design, and operations expect the same result in the same situation. Planning and PO responsibilities may overlap: use the PO reference for prioritization decisions and this reference for behavior and policy definitions.

## Make rules actionable

Express policies as needed through `subjects and conditions → allowed or restricted actions → results → exceptions`. State exact numerical boundaries, permissions, and time bases when they change the outcome. Do not invent undecided thresholds.

| Content | Question the reader should be able to answer |
|---|---|
| Terms and scope | Does the same name mean the same state or entity? Where does this change apply? |
| Flow and policy | Who can do what, when, and what state follows? |
| Exceptions and handoffs | What happens on failure, cancellation, or expiration, and who handles it? |
| Acceptance criteria | Which case and observable result establish that the requirement is met? |

Use condition tables for recurring combinations and flows when order matters. Define shared policies once rather than repeating them for each screen. Include technical implementation only when it affects the guarantees of the outcome.

## Communicating rules and unresolved decisions together

Fictional confirmed requirements and an unresolved decision:

> 저장이 실패해도 사용자가 현재 화면에 입력한 값은 유지한다. 사용자는 같은 화면에서 다시 저장할 수 있다. 화면을 나갔다 돌아온 경우의 입력 복원은 미정이다. 따라서 이번 요구만으로 임시 저장 기능까지 구현 범위에 넣을 수는 없다.

Make acceptance cases observable, such as "입력 후 저장이 실패했을 때 기존 입력값이 남아 있고 재시도가 가능하다". Replace untestable wording such as "안정적으로 처리" with conditions and results.

During review, check whether engineering, design, and operations could interpret the same case as different policies.
