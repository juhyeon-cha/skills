# FE: states and screen behavior

Help frontend (FE) implementers build screens and connect server behavior without guessing. First distinguish a screen specification from a handoff of changes to an existing implementation.

## What to retain

| Reader's task | Needed content | Content that can be omitted |
|---|---|---|
| Implement a screen | Entry conditions, user actions, screen states, transitions, exit conditions | Repetition of colors and spacing in an already-linked design |
| Connect an API | Consumed fields and meanings, request timing, display for each response, whether another request is allowed | Server classes unrelated to the screen |
| Apply a change | Changed behavior, affected screens and shared elements, behavior to preserve | An overview of the entire system unrelated to the change |

Select the loading, empty, success, failure, and permission-denied states that actually apply. When several states matter, use a `condition → display → available action` table. Explain repeated clicks, late responses, or navigation away only when they change the outcome.

Connect keyboard interaction, focus movement, assistive-technology announcements, and responsive constraints to design evidence where they affect implementation. If the API and design define different states, mark the conflict as unresolved rather than leaving the implementer to decide implicitly.

## Short example

The following is a fictional confirmed specification, with the unresolved contract identified explicitly:

> 저장을 누르면 요청이 끝날 때까지 저장 버튼을 비활성화한다. 성공하면 완료 안내를 띄운다. 실패하면 입력값을 유지하고 다시 저장할 수 있게 한다. 시간 초과 뒤 중복 저장을 막는 서버 계약은 미정이며, 자동 재시도 여부는 이 계약이 정해진 뒤 확정한다.

The useful distinction is between preserving input after failure and deciding retry behavior, not the length of the button description. Carry only verified contracts into real requests.

During review, check whether the reader can map both the normal path and important failure paths to screen states.
