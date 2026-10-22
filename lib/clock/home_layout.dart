import 'dart:convert';

const homeModules = ['time', 'date', 'weather', 'crypto'];
const homeModuleLabels = {
  'time': '时间',
  'date': '日期',
  'weather': '天气',
  'crypto': 'K 线',
};

/// Positions and sizes are fractions of the safe display canvas, not pixels.
/// Separate orientation documents prevent a rotation from rewriting user edits.
class HomeModuleLayout {
  const HomeModuleLayout({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.visible = true,
  });
  final double x, y, width, height;
  final bool visible;
  HomeModuleLayout copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    bool? visible,
  }) {
    final w = _number(width ?? this.width, this.width).clamp(.12, 1.0);
    final h = _number(height ?? this.height, this.height).clamp(.06, 1.0);
    return HomeModuleLayout(
      x: _number(x ?? this.x, this.x).clamp(0, 1 - w),
      y: _number(y ?? this.y, this.y).clamp(0, 1 - h),
      width: w,
      height: h,
      visible: visible ?? this.visible,
    );
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'visible': visible,
  };
  static HomeModuleLayout read(Object? raw, HomeModuleLayout fallback) {
    if (raw is! Map) return fallback;
    return fallback.copyWith(
      x: _number(raw['x'], fallback.x),
      y: _number(raw['y'], fallback.y),
      width: _number(raw['width'], fallback.width),
      height: _number(raw['height'], fallback.height),
      visible: raw['visible'] is bool
          ? raw['visible'] as bool
          : fallback.visible,
    );
  }

  static double _number(Object? value, double fallback) =>
      value is num && value.isFinite ? value.toDouble() : fallback;
}

class HomeLayout {
  HomeLayout({
    this.enabled = false,
    Map<String, HomeModuleLayout>? portrait,
    Map<String, HomeModuleLayout>? landscape,
  }) : portrait = Map.unmodifiable(portrait ?? defaults(false)),
       landscape = Map.unmodifiable(landscape ?? defaults(true));
  final bool enabled;
  final Map<String, HomeModuleLayout> portrait, landscape;
  Map<String, HomeModuleLayout> forOrientation(bool wide) =>
      wide ? landscape : portrait;
  HomeLayout copyWith({
    bool? enabled,
    Map<String, HomeModuleLayout>? portrait,
    Map<String, HomeModuleLayout>? landscape,
  }) => HomeLayout(
    enabled: enabled ?? this.enabled,
    portrait: portrait ?? this.portrait,
    landscape: landscape ?? this.landscape,
  );
  static Map<String, HomeModuleLayout> defaults(bool wide) => wide
      ? const {
          'date': HomeModuleLayout(x: .1, y: .05, width: .8, height: .10),
          'time': HomeModuleLayout(x: .1, y: .17, width: .8, height: .3),
          'weather': HomeModuleLayout(
            x: .03,
            y: .55,
            width: .3,
            height: .4,
            visible: false,
          ),
          'crypto': HomeModuleLayout(
            x: .37,
            y: .55,
            width: .6,
            height: .4,
            visible: false,
          ),
        }
      : const {
          'date': HomeModuleLayout(x: .06, y: .10, width: .88, height: .08),
          'time': HomeModuleLayout(x: .03, y: .20, width: .94, height: .16),
          'weather': HomeModuleLayout(
            x: .06,
            y: .41,
            width: .88,
            height: .18,
            visible: false,
          ),
          'crypto': HomeModuleLayout(
            x: .06,
            y: .64,
            width: .88,
            height: .3,
            visible: false,
          ),
        };
  factory HomeLayout.fromJson(Object? raw) {
    if (raw is! Map || raw['version'] != 1) return HomeLayout();
    Map<String, HomeModuleLayout> read(bool wide) {
      final value = raw[wide ? 'landscape' : 'portrait'];
      return {
        for (final entry in defaults(wide).entries)
          entry.key: HomeModuleLayout.read(
            value is Map ? value[entry.key] : null,
            entry.value,
          ),
      };
    }

    return HomeLayout(
      enabled: raw['enabled'] == true,
      portrait: read(false),
      landscape: read(true),
    );
  }
  Map<String, dynamic> toJson() => {
    'version': 1,
    'enabled': enabled,
    'portrait': portrait.map((k, v) => MapEntry(k, v.toJson())),
    'landscape': landscape.map((k, v) => MapEntry(k, v.toJson())),
  };
  @override
  bool operator ==(Object other) =>
      other is HomeLayout && jsonEncode(toJson()) == jsonEncode(other.toJson());
  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}
