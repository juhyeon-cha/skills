#!/usr/bin/env bash
# 두 추출기를 고정 커밋 샘플에 돌려 같은 스냅샷 스키마를 만족하는지 단언한다.
#
#   check.sh              전체 자기검사 (샘플 확보 → 추출 → 단언 → 부정 대조군)
#   check.sh <파일.json>  그 스냅샷 하나에 스키마 단언만 (부정 대조군이 이 모드를 쓴다)
#
# 스키마는 같은 폴더의 snapshot-schema.md 가 정의한다.

set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

# 사용자 확정 샘플 (2026-08-29). 커밋을 고정해야 판정이 재현된다.
SPRING_URL=https://github.com/spring-petclinic/spring-petclinic-microservices
SPRING_SHA=3858f9c630cf989bb6809a86edf47c2be78dc9f1
FASTAPI_URL=https://github.com/fastapi/full-stack-fastapi-template
FASTAPI_SHA=486f054cc8d1aead59ec96cc0a16933d06c10e0d

# 스키마 단언. 빈 집합은 통과가 아니다 — endpoints·models 는 1건 이상을 요구한다.
assert_schema() {
  local f=$1
  if [ ! -f "$f" ]; then
    echo "스냅샷 파일이 없다: $f" >&2
    return 1
  fi
  jq -e '
    (.framework | type == "string")
    and (.endpoints | type == "array") and (.endpoints | length > 0)
    and (.endpoints | map(has("method") and has("path") and has("request") and has("response")) | all)
    and (.models | type == "array") and (.models | length > 0)
    and (.models | map(has("name") and has("fields")) | all)
    and (.enums | type == "array")
    and (.enums | map(has("name") and has("values")) | all)
  ' "$f" > /dev/null
}

if [ $# -gt 0 ]; then
  assert_schema "$1"
  exit $?
fi

command -v jq > /dev/null || { echo "jq 가 없다" >&2; exit 1; }
command -v git > /dev/null || { echo "git 이 없다" >&2; exit 1; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# 샘플은 캐시에 고정 커밋으로 받아둔다. 이미 그 커밋이면 네트워크를 쓰지 않는다.
CACHE=${API_SPEC_SAMPLE_CACHE:-${TMPDIR:-/tmp}/api-spec-viewer-samples}
fetch_sample() { # 이름 URL SHA — 성공하면 경로를 stdout 으로
  local d=$CACHE/$1
  if [ "$(git -C "$d" rev-parse HEAD 2> /dev/null)" = "$3" ]; then
    echo "$d"
    return 0
  fi
  mkdir -p "$d" || return 1
  git -C "$d" init -q || return 1
  git -C "$d" remote add origin "$2" 2> /dev/null || git -C "$d" remote set-url origin "$2" || return 1
  git -C "$d" fetch -q --depth 1 origin "$3" || return 1
  git -C "$d" checkout -q FETCH_HEAD || return 1
  echo "$d"
}

checked=0
run_one() { # 이름 추출기 URL SHA
  local name=$1 script=$2 dir out=$TMP/$1.json
  dir=$(fetch_sample "$1" "$3" "$4") || { echo "$name: 샘플 $4 확보 실패 ($3)" >&2; return 1; }
  python3 "$HERE/$script" "$dir" > "$out" || { echo "$name: 추출 실패" >&2; return 1; }
  assert_schema "$out" || { echo "$name: 스키마 단언 실패 — $out" >&2; return 1; }
  echo "$name: 엔드포인트 $(jq '.endpoints | length' "$out")개 · 모델 $(jq '.models | length' "$out")개 · enum $(jq '.enums | length' "$out")개 — 스키마 단언 통과"
  checked=$((checked + 1))
}

rc=0
run_one spring extract-spring.py "$SPRING_URL" "$SPRING_SHA" || rc=1
run_one fastapi extract-fastapi.py "$FASTAPI_URL" "$FASTAPI_SHA" || rc=1

# 판정 도달 단언 — 한쪽을 건너뛰고 종료 코드 0 이 나오는 경우를 막는다.
if [ "$checked" -ne 2 ]; then
  echo "추출기 2종 중 $checked 종만 검사됐다" >&2
  exit 1
fi

# 부정 대조군 — 단언이 죽으면 통과해 버리는지 본다.
negative() { # 설명 파일
  if bash "$0" "$2" > /dev/null 2>&1; then
    echo "부정 대조군이 통과했다(실패해야 한다): $1" >&2
    return 1
  fi
  echo "부정 대조군 확인: $1"
}

orig=$TMP/spring.json
broken=$TMP/broken.json
empty=$TMP/empty.json
jq 'del(.endpoints[0].response)' "$orig" > "$broken" || rc=1
jq '.endpoints = []' "$orig" > "$empty" || rc=1
if [ -s "$orig" ] && [ -s "$broken" ] && ! cmp -s "$orig" "$broken"; then
  negative "스키마 키를 하나 뺀 사본" "$broken" || rc=1
else
  echo "부정 대조군 사본이 원본과 같거나 비어 있다" >&2
  rc=1
fi
negative "엔드포인트가 빈 스냅샷" "$empty" || rc=1
negative "없는 입력 파일" "$TMP/없는파일.json" || rc=1

exit $rc
