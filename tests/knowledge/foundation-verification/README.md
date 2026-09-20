# 1단계 최종 관측 원본

[최종 보고서](../../../docs/initiatives/code-driven-knowledge/experiments/foundation-verification.md)의 열람용 증거다. 대상 소스는 `c9669e07e6c930d2c56cdbe49346dafbd4e6edb4`다.

- [observation.json](observation.json): `execution`은 실제 CLI 요청·결과, 패키지 manifest, 실행 context·review·completion, 최종 문서 등 83개 파일의 원문이다. `roles_and_checks`는 실제 spawn 전달문과 반환, 역할 응답·등록·완료 결과, 인계 CLI·검사 기록 등 61개 파일의 원문이다.
- [code-review.md](code-review.md): 누적 변경 및 추가 수정의 독립 정적 리뷰. 리뷰어가 테스트를 실행했다는 주장은 하지 않는다.
- [acceptance.md](acceptance.md): 별도 평가자의 S1-01~06 판정과 직접 검사 결과.

원래 절대 경로는 관측 당시 좌표다. 이 묶음은 실행 가능한 이동 사본이 아니며 임시 디렉터리·SQLite·Git 저장소를 복제하지 않는다. 패키지 파일은 고정 소스 커밋과 manifest의 SHA256으로 대조한다. 각 역할 응답은 공식 완료 결과의 bodyHash와 대조해 보존했다.

역할은 하네스의 공식 generic 등록 절차를 거쳤다. provenance는 부모가 실제 도구 반환으로 증언한 기록이고 permission은 prompt-only다. native 역할 강제나 CLI 자체의 작성자 인증을 뜻하지 않는다. 설치된 가드를 끄거나 수정하지 않았다. 최종 실행은 기존 측정 실행기의 상태 기계를 사용하지 않은 별도 공개 CLI 관측이며, 예전 미실행 결과를 성공으로 바꾸지 않는다.
