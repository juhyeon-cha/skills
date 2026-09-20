"""Coordinator regression tests; synthetic receipts are not live observations."""
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import runner


class MeasurementTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='measurement test ')
        self.addCleanup(self.temp.cleanup)
        self.run = Path(self.temp.name) / 'run'

    def prepare(self, case='document-ac'):
        runner.prepare(runner.ROOT, self.run, case)

    def receipt(self, packet, response='fixture response', actor=None, **changes):
        result = dict(task=packet['id'], prompt_sha256=packet['prompt_sha256'],
                      actor=actor or '/root/test_' + packet['id'],
                      actual_prompt=packet['prompt'], origin='host-agent-tool',
                      outcome='completed', response=response)
        result['dispatch'] = {'task_name': result['actor']}
        result.update(changes)
        path = Path(self.temp.name) / (runner.uuid.uuid4().hex + '.json')
        runner.write(path, result)
        return path

    def deliver(self, response, **kwargs):
        task = runner.next_action(self.run)
        return runner.accept(self.run, self.receipt(task, response, **kwargs))

    def test_documents_and_pending_reentry(self):
        self.prepare()
        first = runner.next_action(self.run)
        self.assertEqual(first['id'], runner.next_action(self.run)['id'])
        self.assertNotIn('expectations.json', first['prompt'])
        self.deliver('normal fixture')
        self.deliver('variant fixture')
        task = runner.next_action(self.run)
        self.assertIn('normal fixture', task['prompt'])
        verdict = {k: 'pass' for k in ['CUR-1', 'CUR-2', 'TGT-1', 'TGT-2', 'WRD-1']}
        result = self.deliver(json.dumps(dict(normal=verdict, variant={**verdict, 'CUR-2':'fail', 'TGT-2':'fail', 'WRD-1':'not-executed'}, rationale='Synthetic test only.')))
        self.assertEqual(result['status'], 'pass')
        self.assertEqual(result['host_plugin_loading'], 'not-executed')
        self.assertEqual(len(result['history']), 3)

    def test_mismatched_judgment_fails(self):
        self.prepare()
        self.deliver('normal'); self.deliver('variant')
        self.assertEqual(self.deliver('{"normal":{},"variant":{},"rationale":"Wrong verdicts"}')['status'], 'fail')

    def test_blocked_is_not_success(self):
        self.prepare()
        result = self.deliver('GUARD-DENY: child role is unidentified', outcome='not-executed')
        self.assertEqual(result['status'], 'not-executed')
        self.assertEqual(runner.next_action(self.run)['status'], 'not-executed')

    def test_stale_fabricated_and_reused_receipts_rejected(self):
        self.prepare()
        task = runner.next_action(self.run)
        for changes in [dict(task='stale'), dict(actual_prompt='changed'), dict(actor='/root', dispatch={'task_name':'/root'}), dict(origin='replay')]:
            with self.assertRaises(ValueError):
                runner.accept(self.run, self.receipt(task, **changes))
        self.deliver('first', actor='/root/used')
        with self.assertRaisesRegex(ValueError, 'INDEPENDENCE'):
            self.deliver('second', actor='/root/used')

    def test_frozen_and_manifest_tampering(self):
        self.prepare()
        manifest = self.run / 'manifest.json'
        original = manifest.read_bytes()
        manifest.write_bytes(original + b' ')
        with self.assertRaisesRegex(ValueError, 'MANIFEST_CHANGED'):
            runner.next_action(self.run)
        manifest.write_bytes(original)
        (self.run / 'frozen/runner.py').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'SOURCE_CHANGED'):
            runner.next_action(self.run)

    def test_task_and_receipt_tampering(self):
        self.prepare()
        task = runner.next_action(self.run)
        path = Path(task['task_file']); original = path.read_bytes()
        path.write_bytes(original + b' ')
        with self.assertRaisesRegex(ValueError, 'TASK_CHANGED'):
            runner.next_action(self.run)
        path.write_bytes(original)
        result = self.deliver('first')
        (self.run / result['history'][0]['receipt']).write_text('{}')
        with self.assertRaisesRegex(ValueError, 'RECEIPT_CHANGED'):
            runner.next_action(self.run)

    def test_duplicate_directory_and_concurrent_coordinator(self):
        self.prepare()
        with self.assertRaises(FileExistsError):
            self.prepare()
        with runner.state(self.run):
            with self.assertRaises(sqlite3.OperationalError):
                runner.next_action(self.run)

    def test_missing_prerequisite_leaves_no_output(self):
        with patch.object(runner.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'doctor')):
            with self.assertRaises(subprocess.CalledProcessError):
                self.prepare()
        self.assertFalse(self.run.exists())

    def test_failed_command_retains_output(self):
        self.prepare()
        with self.assertRaisesRegex(ValueError, 'COMMAND_FAILED'):
            runner.command(self.run, sys.executable, '-c', 'print("failure evidence"); raise SystemExit(7)')
        results = list((self.run / 'commands').glob('*-result.json'))
        self.assertEqual(len(results), 1)
        self.assertEqual(runner.read(results[0])['rc'], 7)
        self.assertEqual(runner.read(results[0])['stdout'], 'failure evidence\n')

    def test_workflow_reentry_after_applied_side_effect(self):
        self.prepare('workflow')
        fixture = runner.ROOT / 'tests/knowledge/foundation-observation'
        self.deliver((fixture / 'review-bad.json').read_text())
        decisions = runner.read(fixture / 'packet-fixed.json')['plan']['decisions']
        self.deliver(json.dumps(decisions))
        result = self.deliver((fixture / 'review-fixed.json').read_text())
        self.assertEqual(result['step'], 'apply-b')
        finish = runner.finish_workflow
        def interrupted(run, value):
            finish(run, value)
            raise RuntimeError('coordinator exits after plugin commit')
        with patch.object(runner, 'finish_workflow', interrupted):
            with self.assertRaises(RuntimeError):
                runner.next_action(self.run)
        # SQLite coordinator transaction rolled back; plugin changes survive.
        task = runner.next_action(self.run)
        self.assertEqual(task['role'], 'author')
        decisions = runner.read(fixture / 'packet-c.json')['plan']['decisions']
        self.deliver(json.dumps(decisions))
        self.deliver((fixture / 'review-c.json').read_text())
        result = runner.next_action(self.run)
        self.assertEqual(result['status'], 'pass')
        self.assertEqual((self.run / 'docs/guide.md').read_text(), (fixture / 'document-c.md').read_text())
        logs = [runner.read(p) for p in (self.run / 'commands').glob('*-result.json')]
        self.assertIn(91, [log['rc'] for log in logs])


if __name__ == '__main__':
    unittest.main()
