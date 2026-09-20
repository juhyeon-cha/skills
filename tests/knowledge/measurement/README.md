# 릴리스 없는 1단계 실측

개발 중인 toolkit 소스를 실행별로 복사해 바로 측정한다. 설치된 플러그인이나 버전은 바꾸지 않는다. 현재 실행기는 1단계의 두 사례를 지원한다.

| 사례 | 실제 관측 |
|---|---|
| `workflow` | 의도적으로 잘못된 문서의 독립 리뷰 → 작성자 수정 → 새 리뷰어 판정 → 적용 중 프로세스 종료·재개 → 다음 코드 변경의 기준선 계승 → 작성·리뷰·적용 |
| `document-ac` | 정상 문서와 결함 문서에 대한 별도 독자 응답 → 독립 판정자의 AC별 대조 |

Python 3.10 이상, Git, `jsonschema`가 필요하다. 기존 개발 환경의 Python을 사용한다. `prepare`는 의존성을 먼저 확인하고, 이미 있는 출력 디렉터리는 덮어쓰지 않는다.

```bash
python tests/knowledge/measurement/runner.py prepare \
  --case workflow --out /tmp/knowledge-workflow-001
python /tmp/knowledge-workflow-001/frozen/runner.py next \
  --run /tmp/knowledge-workflow-001
```

이후에는 출력된 **고정 실행기**를 계속 사용한다. `next`는 필요한 로컬 명령을 실행한 뒤 에이전트에 전달할 작업을 반환한다. 실제 역할 호출은 현재 Codex 세션의 도구로 수행한다. 이 CLI 자체가 모델을 호출하거나 API 키를 요구하지는 않는다. 에이전트에게 맡길 때는 [coordinator.md](coordinator.md)를 읽도록 한다.

```text
tests/knowledge/measurement/coordinator.md 절차로 현재 소스를 workflow와
 document-ac 두 사례에서 실측하고, 실제 응답과 미실행 범위를 보고하세요.
```

소스를 수정했으면 새 출력 경로로 `prepare`한다. 같은 실행에 새 소스를 섞지 않는다. 중간 종료 후에는 `status`로 보존 상태를 확인하고 `next`로 재개한다. 에이전트 작업이 대기 중이면 동일한 작업 ID가 반환된다. 이미 응답을 받았다면 보관한 응답을 먼저 접수한다. 차단이나 도구 부재는 `not-executed`로 접수하며, 이전 응답으로 대체하지 않는다.

```bash
python /tmp/knowledge-workflow-001/frozen/runner.py status \
  --run /tmp/knowledge-workflow-001
```

실행 디렉터리에는 소스·실행기 해시와 Git 상태(`manifest.json`), 실제 전달문(`tasks/`), 원문 응답(`generated/receipt-*.json`), CLI 실행 결과(`commands/`), 재개 상태(`measurement.sqlite3`)가 남는다. 공유할 때는 이 디렉터리를 함께 보존한다. 경로가 절대 경로로 기록되므로 다른 위치로 옮긴 사본은 증거 열람용이며 이어서 실행하는 용도가 아니다.

`pass`는 선택한 사례에서 기대한 결과가 관측됐다는 뜻이다. 결함 문서는 실패로 판정돼야 사례가 통과한다. 에이전트 식별자는 부모 세션이 실제 도구 결과에서 기록하며 CLI가 인증하지 않는다. 설치본 자동 로딩, 새 Codex 세션 인계, 실제 서비스 실행·배포는 별도 미검증 항목이다. 이 결과만으로 1단계 전체 완료를 선언하지 않는다.

회귀 검사는 다음 명령으로 수행한다. 여기의 합성 응답은 실제 실측 증거가 아니다.

```bash
KNOWLEDGE_PYTHON=python bash tests/knowledge/measurement-check.sh
```

기존 응답을 재생하는 검사도 별도로 유지한다. `tests/knowledge/foundation-observation/replay.py`는 새 에이전트 실측을 대신하지 않는다.

## 이번 구현의 관측

[2026-09-20 기록](observation.json)은 실제 전달문·응답·명령 로그와 실행 상태를 보존한 열람용 묶음이다. 고정 입력은 해당 manifest의 해시와 저장소 소스로 대조할 수 있다.

- `document-ac`: 독자 2명과 판정자 1명의 실제 호출로 정상본 5개 AC 통과, 결함본의 예외 누락·거짓 완료 주장 검출을 확인했다.
- `workflow`: 첫 변경의 거절·수정·독립 통과, 적용 중 종료와 재개, 다음 기준선 계승을 확인했다. 두 번째 변경의 작성까지 수행한 뒤 최종 리뷰어의 참조 문서 읽기가 `child role is unidentified`로 차단됐다. 전체 결과는 `not-executed`다.
- 회귀 검사는 합성 응답으로 두 변경의 끝까지 진행, 적용 후 재진입, 잘못된 판정, 식별자·출처 불일치와 오래된 응답, 파일 변조, 동시 실행과 중복 출력 거부를 검사한다. 실제 역할 호출과 구분한다.
