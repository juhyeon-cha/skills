# 일반 자식 실행 관측과 어댑터 설계 근거

훅 연결을 변경할 때는 `tests/harness/generic-hook-check.mjs`를 실행한다.
이 검사는 실제 guard와 임시 Git 저장소의 begin/bind/complete를 연결하며,
부모 checkout과 linked worktree의 공통 저장소 식별, bind 이전 dispatch,
다른 세션·손상 기록·종료 기록의 거부를 다룬다. `--baseline`은 수정 전 소스에서
첫 읽기의 code 2를 확인하는 재현 모드다. 정상 모드는 읽기 code 0을 요구한다.
세션 ID와 data는 훅이 받은 좌표이고 call.repository는 배정 worktree다.
fixture가 합성한 이벤트는 설치본의 실제 자식 실행이나 native 역할 증거가 아니다.
실측 결과와 복구 실행 예외는 [skills#288](https://github.com/juhyeon-cha/skills/issues/288)에 둔다.

이 문서는 하네스 개발자가 일반 자식 실행 어댑터를 설계할 때 쓰는 자료다.
실측 근거와 사용자 결정의 원장은 [skills#275](https://github.com/juhyeon-cha/skills/issues/275)이며,
[관측 fixture](../tests/harness/fixtures/collaboration-observations.json)는 그 notes와
parent가 남긴 실증 메모에서 발췌한 구조화 자료다. 전체 도구 응답을 보존한 인증
캡처가 아니며, 이 JSON을 읽거나 내용이 일치한다는 사실만으로 실제 실행을 인증할 수 없다.

## 관측 범위와 출처

현재 세션에 제공된 `collaboration.spawn_agent`의 인자는 `task_name`, `message`,
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

## 승인된 계약과 구현할 경계

사용자 결정은 **`prompt-only`를 명시적으로 선택한 일반 자식 실행 허용**이다.
`enforced` 권한을 필수로 요구하는 요청은 현재 provider에서 거절한다. native
경로를 일반 경로로 자동 전환하지 않는다. 역할 문서에 적힌 금지를 전달하는 것과
runtime이 그 금지를 강제했음을 입증하는 것은 서로 다른 보장이다.

다음 항목은 위 관측에서 도출한 구현 요구이며, 이 문서나 fixture가 구현·검증한
제품 기능이 아니다.

- Parent가 호출 전에 invocation inventory를 만들고, 호출마다 불변 식별자와
  task·commit scope·배정 역할·canonical 역할 문서 hash를 결합한다. 이 식별자는
  parent가 소유하는 로컬 식별자이며 provider가 발급한 native invocation ID가 아니다.
- 실제 생성 반환을 inventory에 연결하고 parent가 관측한 완료 상태·본문을 같은
  호출에 귀속한다. 문서 hash는 어떤 역할 지시를 배정했는지 나타낼 뿐, 자식의
  native 역할 identity나 권한 강제를 증명하지 않는다.
- 구현자와 심사자의 실제 child identity를 비교해 독립성을 확인한다. 동일 child의
  자기평가, 이미 소비한 child/outcome, 중단 뒤 후속 응답을 이전 호출에 붙이는
  시도를 거절한다. 별도 invocation ID가 없으므로 child path만으로 승인하지 않는다.
- SIGNAL은 기존 canonical 역할 문서의 허용 목록과 대조한다. 관측 provenance,
  역할 배정, 결과 판정, 권한 보장 수준을 구별해서 반환하며, 없는 근거는
  `unavailable`로 표시한다.
- Parent-owned 기록은 신뢰 경계다. 자식이 쓴 완료 주장이나 임의 JSON을 parent의
  도구 관측으로 승격하지 않는다. fixture 재생은 이 경계의 회귀 검사 재료이며
  실제 provider 실행이나 native hook 검증을 대신하지 않는다.

M0/M1 bootstrap 사이클은 승인된 prompt-only 역할 문서 규율과 실제 일반 자식
관측을 원장에 기록한다. 새 어댑터가 존재하기 전 수행한 실행을 새 어댑터가
검증했다고 소급 주장하지 않는다. 기존 native 계약과 제품 코드는 이 자료의 범위 밖이다.
