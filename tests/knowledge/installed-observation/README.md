# 설치 패키지 실제 실행 관측

일회용 소스·문서를 사용한 신규 세션의 실제 결정, 리뷰, 최종 문서와 선택된 도구 기록이다. `tool-trace.json`은 Read/Skill/Agent 호출의 경로·역할과 도구 결과의 오류 여부만 보존한다. `$FIXTURE`는 임시 실행 루트다. 프롬프트·전체 응답·환경 훅 출력은 제외했다. 원본 전체 로그의 해시와 당시 설치 파일 해시는 `provenance.json`에 있다.

첫 일반 역할 리뷰의 도구 사용은 거부됐고, 등록된 harness:reviewer의 실제 읽기와 리뷰는 성공했다. 상세 판정과 한계는 [관측 보고서](../../../docs/initiatives/code-driven-knowledge/experiments/installed-workflow.md)를 따른다. 기록은 과거 관측이며 최신 코드 전체의 재검증 결과가 아니다.
