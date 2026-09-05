#!/usr/bin/env bash
# R-DUP 언어 축소의 대조군 — 축소가 작동하는가, 그리고 남은 커버리지가 살아 있는가.
#
# checks/rules-check.sh 의 R-DUP 주석 "부정 대조군(이 검사가 죽었는지)" 이 산문으로 적어
# 둔 절차를 실행 가능한 형태로 만든 것이다. 그 주석이 요구하는 세 단언을 그대로 든다:
#   ① 사본이 실재하고 ② 원본과 다르며 ③ 주입한 문장이 실제 원천 단위 목록에 있다.
#   ③ 이 없으면 임계값 미만의 문장을 주입했을 때 사본은 원본과 다른데 적중이 0이고,
#   그러면 대조군이 공허한 채로 "검사가 죽었다" 로 오독된다.
#
# 재는 것 둘.
#   (A) 부정 대조 — 한글이 없는 파일 + 원천 문장의 **영어 번역**.
#       판정: 언어 제외 1파일 · rc 0. **적중 0줄은 판정하지 않는다** — 축소 전에도 0줄이었고
#       (M0 실측 harness-g88o.1.1) 축소 뒤에는 픽스처가 스캔에서 빠져 구조적으로 나올 수도
#       없다. 축소가 실제로 일어났다는 근거는 scope 줄의 **제외 수** 하나이고, 적중 수는
#       보고 줄에 관측값으로만 찍는다.
#   (B) 양성 대조 — 한국어 역할 정의 사본 + 원천 문장 **그대로**.
#       기대: 적중 1줄 이상 · rc 1. 축소 뒤에도 한국어 문서의 복제는 그대로 잡힌다.
#       역할 정의를 기점으로 쓰는 것은 그것이 이 스토리의 번역 표면 밖이기 때문이다.
#
# 이력: 초판(M0, harness-g88o.1.1)은 인자로 받은 영어 번역본을 (A) 의 기점으로 썼고 재는
#   것이 "언어 교차에서 R-DUP 이 죽는가" 였다. 그 답이 "죽는다" 로 확정되고 사용자가 축소를
#   결정한 뒤(스토리 harness-g88o 의 note), 이 스크립트가 재는 것은 축소의 작동으로 바뀌었다.
#   인자를 없앤 것은 그 결과다 — (A) 의 판정을 가르는 것은 기점 파일이 아니라 **한글의
#   유무**이므로 픽스처를 여기서 만든다. 인자가 사라져 트리 밖 사본 없이 돌아간다.
#
# 귀속: rules-check.sh 는 R-DUP 말고도 여러 규칙을 돌리므로 전체 rc 만으로는 R-DUP 에
#   귀속되지 않는다. 먼저 RDUP_SCAN_EXTRA 없이 한 번 돌려 기준선 rc 를 잡고(0이 아니면
#   여기서 멈춘다), 적중은 사본 경로를 지목한 "✗ R-DUP <경로>:<줄>" 줄로만 센다.
#
# 사용: bash checks/rdup-language-probe.sh   (인자 없음)
#   사본 둘은 mktemp -d 아래에 만들고 끝나면 지운다.
#
# 종료 코드: 0 = 위 기대대로다. 1 = 기대와 다르다(그 사실이 곧 산출물이다). 2 = 전제 불성립.
set -uo pipefail

# 대상은 플러그인 트리다. rules-check 자신은 원장 검사에 lib/harness-root.sh 를 쓰므로 이 프로브도
# 하네스 루트가 보이는 자리(스토리 워크트리 안, 또는 HARNESS_ROOT 지정)에서 돌아야 기준선이 선다.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$PLUGIN_ROOT" || exit 2   # 호출자 CWD 에서 계속 돌면 다른 트리를 판정한다 (2 = 전제 불성립)

AGENT="agents/implementer.md"
SRC_DOC="hooks/session-context.md"
RULES="checks/rules-check.sh"

# 주입할 원천 문장 한 쌍. 손으로 고른 유일한 값이며, 아래에서 셋을 단언한다 —
# SRC_DOC 에 그대로 있는가 · RDUP_MIN 이상인가 · (B) 의 적중이 이 문장을 지목하는가.
# 마크업(**·백틱)이 없는 줄에서 고른다 — 원천 단위는 정규화된 형태이고, 마크업이 있으면
# SRC_DOC 원문의 grep 과 어긋난다(정규화 함수를 여기 복제하지 않으려는 선택이다).
# 원천 단위는 `다. ` 로 갈린 조각이라 문장의 마지막 "다" 가 빠진 형태다 — 원문 grep 도 그 부분문자열로 한다.
UNIT_KO='게이트가 있어도 금지는 그대로다 — 게이트는 우회 가능하고, "못 막는 것"은 "해도 되는 것"이 아니'
UNIT_EN='Even with a gate the prohibition stands - a gate can be bypassed, and "cannot block" is not "allowed".'

die() { echo "✗ $*" >&2; exit 2; }

# ── 전제: 기점의 실재를 먼저 단언한다 ────────────────────────────────
# cmp 의 비-0 만으로 판정하지 않는다 — 부재의 rc 2 와 차이의 rc 1 이 || 에서 같은 분기다.
[[ -s "$AGENT" ]]   || die "$AGENT 가 없거나 비었다 ((B) 사본의 기점)"
[[ -s "$SRC_DOC" ]] || die "$SRC_DOC 이 없거나 비었다 (원천 문장의 출처)"
[[ -s "$RULES" ]]   || die "$RULES 가 없거나 비었다"

grep -qF -- "$UNIT_KO" "$SRC_DOC" \
  || die "주입할 문장이 $SRC_DOC 에 없다 — 문서가 바뀌었으면 이 스크립트의 UNIT_KO/UNIT_EN 을 고쳐라: $UNIT_KO"

RDUP_MIN=$(sed -n 's/^RDUP_MIN=\([0-9][0-9]*\).*/\1/p' "$RULES" | head -1)
[[ -n "$RDUP_MIN" ]] || die "$RULES 에서 RDUP_MIN 을 못 읽었다 — 임계값 표기가 바뀌었으면 이 파생을 고쳐라"
n_bytes=$(printf '%s' "$UNIT_KO" | LC_ALL=C wc -c | tr -d ' ')
[[ "$n_bytes" -ge "$RDUP_MIN" ]] \
  || die "주입할 문장이 ${n_bytes}바이트로 임계값 ${RDUP_MIN} 미만이다 — (B) 도 0줄이 나와 대조군이 공허해진다"

# ── 기준선: RDUP_SCAN_EXTRA 없이 돌린 rc 와 제외 수 ───────────────────
base_out=$(bash "$RULES" 2>&1); rc_base=$?
[[ "$rc_base" -eq 0 ]] || {
  printf '%s\n' "$base_out" | grep '^✗' >&2
  die "기준선 rules-check 이 rc=$rc_base 다 — 이 트리에서는 사본의 rc 를 R-DUP 에 귀속할 수 없다"
}
skip_base=$(printf '%s\n' "$base_out" | grep 'R-DUP' | sed -n 's/.*언어 제외 \([0-9][0-9]*\)).*/\1/p' | head -1)
[[ -n "$skip_base" ]] || die "기준선 출력의 R-DUP scope 줄에서 '언어 제외 <수>' 를 못 읽었다 — 표기가 바뀌었으면 이 파생을 고쳐라"

# ── 사본 둘 ───────────────────────────────────────────────────────────
TMP=$(mktemp -d) || die "mktemp 실패"
trap 'rm -rf "$TMP"' EXIT
A="$TMP/translated.en.SKILL.md"   # 한글 없는 픽스처 + 원천 문장의 영어 번역
B="$TMP/implementer.ko.md"        # 한국어 역할 정의 사본 + 원천 문장 그대로
{ printf '# Translated skill fixture\n\nThis file stands in for a skill that M2-M5 translate: it holds no Hangul at all.\n\n'
  printf '%s\n' "$UNIT_EN"; } > "$A"
{ cat "$AGENT"; printf '\n%s\n' "$UNIT_KO"; } > "$B"

[[ -s "$A" ]] || die "사본 (A) 가 만들어지지 않았다: $A"
[[ -s "$B" ]] || die "사본 (B) 가 만들어지지 않았다: $B"
cmp -s "$B" "$AGENT" && die "사본 (B) 가 기점과 같다 — 주입이 안 됐다"
# (A) 의 전제는 "한글이 없다" 다. 픽스처에 한글이 섞이면 제외되지 않아 대조가 공허해진다.
LC_ALL=C grep -q $'[\xea-\xed]' "$A" && die "사본 (A) 에 한글이 있다 — 픽스처를 고쳐라 (제외되지 않아 (A) 가 무의미해진다)"

# ── 측정 ──────────────────────────────────────────────────────────────
# 적중 줄과 제외 수는 파일로 넘긴다 — $(…) 안의 대입은 서브셸에 갇혀 호출부로 오지 않는다.
run_probe() {  # run_probe <사본경로> <태그> → stdout: rc · 적중 줄: $TMP/hits.<태그> · 제외 수: $TMP/skip.<태그>
  local extra="$1" out rc
  out=$(RDUP_SCAN_EXTRA="$extra" bash "$RULES" 2>&1); rc=$?
  printf '%s\n' "$out" | grep -F "✗ R-DUP $extra:" > "$TMP/hits.$2"
  printf '%s\n' "$out" | grep 'R-DUP' | sed -n 's/.*언어 제외 \([0-9][0-9]*\)).*/\1/p' | head -1 > "$TMP/skip.$2"
  echo "$rc"
}

rc_a=$(run_probe "$A" a); hits_a=$(cat "$TMP/hits.a"); n_a=$(grep -c . "$TMP/hits.a" | tr -d ' '); skip_a=$(cat "$TMP/skip.a")
rc_b=$(run_probe "$B" b); hits_b=$(cat "$TMP/hits.b"); n_b=$(grep -c . "$TMP/hits.b" | tr -d ' ')

# ③ 주입 문장이 실제 원천 단위 목록에 있는가 — (B) 의 적중 줄이 그 문장을 지목해야 한다.
# 적중 줄은 단위를 110자로 자르므로 앞부분으로 대조한다.
unit_head=$(printf '%s' "$UNIT_KO" | cut -c1-20)
in_units=no
printf '%s\n' "$hits_b" | grep -qF -- "$unit_head" && in_units=yes

# ── 보고 ──────────────────────────────────────────────────────────────
echo "── R-DUP 언어 축소 대조군 ──"
echo "  (B) 기점 역할정의 : $AGENT"
echo "  주입 문장(원천)   : $UNIT_KO  [${n_bytes}바이트 ≥ RDUP_MIN=$RDUP_MIN]"
echo "  주입 문장(영어)   : $UNIT_EN"
echo "  기준선            : rc=$rc_base · 언어 제외 ${skip_base}파일 (RDUP_SCAN_EXTRA 없음)"
echo "  (A) 영어 픽스처   : rc=$rc_a  R-DUP 적중 ${n_a}줄  언어 제외 ${skip_a}파일"
[[ -n "$hits_a" ]] && printf '      %s\n' "$hits_a"
echo "  (B) 한국어 사본   : rc=$rc_b  R-DUP 적중 ${n_b}줄"
[[ -n "$hits_b" ]] && printf '      %s\n' "$hits_b"
echo "  주입 문장이 원천 단위 목록에 있는가 : $in_units  ((B) 적중이 그 문장을 지목했는가)"

f=0
# (A) 의 근거는 제외 수 하나다. **적중 0줄은 단언하지 않는다** — 픽스처가 축소로 스캔에서
#   빠지므로 그 경로를 지목한 적중은 구조적으로 나올 수 없고, 단언해 두면 공허한 참이
#   근거처럼 읽힌다. 위 보고 줄에 관측값으로만 찍는다. 축소가 걸리지 않으면 그때는 제외 수
#   단언이 먼저 깨진다.
[[ "$skip_a" == "$((skip_base + 1))" ]] || { echo "✗ (A) 언어 제외가 ${skip_a}파일이다 — 기대는 기준선 ${skip_base} + 1. 축소가 그 사본에 걸리지 않았다"; f=1; }
[[ "$rc_a" -eq 0 ]]      || { echo "✗ (A) rc=$rc_a — 기대는 0"; f=1; }
[[ "$n_b" -ge 1 ]]       || { echo "✗ (B) 한국어 사본의 적중이 0줄이다 — 대조군이 공허하다 (검사가 죽었거나 주입이 임계값 미만이다)"; f=1; }
[[ "$rc_b" -eq 1 ]]      || { echo "✗ (B) rc=$rc_b — 기대는 1"; f=1; }
[[ "$in_units" == yes ]] || { echo "✗ 주입 문장이 원천 단위 목록에 없다 — 대조군이 공허하다"; f=1; }

if [[ "$f" -eq 0 ]]; then
  echo "✓ 기대대로다: 한글 없는 파일은 제외 수로 드러나며 빠지고(rc 0), 한국어 문서의 복제는 그대로 잡힌다(rc 1)"
else
  echo "✗ 기대와 다르다 — 위 수치가 산출물이다"
fi
exit "$f"
