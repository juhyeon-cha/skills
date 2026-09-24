"""Build and atomically select a checked, source-scoped notebook wiki."""
import json
from pathlib import Path
import subprocess
from datetime import datetime, timezone
from observations import read, require, safe_path, notebook_scope


def wiki(root, source, output, node, markdown_it, publish=None, require_current=False):
    from observation_wiki import export
    scope = notebook_scope(root, required=True)
    view = read(root, source)
    if require_current:
        require(bool(view['documents']) and all(d['status'] == 'current' for d in view['documents']),
                'publication requires reviewed current documents in the exported snapshot')
    output = safe_path(output)
    if publish is not None:
        publish = safe_path(publish)
        require(publish in output.parents, 'wiki output must be a new child of its stable publication root')
        owner = publish / 'scope.json'
        safe_path(owner)
        safe_path(publish / 'index.html')
        if owner.exists():
            require(json.loads(owner.read_text(encoding='utf-8')) == scope, 'wiki publication scope mismatch')
        else:
            require(not publish.exists() or not any(publish.iterdir()), 'publication root is not an empty knowledge wiki')
            publish.mkdir(parents=True, exist_ok=True, mode=0o700)
            with owner.open('x', encoding='utf-8') as file:
                file.write(json.dumps(scope, ensure_ascii=False))
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    from urllib.parse import quote
    base_path = '/' + quote((output / 'site').relative_to(publish).as_posix(), safe='/') + '/' if publish else '/'
    export(view, output / 'content', base_path)
    scripts = Path(__file__).resolve().parent / 'wiki'
    for command in ([node, str(scripts / 'build.mjs'), str(output / 'content'), str(output / 'site'), str(markdown_it)],
                    [node, str(scripts / 'check.mjs'), str(output / 'content/manifest.json'), str(output / 'site')]):
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        require(result.returncode == 0, 'wiki build/check failed; preserve output and inspect runtime dependencies')
    if publish is not None:
        import os
        import tempfile
        from urllib.parse import quote
        target = quote((output / 'site/index.html').relative_to(publish).as_posix(), safe='/')
        content = ('<!doctype html><html lang="ko"><meta charset="utf-8">'
                   '<meta http-equiv="refresh" content="0;url=' + target + '">'
                   '<title>내 지식</title><a href="' + target + '">내 지식 열기</a></html>')
        # Only checked snapshots become the entry point; a failed build leaves it unchanged.
        safe_path(publish / 'index.html')
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=publish, delete=False) as file:
            file.write(content)
            temporary = file.name
        import hashlib
        from common import digest
        receipt = {'revision': digest(view), 'published_at': datetime.now(timezone.utc).isoformat(),
                   'entry_hash': hashlib.sha256(content.encode('utf-8')).hexdigest()}
        receipt_path = safe_path(publish / 'published.json')
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=publish, delete=False) as file:
            json.dump(receipt, file, ensure_ascii=False)
            receipt_temp = file.name
        os.replace(receipt_temp, receipt_path)
        os.replace(temporary, publish / 'index.html')
    return {'ok': True, 'entry': str(publish / 'index.html') if publish else None,
            'index': str(output / 'site/index.html'),
            'site': str(output / 'site'), 'scope': 'Local static wiki snapshot; serve on loopback to use search.'}
