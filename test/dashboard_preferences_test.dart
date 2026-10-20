import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';

void main() {
  test('order-book currency defaults, validates and survives preference round trip', () {
    expect(DashboardPreferences.decode(null).cryptoCurrency, 'USD');
    expect(
      DashboardPreferences.decode('{"cryptoCurrency":"EUR"}').cryptoCurrency,
      'USD',
    );
    final p = DashboardPreferences.decode(
      '{"cryptoCurrency":"CNY","cryptoSymbol":"ETHUSDT","cryptoPaneHeights":{"vol":200}}',
    );
    expect(DashboardPreferences.decode(p.encode()).cryptoCurrency, 'CNY');
    expect(p.cryptoSymbol, 'ETHUSDT');
    expect(p.cryptoPaneHeights, {'vol': 200});
  });

  test(
    'pane height cache migrates, validates and survives preference round trips',
    () {
      expect(
        DashboardPreferences.decode('{"cryptoSymbol":"ETHUSDT"}')
            .cryptoPaneHeights,
        isEmpty,
      );
      final p = DashboardPreferences.decode(
        jsonEncode({
          'cryptoSymbol': 'ETHUSDT',
          'cryptoInterval': '1d',
          'cryptoPaneHeights': {
            'vol': 224.5,
            'macd': 999,
            'rsi': -5,
            'ma': 240,
            'unknown': 180,
            'atr': '200',
          },
        }),
      );
      expect(p.cryptoPaneHeights, {'vol': 224.5, 'macd': 400.0, 'rsi': 64.0});
      final restored = DashboardPreferences.decode(p.encode());
      expect(restored.cryptoPaneHeights, p.cryptoPaneHeights);
      expect(restored.cryptoSymbol, 'ETHUSDT');
      expect(restored.cryptoInterval, '1d');
      expect(
        cleanCryptoPaneHeights({
          'vol': double.nan,
          'macd': double.infinity,
          'rsi': 180,
        }),
        {'rsi': 180.0},
      );
      expect(
        DashboardPreferences.decode('{"cryptoPaneHeights":[]}')
            .cryptoPaneHeights,
        isEmpty,
      );
    },
  );

  test('defaults and corrupt storage remain usable', () {
    expect(DashboardPreferences.decode(null).order, dashboardModules);
    expect(DashboardPreferences.decode('{bad').order, dashboardModules);
    expect(DashboardPreferences.decode('[]').city, isNull);
  });

  test('popular defaults and Chinese news are provided on first launch', () {
    final read = DashboardPreferences.decode(null);
    expect(read.repos, defaultDashboardRepos);
    expect(read.repos, hasLength(24));
    expect(read.feed, 'sspai');
    expect(read.order, ['weather', 'releases', 'news', 'market', 'crypto']);
    expect(read.favorites, ['weather']);
  });

  test(
    'old untouched defaults migrate, custom lists and chosen feeds survive',
    () {
      final old = DashboardPreferences.decode(
        '{"repos":["flutter/flutter"],"feed":"top"}',
      );
      expect(old.repos, defaultDashboardRepos);
      expect(old.feed, 'sspai');
      final custom = DashboardPreferences.decode(
        '{"repos":["owner/project"],"feed":"show"}',
      );
      expect(custom.repos, ['owner/project']);
      expect(custom.feed, 'show');
      expect(DashboardPreferences.decode('{"repos":[]}').repos, isEmpty);
    },
  );

  test('removed defaults and intentional single-repo lists stay removed', () {
    final saved = DashboardPreferences(repos: ['flutter/flutter'], feed: 'top');
    expect(DashboardPreferences.decode(saved.encode()).repos, [
      'flutter/flutter',
    ]);
    expect(DashboardPreferences.decode(saved.encode()).feed, 'top');
    saved.repos = [];
    expect(DashboardPreferences.decode(saved.encode()).repos, isEmpty);
  });

  test(
    'saved repositories are deduplicated case-insensitively up to capacity',
    () {
      final saved = DashboardPreferences.decode(
        jsonEncode({
          'version': 2,
          'repos': [
            'Owner/Project',
            'owner/project',
            for (var i = 0; i < 60; i++) 'owner/repo$i',
          ],
        }),
      );
      expect(saved.repos, hasLength(maxDashboardRepos));
      expect(saved.repos.first, 'owner/project');
    },
  );

  test('all selections round trip and missing modules are restored', () {
    final settings = DashboardPreferences(
      city: {'name': '上海', 'latitude': 31.23, 'longitude': 121.47},
      repos: ['dart-lang/sdk'],
      feed: 'show',
      order: ['news', 'market'],
      favorites: ['news'],
    );
    final read = DashboardPreferences.decode(settings.encode());
    expect(read.city?['name'], '上海');
    expect(read.repos, ['dart-lang/sdk']);
    expect(read.feed, 'show');
    expect(read.order, ['news', 'market', 'weather', 'releases', 'crypto']);
    expect(read.favorites, ['news']);
  });

  test(
    'retired module preferences are removed without losing active choices',
    () {
      final read = DashboardPreferences.decode(
        jsonEncode({
          'version': 4,
          'city': {'name': '上海', 'latitude': 31.23, 'longitude': 121.47},
          'repos': ['owner/project'],
          'base': 'EUR',
          'quote': 'JPY',
          'amount': 42,
          'feed': 'top',
          'marketIndex': 'shenzhen',
          'marketInterval': 'W',
          'leaveDays': 5,
          'order': ['holidays', 'news', 'weather', 'fx', 'releases'],
          'favorites': ['holidays', 'fx', 'news', 'weather'],
        }),
      );
      expect(read.order, ['news', 'weather', 'releases', 'market', 'crypto']);
      expect(read.favorites, ['news', 'weather']);
      expect(read.city?['name'], '上海');
      expect(read.repos, ['owner/project']);
      expect(read.feed, 'top');
      expect(read.marketIndex, 'shenzhen');
      expect(read.marketInterval, 'W');
      final encoded = jsonDecode(read.encode()) as Map<String, dynamic>;
      expect(encoded['version'], 4);
      expect(encoded.containsKey('leaveDays'), isFalse);
      expect(encoded.containsKey('base'), isFalse);
      expect(encoded.containsKey('quote'), isFalse);
      expect(encoded.containsKey('amount'), isFalse);
      expect(read.encode(), isNot(contains('holidays')));
      expect(read.encode(), isNot(contains('"fx"')));
      expect(DashboardPreferences.decode(read.encode()).order, read.order);
      expect(
        DashboardPreferences.decode('{"favorites":["holidays","fx"]}')
            .favorites,
        isEmpty,
      );
    },
  );

  test('invalid saved values cannot make unsupported API requests', () {
    final read = DashboardPreferences.decode(
      jsonEncode({
        'city': {'name': 'bad', 'latitude': 100, 'longitude': 0},
        'repos': ['https://evil.test', 'flutter/flutter', 'flutter/flutter'],
        'feed': 'wrong',
        'order': ['news', 'bogus', 'news'],
        'favorites': ['bogus'],
      }),
    );
    expect(read.city, isNull);
    expect(read.repos, ['flutter/flutter']);
    expect(read.feed, 'sspai');
    expect(read.order.toSet(), dashboardModules.toSet());
    expect(read.favorites, isEmpty);
  });
}
