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
