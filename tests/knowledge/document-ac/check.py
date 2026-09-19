#!/usr/bin/env python3
"""Offline checks for this pinned writing experiment; never a semantic grader."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parent
DOCUMENTS = ("policy.md", "frontend.md", "planning.md", "uiux.md")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def check(documents, source_repo=None):
    errors = []
    frozen = read_json(ROOT / "frozen.json")
    for name in ("sources.json", "questions.json", "expectations.json"):
        if digest((ROOT / name).read_bytes()) != frozen["files"].get(name):
            errors.append(f"FROZEN_INPUT_CHANGED: {name}")
    sources = read_json(ROOT / "sources.json")
    questions = read_json(ROOT / "questions.json")
    expected = read_json(ROOT / "expectations.json")
    ids = [q["id"] for q in questions]
    if not ids or len(ids) != len(set(ids)):
        errors.append("QUESTIONS: empty or duplicate IDs")
    if set(ids) != {q["id"] for q in expected["criteria"]}:
        errors.append("EXPECTATIONS: question coverage differs")
    if expected["source_commit"] != sources["commit"]:
        errors.append("SOURCE_VERSION: expectations disagree")
    excerpt_ids = {e["id"] for e in sources["excerpts"]}
    for criterion in expected["criteria"]:
        if not criterion["required"] or not set(criterion["sources"]) <= excerpt_ids:
            errors.append(f"EXPECTATIONS: missing propositions/source for {criterion['id']}")
    for excerpt in sources["excerpts"]:
        if digest(excerpt["text"].encode()) != excerpt["sha256"]:
            errors.append(f"SOURCE_HASH: {excerpt['id']}")
    if source_repo is not None:
        for source in sources["files"]:
            result = subprocess.run(
                ["git", "-C", str(source_repo), "show",
                 sources["commit"] + ":" + source["path"]],
                capture_output=True, check=False,
            )
            if result.returncode:
                errors.append(f"SOURCE_UNREACHED: {source['path']}")
                continue
            if digest(result.stdout) != source["sha256"]:
                errors.append(f"SOURCE_HASH: {source['path']}")
            lines = result.stdout.decode().splitlines(keepends=True)
            for excerpt in sources["excerpts"]:
                if excerpt["path"] != source["path"]:
                    continue
                offset = excerpt["start_line"] - 1
                actual = "".join(lines[offset:offset + len(excerpt["text"].splitlines())])
                if actual != excerpt["text"]:
                    errors.append(f"SOURCE_EXCERPT: {excerpt['id']}")

    for name in DOCUMENTS:
        path = documents / name
        if not path.is_file() or not path.read_text().strip():
            errors.append(f"DOCUMENT_MISSING: {name}")
            continue
        text = path.read_text()
        # This case names the chat route. Check route literals against the pinned declaration.
        routes = re.findall(r"(?<![\w/])/api/[A-Za-z0-9_/-]+", text)
        allowed_routes = set(re.findall(r"/api/[A-Za-z0-9_/-]+", next(
            e["text"] for e in sources["excerpts"] if e["id"] == "route")))
        for route in routes:
            if route not in allowed_routes:
                errors.append(f"IDENTIFIER: {name}: {route}")
        for href in re.findall(r"\[[^\]]*\]\(([^)]+)\)", text):
            parsed = urlsplit(href)
            if parsed.scheme:
                continue  # Remote availability is not checked offline.
            target = path if not parsed.path else path.parent / unquote(parsed.path)
            if not target.is_file():
                errors.append(f"LINK: {name}: {href}")
                continue
            if parsed.fragment:
                headings = re.findall(r"^#+\s+(.+)$", target.read_text(), re.M)
                anchors = {re.sub(r"[^\w\- ]", "", h.lower()).replace(" ", "-")
                           for h in headings}
                if unquote(parsed.fragment) not in anchors:
                    errors.append(f"ANCHOR: {name}: {href}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--documents", type=Path, default=ROOT / "documents")
    parser.add_argument("--source-repo", type=Path,
                        help="also compare excerpts with the pinned local Git object")
    args = parser.parse_args()
    try:
        errors = check(args.documents.resolve(), args.source_repo)
    except (OSError, ValueError, KeyError, TypeError, StopIteration) as error:
        print(f"INPUT_UNREACHED: {error}", file=sys.stderr)
        return 2
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("PASS: frozen evidence, question coverage, local links, chat-route literals")
    print("NOT ESTABLISHED: semantic correctness, reader answers, remote links, live behavior")
    return 0


if __name__ == "__main__":
    sys.exit(main())
