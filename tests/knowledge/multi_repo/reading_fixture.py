"""Repeatable local two-repository reading input; all fixture review receipts are synthetic."""
from pathlib import Path
from types import SimpleNamespace
from test_multi_repo import Fixture, initialize, write


class ReadingFixture(Fixture):
    def update(self, repository, value):
        super().update(repository, value)
        revision = self.revisions[repository]
        docs = self.root / (repository + '-reading-docs-' + revision)
        docs.mkdir()
        bodies = {
            'contract.md': '# ' + repository + ' 계약\n\n'
                '이 문서는 두 저장소 사이의 금액 필드를 설명합니다.\n\n'
                '## 금액\n\n| 필드 | 의미 |\n| --- | --- |\n| ' + value + ' | 금액 합계 |\n\n'
                '```json\n{"' + value + '":120}\n```\n\n'
                '[호출 안내의 검증](guide.md#검증)\n\n'
                '## 금액\n\n중복 제목의 두 번째 절입니다. [첫 금액](#금액)\n\n'
                '[확인 불가](private.md)\n',
            'guide.md': '# 호출 안내\n\n## 검증\n\n'
                '호출자는 ' + value + ' 필드를 읽습니다. [계약으로](contract.md#금액)\n\n'
                '| 대상 | 의미 |\n| --- | --- |\n| ' + value + ' | 금액 합계 |\n\n'
                '이 예제의 검사는 로컬에서 실행됩니다. 운영 배포는 검증하지 않습니다.\n',
        }
        for name, text in bodies.items():
            (docs/name).write_text(text)
        spec = self.root/(repository + '-reading-spec.json')
        write(spec, {'documents': [{'path': name, 'claims': [
            {'id': 'body', 'text': text, 'evidence': ['app.py']}]} for name, text in bodies.items()]})
        project = self.root/(repository + '-reading-project-' + revision)
        initialize(SimpleNamespace(repo=Path(self.host['repositories'][repository]['path']), docs=docs,
            repository=repository, baseline=revision, path=['app.py'], spec=spec,
            audience='Local reading evaluation', purpose='Read field contract and verification scope'), project)
        self.host['repositories'][repository]['project'] = str(project)
        self.persist()


def published_fixture():
    fixture = ReadingFixture()
    fixture.complete()
    fixture.call('refresh', {'goal': 'contract'})
    fixture.call('publish', {'goal': 'contract', 'audience': 'reader'})
    return fixture
