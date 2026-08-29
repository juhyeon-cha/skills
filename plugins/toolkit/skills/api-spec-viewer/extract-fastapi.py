#!/usr/bin/env python3
"""FastAPI 소스 트리에서 API 스냅샷 JSON 을 뽑는다.

앱을 기동하지 않는다 — /openapi.json 을 받지 않고 .py 파일만 ast 로 읽는다.
출력 스키마는 같은 폴더의 snapshot-schema.md 가 정의한다.

사용법: extract-fastapi.py <소스 트리 경로>

ponytail: 경로 접두사는 그 파일 안의 APIRouter(prefix=...) 리터럴까지만 본다.
include_router(..., prefix=settings.API_V1_STR) 처럼 다른 파일의 상수로 붙는
접두사는 따라가지 않는다 — 상수 해석을 넣는 것은 그 접두사가 실제로 필요해질 때.
"""

import ast
import json
import os
import sys

METHODS = {"get", "post", "put", "patch", "delete", "head", "options", "trace"}
MODEL_ROOTS = {"BaseModel", "SQLModel"}
ENUM_ROOTS = {"Enum", "IntEnum", "StrEnum", "IntFlag", "Flag"}
SKIP_DIRS = {".git", ".venv", "venv", "node_modules", "__pycache__", "tests", "test"}


def base_name(node):
    """상속 표현에서 이름만 뽑는다. Name·Attribute 만 본다."""
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return None


def join_path(prefix, path):
    parts = [p.strip("/") for p in (prefix, path) if p and p.strip("/")]
    return "/" + "/".join(parts)


def classes_of(tree):
    """(이름, 상속목록, 노드) 를 모듈 어디에 있든 모아온다."""
    return [
        (n.name, [b for b in (base_name(x) for x in n.bases) if b], n)
        for n in ast.walk(tree)
        if isinstance(n, ast.ClassDef)
    ]


def fields_of(node):
    fields = []
    for stmt in node.body:
        if isinstance(stmt, ast.AnnAssign) and isinstance(stmt.target, ast.Name):
            fields.append({"name": stmt.target.id, "type": ast.unparse(stmt.annotation)})
    return fields


def routers_of(tree):
    """라우터 변수 이름 → 접두사. APIRouter(prefix=...) 와 FastAPI() 를 본다."""
    routers = {}
    for stmt in ast.walk(tree):
        if not isinstance(stmt, ast.Assign) or not isinstance(stmt.value, ast.Call):
            continue
        fn = base_name(stmt.value.func)
        if fn not in ("APIRouter", "FastAPI"):
            continue
        prefix = ""
        for kw in stmt.value.keywords:
            if kw.arg == "prefix" and isinstance(kw.value, ast.Constant) and isinstance(kw.value.value, str):
                prefix = kw.value.value
        for target in stmt.targets:
            if isinstance(target, ast.Name):
                routers[target.id] = prefix
    return routers


def endpoints_of(tree, routers, model_names):
    found = []
    for fn in ast.walk(tree):
        if not isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        for dec in fn.decorator_list:
            if not isinstance(dec, ast.Call) or not isinstance(dec.func, ast.Attribute):
                continue
            if dec.func.attr not in METHODS or not isinstance(dec.func.value, ast.Name):
                continue
            var = dec.func.value.id
            if var not in routers:
                continue
            path = ""
            if dec.args and isinstance(dec.args[0], ast.Constant) and isinstance(dec.args[0].value, str):
                path = dec.args[0].value
            response = None
            for kw in dec.keywords:
                if kw.arg == "response_model":
                    response = ast.unparse(kw.value)
            if response is None and fn.returns is not None:
                response = ast.unparse(fn.returns)
            request = None
            for arg in list(fn.args.args) + list(fn.args.kwonlyargs):
                ann = arg.annotation
                if isinstance(ann, ast.Name) and ann.id in model_names:
                    request = ann.id
                    break
            found.append({
                "method": dec.func.attr.upper(),
                "path": join_path(routers[var], path),
                "request": request,
                "response": response,
            })
    return found


def uniq_sorted(items):
    seen, keyed = set(), []
    for it in items:
        k = json.dumps(it, sort_keys=True, ensure_ascii=False)
        if k not in seen:
            seen.add(k)
            keyed.append((k, it))
    keyed.sort(key=lambda p: p[0])
    return [it for _, it in keyed]


def python_files(root):
    found = []
    for d, dirs, names in os.walk(root):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
        for nm in sorted(names):
            if nm.endswith(".py"):
                found.append(os.path.join(d, nm))
    return found


def main(argv):
    if len(argv) != 2:
        print("사용법: extract-fastapi.py <FastAPI 소스 트리 경로>", file=sys.stderr)
        return 2
    root = argv[1]
    if not os.path.isdir(root):
        print(f"경로가 없거나 디렉토리가 아니다: {root}", file=sys.stderr)
        return 2
    files = python_files(root)
    if not files:
        print(f".py 파일이 하나도 없다: {root}", file=sys.stderr)
        return 3

    trees = []
    for path in files:
        with open(path, encoding="utf-8", errors="replace") as f:
            try:
                trees.append(ast.parse(f.read(), filename=path))
            except SyntaxError:
                continue  # 이 트리가 쓰는 문법이 아닌 파일은 건너뛴다

    # 모델 이름 집합을 먼저 확정한다 — 상속으로 이어진 모델까지 고정점까지 넓힌다.
    declared = [c for t in trees for c in classes_of(t)]
    model_names = {n for n, bases, _ in declared if MODEL_ROOTS & set(bases)}
    while True:
        grown = {n for n, bases, _ in declared if model_names & set(bases)} | model_names
        if grown == model_names:
            break
        model_names = grown

    models = [
        {"name": n, "fields": fields_of(node)}
        for n, _, node in declared
        if n in model_names
    ]
    enums = [
        {"name": n, "values": [
            t.id for stmt in node.body if isinstance(stmt, ast.Assign)
            for t in stmt.targets if isinstance(t, ast.Name)
        ]}
        for n, bases, node in declared
        if ENUM_ROOTS & set(bases)
    ]
    endpoints = []
    for tree in trees:
        routers = routers_of(tree)
        if routers:
            endpoints += endpoints_of(tree, routers, model_names)

    if not endpoints:
        # 빈 결과를 성공으로 내면 "파싱이 실패했다" 와 "엔드포인트가 없다" 가 구분되지 않는다.
        print(f"엔드포인트를 하나도 찾지 못했다: {root}", file=sys.stderr)
        return 3
    json.dump(
        {
            "framework": "fastapi",
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
