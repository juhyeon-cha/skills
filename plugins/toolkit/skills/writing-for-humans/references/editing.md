# Editing criteria and audience-specific examples

## Order of cuts

1. Remove sections that do not affect the reader's decision or action.
2. Consolidate repeated facts. If the introduction and conclusion say the same thing, one is sufficient.
3. Replace strings of nouns with sentences that have subjects and verbs.
4. Compare with the source to verify that conditions, exceptions, uncertainty, and evidence are preserved.

"좋은 사용자 경험을 위한 저장 안정성 고도화가 필요하다" does not say what should change. When supported by evidence, state the situation and result, such as "저장 실패 뒤 입력이 사라져 다시 작성해야 한다". Without evidence, do not invent this specific fact either.

Do not shorten to "실패 시 재시도" merely for brevity. It is insufficient for readers who need input-preservation or duplicate-handling conditions. Conversely, showing every response field to a PO can obstruct the decision.

## Same source material, different readers

**Fictional source material for practice:** The team agreed to preserve input on the current screen after a save failure. Users retry manually. Restoration after navigating away and automatic retries remain undecided. No failure-frequency or development-schedule data is available.

| Reader and purpose | Short output example |
|---|---|
| FE implementation handoff | 저장 실패 시 현재 화면의 입력값을 유지하고 사용자가 다시 저장할 수 있게 한다. 화면 이탈 뒤 복원과 자동 재시도는 미정이다. |
| BE contract review | 사용자가 실패 뒤 저장을 재시도한다. 시간 초과처럼 성공 여부를 알 수 없는 상황에서 중복 저장 가능성이 있는지 확인이 필요하다. 자동 재시도는 미정이다. |
| UI/UX design review | 저장 실패 뒤 입력을 유지하고 직접 재시도할 수 있게 하기로 했다. 실패 안내에서 현재 상태와 가능한 다음 행동을 어떻게 전달할지 설계가 필요하다. |
| PO scope decision | 현재 화면의 입력 보존과 직접 재시도는 합의되었다. 화면 이탈 뒤 복원과 자동 재시도는 추가 범위 결정이 필요하다. 실패 빈도와 일정 자료는 없어 효과 규모나 출시일을 확정할 수 없다. |
| Service policy specification | 저장 실패 시 현재 화면의 입력값을 유지하며 재저장을 허용한다. 화면 이탈 후 복원 여부와 자동 재시도는 미결정 정책으로 남긴다. |

These examples illustrate content selection. Do not expand the actual deliverable into five versions or mix the examples' facts into the user's material.

## Preserve degrees of certainty

| Original | Meaning-changing condensation | Faithful edit |
|---|---|---|
| 실험 대상에서 완료율이 높아졌으나 표본이 적다 | 완료율 개선이 검증됐다 | 실험 대상의 완료율은 높아졌지만 표본이 적어 효과 확정은 어렵다 |
| 일정은 의존 팀 확인 뒤 확정한다 | 다음 주 출시한다 | 의존 팀 확인 후 일정을 확정한다 |
| 장애 시 입력 유지 방안을 제안한다 | 장애 시 입력을 유지한다 | 장애 시 입력을 유지하는 안을 제안한다 |

Before delivering, locate the conclusion, evidence, and conditions in the body. Correct unsupported certainty, unclear actors, and endings that repeat the preceding paragraph. Do not append this check to the finished document.
