import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';

void main() {
  test('defaults and corrupt storage remain usable', () {
    expect(DashboardPreferences.decode(null).order, dashboardModules);
    expect(DashboardPreferences.decode('{bad').base, 'USD');
    expect(DashboardPreferences.decode('[]').city, isNull);
  });

  test('all selections round trip and missing modules are restored', () {
    final settings = DashboardPreferences(
      city: {'name': '上海', 'latitude': 31.23, 'longitude': 121.47},
      repos: ['dart-lang/sdk'],
      base: 'JPY',
      quote: 'CNY',
      amount: 13500,
      feed: 'show',
      leaveDays: 3,
      order: ['news', 'fx'],
      favorites: ['news'],
    );
    final read = DashboardPreferences.decode(settings.encode());
    expect(read.city?['name'], '上海');
    expect(read.repos, ['dart-lang/sdk']);
    expect(read.base, 'JPY');
    expect(read.amount, 13500);
    expect(read.feed, 'show');
    expect(read.leaveDays, 3);
    expect(read.order, ['news', 'fx', 'weather', 'holidays', 'releases']);
    expect(read.favorites, ['news']);
  });

  test('invalid saved values cannot make unsupported API requests', () {
    final read = DashboardPreferences.decode(
      jsonEncode({
        'city': {'name': 'bad', 'latitude': 100, 'longitude': 0},
        'repos': ['https://evil.test', 'flutter/flutter', 'flutter/flutter'],
        'base': 'BAD',
        'quote': 'x',
        'amount': -1,
        'feed': 'wrong',
        'leaveDays': 50,
        'order': ['news', 'bogus', 'news'],
        'favorites': ['bogus'],
      }),
    );
    expect(read.city, isNull);
    expect(read.repos, ['flutter/flutter']);
    expect(read.base, 'USD');
    expect(read.amount, 100);
    expect(read.feed, 'top');
    expect(read.leaveDays, 2);
    expect(read.order.toSet(), dashboardModules.toSet());
    expect(read.favorites, isEmpty);
  });
}
