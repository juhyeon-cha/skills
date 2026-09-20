"""Exercise contracts against real, disposable Git histories and damaged artifacts."""

import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from runtime import ROOT
from cli import identify



class ContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Contract Test")
        self.git("config", "user.email", "contract@example.invalid")
        (self.repo / "src").mkdir()
        self.put("a.py", "print('original')\n")
        self.put("gone.py", "print('removed')\n")
        self.put("rename.py", "print('stable')\n")
        self.before_commit = self.commit()

    def git(self, *args):
        result = subprocess.run(["git", "-C", str(self.repo), *args], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def put(self, name, text):
        (self.repo / "src" / name).write_text(text)

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        return self.git("rev-parse", "HEAD")

    def cli(self, *args, ok=True):
        result = subprocess.run([sys.executable, str(ROOT / "cli.py"), *map(str, args)],
                                capture_output=True, text=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def capture(self, name, rev=None, scope="src"):
        path = self.root / name
        self.cli("capture", "--repo", self.repo, "--repository", "fixture/repo",
                 "--rev", rev or self.before_commit, "--path", scope, "--out", path)
        return path

    def save(self, name, record, reseal=False):
        if reseal:
            record["id"] = identify(record)
        path = self.root / name
        path.write_text(json.dumps(record))
        return path

    def test_fixed_commit_repeat_and_no_overwrite(self):
        a = self.capture("a.json")
        self.put("a.py", "uncommitted content")
        b = self.capture("b.json")
        self.assertEqual(a.read_bytes(), b.read_bytes())
        saved = a.read_bytes()
        self.cli("capture", "--repo", self.repo, "--repository", "fixture/repo",
                 "--rev", self.before_commit, "--path", "src", "--out", a, ok=False)
        self.assertEqual(saved, a.read_bytes())
        self.cli("check", a, "--repo", self.repo)

    def test_repository_subdirectory_uses_full_tree(self):
        a = self.capture("root.json")
        b = self.root / "subdir.json"
        self.cli("capture", "--repo", self.repo / "src", "--repository", "fixture/repo",
                 "--rev", self.before_commit, "--path", "src", "--out", b)
        self.assertEqual(a.read_bytes(), b.read_bytes())
        self.cli("check", a, "--repo", self.repo / "src")

    def test_unselected_non_utf8_path_does_not_block_scope(self):
        # Build the Git tree directly: some hosts cannot create this filename on disk.
        tree = subprocess.check_output(["git", "-C", str(self.repo), "ls-tree", "-z", "HEAD"])
        blob = self.git("rev-parse", "HEAD:src/a.py").encode()
        tree += b"100644 blob " + blob + b"\toutside-\xff\x00"
        oid = subprocess.check_output(["git", "-C", str(self.repo), "mktree", "-z"], input=tree).decode().strip()
        revision = self.git("commit-tree", oid, "-p", self.before_commit, "-m", "raw path fixture")
        a = self.capture("scoped.json", revision)
        self.assertEqual(len(json.loads(a.read_text())["files"]), 3)

    def test_changes_and_recomputed_validation(self):
        a = self.capture("a.json")
        self.put("a.py", "print('changed')\n")
        (self.repo / "src/gone.py").unlink()
        (self.repo / "src/rename.py").rename(self.repo / "src/moved.py")
        self.put("new.py", "print('new')\n")
        b = self.capture("b.json", self.commit())
        out = self.root / "diff.json"
        self.cli("diff", a, b, "--out", out)
        changes = json.loads(out.read_text())["changes"]
        self.assertEqual({c['type'] for c in changes}, {"added", "removed", "modified", "rename-candidate"})
        self.cli("check", out, "--before", a, "--after", b, "--repo", self.repo)
        damaged = json.loads(out.read_text()); damaged["changes"] = []
        bad = self.save("bad.json", damaged, reseal=True)
        self.assertIn("CHANGE_MISMATCH", self.cli("check", bad, "--before", a, "--after", b, ok=False).stderr)
        self.cli("check", out, ok=False)

    def test_tampering_schema_and_source_omission(self):
        a = self.capture("a.json")
        original = json.loads(a.read_text())
        cases = []
        x = copy.deepcopy(original); x["version"] = 2; cases.append((x, False, "SCHEMA"))
        x = copy.deepcopy(original); x["files"][0]["text"] += "tamper"; cases.append((x, True, "CONTENT_HASH"))
        x = copy.deepcopy(original); x["files"].append(x["files"][0]); cases.append((x, True, "FILES"))
        for i, (record, reseal, diagnostic) in enumerate(cases):
            bad = self.save(f"bad{i}.json", record, reseal)
            self.assertIn(diagnostic, self.cli("check", bad, ok=False).stderr)
        missing = copy.deepcopy(original); missing["files"] = []
        bad = self.save("missing.json", missing, True)
        self.assertIn("NOT VERIFIED", self.cli("check", bad).stdout)
        self.assertIn("SOURCE_MISMATCH", self.cli("check", bad, "--repo", self.repo, ok=False).stderr)
        self.cli("check", a, "--repo", self.root / "absent", ok=False)

    def test_scope_mismatch_and_unchanged(self):
        a = self.capture("a.json")
        b = self.capture("b.json", scope="src/a.py")
        out = self.root / "diff.json"
        self.cli("diff", a, b, "--out", out, ok=False)
        self.assertFalse(out.exists())
        self.cli("diff", a, a, "--out", out)
        self.assertEqual(json.loads(out.read_text())["changes"], [])
        other = json.loads(a.read_text()); other["repository"] = "different"
        self.cli("diff", a, self.save("other.json", other, True), "--out", self.root / "otherdiff", ok=False)

    def test_empty_scope_result_supports_deletion(self):
        for path in (self.repo / "src").iterdir():
            path.unlink()
        b = self.capture("empty.json", self.commit())
        self.assertEqual(json.loads(b.read_text())["files"], [])
        self.cli("check", b, "--repo", self.repo)

    def test_ambiguous_rename_and_mode_change(self):
        self.put("copy.py", "print('stable')\n")
        a = self.capture("a.json", self.commit())
        (self.repo / "src/copy.py").unlink()
        (self.repo / "src/rename.py").unlink()
        self.put("new1.py", "print('stable')\n")
        self.put("new2.py", "print('stable')\n")
        os.chmod(self.repo / "src/a.py", 0o755)
        b = self.capture("b.json", self.commit())
        out = self.root / "diff.json"; self.cli("diff", a, b, "--out", out)
        changes = json.loads(out.read_text())["changes"]
        self.assertEqual(sum(c["type"] == "rename-candidate" for c in changes), 0)
        self.assertIn({"type": "modified", "before": "src/a.py", "after": "src/a.py"}, changes)

    def test_unsupported_source_and_invalid_input(self):
        for rev, scope in [("does-not-exist", "src"), ("HEAD", "../src"), ("HEAD", "/src")]:
            out = self.root / "bad.json"
            self.cli("capture", "--repo", self.repo, "--repository", "fixture/repo",
                     "--rev", rev, "--path", scope, "--out", out, ok=False)
            self.assertFalse(out.exists())
        (self.repo / "src/link").symlink_to("a.py")
        rev = self.commit()
        self.cli("capture", "--repo", self.repo, "--repository", "fixture/repo",
                 "--rev", rev, "--path", "src", "--out", self.root / "link.json", ok=False)
        bad = self.root / "invalid.json"; bad.write_text("not json")
        self.cli("check", bad, ok=False)

    def test_binary_and_non_utf8_selected_content_fail_before_output(self):
        for i, data in enumerate((b"binary\x00", b"invalid\xff")):
            (self.repo / "src/a.py").write_bytes(data)
            revision = self.commit()
            out = self.root / f"unsupported{i}.json"
            self.cli("capture", "--repo", self.repo, "--repository", "fixture/repo",
                     "--rev", revision, "--path", "src", "--out", out, ok=False)
            self.assertFalse(out.exists())


if __name__ == "__main__":
    unittest.main()
