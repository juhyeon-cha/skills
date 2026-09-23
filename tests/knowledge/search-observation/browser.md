# 실제 브라우저 관측

2026-09-23 13:46–13:48 UTC, Codex in-app browser tab7, 실제 loopback `http://127.0.0.1:54664/`. `search_preview.py`의 격리 fixture이며 운영 서비스가 아니다.

- 개요의 검색 입력에 `재시도 상한`을 입력하고 찾기를 눌렀다. 결과 1개, producer/contract.md, 최대3회 발췌, 검증됨과 시험용 응답 표시를 확인했다.
- 결과 링크를 눌러 실제 `/documents/producer/contract.md/#doc-정책-2` 절에 도착했다. AX와 스크린샷에서 첫 정책의 보관30일과 두 번째 정책의 재시도3회가 구분되고 두 번째 절이 화면에 보였다.
- 문서 검색 탐색 링크의 빈 질의는 0건과 입력 안내였다. `양자결제` 검색은 0건과 현재 제공 가능한 문서/권한/상태를 확인하라는 안내였다.
- `변경 total` 검색은 consumer/guide.md 변경 영향1건, amount→total 발췌와 정확한 절 링크를 표시했다.
- 같은 서버의 격리 host fixture에서 reader의 consumer 권한을 회수한 뒤 브라우저 reload: consumer 탐색 링크와 제목/발췌가 없어졌다. 전체 미완료, 비공개1, 본문 미제공, 오래된 색인, 검색0건이 표시됐다. 조회 후 fixture 권한을 원복했다.

AX·스크린샷 원본은 현재 작업 대화의 실제 도구 응답이며 이 파일은 관측 요약이다. 브라우저에서 직접404 화면·전체 조합·사용자 소요 시간은 측정하지 않았다. API 및 직접 문서 요청의 회귀 검사는 별도 test_search.py/test_reader.py 결과를 따른다.
