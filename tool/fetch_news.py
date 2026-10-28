#!/usr/bin/env python3
"""Fetch public official RSS metadata only. No article bodies, keys or proxy."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
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

def iso(seconds):
    return datetime.fromtimestamp(seconds, timezone.utc).isoformat().replace('+00:00', 'Z')

def article_url(value, source):
    if not isinstance(value, str):
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
    if len(raw) > MAX_BYTES or re.search(br'<!DOCTYPE|<!ENTITY', raw, re.I):
        raise ValueError('unsupported XML')
    root = ET.fromstring(raw)
    channel = root.find('channel') if root.tag == 'rss' else None
    if channel is None:
        raise ValueError('RSS channel missing')
    stories = []
    for item in channel.findall('item')[:100]:
        title = ' '.join(''.join(item.find('title').itertext()).split())[:500] if item.find('title') is not None else ''
        link = article_url(item.findtext('link') or '', source)
        if not title or not link:
            continue
        stories.append({'title': title, 'url': link, 'time': published(item.findtext('pubDate') or '', now), 'source': source['name'], 'sourceId': source['id']})
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
            stories.append({**story, 'url': link, 'source': source['name']})
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
    return {'schemaVersion': 1, 'generatedAt': iso(now), 'sources': statuses, 'stories': stories}

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
