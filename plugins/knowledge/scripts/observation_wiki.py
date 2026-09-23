"""Export one explicit source's notebook as inputs for the shared static wiki."""
import json
from pathlib import Path

from common import digest
from observations import safe_path, require

STATUS = {'current': '현재 가져온 근거와 일치 · 독립 검토 기록 있음',
          'unreviewed': '독립 검토 대기', 'stale': '근거 변경 · 설명 갱신 필요',
          'evidence_pending': '근거 수집 미완료 또는 제거 관측 · 설명 재확인 필요',
          'revise': '설명 수정 필요', 'blocked': '판단 보류'}


def literal(value):
    # Keep supplied evidence/notes as text, even if it contains Markdown fences or links.
    text = str(value)
    length = max([len(part) for part in text.split('\n') if part and set(part) == {'`'}] + [2]) + 1
    # Include runs embedded in a line as well, to ensure a valid closing fence cannot occur.
    import re
    length = max(length, max([len(x) + 1 for x in re.findall(r'`+', text)] + [3]))
    fence = '`' * length
    return fence + '\n' + text + '\n' + fence + '\n'


def label(value):
    return str(value).replace('\\', '\\\\').replace('[', '\\[').replace(']', '\\]').replace('\n', ' ').replace('\r', ' ')


def export(view, output, base_path="/"):
    scope = view.get('notebook_scope')
    require(scope is not None and scope['audience'] == view['audience'] and
            scope['source'] == view['source'], 'export requires a scoped notebook')
    audience = scope['audience']
    require(all(d['value']['audience'] == audience for d in view['documents']), 'mixed wiki audiences')
    title = '제품 사용 지식' if audience == 'user' else '제품 개발 지식'
    output = safe_path(output)
    files = {}
    pages = []

    def page(identity, title, text, review='해당 항목의 검토 상태 참조', kind=None):
        name = identity + '.md'
        files[name] = text
        entry = {'id': identity, 'path': name, 'title': title, 'summary': title,
                 'evidence': {'reviewStatus': review, 'liveStatus': '가져온 자료의 로컬 스냅샷 · 실시간 SAP 확인 아님'}}
        if kind:
            entry['kind'] = kind
        pages.append(entry)

    page('home', '무엇을 하려 하나요?', '# 무엇을 하려 하나요?\n\n'
         '이 지식은 선택한 출처의 로컬 스냅샷입니다. 문서별 제품 버전과 근거 상태를 확인하세요.\n\n'
         '- [' + title + '](' + audience + '.md)\n'
         '- [추가한 메모와 이전 지식](notes.md)\n- [근거와 수집 상태](evidence.md)\n')
    areas = {'usage': '제품 사용', 'development': '제품 개발', 'domain': '대상 시스템 지식'}
    for audience, title in ((audience, title),):
        rows = [d for d in view['documents'] if d['value']['audience'] == audience]
        text = '# ' + title + '\n\n'
        if not rows:
            text += '현재 선택한 출처·버전·검색 조건에 맞는 설명이 없습니다.\n'
        for area, area_title in areas.items():
            group = [d for d in rows if d['value']['area'] == area]
            if group:
                text += '\n## ' + area_title + '\n\n'
            for doc in group:
                value = doc['value']
                text += '- [' + label(value['title']) + '](p-' + doc['id'] + '.md) — ' + STATUS[doc['status']] + '\n'
        page(audience, title, text)
    for doc in view['documents']:
        value = doc['value']
        text = '# ' + label(value['title']) + '\n\n**' + STATUS[doc['status']] + '**\n\n'
        text += '적용 제품 버전: ' + label(value['product_version']) + '\n\n읽은 뒤 할 일: ' + label(value['purpose']) + '\n\n'
        body = value['body']
        heading = '# ' + value['title'] + '\n'
        if body.startswith(heading):
            body = body[len(heading):].lstrip('\n')
        text += body + '\n\n[근거·수집 상태](evidence.md) · [메모](notes.md)\n'
        page('p-' + doc['id'], value['title'], text, STATUS[doc['status']])
    notes = '# 추가한 메모와 이전 지식\n\n메모는 사용자 기록입니다. 검토된 사실이나 현재 동작으로 자동 승격하지 않습니다.\n'
    for row in view['notes']:
        value = row['value']
        notes += '\n## ' + row['id'][:12] + '\n\n' + literal(json.dumps({k: value[k] for k in ('object', 'author', 'origin')}, ensure_ascii=False))
        notes += '\n' + literal(value['body'])
    if not view['notes']:
        notes += '\n기록된 메모가 없습니다.\n'
    page('notes', '추가한 메모와 이전 지식', notes, '메모 · 독립 검토된 사실 아님')
    evidence = '# 근거와 수집 상태\n\n이 페이지의 버전·상태는 마지막으로 가져온 자료에 관한 것입니다. 최신 SAP 상태를 보장하지 않습니다.\n\n'
    evidence += literal(json.dumps({k: view[k] for k in ('source', 'audience', 'area', 'product_version', 'scope')}, ensure_ascii=False, indent=2))
    evidence += '\n## 설명별 근거 연결\n\n'
    for doc in view['documents']:
        evidence += '\n### ' + label(doc['value']['title']) + '\n\n'
        evidence += literal(json.dumps({'document': doc['id'], 'dependencies': doc['dependencies']}, ensure_ascii=False, indent=2))
    for row in view['observations']:
        evidence += '\n## ' + label(row['value']['title']) + '\n\n' + literal(json.dumps(row, ensure_ascii=False, indent=2))
    evidence += '\n## 보존된 이력 식별자\n\n' + literal(json.dumps(view['history'], ensure_ascii=False, indent=2))
    page('evidence', '근거와 수집 상태', evidence, '입력 자료 · 의미 정확성 검토 아님', 'evidence')
    manifest = {'basePath': base_path, 'title': title, 'revision': digest(view), 'home': 'home', 'evidencePage': 'evidence', 'pages': pages}
    # A new directory only. Manifest is written last; interrupted exports are never complete inputs.
    output.mkdir(parents=True, exist_ok=False)
    for path, text in files.items():
        (output / path).write_text(text, encoding='utf-8')
    (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    return {'output': str(output), 'revision': manifest['revision'], 'pages': len(pages),
            'scope': 'Static wiki inputs only; build with the shared wiki renderer. No remote publication.'}
