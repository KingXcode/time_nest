/// Article data is untrusted, even when read from a same-origin cached snapshot.
/// This model renders plain text only; it never loads article pages or HTML.
class NewsReusePermission {
  const NewsReusePermission({
    required this.licenseUrl,
    this.excerpt = false,
    this.full = false,
  });
  final String licenseUrl;
  final bool excerpt;
  final bool full;
}

/// A public RSS endpoint is not a public republication license. Add a source
/// only after reviewing an explicit grant, together with the generator/JS policy.
const newsReusePermissions = <String, NewsReusePermission>{};

String safeNewsUrl(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 4096 ||
      RegExp(r'[\x00-\x20\x7f\\]').hasMatch(value)) {
    return '';
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !const ['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return '';
  }
  return uri.toString();
}

String _text(Object? value, int maximum) {
  if (value is! String) return '';
  return String.fromCharCodes(value.runes.take(maximum))
      .replaceAll(
        RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u202a-\u202e\u2066-\u2069]'),
        '',
      )
      .trim();
}

DateTime? newsPublishedAt(Object? value) {
  if (value is num && value.isFinite && value > 0 && value < 8640000000000) {
    return DateTime.fromMillisecondsSinceEpoch((value * 1000).toInt())
        .toLocal();
  }
  return value is String && value.length <= 100
      ? DateTime.tryParse(value)?.toLocal()
      : null;
}

class NewsArticle {
  const NewsArticle._({
    required this.title,
    required this.url,
    required this.source,
    required this.sourceId,
    required this.discussion,
    required this.publishedAt,
    required this.kind,
    required this.reason,
    required this.body,
    required this.licenseUrl,
  });

  factory NewsArticle.fromJson(
    Map story, {
    Map<String, NewsReusePermission> permissions = newsReusePermissions,
  }) {
    final id = story['id'];
    final discussion = safeNewsUrl(story['discussion']).isNotEmpty
        ? safeNewsUrl(story['discussion'])
        : id is int && id > 0
        ? 'https://news.ycombinator.com/item?id=$id'
        : '';
    final rawUrl = safeNewsUrl(story['url']);
    final url = rawUrl.isNotEmpty ? rawUrl : discussion;
    final sourceId = _text(story['sourceId'], 40);
    final permission = permissions[sourceId];
    var kind = 'unavailable';
    var reason = permission == null ? 'permission_required' : 'not_provided';
    var body = '';
    var licenseUrl = '';
    final content = story['content'];
    if (permission != null && content is Map) {
      final candidate = content['kind'];
      final raw = content['text'];
      final allowed =
          candidate == 'full' && permission.full ||
          candidate == 'excerpt' && permission.excerpt;
      if (allowed &&
          content['format'] == 'plain_text' &&
          safeNewsUrl(content['licenseUrl']).startsWith('https://') &&
          content['licenseUrl'] == permission.licenseUrl &&
          raw is String) {
        final limit = candidate == 'full' ? 24000 : 280;
        // Reject, never silently truncate and mislabel a partial article as full.
        if (raw.length > limit * 2 || raw.runes.length > limit) {
          reason = 'too_large';
        } else {
          body = _text(raw, limit);
          if (body.isNotEmpty) {
            kind = candidate as String;
            licenseUrl = permission.licenseUrl;
          } else {
            reason = 'not_provided';
          }
        }
      } else if (candidate == 'unavailable' &&
          const [
            'permission_required',
            'not_provided',
            'invalid_content',
            'too_large',
          ].contains(content['reason'])) {
        reason = content['reason'] as String;
      } else {
        reason = 'invalid_content';
      }
    }
    final title = _text(story['title'], 500);
    final source = _text(story['source'], 80);
    return NewsArticle._(
      title: title.isEmpty ? '未命名文章' : title,
      url: url,
      source: source.isNotEmpty
          ? source
          : Uri.tryParse(url)?.host.replaceFirst(RegExp(r'^www\.'), '') ?? '',
      sourceId: sourceId,
      discussion: discussion,
      publishedAt: newsPublishedAt(story['time']),
      kind: kind,
      reason: reason,
      body: body,
      licenseUrl: licenseUrl,
    );
  }

  final String title, url, source, sourceId, discussion;
  final DateTime? publishedAt;
  final String kind, reason, body, licenseUrl;
}
