#!/usr/bin/env python3
"""Serve one host-selected managed knowledge goal on loopback; no publication writes."""
import argparse
from html import escape
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from urllib.parse import quote, urlsplit, parse_qs

from jsonschema.exceptions import ValidationError
from multi_repo import Store

LABELS = {'complete': '완료', 'incomplete': '미완료', 'active': '진행 중',
          'withdrawn': '철회', 'deferred': '보류', 'verified': '검증됨',
          'pending': '검증 대기', 'pending_or_stale': '검증 대기 또는 오래됨',
          'source_unavailable': '소스 확인 불가', 'current': '현재 근거와 일치',
          'stale': '오래됨', 'absent': '없음', 'unavailable_or_partial': '본문 미제공',
          'published': '게시됨', 'partial': '부분 게시', 'failed': '실패'}

DIAGNOSES = {
    'verified': '이 검증 범위에서 차단 없음', 'source_dirty': '소스에 미커밋 변경이 있음',
    'documents_pending': '현재 코드에 대한 문서 반영이 대기 중',
    'document_evidence_changed': '문서와 검토된 근거가 일치하지 않음',
    'check_pending': '필요한 검사 기록이 없음', 'check_stale': '검사 기록이 현재 입력과 다름',
    'check_failed': '현재 입력에 대한 검사 실행이 실패함', 'review_pending': '현재 근거에 대한 독립 검토가 필요함',
    'members_pending': '저장소별 검증이 먼저 필요함', 'withheld': '비공개 필수 근거가 있음',
    'evidence_unavailable': '이 단계의 근거를 확인할 수 없음',
}
ACTIONS = {
    'none': '이 단계의 추가 조치 없음', 'resolve_source_changes': '소유자가 소스 변경을 정리한 뒤 다시 조회',
    'update_and_review_documents': '문서와 근거를 확인하고 갱신·검토 절차 진행',
    'run_checks': '담당자가 현재 입력으로 검사 실행',
    'inspect_check_and_rerun': '담당자가 검사 실패를 확인·수정하고 다시 실행',
    'request_independent_review': '현재 근거에 대한 독립 검토 요청',
    'resolve_member_blockers': '저장소별 차단 원인부터 확인',
    'ask_host_to_verify_access': '호스트 담당자에게 접근 가능 범위 확인 요청',
    'ask_host_to_inspect_evidence': '호스트 담당자에게 해당 단계의 근거 확인 요청',
}
STAGES = {'source': '소스', 'documents': '문서', 'checks': '검사', 'review': '독립 검토',
          'integration': '통합', 'complete': '검증 완료'}


def esc(value):
    return escape(str(value), quote=True)


def label(value):
    return esc(LABELS.get(value, value))


def field(name, value):
    return '<div><dt>' + esc(name) + '</dt><dd>' + value + '</dd></div>'


def diagnosis(detail):
    return '<dl class="facts">' + field('확인 단계', esc(STAGES[detail['stage']])) + field(
        '진단', esc(DIAGNOSES[detail['code']])) + field('다음 조치', esc(ACTIONS[detail['next_action']])) + '</dl>'


def document_url(repository, path):
    return '/documents/' + quote(repository, safe='') + '/' + quote(path, safe='') + '/'


def markdown_pages(documents, module):
    """Render only the authorized text projection; no state/source coordinates cross this bridge."""
    if not module or not Path(module).is_absolute():
        raise ValueError('Select an absolute markdown-it module directory using --markdown-it or WIKI_MARKDOWN_IT_MODULE')
    result = subprocess.run(['node', str(Path(__file__).parent/'wiki/managed.mjs'), str(module)],
                            input=json.dumps(documents, ensure_ascii=False), text=True,
                            capture_output=True, timeout=10, check=True)
    pages = json.loads(result.stdout)
    if (not isinstance(pages, list) or len(pages) != len(documents)
            or any(not isinstance(p, dict) or p.get('url') != d['url']
                   or not isinstance(p.get('html'), str) or not isinstance(p.get('title'), str)
                   or not isinstance(p.get('headings'), list)
                   or any(not isinstance(h, dict) or not isinstance(h.get('id'), str)
                          or not isinstance(h.get('title'), str) or h.get('level') not in range(1, 7)
                          for h in p['headings']) for p, d in zip(pages, documents))):
        raise ValueError('MARKDOWN_RESULT_INVALID')
    return pages


def disclosure(title, body):
    return '<details class="technical"><summary>' + esc(title) + '</summary>' + body + '</details>'


def render(view, route, search='', markdown_it=None):
    """Render only the public reading projection; never load repository documents."""
    members = view['members']
    nav = '<a href="/">목표 개요</a><a href="/evidence/">근거와 확인 범위</a>'
    for member in members:
        nav += '<a href="/repositories/' + quote(member['repository'], safe='') + '/">' + esc(member['repository']) + '</a>'
    heading, body, has_body_title = '목표 개요', '', False
    if route == '/':
        body = '<dl class="facts">' + ''.join([
            field('목표 상태', label(view['status'])), field('전체 완료', label(view['completion'])),
            field('필수 저장소', str(view['required_count'])), field('비공개 필수 저장소', str(view['withheld_count'])),
            field('통합 검증', label(view['integration'])), field('문서 제공', label(view['served']))]) + '</dl>'
        body += '<h2>통합 검증 진단</h2>' + diagnosis(view['integration_detail'])
        body += '<h2>저장소별 현재와 목표</h2><form action="/" method="get"><label for="q">허용된 결과에서 찾기</label><input id="q" name="q" value="' + esc(search) + '"><button>찾기</button></form>'
        matches = [m for m in members if search.casefold() in json.dumps(m, ensure_ascii=False).casefold()]
        body += '<p>표시 ' + str(len(matches)) + ' / 접근 가능 ' + str(len(members)) + '개 · 검색은 전체 완료 판정을 바꾸지 않습니다.</p>'
        for member in matches:
            body += '<article><h3><a href="/repositories/' + quote(member['repository'], safe='') + '/">' + esc(member['repository']) + '</a></h3>' + member_facts(member) + '</article>'
    elif route == '/evidence/':
        heading = '근거와 확인 범위'
        body = '<dl class="facts">' + field('조회 색인', label(view['index'])) + '</dl>'
        body += '<p>색인의 최신성, 문서 제공 여부, 구현 검증은 서로 다른 상태입니다. 로컬 검증은 운영 배포를 증명하지 않습니다.</p>'
        body += '<h2>통합 검증 진단</h2>' + diagnosis(view['integration_detail'])
        for member in members:
            body += '<article><h2>' + esc(member['repository']) + '</h2>' + diagnosis(member['validation_detail'])
            evidence = member.get('evidence')
            if evidence:
                body += '<p>검토 기록: ' + ('시험용 응답' if evidence['review_synthetic'] else '실제 호출에 대한 호스트 기록') + '</p>'
                body += disclosure('검토 기록 상세', '<pre>' + esc(json.dumps(evidence, ensure_ascii=False, indent=2)) + '</pre>')
            else:
                body += '<p>현재 근거를 확인할 수 없습니다.</p>'
            body += '</article>'
        body += disclosure('영향과 후속 조치 상세', '<pre>' + esc(json.dumps(view.get('relations', []), ensure_ascii=False, indent=2)) + '</pre>')
        body += '<h2>게시 이력</h2><ul>' + ''.join('<li>' + esc(p['time']) + ' · ' + label(p['outcome']) + '</li>' for p in view['publication_history']) + '</ul>'
    else:
        documents = [{'path': d['path'], 'text': d['text'], 'repository': m['repository'],
                      'url': document_url(m['repository'], d['path'])}
                     for m in members for d in m.get('documents', [])]
        # Resolve against exact encoded routes in this request, never a filesystem path.
        document = next((d for d in documents if d['url'] == route), None)
        member = next((m for m in members if route == '/repositories/' + quote(m['repository'], safe='') + '/'), None)
        if document is None and member is None:
            raise KeyError('route')
        pages = markdown_pages(documents, markdown_it or os.environ.get('WIKI_MARKDOWN_IT_MODULE')) if documents else []
        by_url = {p['url']: p for p in pages}
        if document:
            page = by_url[route]
            heading = page['title']
            has_body_title = bool(page['headings'] and page['headings'][0]['level'] == 1)
            repository_url = '/repositories/' + quote(document['repository'], safe='') + '/'
            body = '<p class="breadcrumb"><a href="' + repository_url + '">' + esc(document['repository']) + '</a> / ' + esc(document['path']) + '</p>'
            body += '<nav class="toc" aria-label="이 문서의 목차"><strong>이 문서에서</strong>' + ''.join(
                '<a href="#' + quote(h['id'], safe='') + '">' + esc(h['title']) + '</a>' for h in page['headings']) + '</nav>'
            body += '<article class="document">' + page['html'] + '</article>'
            body += '<p><a href="/evidence/">근거와 확인 범위 보기</a></p>'
        else:
            heading = member['repository']
            body = member_facts(member) + '<h2>검토된 문서</h2>'
            selected = [d for d in documents if d['repository'] == member['repository']]
            if not selected:
                body += '<p>현재 권한·검증·게시 상태에서는 문서 본문을 제공하지 않습니다. 목표 개요와 근거를 확인하세요.</p>'
            for d in selected:
                page = by_url[d['url']]
                body += '<article><h3><a href="' + d['url'] + '">' + esc(page['title']) + '</a></h3><p class="path">' + esc(d['path']) + '</p></article>'
    return '''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>''' + esc(heading) + ''' · 지식 조회</title><link rel="stylesheet" href="/style.css"></head><body><a class="skip" href="#main">본문으로</a><header><strong>KNOWLEDGE</strong><span>현재 근거 조회</span><a href="/">새로 조회</a></header><div class="layout"><aside><p>읽기 안내</p><nav aria-label="저장소 탐색">''' + nav + '''</nav></aside><main id="main"><p class="eyebrow">''' + esc(view['goal']) + ' · 목표 ' + esc(view['version']) + '</p>' + ('' if has_body_title else '<h1>' + esc(heading) + '</h1>') + '''<p class="notice">페이지를 요청할 때 권한과 근거를 다시 확인합니다. 이미 읽거나 저장한 내용은 회수되지 않습니다.</p>''' + body + disclosure('조회 상태와 기술 근거', '<p>진단은 확인 순서상 첫 차단 원인입니다. 다음 조치는 안내이며, 실행·완료·게시를 뜻하지 않습니다.</p><p>목표 근거 ID: <code>' + esc(view['goal_hash']) + '</code></p><p>결과 ID: <code>' + esc(view['projection_id']) + '</code></p>') + '<footer><p>조회 시각: ' + esc(view['read_at']) + '</p></footer></main></div></body></html>'


def member_facts(member):
    body = '<dl class="facts">' + field('저장소 ID', esc(member['repository'])) + field('목표', esc(member.get('target', '확인 불가'))) + field('검증', label(member['validation'])) + '</dl>' + diagnosis(member['validation_detail'])
    return body + disclosure('현재 구현과 저장소 정보', '<dl class="facts">' + field('현재 코드 커밋', '<code>' + esc(member.get('current', {}).get('commit', '확인 불가')) + '</code>') + field('저장소 URL', esc(member.get('source_url', '확인 불가'))) + '</dl>')


def make_server(state, host, principal, goal, port, markdown_it=None):
    module = markdown_it or os.environ.get("WIKI_MARKDOWN_IT_MODULE")
    markdown_pages([], module)  # Fail at startup when the selected runtime is unavailable.
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # URLs may include reader text; keep it out of logs.

        def send(self, status, body, mime='text/html; charset=utf-8'):
            encoded = body.encode('utf-8')
            self.send_response(status)
            for key, value in {'Content-Type': mime, 'Content-Length': str(len(encoded)),
                               'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
                               'X-Content-Type-Options': 'nosniff',
                               'Content-Security-Policy': "default-src 'none'; style-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"}.items():
                self.send_header(key, value)
            self.end_headers()
            self.wfile.write(encoded)

        def do_GET(self):
            authority = '127.0.0.1:' + str(self.server.server_port)
            if self.headers.get('Host') != authority or self.headers.get('Origin', 'http://' + authority) != 'http://' + authority:
                self.send(403, '접근할 수 없습니다.', 'text/plain; charset=utf-8')
                return
            parsed = urlsplit(self.path)
            if parsed.scheme or parsed.netloc:
                self.send(400, '잘못된 요청입니다.', 'text/plain; charset=utf-8')
                return
            if parsed.path == '/style.css':
                self.send(200, Path(__file__).with_name('reader.css').read_text(), 'text/css; charset=utf-8')
                return
            params = parse_qs(parsed.query, keep_blank_values=True)
            if set(params) - {'q'} or any(len(v) != 1 for v in params.values()):
                self.send(400, '잘못된 요청입니다.', 'text/plain; charset=utf-8')
                return
            try:
                store = Store(state, host, principal)
                with store.locked(readonly=True):
                    view = store.reading({'goal': goal})
                if parsed.path == '/api/read':
                    self.send(200, json.dumps(view, ensure_ascii=False), 'application/json; charset=utf-8')
                else:
                    self.send(200, render(view, parsed.path, params.get('q', [''])[0], module))
            except KeyError:
                self.send(404, '페이지를 제공할 수 없습니다.', 'text/plain; charset=utf-8')
            except (OSError, ValueError, TypeError, ValidationError, sqlite3.Error, subprocess.SubprocessError):
                self.send(503, '현재 근거를 조회할 수 없습니다. 상태를 확인한 뒤 다시 조회하세요.', 'text/plain; charset=utf-8')

    return HTTPServer(('127.0.0.1', port), Handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--host', type=Path, required=True)
    parser.add_argument('--principal', required=True)
    parser.add_argument('--goal', required=True)
    parser.add_argument('--port', type=int, default=8774)
    parser.add_argument('--markdown-it', default=os.environ.get('WIKI_MARKDOWN_IT_MODULE'),
                        help='Absolute path to the prepared markdown-it module directory')
    args = parser.parse_args()
    if not 0 <= args.port <= 65535:
        parser.error('port must be between 0 and 65535')
    server = make_server(args.state, args.host, args.principal, args.goal, args.port, args.markdown_it)
    print('http://127.0.0.1:' + str(server.server_port), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
