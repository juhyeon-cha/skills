# 일반 서브에이전트 관측의 역사적 근거

이 문서는 과거 일반 위임 어댑터 설계에 사용한 관측 기록이다. 현재 하네스는
해당 어댑터·모델 선호 정책·호출 기록 프로토콜을 제공하지 않는다. 일반
서브에이전트는 런타임 도구로 직접 사용하며, 현재 절차는
[역할과 위임](../plugins/harness/docs/roles.md)을 따른다.

실측 근거의 원장은 [skills#275](https://github.com/juhyeon-cha/skills/issues/275)와
[skills#288](https://github.com/juhyeon-cha/skills/issues/288)이다.
[관측 fixture](../tests/harness/fixtures/collaboration-observations.json)는 당시
부모가 남긴 실증 메모에서 발췌한 구조화 자료다. 전체 도구 응답을 보존한 인증
캡처가 아니며, 이 JSON의 재생은 실제 실행이나 네이티브 역할 로딩의 증거가 아니다.
기존 기록을 현재 어댑터가 검증한 결과로 소급 해석하지 않는다.

## 관측 범위와 출처

당시 세션에 제공된 `collaboration.spawn_agent`의 인자는 `task_name`, `message`,
`fork_turns`, `model`, `reasoning_effort`다. 이 표면에는 native 역할 선택이나
자식별 도구 권한 설정 인자가 없다. 이는 이 provider 표면에 대한 관측이며
Codex 제품이나 다른 runtime 전체의 지원 여부를 판정하지 않는다.

fixture의 `parent_observation`은 parent가 도구 반환 또는 메시지를 관측했다고
원장에 남긴 내용이다. `child_self_report`는 자식의 보고이며 권한 강제의 증거가
아니다. 발췌는 확인된 필드와 첫 줄만 담는다. 원문 전체를 복원하거나, 관측하지
않은 timestamp·native invocation ID·hook identity를 만들어 넣지 않는다.

| 사례 | 관측 | 판정 경계 |
|---|---|---|
| 생성 | `spawn_agent`가 `/root/capability_probe_275`를 반환 | 실제 생성 반환의 canonical child path |
| 완료 대조 | 같은 sender의 완료 첫 줄이 `PROBE_COMPLETE probe-275-20260910-a`; `list_agents`의 같은 `agent_name`에서 completed 본문도 일치했다고 parent가 기록 | 자식이 성공이라고 말한 것과 별도로 parent가 완료 상태를 대조했음. fixture에는 전체 본문을 재구성하지 않음 |
| 자식 보고 | read-only `pwd` 성공과 hook-delivered identity 미관측 | 읽기 성공은 역할별 쓰기·네트워크 금지의 강제 증거가 아님 |
| 중단 | `/root/interrupt_probe_275`의 `interrupt_agent` 반환은 `previous_status: running`, 이후 `list_agents` 상태는 `interrupted` | 중단은 완료나 성공이 아님 |
| 동일 ID 후속 응답 | 같은 child의 `followup_task` 이후 동일 sender가 `PROBE_FOLLOWUP probe-275-reuse-c`를 반환 | child ID 하나만으로 호출 세대나 이전 결과의 유효성을 구별할 수 없음 |

별도의 native invocation ID, hook 역할 identity, 역할별 강제 권한 증거는 이
실증에서 관측되지 않았다. canonical child path를 `agent_id`나 `agent_type`으로
바꾸거나 native `REACHED` 이벤트를 합성하면 이 범위를 넘는다. 파일 쓰기나
네트워크 작업의 허용·거절을 시험한 관측도 없다.
