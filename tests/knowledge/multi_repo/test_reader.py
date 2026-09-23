"""Real HTTP and CLI on isolated repositories; model receipts here are synthetic."""
import copy
import http.client
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import tempfile
import shutil
import unittest
from unittest.mock import patch

from test_multi_repo import Fixture, SCRIPTS
from multi_repo import Store
from reader import make_server, render, document_url, markdown_pages
from reading_fixture import published_fixture


class ReaderTests(unittest.TestCase):
    def serve(self, fixture):
        server = make_server(fixture.root/'state', fixture.host_path, 'reader', 'contract', 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 3)
        self.addCleanup(server.shutdown)
        return server.server_port

    def request(self, port, route='/', headers=None):
        conn = http.client.HTTPConnection('127.0.0.1', port, timeout=10)
        try:
            conn.request('GET', route, headers=headers or {})
            response = conn.getresponse()
            return response.status, dict(response.getheaders()), response.read().decode()
        finally:
            conn.close()

    def complete(self):
        f = Fixture(); f.complete()
        f.call('refresh', {'goal': 'contract'})
        f.call('publish', {'goal': 'contract', 'audience': 'reader'})
        return f

    def test_same_projection_cli_http_and_readonly_state(self):
        f = self.complete(); port = self.serve(f)
        state = f.root/'state/state.json'
        before = (state.read_bytes(), state.stat().st_mtime_ns)
        value = f.root/'read-input.json'; value.write_text('{"goal":"contract"}')
        result = subprocess.run([sys.executable, str(SCRIPTS/'multi_repo.py'), '--state', str(f.root/'state'),
            '--host', str(f.host_path), '--principal', 'reader', 'read', '--input', str(value)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        cli = json.loads(result.stdout)
        status, headers, body = self.request(port, '/api/read'); api = json.loads(body)
        self.assertEqual(status, 200)
        self.assertEqual(cli['projection_id'], api['projection_id'])
        self.assertEqual(api['completion'], 'complete')
        for route in ('/', '/repositories/producer/', '/repositories/consumer/', '/evidence/'):
            status, headers, body = self.request(port, route)
            self.assertEqual(status, 200)
            self.assertIn(api['projection_id'], body)
            self.assertEqual(headers['Cache-Control'], 'no-store')
            self.assertIn("frame-ancestors 'none'", headers['Content-Security-Policy'])
        self.assertEqual((state.read_bytes(), state.stat().st_mtime_ns), before)

    def test_six_states_and_live_reauthorization(self):
        for case in ('complete', 'partial', 'withdrawn', 'revoked', 'drift', 'check_failed'):
            with self.subTest(case=case):
                if case == 'partial':
                    f = Fixture(); f.update('producer', 'total')
                    f.call('run_checks', {'goal':'contract','checks':['producer']});f.review(['producer'])
                    f.call('refresh', {'goal':'contract'}); f.call('publish', {'goal':'contract','audience':'reader'})
                else:
                    f = self.complete()
                port = self.serve(f)
                self.request(port, '/')  # Same running server before and after changes.
                if case == 'withdrawn':
                    f.goal.update(version='v2',status='withdrawn',origin=f.origin('user','withdrawn')); f.call('set_goal',f.goal)
                elif case == 'revoked':
                    f.host['principals']['reader']['repositories']['consumer']=[]; f.persist()
                elif case == 'drift':
                    docs=f.root/('producer-docs-'+f.revisions['producer']); (docs/'contract.md').write_text('Unreviewed change')
                elif case == 'check_failed':
                    f.host['checks']['producer']['argv']=[sys.executable,'-c','raise SystemExit(1)']; f.persist()
                    f.call('run_checks', {'goal':'contract','checks':['producer']})
                status, _, raw = self.request(port, '/api/read'); self.assertEqual(status, 200)
                value=json.loads(raw)
                self.assertEqual(value['completion'], 'complete' if case == 'complete' else 'incomplete')
                self.assertEqual(value['served'], 'current' if case == 'complete' else 'unavailable_or_partial')
                self.assertEqual(self.request(port, '/documents/producer/contract.md/')[0], 200 if case == 'complete' else 404)
                page=self.request(port, '/')[2]
                self.assertIn(value['projection_id'],page)
                if case != 'complete':
                    self.assertTrue(all('documents' not in m for m in value['members']))
                if case == 'revoked':
                    self.assertNotIn('consumer', raw+page)
                    self.assertEqual(value['withheld_count'],1)
                    self.assertEqual(self.request(port,'/repositories/consumer/')[0],404)
                if case in ('withdrawn','drift','check_failed','revoked'):
                    self.assertEqual(value['index'],'stale')

    def test_single_permission_revocation_search_and_history(self):
        f=self.complete()
        f.call('predict',{'goal':'contract','origin':f.origin('user'),'affected':['consumer'],'rationale':'private'})
        port=self.serve(f)
        for rights in (['source','query'],['source','publish'],[]):
            f.host['principals']['reader']['repositories']['consumer']=rights; f.persist()
            for route in ('/api/read','/','/evidence/','/?q=consumer'):
                status, _, body=self.request(port,route)
                self.assertEqual(status,200)
                # Search text is reflected safely in its input, never as a result.
                if '?q=' not in route: self.assertNotIn('consumer',body)
                self.assertNotIn('consumer-secret',body)
                self.assertNotIn('https://consumer.invalid',body)
                self.assertNotIn('consumer uses total.',body)
            self.assertEqual(self.request(port,'/repositories/consumer/')[0],404)
        f.host['principals']['reader']['goals']=[]; f.persist()
        status, _, body=self.request(port,'/api/read')
        self.assertEqual(status,503);self.assertNotIn('consumer',body);self.assertNotIn(str(f.root),body)

    def test_transport_escape_and_no_request_authority(self):
        f=self.complete(); port=self.serve(f)
        for route in ('/?principal=operator','/?host=/private/file','/?goal=private','/?q=a&q=b'):
            self.assertEqual(self.request(port,route)[0],400)
        for route in ('/state.json','/objects/anything','/../host.json','/repositories/absent/'):
            self.assertEqual(self.request(port,route)[0],404)
        self.assertEqual(self.request(port,'/',{'Host':'evil.invalid'})[0],403)
        self.assertEqual(self.request(port,'/',{'Origin':'http://evil.invalid'})[0],403)
        raw=self.request(port,'/?q=%3Cscript%3Ealert(1)%3C/script%3E')[2]
        self.assertNotIn('<script>',raw); self.assertIn('&lt;script&gt;',raw)
        view=f.call('reading',{'goal':'contract'},'reader')
        next(m for m in view['members'] if m['repository']=='producer')['documents'][0]['text']='<img src=x onerror=alert(1)>'
        from reader import render
        html=render(view,'/documents/producer/contract.md/')
        self.assertNotIn('<img',html);self.assertIn('&lt;img',html)

    def test_document_routes_markup_and_reauthorization(self):
        f = published_fixture(); port = self.serve(f)
        url = '/documents/producer/contract.md/'
        view = f.call('reading', {'goal': 'contract'}, 'reader')
        status, headers, html = self.request(port, url)
        self.assertEqual(status, 200)
        self.assertIn(view['projection_id'], html)
        for value in ('<table>', '<code class="language-json">', 'id="doc-금액-2"',
                      '/documents/producer/guide.md/#doc-%EA%B2%80%EC%A6%9D',
                      '<span class="unavailable-link"', 'aria-label="이 문서의 목차"'):
            self.assertIn(value, html)
        self.assertNotIn('href="private.md"', html)
        self.assertIn('href="' + url + '"', self.request(port, '/repositories/producer/')[2])
        self.assertNotIn('<table>', self.request(port, '/repositories/producer/')[2])
        evidence = self.request(port, '/evidence/')[2]
        self.assertIn('<details class="technical"><summary>검토 기록 상세', evidence)
        self.assertIn('시험용 응답', evidence)
        self.assertIn('운영 배포를 증명하지 않습니다', evidence)
        # Already visited URLs cannot bypass a fresh permission or source decision.
        for rights in (['source', 'query'], ['source', 'publish'], []):
            f.host['principals']['reader']['repositories']['producer'] = rights; f.persist()
            status, _, html = self.request(port, url)
            self.assertEqual(status, 404)
            self.assertNotIn('total', html)
        f.host['principals']['reader']['repositories']['producer'] = ['source', 'query', 'publish']; f.persist()
        self.assertEqual(self.request(port, url)[0], 200)
        docs = f.root / ('producer-reading-docs-' + f.revisions['producer'])
        original = (docs/'contract.md').read_text()
        (docs/'contract.md').write_text('Unreviewed body')
        self.assertEqual(self.request(port, url)[0], 404)
        (docs/'contract.md').write_text(original)
        self.assertEqual(self.request(port, url)[0], 200)
        f.goal.update(version='v2', status='withdrawn', origin=f.origin('user','withdrawn')); f.call('set_goal', f.goal)
        self.assertEqual(self.request(port, url)[0], 404)
        for bad in ('/documents/producer/../host.json/', '/documents/producer/%2e%2e%2fhost.json/',
                    '/documents/producer/%ZZ/', '/documents/absent/contract.md/'):
            self.assertEqual(self.request(port, bad)[0], 404)

    def test_markdown_link_boundary_and_runtime_failure(self):
        module = os.environ['WIKI_MARKDOWN_IT_MODULE']
        docs = [
            {'repository': 'a', 'path': 'dir/계약 문서.md', 'url': document_url('a', 'dir/계약 문서.md'),
             'text': '# main\n\n## 금액\n\n## 금액\n\n'
                     '[허용](../guide.md#검증) [중복](#금액-2) [없는절](#missing) '
                     '[탈출](../../secret.md) [잘못](%ZZ.md) [망](//evil.invalid) '
                     '[다른저장소](../../b/guide.md) [외부](https://example.invalid) '
                     '[위험](javascript:alert(1)) [데이터](data:text/html,evil)\n\n'
                     '<script>alert(1)</script> ![대체](https://evil.invalid/image)\n'},
            {'repository': 'a', 'path': 'guide.md', 'url': document_url('a', 'guide.md'), 'text': '# 안내\n\n## 검증'},
            {'repository': 'b', 'path': 'guide.md', 'url': document_url('b', 'guide.md'), 'text': '# 다른 안내'},
        ]
        docs[1]['text'] += '\n\n[인코딩된 문서 주소](' + docs[0]['url'] + '#금액)'
        pages = markdown_pages(docs, module)
        self.assertIn(docs[0]['url'] + '#doc-%EA%B8%88%EC%95%A1', pages[1]['html'])
        html = pages[0]['html']
        for expected in ('/documents/a/guide.md/#doc-%EA%B2%80%EC%A6%9D', '#doc-%EA%B8%88%EC%95%A1-2',
                         'id="doc-main"', 'https://example.invalid', '&lt;script&gt;', '[이미지: 대체]'):
            self.assertIn(expected, html)
        for unsafe in ('<script>', '<img', 'href="javascript:', 'href="data:', 'href="//', '/documents/b/', 'src='):
            self.assertNotIn(unsafe, html)
        self.assertEqual(html.count('<span '), html.count('</span>'))
        with self.assertRaises(ValueError): markdown_pages([], None)
        with self.assertRaises(subprocess.CalledProcessError): markdown_pages([], '/missing-runtime')
        f = published_fixture(); port = self.serve(f)
        for error in (subprocess.TimeoutExpired('node',10), ValueError('bad-output'), OSError('private-path')):
            with patch('reader.markdown_pages', side_effect=error):
                status, _, html = self.request(port, '/documents/producer/contract.md/')
                self.assertEqual(status, 503)
                self.assertNotIn('private-path', html)
                self.assertNotIn('total', html)
        with patch('reader.subprocess.run', return_value=type('R', (), {'stdout':'{}'})()):
            with self.assertRaises(ValueError): markdown_pages(docs, module)

    def test_link_repository_boundary_negative_control(self):
        module = os.environ['WIKI_MARKDOWN_IT_MODULE']
        docs = [{'repository':'a','path':'contract.md','url':document_url('a','contract.md'),
                 'text':'[다른 저장소 문서](guide.md)'},
                {'repository':'b','path':'guide.md','url':document_url('b','guide.md'),'text':'# hidden target'}]
        self.assertNotIn('/documents/b/', markdown_pages(docs, module)[0]['html'])
        scratch = Path(tempfile.mkdtemp(prefix='knowledge-link-negative-'))
        source = (SCRIPTS/'wiki/managed.mjs').read_text()
        needle = 'p.repository === page.repository && '
        self.assertEqual(source.count(needle), 1)
        (scratch/'managed.mjs').write_text(source.replace(needle, ''))
        shutil.copyfile(SCRIPTS/'wiki/markdown.mjs', scratch/'markdown.mjs')
        result = subprocess.run(['node',str(scratch/'managed.mjs'),module], input=json.dumps(docs),
                                capture_output=True,text=True,check=True)
        self.assertIn('/documents/b/guide.md/', json.loads(result.stdout)[0]['html'])

    def test_change_during_read_fails_closed(self):
        f=self.complete(); store=Store(f.root/'state',f.host_path,'reader')
        original=Store.query
        def changed(instance,value,**kwargs):
            result=original(instance,value,**kwargs);result['members'][0]['current']['commit']='0'*40;return result
        with store.locked(readonly=True), patch.object(Store,'query',changed):
            with self.assertRaisesRegex(ValueError,'READ_CHANGED'):store.reading({'goal':'contract'})
        def changed_policy(instance,value,**kwargs):
            result=original(instance,value,**kwargs);f.host['principals']['reader']['repositories']['consumer']=[];f.persist();return result
        with store.locked(readonly=True), patch.object(Store,'query',changed_policy):
            with self.assertRaisesRegex(ValueError,'READ_CHANGED'):store.reading({'goal':'contract'})

    def test_diagnostics_recovery_and_legacy_publication(self):
        f=self.complete(); port=self.serve(f)
        query_before=f.call('query',{'goal':'contract'},'reader')
        wiki_before=f.call('wiki',{'goal':'contract'},'reader')
        def current():
            status,_,raw=self.request(port,'/api/read'); self.assertEqual(status,200)
            return json.loads(raw)
        def producer(view):
            return next(m for m in view['members'] if m['repository']=='producer')
        initial=current()
        self.assertEqual(initial['index'],'current');self.assertEqual(initial['served'],'current')
        self.assertEqual(producer(initial)['validation_detail']['code'],'verified')
        self.assertEqual(f.call('query',{'goal':'contract'},'reader'),query_before)
        self.assertEqual(f.call('wiki',{'goal':'contract'},'reader'),wiki_before)
        doc=f.root/('producer-docs-'+f.revisions['producer'])/'contract.md'
        original=doc.read_text();doc.write_text('changed')
        drift=current()
        self.assertEqual(producer(drift)['validation_detail'],{'stage':'documents',
            'code':'document_evidence_changed','next_action':'update_and_review_documents'})
        for route in ('/','/repositories/producer/','/evidence/'):
            self.assertIn('문서와 검토된 근거가 일치하지 않음',self.request(port,route)[2])
        doc.write_text(original)
        self.assertEqual(current()['projection_id'],initial['projection_id'])
        command=copy.deepcopy(f.host['checks']['producer'])
        f.host['checks']['producer']['argv']=[sys.executable,'-B','-c',
            "import sys; print('PRIVATE_DIAGNOSTIC_PATH',file=sys.stderr); raise SystemExit(1)"]
        f.persist();f.call('run_checks',{'goal':'contract','checks':['producer']})
        failed=current()
        self.assertEqual(producer(failed)['validation_detail']['code'],'check_failed')
        self.assertNotEqual(failed['projection_id'],drift['projection_id'])
        self.assertNotIn('PRIVATE_DIAGNOSTIC_PATH',json.dumps(failed))
        self.assertNotIn(str(f.root),json.dumps(failed))
        f.host['checks']['producer']=command;f.persist()
        self.assertEqual(producer(current())['validation_detail']['code'],'check_stale')
        f.call('run_checks',{'goal':'contract','checks':['producer']})
        self.assertEqual(producer(current())['validation_detail']['code'],'review_pending')
        f.review()
        reviewed=current();self.assertEqual(reviewed['completion'],'complete')
        self.assertEqual(reviewed['served'],'unavailable_or_partial')
        f.call('refresh',{'goal':'contract'});f.call('publish',{'goal':'contract','audience':'reader'})
        self.assertEqual(current()['served'],'current')

    def test_diagnostics_missing_unknown_integration_and_withheld(self):
        f=Fixture();f.update('producer','total');f.update('consumer','total')
        view=f.call('reading',{'goal':'contract'},'reader')
        self.assertTrue(all(m['validation_detail']['code']=='check_pending' for m in view['members']))
        f.call('run_checks',{'goal':'contract','checks':['producer','consumer','exchange']});f.review()
        f.host['checks']['exchange']['argv']=[sys.executable,'-B','-c','raise SystemExit(1)'];f.persist()
        f.call('run_checks',{'goal':'contract','checks':['exchange']})
        view=f.call('reading',{'goal':'contract'},'reader')
        self.assertTrue(all(m['validation']=='verified' for m in view['members']))
        self.assertEqual(view['completion'],'incomplete')
        self.assertEqual(view['integration_detail']['code'],'check_failed')
        for right in ('source','query','publish'):
            f.host['principals']['reader']['repositories']['producer']=[r for r in ('source','query','publish') if r!=right];f.persist()
            view=f.call('reading',{'goal':'contract'},'reader')
            self.assertEqual(view['integration_detail']['code'],'withheld')
            self.assertNotIn('producer',json.dumps(view));self.assertNotIn('check_failed',json.dumps(view))
        f.host['principals']['reader']['repositories']['producer']=['source','query','publish'];f.persist()
        with patch.object(Store,'documents',side_effect=ValueError('PRIVATE /hidden/member command-output')):
            view=f.call('reading',{'goal':'contract'},'reader')
        self.assertTrue(all(m['validation_detail']=={'stage':'documents','code':'evidence_unavailable',
            'next_action':'ask_host_to_inspect_evidence'} for m in view['members']))
        self.assertNotIn('PRIVATE',json.dumps(view));self.assertNotIn('/hidden',json.dumps(view))

    def test_diagnostic_change_between_projections_is_rejected(self):
        f=self.complete();store=Store(f.root/'state',f.host_path,'reader')
        original=Store.query
        def changed(instance,value,**kwargs):
            result=original(instance,value,**kwargs)
            kwargs['diagnostics']['members']['producer']['code']='check_failed'
            return result
        with store.locked(readonly=True),patch.object(Store,'query',changed):
            with self.assertRaisesRegex(ValueError,'READ_CHANGED'):store.reading({'goal':'contract'})

    def test_dirty_source_then_document_update_pending(self):
        f=self.complete();repo=f.root/'producer'
        (repo/'app.py').write_text("value = 'new contract'\n")
        def detail():
            view=f.call('reading',{'goal':'contract'},'reader')
            return next(m['validation_detail'] for m in view['members'] if m['repository']=='producer')
        self.assertEqual(detail()['code'],'source_dirty')
        f.git(repo,'add','app.py');f.git(repo,'commit','-qm','New source without document update')
        self.assertEqual(detail(),{'stage':'documents','code':'documents_pending',
            'next_action':'update_and_review_documents'})


if __name__ == '__main__':
    unittest.main()
