# 문서·근거 절 검색 관측

원장 [skills#435](https://github.com/juhyeon-cha/skills/issues/435). 기존 기준은 `13550c1eb8c9f52d8b123c6cbc43abeed57e915c`이다. 구현 전에 [고정 기준](protocol.md)과 [입력](corpus.json)을 작성했다.

## 결과와 근거

| 조건 | 관측 |
|---|---|
| Q1 금액 계약 | producer 금액 절, total/KRW/정수 |
| Q2 변경 영향 | consumer 변경 영향 절, amount→total |
| Q3 검증 범위 | consumer 검증 절, 로컬 계약 검사와 운영 배포 미검증 구분 |
| Q4 중복 제목 | 두 번째 정책 절 `doc-정책-2`, 재시도 최대3회 |
| Q5 코드 예제 | 예제 절의 `total:120` |
| Q6 제한 상태 | 권한 회수·부분·철회·drift·소스 실패에서 검색0건, 전체 미완료. 기존 색인만 absent/stale인 경우 현재 허용된 게시 본문은 검색 가능 |
| Q7 메타데이터 | 해시/목표 문자열·링크URL만 일치하는 검색0건 |
| Q8 정답 근거 없음 | 검색0건, 독자는 기능 미지원이라고 단정하지 않음 |

[실제 독립 독자 응답](model-reader.md)은 정답표 없이 실제 HTTP 결과와 도착 HTML을 읽은 별도 모델 호출이다. [브라우저 관측](browser.md)은 검색 폼→결과→근거 절 이동과 같은 서버에서 권한 회수 후 재조회다. fixture 검토 영수증은 전부 합성 응답이며, 이 실제 독자 호출을 소스 검토 영수증으로 대체 등록하지 않았다. 예제 코드가 KRW·재시도 기능을 실제 구현했다고 주장하지 않는다.

[M0 원본](m0-result.json): 22,578bytes corpus, 파서 추출10회 0.474–5.323ms, 예상 절5/5. 실제 독립 `/root/search_m0` 재실행은 0.430–4.875ms, MATCH였다. probe에는 아직 링크URL 제거·NFKC가 없어 제품으로 재사용하지 않았으며 최종 회귀에서 별도로 확인했다.

[HTTP 원본](http/observations.json)은 동일 fixture와 고정 baseline reader를 이용한다. 기존 저장소 JSON 필터는 다중어 질문2개를 놓쳤고 메타데이터 전용 질의를 오탐했다. Q1–Q5의 정답 절 직접 링크는 기존0개, 새 검색5개다. 이는 탐색 경로 개선이며 실제 사람의 과제 수행 시간 측정은 아니다.

금액 질의의 실제 순차 HTTP 5회: 기존367.108–387.281ms, 새404.813–431.767ms. 새 응답3721bytes, 기존3049bytes. 새 검색은 더 느리며 Node 파싱·렌더링 비용을 추가한다. 고정 기준2000ms 안에 들었고 오류0이다. 전체25개 HTTP 요청과 해시를 원본에 보존했다. 이 작은 corpus만으로 대규모 성능을 주장하지 않는다.

중앙 DB·외부 검색 엔진·Promptfoo 도입 없이 기준을 충족했다. 관측 병목은 요청별 기존 근거 검증과 Node 처리이며 외부 검색 엔진을 먼저 도입할 근거는 얻지 못했다. 큰 corpus, 검색어 다양성, 운영 동시성이 필요해지면 별도 고정 평가로 재판정한다. 모델 토큰·금액은 도구에서 제공되지 않아 미측정, 독자에게 추가 질문0회·사용자 개입0회다.

## 검사 및 재현

준비된 jsonschema Python과 markdown-it14.3.0 런타임으로 `tests/knowledge/reader-check.sh`를 실행한다. 기존 reader12개와 검색5개가 포함된다. 검색 검사에는 Unicode/casefold·제목 없는 문서·늦은 근거 발췌·URL 제외·무결과·실제 anchor·오류/권한 경계·색인 지연이 있다. 관련 `tests/knowledge/*-check.sh` 결과와 root gate는 `checks/`에 보존한다.

`search_preview.py --output NEW_DIRECTORY`는 새 격리 fixture, 실제 baseline/candidate HTTP와 독자 패킷을 만들고 loopback preview를 유지한다. `--observe-only`는 관측 후 서버를 정지한다. baseline 커밋이 로컬 Git에 있어야 하며 의존성을 자동 설치하지 않는다. `m0.mjs`는 현재 공통 parser의 전제 재현일 뿐 완성 제품의 검사 대신 쓰지 않는다.

최초 sandbox reader 실행은 loopback bind EPERM으로 실행 환경 실패였다. 소스를 바꾸지 않고 승인된 로컬 네트워크 실행으로 재시도해 통과했다. `initial-reader.log`는 초기 성공 재실행이며 당시 imported test class로 기존12개가 중복 실행된 두 번째 묶음16개였다. 중복을 제거한 최종 검사는12+5다. 상대경로 관측 파일 쓰기도 main 보호 hook이 거부해 실제 linked worktree 절대경로로 실행했다. `workspace prepare/ready`는 codex 브랜치를 legacy worktree-* 형식으로 받지 않아 실패했으며 config에 bootstrap이 없는 것을 확인하고 실제 Git linked identity를 inspect했다. 준비 명령을 성공했다고 보고하지 않는다.

운영 저장소·검색 서비스·위키 계정·설치 활성화·배포·대규모 성능·의미 검색은 미검증이다. 전체 harness 개발 suite는 변경 범위 밖이며 실행하지 않았다. 최종 head의 독립 LGTM/MATCH와 CI 및 전달 상태는 PR/원장을 따른다.
