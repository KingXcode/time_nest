"""One short-lived anonymous session. Used only by the localhost service."""
import contextlib
import datetime as dt
import importlib.metadata
import json
import signal
import socket
import sys
import time

from tool.local_market import FIELDS, INDEX_CODES, SHANGHAI, UTC, MarketError, validate_snapshot


class DeadlineExceeded(BaseException):
    pass


@contextlib.contextmanager
def deadline(seconds):
    def expired(signum, frame):
        # BaoStock catches Exception internally; this must escape that handler.
        raise DeadlineExceeded('BaoStock operation deadline exceeded')
    previous = signal.signal(signal.SIGALRM, expired)
    signal.alarm(seconds)
    try:
        yield
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous)


def checked(result, operation):
    print(json.dumps({'operation': operation, 'error_code': result.error_code,
                      'error_msg': result.error_msg}, ensure_ascii=False), file=sys.stderr)
    if result.error_code != '0':
        raise MarketError('{} 返回错误码 {}。'.format(operation, result.error_code))


def fetch_batch(client, context, now):
    end = now.astimezone(SHANGHAI).date() - dt.timedelta(days=1)
    start = end - dt.timedelta(days=29)
    payload = {'fetchedAt': now.isoformat(), 'startDate': start.isoformat(),
               'endDate': end.isoformat(), 'timezone': 'Asia/Shanghai', 'indices': {}}
    problem = None
    try:
        with deadline(20):
            checked(client.login(), 'login')
        for index, code in enumerate(INDEX_CODES.values()):
            if index:
                time.sleep(1)
            with deadline(20):
                result = client.query_history_k_data_plus(
                    code, FIELDS, start_date=start.isoformat(), end_date=end.isoformat(),
                    frequency='d', adjustflag='3')
                checked(result, code)
                if result.fields != FIELDS.split(','):
                    raise MarketError('BaoStock 返回字段不匹配。')
                rows = []
                while result.error_code == '0' and result.next():
                    row = result.get_row_data()
                    if len(row) != len(result.fields) or len(rows) >= 30:
                        raise MarketError('BaoStock 返回行数或字段数异常。')
                    rows.append(dict(zip(result.fields, row)))
                if result.error_code != '0':
                    checked(result, code + ' rows')
                payload['indices'][code] = rows
                print(json.dumps({'index': code, 'rows': len(rows),
                                  'latest_date': rows[-1]['date'] if rows else None}), file=sys.stderr)
        validate_snapshot(payload, now)
    except BaseException as exc:
        problem = exc
        raise
    finally:
        conn = getattr(context, 'default_socket', None)
        if conn is not None:
            try:
                conn.settimeout(5)
                with deadline(8):
                    checked(client.logout(), 'logout')
            except BaseException:
                if problem is None:
                    raise
            finally:
                conn.close()
                print('BaoStock socket closed', file=sys.stderr)
    return payload


def main():
    import baostock as bs
    import baostock.common.context as context
    import baostock.common.contants as constants
    if sys.prefix == sys.base_prefix or importlib.metadata.version('baostock') != '0.9.4':
        raise MarketError('请使用安装 baostock 0.9.4 的任务专用 venv。')
    if (constants.BAOSTOCK_SERVER_IP, constants.BAOSTOCK_SERVER_PORT) != ('public-api.baostock.com', 10030):
        raise MarketError('仅允许官方公共节点。')
    if hasattr(context, 'apiKey'):
        raise MarketError('个人研究适配器不使用 API Key。')
    connects = []
    def audit(event, args):
        if event == 'socket.connect':
            if connects or args[1] != ('public-api.baostock.com', 10030):
                raise MarketError('每批次仅允许一次官方公共节点连接。')
            connects.append(args[1])
    sys.addaudithook(audit)
    socket.setdefaulttimeout(15)
    try:
        with contextlib.redirect_stdout(sys.stderr):
            payload = fetch_batch(bs, context, dt.datetime.now(UTC))
        print(json.dumps(payload, ensure_ascii=False, allow_nan=False))
        return 0
    except (Exception, DeadlineExceeded) as exc:
        print('{}: {}'.format(type(exc).__name__, exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
