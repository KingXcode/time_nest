import unittest
from tool.fetch_news import aggregate, parse_feed, published, article_url, SOURCES, iso
NOW = 1792324800

def row(source, title, timestamp=NOW, number=1):
    links = {'sspai': f'https://sspai.com/post/{number}', 'ithome': f'https://www.ithome.com/1/019/{number}.htm', 'solidot': f'https://www.solidot.org/story?sid={number}'}
    return dict(title=title, url=links[source['id']], time=timestamp, source=source['name'], sourceId=source['id'])

class NewsTests(unittest.TestCase):
    def test_dates(self):
        for invalid in ['', 'oops', '2026-10-18T01:00:00', '2099-01-01T00:00:00Z']:
            self.assertIsNone(published(invalid, NOW))
        self.assertEqual(published('Sun, 18 Oct 2026 20:00:00 +0800', NOW), NOW)
    def test_parse_no_fake_date_and_safe_urls(self):
        xml = b'<rss><channel><item><title>Test</title><link>https://sspai.com/post/1</link><pubDate>bad</pubDate></item></channel></rss>'
        self.assertIsNone(parse_feed(xml, SOURCES[0], NOW)[0]['time'])
        self.assertIsNone(article_url('https://sspai.com.evil/post/1', SOURCES[0]))
        self.assertEqual(article_url('https://sspai.com/post/1?utm_source=a#x', SOURCES[0]), 'https://sspai.com/post/1')
        with self.assertRaises(ValueError): parse_feed(b'<!DOCTYPE rss>'+xml,SOURCES[0],NOW)
    def test_order_duplicates_and_unknown_last(self):
        result = aggregate(NOW, fetcher=lambda s,n: [row(s, 'same', NOW-10),row(s,s['id'],None,2),row(s,'new'+s['id'],NOW,3)])
        self.assertEqual(len(result['stories']),7)
        times=[s['time'] for s in result['stories']]
        self.assertEqual(times, sorted(times,key=lambda t: t or 0, reverse=True))
    def test_partial_failure_retains_source_and_total_failure_no_empty_replacement(self):
        previous=aggregate(NOW,fetcher=lambda s,n:[row(s,s['id'])])
        def partial(s,n):
            if s['id']=='sspai': raise TimeoutError()
            return [row(s,s['id'])]
        result=aggregate(NOW+60,previous,partial)
        self.assertEqual(result['sources'][0]['status'],'cached')
        self.assertEqual(result['sources'][0]['fetchedAt'],iso(NOW))
        def fail(s,n): raise TimeoutError()
        with self.assertRaises(ValueError):aggregate(NOW, fetcher=fail)
        with self.assertRaises(ValueError):aggregate(NOW+8*86400, previous, fail)
    def test_unknown_date_not_retained_forever(self):
        previous=aggregate(NOW,fetcher=lambda s,n:[row(s,s['id'],None)])
        result=aggregate(NOW+60,previous,lambda s,n:[row(s,'fresh'+s['id'],NOW+60,2)])
        self.assertEqual(len(result['stories']),3)
        self.assertTrue(all(s['time'] is not None for s in result['stories']))
    def test_malformed_previous(self):
        result=aggregate(NOW, {'schemaVersion':1,'sources':None,'stories':{}},lambda s,n:[row(s,s['id'])])
        self.assertEqual(len(result['stories']),3)

# All body fixtures below are invented test strings, not source article text.
from unittest.mock import patch
from tool.fetch_news import (plain_text, feed_content, retained_content, REUSE_POLICIES,
                             MAX_FULL_CHARS, MAX_EXCERPT_CHARS, ContentLimitError,
                             valid_previous)
import xml.etree.ElementTree as ET
import json


def fixture_feed(description='<p>First paragraph.</p><p>Second paragraph.</p>', encoded=None):
    item = ET.Element('item')
    for tag, value in [('title', 'Synthetic fixture'), ('link', 'https://sspai.com/post/1'),
                       ('pubDate', 'Sun, 18 Oct 2026 20:00:00 +0800'), ('description', description)]:
        ET.SubElement(item, tag).text = value
    if encoded is not None:
        ET.SubElement(item, '{http://purl.org/rss/1.0/modules/content/}encoded').text = encoded
    return item


def grant(mode='excerpt', **changes):
    # Test-only fake license. Production policy remains denied for every source.
    return {'mode': mode, 'licenseUrl': 'https://example.test/license',
            'field': 'description' if mode == 'excerpt' else '{http://purl.org/rss/1.0/modules/content/}encoded',
            'verifiedFullText': mode == 'full', **changes}


class ContentTests(unittest.TestCase):
    def test_current_sources_never_publish_body_even_if_feed_claims_license(self):
        item = fixture_feed('<p>Not licensed to this app.</p>', '<p>Full body.</p>')
        ET.SubElement(item, 'license').text = 'https://example.test/open-license'
        for source in SOURCES:
            self.assertEqual(feed_content(item, source), {'kind': 'unavailable', 'reason': 'permission_required'})
        self.assertTrue(all(policy == {'mode': 'link'} for policy in REUSE_POLICIES.values()))

    def test_plain_text_removes_active_hidden_embedded_and_tracking_content(self):
        raw = '''<p onclick="evil()">First &amp; one <b>bold</b>.</p>
        <script>script-secret</script><style>style-secret</style>
        <iframe src="https://tracker.test">iframe-secret</iframe>
        <object>object-secret</object><svg>svg-secret</svg><math>math-secret</math>
        <template>template-secret</template><div hidden>hidden-secret</div>
        <span aria-hidden="true">aria-secret</span><noscript>noscript-secret</noscript>
        <img src="https://tracker.test/pixel" onerror="evil()" alt="tracking-secret">
        <p style="font-size:99px">Second <a href="javascript:evil()">link label</a>.</p>'''
        self.assertEqual(plain_text(raw), 'First & one bold.\n\nSecond link label.')
        self.assertEqual(plain_text('A\x00\u202e &lt;script&gt;literal&lt;/script&gt;'), 'A <script>literal</script>')
        self.assertNotIn('secret', plain_text('<div><script>secret</script></div><p>safe</p>'))

    def test_excerpt_is_bounded_and_never_claims_full(self):
        with patch.dict(REUSE_POLICIES, {'sspai': grant()}):
            body = feed_content(fixture_feed('<p>' + '文' * 400 + '</p>'), SOURCES[0])
        self.assertEqual(body['kind'], 'excerpt')
        self.assertEqual(body['format'], 'plain_text')
        self.assertEqual(len(body['text']), MAX_EXCERPT_CHARS)
        self.assertTrue(body['text'].endswith('…'))

    def test_full_requires_explicit_complete_field_and_is_never_silently_truncated(self):
        item = fixture_feed(encoded='<p>Complete synthetic body.</p>')
        for policy in [grant('full', field='description'), grant('full', verifiedFullText=False),
                       grant('full', licenseUrl='javascript:evil()'), grant('full', licenseUrl='https://user:pw@example.test/license')]:
            with patch.dict(REUSE_POLICIES, {'sspai': policy}):
                self.assertEqual(feed_content(item, SOURCES[0])['reason'], 'permission_required')
        with patch.dict(REUSE_POLICIES, {'sspai': grant('full')}):
            self.assertEqual(feed_content(item, SOURCES[0])['text'], 'Complete synthetic body.')
            self.assertEqual(feed_content(fixture_feed(), SOURCES[0])['reason'], 'not_provided')
            nested = fixture_feed(encoded='Prefix')
            ET.SubElement(nested.find('{http://purl.org/rss/1.0/modules/content/}encoded'), 'p').text = 'Lost tail'
            self.assertEqual(feed_content(nested, SOURCES[0])['reason'], 'invalid_content')
            huge = feed_content(fixture_feed(encoded='x' * (MAX_FULL_CHARS + 1)), SOURCES[0])
            self.assertEqual(huge, {'kind': 'unavailable', 'reason': 'too_large'})

    def test_complex_or_oversized_html_and_xml_fail_closed(self):
        for raw in ['x' * 64_001, '文' * 22_000, '<div>' * 65 + 'deep', '<br>' * 10_001]:
            with self.assertRaises(ContentLimitError):
                plain_text(raw)
        for raw in [b'<rss>' + b'<x>' * 65 + b'</x>' * 65 + b'</rss>',
                    '<!DOCTYPE rss [<!ENTITY bad "expanded">]><rss/>'.encode('utf-16'),
                    b'<rss>' + b'<x/>' * 20_001 + b'</rss>']:
            with self.assertRaises(ValueError):
                parse_feed(raw, SOURCES[0], NOW)

    def test_old_snapshot_unknown_fields_and_forged_permissions_are_discarded(self):
        old = row(SOURCES[0], 'Retained')
        old.update(body='<script>bad</script>', excerpt='unauthorized',
                   content={'kind': 'full', 'format': 'plain_text', 'text': 'unauthorized',
                            'licenseUrl': 'https://example.test/license'})
        previous = {'schemaVersion': 1, 'sources': [{'id': 'sspai', 'fetchedAt': iso(NOW)}], 'stories': [old]}
        _, rows = valid_previous(previous, NOW)
        self.assertEqual(set(rows[0]), {'title', 'url', 'time', 'source', 'sourceId', 'content'})
        self.assertEqual(rows[0]['content'], {'kind': 'unavailable', 'reason': 'permission_required'})
        for mode in ['excerpt', 'full']:
            with patch.dict(REUSE_POLICIES, {'sspai': grant(mode)}):
                valid = {'kind': mode, 'format': 'plain_text', 'text': 'Synthetic safe text.', 'licenseUrl': 'https://example.test/license'}
                self.assertEqual(retained_content(valid, SOURCES[0]), valid)
                for changed in [{'format': 'html'}, {'licenseUrl': 'https://other.test/license'}, {'text': 'a\x00b'}, {'text': 'x'*25_000}]:
                    self.assertEqual(retained_content({**valid, **changed}, SOURCES[0])['reason'], 'invalid_content')

    def test_article_links_require_exact_https_source_and_bounded_input(self):
        for link in ['javascript:alert(1)', 'http://sspai.com/post/1', '//sspai.com/post/1',
                     'https://user@sspai.com/post/1', 'https://sspai.com:8443/post/1',
                     'https://sspai.com\\@evil.test/post/1', 'https://sspai.com/post/'+'1'*4096]:
            self.assertIsNone(article_url(link, SOURCES[0]))

    def test_total_snapshot_bound_drops_content_not_articles_or_full_tail(self):
        def fetcher(source, now):
            return [{**row(source, source['id']), 'content': {'kind': 'full', 'format': 'plain_text',
                    'text': 'x'*1500, 'licenseUrl': 'https://example.test/license'}}]
        with patch('tool.fetch_news.MAX_SNAPSHOT_BYTES', 2000):
            result = aggregate(NOW, fetcher=fetcher)
        self.assertEqual(len(result['stories']), 3)
        self.assertLessEqual(len(json.dumps(result, ensure_ascii=False).encode()), 2000)
        self.assertTrue(any(s['content']['kind'] == 'unavailable' for s in result['stories']))
        self.assertTrue(all(s['content'].get('text', 'x'*1500) == 'x'*1500 for s in result['stories']))
