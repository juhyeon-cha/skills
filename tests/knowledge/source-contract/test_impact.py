"""Test evidence linkage using real Git changes and stale document artifacts."""

import copy
import json
import subprocess
import sys
import unittest

import test_cli as source_tests

ROOT = source_tests.ROOT


class ImpactTests(unittest.TestCase):
    git = source_tests.ContractTests.git
    put = source_tests.ContractTests.put
    commit = source_tests.ContractTests.commit
    cli = source_tests.ContractTests.cli
    capture = source_tests.ContractTests.capture
    save = source_tests.ContractTests.save

    def setUp(self):
        source_tests.ContractTests.setUp(self)
        self.docs = self.root / 'docs'
        self.docs.mkdir()
        (self.docs / 'guide.md').write_text('Original claim.\nRemoved claim.\nMoved claim.\n')
        (self.docs / 'other.md').write_text('Shared claim.\n')
        self.spec = {'documents': [
            {'path': 'guide.md', 'claims': [
                {'id': 'original', 'text': 'Original claim.', 'evidence': ['src/a.py']},
                {'id': 'removed', 'text': 'Removed claim.', 'evidence': ['src/gone.py']},
                {'id': 'moved', 'text': 'Moved claim.', 'evidence': ['src/rename.py']}]},
            {'path': 'other.md', 'claims': [
                {'id': 'shared', 'text': 'Shared claim.', 'evidence': ['src/a.py']}]}
        ]}
        self.before = self.capture('before.json')
        self.spec_path = self.save('spec.json', self.spec)
        self.bindings = self.root / 'bindings.json'
        self.call('bind', self.spec_path, '--snapshot', self.before, '--out', self.bindings)

    def call(self, *args, ok=True):
        result = subprocess.run([sys.executable, str(ROOT / 'impact.py'), *map(str, args),
                                 '--repo', str(self.repo), '--docs-root', str(self.docs)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        return result

    def derive(self, after, out='impact.json', bindings=None, ok=True):
        path = self.root / out
        self.call('impact', bindings or self.bindings, '--before', self.before,
                  '--after', after, '--out', path, ok=ok)
        if not ok:
            self.assertFalse(path.exists())
            return
        return json.loads(path.read_text())

    def test_impact_all_changes_and_shared_evidence(self):
        self.put('a.py', 'changed\n')
        (self.repo / 'src/gone.py').unlink()
        (self.repo / 'src/rename.py').rename(self.repo / 'src/moved.py')
        self.put('new.py', 'added\n')
        after = self.capture('after.json', self.commit())
        result = self.derive(after)
        self.assertEqual([d['path'] for d in result['candidates']], ['guide.md', 'other.md'])
        claims = result['candidates'][0]['claims']
        self.assertEqual({c['changes'][0]['type'] for c in claims}, {'modified','removed','rename-candidate'})
        self.assertEqual(result['unlinked_changes'], [{'type':'added','after':'src/new.py'}])
        self.derive(after, 'repeat.json')
        self.assertEqual((self.root/'impact.json').read_bytes(), (self.root/'repeat.json').read_bytes())
        original = (self.root/'impact.json').read_bytes()
        self.call('impact', self.bindings, '--before', self.before, '--after', after,
                  '--out', self.root/'impact.json', ok=False)
        self.assertEqual(original, (self.root/'impact.json').read_bytes())

    def test_impact_unchanged_and_unlinked_modification(self):
        result = self.derive(self.before)
        self.assertEqual(result['candidates'], [])
        self.assertEqual(result['unlinked_changes'], [])
        spec = copy.deepcopy(self.spec)
        spec['documents'] = [spec['documents'][1]]
        mapping = self.root/'subset.json'
        self.call('bind', self.save('subset-spec.json',spec), '--snapshot',self.before,'--out',mapping)
        self.put('gone.py','unlinked change\n')
        after = self.capture('after.json', self.commit())
        result = self.derive(after, 'subset-impact.json', mapping)
        self.assertEqual(result['candidates'], [])
        self.assertEqual(result['unlinked_changes'][0]['type'], 'modified')

    def test_impact_stale_document_and_baseline_fail(self):
        (self.docs/'guide.md').write_text('Original claim.\nRemoved claim.\nMoved claim.\nextra\n')
        self.derive(self.before, ok=False)
        (self.docs/'guide.md').write_text('Original claim.\nRemoved claim.\nMoved claim.\n')
        damaged = json.loads(self.bindings.read_text()); damaged['snapshot'] = '0'*64
        self.derive(self.before, 'stale.json', self.save('damaged.json',damaged,True),ok=False)
        snapshot = json.loads(self.before.read_text()); snapshot['files'] = []
        bad = self.save('omitted.json',snapshot,True)
        self.derive(bad,'omitted-impact.json',ok=False)

    def test_impact_invalid_links_and_duplicate_ids_fail(self):
        for i, mutation in enumerate(('absent','quote','duplicate','path','evidence','empty')):
            spec=copy.deepcopy(self.spec)
            claim=spec['documents'][0]['claims'][0]
            if mutation=='absent': claim['evidence']=['src/missing.py']
            if mutation=='quote': claim['text']='not in document'
            if mutation=='duplicate': spec['documents'][0]['claims'].append(claim.copy())
            if mutation=='path': spec['documents'][0]['path']='../escape.md'
            if mutation=='evidence': claim['evidence'] *= 2
            if mutation=='empty': claim['text']=' '
            out=self.root/f'bad{i}.json'
            self.call('bind',self.save(f'spec{i}.json',spec),'--snapshot',self.before,'--out',out,ok=False)
            self.assertFalse(out.exists())

    def test_impact_binding_order_and_inputs_preserved(self):
        spec = copy.deepcopy(self.spec)
        spec['documents'][0]['claims'][0]['evidence'].append('src/gone.py')
        first = self.root / 'ordered.json'
        self.call('bind', self.save('ordered-spec.json', spec), '--snapshot', self.before, '--out', first)
        spec['documents'].reverse()
        for doc in spec['documents']:
            doc['claims'].reverse()
            for claim in doc['claims']:
                claim['evidence'].reverse()
        second = self.root / 'reordered.json'
        shuffled = self.save('shuffled.json', spec)
        documents_before = {p.name: p.read_bytes() for p in self.docs.iterdir()}
        git_before = self.git('status', '--porcelain')
        head_before = self.git('rev-parse', 'HEAD')
        self.call('bind', shuffled, '--snapshot', self.before, '--out', second)
        self.assertEqual(first.read_bytes(), second.read_bytes())
        original = first.read_bytes()
        self.call('bind', shuffled, '--snapshot', self.before, '--out', first, ok=False)
        self.assertEqual(first.read_bytes(), original)
        self.derive(self.before, bindings=second)
        self.assertEqual(documents_before, {p.name: p.read_bytes() for p in self.docs.iterdir()})
        self.assertEqual(git_before, self.git('status', '--porcelain'))
        self.assertEqual(head_before, self.git('rev-parse', 'HEAD'))

    def test_impact_symlink_and_missing_document_fail(self):
        (self.docs/'other.md').unlink()
        (self.docs/'other.md').symlink_to(self.docs/'guide.md')
        self.derive(self.before,ok=False)
        (self.docs/'other.md').unlink()
        self.derive(self.before,'missing.json',ok=False)


if __name__ == '__main__':
    unittest.main()
