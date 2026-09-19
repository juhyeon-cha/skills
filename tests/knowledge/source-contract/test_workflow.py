"""Check the exact packet/review boundary and completion recovery."""

import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import test_update as fixtures
import workflow

ROOT = Path(__file__).resolve().parent


class WorkflowTests(unittest.TestCase):
    git = fixtures.UpdateTests.git
    put = fixtures.UpdateTests.put
    commit = fixtures.UpdateTests.commit
    cli = fixtures.UpdateTests.cli
    capture = fixtures.UpdateTests.capture
    save = fixtures.UpdateTests.save
    call = fixtures.UpdateTests.call
    derive = fixtures.UpdateTests.derive
    command = fixtures.UpdateTests.command

    def setUp(self):
        fixtures.UpdateTests.setUp(self)
        self.packet_path = self.root / 'packet.json'
        self.run_workflow('packet', '--plan', self.plan_path, '--bindings', self.bindings,
                          '--before', self.before, '--after', self.after,
                          '--audience', 'BE developer', '--purpose', 'Choose retry behavior',
                          '--out', self.packet_path)
        self.packet = json.loads(self.packet_path.read_text())
        self.review = {'packet': self.packet['id'], 'plan': self.plan['id'], 'verdict': 'pass',
                       'checks': {k: 'pass' for k in ['source_fidelity', 'decision_coverage',
                                                    'reader_action', 'uncertainty']}, 'findings': []}
        self.review_path = self.save('review.json', self.review)
        self.receipt = self.root / 'complete.json'

    def run_workflow(self, *args, ok=True):
        result = subprocess.run([sys.executable, str(ROOT / 'workflow.py'), *map(str, args),
                                 '--repo', str(self.repo)], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        return result

    def finish(self, review=None, packet=None, ok=True):
        return self.run_workflow('finish', '--packet', packet or self.packet_path,
                                 '--review', review or self.review_path, '--docs-root', self.docs,
                                 '--out', self.receipt, ok=ok)

    def test_pass_and_repeat_preserve_receipt_and_advance_bindings(self):
        self.finish()
        receipt = json.loads(self.receipt.read_text())
        self.assertEqual(receipt['next_bindings'], self.plan['next_bindings'])
        inode = self.receipt.stat().st_ino
        self.finish()
        self.assertEqual(inode, self.receipt.stat().st_ino)
        (self.docs / 'other.md').write_text('Subsequent independent edit.')
        self.finish(ok=False)
        self.assertEqual((self.docs / 'other.md').read_text(), 'Subsequent independent edit.')
        self.assertEqual(receipt, json.loads(self.receipt.read_text()))

    def test_review_missing_stale_negative_or_incomplete_blocks_writes(self):
        original = {p.name: p.read_bytes() for p in self.docs.iterdir()}
        self.finish(review=self.root / 'missing-review.json', ok=False)
        for i, variant in enumerate(('packet', 'plan', 'revise', 'check', 'findings', 'missing-check')):
            value = copy.deepcopy(self.review)
            if variant in ('packet', 'plan'): value[variant] = '0' * 64
            if variant == 'revise': value['verdict'] = 'revise'
            if variant == 'check': value['checks']['source_fidelity'] = 'unverified'
            if variant == 'findings': value['findings'] = ['guide.md: incorrect claim']
            if variant == 'missing-check': del value['checks']['reader_action']
            self.finish(review=self.save(f'bad-review-{i}.json', value), ok=False)
            self.assertEqual(original, {p.name: p.read_bytes() for p in self.docs.iterdir()})
            self.assertFalse(self.receipt.exists())

    def test_changed_packet_requires_new_review_and_invalid_plan_is_recomputed(self):
        changed = copy.deepcopy(self.packet)
        changed['audience'] = 'A different reader'
        self.finish(packet=self.save('changed-packet.json', changed, True), ok=False)
        changed = copy.deepcopy(self.packet)
        changed['plan']['documents'][0]['after_text'] = 'unsupported'
        changed['plan']['id'] = workflow.identify(changed['plan'])
        changed['id'] = workflow.identify(changed)
        review = {**self.review, 'packet': changed['id'], 'plan': changed['plan']['id']}
        self.finish(packet=self.save('corrupted-packet.json', changed),
                    review=self.save('for-corrupted.json', review), ok=False)
        self.assertFalse(self.receipt.exists())
        self.assertEqual((self.docs / 'other.md').read_text(), 'Shared claim.\n')

    def test_output_conflict_is_checked_before_documents_change(self):
        self.receipt.write_text('{}')
        self.finish(ok=False)
        self.assertEqual(self.receipt.read_text(), '{}')
        self.assertEqual((self.docs / 'other.md').read_text(), 'Shared claim.\n')

    def test_receipt_write_failure_can_resume_completed_documents(self):
        with patch.object(workflow, 'write_new', side_effect=OSError('receipt storage failed')):
            with self.assertRaisesRegex(OSError, 'receipt storage failed'):
                workflow.finish(self.packet, self.review, self.repo, self.docs, self.receipt)
        self.assertFalse(self.receipt.exists())
        first = self.docs / 'guide.md'
        self.assertEqual(first.read_text(), self.plan['documents'][0]['after_text'])
        inode = first.stat().st_ino
        self.finish()
        self.assertEqual(first.stat().st_ino, inode)
        self.assertEqual(json.loads(self.receipt.read_text())['status'], 'applied')


class RecordedWorkflowTests(unittest.TestCase):
    def test_observed_agent_decisions_review_and_completion_replay(self):
        observed = ROOT.parent / 'workflow-observation'
        read = lambda name: json.loads((observed / name).read_text(encoding='utf-8'))
        packet, decisions, review = read('packet.json'), read('decisions.json'), read('review.json')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo, docs = root / 'source', root / 'docs'
            repo.mkdir(); docs.mkdir()
            subprocess.run(['git', '-C', str(repo), 'init', '-q'], check=True, capture_output=True)
            subprocess.run(['git', '-C', str(repo), 'fast-import', '--quiet'],
                           input=(observed / 'source-history.fi').read_bytes(), check=True, capture_output=True)
            for doc in packet['plan']['documents']:
                path = docs / doc['path']
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(doc['before_text'].encode())
            # The actual author's response reconstructs the exact reviewed plan.
            plan = fixtures.update.prepare(decisions, packet['bindings'], packet['before'],
                                           packet['after'], docs, repo)
            self.assertEqual(plan, packet['plan'])
            receipt = workflow.finish(packet, review, repo, docs, root / 'complete.json')
            self.assertEqual(receipt, read('complete.json'))
            for doc in packet['plan']['documents']:
                self.assertEqual((docs / doc['path']).read_bytes(), doc['after_text'].encode())
            again = workflow.finish(packet, review, repo, docs, root / 'complete.json')
            self.assertEqual(receipt, again)


if __name__ == '__main__':
    unittest.main()
