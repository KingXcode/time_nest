import 'dart:convert';

const dashboardModules = ['weather', 'holidays', 'releases', 'fx', 'news'];

class DashboardPreferences {
  DashboardPreferences({
    this.city,
    this.repos = const ['flutter/flutter'],
    this.base = 'USD',
    this.quote = 'CNY',
    this.amount = 100,
    this.feed = 'top',
    this.leaveDays = 2,
    this.order = dashboardModules,
    this.favorites = const ['weather', 'holidays'],
  });

  Map<String, dynamic>? city;
  List<String> repos;
  String base;
  String quote;
  double amount;
  String feed;
  int leaveDays;
  List<String> order;
  List<String> favorites;

  factory DashboardPreferences.decode(String? raw) {
    try {
      final json = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      final prefs = DashboardPreferences();
      final city = json['city'];
      if (city is Map<String, dynamic> &&
          city['name'] is String &&
          city['latitude'] is num &&
          city['longitude'] is num &&
          (city['latitude'] as num).abs() <= 90 &&
          (city['longitude'] as num).abs() <= 180) {
        prefs.city = city;
      }
      if (json['repos'] is List) {
        prefs.repos = (json['repos'] as List)
            .whereType<String>()
            .where(
              (repo) =>
                  RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repo),
            )
            .toSet()
            .take(4)
            .toList();
      }
      const currencies = [
        'CNY',
        'USD',
        'EUR',
        'GBP',
        'JPY',
        'HKD',
        'TWD',
        'SGD',
        'AUD',
        'CAD',
        'KRW',
        'CHF',
      ];
      if (currencies.contains(json['base'])) {
        prefs.base = json['base'] as String;
      }
      if (currencies.contains(json['quote'])) {
        prefs.quote = json['quote'] as String;
      }
      final amount = json['amount'];
      if (amount is num &&
          amount.isFinite &&
          amount >= 0 &&
          amount <= 1000000000) {
        prefs.amount = amount.toDouble();
      }
      if (['top', 'new', 'show'].contains(json['feed'])) {
        prefs.feed = json['feed'] as String;
      }
      final days = json['leaveDays'];
      if (days is int && days >= 0 && days <= 5) prefs.leaveDays = days;
      if (json['order'] is List) {
        prefs.order = <String>{
          ...(json['order'] as List).whereType<String>().where(
            dashboardModules.contains,
          ),
          ...dashboardModules,
        }.toList();
      }
      if (json['favorites'] is List) {
        prefs.favorites = (json['favorites'] as List)
            .whereType<String>()
            .where(dashboardModules.contains)
            .toSet()
            .toList();
      }
      return prefs;
    } catch (_) {
      return DashboardPreferences();
    }
  }

  String encode() => jsonEncode({
    'city': city,
    'repos': repos,
    'base': base,
    'quote': quote,
    'amount': amount,
    'feed': feed,
    'leaveDays': leaveDays,
    'order': order,
    'favorites': favorites,
  });
}
