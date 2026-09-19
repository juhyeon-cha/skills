# 문서 AC와 독립 독자 실험

문서를 잘 썼다는 작성자의 판단만으로는, 독자가 잘못된 행동을 선택하거나 예외를 놓치는 문제를 발견하기 어렵다. [skills#323](https://github.com/juhyeon-cha/skills/issues/323)에서는 고정 소스에서 기대 결과를 정하고, 맥락 없는 독자의 답변과 인용을 별도 판정자가 비교하는 절차를 실행했다.

## 만든 것

- [장·중·단기 목표](code-driven-knowledge-roadmap.md)와 연결되는 재실행 사례를 `tests/toolkit/writing-for-humans/`에 두었다. 배포 스킬이나 새 평가 플랫폼은 추가하지 않았다.
- [소스 발췌](../tests/toolkit/writing-for-humans/sources.json), [질문 10개](../tests/toolkit/writing-for-humans/questions.json), [기대 명제](../tests/toolkit/writing-for-humans/expectations.json)를 작성 전에 정했다. 해시는 작성자 실행 중 기록했다. 기준은 SAP Harness의 `36a31860ae66c0d03b99ec244abe891a642dbdc4`이며 로컬 Git 원본과 발췌·파일 해시를 대조했다.
- `writing-for-humans`를 읽은 독립 작성자의 초안을 주 에이전트가 축약해 [공통 정책](../tests/toolkit/writing-for-humans/documents/policy.md), [FE](../tests/toolkit/writing-for-humans/documents/frontend.md), [서비스 기획](../tests/toolkit/writing-for-humans/documents/planning.md), [UI/UX](../tests/toolkit/writing-for-humans/documents/uiux.md) 문서로 남겼다. 최종 문서 자체를 독립 검증했다.
- [구조 검사](../tests/toolkit/writing-for-humans/check.py), [독자 입력 생성](../tests/toolkit/writing-for-humans/packets.py), [재실행 절차](../tests/toolkit/writing-for-humans/README.md), 실제 입력·반환·판정을 보존했다. 개발 검사 러너는 새 셸 진입점을 자동 발견한다.

## 실제로 관측한 차이

AC는 수용 기준을 뜻한다. 답변 내용뿐 아니라 모든 필수 명제를 뒷받침하는 문서 인용도 있어야 통과한다. 필수 정보가 없으면 “정보 부족”이라고 답하는 것은 올바른 독서지만 문서의 AC는 실패한다.

| 입력 | 관측 | 판정 |
|---|---|---|
| 정상 공통 정책 | 독자 A가 모든 질문에 답과 근거를 제시 | 10/10 통과 |
| 500 등 기타 실패 행 삭제 | 독자 B가 초안과 제공자 확인 상태를 알 수 없다고 답함 | q5 실패, 나머지 통과 |
| 성공 후 별도 분석 요청을 보내라고 변형 | 독자 C가 같은 질문을 다시 보내야 한다고 답함 | q3 실패, 나머지 통과 |
| `/api/chat`을 `/api/chats`로 변형 | 구조 검사에서 식별자 불일치 검출 | 실패 |
| 근거 링크를 없는 파일로 변형 | 구조 검사에서 링크 단절 검출 | 실패 |
| 작성자에게 누락 AC를 돌려주고 표 행 수정 | 새 독자 D가 500 처리에 정확히 답함. 다른 세 질문은 답은 맞지만 인용 일부 누락 | 문서 누락 해결, 독자 증거 7/10 통과 |
| 결함 복구와 인용 지침 보완 후 새 독자 E | 필수 답변과 인용을 모두 반환 | 10/10 통과 |

실패 뒤에는 기대 답안을 고치지 않았다. 독자에게 각 주장과 미검증 범위를 뒷받침하는 인용을 모두 반환하도록 지침을 명확히 했다. 네 결함을 소스와 일치하는 공통 정책으로 복구하고, 새 독자 E에게 다시 읽혔다. [실행자·입력 해시](../tests/toolkit/writing-for-humans/observations/execution.json), [독립 판정](../tests/toolkit/writing-for-humans/observations/judgments.md), [수정 이력](../tests/toolkit/writing-for-humans/observations/repair-final/history.json)에 성공과 실패를 함께 보존했다.

독립 판정자는 소스와 인용을 대조했으며, 직무별 안내 3종도 공통 정책과 일치한다고 판단했다. 독립 코드 검토에서는 확정할 결함이 없었다. 이들은 일반 서브 에이전트의 실제 응답이며 네이티브 하네스 역할 실행 영수증이 아니다.

## 검증 범위와 재실행

저장소 루트에서 다음 명령을 실행한다.

```sh
bash tests/toolkit/writing-for-humans-check.sh
python3 tests/toolkit/writing-for-humans/check.py
python3 tests/toolkit/writing-for-humans/packets.py /새로운/실행/디렉터리
```

첫 명령은 정상 입력, 결함, 누락·변조·잘못된 입력, 기존 결과 덮어쓰기 거절을 검사하는 7개 테스트다. 구조 검사 성공은 문장 의미나 독자 이해의 성공을 뜻하지 않는다. 생성 명령은 입력을 준비할 뿐 에이전트를 실행하지 않는다. 새 독자와 판정자를 연결하는 방법은 재실행 절차에 있다. 원본 Git 대조에는 `check.py --source-repo <로컬 SAP Harness 저장소>`를 사용한다.

7개 테스트, 고정 Git 원본 대조, 저장소 게이트 `bash scripts/check.sh`, `git diff --check`를 실행해 통과했다. 저장소 전체 `tests/run-all.sh`는 실행하지 않았다. 제품 코드와 하네스 코어를 바꾸지 않았으며, 이번 변경의 검사와 필수 게이트를 실행했다.

관측의 한계는 다음과 같다.

- 독자는 대화 이력 없이 문서와 질문만 받았다. 임시 파일을 한 번 읽는 도구 사용은 허용했다. 입력 분리는 프롬프트 수준이며 실행 환경의 접근 차단을 증명하지 않는다.
- 각 문서의 소수 단일 관측이다. 사람의 이해도, 모델 간 재현성, 일반적인 스킬 품질 향상은 측정하지 않았다. 모델별 사용량과 비용도 미측정이다.
- 일반 자식의 파일 쓰기와 일부 복합 읽기 명령은 역할 확인 훅에 차단됐다. 쓰기는 주 에이전트가 반환 내용을 기록했고, 검토는 허용된 단일 읽기 명령으로 완료했다. 차단된 시도를 성공으로 바꾸거나 훅을 수정하지 않았다.
- 검증 대상은 고정 소스의 설명이다. 브라우저·SAP·서버 실동작, 원격 링크 가용성, 최신 PR 상태는 이번 실행에서 검증하지 않았다.

## 다음 단계 판단

이번 관측은 문서 작성과 평가를 분리하고, 실패를 작성·풀이 단계로 돌려보내는 방식이 이 사례에서 작동함을 보여준다. 일반적인 문서 수정과 재평가는 사용자에게 확인하지 않고 진행했다. 제품 정책 결정이 필요한 상황은 발생하지 않았다.

`writing-for-humans`에 새 규칙을 추가할 근거는 발견하지 못했다. 작성 초안은 코드 주석과 실행 분기의 차이까지 설명했다. 관측한 인용 누락은 독자 평가 절차에 반영했다. 중기에는 이 사례를 기준으로 변경 전후 근거와 영향 문서를 연결하는 작업을 이어갈 수 있다.
