# UI/UX: experience and design rationale

User interface (UI) and user experience (UX) documents explain what users are trying to do, in which circumstances, and how the design supports that action. Retain the intent that a screen inventory alone would not convey.

## Select by document purpose

| Purpose | Content to retain |
|---|---|
| Design review | User task, observed difficulty, proposed flow, rationale and tradeoffs, questions for review |
| Development handoff | Flow entry and exit, actions and feedback per state, copy, important accessibility behavior, design links |
| Research sharing | Observation conditions and participants, observations, interpretation, applicability, next decision |

Place observations and interpretations together while distinguishing them. Do not generalize one interview statement into a requirement for all users. For figures, include the population, period, or measurement method needed to interpret them. Design intent does not establish effectiveness.

Show important branches and return paths instead of expanding descriptions for every screen. Use a diagram only when it conveys branches faster than prose. Explain why an action is available in a state instead of repeating the visual details.

## Wording example

Fictional proposal:

> 저장 실패 뒤 입력을 유지하는 안을 제안한다. 사용자가 내용을 다시 작성하지 않고 저장을 재시도할 수 있게 하려는 목적이다. 실패 안내에서 다시 시도할 수 있음을 알린다. 실제로 재작성 부담이 줄었는지는 검증 전이다.

Replace "직관적인 UX 제공" with user behavior and the expected effect. Distinguish confirmed implementation, design proposals, and validation results in the wording.

During review, check whether the reader can explain the user flow and rationale, and whether developers can handle empty and failure states without separate guesses.
