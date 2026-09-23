#!/usr/bin/env python3
"""Serve one host-selected managed knowledge goal on loopback; no publication writes."""
import argparse
from html import escape
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import sqlite3
import subprocess
from urllib.parse import quote, unquote, urlsplit, parse_qs

from jsonschema.exceptions import ValidationError
from multi_repo import Store

LABELS = {'complete': '완료', 'incomplete': '미완료', 'active': '진행 중',
          'withdrawn': '철회', 'deferred': '보류', 'verified': '검증됨',
          'pending': '검증 대기', 'pending_or_stale': '검증 대기 또는 오래됨',
          'source_unavailable': '소스 확인 불가', 'current': '현재 근거와 일치',
          'stale': '오래됨', 'absent': '없음', 'unavailable_or_partial': '본문 미제공',
          'published': '게시됨', 'partial': '부분 게시', 'failed': '실패'}


def esc(value):
    return escape(str(value), quote=True)


def label(value):
    return esc(LABELS.get(value, value))


def field(name, value):
    return '<div><dt>' + esc(name) + '</dt><dd>' + value + '</dd></div>'


def render(view, route, search=''):
    """Render only the public reading projection; never load repository documents."""
    members = view['members']
    nav = '<a href="/">목표 개요</a><a href="/evidence/">근거와 확인 범위</a>'
    for member in members:
        nav += '<a href="/repositories/' + quote(member['repository'], safe='') + '/">' + esc(member['repository']) + '</a>'
    heading, body = '목표 개요', ''
    if route == '/':
        body = '<dl class="facts">' + ''.join([
            field('목표 상태', label(view['status'])), field('전체 완료', label(view['completion'])),
            field('필수 저장소', str(view['required_count'])), field('비공개 필수 저장소', str(view['withheld_count'])),
            field('통합 검증', label(view['integration'])), field('문서 제공', label(view['served']))]) + '</dl>'
        body += '<h2>저장소별 현재와 목표</h2><form action="/" method="get"><label for="q">허용된 결과에서 찾기</label><input id="q" name="q" value="' + esc(search) + '"><button>찾기</button></form>'
        matches = [m for m in members if search.casefold() in json.dumps(m, ensure_ascii=False).casefold()]
        body += '<p>표시 ' + str(len(matches)) + ' / 접근 가능 ' + str(len(members)) + '개 · 검색은 전체 완료 판정을 바꾸지 않습니다.</p>'
        for member in matches:
            body += '<article><h3><a href="/repositories/' + quote(member['repository'], safe='') + '/">' + esc(member['repository']) + '</a></h3>' + member_facts(member) + '</article>'
    elif route == '/evidence/':
        heading = '근거와 확인 범위'
        body = '<dl class="facts">' + field('조회 색인', label(view['index'])) + field('결과 ID', '<code>' + esc(view['projection_id']) + '</code>') + field('목표 근거 ID', '<code>' + esc(view['goal_hash']) + '</code>') + '</dl>'
        body += '<p>색인의 최신성, 문서 제공 여부, 구현 검증은 서로 다른 상태입니다. 로컬 검증은 운영 배포를 증명하지 않습니다.</p>'
        for member in members:
            body += '<article><h2>' + esc(member['repository']) + '</h2>'
            evidence = member.get('evidence')
            if evidence:
                body += '<p>검토 기록: ' + ('시험용 응답' if evidence['review_synthetic'] else '실제 호출에 대한 호스트 기록') + '</p><pre>' + esc(json.dumps(evidence, ensure_ascii=False, indent=2)) + '</pre>'
            else:
                body += '<p>현재 근거를 확인할 수 없습니다.</p>'
            body += '</article>'
        body += '<h2>영향과 후속 조치</h2><pre>' + esc(json.dumps(view.get('relations', []), ensure_ascii=False, indent=2)) + '</pre>'
        body += '<h2>게시 이력</h2><pre>' + esc(json.dumps(view['publication_history'], ensure_ascii=False, indent=2)) + '</pre>'
    else:
        prefix = '/repositories/'
        if not route.startswith(prefix) or not route.endswith('/'):
            raise KeyError('route')
        identity = unquote(route[len(prefix):-1])
        member = next((m for m in members if m['repository'] == identity), None)
        if member is None:
            raise KeyError('route')
        heading = identity
        body = member_facts(member) + '<h2>검토된 문서</h2>'
        if not member.get('documents'):
            body += '<p>현재 권한·검증·게시 상태에서는 문서 본문을 제공하지 않습니다. 목표 개요와 근거를 확인하세요.</p>'
        for document in member.get('documents', []):
            body += '<article><h3>' + esc(document['path']) + '</h3><pre class="document">' + esc(document['text']) + '</pre></article>'
    return '''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>''' + esc(heading) + ''' · 지식 조회</title><link rel="stylesheet" href="/style.css"></head><body><a class="skip" href="#main">본문으로</a><header><strong>KNOWLEDGE</strong><span>현재 근거 조회</span><a href="/">새로 조회</a></header><div class="layout"><aside><p>읽기 안내</p><nav>''' + nav + '''</nav></aside><main id="main"><p class="eyebrow">''' + esc(view['goal']) + ' · 목표 ' + esc(view['version']) + '''</p><h1>''' + esc(heading) + '''</h1><p class="notice">페이지를 요청할 때 권한과 근거를 다시 확인합니다. 이미 읽거나 저장한 내용은 회수되지 않습니다.</p>''' + body + '''<footer><p>조회 시각: ''' + esc(view['read_at']) + '''</p><details><summary>이 화면의 결과 식별자</summary><code>''' + esc(view['projection_id']) + '''</code></details></footer></main></div></body></html>'''


def member_facts(member):
    return '<dl class="facts">' + field('저장소 ID', esc(member['repository'])) + field('현재 코드 커밋', '<code>' + esc(member.get('current', {}).get('commit', '확인 불가')) + '</code>') + field('목표', esc(member.get('target', '확인 불가'))) + field('검증', label(member['validation'])) + field('저장소 URL', esc(member.get('source_url', '확인 불가'))) + '</dl>'


def make_server(state, host, principal, goal, port):
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
                    self.send(200, render(view, parsed.path, params.get('q', [''])[0]))
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
    args = parser.parse_args()
    if not 0 <= args.port <= 65535:
        parser.error('port must be between 0 and 65535')
    server = make_server(args.state, args.host, args.principal, args.goal, args.port)
    print('http://127.0.0.1:' + str(server.server_port), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
