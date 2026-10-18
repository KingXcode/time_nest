import 'dart:convert';

const dashboardModules = ['weather', 'releases', 'fx', 'news'];

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
    this.base = 'USD',
    this.quote = 'CNY',
    this.amount = 100,
    this.feed = 'sspai',
    this.order = dashboardModules,
    this.favorites = const ['weather'],
  });

  Map<String, dynamic>? city;
  List<String> repos;
  String base;
  String quote;
  double amount;
  String feed;
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
      if (dashboardFeeds.contains(json['feed'])) {
        prefs.feed = json['feed'] as String;
      }
      if (json['version'] == null && json['feed'] == 'top') {
        prefs.feed = 'sspai';
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
    'version': 3,
    'city': city,
    'repos': repos,
    'base': base,
    'quote': quote,
    'amount': amount,
    'feed': feed,
    'order': order,
    'favorites': favorites,
  });
}
