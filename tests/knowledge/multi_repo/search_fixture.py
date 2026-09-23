"""Fixed long-document corpus in isolated repositories; receipts are synthetic."""
import json
from pathlib import Path
from types import SimpleNamespace
from test_multi_repo import Fixture, initialize, write

CORPUS = Path(__file__).resolve().parents[1]/'search-observation/corpus.json'


def documents():
    corpus = json.loads(CORPUS.read_text())
    return [{**d, 'text': d['text'].replace('{background}', corpus['background'] * corpus['repeat'])}
            for d in corpus['documents']]


class SearchFixture(Fixture):
    def update(self, repository, value):
        super().update(repository, value)
        revision = self.revisions[repository]
        docs = self.root/(repository + '-search-docs-' + revision)
        docs.mkdir()
        selected = [d for d in documents() if d['repository'] == repository]
        for d in selected:
            (docs/d['path']).write_text(d['text'])
        spec = self.root/(repository + '-search-spec.json')
        write(spec, {'documents': [{'path': d['path'], 'claims': [
            {'id': 'body', 'text': d['text'], 'evidence': ['app.py']}]} for d in selected]})
        project = self.root/(repository + '-search-project-' + revision)
        initialize(SimpleNamespace(repo=Path(self.host['repositories'][repository]['path']), docs=docs,
            repository=repository, baseline=revision, path=['app.py'], spec=spec,
            audience='Local search evaluation', purpose='Find contract, impact and verification evidence'), project)
        self.host['repositories'][repository]['project'] = str(project)
        self.persist()


def published_fixture():
    fixture = SearchFixture()
    fixture.complete()
    fixture.call('refresh', {'goal': 'contract'})
    fixture.call('publish', {'goal': 'contract', 'audience': 'reader'})
    return fixture
