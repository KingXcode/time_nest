import datetime as dt
from types import SimpleNamespace
import unittest

from tool.baostock_worker import fetch_batch
from tool.local_market import FIELDS, MarketError


NOW = dt.datetime(2026, 10, 18, 23, 40, tzinfo=dt.timezone.utc)


class Socket:
    closed = False
    def close(self):
        self.closed = True
    def settimeout(self, seconds):
        self.timeout = seconds


class Result:
    def __init__(self, code='0', row=None):
        self.error_code, self.error_msg = code, 'synthetic test response'
        self.fields = FIELDS.split(',')
        self.row = row
    def next(self):
        return self.row is not None
    def get_row_data(self):
        row, self.row = self.row, None
        return row


class Client:
    def __init__(self, fail_at=None):
        self.calls, self.fail_at = [], fail_at
    def login(self):
        self.calls.append('login')
        return Result('99' if self.fail_at == 'login' else '0')
    def query_history_k_data_plus(self, code, fields, **kwargs):
        self.calls.append(code)
        if code == self.fail_at:
            raise TimeoutError('synthetic provider timeout')
        assert fields == 'date,code,open,high,low,close,volume,amount'
        assert kwargs == dict(start_date='2026-09-19', end_date='2026-10-18', frequency='d', adjustflag='3')
        return Result(row=['2026-10-16', code, '100', '102', '99', '101', '1000', '100000'])
    def logout(self):
        self.calls.append('logout')
        return Result('99' if self.fail_at == 'logout' else '0')


class WorkerTests(unittest.TestCase):
    def test_three_queries_use_one_session_and_yesterdays_closed_window(self):
        client, context = Client(), SimpleNamespace(default_socket=Socket())
        result = fetch_batch(client, context, NOW)
        self.assertEqual(result.get('startDate'), '2026-09-19')
        self.assertEqual(result.get('endDate'), '2026-10-18')
        self.assertEqual(client.calls, ['login', 'sh.000001', 'sh.000300', 'sz.399001', 'logout'])
        self.assertTrue(context.default_socket.closed)
        self.assertEqual(result['indices']['sh.000001'][0]['close'], '101')

    def test_query_failure_still_logs_out_and_closes(self):
        client, context = Client('sh.000300'), SimpleNamespace(default_socket=Socket())
        with self.assertRaises(TimeoutError):
            fetch_batch(client, context, NOW)
        self.assertEqual(client.calls, ['login', 'sh.000001', 'sh.000300', 'logout'])
        self.assertTrue(context.default_socket.closed)

    def test_failed_login_never_queries(self):
        client, context = Client('login'), SimpleNamespace(default_socket=Socket())
        with self.assertRaises(MarketError):
            fetch_batch(client, context, NOW)
        self.assertEqual(client.calls, ['login', 'logout'])
        self.assertTrue(context.default_socket.closed)

    def test_failed_logout_still_closes_and_does_not_claim_success(self):
        client, context = Client('logout'), SimpleNamespace(default_socket=Socket())
        with self.assertRaises(MarketError):
            fetch_batch(client, context, NOW)
        self.assertTrue(context.default_socket.closed)


if __name__ == '__main__':
    unittest.main()
