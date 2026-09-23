실제 Codex in-app browser CUA 관측

partial: 목표 개요에서 전체 미완료, producer 검증됨, consumer 검증 대기 또는 오래됨, 통합 검증 대기, 필수2/비공개0. producer 링크 직접클릭: 현재커밋 f801751439428b33019917409a39e43963049dc2, 목표 total, 검증됨, 본문 미제공. screenshot으로 좁은뷰포트에서 카드/줄바꿈/탐색 확인. 새로조회 API 결과는 partial.json.

complete: overview 전체완료/통합검증됨/필수2/비공개0. evidence의 결과 ID 740ae62724bdfb1e03e7c0e8713167a561e29270517fe932fbb978d39777458f는 CLI complete.json과 동일. 실제 호출에 대한 호스트 기록 표시와 게시이력 published. consumer 링크 클릭으로 total값1/누락KeyError/기본값없음/배포미검증/현재commit 본문 확인. 검색 입력 KeyError→찾기 클릭: 두결과, 전체완료 유지.
revoked: 동일서버 reload 후 consumer nav/card 사라짐, 필수2/비공개1, 전체미완료/통합대기/본문미제공. 이전 consumer 직접URL 이동은 IAB net::ERR_BLOCKED_BY_CLIENT로 차단되어 이전화면유지(404 오류화면 자체는 브라우저가 열지않음). 실제HTTP 직접링크404는 회귀검사로 별도확인.
drift: 원래권한복구 후 검토되지않은문서변경 주입. resume가 rc1로 거부된 trace 보존. evidence페이지는 색인오래됨/producer근거확인불가, 결과ID 2c7e78a47298590c520ea68181cbd74c9eb0826e376d81249b43b94d2afa2f76 일치. producer페이지는 검증대기또는오래됨/본문미제공. 원본문 바이트복구후 CLI complete 결과ID원복 확인.
check_failed: 실제 승인된로컬check를 rc1로실패시키고 같은서버 목표개요를요청. consumer검증됨/producer검증대기또는오래됨, 전체미완료/통합대기/본문미제공. drift와같은공개상태여서결과ID도같음; 이화면은실패원인상세를구분하지않으며 실제원인은trace로확인.
withdrawn: 코드동일/문서화목표철회intake 등록후v2. same-server reload에서 목표v2/철회/전체미완료/본문미제공 확인. 첫intake를behavior_change로분류하여거절된원본과current_behavior로정정한성공기록을분리보존.

도구경계: 관측은 CUA 실제AX상태와partial페이지스크린샷이다. in-app browser content.export는 지원되지 않아 rawexport파일없음. 이문서는 관측자 요약이며 원본도구출력은 대화기록에남는다. 별도HTTP회귀와 의미판정을 대체하지 않는다.
