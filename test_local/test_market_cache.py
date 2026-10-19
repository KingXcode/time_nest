"""Synthetic fixtures only. Tests never contact BaoStock."""
import copy
import datetime as dt
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor

from tool.local_market import MarketCache, MarketError, validate_snapshot


NOW = dt.datetime(2026, 10, 18, 23, 40, tzinfo=dt.timezone.utc)


def fixture(at=NOW):
    # Deliberately synthetic values, not captured market records.
    return {
        'fetchedAt': at.isoformat(), 'startDate': '2026-09-19',
        'endDate': '2026-10-18', 'timezone': 'Asia/Shanghai',
        'indices': {
            code: [dict(date='2026-10-16', code=code, open='100', high='102',
                        low='99', close='101', volume='1000', amount='100000')]
            for code in ('sh.000001', 'sh.000300', 'sz.399001')
        },
    }


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.clock = [NOW]
        self.fetches = 0

    def fetch(self):
        self.fetches += 1
        return fixture(self.clock[0])

    def cache(self, fetch=None, **options):
        return MarketCache(self.path, fetch or self.fetch, lambda: self.clock[0], **options)

    def test_disk_cache_survives_a_new_service_instance(self):
        first = self.cache().get()
        second = self.cache().get()
        self.assertEqual(first.get('payload'), fixture())
        self.assertEqual(second.get('payload'), fixture())
        self.assertEqual(self.fetches, 1)
        self.assertIs(first.get('cached'), False)
        self.assertIs(second.get('cached'), True)

    def test_simultaneous_requests_share_one_provider_session(self):
        active = 0
        peak = 0
        guard = threading.Lock()
        def fetch():
            nonlocal active, peak
            with guard:
                active += 1
                peak = max(peak, active)
            try:
                time.sleep(.06)
                return self.fetch()
            finally:
                with guard:
                    active -= 1
        caches = [self.cache(fetch) for _ in range(4)]
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda cache: cache.get(), caches))
        self.assertEqual(self.fetches, 1)
        self.assertEqual(peak, 1)
        self.assertEqual([item.get('payload') for item in results], [fixture()] * 4)

    def test_forced_refresh_is_cooled_down_but_later_refreshes(self):
        cache = self.cache()
        cache.get()
        self.clock[0] += dt.timedelta(seconds=10)
        cache.get(refresh=True)
        self.assertEqual(self.fetches, 1)
        self.clock[0] += dt.timedelta(seconds=60)
        result = cache.get(refresh=True)
        self.assertEqual(self.fetches, 2)
        self.assertEqual(result.get('payload', {}).get('fetchedAt'), self.clock[0].isoformat())

    def test_failed_refresh_retains_original_timestamp_and_flags_stale(self):
        cache = self.cache()
        cache.get()
        self.clock[0] += dt.timedelta(minutes=20)
        def fail():
            raise MarketError('synthetic upstream failure')
        result = self.cache(fail).get()
        self.assertEqual(result.get('payload', {}).get('fetchedAt'), NOW.isoformat())
        self.assertIs(result.get('cached'), True)
        self.assertIs(result.get('stale'), True)
        self.assertTrue(result.get('warning'))
        # An immediate repeat must still say stale, not relabel the failed refresh.
        repeated = self.cache(fail).get()
        self.assertIs(repeated.get('stale'), True)

    def test_failure_without_cache_is_an_error_and_has_a_retry_cooldown(self):
        attempts = []
        def fail():
            attempts.append(1)
            raise MarketError('synthetic upstream failure')
        cache = self.cache(fail)
        for _ in range(2):
            with self.assertRaises(MarketError):
                cache.get()
        self.assertEqual(len(attempts), 1)

    def test_corrupt_cache_is_not_served_and_invalid_fetch_is_not_saved(self):
        (self.path / 'snapshot.json').write_text('{broken')
        bad = fixture()
        bad['indices']['sh.000001'][0]['close'] = 'NaN'
        with self.assertRaises(MarketError):
            self.cache(lambda: bad).get()
        self.assertEqual((self.path / 'snapshot.json').read_text(), '{broken')

    def test_week_old_cache_is_not_used_when_provider_fails(self):
        self.cache().get()
        self.clock[0] += dt.timedelta(days=8)
        def fail():
            raise MarketError('synthetic upstream failure')
        with self.assertRaises(MarketError):
            self.cache(fail).get()

    def test_cache_inside_repository_is_rejected(self):
        with self.assertRaises(MarketError):
            MarketCache(Path(__file__).resolve().parents[1] / 'private-cache', self.fetch, lambda: NOW)


class ValidationTests(unittest.TestCase):
    def test_valid_synthetic_records_keep_exchange_dates(self):
        self.assertIsNone(validate_snapshot(fixture(), NOW))

    def test_wrong_identity_invalid_dates_nonfinite_and_bad_ohlc_are_rejected(self):
        for field, value in [('code', 'sz.399001'), ('date', '2026-02-30'),
                             ('date', '2026-10-19'), ('close', 'inf'),
                             ('high', '99'), ('volume', '-1')]:
            with self.subTest(field=field, value=value):
                bad = fixture()
                bad['indices']['sh.000001'][0][field] = value
                with self.assertRaises(MarketError):
                    validate_snapshot(bad, NOW)
        bad = fixture()
        bad['indices']['sh.000001'] *= 2
        with self.assertRaises(MarketError):
            validate_snapshot(bad, NOW)
        bad = fixture()
        bad['fetchedAt'] = '2026-10-19T07:40:00'  # No timezone: never guess.
        with self.assertRaises(MarketError):
            validate_snapshot(bad, NOW)


if __name__ == '__main__':
    unittest.main()
