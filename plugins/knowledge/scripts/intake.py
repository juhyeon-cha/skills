"""Versioned change intake; semantic classification is supplied by the agent."""
import re
from cli import Draft202012Validator, identify, sha

NONEMPTY = {'type': 'string', 'pattern': r'\S'}
def obj(properties, required=None):
    return {'type': 'object', 'properties': properties, 'required': required or list(properties), 'additionalProperties': False}
def array(items, minimum=1):
    return {'type': 'array', 'items': items, 'minItems': minimum}
SOURCE = obj({'id': NONEMPTY, 'kind': {'enum': ['user', 'document', 'code', 'decision']},
              'authority': {'enum': ['user_instruction', 'observed_implementation', 'approved_decision', 'context']},
              'version': NONEMPTY, 'locator': NONEMPTY, 'text': NONEMPTY,
              'sha256': {'type': 'string', 'pattern': '^[a-f0-9]{64}$'}})
SCHEMA = obj({'version': {'const': 1}, 'origin': {'enum': ['user', 'document', 'code']},
    'intent': {'enum': ['current_behavior', 'wording_only', 'behavior_change']},
    'sources': array(SOURCE),
    'current': obj({'code': {'anyOf': [NONEMPTY, {'type': 'null'}]}, 'description': NONEMPTY}),
    'target': obj({'sources': array(NONEMPTY), 'description': NONEMPTY,
                   'acceptance': array(NONEMPTY), 'status': {'enum': ['proposed', 'confirmed', 'deferred', 'withdrawn']}}),
    'differences': array(obj({'kind': {'enum': ['wording', 'behavior', 'documentation']},
                             'description': NONEMPTY, 'sources': array(NONEMPTY)})),
    'rationale': NONEMPTY})


def classify(value):
    Draft202012Validator(SCHEMA).validate(value)
    sources = {s['id']: s for s in value['sources']}
    if len(sources) != len(value['sources']):
        raise ValueError('INTAKE: duplicate source IDs')
    authority = {'user_instruction': 'user', 'observed_implementation': 'code', 'approved_decision': 'decision'}
    for source in sources.values():
        if source['sha256'] != sha(source['text'].encode()):
            raise ValueError('INTAKE: source content hash mismatch')
        if source['authority'] != 'context' and authority[source['authority']] != source['kind']:
            raise ValueError('INTAKE: authority does not match source kind')
    if not any(s['kind'] == value['origin'] for s in sources.values()):
        raise ValueError('INTAKE: origin source missing')
    refs = value['target']['sources'] + [r for d in value['differences'] for r in d['sources']]
    code = value['current']['code']
    if code is not None:
        refs.append(code)
    if any(ref not in sources for ref in refs):
        raise ValueError('INTAKE: unknown source reference')
    if code is not None and sources[code]['authority'] != 'observed_implementation':
        raise ValueError('INTAKE: current code needs implementation evidence')
    kinds = {d['kind'] for d in value['differences']}
    intent = value['intent']
    if intent == 'current_behavior':
        if code is None or code not in value['target']['sources'] or kinds != {'documentation'}:
            raise ValueError('INTAKE: current explanation needs code authority and documentation-only differences')
        route, phase = 'current_documentation', 'awaiting_document_update'
    elif intent == 'wording_only':
        if value['origin'] != 'document' or kinds != {'wording'}:
            raise ValueError('INTAKE: wording-only requires document origin and only wording differences')
        route, phase = 'document_wording', 'no_code_work'
    else:
        if 'behavior' not in kinds or not any(sources[r]['authority'] in ('user_instruction', 'approved_decision') for r in value['target']['sources']):
            raise ValueError('INTAKE: behavior target needs instruction/decision authority and remaining behavior difference')
        route = 'implementation_handoff'
        phase = {'proposed': 'awaiting_decision', 'confirmed': 'pending_implementation',
                 'deferred': 'deferred', 'withdrawn': 'withdrawn'}[value['target']['status']]
    if value['target']['status'] != 'confirmed':
        phase = {'proposed': 'awaiting_decision', 'deferred': 'deferred', 'withdrawn': 'withdrawn'}[value['target']['status']]
    result = {'version': 1, 'kind': 'change-intake', 'input': value, 'route': route, 'phase': phase,
              'implementation': 'not_verified' if intent != 'wording_only' else 'not_required',
              'document_quality': 'not_evaluated', 'deployment': 'not_verified'}
    result['id'] = identify(result)
    return result


def register(args, project):
    from project_store import immutable, read
    if (project / 'retired.json').exists():
        raise ValueError('PROJECT_RETIRED: use a reviewed successor')
    result = classify(read(args.input))
    path = project / 'intakes' / (result['id'] + '.json')
    if (project / 'project.sqlite3').exists():
        from project_store import database
        with database(project, True):
            immutable(path, result)
    else:
        immutable(path, result)
    return {'intake': result['id'], 'record': str(path), 'route': result['route'], 'phase': result['phase']}


def load(project, identity):
    from project_store import read
    if not re.fullmatch('[a-f0-9]{64}', identity):
        raise ValueError('INTAKE: invalid ID')
    path = project / 'intakes' / (identity + '.json')
    if path.is_symlink():
        raise ValueError('INTAKE: symlink record refused')
    record = read(path)
    if classify(record['input']) != record or record['id'] != identity:
        raise ValueError('INTAKE: record changed')
    return record


def inspect(args, project):
    return load(project, args.intake)
