import 'dart:convert';
import 'dart:io';

/// One atomic local file holds preferences and the shared data worker's caches.
class NativeStore {
  NativeStore(this.directory) {
    try {
      directory.createSync(recursive: true);
      if (file.existsSync()) {
        if (file.lengthSync() > maxBytes) throw const FormatException();
        final raw = jsonDecode(file.readAsStringSync());
        if (raw is! Map) throw const FormatException();
        for (final e in raw.entries) {
          if (e.key is! String ||
              !e.key.startsWith('shike.') ||
              e.value is! String) {
            throw const FormatException();
          }
          _values[e.key as String] = e.value as String;
        }
      }
    } catch (_) {
      _values.clear();
      available = false;
    }
  }
  static const maxBytes = 16 * 1024 * 1024;
  final Directory directory;
  File get file => File('${directory.path}/state.json');
  final _values = <String, String>{};
  bool available = true;
  Map<String, String> get snapshot => Map.of(_values);
  String? read(String key) => _values[key];

  bool write(String key, String? value) {
    if (!key.startsWith('shike.')) return false;
    final next = Map.of(_values);
    value == null ? next.remove(key) : next[key] = value;
    try {
      final raw = jsonEncode(next);
      if (utf8.encode(raw).length > maxBytes) return false;
      // Keep the original file when an unreadable store needs recovery.
      if (!available && file.existsSync()) {
        file.copySync('${file.path}.recovery');
      }
      final temporary = File('${file.path}.$pid.tmp');
      temporary.writeAsStringSync(raw, flush: true);
      temporary.renameSync(file.path);
      _values.clear();
      _values.addAll(next);
      available = true;
      return true;
    } catch (_) {
      available = false;
      return false;
    }
  }
}
