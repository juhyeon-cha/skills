고정 입력: 한국어 중복 제목, 표, 코드, 동일 문서 anchor, 상대 문서 링크, 미허용 문서 링크, raw HTML, javascript/data 링크를 포함한 두 문서. 기존 정적 renderer와 동일한 pinned markdown-it runtime을 사용한다.
기대: 제목·표가 HTML 요소로 변환되며 중복 제목은 고유 ID다. 허용 문서/anchor만 내부 경로로 연결할 수 있다. HTML·위험 프로토콜은 실행되지 않고 숨은 문서 내용을 읽지 않는다. 프로세스 입력은 허용된 text뿐이며 repository/state 파일을 renderer가 직접 읽지 않는다.
실행 전 질문/정답: 1) 일반 본문을 실제 요소로 렌더링 가능한가=가능해야 한다. 2) 비허용 대상은 내용을 읽지 않고 비활성 처리 가능한가=가능해야 한다. 3) 기존 Python reader의 추가 runtime 경계는 무엇인가=관측한 Node/module requirement와 실패 동작을 명시한다.
품질 판정: 위 기대 전부 관측하고 독립 evaluator가 구현 전제로 충분한지 판정한다. 비용: 실제 실행 시간만 기록, 모델 tokens/요금 미제공은 unknown. 프로세스 호출 지연을 관측하여 요청당 수행 가능성을 판단하되 성능 일반화는 하지 않는다. M0는 제품 완료 판정이 아니다.
