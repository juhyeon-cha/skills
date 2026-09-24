"""Product-neutral writing handoff over exact evidence and immutable document revisions."""
import json
from observations import notebook_scope, require, safe_path, read_snapshot
from notebook_store import location


def collection_result(path, source):
    if path is None:
        return None
    report = json.loads(safe_path(path).read_text(encoding='utf-8'))
    require(report.get('source') == source and isinstance(report.get('ok'), bool), 'invalid collection report')
    return report['ok']


def handoff(root, source, collection=None, save=False):
    scope = notebook_scope(root, required=True)
    require(scope['source'] == source, 'notebook source mismatch')
    success = collection_result(collection, source)
    result = {'version': 1, 'source': source, 'collection_ok': success,
              'documents': [], 'observations': [], 'notes': [], 'history': [], 'evidence_changes': [],
              'instruction': 'Compare exact bound and latest evidence. Revise affected explanations using their previous IDs; preserve notes and history. Obtain a real independent review. Collection is not semantic approval.'}
    view, rows = read_snapshot(root, source)
    result.update(documents=[d for d in view['documents'] if d['status'] != 'current'],
                  observations=view['observations'], notes=view['notes'], history=view['history'])
    by_id = {row['id']: row for row in rows}
    for document in result['documents']:
        for dependency in document['dependencies']:
            if dependency['bound'] != dependency['latest'] or dependency['status'] != 'complete':
                result['evidence_changes'].append({'document': document['id'], 'object': dependency['object'],
                    'reason': 'incomplete_evidence' if dependency['status'] != 'complete' else 'new_observation',
                    'bound': by_id[dependency['bound']], 'latest': by_id[dependency['latest']]})
    if save:
        from common import digest
        from notebook_transfer import write_new
        path = location(root, 'artifacts') / 'handoffs' / (digest(result) + '.json')
        safe_path(path)
        result['artifact'] = write_new(path, result, reuse=True)
    return result
