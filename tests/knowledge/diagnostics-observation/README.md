# 차단 원인·다음 조치 관측

skills#423, 기준 main 9721f38950cc4db59e3dda67f8784f0c219df87b. [M0 입력](m0.md)을 먼저 고정하고 [독립 판정](m0-verdict.json) 뒤 구현했다. 이 실험의 저장소 검토 영수증은 모두 synthetic이며, 실제 독립 모델의 판단과 구분한다.

[기존 방식](results.json)의 12개 로컬 복수 저장소 fixture를 [후보 CLI](candidate-results.json)가 그대로 읽었다. 36회 실제 호출에서 기존 query/wiki 응답과 모든 fixture 파일 바이트가 유지됐다. 변경된 read만 첫 차단 진단을 제공한다. [독립 독자](reader-answers.json)는 정답과 내부 오류를 받지 않고 [공개 응답과 고정 질문](answer-input.json)만 읽었다. 12개 사례 × 5개 답변을 보존한다.

문서 불일치, 현재 검사 실패, 오래된 검사, 검사 없음, 검토 대기, 소스 미커밋, 문서 접근 불가, 통합 실패, 세 종류 권한 철회를 확인했다. HTTP 회귀는 문서 원본 복원과 검사 수정→재실행→새 검토→게시를 별도 단계로 확인한다. 시험용 검토를 실제 독립 구현 승인으로 간주하지 않는다.

[실제 브라우저 관측](browser-observations.md)은 여섯 상태의 개요/저장소/근거 표시를 확인한 부모 관측자 요약이다. 원본 AX 출력은 작업 대화에 있고 별도 export 파일은 없다. 마지막 미리보기 재연결 실패도 기록했다. browser-live.json은 과거 서버 시작 기록이며 현재 서비스 가용성을 보증하지 않는다.

[모델 구분](model-observations.json), [검사 결과](check-results.json)와 원본 로그를 함께 보존한다. files.sha256.json은 이 디렉터리 보존 파일 해시다. 절대 경로는 당시 실험 좌표이며 이 문서의 실행 명령이 아니다. Git/SQLite 원본은 로컬 실험 경로에 유지하고 여기 복제하지 않는다. 관측 스크립트는 당시 입력·실행의 기록이며 자동 재현 회귀는 tests/knowledge/reader-check.sh다.

진단은 첫 관측 차단 원인이다. 전체 근본 원인, 자동 복구, 운영 배포·인증, 동시 외부 쓰기 원자성, 실제 모델 비용·토큰·provider 감사, 성능·검색 품질 개선은 입증하지 않았다. 확인할 수 없는 근거는 unknown 대신 공개 계약의 evidence_unavailable로 남긴다.
