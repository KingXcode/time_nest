import 'dart:convert';
import 'dart:math' as math;

/// Immutable clock preferences, independent of Flutter and browser storage.
///
/// The const constructor accepts trusted, typed values. Persisted values and
/// edits through [copyWith] are normalized before constructing a new instance.
final class ClockSettings {
  const ClockSettings({
    this.hourCycle = 'h23',
    this.showSeconds = true,
    this.showMilliseconds = true,
    this.textIntensity = 1.0,
    this.nightEnabled = false,
    this.nightStart = '22:00',
    this.nightEnd = '07:00',
    this.nightIntensity = 0.25,
    this.keepAwake = false,
    this.showDate = true,
    this.tone = 'neutral',
    this.orientation = 'auto',
  });

  final String hourCycle;
  final bool showSeconds;
  final bool showMilliseconds;
  final double textIntensity;
  final bool nightEnabled;
  final String nightStart;
  final String nightEnd;
  final double nightIntensity;
  final bool keepAwake;
  final bool showDate;
  final String tone;
  final String orientation;

  String get preset {
    if (showDate &&
        showSeconds &&
        !showMilliseconds &&
        tone == 'neutral' &&
        !nightEnabled &&
        textIntensity == 1) {
      return 'office';
    }
    if (showDate &&
        !showSeconds &&
        !showMilliseconds &&
        tone == 'warm' &&
        nightEnabled &&
        textIntensity == .65 &&
        nightIntensity == .2) {
      return 'bedside';
    }
    if (!showDate &&
        !showSeconds &&
        !showMilliseconds &&
        tone == 'neutral' &&
        !nightEnabled &&
        textIntensity == 1) {
      return 'minimal';
    }
    return 'custom';
  }

  ClockSettings applyPreset(String preset) => switch (preset) {
    'office' => copyWith(
      showDate: true,
      showSeconds: true,
      showMilliseconds: false,
      tone: 'neutral',
      textIntensity: 1,
      nightEnabled: false,
    ),
    'bedside' => copyWith(
      showDate: true,
      showSeconds: false,
      showMilliseconds: false,
      tone: 'warm',
      textIntensity: .65,
      nightEnabled: true,
      nightIntensity: .2,
    ),
    'minimal' => copyWith(
      showDate: false,
      showSeconds: false,
      showMilliseconds: false,
      tone: 'neutral',
      textIntensity: 1,
      nightEnabled: false,
    ),
    _ => this,
  };

  /// Hiding seconds never destroys the user's millisecond preference.
  bool get effectiveMilliseconds => showSeconds && showMilliseconds;

  /// Whether [time]'s wall-clock time falls in the half-open night interval.
  ///
  /// The caller supplies local time when local-time behavior is desired. This
  /// method never samples the clock or changes the supplied time zone.
  bool isNight(DateTime time) {
    if (!nightEnabled) return false;

    final start = _minutes(_readTime(nightStart, '22:00'));
    final end = _minutes(_readTime(nightEnd, '07:00'));
    if (start == end) return false;

    final current = time.hour * 60 + time.minute;
    if (start < end) return current >= start && current < end;
    return current >= start || current < end;
  }

  /// Night mode can dim the text, but can never make it brighter.
  double intensityAt(DateTime time) {
    final normal = _readIntensity(textIntensity, 1.0);
    if (!isNight(time)) return normal;
    return math.min(normal, _readIntensity(nightIntensity, 0.25));
  }

  /// Null arguments preserve their current preference; supplied values are
  /// normalized using the same rules as persisted settings.
  ClockSettings copyWith({
    String? hourCycle,
    bool? showSeconds,
    bool? showMilliseconds,
    double? textIntensity,
    bool? nightEnabled,
    String? nightStart,
    String? nightEnd,
    double? nightIntensity,
    bool? keepAwake,
    bool? showDate,
    String? tone,
    String? orientation,
  }) {
    return ClockSettings(
      hourCycle: _readHourCycle(hourCycle ?? this.hourCycle),
      showSeconds: showSeconds ?? this.showSeconds,
      showMilliseconds: showMilliseconds ?? this.showMilliseconds,
      textIntensity: _readIntensity(textIntensity ?? this.textIntensity, 1.0),
      nightEnabled: nightEnabled ?? this.nightEnabled,
      nightStart: _readTime(nightStart ?? this.nightStart, '22:00'),
      nightEnd: _readTime(nightEnd ?? this.nightEnd, '07:00'),
      nightIntensity: _readIntensity(
        nightIntensity ?? this.nightIntensity,
        0.25,
      ),
      keepAwake: keepAwake ?? this.keepAwake,
      showDate: showDate ?? this.showDate,
      tone: _choice(tone ?? this.tone, ['neutral', 'warm'], 'neutral'),
      orientation: _choice(orientation ?? this.orientation, [
        'auto',
        'landscape',
        'portrait',
      ], 'auto'),
    );
  }

  /// Produces the version-1 storage schema, including nested night settings.
  /// Invalid values from a direct constructor are normalized for safe encoding.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': 1,
      'hourCycle': _readHourCycle(hourCycle),
      'showSeconds': showSeconds,
      'showMilliseconds': showMilliseconds,
      'textIntensity': _readIntensity(textIntensity, 1.0),
      'nightMode': <String, dynamic>{
        'enabled': nightEnabled,
        'start': _readTime(nightStart, '22:00'),
        'end': _readTime(nightEnd, '07:00'),
        'textIntensity': _readIntensity(nightIntensity, 0.25),
      },
      'keepAwake': keepAwake,
      'showDate': showDate,
      'tone': tone,
      'orientation': orientation,
    };
  }

  /// Reads only the supported version and strictly validates each field.
  ///
  /// Unsupported/missing versions or non-map roots reset the entire model.
  /// Otherwise a bad field resets only that field, not its valid neighbors.
  factory ClockSettings.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) return const ClockSettings();
    final version = value['version'];
    if (version is! int || version != 1) return const ClockSettings();

    final nightValue = value['nightMode'];
    final night = nightValue is Map<Object?, Object?>
        ? nightValue
        : const <String, Object?>{};
    return ClockSettings(
      hourCycle: _readHourCycle(value['hourCycle']),
      showSeconds: _readBool(value['showSeconds'], true),
      showMilliseconds: _readBool(value['showMilliseconds'], true),
      textIntensity: _readIntensity(value['textIntensity'], 1.0),
      nightEnabled: _readBool(night['enabled'], false),
      nightStart: _readTime(night['start'], '22:00'),
      nightEnd: _readTime(night['end'], '07:00'),
      nightIntensity: _readIntensity(night['textIntensity'], 0.25),
      keepAwake: _readBool(value['keepAwake'], false),
      showDate: _readBool(value['showDate'], true),
      tone: _choice(value['tone'], ['neutral', 'warm'], 'neutral'),
      orientation: _choice(value['orientation'], [
        'auto',
        'landscape',
        'portrait',
      ], 'auto'),
    );
  }

  /// Corrupt or absent storage must not prevent the clock from working.
  static ClockSettings decode(String? raw) {
    if (raw == null) return const ClockSettings();
    try {
      return ClockSettings.fromJson(jsonDecode(raw));
    } on FormatException {
      return const ClockSettings();
    }
  }

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ClockSettings &&
            hourCycle == other.hourCycle &&
            showSeconds == other.showSeconds &&
            showMilliseconds == other.showMilliseconds &&
            textIntensity == other.textIntensity &&
            nightEnabled == other.nightEnabled &&
            nightStart == other.nightStart &&
            nightEnd == other.nightEnd &&
            nightIntensity == other.nightIntensity &&
            keepAwake == other.keepAwake &&
            showDate == other.showDate &&
            tone == other.tone &&
            orientation == other.orientation;
  }

  @override
  int get hashCode => Object.hash(
    hourCycle,
    showSeconds,
    showMilliseconds,
    textIntensity,
    nightEnabled,
    nightStart,
    nightEnd,
    nightIntensity,
    keepAwake,
    showDate,
    tone,
    orientation,
  );

  static String _choice(Object? value, List<String> values, String fallback) =>
      value is String && values.contains(value) ? value : fallback;

  static bool _readBool(Object? value, bool fallback) {
    return value is bool ? value : fallback;
  }

  static String _readHourCycle(Object? value) {
    return value is String && value == 'h12' ? 'h12' : 'h23';
  }

  static double _readIntensity(Object? value, double fallback) {
    if (value is! num || !value.isFinite) return fallback;
    return value.toDouble().clamp(0.15, 1.0).toDouble();
  }

  static final RegExp _timePattern = RegExp(
    r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$',
  );

  static String _readTime(Object? value, String fallback) {
    // The length check also rejects a trailing newline accepted by some `$`
    // regular-expression implementations.
    return value is String && value.length == 5 && _timePattern.hasMatch(value)
        ? value
        : fallback;
  }

  static int _minutes(String value) {
    return int.parse(value.substring(0, 2)) * 60 +
        int.parse(value.substring(3, 5));
  }
}
