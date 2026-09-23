# 실제 브라우저 관측

2026-09-23 10:00–10:03 UTC, 부모가 실제 CUA in-app-browser tab 5에서 관측했다. URL은 preview runner가 반환한 http://127.0.0.1:49354 이다. 아래는 도구 응답을 요약한 관측이며 raw AX와 스크린샷은 이 작업 대화에 있다. 브라우저 content.export는 지원되지 않아 실패했으며 브라우저 원본 export 파일은 없다. HTTP 원본 HTML은 별도 runner가 보존했다.

- 개요 → producer → producer 계약을 실제 링크 클릭으로 이동. contract.md 문서별 URL과 표(total / 금액 합계), JSON {"total":120}, 문서 목차를 확인했다.
- 두 번째 금액 목차 클릭 후 URL fragment는 doc-금액-2였다. wide 스크린샷에서 표·코드·본문 링크와 두 번째 절을 확인했다.
- '호출 안내의 검증' 클릭 후 /documents/producer/guide.md/#doc-검증로 이동. 표, total 필드 설명, 운영 배포 미검증 문구가 보였다.
- 조회 상태와 기술 근거 펼치기에서 목표 근거 ID와 결과 ID가 표시되었다. 결과 ID는 c8ca14c5bc90365078b2349a7bcb865ebf2467dd4cf9bb439b891f0722442fee였다.
- viewport 390×844에서 스크린샷 관측: 본문·표·링크·disclosure가 화면 안에 있었다. DOM 측정 clientWidth=390, scrollWidth=390, table 1. viewport override는 reset했다.
- 근거 화면에서 '시험용 응답'이 펼치기 전부터 보이고, 검토 기록 상세는 닫힌 상태였다. 클릭하면 review_synthetic:true 및 근거 JSON이 표시됐다.
- consumer 문서 접근 성공 후 이 격리 fixture의 reader consumer 권한만 제거했다. reload 도구는 이전 AX를 반환하여 성공한 갱신으로 판정하지 않았다. 실제 HTTP GET은 404/no-store, '페이지를 제공할 수 없습니다.'를 반환했다. 이어 개요 링크를 클릭하면 consumer 링크/내용이 없고 전체 미완료·필수 2·비공개 1·본문 미제공이 표시됐다. 이전 consumer 문서 URL을 새로 열기는 브라우저가 net::ERR_BLOCKED_BY_CLIENT로 거부했다. 이는 사용자에게 404 안내 페이지가 렌더링되었다는 증거가 아니며, HTTP 404와 개요의 권한 반영은 별도로 확인됐다.

이미 받은 화면 바이트가 자동 회수되거나 열려 있는 문서가 실시간 변경된다는 주장은 하지 않는다. 운영 계정·저장소·실제 업무 데이터는 사용하지 않았다. synthetic fixture 검토는 독립 모델 검토로 세지 않는다.

## 최종 화면 재관측

10:08 UTC, 최종 Python 렌더러를 새 프로세스와 새 격리 fixture로 시작했다. URL http://127.0.0.1:50013, tab 6. producer 계약의 중복 shell 제목이 없어지고 정본 h1 하나만 표시됐다. 실제 링크 클릭으로 guide.md의 doc-검증로 이동했다. 다시 390×844에서 본문·표·목차·접힌 근거를 스크린샷으로 확인했고 clientWidth=scrollWidth=390이었다. viewport를 reset했다. 초기 resize 직후 캡처는 전환 중 모양이어서 최신 AX 확인 후 캡처로 판정했다. 최종 HTTP 원본은 final-complete/에 별도 보존한다.
