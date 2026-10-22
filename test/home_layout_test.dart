import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/clock/home_layout.dart';

void main() {
  test('invalid documents and unknown versions use safe defaults', () {
    for (final raw in [
      null,
      [],
      'bad',
      {},
      {'version': 2},
    ]) {
      expect(HomeLayout.fromJson(raw), HomeLayout());
    }
  });

  test('corrupt fields fall back, finite outliers clamp inside the canvas', () {
    final layout = HomeLayout.fromJson({
      'version': 1,
      'enabled': true,
      'portrait': {
        'time': {'x': -20, 'y': 50, 'width': 3, 'height': -4},
        'date': {
          'x': double.nan,
          'y': double.infinity,
          'width': 'bad',
          'visible': 1,
        },
        'unknown': {},
      },
      'landscape': 'corrupt',
    });
    final time = layout.portrait['time']!;
    expect(time.x, 0);
    expect(time.y, closeTo(.94, .0001));
    expect(time.width, 1);
    expect(time.height, .06);
    expect(
      layout.portrait['date']!.toJson(),
      HomeLayout.defaults(false)['date']!.toJson(),
    );
    expect(layout.portrait.keys, unorderedEquals(homeModules));
    expect(
      layout.landscape.map((k, v) => MapEntry(k, v.toJson())),
      HomeLayout.defaults(true).map((k, v) => MapEntry(k, v.toJson())),
    );
  });

  test('round trip preserves distinct orientation edits and visibility', () {
    final initial = HomeLayout();
    final edited = initial.copyWith(
      enabled: true,
      portrait: {
        ...initial.portrait,
        'time': initial.portrait['time']!.copyWith(x: .2, width: .5),
        'weather': initial.portrait['weather']!.copyWith(visible: true),
      },
    );
    final restored = HomeLayout.fromJson(
      jsonDecode(jsonEncode(edited.toJson())),
    );
    expect(restored, edited);
    expect(restored.hashCode, edited.hashCode);
    expect(restored.forOrientation(false)['time']!.x, .2);
    expect(restored.forOrientation(true)['time']!.x, .1);
    expect(initial.enabled, isFalse);
    expect(initial.portrait['weather']!.visible, isFalse);
    expect(
      () => restored.portrait['time'] = initial.portrait['time']!,
      throwsUnsupportedError,
    );
  });

  test(
    'copyWith ignores non-finite edits and clamps position after resizing',
    () {
      const item = HomeModuleLayout(x: .6, y: .6, width: .3, height: .3);
      expect(
        item.copyWith(x: double.nan, width: double.infinity).toJson(),
        item.toJson(),
      );
      final resized = item.copyWith(width: .8, height: .9);
      expect(resized.x, closeTo(.2, .0001));
      expect(resized.y, closeTo(.1, .0001));
    },
  );
}
