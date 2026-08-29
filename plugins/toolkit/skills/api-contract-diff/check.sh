#!/usr/bin/env bash
# render-diff.py 가 두 스냅샷의 차이를 실제로 집어내는지, 실패해야 할 입력에서
# 실패하는지 단언한다. 입력은 이 스크립트가 만드는 합성 스냅샷이라 네트워크가 필요 없다.
#
#   check.sh
#
# 스냅샷 스키마는 ../api-spec-viewer/snapshot-schema.md 가 정의한다.

set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq > /dev/null || { echo "jq 가 없다" >&2; exit 1; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
rc=0

cat > "$TMP/before.json" << 'JSON'
{
  "framework": "spring",
  "endpoints": [
    { "method": "GET", "path": "/owners/{id}", "request": null, "response": "Owner" },
    { "method": "DELETE", "path": "/owners/{id}", "request": null, "response": "void" },
    { "method": "POST", "path": "/owners", "request": "OwnerRequest", "response": "Owner" }
  ],
  "models": [
    { "name": "Owner", "fields": [
      { "name": "id", "type": "Long" },
      { "name": "nickname", "type": "String" },
      { "name": "telephone", "type": "String" }
    ] },
    { "name": "OwnerRequest", "fields": [ { "name": "telephone", "type": "String" } ] }
  ],
  "enums": []
}
JSON

# 이후 스냅샷 — before 와 다음이 다르다:
#   엔드포인트 삭제 1 (DELETE /owners/{id}) · 추가 1 (GET /owners)
#   Owner 필드 추가 1 (email) · 삭제 1 (nickname) · 타입 변경 1 (telephone)
cat > "$TMP/after.json" << 'JSON'
{
  "framework": "spring",
  "endpoints": [
    { "method": "GET", "path": "/owners/{id}", "request": null, "response": "Owner" },
    { "method": "GET", "path": "/owners", "request": null, "response": "List<Owner>" },
    { "method": "POST", "path": "/owners", "request": "OwnerRequest", "response": "Owner" }
  ],
  "models": [
    { "name": "Owner", "fields": [
      { "name": "id", "type": "Long" },
      { "name": "email", "type": "String" },
      { "name": "telephone", "type": "Phone" }
    ] },
    { "name": "OwnerRequest", "fields": [ { "name": "telephone", "type": "Phone" } ] },
    { "name": "Phone", "fields": [ { "name": "number", "type": "String" } ] }
  ],
  "enums": []
}
JSON

cat > "$TMP/fastapi.json" << 'JSON'
{
  "framework": "fastapi",
  "endpoints": [ { "method": "GET", "path": "/items", "request": null, "response": "Item" } ],
  "models": [ { "name": "Item", "fields": [ { "name": "id", "type": "int" } ] } ],
  "enums": []
}
JSON

jq '{framework, endpoints}' "$TMP/before.json" > "$TMP/otherkeys.json"

out=$TMP/diff.html
python3 "$HERE/render-diff.py" "$TMP/before.json" "$TMP/after.json" > "$out" || {
  echo "두 스냅샷 render 실패" >&2; exit 1
}
[ -s "$out" ] || { echo "산출 HTML 이 비었다" >&2; exit 1; }

# 자체 포함 단언 — 외부 리소스를 참조하면 그 호스트가 죽을 때 화면이 죽는다.
ext=$(grep -cE '(src|href)="https?://' "$out")
[ "$ext" -eq 0 ] || { echo "산출 HTML 이 외부 리소스를 $ext 건 참조한다" >&2; rc=1; }

# 화면에 심긴 diff 를 꺼내 집계를 단언한다. 0건 통과를 막으려고 각 항목을 수로 못박는다.
payload=$(python3 - "$out" << 'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
raw = re.findall(r'<script id="diff" type="application/json">(.*?)</script>', src, re.S)[0]
sys.stdout.write(raw.replace("\\u003c", "<"))
PY
)
assert_count() { # 설명 jq식 기대값
  local got
  got=$(printf '%s' "$payload" | jq -r "$2")
  if [ "$got" != "$3" ]; then
    echo "$1: $3 이어야 하는데 $got" >&2
    return 1
  fi
  echo "확인: $1 = $got"
}
assert_count "엔드포인트 추가" '.endpoints.added | length' 1 || rc=1
assert_count "엔드포인트 삭제" '.endpoints.removed | length' 1 || rc=1
assert_count "Owner 필드 추가" '.models.changed[] | select(.name=="Owner") | .added | length' 1 || rc=1
assert_count "Owner 필드 삭제" '.models.changed[] | select(.name=="Owner") | .removed | length' 1 || rc=1
assert_count "Owner 필드 타입 변경" '.models.changed[] | select(.name=="Owner") | .retyped | length' 1 || rc=1
assert_count "삭제된 엔드포인트 경로" '.endpoints.removed[0].path' "/owners/{id}" || rc=1
# 영향 전파 — Phone 은 OwnerRequest.telephone 을 거쳐 POST /owners 에도 닿는다.
assert_count "추가된 Phone 모델의 영향 엔드포인트" '.models.added[] | select(.name=="Phone") | .affected | length' 3 || rc=1
assert_count "변경 없음 플래그" '.empty' false || rc=1

# 색 구분 자체는 브라우저에서만 확인된다. 여기서 보는 것은 그 앞 두 가지 —
# 추가·삭제에 다른 클래스가 붙는가, 그 클래스가 다른 색으로 정의돼 있는가.
for token in 'class="row ' 'class="badge ' '.card.add' '.card.del' '.row.add' '.row.del'; do
  grep -qF -- "$token" "$out" || { echo "추가·삭제 구분에 쓰는 것이 없다: $token" >&2; rc=1; }
done
addc=$(grep -oE -- '--add: #[0-9a-f]{6}' "$out" | head -1)
delc=$(grep -oE -- '--del: #[0-9a-f]{6}' "$out" | head -1)
if [ -n "$addc" ] && [ -n "$delc" ] && [ "${addc#*: }" != "${delc#*: }" ]; then
  echo "확인: 추가 ${addc#*: } · 삭제 ${delc#*: } — 서로 다른 색"
else
  echo "추가·삭제 색이 같거나 없다: '$addc' '$delc'" >&2; rc=1
fi

# 변경 없음 — 빈 diff 는 오류가 아니다.
same=$TMP/same.html
if python3 "$HERE/render-diff.py" "$TMP/before.json" "$TMP/before.json" > "$same"; then
  if grep -q "변경 없음" "$same"; then
    echo "확인: 같은 스냅샷 두 번 → rc=0 이고 '변경 없음' 이 찍힌다"
  else
    echo "같은 스냅샷인데 '변경 없음' 이 없다" >&2; rc=1
  fi
else
  echo "같은 스냅샷 두 번인데 rc≠0" >&2; rc=1
fi

# 부정 대조군 — 실패해야 할 입력이 실제로 실패하는지.
negative() { # 설명 인자...
  local what=$1; shift
  if python3 "$HERE/render-diff.py" "$@" > /dev/null 2>&1; then
    echo "부정 대조군이 통과했다(실패해야 한다): $what" >&2
    return 1
  fi
  echo "부정 대조군 확인: $what"
}
negative "두 번째 인자가 없는 경로" "$TMP/before.json" "$TMP/없는파일.json" || rc=1
negative "첫 번째 인자가 없는 경로" "$TMP/없는파일.json" "$TMP/after.json" || rc=1
negative "키 구성이 다른 스냅샷" "$TMP/before.json" "$TMP/otherkeys.json" || rc=1
negative "프레임워크가 다른 두 스냅샷" "$TMP/before.json" "$TMP/fastapi.json" || rc=1
negative "인자가 하나뿐" "$TMP/before.json" || rc=1

# 없는 경로가 stderr 에 실제로 찍히는지 — 종료 코드만으로는 어느 파일인지 알 수 없다.
# 파이프로 받지 않는다: pipefail 이 render-diff.py 의 rc=1 을 파이프라인 실패로 읽는다.
msg=$(python3 "$HERE/render-diff.py" "$TMP/before.json" "$TMP/없는파일.json" 2>&1 > /dev/null)
case "$msg" in
  *없는파일.json*) echo "확인: 없는 경로가 stderr 에 찍힌다" ;;
  *) echo "없는 경로가 stderr 에 안 찍힌다 — stderr: $msg" >&2; rc=1 ;;
esac

exit $rc
