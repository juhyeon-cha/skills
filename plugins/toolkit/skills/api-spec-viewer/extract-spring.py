#!/usr/bin/env python3
"""Spring Boot 소스 트리에서 API 스냅샷 JSON 을 뽑는다.

앱을 기동하지 않는다 — .java 파일만 읽는 정적 파싱이다.
출력 스키마는 같은 폴더의 snapshot-schema.md 가 정의한다.

사용법: extract-spring.py <소스 트리 경로>

ponytail: 정규식 기반 파서다. 감당하는 범위는 이 샘플이 실제로 쓰는 형태 —
클래스 레벨 @RequestMapping 접두사 하나, 메서드 레벨 @Get/@Post/@Put/@Delete/
@PatchMapping, record 와 @Entity 클래스. 못 보는 것: 메서드 레벨
@RequestMapping(method=...), 상수로 뺀 경로, 상속으로 물려받은 매핑.
파서를 javalang 같은 의존성으로 바꾸는 것은 그 형태가 실제로 나올 때.
"""

import json
import os
import re
import sys

MAPPING = {"Get": "GET", "Post": "POST", "Put": "PUT", "Delete": "DELETE", "Patch": "PATCH"}
MODIFIERS = {
    "public", "private", "protected", "static", "final", "abstract",
    "synchronized", "native", "transient", "volatile", "default", "strictfp",
}
SKIP_DIRS = {".git", "target", "build", "node_modules", "out"}


def strip_comments(src):
    """주석만 지운다. 문자열 리터럴은 애노테이션 값이라 보존한다."""
    out = []
    i, n = 0, len(src)
    while i < n:
        ch = src[i]
        if ch in "\"'":
            out.append(ch)
            i += 1
            while i < n:
                c = src[i]
                out.append(c)
                i += 1
                if c == "\\":
                    if i < n:
                        out.append(src[i])
                        i += 1
                elif c == ch:
                    break
            continue
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            out.append(" ")
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def span(s, i, opener, closer):
    """s[i] == opener 일 때 짝 맞는 closer 의 다음 인덱스. 못 찾으면 len(s)."""
    depth = 0
    n = len(s)
    while i < n:
        ch = s[i]
        if ch in "\"'":
            i += 1
            while i < n:
                if s[i] == "\\":
                    i += 2
                    continue
                if s[i] == ch:
                    break
                i += 1
            i += 1
            continue
        if ch == opener:
            depth += 1
        elif ch == closer:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def skip_ws(s, i):
    while i < len(s) and s[i] in " \t\r\n":
        i += 1
    return i


def strip_annotations(text):
    """@Ann · @Ann(...) 를 공백으로 지운다."""
    out = []
    i, n = 0, len(text)
    while i < n:
        if text[i] == "@":
            j = i + 1
            while j < n and (text[j].isalnum() or text[j] in "_."):
                j += 1
            k = skip_ws(text, j)
            i = span(text, k, "(", ")") if k < n and text[k] == "(" else j
            out.append(" ")
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def split_top(text):
    """괄호·꺾쇠 깊이 0 의 쉼표로만 자른다."""
    parts, cur, depth = [], [], 0
    for ch in text:
        if ch in "(<[":
            depth += 1
        elif ch in ")>]":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur))
    return [p.strip() for p in parts if p.strip()]


def type_and_name(decl):
    """'public List<Pet> foo' → ('List<Pet>', 'foo'). 못 가르면 None."""
    toks = [t for t in decl.split() if t not in MODIFIERS]
    if len(toks) < 2:
        return None
    return "".join(toks[:-1]), toks[-1]


def first_string(text):
    m = re.search(r'"([^"]*)"', text)
    return m.group(1) if m else ""


def join_path(prefix, path):
    parts = [p.strip("/") for p in (prefix, path) if p and p.strip("/")]
    return "/" + "/".join(parts)


def signature_after(s, i):
    """애노테이션 뒤의 메서드 시그니처를 (반환타입, 파라미터목록) 으로."""
    n = len(s)
    while True:
        i = skip_ws(s, i)
        if i >= n:
            return None
        if s[i] != "@":
            break
        j = i + 1
        while j < n and (s[j].isalnum() or s[j] in "_."):
            j += 1
        k = skip_ws(s, j)
        i = span(s, k, "(", ")") if k < n and s[k] == "(" else j
    p = s.find("(", i)
    if p < 0:
        return None
    head = s[i:p]
    if any(c in head for c in ";{}="):
        return None
    tn = type_and_name(head)
    if tn is None:
        return None
    end = span(s, p, "(", ")")
    return tn[0], split_top(s[p + 1:end - 1])


def endpoints_of(src):
    if "@RestController" not in src and "@Controller" not in src:
        return []
    prefix = ""
    m = re.search(r"@RequestMapping\s*\(", src)
    if m:
        open_at = src.index("(", m.start())
        prefix = first_string(src[open_at:span(src, open_at, "(", ")")])
    found = []
    for m in re.finditer(r"@(Get|Post|Put|Delete|Patch)Mapping\b", src):
        i, path = m.end(), ""
        j = skip_ws(src, i)
        if j < len(src) and src[j] == "(":
            end = span(src, j, "(", ")")
            path = first_string(src[j:end])
            i = end
        sig = signature_after(src, i)
        if sig is None:
            continue
        response, params = sig
        request = None
        for p in params:
            if re.search(r"@RequestBody\b", p):
                tn = type_and_name(strip_annotations(p))
                if tn:
                    request = tn[0]
                break
        found.append({
            "method": MAPPING[m.group(1)],
            "path": join_path(prefix, path),
            "request": request,
            "response": response,
        })
    return found


def _fields_of_body(body):
    fields = []
    for fm in re.finditer(r"\b(?:private|protected|public)\s+([^;{}()=]+?)\s+(\w+)\s*(?:=[^;{}]*)?;", body):
        if "static" in fm.group(1).split():
            continue
        tn = type_and_name(fm.group(1) + " " + fm.group(2))
        if tn:
            fields.append({"name": tn[1], "type": tn[0]})
    return fields


def models_of(src):
    """record 와 @Entity 클래스를 모델로 본다."""
    out = []
    for m in re.finditer(r"\brecord\s+(\w+)\s*\(", src):
        open_at = src.index("(", m.start(1))
        end = span(src, open_at, "(", ")")
        fields = []
        for comp in split_top(strip_annotations(src[open_at + 1:end - 1])):
            tn = type_and_name(comp)
            if tn:
                fields.append({"name": tn[1], "type": tn[0]})
        out.append({"name": m.group(1), "fields": fields})
    for m in re.finditer(r"@Entity\b", src):
        cm = re.compile(r"\bclass\s+(\w+)").search(src, m.end())
        if not cm:
            continue
        brace = src.find("{", cm.end())
        if brace < 0:
            continue
        body = strip_annotations(src[brace + 1:span(src, brace, "{", "}") - 1])
        out.append({"name": cm.group(1), "fields": _fields_of_body(body)})
    return out


def enums_of(src):
    out = []
    for m in re.finditer(r"\benum\s+(\w+)\s*\{", src):
        brace = src.index("{", m.end(1))
        body = strip_annotations(src[brace + 1:span(src, brace, "{", "}") - 1])
        values = []
        for part in split_top(body.split(";")[0]):
            vm = re.match(r"\s*(\w+)", part)
            if vm:
                values.append(vm.group(1))
        out.append({"name": m.group(1), "values": values})
    return out


def uniq_sorted(items):
    seen, keyed = set(), []
    for it in items:
        k = json.dumps(it, sort_keys=True, ensure_ascii=False)
        if k not in seen:
            seen.add(k)
            keyed.append((k, it))
    keyed.sort(key=lambda p: p[0])
    return [it for _, it in keyed]


def java_files(root):
    found = []
    for d, dirs, names in os.walk(root):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
        for nm in sorted(names):
            if not nm.endswith(".java"):
                continue
            p = os.path.join(d, nm)
            if os.sep + "src" + os.sep + "test" + os.sep in p:
                continue
            found.append(p)
    return found


def main(argv):
    if len(argv) != 2:
        print("사용법: extract-spring.py <Spring Boot 소스 트리 경로>", file=sys.stderr)
        return 2
    root = argv[1]
    if not os.path.isdir(root):
        print(f"경로가 없거나 디렉토리가 아니다: {root}", file=sys.stderr)
        return 2
    files = java_files(root)
    if not files:
        print(f".java 파일이 하나도 없다: {root}", file=sys.stderr)
        return 3
    endpoints, models, enums = [], [], []
    for path in files:
        with open(path, encoding="utf-8", errors="replace") as f:
            src = strip_comments(f.read())
        endpoints += endpoints_of(src)
        models += models_of(src)
        enums += enums_of(src)
    if not endpoints:
        # 빈 결과를 성공으로 내면 "파싱이 실패했다" 와 "엔드포인트가 없다" 가 구분되지 않는다.
        print(f"엔드포인트를 하나도 찾지 못했다: {root}", file=sys.stderr)
        return 3
    json.dump(
        {
            "framework": "spring",
            "endpoints": uniq_sorted(endpoints),
            "models": uniq_sorted(models),
            "enums": uniq_sorted(enums),
        },
        sys.stdout,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    )
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
