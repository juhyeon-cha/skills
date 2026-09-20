# 설치 환경의 연속 실행 관측

2026-09-20, macOS의 Codex 부모 작업이 복사한 toolkit과 기존 전용 Python 가상환경을 사용했다. 실제 독립 리뷰 `/root/installed_review`가 설치본 SKILL·rubric·response와 패킷 전체를 읽고 반환한 JSON을 그대로 보존했다. 이 에이전트는 구현·작성 이력을 받지 않은 새 맥락에서 첫 리뷰를 시작했고 이후 새 패킷을 재검토했다.

`trace.json`은 doctor→init→B start→반려→수정→통과→적용 직후 프로세스 종료(91)→status→resume→C start→통과→resume의 실제 명령과 응답이다. 첫 문서는 조건과 예외가 빠져 반려됐다. `review-bad.json`, `review-fixed.json`, `review-c.json`은 실제 리뷰 응답이며 부모가 작성한 가짜 통과가 아니다. 패킷·완료 기록·최종 문서를 함께 보존한다. Git 이력은 `source-history.fi`로 재구성할 수 있다.

첫 실행의 패키지는 이번 개발 중간 복사본이었다. 마지막 소스와 같은 것으로 꾸미지 않기 위해, 최종 소스를 새로 복사한 설치 환경에서 `replay.py`를 추가 실행했다. 이 재실행은 같은 Git 커밋·문서에서 패킷이 실제 리뷰 당시와 완전히 같은지 검사한 뒤 그 리뷰를 재사용한다. 새 모델 실행이나 마켓플레이스 설치 관측은 아니다.

```sh
KNOWLEDGE_PYTHON=/private/tmp/knowledge-contract-venv/bin/python bash tests/knowledge/foundation-check.sh
# 원본 명령·응답을 보존하려면 존재하지 않는 출력 디렉터리 사용:
<requirements를 설치한 Python> tests/knowledge/foundation-observation/replay.py --out /새로운/결과
```

재실행은 하나의 복사 설치에서 연속 두 변경, 반려·수정, 오래된 리뷰 거절, 손상 패킷 보존·신뢰 원본 복구, 독립 문서 편집 보존, 종료·재개, 사용자/문서/코드 접수, 코드 없는 목표 인계, 표현 변경의 코드 작업 불필요 분류, 의존 스킬 누락, 실행 종료·프로젝트 격리·새 기준 전환을 검사한다. `final-replay-3/`에는 최종 실행 로그와 설치 파일 해시가 있다. 앞선 두 final-replay 디렉터리는 참조 문구·파일 끝 공백 보완 전의 통과 실행을 보존한다. 임시 문서의 결함 주입은 실제 사용자의 문서를 바꾸지 않는다.

사용자 개입은 없었다. 리뷰어는 정적 내용만 판정했고 Git·문서 결과는 부모가 확인했다. 원본 입력·리뷰와 문서의 연결은 검증하지만 리뷰 JSON의 진짜 작성자를 CLI가 인증하지는 않는다.

## 미실행 관측

새 `/root/resume_observer`에 project와 run ID, 설치 스킬 위치만 넘겼다. 스킬·project.md·workflow.md 읽기는 성공했지만 아래 명령은 실행 전에 하네스에 차단됐다.

```sh
/private/tmp/knowledge-contract-venv/bin/python /private/tmp/foundation-live-20260920/toolkit/skills/refresh-knowledge/scripts/knowledge.py --project /private/tmp/foundation-live-20260920/project status --run e9f434226d650ab13ead857854dbceae8d7c6db7ac74fb31fe490700a31a124a
```

응답: `Command blocked by PreToolUse hook: GUARD-DENY: UNREACHED — 판정에 도달하지 못했다: child role is unidentified.`

따라서 이 새 에이전트의 resume·최종 검증은 미실행이다. 별도 CLI 프로세스의 재개 성공과 구분한다. 하네스 역할 등록·설정 변경이나 외부 모델 서비스를 이용한 우회는 하지 않았다. 현재 호스트에서 새 일반 에이전트의 독자적 실행 인계까지 지원한다고 주장할 수 없다.
