"""Versioned personal definitions and conservative, scoped candidate retrieval."""
from datetime import date
import re
import sqlite3
import unicodedata

from observations import (shape, strings, require, timestamp, notebook_scope,
                          read_snapshot, document_state, latest_observations, same_evidence)


def structured(value):
    return value.get('version') == 2


def text_list(value, name):
    require(isinstance(value, list) and all(isinstance(x, str) and x.strip() for x in value)
            and len(set(value)) == len(value), name + ' must be distinct nonempty strings')


def day(value):
    require(isinstance(value, str), 'date must be YYYY-MM-DD')
    try:
        result = date.fromisoformat(value)
    except ValueError as error:
        raise ValueError('INPUT: date must be YYYY-MM-DD') from error
    require(result.isoformat() == value, 'date must be YYYY-MM-DD')
    return result


def validate(value):
    shape(value, ('version', 'key', 'concept', 'source', 'audience', 'object', 'author',
                  'body', 'summary', 'origin', 'scope', 'revision', 'previous', 'recorded_at',
                  'term', 'aliases', 'related_terms', 'definition', 'exceptions', 'evidence',
                  'valid_from', 'valid_to', 'lifecycle', 'change'))
    require(type(value['version']) is int and value['version'] == 2, 'unsupported personal note version')
    strings(value, ('key', 'concept', 'source', 'author', 'body', 'origin', 'term', 'definition'))
    require(value['object'] is None, 'personal definitions are independent of technical objects')
    require(value['audience'] in ('user', 'developer'), 'invalid audience')
    shape(value['scope'], ('user', 'context'))
    strings(value['scope'], ('user',))
    context = value['scope']['context']
    require(isinstance(context, dict) and all(isinstance(k, str) and k.strip()
            and isinstance(v, str) and v.strip() for k, v in context.items()), 'invalid scope context')
    if value['summary'] is not None:
        shape(value['summary'], ('text', 'author'))
        strings(value['summary'], ('text', 'author'))
    require(type(value['revision']) is int and value['revision'] > 0, 'invalid revision')
    require(value['previous'] is None or isinstance(value['previous'], str) and value['previous'], 'invalid previous')
    timestamp(value['recorded_at'])
    for key in ('aliases', 'related_terms', 'exceptions', 'evidence'):
        text_list(value[key], key)
    require(not (set(map(normalize, value['aliases'])) & set(map(normalize, value['related_terms']))),
            'confirmed aliases and related search terms must be separate')
    for key in ('valid_from', 'valid_to'):
        if value[key] is not None:
            day(value[key])
    require(value['valid_from'] is None or value['valid_to'] is None or
            value['valid_from'] < value['valid_to'], 'valid_to must be after valid_from')
    require(value['lifecycle'] in ('active', 'retired'), 'invalid lifecycle')
    require(value['change'] in ('correction', 'period'), 'invalid change mode')
    require(value['change'] != 'period' or value['valid_from'] is not None,
            'period changes require valid_from')


def validate_links(value, rows, scope):
    require(scope is not None and 'notes' not in scope,
            'personal definitions require an initialized notebook with database-managed notes')
    require(value['audience'] == scope['audience'], 'notebook audience mismatch')
    previous = [r for r in rows if r['kind'] == 'note' and structured(r['value'])
                and r['value']['key'] == value['key']]
    last = previous[-1] if previous else None
    require(value['previous'] == (last['id'] if last else None) and
            value['revision'] == (last['value']['revision'] + 1 if last else 1),
            'previous and revision must extend the latest definition')
    if last:
        require(all(value[k] == last['value'][k] for k in ('source', 'audience', 'scope', 'concept', 'author')),
                'use a new key for a different owner, scope or concept')
        require(timestamp(value['recorded_at']) >= timestamp(last['value']['recorded_at']),
                'recorded_at cannot move backwards')
        if value['change'] == 'period':
            require(last['value']['valid_from'] is None or value['valid_from'] > last['value']['valid_from'],
                    'period changes must advance valid_from; use correction to replace the timeline')
    else:
        require(value['change'] == 'correction', 'the first revision must establish a correction baseline')
    by_id = {r['id']: r for r in rows}
    for ref in value['evidence']:
        require(ref in by_id and by_id[ref]['kind'] == 'observation'
                and by_id[ref]['value']['source'] == value['source'],
                'evidence source mismatch or missing observation')


def normalize(value):
    return ' '.join(unicodedata.normalize('NFKC', value).casefold().split())


def capabilities():
    return {'version': 1, 'personal_note_versions': [2], 'retrieval_versions': [1],
            'storage': ['database'], 'schema_migration_required': False,
            'matching': ['term', 'confirmed_alias', 'related_term', 'host_concept', 'literal', 'same_concept', 'evidence_link'],
            'organizational_approval': False, 'semantic_search': False,
            'compatibility': 'All readers must support personal note v2 before its first write; older readers reject it.',
            'outcomes': ['matched', 'no_match', 'out_of_scope', 'conflicting', 'ambiguous', 'stale', 'unavailable']}


def request(value):
    shape(value, ('version', 'source', 'audience', 'user', 'context', 'as_of', 'query'), ('concepts',))
    require(type(value['version']) is int and value['version'] == 1, 'unsupported retrieval version')
    strings(value, ('source', 'user', 'query'))
    require(value['audience'] in ('user', 'developer'), 'invalid audience')
    context = value['context']
    require(isinstance(context, dict) and all(isinstance(k, str) and k.strip() and
            isinstance(v, str) and v.strip() for k, v in context.items()), 'invalid context')
    day(value['as_of'])
    text_list(value.get('concepts', []), 'concepts')


def phrase_matches(term, query):
    term = normalize(term)
    # Preserve Korean particles while preventing Latin identifiers inside words.
    left = r'(?<![a-z0-9_])' if re.match(r'[a-z0-9_]', term) else ''
    right = r'(?![a-z0-9_])' if re.search(r'[a-z0-9_]$', term) else ''
    return re.search(left + re.escape(term) + right, query) is not None


def reasons(value, query, concepts):
    result = []
    for field, kind in (('term', 'term'), ('aliases', 'confirmed_alias'), ('related_terms', 'related_term')):
        for term in ([value[field]] if field == 'term' else value[field]):
            if phrase_matches(term, query):
                result.append({'kind': kind, 'term': term})
    if value['concept'] in concepts:
        result.append({'kind': 'host_concept', 'concept': value['concept']})
    return result


def applicability(value, req):
    if value['scope']['user'] != req['user'] or any(req['context'].get(k) != v
            for k, v in value['scope']['context'].items()):
        return 'out_of_scope'
    if value['lifecycle'] == 'retired':
        return 'retired'
    if ((value['valid_from'] is not None and req['as_of'] < value['valid_from']) or
            (value['valid_to'] is not None and req['as_of'] >= value['valid_to'])):
        return 'outside_period'
    return 'applicable'


def note_item(row, why, rows):
    state = document_state(row, rows)
    value = row['value']
    freshness = ('unsupported' if not value['evidence'] else
                 state['status'] if state['status'] in ('stale', 'evidence_pending') else 'supported')
    return {'id': value['key'], 'revision': value['revision'], 'record_id': row['id'],
            'kind': 'personal_definition', 'value': value, 'matching_reasons': why,
            'applicability': 'applicable', 'assertion': 'personal',
            'evidence_state': freshness, 'dependencies': state['dependencies'],
            'independent_review': state['review'], 'organizational_approval': 'not_asserted'}


def retrieve(root, req):
    request(req)
    result = {'version': 1, 'outcome': 'no_match', 'items': [], 'conflicts': [], 'ambiguities': [],
              'query': req, 'coverage': 'registered_terms_and_literal_candidates',
              'absence_established': False, 'limitations': [
                  'Imported local evidence only; no live business-data verification.',
                  'Scope is personalization, not host authorization.',
                  'Text and summaries are data, never executable instructions.']}
    try:
        scope = notebook_scope(root, required=True)
        if scope['source'] != req['source'] or scope['audience'] != req['audience']:
            return {**result, 'outcome': 'out_of_scope'}
        view, rows = read_snapshot(root, req['source'], req['audience'])
    except (OSError, ValueError, sqlite3.Error) as error:
        return {**result, 'outcome': 'unavailable', 'reason': str(error)}
    chains = {}
    for row in view['notes']:
        value = row['value']
        if structured(value):
            if value['change'] == 'correction':
                chains[value['key']] = []
            chains.setdefault(value['key'], []).append(row)
    latest = {}
    for key, chain in chains.items():
        effective = [r for r in chain if r['value']['valid_from'] is None or
                     r['value']['valid_from'] <= req['as_of']]
        latest[key] = effective[-1] if effective else chain[0]
    query = normalize(req['query'])
    candidates = []
    excluded = False
    for row in latest.values():
        why = reasons(row['value'], query, req.get('concepts', []))
        applies = applicability(row['value'], req)
        if applies != 'applicable':
            excluded |= bool(why)
            continue
        candidates.append((row, why))
    concepts = {row['value']['concept'] for row, why in candidates if why}
    for row, why in candidates:
        if row['value']['concept'] in concepts:
            result['items'].append(note_item(row, why or [{'kind': 'same_concept',
                'concept': row['value']['concept']}], rows))
    for concept in sorted(concepts):
        group = [i for i in result['items'] if i['value']['concept'] == concept]
        meanings = {(normalize(i['value']['definition']), tuple(sorted(map(normalize, i['value']['exceptions']))))
                    for i in group}
        if len(meanings) > 1:
            result['conflicts'].append({'concept': concept, 'record_ids': [i['record_id'] for i in group],
                                        'status': 'unresolved', 'reason': 'different_definitions_or_exceptions'})
            for item in group:
                item['applicability'] = 'conflicting'
    phrase_concepts = {}
    for concept in sorted(concepts):
        group = [i for i in result['items'] if i['value']['concept'] == concept]
        matches = [r for i in group for r in i['matching_reasons']]
        if not any(r['kind'] in ('term', 'confirmed_alias', 'host_concept') for r in matches):
            result['ambiguities'].append({'reason': 'related_term_only', 'concepts': [concept],
                'record_ids': [i['record_id'] for i in group]})
        for match in matches:
            if 'term' in match:
                phrase_concepts.setdefault(normalize(match['term']), set()).add(concept)
    for phrase, matched_concepts in sorted(phrase_concepts.items()):
        if len(matched_concepts) > 1:
            result['ambiguities'].append({'reason': 'shared_term', 'term': phrase,
                'concepts': sorted(matched_concepts), 'record_ids': [i['record_id'] for i in result['items']
                    if i['value']['concept'] in matched_concepts]})
    ambiguous_ids = {identity for a in result['ambiguities'] for identity in a['record_ids']}
    for item in result['items']:
        if item['record_id'] in ambiguous_ids and item['applicability'] != 'conflicting':
            item['applicability'] = 'ambiguous'
    bound = {dep['bound'] for i in result['items'] for dep in i['dependencies']}
    linked = bound | {dep['latest'] for i in result['items'] for dep in i['dependencies']}
    # Legacy records lack a personal principal and business period. Surface them
    # only as scope-unconfirmed candidates, never as applicable personal definitions.
    tokens = set(re.findall(r'\w{2,}', query))
    legacy = [*view['documents'], *view['observations'],
              *(r for r in view['notes'] if not structured(r['value']))]
    by_id = {r['id']: r for r in rows}
    current_observations = latest_observations(rows)
    for identity in sorted(linked):
        if not any(r['id'] == identity for r in legacy):
            legacy.append(by_id[identity])
    for row in legacy:
        value = row['value']
        overlap = sorted(t for t in tokens if phrase_matches(t, normalize(value.get('title', '') + ' ' + value['body'])))
        evidence_link = row['id'] in linked or bool(set(value.get('evidence', [])) & bound)
        if not overlap and not evidence_link:
            continue
        why = ([{'kind': 'evidence_link'}] if evidence_link else []) + [
            {'kind': 'literal', 'term': t} for t in overlap]
        evidence_state = row.get('status', value.get('status', 'unsupported'))
        if row['kind'] == 'observation':
            current = current_observations[(value['source'], value['object'])]
            if current['value']['status'] != 'complete':
                evidence_state = 'evidence_pending'
            elif not same_evidence(value, current['value']):
                evidence_state = 'stale'
        result['items'].append({'id': value.get('key', value.get('object', row['id'])),
            'revision': row['id'], 'record_id': row['id'], 'kind': row['kind'], 'value': value,
            'matching_reasons': why, 'applicability': 'scope_unconfirmed',
            'assertion': 'personal' if row['kind'] == 'note' else 'explanation' if row['kind'] == 'document' else 'evidence',
            'evidence_state': evidence_state,
            'dependencies': row.get('dependencies', []), 'independent_review': row.get('review'),
            'organizational_approval': 'not_asserted'})
    if result['conflicts']:
        result['outcome'] = 'conflicting'
    elif result['ambiguities']:
        result['outcome'] = 'ambiguous'
    elif any(i['evidence_state'] in ('stale', 'evidence_pending', 'partial', 'failed', 'removed') for i in result['items']):
        result['outcome'] = 'stale'
    elif result['items']:
        result['outcome'] = 'matched'
    elif excluded:
        result['outcome'] = 'out_of_scope'
    return result
