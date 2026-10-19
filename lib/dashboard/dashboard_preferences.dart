import 'dart:convert';

import 'market_config.dart';
import 'crypto_market.dart';

const dashboardModules = ['weather', 'releases', 'news', 'market', 'crypto'];

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

class DashboardPreferences {
  DashboardPreferences({
    this.city,
    this.repos = defaultDashboardRepos,
    this.feed = 'sspai',
    this.marketIndex = 'shanghai',
    this.marketInterval = 'D',
    this.cryptoSymbol = 'BTCUSDT',
    this.cryptoInterval = '1h',
    this.order = dashboardModules,
    this.favorites = const ['weather'],
  });

  Map<String, dynamic>? city;
  List<String> repos;
  String feed;
  String marketIndex;
  String marketInterval;
  String cryptoSymbol;
  String cryptoInterval;
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
      prefs.marketIndex = marketIndexFor(
        json['marketIndex'] is String ? json['marketIndex'] as String : '',
      ).id;
      if (marketIntervals.containsKey(json['marketInterval'])) {
        prefs.marketInterval = json['marketInterval'] as String;
      }
      if (cryptoAssets.containsKey(json['cryptoSymbol'])) {
        prefs.cryptoSymbol = json['cryptoSymbol'] as String;
      }
      if (cryptoIntervals.containsKey(json['cryptoInterval'])) {
        prefs.cryptoInterval = json['cryptoInterval'] as String;
      }
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
    'marketIndex': marketIndex,
    'marketInterval': marketInterval,
    'cryptoSymbol': cryptoSymbol,
    'cryptoInterval': cryptoInterval,
    'order': order,
    'favorites': favorites,
  });
}
