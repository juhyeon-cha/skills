## 고정 제품 수용 조건
1. 격리 producer/consumer의 동일한 정본을 사용한다. 정상 완료 및 게시 상태에서 문서별 독립 URL, 한글 중복 제목 목차, 표·코드·상대 문서/anchor 링크를 실제 HTML로 제공한다. 원문과 code commit/goal/projection ID를 바꾸지 않는다.
2. 전체 완료·필수/비공개 수·진단은 즉시 보이며 기술 JSON과 커밋/해시는 disclosure 아래에 둔다. 기존 query/wiki/read 의미와 API 구조는 유지한다.
3. 잘못된 URL·경로탈출·없는 문서/anchor·HTML/script·위험 URI는 실행/파일 읽기/권한 확대를 일으키지 않는다. 권한 회수·부분 완료·목표 철회·오래된 문서 후 이전 문서 URL 요청은 본문을 제공하지 않는다. runtime 누락/실패는 명확히 실패하며 오래된 본문으로 대체하지 않는다.
4. 기존 reader/정적 wiki/multi-repo 회귀와 bash scripts/check.sh가 exit 0이다. 변경된 권한 경로의 negative control을 격리 사본에서 관측한다.
5. 재실행 가능한 로컬 fixture/preview runner는 port 0과 명시적 종료를 지원하고 실제 HTTP 기록·입력·기대 답·시간을 보존한다. fixture의 synthetic review와 실제 독립 모델 호출을 구분한다. 실제 브라우저에서 문서/목차/본문 링크/disclosure/권한 회수 경로와 넓고 좁은 화면을 확인한다.
6. 독립 독자는 아래 질문을 공개 결과와 브라우저 관측만으로 답한다. 정답·근거 전부 일치, 부분 완료 오판 0, 숨은 근거 추론 0이 통과 기준이다. 독립 품질 LGTM과 별도 수용 MATCH를 최종 전달 head에 확보한다.

## 고정 독자 질문과 정답 근거
Q1: producer/consumer가 주고받는 필드명과 예시는? 정상 정본 contract.md의 total, JSON {"total":120}; guide.md 표의 금액 합계 설명을 인용한다.
Q2: 계약 문서에서 호출 안내의 검증 절로 이동할 수 있는가? contract.md 상대 guide.md#검증 링크와 해당 문서 제목 ID를 확인한다.
Q3: 두 저장소가 모두 검증돼도 운영 배포까지 증명되는가? 아니다. 로컬 검사와 합성 검토 기록 경계이며 화면의 근거 안내에 표시된다.
Q4: producer만 완료인 결과에서 목표 전체 완료인가? 아니다. completion incomplete 및 consumer 대기 근거를 확인한다.
Q5: consumer 권한이 회수된 뒤 저장한 문서 URL로 본문을 다시 볼 수 있는가? 아니다. 다음 요청 404; 이미 읽은 바이트 회수는 보장하지 않는다. 비공개 이유/내용은 추론할 수 없다.
Q6: 문서 변경 또는 목표 철회 후 예전 본문이 제공되는가? 아니다. direct document URL 404이며 개요는 미완료/진단 상태다.

## 비교·비용 판정
동일 정본을 이전 renderer(6be4fe0)와 후보로 렌더링한다. 이전에는 pre 본문과 저장소 경로만, 후보는 실제 표/제목/목차/문서 URL이 존재함을 관측한다. 사람이 더 빠르다는 주장은 사용자 실험 없이 하지 않는다. 실제 HTTP 지연·실행 시간만 기록하고 모델 tokens/요금은 미제공시 null. 두 방식의 품질/비용 tradeoff를 보고한다.
