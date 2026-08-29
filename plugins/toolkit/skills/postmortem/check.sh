#!/usr/bin/env bash
# postmortem.py 자기검사. 시각 있는 입력과 없는 입력을 각각 전 경로에 태우고,
# 축적하지 않는다는 것과 없는 입력 파일의 실패를 단언한다.
#
#   check.sh            검사만 하고 산출물은 임시 디렉토리와 함께 지운다
#   check.sh <출력폴더>  산출물을 그 폴더에 남긴다 (사람이 열어볼 때)
#
# 통과의 근거는 종료 코드다.

set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPORT=$HERE/../html-report
OUT=${1:-}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# 경과 기록 섹션의 표시. 산출물에서 이 문자열의 건수로 섹션의 유무를 판정한다.
MARK='class="timeline"'

cat > "$T/with-time.json" <<'JSON'
{
  "title": "결제 승인 API 47분 장애",
  "date": "2026-08-20",
  "team": "결제팀",
  "author": "차주현",
  "impact": "20일 14:02~14:49 결제 승인 요청의 62%가 실패했다. 승인 실패 건은 재시도로 복구됐고 이중 청구는 없다.",
  "timeline": [
    { "when": "14:02", "what": "승인 실패율 알림", "detail": "5분 이동 평균이 임계값 5%를 넘어 온콜 호출." },
    { "when": "14:11", "what": "PG 커넥션 풀 고갈 확인", "detail": "활성 커넥션 200/200, 대기 큐 1,400." },
    { "when": "14:31", "what": "풀 크기 상향 배포" },
    { "when": "14:49", "what": "실패율 정상 복귀", "detail": "이동 평균 0.4%." }
  ],
  "causes": [
    {
      "title": "커넥션을 반납하지 않는 경로가 있었다",
      "cause": "타임아웃 예외가 finally 밖에서 처리돼 그 경로만 커넥션을 반납하지 않았다. 평소에는 타임아웃이 드물어 누수가 드러나지 않았다.",
      "action": "풀 크기를 200에서 400으로 올려 급한 불을 껐고, 다음 배포에서 반납을 finally 로 옮겼다.",
      "prevention": "커넥션 누수를 잡는 통합 테스트를 추가했다. 풀 사용률 80% 경보는 아직 만들지 않았다 — 액션 아이템으로 남겼다."
    },
    {
      "title": "포화를 알리는 지표가 없었다",
      "cause": "대시보드에 실패율만 있고 풀 사용률이 없어, 알림이 울린 뒤에야 원인을 찾기 시작했다.",
      "action": "장애 중 수동으로 풀 상태를 확인했다.",
      "prevention": "풀 사용률을 대시보드와 경보에 넣기로 했다. 아직 하지 않았다."
    }
  ],
  "actions": [
    { "todo": "커넥션 풀 사용률 80% 경보 추가", "owner": "결제팀 박OO", "due": "2026-09-05" },
    { "todo": "타임아웃 경로 커넥션 반납 통합 테스트 CI 편입", "owner": "결제팀 차주현", "due": "2026-09-12" }
  ],
  "refs": ["장애 채널 로그 #incident-2026-08-20", "PG 사업자 상태 페이지 (해당 시간 이상 없음)"]
}
JSON

# 시각 정보가 하나도 없는 입력. timeline 키 자체가 없다.
python3 - "$T/with-time.json" "$T/no-time.json" <<'PY'
import json, sys
rec = json.load(open(sys.argv[1], encoding='utf-8'))
rec.pop('timeline')
rec.pop('refs')
json.dump(rec, open(sys.argv[2], 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PY

run() {  # <입력> <이름> — render → embed-font → finalize
  python3 "$HERE/postmortem.py" "$1" > "$T/$2-draft.html" || fail "$2 render rc=$?"
  python3 "$REPORT/embed-font.py" "$T/$2-draft.html" pretendard > "$T/$2-font.html" \
    || fail "$2 embed-font rc=$?"
  python3 "$REPORT/finalize.py" "$T/$2-font.html" > "$T/$2.html" || fail "$2 finalize rc=$?"
  [ -s "$T/$2.html" ] || fail "$2 산출물이 비었다"
}

# ── 시각 있는 입력: 세 요소가 다 있다 ───────────────────────────────────────
export HOME=$T/home
mkdir -p "$HOME"
run "$T/with-time.json" with-time
for pat in "$MARK" '원인' '조치' '재발 방지' '액션 아이템'; do
  grep -qF "$pat" "$T/with-time.html" || fail "산출물에 ${pat} 가 없다"
done

# ── 축적하지 않는다: 홈 아래에 새 파일이 0건 ────────────────────────────────
n=$(find "$HOME" -mindepth 1 | wc -l | tr -d ' ')
[ "$n" = 0 ] || fail "홈 아래에 ${n}건이 생겼다:
$(find "$HOME" -mindepth 1)"

# ── 시각 없는 입력: 경과 기록 섹션이 빠지고 그 사실이 한 줄로 남는다 ────────
run "$T/no-time.json" no-time
m=$(grep -cF "$MARK" "$T/no-time.html")
[ "$m" = 0 ] || fail "시각이 없는데 경과 기록 표시가 ${m}건 남았다"
grep -qF '경과 기록 섹션을 넣지 않았다' "$T/no-time.html" \
  || fail "뺐다는 사실이 산출물에 없다"
# 부정 대조군 — 위 0건이 "검사가 안 돌았다" 와 구분되게, 있는 쪽을 함께 센다.
k=$(grep -cF "$MARK" "$T/with-time.html")
[ "$k" -ge 1 ] || fail "시각이 있는 산출물에도 경과 기록 표시가 0건이다 — 판정이 무의미하다"

# ── 실패 경로: 없는 입력 파일 ───────────────────────────────────────────────
python3 "$HERE/postmortem.py" "$T/없는파일.json" > /dev/null 2> "$T/err"
[ $? -ne 0 ] || fail "없는 파일인데 rc=0"
grep -qF '없는파일.json' "$T/err" || fail "stderr 에 그 경로가 없다"

if [ -n "$OUT" ]; then
  mkdir -p "$OUT" && cp "$T"/*.json "$T/with-time.html" "$T/no-time.html" \
    "$T/with-time-draft.html" "$T/no-time-draft.html" "$OUT/" \
    || fail "산출물을 $OUT 에 남기지 못했다"
  echo "남김: $OUT/with-time.html · $OUT/no-time.html"
fi

echo "OK: postmortem — 세 요소 있음 · 홈 아래 0건 · 시각 없으면 섹션 0건 · 없는 파일 rc≠0"
