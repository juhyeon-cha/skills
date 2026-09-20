#!/usr/bin/env python3
"""Capture and compare pinned Git text evidence; no models or remote writes."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

try:
    from jsonschema import Draft202012Validator
    from jsonschema.exceptions import ValidationError
except ImportError:
    sys.exit("DEPENDENCY_UNREACHED: install the adjacent requirements.txt in a user-owned environment")

ROOT = Path(__file__).resolve().parent


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def identify(record):
    return sha(canonical({k: v for k, v in record.items() if k != "id"}))


def git(repo, *args):
    result = subprocess.run(["git", "--no-replace-objects", "-C", str(repo), *args], capture_output=True)
    if result.returncode:
        raise ValueError("SOURCE_UNREACHED: " + result.stderr.decode(errors="replace").strip())
    return result.stdout


def valid_path(path):
    return (bool(path) and not path.startswith("/") and "\\" not in path
            and "\x00" not in path and all(p not in ("", ".", "..") for p in path.split("/")))


def validate(record):
    schema = json.loads((ROOT / "schema.json").read_text())
    Draft202012Validator(schema).validate(record)
    if record["id"] != identify(record):
        raise ValueError("RECORD_HASH: record bytes changed")
    scope = record["scope"]
    if scope != sorted(set(scope)) or not all(valid_path(p) for p in scope):
        raise ValueError("SCOPE: use unique sorted repository-relative literal paths")
    if record["kind"] == "snapshot":
        paths = [f["path"] for f in record["files"]]
        if paths != sorted(set(paths)):
            raise ValueError("FILES: duplicate or unsorted paths")
        for file in record["files"]:
            path = file["path"]
            if not valid_path(path) or not any(path == s or path.startswith(s + "/") for s in scope):
                raise ValueError("PATH: file outside declared scope")
            if sha(file["text"].encode()) != file["sha256"]:
                raise ValueError("CONTENT_HASH: " + path)


def seal(record):
    record["id"] = identify(record)
    validate(record)
    return record


def capture(repo, repository, revision, scope):
    if not repository.strip() or not scope or not all(valid_path(p) for p in scope):
        raise ValueError("INPUT: repository identity and literal relative paths are required")
    scope = sorted(set(scope))
    commit = git(repo, "rev-parse", "--verify", "--end-of-options", revision + "^{commit}").decode().strip()
    entries = git(repo, "ls-tree", "--full-tree", "-r", "-z", commit).split(b"\x00")
    raw_scope = [p.encode("utf-8") for p in scope]
    files = []
    for entry in entries:
        if not entry:
            continue
        header, raw_path = entry.split(b"\t", 1)
        if not any(raw_path == s or raw_path.startswith(s + b"/") for s in raw_scope):
            continue
        path = raw_path.decode("utf-8")
        mode, kind, oid = header.decode().split()
        if mode not in ("100644", "100755") or kind != "blob":
            raise ValueError("UNSUPPORTED_FILE: symlink or submodule: " + path)
        data = git(repo, "cat-file", "blob", oid)
        if b"\x00" in data:
            raise ValueError("UNSUPPORTED_FILE: binary: " + path)
        files.append({"path": path, "mode": mode, "sha256": sha(data), "text": data.decode("utf-8")})
    return seal({"version": 1, "kind": "snapshot", "repository": repository,
                 "commit": commit, "scope": scope, "files": sorted(files, key=lambda f: f["path"])})


def load(path, kind=None):
    record = json.loads(path.read_text(encoding="utf-8"))
    validate(record)
    if kind and record["kind"] != kind:
        raise ValueError("KIND: expected " + kind)
    return record


def compare(before, after):
    for field in ("repository", "scope"):
        if before[field] != after[field]:
            raise ValueError("INCOMPARABLE: " + field + " differs")
    old = {f["path"]: f for f in before["files"]}
    new = {f["path"]: f for f in after["files"]}
    removed, added = set(old) - set(new), set(new) - set(old)
    changes = []
    # Pair only unique byte-and-mode matches. Similarity is not identity evidence.
    for path in sorted(removed):
        signature = (old[path]["sha256"], old[path]["mode"])
        old_matches = [p for p in removed if (old[p]["sha256"], old[p]["mode"]) == signature]
        new_matches = [p for p in added if (new[p]["sha256"], new[p]["mode"]) == signature]
        if len(old_matches) == len(new_matches) == 1:
            changes.append({"type": "rename-candidate", "before": path, "after": new_matches[0]})
    paired_old = {c["before"] for c in changes}
    paired_new = {c["after"] for c in changes}
    changes += [{"type": "removed", "before": p} for p in sorted(removed - paired_old)]
    changes += [{"type": "added", "after": p} for p in sorted(added - paired_new)]
    changes += [{"type": "modified", "before": p, "after": p}
                for p in sorted(set(old) & set(new)) if old[p] != new[p]]
    return seal({"version": 1, "kind": "change", "repository": before["repository"],
                 "scope": before["scope"], "before": before["id"], "after": after["id"],
                 "changes": sorted(changes, key=lambda c: (c.get("before", ""), c.get("after", "")))})


def write_new(path, record):
    # Compute and validate before creating output; existing evidence is never overwritten.
    payload = json.dumps(record, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    with path.open("x", encoding="utf-8") as stream:
        stream.write(payload)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    cap = commands.add_parser("capture")
    cap.add_argument("--repo", type=Path, required=True)
    cap.add_argument("--repository", required=True, help="stable repository identity, not a local path")
    cap.add_argument("--rev", required=True)
    cap.add_argument("--path", action="append", required=True, help="literal file or directory scope")
    cap.add_argument("--out", type=Path, required=True)
    diff = commands.add_parser("diff")
    diff.add_argument("before", type=Path)
    diff.add_argument("after", type=Path)
    diff.add_argument("--out", type=Path, required=True)
    check = commands.add_parser("check")
    check.add_argument("record", type=Path)
    check.add_argument("--repo", type=Path)
    check.add_argument("--before", type=Path)
    check.add_argument("--after", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "capture":
            record = capture(args.repo, args.repository, args.rev, args.path)
            write_new(args.out, record)
            print("CAPTURED:", record["id"], "files=" + str(len(record["files"])))
        elif args.command == "diff":
            record = compare(load(args.before, "snapshot"), load(args.after, "snapshot"))
            write_new(args.out, record)
            print("COMPARED:", record["id"], "changes=" + str(len(record["changes"])))
        else:
            record = load(args.record)
            if record["kind"] == "snapshot":
                if args.before or args.after:
                    raise ValueError("INPUT: --before/--after apply only to changes")
                if args.repo:
                    actual = capture(args.repo, record["repository"], record["commit"], record["scope"])
                    if actual != record:
                        raise ValueError("SOURCE_MISMATCH: pinned Git tree differs")
                    print("PASS: schema, hashes and pinned Git tree")
                else:
                    print("PASS: schema and internal hashes only; Git source NOT VERIFIED")
            else:
                if not args.before or not args.after:
                    raise ValueError("INPUT: change check requires --before and --after")
                before, after = load(args.before, "snapshot"), load(args.after, "snapshot")
                if args.repo:
                    for snap in (before, after):
                        if capture(args.repo, snap["repository"], snap["commit"], snap["scope"]) != snap:
                            raise ValueError("SOURCE_MISMATCH: pinned Git tree differs")
                if compare(before, after) != record:
                    raise ValueError("CHANGE_MISMATCH: comparison differs from supplied snapshots")
                print("PASS: recomputed changes; Git source " + ("VERIFIED" if args.repo else "NOT VERIFIED"))
        return 0
    except ValidationError as error:
        print("SCHEMA: " + error.message, file=sys.stderr)
        return 1
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
