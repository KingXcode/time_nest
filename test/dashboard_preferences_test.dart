import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';

void main() {
  test('order book levels and per-symbol steps validate and retain other preferences', () {
    expect(DashboardPreferences.decode(null).cryptoBookLevels, isNull);
    for (final value in [0, 15, '5', 5.0]) {
      expect(
        DashboardPreferences.decode(jsonEncode({'cryptoBookLevels': value}))
            .cryptoBookLevels,
        isNull,
      );
    }
    for (final levels in [5, 10, 20]) {
      final p = DashboardPreferences.decode(
        jsonEncode({
          'cryptoBookLevels': levels,
          'cryptoBookSteps': {
            'BTCUSDT': 10,
            'XRPUSDT': .001,
            'DOGEUSDT': -1,
            'invalid/symbol': 1,
            'ETHUSDT': '0.1',
          },
          'cryptoCurrency': 'CNY',
        }),
      );
      final restored = DashboardPreferences.decode(p.encode());
      expect(restored.cryptoBookLevels, levels);
      expect(restored.cryptoBookSteps, {'BTCUSDT': 10, 'XRPUSDT': .001});
      expect(restored.cryptoCurrency, 'CNY');
    }
    expect(
      cleanCryptoBookSteps({'BTCUSDT': double.nan, 'ETHUSDT': double.infinity}),
      isEmpty,
    );
  });

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

  test('active modules and Chinese news are provided on first launch', () {
    final read = DashboardPreferences.decode(null);
    expect(read.feed, 'sspai');
    expect(read.order, ['weather', 'news', 'crypto']);
    expect(read.favorites, ['weather']);
  });

  test('old news defaults migrate and chosen feeds survive', () {
    final old = DashboardPreferences.decode(
      '{"repos":["flutter/flutter"],"feed":"top"}',
    );
    expect(old.feed, 'sspai');
    final custom = DashboardPreferences.decode(
      '{"repos":["owner/project"],"feed":"show"}',
    );
    expect(custom.feed, 'show');
  });

  test('versioned news selection stays unchanged', () {
    final saved = DashboardPreferences(feed: 'top');
    expect(DashboardPreferences.decode(saved.encode()).feed, 'top');
  });

  test('all selections round trip and missing modules are restored', () {
    final settings = DashboardPreferences(
      city: {'name': '上海', 'latitude': 31.23, 'longitude': 121.47},
      feed: 'show',
      order: ['news', 'crypto'],
      favorites: ['news'],
    );
    final read = DashboardPreferences.decode(settings.encode());
    expect(read.city?['name'], '上海');
    expect(read.feed, 'show');
    expect(read.order, ['news', 'crypto', 'weather']);
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
          'order': ['holidays', 'market', 'news', 'weather', 'fx', 'releases'],
          'favorites': [
            'holidays',
            'market',
            'releases',
            'fx',
            'news',
            'weather',
          ],
        }),
      );
      expect(read.order, ['news', 'weather', 'crypto']);
      expect(read.favorites, ['news', 'weather']);
      expect(read.city?['name'], '上海');
      expect(read.feed, 'top');
      final encoded = jsonDecode(read.encode()) as Map<String, dynamic>;
      expect(encoded['version'], 4);
      expect(encoded.containsKey('repos'), isFalse);
      expect(read.encode(), isNot(contains('releases')));
      expect(encoded.containsKey('marketIndex'), isFalse);
      expect(encoded.containsKey('marketInterval'), isFalse);
      expect(encoded.containsKey('leaveDays'), isFalse);
      expect(encoded.containsKey('base'), isFalse);
      expect(encoded.containsKey('quote'), isFalse);
      expect(encoded.containsKey('amount'), isFalse);
      expect(read.encode(), isNot(contains('holidays')));
      expect(read.encode(), isNot(contains('"fx"')));
      expect(DashboardPreferences.decode(read.encode()).order, read.order);
      expect(
        DashboardPreferences.decode(
          '{"favorites":["holidays","fx","market","releases"]}',
        ).favorites,
        isEmpty,
      );
    },
  );

  test('retired module migration preserves every active setting across repeated saves', () {
    final active = jsonDecode(
      DashboardPreferences(
        city: {'name': '上海', 'latitude': 31.23, 'longitude': 121.47},
        feed: 'show',
        cryptoSymbol: 'XRPUSDT',
        cryptoInterval: '4h',
        cryptoOverlays: const ['ema', 'boll'],
        cryptoPanes: const ['rsi', 'vol'],
        cryptoInfoRight: true,
        cryptoCurrency: 'CNY',
        cryptoBookLevels: 10,
        cryptoBookSteps: const {'XRPUSDT': .001, 'BTCUSDT': 10},
        cryptoPaneHeights: const {'rsi': 240, 'vol': 180},
        order: const ['crypto', 'news', 'weather'],
        favorites: const ['crypto', 'news'],
      ).encode(),
    ) as Map<String, dynamic>;
    active['cryptoView'] = {
      'orderBook': false,
      'trades': false,
      'tradeAmount': false,
      'timeline': false,
      'indicatorValues': false,
      'assessment': false,
      'tradeRows': 100,
    };
    final legacy = {
      ...active,
      'repos': ['owner/project'],
      'marketIndex': 'shenzhen',
      'marketInterval': 'W',
      'order': ['market', 'crypto', 'news', 'weather', 'market', 'releases'],
      'favorites': [
        'market',
        'releases',
        'crypto',
        'news',
        'market',
        'releases',
      ],
    };
    final migrated = DashboardPreferences.decode(jsonEncode(legacy));
    expect(jsonDecode(migrated.encode()), active);
    expect(
      jsonDecode(DashboardPreferences.decode(migrated.encode()).encode()),
      active,
    );
  });

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
    expect(read.feed, 'sspai');
    expect(read.order.toSet(), dashboardModules.toSet());
    expect(read.favorites, isEmpty);
  });
}
