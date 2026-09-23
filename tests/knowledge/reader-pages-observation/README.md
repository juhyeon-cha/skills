# 관리형 문서 읽기 평가

skills#429의 고정 수용 조건은 [reader-ac.md](reader-ac.md), M0 관측과 독립 판정은
[m0-close.md](m0-close.md)에 있다. 실제 소스 해시는 [source-hashes.json](source-hashes.json)이다.

## 결과와 경계

- 동일 정본의 이전 화면은 저장소 페이지 안 `pre` 본문이었다. 후보는 문서별 URL·제목 목차·표·코드·허용된 본문 링크를 제공한다. [comparison.json](comparison.json)은 동일 projection에 대한 렌더 비교다. 단일 로컬 render 관측은 이전 약 0.04ms, 후보 약 46ms로, Node 시작 비용이 추가된다. 사람의 읽기 속도 개선이나 서비스 성능 일반화는 측정하지 않았다.
- [checks.json](checks.json)의 knowledge 검사 9개와 저장소 게이트가 모두 통과했다. reader 검사 12개에는 실제 HTTP/CLI·권한 회수·부분 완료·철회·문서 변경·runtime 실패·경로/HTML/링크 경계가 포함된다. 저장소 링크 경계를 제거한 격리 사본에서 잘못된 교차 저장소 링크가 활성화되는 negative control을 확인했다.
- 최초 전체 검사에서 브라우저 내부 오류 문구가 공개 CLI 오류 prefix로 해석돼 source-contract가 실패했다. 문구 수정 후 해당 전체 계약·reader·게이트를 다시 실행했다. `initial-*`은 실패를 보존하고, 같은 이름의 최종 로그와 checks.json은 수정 후 결과다. 전체 tests/run-all.sh는 실행하지 않았다.
- `complete/`, `partial/`, `revoked/`, `drift/`, `withdrawn/`는 격리 Git 두 저장소에서 생성한 HTTP 원본과 공개 API다. 저장소 검토 영수증은 모두 **시험용 응답**이다. 실제 모델이 제품 지식 갱신을 수행했다는 뜻이 아니다.
- [independent-reader.json](independent-reader.json)은 실제 독립 모델 `/root/reader_pages_reader`의 응답 요약과 고정 정답 대조다. 여섯 질문 모두 일치했다. 실제 호출과 시험용 영수증은 별개다. 모델 tokens·요금·모델 식별자는 제공되지 않았다.
- [browser-observations.md](browser-observations.md)는 실제 CUA 링크·목차·disclosure·390px 화면 관측 요약이다. raw AX/스크린샷은 작업 대화에 있고, 지원되지 않은 content export는 보존 파일로 주장하지 않는다. 권한 회수 후 HTTP 404와 개요의 비공개·미완료는 관측했지만 브라우저 404 안내 페이지 렌더링은 확인하지 못했다. 이미 열린 화면을 자동 회수하지 않는다.
- `final-complete/`는 제목 중복 제거와 입력/출력 경계 보완 후 새 프로세스에서 재관측한 최종 정상 화면이다. 원본 정본·상태 의미는 동일하며 임시 fixture의 커밋·projection ID는 재실행마다 달라질 수 있다.

## 재현

저장소 루트에서 기존 Python 및 외부 Markdown runtime을 선택한다. 준비 방법은
[관리형 reader](../../../plugins/knowledge/references/reader.md)를 따른다. 자동 설치·운영 연결은 없다.

```sh
export WIKI_MARKDOWN_IT_MODULE=/absolute/user-owned/wiki-runtime/node_modules/markdown-it
export KNOWLEDGE_PYTHON=/absolute/user-owned/knowledge-venv/bin/python
bash tests/knowledge/reader-check.sh
"$KNOWLEDGE_PYTHON" -B tests/knowledge/multi_repo/reading_preview.py --output /absolute/new-observation
```

runner는 새 격리 두 저장소를 만들고, 선택한 principal/goal의 서버를 port 0으로 시작하며 URL을 출력한다.
브라우저에서 저장소 → 계약 → 목차/호출 안내 → 근거 펼치기를 확인한다. Ctrl-C는 이 runner 소유 서버만 종료한다.
fixture와 관측 파일은 남기며, 운영 저장소나 설치본을 변경하지 않는다. HTTP 자동 관측은 `--observe-only`로 종료한다.
`--case partial|revoked|drift|withdrawn`으로 각 실패/제한 상태를 같은 생성 절차로 재현한다.
각 실행은 존재하지 않는 새 `--output`을 사용한다. `observations.json`은 실제 HTTP 응답·시간·해시를 저장하고
브라우저·독립 모델 관측 여부는 자동으로 성공 처리하지 않는다. 그 두 평가는 별도 실제 호출이 필요하다.

`files.sha256.json`은 이 평가 묶음의 파일 무결성 목록이다. 운영 배포·대규모 부하·다중 사용자 인증·
지식 문서의 실제 업무 정확도·설치본 활성화는 이 평가의 검증 범위가 아니다.
