#!/usr/bin/env python3
"""Fetch official RSS under explicit reuse policies; never scrape article pages."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from html.parser import HTMLParser
from io import BytesIO
import json
from pathlib import Path
import re
import urllib.request
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode
import xml.etree.ElementTree as ET

SOURCES = [
    {'id': 'sspai', 'name': '少数派', 'url': 'https://sspai.com/feed', 'hosts': ['sspai.com']},
    {'id': 'ithome', 'name': 'IT之家', 'url': 'https://www.ithome.com/rss/', 'hosts': ['www.ithome.com', 'ithome.com']},
    {'id': 'solidot', 'name': 'Solidot', 'url': 'https://www.solidot.org/index.rss', 'hosts': ['www.solidot.org', 'solidot.org']},
]
MAX_BYTES = 2_000_000
MAX_STORIES = 300
RETENTION = 7 * 86400
MAX_HTML_BYTES = 64_000
MAX_FULL_CHARS = 24_000
MAX_EXCERPT_CHARS = 280
MAX_SNAPSHOT_BYTES = 850_000  # Below browser fetch/cache limits, measured as UTF-8.
# RSS availability is not a republication license. Add grants only after checking
# their scope, attribution and whether the named field really contains full text.
# The browser and Dart reader must enable the same reviewed permission separately.
# No grant is enabled for the current three sources.
REUSE_POLICIES = {
    'sspai': {'mode': 'link'},
    'ithome': {'mode': 'link'},
    'solidot': {'mode': 'link'},
}
CONTENT_REASONS = {'permission_required', 'not_provided', 'invalid_content', 'too_large'}


def unavailable(reason):
    return {'kind': 'unavailable', 'reason': reason}


class ContentLimitError(ValueError):
    pass


class _PlainText(HTMLParser):
    # No markup is returned. Images, URLs, event handlers and style attributes
    # never reach a renderer or cause network requests.
    BLOCKED = {'script', 'style', 'iframe', 'object', 'embed', 'svg', 'math',
               'audio', 'video', 'canvas', 'form', 'button', 'template', 'head',
               'title', 'noscript', 'textarea', 'select'}
    VOID = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link',
            'meta', 'param', 'source', 'track', 'wbr'}
    BLOCK = {'p', 'div', 'br', 'hr', 'li', 'ul', 'ol', 'blockquote', 'pre',
             'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'section', 'article', 'tr'}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.parts = []
        self.tokens = 0

    def handle_starttag(self, tag, attrs):
        self.tokens += 1
        if self.tokens > 10_000 or len(self.stack) >= 64:
            raise ContentLimitError('HTML complexity limit')
        hidden = any(name == 'hidden' or name == 'aria-hidden' and value == 'true'
                     for name, value in attrs)
        blocked = bool(self.stack and self.stack[-1][1]) or tag in self.BLOCKED or hidden
        if not blocked and tag in self.BLOCK:
            self.parts.append('\n\n')
        if tag not in self.VOID:
            self.stack.append((tag, blocked))

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in self.VOID:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        index = next((i for i in range(len(self.stack)-1, -1, -1)
                      if self.stack[i][0] == tag), None)
        if index is None:
            return
        blocked = self.stack[index][1]
        del self.stack[index:]
        if not blocked and tag in self.BLOCK:
            self.parts.append('\n\n')

    def handle_data(self, value):
        if not self.stack or not self.stack[-1][1]:
            self.parts.append(value)


def plain_text(raw):
    """Convert bounded HTML to inert paragraph text. Fail closed on complexity."""
    if not isinstance(raw, str) or len(raw.encode('utf-8')) > MAX_HTML_BYTES:
        raise ContentLimitError('HTML byte limit')
    parser = _PlainText()
    parser.feed(raw)
    parser.close()
    text = ''.join(parser.parts).replace('\r', '\n')
    text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u202a-\u202e\u2066-\u2069]', '', text)
    text = re.sub(r'[^\S\n]+', ' ', text)
    text = re.sub(r' *\n *', '\n', text)
    return re.sub(r'\n{3,}', '\n\n', text).strip()


def reuse_policy(source):
    policy = REUSE_POLICIES.get(source['id'], {})
    # Only a reviewed, code-side grant with a fixed evidence URL can authorize
    # body text. JSON/RSS claims, per-item license fields and old caches cannot.
    license_url = policy.get('licenseUrl')
    if policy.get('mode') not in {'excerpt', 'full'} or not isinstance(license_url, str):
        return None
    try:
        url = urlsplit(license_url)
        if url.scheme != 'https' or not url.hostname or url.username or url.password or url.port or re.search(r'[\x00-\x20\x7f\\]', license_url):
            return None
    except ValueError:
        return None
    if policy.get('field') not in {'description', '{http://purl.org/rss/1.0/modules/content/}encoded'}:
        return None
    # A description is an excerpt, regardless of length. Full requires a field
    # whose completeness has been explicitly verified in the reviewed policy.
    if policy['mode'] == 'full' and (policy['field'] == 'description' or policy.get('verifiedFullText') is not True):
        return None
    return policy


def feed_content(item, source):
    policy = reuse_policy(source)
    if policy is None:
        return unavailable('permission_required')
    field = item.find(policy['field'])
    if field is not None and len(field):
        # The contract is escaped/CDATA HTML. findtext() on XML children would
        # silently lose their tails and could mislabel an incomplete full body.
        return unavailable('invalid_content')
    raw = field.text if field is not None else None
    if not raw:
        return unavailable('not_provided')
    try:
        value = plain_text(raw)
    except ContentLimitError:
        return unavailable('too_large')
    except (ValueError, UnicodeError):
        return unavailable('invalid_content')
    if not value:
        return unavailable('not_provided')
    if policy['mode'] == 'full' and len(value) > MAX_FULL_CHARS:
        return unavailable('too_large')
    if policy['mode'] == 'excerpt' and len(value) > MAX_EXCERPT_CHARS:
        value = value[:MAX_EXCERPT_CHARS - 1].rstrip() + '…'
    return {'kind': policy['mode'], 'format': 'plain_text', 'text': value,
            'licenseUrl': policy['licenseUrl']}


def retained_content(value, source):
    policy = reuse_policy(source)
    if policy is None:
        return unavailable('permission_required')
    if not isinstance(value, dict):
        return unavailable('not_provided')
    if value.get('kind') == 'unavailable':
        reason = value.get('reason')
        return unavailable(reason if reason in CONTENT_REASONS else 'not_provided')
    text = value.get('text')
    limit = MAX_FULL_CHARS if policy['mode'] == 'full' else MAX_EXCERPT_CHARS
    if (value.get('kind') != policy['mode'] or value.get('format') != 'plain_text'
            or value.get('licenseUrl') != policy['licenseUrl']
            or not isinstance(text, str) or not 0 < len(text) <= limit
            or re.search(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u202a-\u202e\u2066-\u2069]', text)):
        return unavailable('invalid_content')
    return {'kind': policy['mode'], 'format': 'plain_text', 'text': text,
            'licenseUrl': policy['licenseUrl']}


def parse_xml(raw):
    if (not isinstance(raw, bytes) or len(raw) > MAX_BYTES or b'\x00' in raw
            or re.search(br'<!DOCTYPE|<!ENTITY', raw, re.I)):
        raise ValueError('unsupported XML')
    # Iterative event parsing rejects deeply nested feeds before walking content.
    depth = nodes = 0
    parser = ET.iterparse(BytesIO(raw), events=('start', 'end'))
    for event, _ in parser:
        if event == 'start':
            depth += 1
            nodes += 1
            if depth > 64 or nodes > 20_000:
                raise ValueError('XML complexity limit')
        else:
            depth -= 1
    return parser.root

def iso(seconds):
    return datetime.fromtimestamp(seconds, timezone.utc).isoformat().replace('+00:00', 'Z')

def article_url(value, source):
    if not isinstance(value, str) or len(value) > 4096 or '\\' in value:
        return None
    try:
        url = urlsplit(value.strip())
        if url.scheme != 'https' or url.hostname not in source['hosts'] or url.port or url.username or url.password:
            return None
        if re.search(r'[\x00-\x20\x7f]', value):
            return None
        if source['id'] == 'sspai' and not re.fullmatch(r'/post/\d+/?', url.path):
            return None
        if source['id'] == 'ithome' and not re.fullmatch(r'/\d+/\d+/\d+\.htm', url.path):
            return None
        if source['id'] == 'solidot' and (url.path != '/story' or not re.fullmatch(r'\d+', dict(parse_qsl(url.query)).get('sid', ''))):
            return None
        query = urlencode([(k, v) for k, v in parse_qsl(url.query) if not k.lower().startswith('utm_')])
        return urlunsplit(('https', source['hosts'][0], url.path.rstrip('/'), query, ''))
    except (ValueError, TypeError):
        return None

def published(value, now):
    if not isinstance(value, str):
        return None
    try:
        try:
            date = parsedate_to_datetime(value)
        except (ValueError, TypeError):
            date = datetime.fromisoformat(value.replace('Z', '+00:00'))
        if date.tzinfo is None:
            return None  # Unknown timezone is not the machine's local time.
        stamp = int(date.timestamp())
        return stamp if 0 < stamp <= now + 86400 else None
    except (ValueError, TypeError, OverflowError):
        return None

def parse_feed(raw, source, now):
    root = parse_xml(raw)
    channel = root.find('channel') if root.tag == 'rss' else None
    if channel is None:
        raise ValueError('RSS channel missing')
    stories = []
    for item in channel.findall('item')[:100]:
        title = ' '.join(''.join(item.find('title').itertext()).split())[:500] if item.find('title') is not None else ''
        link = article_url(item.findtext('link') or '', source)
        if not title or not link:
            continue
        stories.append({'title': title, 'url': link, 'time': published(item.findtext('pubDate') or '', now), 'source': source['name'], 'sourceId': source['id'], 'content': feed_content(item, source)})
    if channel.findall('item') and not stories:
        raise ValueError('No valid article metadata')
    return stories

def fetch(source, now):
    request = urllib.request.Request(source['url'], headers={'User-Agent': 'TimeNest-RSS/1.0', 'Accept': 'application/rss+xml, application/xml, text/xml'})
    with urllib.request.urlopen(request, timeout=12) as response:
        if urlsplit(response.url).hostname not in source['hosts'] or urlsplit(response.url).scheme != 'https':
            raise ValueError('unexpected redirect')
        if response.headers.get_content_type() not in ['application/rss+xml', 'application/xml', 'text/xml']:
            raise ValueError('not XML')
        return parse_feed(response.read(MAX_BYTES + 1), source, now)

def valid_previous(previous, now):
    if not isinstance(previous, dict) or previous.get('schemaVersion') != 1:
        return {}, []
    statuses = {}
    for status in (previous.get('sources') if isinstance(previous.get('sources'), list) else [])[:3]:
        if not isinstance(status, dict):
            continue
        stamp = published(status.get('fetchedAt', ''), now)
        if stamp and now - stamp <= RETENTION:
            if status.get('id') in [s['id'] for s in SOURCES]:
                statuses[status['id']] = stamp
    stories = []
    for story in (previous.get('stories') if isinstance(previous.get('stories'), list) else [])[:MAX_STORIES]:
        if not isinstance(story, dict):
            continue
        source = next((s for s in SOURCES if s['id'] == story.get('sourceId')), None)
        if not source or source['id'] not in statuses:
            continue
        link = article_url(story.get('url', ''), source)
        title, stamp = story.get('title'), story.get('time')
        if link and isinstance(title, str) and 0 < len(title) <= 500 and (type(stamp) is int and now - RETENTION <= stamp <= now + 86400):
            stories.append({'title': title, 'url': link, 'time': stamp,
                            'source': source['name'], 'sourceId': source['id'],
                            'content': retained_content(story.get('content'), source)})
    return statuses, stories

def aggregate(now, previous=None, fetcher=fetch):
    old_status, old_stories = valid_previous(previous, now)
    def get(source):
        try:
            return source, fetcher(source, now), True
        except Exception as error:
            print(f"{source['id']}: unavailable ({type(error).__name__})")
            return source, [], False
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(get, SOURCES))
    statuses, rows = [], []
    for source, fresh, ok in results:
        retained = [s for s in old_stories if s['sourceId'] == source['id']]
        rows += fresh + retained
        statuses.append({'id': source['id'], 'name': source['name'], 'url': source['url'], 'status': 'ok' if ok else 'cached' if retained else 'unavailable', 'fetchedAt': iso(now) if ok else iso(old_status[source['id']]) if retained else None})
    # Prefer current metadata; conservatively deduplicate identical URLs and exact
    # normalized titles only. Similar headlines are not necessarily one story.
    by_url, titles = {}, set()
    for story in rows:
        if story['time'] is not None and story['time'] < now - RETENTION:
            continue
        if story['url'] not in by_url:
            by_url[story['url']] = story
    ordered = sorted(by_url.values(), key=lambda s: (-(s['time'] or 0), s['sourceId'], s['url']))
    stories = []
    for story in ordered:
        key = re.sub(r'\s+', ' ', story['title']).strip().casefold()
        if key not in titles:
            titles.add(key)
            stories.append(story)
    stories = stories[:MAX_STORIES]
    for status in statuses:
        status['count'] = sum(s['sourceId'] == status['id'] for s in stories)
    if not stories:
        raise ValueError('All feeds empty or unavailable; preserving previous snapshot')
    result = {'schemaVersion': 1, 'generatedAt': iso(now), 'sources': statuses, 'stories': stories}
    # Keep the hourly artifact and browser cache bounded even after future grants.
    # Never truncate a full article and continue labelling it as full.
    for story in sorted(stories, key=lambda s: len(json.dumps(s.get('content', {}), ensure_ascii=False).encode('utf-8')), reverse=True):
        if len(json.dumps(result, ensure_ascii=False).encode('utf-8')) <= MAX_SNAPSHOT_BYTES:
            break
        if story.get('content', {}).get('kind') in {'full', 'excerpt'}:
            story['content'] = unavailable('too_large')
    if len(json.dumps(result, ensure_ascii=False).encode('utf-8')) > MAX_SNAPSHOT_BYTES:
        raise ValueError('News snapshot exceeds byte limit')
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output')
    parser.add_argument('--previous')
    args = parser.parse_args()
    previous = None
    if args.previous:
        try:
            raw = Path(args.previous).read_bytes()
            if len(raw) <= 1_000_000:
                previous = json.loads(raw)
        except (OSError, ValueError):
            pass
    result = aggregate(int(datetime.now(timezone.utc).timestamp()), previous)
    target = Path(args.output)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(f"Saved {len(result['stories'])} headlines; " + ', '.join(f"{s['name']} {s['count']} ({s['status']})" for s in result['sources']))

if __name__ == '__main__':
    main()
