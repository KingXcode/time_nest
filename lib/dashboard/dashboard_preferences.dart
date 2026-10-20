import 'dart:convert';

import 'crypto_market.dart';
import 'crypto_indicators.dart';
import 'crypto_view_settings.dart';

const dashboardModules = ['weather', 'releases', 'news', 'crypto'];

// Curated popular projects, not a live star ranking. No authentication required.
const defaultDashboardRepos = [
  'flutter/flutter',
  'ollama/ollama',
  'langgenius/dify',
  'microsoft/vscode',
  'open-webui/open-webui',
  'n8n-io/n8n',
  'huggingface/transformers',
  'langchain-ai/langchain',
  'ggml-org/llama.cpp',
  'Comfy-Org/ComfyUI',
  'react/react',
  'vuejs/core',
  'vercel/next.js',
  'sveltejs/svelte',
  'vitejs/vite',
  'tailwindlabs/tailwindcss',
  'microsoft/TypeScript',
  'nodejs/node',
  'denoland/deno',
  'oven-sh/bun',
  'rust-lang/rust',
  'astral-sh/uv',
  'kubernetes/kubernetes',
  'react/react-native',
];
const maxDashboardRepos = 50;
const dashboardFeeds = ['sspai', 'top', 'new', 'show'];

const cryptoMinPaneHeight = 64.0, cryptoMaxPaneHeight = 400.0;

Map<String, double> cleanCryptoPaneHeights(Object? raw) {
  if (raw is! Map) return {};
  return {
    for (final entry in raw.entries)
      if (cryptoIndicators[entry.key]?.overlay == false &&
          entry.value is num &&
          (entry.value as num).isFinite)
        entry.key as String: (entry.value as num).toDouble().clamp(
          cryptoMinPaneHeight,
          cryptoMaxPaneHeight,
        ),
  };
}

int? cleanCryptoBookLevels(Object? raw) =>
    raw is int && const [5, 10, 20].contains(raw) ? raw : null;

Map<String, double> cleanCryptoBookSteps(Object? raw) {
  if (raw is! Map) return {};
  return {
    for (final entry in raw.entries)
      if (cryptoAssets.containsKey(entry.key) &&
          entry.value is num &&
          (entry.value as num).isFinite &&
          (entry.value as num) > 0 &&
          (entry.value as num) <= 1e12)
        entry.key as String: (entry.value as num).toDouble(),
  };
}

class DashboardPreferences {
  DashboardPreferences({
    this.city,
    this.repos = defaultDashboardRepos,
    this.feed = 'sspai',
    this.cryptoSymbol = 'BTCUSDT',
    this.cryptoInterval = '1h',
    this.cryptoOverlays = defaultCryptoOverlays,
    this.cryptoPanes = defaultCryptoPanes,
    this.cryptoInfoRight = false,
    this.cryptoCurrency = 'USD',
    this.cryptoBookLevels,
    this.cryptoBookSteps = const {},
    this.cryptoPaneHeights = const {},
    this.cryptoView = const CryptoViewSettings(),
    this.order = dashboardModules,
    this.favorites = const ['weather'],
  });

  Map<String, dynamic>? city;
  List<String> repos;
  String feed;
  String cryptoSymbol;
  String cryptoInterval;
  List<String> cryptoOverlays, cryptoPanes;
  bool cryptoInfoRight;
  CryptoViewSettings cryptoView;
  String cryptoCurrency;
  int? cryptoBookLevels;
  Map<String, double> cryptoBookSteps;
  Map<String, double> cryptoPaneHeights;
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
            .map((repo) => repo.toLowerCase())
            .toSet()
            .take(maxDashboardRepos)
            .toList();
      }
      // Upgrade only the exact old shipped default. Custom and empty lists stay
      // intact; versioned preferences never silently re-follow removed projects.
      if (json['version'] == null &&
          json['repos'] is List &&
          (json['repos'] as List).length == 1 &&
          (json['repos'] as List).first == 'flutter/flutter') {
        prefs.repos = List.of(defaultDashboardRepos);
      }
      if (dashboardFeeds.contains(json['feed'])) {
        prefs.feed = json['feed'] as String;
      }
      if (json['version'] == null && json['feed'] == 'top') {
        prefs.feed = 'sspai';
      }
      if (cryptoAssets.containsKey(json['cryptoSymbol'])) {
        prefs.cryptoSymbol = json['cryptoSymbol'] as String;
      }
      if (cryptoIntervals.containsKey(json['cryptoInterval'])) {
        prefs.cryptoInterval = json['cryptoInterval'] as String;
      }
      prefs.cryptoOverlays = cleanIndicators(
        json['cryptoOverlays'],
        overlay: true,
        fallback: defaultCryptoOverlays,
      );
      prefs.cryptoPanes = cleanIndicators(
        json['cryptoPanes'],
        overlay: false,
        fallback: defaultCryptoPanes,
      );
      if (const ['USD', 'CNY'].contains(json['cryptoCurrency'])) {
        prefs.cryptoCurrency = json['cryptoCurrency'] as String;
      }
      prefs.cryptoBookLevels = cleanCryptoBookLevels(json['cryptoBookLevels']);
      prefs.cryptoBookSteps = cleanCryptoBookSteps(json['cryptoBookSteps']);
      prefs.cryptoInfoRight = json['cryptoInfoRight'] == true;
      prefs.cryptoView = CryptoViewSettings.decode(json['cryptoView']);
      prefs.cryptoPaneHeights = cleanCryptoPaneHeights(
        json['cryptoPaneHeights'],
      );
      // Ignore retired module settings and filter their navigation IDs while
      // keeping the relative order and favorites of every active module.
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
    'version': 4,
    'city': city,
    'repos': repos,
    'feed': feed,
    'cryptoSymbol': cryptoSymbol,
    'cryptoInterval': cryptoInterval,
    'cryptoOverlays': cryptoOverlays,
    'cryptoPanes': cryptoPanes,
    'cryptoInfoRight': cryptoInfoRight,
    'cryptoCurrency': cryptoCurrency,
    'cryptoBookLevels': cleanCryptoBookLevels(cryptoBookLevels),
    'cryptoBookSteps': cleanCryptoBookSteps(cryptoBookSteps),
    'cryptoPaneHeights': cleanCryptoPaneHeights(cryptoPaneHeights),
    'cryptoView': cryptoView.toJson(),
    'order': order,
    'favorites': favorites,
  });
}
