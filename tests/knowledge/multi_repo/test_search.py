"""Search behavior and live authorization; fixture review receipts are synthetic."""
import json
import unittest
from urllib.parse import quote, unquote, urlsplit
from unittest.mock import patch
import test_reader
from search_fixture import published_fixture
from reader import search_documents, render


class SearchTests(unittest.TestCase):
    serve = test_reader.ReaderTests.serve
    request = test_reader.ReaderTests.request

    def search(self, port, query):
        status, headers, raw = self.request(port, '/api/search?q=' + quote(query))
        self.assertEqual(status, 200, raw)
        self.assertEqual(headers['Cache-Control'], 'no-store')
        return json.loads(raw)

    def test_fixed_questions_links_api_page_and_readonly(self):
        f = published_fixture(); port = self.serve(f)
        state = f.root/'state/state.json'; before = state.read_bytes()
        view = f.call('reading', {'goal':'contract'}, 'reader')
        for query, repository, anchor, expected in [
            ('금액 단위','producer','doc-금액','KRW'),
            ('변경 total','consumer','doc-변경-영향','amount'),
            ('운영 배포','consumer','doc-검증','검증하지 않았습니다'),
            ('재시도 상한','producer','doc-정책-2','3회'),
            ('total 120','producer','doc-예제','120')]:
            result = self.search(port, query)
            self.assertEqual(result['projection_id'], view['projection_id'])
            self.assertEqual(result['completion'], 'complete')
            self.assertEqual(len(result['results']), 1)
            hit = result['results'][0]
            self.assertEqual(hit['repository'], repository)
            self.assertEqual(hit['validation'], 'verified')
            self.assertTrue(hit['review_synthetic'])
            self.assertIn('commit', hit['current']); self.assertIn('total', hit['target'])
            self.assertIn(expected, hit['excerpt'])
            url = urlsplit(hit['url'])
            self.assertEqual(unquote(url.fragment), anchor)
            status, _, page = self.request(port, url.path)
            self.assertEqual(status, 200); self.assertIn('id="' + anchor + '"', page)
            html = self.request(port, '/search/?q=' + quote(query))[2]
            self.assertIn(hit['url'], html); self.assertIn(view['projection_id'], html)
        for query in ('', '   ', '양자결제', 'METADATA_ONLY_771', 'example.invalid'):
            self.assertEqual(self.search(port, query)['results'], [])
        self.assertEqual(state.read_bytes(), before)

    def test_text_only_unicode_titleless_and_stable_sections(self):
        f = published_fixture(); view = f.call('reading', {'goal':'contract'}, 'reader')
        member = view['members'][0]
        view['members'] = [member]
        member['target'] = 'METADATA_ONLY_771'
        member['documents'] = [
            {'path':'z.md','text':'# [표시 제목](https://heading.invalid)\n\n## 절\n\nＳＴＲＡＳＳＥ Straße **금액**\n\n[링크](https://url.invalid)\n\n![대체](https://image.invalid)\n\n| 표 | 값 |\n|---|---|\n| total | 120 |'},
            {'path':'a.md','text':'제목 없이 본문에 바늘이 있습니다.\n\n' + ('긴배경 ' * 100) + '끝바늘 정답'},
        ]
        for q in ('heading.invalid','url.invalid','image.invalid','METADATA_ONLY_771','a.md'):
            self.assertEqual(search_documents(view,q)['results'], [])
        for q in ('strasse 금액','STRASSE 금액','ＳＴＲＡＳＳＥ 금액','대체','total 120','표시 금액'):
            hits = search_documents(view,q)['results']
            self.assertEqual(len(hits),1,q)
            self.assertTrue(hits[0]['url'].endswith('#doc-%EC%A0%88'))
        hits = search_documents(view,'끝바늘')['results']
        self.assertIn('끝바늘', hits[0]['excerpt']); self.assertTrue(hits[0]['url'].endswith('/a.md/'))
        for query in ('<script>', '& "'):
            html = render(view, '/search/', query)
            self.assertNotIn('<script>',html)

    def test_same_server_fails_closed_after_change(self):
        for case in ('revoked','partial','withdrawn','drift','source_missing'):
            with self.subTest(case=case):
                f = published_fixture(); port = self.serve(f)
                self.assertTrue(self.search(port,'금액 단위')['results'])
                if case == 'revoked':
                    f.host['principals']['reader']['repositories']['consumer'] = ['query']; f.persist()
                elif case == 'partial':
                    f.update('consumer','amount')
                elif case == 'withdrawn':
                    f.goal.update(version='v2',status='withdrawn',origin=f.origin('user','withdrawn'));f.call('set_goal',f.goal)
                elif case == 'drift':
                    docs = f.root/('producer-search-docs-' + f.revisions['producer'])
                    (docs/'contract.md').write_text('unreviewed leaked body')
                else:
                    f.host['repositories']['consumer']['path'] = str(f.root/'missing'); f.persist()
                for query in ('금액 단위','변경 total'):
                    result = self.search(port,query)
                    self.assertEqual(result['results'],[])
                    self.assertEqual(result['completion'],'incomplete')
                    self.assertEqual(result['served'],'unavailable_or_partial')
                    self.assertNotIn('생산자 계약',json.dumps(result,ensure_ascii=False))
                self.assertEqual(self.request(port,'/documents/producer/contract.md/')[0],404)
                if case == 'revoked':
                    raw = self.request(port,'/api/search?q=total')[2]
                    self.assertNotIn('consumer',raw)
        # Missing source access for the entire goal is an error, not an empty success.
        f.host['principals']['reader']['goals'] = [];f.persist()
        self.assertEqual(self.request(port,'/api/search?q=total')[0],503)

    def test_runtime_failure_and_invalid_request(self):
        f = published_fixture(); port = self.serve(f)
        for route in ('/api/search?q=a&q=b','/api/search?principal=operator'):
            self.assertEqual(self.request(port,route)[0],400)
        with patch('reader.markdown_pages', side_effect=ValueError('private-path')):
            status, _, body = self.request(port,'/api/search?q=total')
            self.assertEqual(status,503);self.assertNotIn('private-path',body)

    def test_absent_or_stale_index_does_not_replace_current_projection(self):
        f = published_fixture(); port = self.serve(f)
        state = f.root/'state/state.json'
        for cached, expected in (({}, 'absent'), ({'contract':'0' * 64}, 'stale')):
            value = json.loads(state.read_text());value['index'] = cached
            state.write_text(json.dumps(value))  # Isolated index lag, without modifying approved bodies.
            before = state.read_bytes()
            result = self.search(port,'금액 단위')
            self.assertEqual(result['index'],expected)
            self.assertEqual(result['served'],'current')
            self.assertEqual(result['completion'],'complete')
            self.assertEqual(len(result['results']),1)
            self.assertEqual(state.read_bytes(),before)


if __name__ == '__main__':
    unittest.main()
