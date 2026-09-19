"""Exercise the actual CLI on valid, corrupted and missing experiment inputs."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent


class CheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "case"
        shutil.copytree(ROOT, self.root, ignore=shutil.ignore_patterns("__pycache__"))

    def run_cli(self, script, *args):
        return subprocess.run([sys.executable, str(self.root / script), *map(str, args)],
                              text=True, capture_output=True)

    def test_valid_and_negative_controls(self):
        result = self.run_cli("check.py")
        self.assertEqual(result.returncode, 0, result.stderr)
        output = Path(self.temp.name) / "run"
        prepared = self.run_cli("packets.py", output)
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        for case, expected_rc, diagnostic in (
            ("normal", 0, "NOT ESTABLISHED"),
            ("bad-identifier", 1, "IDENTIFIER"),
            ("broken-link", 1, "LINK"),
            # Structural checks deliberately cannot judge semantic defects.
            ("missing-exception", 0, "NOT ESTABLISHED"),
            ("resend", 0, "NOT ESTABLISHED"),
        ):
            with self.subTest(case=case):
                result = self.run_cli("check.py", "--documents", output / case / "documents")
                self.assertEqual(result.returncode, expected_rc, result.stderr)
                self.assertIn(diagnostic, result.stdout + result.stderr)
        normal = (output / "normal/reader-prompt.txt").read_text()
        self.assertNotIn('"required":', normal)
        self.assertNotIn('"excerpts":', normal)
        self.assertNotIn("missing-exception", normal)

    def test_refuses_overwriting_observations(self):
        output = Path(self.temp.name) / "run"
        output.mkdir()
        sentinel = output / "observation.txt"
        sentinel.write_text("actual reader return")
        result = self.run_cli("packets.py", output)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(sentinel.read_text(), "actual reader return")

    def test_missing_document_is_not_success(self):
        result = self.run_cli("check.py", "--documents", self.root / "absent")
        self.assertEqual(result.returncode, 1)
        self.assertIn("DOCUMENT_MISSING", result.stderr)

    def test_changed_evidence_is_not_success(self):
        source = self.root / "sources.json"
        data = json.loads(source.read_text())
        data["excerpts"][0]["text"] += "changed"
        source.write_text(json.dumps(data))
        result = self.run_cli("check.py")
        self.assertEqual(result.returncode, 1)
        self.assertIn("FROZEN_INPUT_CHANGED", result.stderr)
        self.assertIn("SOURCE_HASH", result.stderr)

    def test_unavailable_source_is_not_success(self):
        result = self.run_cli("check.py", "--source-repo", self.root / "absent")
        self.assertEqual(result.returncode, 1)
        self.assertIn("SOURCE_UNREACHED", result.stderr)

    def test_invalid_input_is_not_success(self):
        (self.root / "questions.json").write_text("not json")
        result = self.run_cli("check.py")
        self.assertEqual(result.returncode, 2)
        self.assertIn("INPUT_UNREACHED", result.stderr)

    def test_empty_questions_are_not_success(self):
        (self.root / "questions.json").write_text("[]")
        result = self.run_cli("check.py")
        self.assertEqual(result.returncode, 1)
        self.assertIn("QUESTIONS", result.stderr)


if __name__ == "__main__":
    unittest.main()
