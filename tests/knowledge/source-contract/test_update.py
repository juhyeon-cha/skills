"""Verify plan coverage, checked application, and recovery from partial writes."""

import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

import test_impact as fixtures
import update

ROOT = fixtures.ROOT


class UpdateTests(unittest.TestCase):
    git = fixtures.ImpactTests.git
    put = fixtures.ImpactTests.put
    commit = fixtures.ImpactTests.commit
    cli = fixtures.ImpactTests.cli
    capture = fixtures.ImpactTests.capture
    save = fixtures.ImpactTests.save
    call = fixtures.ImpactTests.call
    derive = fixtures.ImpactTests.derive

    def setUp(self):
        fixtures.ImpactTests.setUp(self)
        self.put('a.py', "print('changed')\n")
        (self.repo / 'src/gone.py').unlink()
        (self.repo / 'src/rename.py').rename(self.repo / 'src/moved.py')
        self.put('new.py', "print('new')\n")
        self.after = self.capture('after.json', self.commit())
        queue = self.derive(self.after)
        self.decisions = {'impact': queue['id'], 'claims': [
            {'path': 'guide.md', 'id': 'original', 'action': 'replace', 'reason': 'Source output changed.',
             'text': 'Changed claim.', 'evidence': ['src/a.py']},
            {'path': 'guide.md', 'id': 'removed', 'action': 'remove', 'reason': 'Source was removed.',
             'text': '', 'evidence': []},
            {'path': 'guide.md', 'id': 'moved', 'action': 'keep', 'reason': 'Only the source path changed.',
             'text': 'Moved claim.', 'evidence': ['src/moved.py']},
            {'path': 'other.md', 'id': 'shared', 'action': 'replace', 'reason': 'Shared source changed.',
             'text': 'Updated shared claim.', 'evidence': ['src/a.py']}
        ], 'unlinked': [{'change': c, 'action': 'no-document-change', 'reason': 'New output is outside the current guide scope.'}
                        for c in queue['unlinked_changes']]}
        self.decisions_path = self.save('decisions.json', self.decisions)
        self.plan_path = self.root / 'plan.json'
        self.command('prepare', self.decisions_path, '--out', self.plan_path)
        self.plan = json.loads(self.plan_path.read_text())

    def command(self, *args, ok=True):
        result = subprocess.run([sys.executable, str(ROOT / 'update.py'), *map(str, args),
                                 '--bindings', str(self.bindings), '--before', str(self.before),
                                 '--after', str(self.after), '--repo', str(self.repo),
                                 '--docs-root', str(self.docs)], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        return result

    def inputs(self):
        return (json.loads(self.bindings.read_text()), json.loads(self.before.read_text()),
                json.loads(self.after.read_text()))

    def test_apply_end_to_end_and_repeat(self):
        before_source = self.git('status', '--porcelain')
        os.chmod(self.docs / 'guide.md', 0o640)
        result = self.command('apply', self.plan_path)
        self.assertEqual(json.loads(result.stdout)['status'], 'applied')
        self.assertEqual((self.docs / 'guide.md').read_text(), 'Changed claim.\n\nMoved claim.\n')
        self.assertEqual((self.docs / 'other.md').read_text(), 'Updated shared claim.\n')
        self.assertEqual((self.docs / 'guide.md').stat().st_mode & 0o777, 0o640)
        self.assertEqual(before_source, self.git('status', '--porcelain'))
        self.assertEqual(result.stdout, self.command('apply', self.plan_path).stdout)
        next_path = self.save('next-bindings.json', self.plan['next_bindings'])
        self.call('impact', next_path, '--before', self.after, '--after', self.after,
                  '--out', self.root / 'next-impact.json')
        self.assertEqual(json.loads((self.root / 'next-impact.json').read_text())['candidates'], [])

    def test_stale_preflight_changes_nothing(self):
        original = (self.docs / 'guide.md').read_bytes()
        (self.docs / 'other.md').write_text('Independent later edit.\n')
        self.assertIn('STALE_DOCUMENT', self.command('apply', self.plan_path, ok=False).stderr)
        self.assertEqual((self.docs / 'guide.md').read_bytes(), original)
        self.assertEqual((self.docs / 'other.md').read_text(), 'Independent later edit.\n')

    def test_partial_failure_resumes_without_rewriting_applied_file(self):
        replace = update.replace_document
        def fail_second(root, doc, mode):
            if doc['path'] == 'other.md':
                raise OSError('injected write failure')
            replace(root, doc, mode)
        with patch.object(update, 'replace_document', side_effect=fail_second):
            with self.assertRaisesRegex(OSError, 'injected'):
                update.apply_plan(self.plan, *self.inputs(), self.docs, self.repo)
        first = self.docs / 'guide.md'
        self.assertEqual(first.read_text(), self.plan['documents'][0]['after_text'])
        self.assertEqual((self.docs / 'other.md').read_text(), 'Shared claim.\n')
        inode = first.stat().st_ino
        self.command('apply', self.plan_path)
        self.assertEqual(first.stat().st_ino, inode)
        self.assertEqual((self.docs / 'other.md').read_text(), 'Updated shared claim.\n')

    def test_partial_resume_preserves_later_independent_edit(self):
        first = self.docs / 'guide.md'
        second = self.docs / 'other.md'
        first.write_text(self.plan['documents'][0]['after_text'])
        second.write_text('Independent edit after interruption.')
        inode = first.stat().st_ino
        self.command('apply', self.plan_path, ok=False)
        self.assertEqual(first.stat().st_ino, inode)
        self.assertEqual(first.read_text(), self.plan['documents'][0]['after_text'])
        self.assertEqual(second.read_text(), 'Independent edit after interruption.')

    def test_source_mismatch_or_unavailable_commit_changes_no_document(self):
        original_docs = {p.name: p.read_bytes() for p in self.docs.iterdir()}
        original_after = json.loads(self.after.read_text())
        for i in range(2):
            damaged = copy.deepcopy(original_after)
            if i == 0:
                damaged['files'] = []
            else:
                damaged['commit'] = '0' * 40
            self.after = self.save(f'bad-source-{i}.json', damaged, True)
            self.command('apply', self.plan_path, ok=False)
            self.assertEqual(original_docs, {p.name: p.read_bytes() for p in self.docs.iterdir()})

    def test_intervening_edit_and_replace_failure_preserve_originals(self):
        original = (self.docs / 'guide.md').read_bytes()
        with patch.object(update.os, 'replace', side_effect=OSError('replacement failed')):
            with self.assertRaises(OSError):
                update.apply_plan(self.plan, *self.inputs(), self.docs, self.repo)
        self.assertEqual((self.docs / 'guide.md').read_bytes(), original)
        self.assertEqual(list(self.docs.glob('.knowledge-update-*')), [])
        replace = update.replace_document
        def edit_before_replace(root, doc, mode):
            (root / doc['path']).write_text('Concurrent edit.')
            replace(root, doc, mode)
        with patch.object(update, 'replace_document', side_effect=edit_before_replace):
            with self.assertRaisesRegex(ValueError, 'STALE_DOCUMENT'):
                update.apply_plan(self.plan, *self.inputs(), self.docs, self.repo)
        self.assertEqual((self.docs / 'guide.md').read_text(), 'Concurrent edit.')
        self.assertEqual((self.docs / 'other.md').read_text(), 'Shared claim.\n')

    def test_missing_duplicate_and_invalid_decisions_fail_before_output(self):
        for i, mutation in enumerate(('missing', 'duplicate', 'unlinked', 'empty-reason', 'evidence', 'keep', 'remove', 'defer')):
            value = copy.deepcopy(self.decisions)
            if mutation == 'missing': value['claims'].pop()
            if mutation == 'duplicate': value['claims'].append(value['claims'][0])
            if mutation == 'unlinked': value['unlinked'] = []
            if mutation == 'empty-reason': value['claims'][0]['reason'] = ' '
            if mutation == 'evidence': value['claims'][0]['evidence'] = ['src/missing.py']
            if mutation == 'keep': value['claims'][0]['action'] = 'keep'
            if mutation == 'remove': value['claims'][1]['text'] = 'not empty'
            if mutation == 'defer': value['unlinked'][0]['action'] = 'defer'
            out = self.root / f'bad-plan-{i}.json'
            self.command('prepare', self.save(f'bad-decisions-{i}.json', value), '--out', out, ok=False)
            self.assertFalse(out.exists())
        self.assertEqual((self.docs / 'guide.md').read_text(), 'Original claim.\nRemoved claim.\nMoved claim.\n')

    def test_resealed_tampering_and_symlinks_fail(self):
        tampered = copy.deepcopy(self.plan)
        tampered['documents'][0]['after_text'] = 'arbitrary replacement'
        tampered['documents'][0]['after_sha256'] = update.sha(b'arbitrary replacement')
        self.command('apply', self.save('tampered.json', tampered, True), ok=False)
        target = self.docs / 'other.md'
        target.unlink()
        target.symlink_to(self.docs / 'guide.md')
        self.command('apply', self.plan_path, ok=False)
        self.assertEqual((self.docs / 'guide.md').read_text(), 'Original claim.\nRemoved claim.\nMoved claim.\n')

    def test_plan_order_and_no_overwrite(self):
        value = copy.deepcopy(self.decisions)
        value['claims'].reverse()
        out = self.root / 'repeat-plan.json'
        self.command('prepare', self.save('reversed.json', value), '--out', out)
        self.assertEqual(self.plan_path.read_bytes(), out.read_bytes())
        original = self.plan_path.read_bytes()
        self.command('prepare', self.decisions_path, '--out', self.plan_path, ok=False)
        self.assertEqual(self.plan_path.read_bytes(), original)

    def test_ambiguous_or_overlapping_edits_fail(self):
        # Rebind changed input intentionally before asking for a fresh plan.
        for i, text in enumerate(('Original claim. Original claim.\nRemoved claim.\nMoved claim.\n',
                                  'Original claim.\nRemoved claim.\nMoved claim.\n')):
            (self.docs / 'guide.md').write_text(text)
            spec = copy.deepcopy(self.spec)
            if i == 1:
                spec['documents'][0]['claims'][1]['text'] = 'Original'
            binding = self.root / f'ambiguous-binding-{i}.json'
            self.call('bind', self.save(f'ambiguous-spec-{i}.json', spec), '--snapshot', self.before, '--out', binding)
            queue_path = self.root / f'ambiguous-impact-{i}.json'
            self.call('impact', binding, '--before', self.before, '--after', self.after, '--out', queue_path)
            value = copy.deepcopy(self.decisions)
            value['impact'] = json.loads(queue_path.read_text())['id']
            with self.assertRaisesRegex(ValueError, 'AMBIGUOUS_EDIT'):
                update.prepare(value, json.loads(binding.read_text()), *self.inputs()[1:], self.docs, self.repo)

    def test_remove_every_claim_yields_no_next_bindings(self):
        # Every original claim is affected in this fixture.
        value = copy.deepcopy(self.decisions)
        for decision in value['claims']:
            decision.update(action='remove', text='', evidence=[])
        out = self.root / 'remove-plan.json'
        self.command('prepare', self.save('remove-decisions.json', value), '--out', out)
        self.assertIsNone(json.loads(out.read_text())['next_bindings'])
        self.command('apply', out)
        self.assertEqual((self.docs / 'guide.md').read_text(), '\n\n\n')
        self.assertEqual((self.docs / 'other.md').read_text(), '\n')


if __name__ == '__main__':
    unittest.main()
