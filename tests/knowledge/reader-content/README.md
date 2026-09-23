# 독자별 지식 내용 평가

FE·BE·기획·PO가 같은 기능을 각자의 업무에 사용할 수 있도록, knowledge의
생성·갱신·검토 절차에 독자별 필수 질문과 근거 연결을 추가한 사례다.
[생성 문서](generated/knowledge.md)는 가상의 주문 취소 기능을 다룬다.
공통 정책을 한곳에 두고 화면 구현, 서버 계약, 기획 수용 조건, 제품 판단을 연결한다.

## 입력과 관측 기록

- [평가 절차](protocol.md), [질문 12개](questions.json), [정답 근거](expectations.json),
  `fixture/`의 코드·가상 의사결정을 문서 작성 전에 고정했다. 바이트 해시는 `frozen.json`에 있다.
- 독립 작성자 `/root/content_author`는 코드·결정·질문과 후보 지침을 읽었다.
  정답표는 제공하지 않았다. [내용 연결 기록](generated/coverage.json)은 질문별
  근거·조건·예외·답변 위치와 미확인 사항을 담는다.
- 이전 대화 없이 실행한 `/root/reader_a`와 `/root/reader_b`는 각각 정상·결함 문서와
  같은 질문만 읽었다. 두 모델 실행이 네 업무 상황을 각각 답한 것이며, 사람 네 명의 평가가 아니다.
- `observations/reader-*-prompt.txt`와 `reader-*-dispatch.txt`는 실제 입력이다.
  `reader-a.json`과 `reader-b.json`은 세션의 실제 최종 응답을 수정 없이 추출했다.
  `returns.json`에 응답 식별자·시각·해시를 보존했다. 입력 분리는 프롬프트 수준이며 도구 접근을 강제 차단한 것은 아니다.
- `observations/defect.patch`는 정상 문서를 보존하면서 만든 두 결함을 보여준다.
  응답 유실을 실패 확정·즉시 재요청으로 바꾸고, 미측정 성과를 달성한 결과로 바꿨다.
- 독립 검토자 `/root/content_review`는 원본 근거·고정 기준·문서·실제 독자 응답을 대조한다.
  [판정 원문](observations/acceptance.md)에 질문별 결과와 근거를 보존한다.

정상 문서와 독자 응답은 12개 필수 기준 모두 통과했다. 결함본은 FE2·PL2·PO1·PO3에서
실패해 두 결함 유형 모두 검출됐다. 결함본 독자가 허위 성과와 서문의 모순을 감지했더라도,
문서에서 사라진 미측정 사실·미정 조건을 대신 입증한 것으로 계산하지 않았다.

## 확인 범위

저장소 게이트의 플러그인 검증, 셸 63개 검사, 설명 일치가 통과했다.
`source-contract-check.sh` 69개, `automation-check.sh` 25개,
`document-ac-check.sh` 7개로 관련 회귀 테스트 101개가 통과했다.
소스 계약 검사에는 새 독자 기준 파일이 설치본에서 누락되면 작성 시작 전에 실패하는 경우가 포함된다.

이 관측은 작은 합성 입력에서 문서 내용과 독해를 검증한다. 일반적인 생성 품질 향상,
실제 팀의 업무 시간 단축, 운영 서비스의 동작·성과, 설치된 플러그인의 로딩을 입증하지 않는다.
공통 정책 변경 이후 전체 갱신을 수행하는 실험도 이번에는 실행하지 않았다.
갱신 경로의 지침 연결은 독립 정적 리뷰와 기존 회귀 검사로 확인했다.
CLI는 독자 질문의 의미나 충실도를 자동 판정하지 않으며, 실행 조정자가 관련 자료를 검토자에게 전달해야 한다.
모델별 토큰·비용은 관측되지 않았다.

## 다시 확인하기

저장된 입력·산출물의 바이트를 확인하려면 저장소 루트에서 실행한다.
이 명령은 과거 응답을 새로운 모델 평가로 재실행하거나 의미를 판정하지 않는다.

```sh
python3 - <<'PY'
from pathlib import Path
import hashlib, json
root = Path('tests/knowledge/reader-content')
for path, digest in json.loads((root / 'artifacts.json').read_text()).items():
    actual = hashlib.sha256((root / path).read_bytes()).hexdigest()
    assert actual == digest, path
print('저장된 관측 바이트 일치 — 새로운 의미 평가 아님')
PY
```

새 문서나 지침으로 평가하려면 `protocol.md`를 따라 입력·질문·판정 기준부터 새 버전으로 고정하고,
새 작성·독자·판정 응답을 별도로 보존한다. 기존 응답을 변경된 문서의 증거로 재사용하지 않는다.
회귀 검사는 `KNOWLEDGE_PYTHON`으로 jsonschema 4.26.0이 준비된 Python을 지정한 뒤
위 세 검사와 `bash scripts/check.sh`를 실행한다. 네트워크 다운로드나 원격 반영은 필요하지 않다.
