"""Read-only workflow status for a desktop host; collection is not document approval."""
import hashlib
import json
from common import digest
from observations import read, safe_path, notebook_scope, require, timestamp


def status(root, source, publication, collection=None):
    scope = notebook_scope(root, required=True)
    require(scope['source'] == source, 'notebook source mismatch')
    publication = safe_path(publication)
    entry = safe_path(publication / 'index.html')
    owner = safe_path(publication / 'scope.json')
    has_wiki = entry.is_file()
    if has_wiki:
        require(owner.is_file() and json.loads(owner.read_text(encoding='utf-8')) == scope,
                'wiki publication scope mismatch')
    result = {'source': source, 'audience': scope['audience'], 'has_wiki': has_wiki,
              'stage': 'empty', 'documents': [], 'last_observed_at': None,
              'last_published_at': None}
    if not (safe_path(root) / 'observations.sqlite').exists():
        return result
    view = read(root, source)
    result['documents'] = [{'title': d['value']['title'], 'status': d['status']} for d in view['documents']]
    result['last_observed_at'] = max((o['value']['observed_at'] for o in view['observations']), key=timestamp, default=None)
    receipt = safe_path(publication / 'published.json')
    published = json.loads(receipt.read_text(encoding='utf-8')) if receipt.is_file() else {}
    entry_matches = has_wiki and published.get('entry_hash') == hashlib.sha256(entry.read_bytes()).hexdigest()
    if entry_matches:
        result['last_published_at'] = published.get('published_at')
    if collection is not None:
        report = json.loads(safe_path(collection).read_text(encoding='utf-8'))
        require(report.get('source') == source and isinstance(report.get('ok'), bool), 'invalid collection report')
        if not report['ok']:
            result['stage'] = 'collection_failed'
            return result
    states = {d['status'] for d in view['documents']}
    if not states or states & {'stale', 'evidence_pending', 'revise', 'blocked'}:
        result['stage'] = 'writing'
    elif 'unreviewed' in states:
        result['stage'] = 'review'
    elif states == {'current'}:
        result['stage'] = 'complete' if entry_matches and published.get('revision') == digest(view) else 'publish'
    return result
