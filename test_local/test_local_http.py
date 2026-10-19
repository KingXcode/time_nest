import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest

from tool.local_market import create_server, MarketError
from test_local.test_market_cache import fixture


class Cache:
    def __init__(self):
        self.calls = []
        self.stale = False
        self.fail = False
    def get(self, refresh=False):
        self.calls.append(refresh)
        if self.fail:
            raise MarketError('synthetic failure')
        return dict(payload=fixture(), cached=True, stale=self.stale)


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.build = self.root / 'web'
        self.build.mkdir()
        (self.build / 'index.html').write_text('<html>local test</html>')
        (self.root / 'outside.txt').write_text('not web content')
        (self.build / 'escape.txt').symlink_to(self.root / 'outside.txt')
        self.cache = Cache()
        self.server = create_server(self.build, self.cache)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop)
        self.port = self.server.server_port

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, path, headers=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=2)
        try:
            connection.request('GET', path, headers=headers or {})
            result = connection.getresponse()
            return result.status, dict(result.getheaders()), result.read()
        finally:
            connection.close()

    def test_same_origin_index_returns_daily_contract_and_real_session_date(self):
        status, headers, body = self.request('/api/market-history?index=shanghai')
        self.assertEqual(status, 200)
        data = json.loads(body)
        self.assertEqual(data['indexId'], 'shanghai')
        self.assertEqual(data['code'], 'sh.000001')
        self.assertEqual(data['rows'], [{'date': '2026-10-16', 'close': 101.0}])
        self.assertEqual(data['fetchedAt'], '2026-10-18T23:40:00+00:00')
        self.assertEqual(data['freshness'], 'unverified')
        self.assertEqual(headers['Cache-Control'], 'no-store')
        self.assertNotIn('Access-Control-Allow-Origin', headers)

    def test_refresh_and_stale_cache_are_not_relabelled_as_current(self):
        self.cache.stale = True
        status, _, body = self.request('/api/market-history?index=csi300&refresh=1')
        self.assertEqual(status, 200)
        self.assertEqual(self.cache.calls, [True])
        data = json.loads(body)
        self.assertEqual(data['freshness'], 'stale')
        self.assertEqual(data['fetchedAt'], '2026-10-18T23:40:00+00:00')

    def test_arbitrary_symbols_urls_and_duplicate_parameters_never_fetch(self):
        for path in ['/api/market-history?index=star50',
                     '/api/market-history?index=shanghai&url=https://example.com',
                     '/api/market-history?index=shanghai&index=csi300',
                     '/api/market-history?index=shanghai&refresh=yes']:
            self.assertEqual(self.request(path)[0], 400)
        self.assertEqual(self.cache.calls, [])

    def test_foreign_origin_host_and_cross_site_requests_are_rejected(self):
        for headers in [{'Origin': 'https://example.com'},
                        {'Host': 'example.com:' + str(self.port)},
                        {'Sec-Fetch-Site': 'cross-site'}]:
            self.assertEqual(self.request('/api/market-history?index=shanghai', headers)[0], 403)
        self.assertEqual(self.cache.calls, [])

    def test_static_files_cannot_escape_web_root(self):
        status, _, body = self.request('/')
        self.assertEqual(status, 200)
        self.assertIn(b'local test', body)
        for path in ['/../outside.txt', '/%2e%2e/outside.txt', '/escape.txt']:
            self.assertEqual(self.request(path)[0], 403)

    def test_upstream_failure_is_a_retriable_error_not_fake_rows(self):
        self.cache.fail = True
        status, _, body = self.request('/api/market-history?index=shenzhen')
        self.assertEqual(status, 503)
        self.assertIn('error', json.loads(body))
        self.assertNotIn('rows', json.loads(body))

    def test_bind_cannot_be_changed_to_lan_or_public(self):
        try:
            other = create_server(self.build, self.cache, host='0.0.0.0')
        except MarketError:
            return
        other.server_close()
        self.fail('Non-loopback bind was accepted')


if __name__ == '__main__':
    unittest.main()
