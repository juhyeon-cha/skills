"""Check frozen input bytes only; never infer semantic acceptance from this exit code."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
manifest = json.loads((root / 'frozen.json').read_text())
assert set(manifest['sha256']) == {'sources.json', 'expectations.json', 'reader-normal-prompt.txt', 'reader-variant-prompt.txt'}
for name, expected in manifest['sha256'].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == expected, name
criteria = json.loads((root / 'expectations.json').read_text())['criteria']
sources = json.loads((root / 'sources.json').read_text())
assert len({c['id'] for c in criteria}) == len(criteria) == 5
assert all(c['authority'] in sources and c['required'] for c in criteria)
print('PASS: frozen bytes, IDs and authority links only; content/reader judgments are separate')
