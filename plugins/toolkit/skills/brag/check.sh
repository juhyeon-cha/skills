#!/usr/bin/env bash
# brag.py 자기검사. 임시 HOME 으로 축적 자리를 격리하고, 쌓기 → 초안 → 폰트 →
# finalize 전 경로와 실패 경로 둘(0건 · 쓸 수 없는 홈)을 단언한다.
#
#   check.sh            검사만 하고 산출물은 임시 디렉토리와 함께 지운다
#   check.sh <출력폴더>  산출물을 그 폴더에 남긴다 (사람이 열어볼 때)
#
# 통과의 근거는 종료 코드다. root 로 돌리면 "쓸 수 없는 홈" 단언이 무의미해진다 —
# 권한 검사를 우회하므로 그 경우 이 검사는 신뢰할 수 없다.

set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPORT=$HERE/../html-report
OUT=${1:-}
T=$(mktemp -d)
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

cat > "$T/a.json" <<'JSON'
{
  "date": "2026-05-14",
  "project": "결제 게이트웨이",
  "title": "결제 승인 실패 재시도를 큐로 옮겼다",
  "problem": "PG 타임아웃이 그대로 사용자 에러로 나갔다. 하루 평균 40건이 결제 포기로 이어졌다.",
  "solution": "승인 요청을 큐에 넣고 지수 백오프로 3회까지 재시도하게 바꿨다.",
  "result": "결제 실패율이 2.4%에서 0.3%로 떨어졌다. 6주치 로그 기준.",
  "metrics": [
    { "label": "결제 실패율", "from": "2.4%", "to": "0.3%", "delta": "▼ 2.1%p", "good": true }
  ]
}
JSON

cat > "$T/b.json" <<'JSON'
{
  "date": "2026-08-02",
  "project": "정산 배치",
  "title": "야간 정산 배치를 증분 처리로 바꿨다",
  "problem": "전량 재계산이라 거래가 늘수록 배치 시간이 선형으로 늘었다. 아침 9시 마감을 두 번 놓쳤다.",
  "solution": "마지막 성공 시각 이후 거래만 읽도록 커서를 두고, 실패 시 그 커서에서 재개하게 했다.",
  "result": "배치 시간이 4시간 12분에서 22분으로 줄었다. 8월 1주 실측.",
  "metrics": [
    { "label": "야간 배치 소요", "from": "4h 12m", "to": "22m", "delta": "▼ 3h 50m", "good": true }
  ]
}
JSON

# ── 축적: 서로 다른 입력 두 번 → 2건 ────────────────────────────────────────
# 트리를 건드리지 않는지는 전·후 비교로 본다. "지금 트리가 깨끗한가" 로 물으면
# 작업 중인 트리에서 항상 실패해, 검사가 무엇을 보는지 흐려진다.
before=$(git -C "$HERE" status --porcelain 2>/dev/null)
export HOME=$T/home
python3 "$HERE/brag.py" add "$T/a.json" || fail "add a rc=$?"
python3 "$HERE/brag.py" add "$T/b.json" || fail "add b rc=$?"
n=$(wc -l < "$HOME/.brag/entries.jsonl" | tr -d ' ')
[ "$n" = 2 ] || fail "축적 2건이어야 하는데 ${n}건"
after=$(git -C "$HERE" status --porcelain 2>/dev/null)
[ "$before" = "$after" ] || fail "축적이 워킹 트리를 바꿨다:
$(diff <(echo "$before") <(echo "$after"))"

# ── 산출 경로: render → embed-font → finalize ───────────────────────────────
python3 "$HERE/brag.py" render --team "플랫폼팀" --author "차주현" > "$T/draft.html" \
  || fail "render rc=$?"
python3 "$REPORT/embed-font.py" "$T/draft.html" pretendard > "$T/draft-font.html" \
  || fail "embed-font rc=$?"
python3 "$REPORT/finalize.py" "$T/draft-font.html" > "$T/brag.html" || fail "finalize rc=$?"
[ -s "$T/brag.html" ] || fail "산출물이 비었다"

# 부정 대조군 — 통과가 "검사가 안 돌았다" 와 구분되게, 있어야 할 것을 센다.
for pat in '문제' '해결' '성과' '분기' 'class="from"'; do
  grep -qF "$pat" "$T/brag.html" || fail "산출물에 ${pat} 가 없다"
done

# ── 실패 경로 1: 쌓인 기록 0건 ──────────────────────────────────────────────
HOME=$T/empty python3 "$HERE/brag.py" render > /dev/null 2> "$T/err1"
[ $? -ne 0 ] || fail "0건인데 render 가 rc=0"
grep -q '쌓인 기록이 없다' "$T/err1" || fail "0건 사유가 stderr 에 없다"

# ── 실패 경로 2: 쓸 수 없는 홈 ──────────────────────────────────────────────
mkdir -p "$T/ro" && chmod 500 "$T/ro"
HOME=$T/ro/h python3 "$HERE/brag.py" add "$T/a.json" > /dev/null 2>&1
[ $? -ne 0 ] || fail "쓸 수 없는 홈인데 add 가 rc=0"
[ ! -e "$T/ro/h" ] || fail "쓸 수 없는 홈에 무언가 생겼다"
chmod 700 "$T/ro"

if [ -n "$OUT" ]; then
  mkdir -p "$OUT" && cp "$T/draft.html" "$T/brag.html" "$T/a.json" "$T/b.json" "$OUT/" \
    || fail "산출물을 $OUT 에 남기지 못했다"
  echo "남김: $OUT/brag.html · $OUT/draft.html"
fi

echo "OK: brag — 축적 2건 · 산출 경로 rc=0 · 실패 경로 2건"
