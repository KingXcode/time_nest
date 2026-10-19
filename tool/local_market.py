"""Local-only market service; provider cache lives outside the repository."""
import contextlib
import datetime as dt
import fcntl
import argparse
import json
import math
from http.server import BaseHTTPRequestHandler, HTTPServer
import mimetypes
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import parse_qs, unquote, urlsplit


UTC = dt.timezone.utc
SHANGHAI = dt.timezone(dt.timedelta(hours=8))
INDEX_CODES = {'shanghai': 'sh.000001', 'csi300': 'sh.000300', 'shenzhen': 'sz.399001'}
FIELDS = 'date,code,open,high,low,close,volume,amount'
PROJECT_ROOT = Path(__file__).resolve().parents[1]


def create_server(build_directory, cache, port=0, host='127.0.0.1'):
    if host != '127.0.0.1':
        raise MarketError('个人研究服务只能监听 127.0.0.1。')
    root = Path(build_directory).resolve()
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(5)

        def _json(self, status, data):
            raw = json.dumps(data, ensure_ascii=False, allow_nan=False).encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Length', str(len(raw)))
            if status == 503:
                self.send_header('Retry-After', '60')
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self):
            self._serve()

        def do_HEAD(self):
            self._serve(head=True)

        def _serve(self, head=False):
            host_header = self.headers.get('Host', '')
            allowed = {'127.0.0.1:' + str(self.server.server_port),
                       'localhost:' + str(self.server.server_port)}
            if (host_header not in allowed
                    or self.headers.get('Origin', 'http://' + host_header) != 'http://' + host_header
                    or self.headers.get('Sec-Fetch-Site') == 'cross-site'):
                self._json(403, {'error': '仅允许本机同源访问。'})
                return
            url = urlsplit(self.path)
            if url.scheme or url.netloc or not url.path.startswith('/'):
                self._json(400, {'error': '请求路径无效。'})
                return
            if url.path == '/health':
                self._json(200, {'service': 'time-nest-local', 'indices': list(INDEX_CODES)})
                return
            if url.path == '/api/market-history':
                if head:
                    self._json(405, {'error': '此接口仅支持 GET。'})
                    return
                args = parse_qs(url.query, keep_blank_values=True)
                if (set(args) - {'index', 'refresh'}
                        or args.get('index', []) not in [[key] for key in INDEX_CODES]
                        or args.get('refresh', ['0']) not in [['0'], ['1']]):
                    self._json(400, {'error': '仅支持三个固定指数的日线请求。'})
                    return
                try:
                    result = cache.get(refresh=args.get('refresh') == ['1'])
                    payload = result['payload']
                    index_id = args['index'][0]
                    code = INDEX_CODES[index_id]
                    self._json(200, {
                        'schemaVersion': 1, 'indexId': index_id, 'code': code,
                        'frequency': 'd', 'timezone': 'Asia/Shanghai',
                        'startDate': payload['startDate'], 'endDate': payload['endDate'],
                        'fetchedAt': payload['fetchedAt'], 'cached': result['cached'],
                        'freshness': 'stale' if result['stale'] else 'unverified',
                        'warning': result.get('warning'),
                        'rows': [{'date': row['date'], 'close': float(row['close'])}
                                 for row in payload['indices'][code]],
                    })
                except MarketError as exc:
                    self._json(503, {'error': str(exc)})
                return
            path = (root / unquote(url.path).lstrip('/')).resolve()
            if path == root:
                path = root / 'index.html'
            if not path.is_relative_to(root):
                self._json(403, {'error': '此路径不属于应用文件。'})
                return
            if not path.is_file():
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', mimetypes.guess_type(path)[0] or 'application/octet-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('Content-Length', str(path.stat().st_size))
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.end_headers()
            if not head:
                with path.open('rb') as handle:
                    shutil.copyfileobj(handle, self.wfile)
    # Deliberately single-threaded. The file lock also protects separate launches.
    return HTTPServer((host, port), Handler)


def fetch_worker():
    try:
        result = subprocess.run(
            [sys.executable, '-m', 'tool.baostock_worker'], cwd=PROJECT_ROOT,
            capture_output=True, text=True, timeout=95, check=False)
    except subprocess.TimeoutExpired as exc:
        raise MarketError('BaoStock 获取超时，请稍后重试。') from exc
    if result.stderr:
        print(result.stderr[-6000:], file=sys.stderr, flush=True)
    if result.returncode != 0:
        raise MarketError('BaoStock 连接或取数失败，请查看本机服务日志后重试。')
    try:
        return json.loads(result.stdout)
    except ValueError as exc:
        raise MarketError('BaoStock 返回内容无效。') from exc


class MarketError(Exception):
    pass


class MarketCache:
    def __init__(self, directory, fetch, now, ttl=900, cooldown=60,
                 retain=7 * 86400, lock_timeout=2):
        self.directory = Path(directory).resolve()
        if any((parent / '.git').exists() for parent in (self.directory, *self.directory.parents)):
            raise MarketError('行情缓存必须放在 Git 仓库之外。')
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.fetch, self.now = fetch, now
        self.ttl, self.cooldown, self.retain = ttl, cooldown, retain
        self.lock_timeout = lock_timeout

    @contextlib.contextmanager
    def _lock(self):
        # Separate open descriptors also serialize distinct instances/processes.
        with (self.directory / 'provider.lock').open('a') as handle:
            end = time.monotonic() + self.lock_timeout
            while True:
                try:
                    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() >= end:
                        raise MarketError('已有行情请求正在进行，请稍后重试。')
                    time.sleep(.025)
            try:
                yield
            finally:
                fcntl.flock(handle, fcntl.LOCK_UN)

    def _read(self, name):
        try:
            path = self.directory / name
            if path.stat().st_size > 1_000_000:
                return None
            return json.loads(path.read_text(encoding='utf-8'))
        except (OSError, ValueError):
            return None

    def _write(self, name, value):
        temporary = self.directory / (name + '.tmp')
        temporary.write_text(json.dumps(value, ensure_ascii=False, allow_nan=False), encoding='utf-8')
        temporary.replace(self.directory / name)

    def get(self, refresh=False):
        with self._lock():
            now = self.now()
            payload = self._read('snapshot.json')
            try:
                validate_snapshot(payload, now)
                age = (now - timestamp(payload['fetchedAt'])).total_seconds()
                if age > self.retain:
                    payload = None
            except MarketError:
                payload = None
            attempt = self._read('attempt.json')
            try:
                attempt_age = (now - timestamp(attempt['at'])).total_seconds()
                if not 0 <= attempt_age <= self.retain:
                    attempt = None
            except (MarketError, TypeError, KeyError):
                attempt = None
            failed = bool(attempt and attempt.get('status') != 'success')
            if payload and age < self.ttl and not refresh and not failed:
                return {'payload': payload, 'cached': True, 'stale': False}
            if attempt and attempt_age < self.cooldown:
                if payload:
                    return {'payload': payload, 'cached': True,
                            'stale': failed or age >= self.ttl,
                            'warning': '刚刚尝试获取过数据，稍后可重试。'}
                raise MarketError('刚刚尝试获取过数据，请稍后重试。')
            attempt = {'at': now.isoformat(), 'status': 'pending'}
            self._write('attempt.json', attempt)
            try:
                fresh = self.fetch()
                validate_snapshot(fresh, self.now())
                self._write('snapshot.json', fresh)
                self._write('attempt.json', {**attempt, 'status': 'success'})
                return {'payload': fresh, 'cached': False, 'stale': False}
            except Exception as exc:
                self._write('attempt.json', {**attempt, 'status': 'failed'})
                if payload:
                    return {'payload': payload, 'cached': True, 'stale': True,
                            'warning': '本次获取失败，保留原获取时间的旧缓存。'}
                if isinstance(exc, MarketError):
                    raise
                raise MarketError('暂时无法获取 BaoStock 数据，请稍后重试。') from exc


def timestamp(value):
    try:
        if not isinstance(value, str) or not re.search(r'(Z|[+-]\d\d:\d\d)$', value):
            raise ValueError('timezone missing')
        result = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
        if result.tzinfo is None:
            raise ValueError('timezone missing')
        return result.astimezone(UTC)
    except (ValueError, TypeError):
        raise MarketError('获取时间格式无效。')


def session_date(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d{4}-\d{2}-\d{2}', value):
        raise ValueError('invalid date')
    return dt.date.fromisoformat(value)


def validate_snapshot(payload, now):
    try:
        if not isinstance(payload, dict) or payload.get('timezone') != 'Asia/Shanghai':
            raise ValueError('wrong timezone')
        fetched = timestamp(payload['fetchedAt'])
        if fetched > now + dt.timedelta(minutes=5):
            raise ValueError('future retrieval time')
        start, end = session_date(payload['startDate']), session_date(payload['endDate'])
        if end - start != dt.timedelta(days=29) or end >= fetched.astimezone(SHANGHAI).date():
            raise ValueError('invalid closed-day window')
        if not isinstance(payload['indices'], dict) or set(payload['indices']) != set(INDEX_CODES.values()):
            raise ValueError('unexpected indices')
        for code, rows in payload['indices'].items():
            if not isinstance(rows, list) or len(rows) > 30:
                raise ValueError('invalid row count')
            previous = None
            for row in rows:
                if not isinstance(row, dict) or set(row) != set(FIELDS.split(',')):
                    raise ValueError('invalid fields')
                day = session_date(row['date'])
                if row['code'] != code or not start <= day <= end or (previous and day <= previous):
                    raise ValueError('invalid code or session order')
                previous = day
                numbers = {key: float(row[key]) for key in FIELDS.split(',')[2:]}
                if not all(math.isfinite(value) for value in numbers.values()):
                    raise ValueError('nonfinite number')
                if not (0 < numbers['low'] <= min(numbers['open'], numbers['close'])
                        <= max(numbers['open'], numbers['close']) <= numbers['high']):
                    raise ValueError('invalid OHLC')
                if numbers['volume'] < 0 or numbers['amount'] < 0:
                    raise ValueError('negative volume or amount')
    except (ValueError, TypeError, KeyError, OverflowError) as exc:
        raise MarketError('BaoStock 数据未通过日期、指数或数值校验。') from exc


def main():
    parser = argparse.ArgumentParser(description='Time Nest localhost personal-research service')
    parser.add_argument('--cache-dir', type=Path, required=True, help='A directory outside any Git repository')
    parser.add_argument('--build-dir', type=Path, default=PROJECT_ROOT / 'build/web')
    parser.add_argument('--port', type=int, default=8787)
    args = parser.parse_args()
    if not (args.build_dir / 'index.html').is_file():
        parser.error('Build the local Flutter Web application first.')
    if not 0 <= args.port <= 65535:
        parser.error('Invalid localhost port.')
    cache = MarketCache(args.cache_dir, fetch_worker, lambda: dt.datetime.now(UTC))
    server = create_server(args.build_dir, cache, port=args.port)
    print('Listening on http://127.0.0.1:{} (personal research only)'.format(server.server_port), flush=True)
    try:
        server.serve_forever(poll_interval=.25)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
