# 설명 구성과 위키 표시 관찰

동일한 합성 주문 취소 입력으로 업무 맥락, 역할별 설명, 정상·응답 유실 사례와
흐름도·카드를 작성했다. 정적·관리형 위키에서 실제 표시까지 확인했다.
`protocol-wiki.md`와 `frozen-wiki.json`이 실행한 범위다. 기존 `protocol.md`는
위키 표시를 포함하기 전 실행하지 않은 제안이며 비교 실험 결과가 아니다.

## 관찰 결과

- 독립 검토: C1–C3와 C5 내용 통과. 기존 12개 사실 기준을 보존했다.
- 새 독자: 문서만 읽고 네 종합 질문에 답했다. 맥락, 역할별 다음 행동,
  재조회 이유, 시각 표현의 범위를 이해했다. 개별 12문항 재시험이나 인간 연구는 아니다.
- 실제 화면: C4 확인. 정적·관리형 모두 1280×900과 390×844에서 관찰했다.
  단계의 세로 화살표, 마지막 단계의 다섯 결과, 세 카드가 표시되었다.
  넓은 정적 화면은 카드 2열, 관리형은 3열이며 좁은 화면은 모두 1열이다.
  한글 문장·조건·미정 사항이 잘리지 않았고 문서 너비는 모바일 뷰포트 390px와 같았다.
  기존 제목 앵커로 해당 절에 도착했고 목록 읽기 순서를 유지했다.
- 위키 회귀 검사 46개, 관리형 reader 13개, 검색 5개 통과.
  저장소 gate의 플러그인 검증·shellcheck 63개·설명 일치 검사 통과.

`reader-prompt.txt`는 보낸 질문이고 `reader-response.md`는 실제 독자 응답 원문이다.
`reader-response-record.json`에는 원문 메시지 식별자와 해시를 기록했다.
`independent-review.md`는 별도 검토자의 실제 반환이다. 검토자가 보류한 C4 화면
판정은 이후 위의 실제 브라우저 관찰로 보완했다. `observation-hashes.json`은
검토한 문서·응답 바이트를 식별할 뿐 의미 정확성을 증명하지 않는다.
예제 문서의 대기 상태 문구는 작성 시점의 고정 바이트로 보존했으며 후속 결과는 이 기록을 따른다.

## 재현과 범위

준비된 MarkdownIt 14.3.0 모듈 경로를 지정해 다음을 실행한다. 출력 디렉토리는 새 경로여야 한다.

```sh
node plugins/knowledge/scripts/wiki/build.mjs tests/knowledge/reader-composition/documents NEW_OUTPUT MARKDOWN_IT_MODULE
node plugins/knowledge/scripts/wiki/check.mjs tests/knowledge/reader-composition/documents/manifest.json NEW_OUTPUT
WIKI_MARKDOWN_IT_MODULE=MARKDOWN_IT_MODULE bash tests/knowledge/knowledge-wiki-check.sh
WIKI_MARKDOWN_IT_MODULE=MARKDOWN_IT_MODULE KNOWLEDGE_PYTHON=PYTHON_WITH_JSONSCHEMA bash tests/knowledge/reader-check.sh
bash scripts/check.sh
```

실제 정적 관찰 빌드의 snapshotHash는
`6acc69e8ef2a23c1ea7fc8bb87a17b15d33a4ec9ad59a8626f0104c257b89f47`이며
본문 링크 13개를 검증했다. 관리형 관찰은 `search_fixture.published_fixture()`의
임시 저장소에서 문서 입력을 이 예제 두 페이지로 대체해 실제 HTTP 경로로 열었다.
검토 영수증은 합성이므로 이 화면이 실제 업무 문서의 승인이나 서비스 완료를 증명하지 않는다.

초기 검사의 이미지 fixture는 정적 위키의 기존 이미지 금지 정책에 맞춰 분리했다.
기존 negative-control fixture의 공유 모듈 복사 누락을 수정한 뒤 전체 검사를 통과했다.
로컬 루프백 바인딩은 sandbox 밖에서 실행했고 의존성 다운로드·원격 게시 없이 확인했다.

이 결과는 로컬 렌더링과 작은 합성 문서의 이해 관찰이다. 실제 서비스 배포,
설치된 플러그인 갱신, 정책 변경 후 자동 갱신, 기존 문서 대비 향상은 확인하지 않았다.
흐름도 지원은 순차 단계와 마지막 결과 분기로 제한되며 임의 그래프·Mermaid 실행은 포함하지 않는다.
