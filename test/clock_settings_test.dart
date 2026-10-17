import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/clock/clock_settings.dart';

void main() {
  const defaults = ClockSettings();

  group('defaults and immutable edits', () {
    test('const defaults match the v1 preferences', () {
      expect(defaults.hourCycle, 'h23');
      expect(defaults.showSeconds, isTrue);
      expect(defaults.showMilliseconds, isTrue);
      expect(defaults.effectiveMilliseconds, isTrue);
      expect(defaults.textIntensity, 1.0);
      expect(defaults.nightEnabled, isFalse);
      expect(defaults.nightStart, '22:00');
      expect(defaults.nightEnd, '07:00');
      expect(defaults.nightIntensity, 0.25);
      expect(defaults.keepAwake, isFalse);
    });

    test('copyWith changes every field without mutating the source', () {
      final edited = defaults.copyWith(
        hourCycle: 'h12',
        showSeconds: false,
        showMilliseconds: false,
        textIntensity: 0.7,
        nightEnabled: true,
        nightStart: '21:30',
        nightEnd: '06:15',
        nightIntensity: 0.2,
        keepAwake: true,
      );
      expect(
        edited,
        const ClockSettings(
          hourCycle: 'h12',
          showSeconds: false,
          showMilliseconds: false,
          textIntensity: 0.7,
          nightEnabled: true,
          nightStart: '21:30',
          nightEnd: '06:15',
          nightIntensity: 0.2,
          keepAwake: true,
        ),
      );
      expect(defaults, const ClockSettings());
      expect(edited.copyWith(), edited);
      expect(
        edited.copyWith(
          hourCycle: null,
          showSeconds: null,
          showMilliseconds: null,
          textIntensity: null,
          nightEnabled: null,
          nightStart: null,
          nightEnd: null,
          nightIntensity: null,
          keepAwake: null,
        ),
        edited,
      );
    });

    test(
      'effective milliseconds follows the complete visibility truth table',
      () {
        for (final seconds in <bool>[false, true]) {
          for (final milliseconds in <bool>[false, true]) {
            final settings = ClockSettings(
              showSeconds: seconds,
              showMilliseconds: milliseconds,
            );
            expect(settings.effectiveMilliseconds, seconds && milliseconds);
            expect(settings.showMilliseconds, milliseconds);
          }
        }
      },
    );

    test(
      'hiding seconds retains either millisecond preference across storage',
      () {
        for (final preference in <bool>[false, true]) {
          final original = defaults.copyWith(showMilliseconds: preference);
          final hidden = original.copyWith(showSeconds: false);
          expect(hidden.showMilliseconds, preference);
          expect(hidden.effectiveMilliseconds, isFalse);
          final restored = ClockSettings.decode(hidden.encode());
          expect(restored, hidden);
          final visible = restored.copyWith(showSeconds: true);
          expect(visible.showMilliseconds, preference);
          expect(visible.effectiveMilliseconds, preference);
          expect(visible, original);
        }
      },
    );

    test('copyWith normalizes invalid preferences and clamps brightness', () {
      final edited = defaults.copyWith(
        hourCycle: 'h24',
        textIntensity: -20,
        nightStart: '7:00',
        nightEnd: '24:00',
        nightIntensity: 20,
      );
      expect(edited.hourCycle, 'h23');
      expect(edited.textIntensity, 0.15);
      expect(edited.nightStart, '22:00');
      expect(edited.nightEnd, '07:00');
      expect(edited.nightIntensity, 1.0);
      for (final value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final normalized = edited.copyWith(
          textIntensity: value,
          nightIntensity: value,
        );
        expect(normalized.textIntensity, 1.0);
        expect(normalized.nightIntensity, 0.25);
      }
    });
  });

  group('strict versioned JSON decoding', () {
    test('absent, scalar and list roots return all defaults', () {
      for (final value in <Object?>[
        null,
        true,
        false,
        1,
        1.5,
        'settings',
        <Object?>[],
        <Object?>[1],
        <String, Object?>{},
      ]) {
        expect(ClockSettings.fromJson(value), defaults, reason: '$value');
      }
    });

    test(
      'unsupported, missing and wrongly typed versions reset everything',
      () {
        for (final version in <Object?>[
          null,
          0,
          2,
          -1,
          '1',
          1.0,
          true,
          <int>[],
        ]) {
          expect(
            ClockSettings.fromJson(<String, Object?>{
              'version': version,
              'hourCycle': 'h12',
              'showSeconds': false,
              'textIntensity': 0.5,
              'keepAwake': true,
              'nightMode': <String, Object?>{'enabled': true},
            }),
            defaults,
            reason: 'version=$version (${version.runtimeType})',
          );
        }
        expect(
          ClockSettings.fromJson(<String, Object?>{'hourCycle': 'h12'}),
          defaults,
        );
        expect(
          ClockSettings.fromJson(<String, Object?>{'version': 1}),
          defaults,
        );
      },
    );

    test(
      'valid nested schema restores all fields and ignores unknown fields',
      () {
        final settings = ClockSettings.fromJson(<String, Object?>{
          'version': 1,
          'hourCycle': 'h12',
          'showSeconds': false,
          'showMilliseconds': false,
          'textIntensity': 0.6,
          'keepAwake': true,
          'futureOption': 'ignored',
          'nightMode': <String, Object?>{
            'enabled': true,
            'start': '23:10',
            'end': '05:45',
            'textIntensity': 0.2,
            'futureOption': 'ignored',
          },
        });
        expect(
          settings,
          const ClockSettings(
            hourCycle: 'h12',
            showSeconds: false,
            showMilliseconds: false,
            textIntensity: 0.6,
            nightEnabled: true,
            nightStart: '23:10',
            nightEnd: '05:45',
            nightIntensity: 0.2,
            keepAwake: true,
          ),
        );
      },
    );

    test('only boolean values are accepted for boolean fields', () {
      for (final invalid in <Object?>[
        null,
        'true',
        'false',
        0,
        1,
        <Object?>[],
        <String, Object?>{},
      ]) {
        final settings = ClockSettings.fromJson(<String, Object?>{
          'version': 1,
          'hourCycle': 'h12',
          'showSeconds': invalid,
          'showMilliseconds': invalid,
          'keepAwake': invalid,
          'nightMode': <String, Object?>{'enabled': invalid},
        });
        expect(settings.hourCycle, 'h12');
        expect(settings.showSeconds, isTrue, reason: '$invalid');
        expect(settings.showMilliseconds, isTrue, reason: '$invalid');
        expect(settings.keepAwake, isFalse, reason: '$invalid');
        expect(settings.nightEnabled, isFalse, reason: '$invalid');
      }
    });

    test('hour cycle accepts only the two exact supported strings', () {
      for (final value in <Object?>[
        null,
        12,
        true,
        'H12',
        'h24',
        'h12 ',
        <String>['h12'],
        <String, Object?>{},
      ]) {
        expect(
          ClockSettings.fromJson(<String, Object?>{
            'version': 1,
            'hourCycle': value,
          }).hourCycle,
          'h23',
          reason: '$value',
        );
      }
      for (final value in <String>['h12', 'h23']) {
        expect(
          ClockSettings.fromJson(<String, Object?>{
            'version': 1,
            'hourCycle': value,
          }).hourCycle,
          value,
        );
      }
    });

    test('finite numeric brightness is converted to double and clamped', () {
      final cases = <num, double>{
        -100: 0.15,
        0: 0.15,
        0.149: 0.15,
        0.15: 0.15,
        0.25: 0.25,
        0.999: 0.999,
        1: 1.0,
        1.001: 1.0,
        100: 1.0,
      };
      for (final entry in cases.entries) {
        final settings = ClockSettings.fromJson(<String, Object?>{
          'version': 1,
          'textIntensity': entry.key,
          'nightMode': <String, Object?>{'textIntensity': entry.key},
        });
        expect(settings.textIntensity, entry.value, reason: '${entry.key}');
        expect(settings.nightIntensity, entry.value, reason: '${entry.key}');
        expect(settings.textIntensity, isA<double>());
        expect(settings.nightIntensity, isA<double>());
      }
    });

    test('non-numeric and non-finite brightness uses each field default', () {
      for (final invalid in <Object?>[
        null,
        '0.5',
        true,
        false,
        <Object?>[],
        <String, Object?>{},
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final settings = ClockSettings.fromJson(<String, Object?>{
          'version': 1,
          'textIntensity': invalid,
          'keepAwake': true,
          'nightMode': <String, Object?>{
            'enabled': true,
            'textIntensity': invalid,
          },
        });
        expect(settings.textIntensity, 1.0, reason: '$invalid');
        expect(settings.nightIntensity, 0.25, reason: '$invalid');
        expect(settings.keepAwake, isTrue);
        expect(settings.nightEnabled, isTrue);
      }
    });

    test('night times accept strict zero-padded HH:mm', () {
      for (final value in <String>[
        '00:00',
        '01:09',
        '09:59',
        '10:00',
        '19:59',
        '20:00',
        '23:59',
      ]) {
        final settings = ClockSettings.fromJson(<String, Object?>{
          'version': 1,
          'nightMode': <String, Object?>{'start': value, 'end': value},
        });
        expect(settings.nightStart, value);
        expect(settings.nightEnd, value);
      }
    });

    test('invalid night times fall back independently without coercion', () {
      for (final invalid in <Object?>[
        null,
        2200,
        true,
        '',
        '7:00',
        '00:0',
        '24:00',
        '23:60',
        '-1:00',
        '22:00:00',
        ' 22:00',
        '22:00 ',
        '22:00\n',
        '２２:００',
        <String>['22:00'],
      ]) {
        final settings = ClockSettings.fromJson(<String, Object?>{
          'version': 1,
          'nightMode': <String, Object?>{
            'enabled': true,
            'start': invalid,
            'end': invalid,
            'textIntensity': 0.4,
          },
        });
        expect(settings.nightStart, '22:00', reason: '$invalid');
        expect(settings.nightEnd, '07:00', reason: '$invalid');
        expect(settings.nightEnabled, isTrue);
        expect(settings.nightIntensity, 0.4);
      }
      final partial = ClockSettings.fromJson(<String, Object?>{
        'version': 1,
        'nightMode': <String, Object?>{'start': 'bad', 'end': '04:30'},
      });
      expect(partial.nightStart, '22:00');
      expect(partial.nightEnd, '04:30');
    });

    test(
      'bad nightMode resets only night fields and flat night keys are ignored',
      () {
        for (final invalid in <Object?>[null, true, 1, 'night', <Object?>[]]) {
          final settings = ClockSettings.fromJson(<String, Object?>{
            'version': 1,
            'hourCycle': 'h12',
            'showSeconds': false,
            'nightEnabled': true,
            'nightStart': '01:00',
            'nightEnd': '02:00',
            'nightIntensity': 0.9,
            'nightMode': invalid,
          });
          expect(
            settings,
            defaults.copyWith(hourCycle: 'h12', showSeconds: false),
          );
        }
      },
    );
  });

  group('storage and value semantics', () {
    test('toJson emits exactly the documented nested v1 schema', () {
      expect(defaults.toJson(), <String, Object?>{
        'version': 1,
        'hourCycle': 'h23',
        'showSeconds': true,
        'showMilliseconds': true,
        'textIntensity': 1.0,
        'nightMode': <String, Object?>{
          'enabled': false,
          'start': '22:00',
          'end': '07:00',
          'textIntensity': 0.25,
        },
        'keepAwake': false,
        'showDate': true,
        'tone': 'neutral',
        'orientation': 'auto',
      });
      expect(jsonDecode(defaults.encode()), defaults.toJson());
    });

    test('returned JSON is detached from the immutable settings', () {
      final json = defaults.toJson();
      json['hourCycle'] = 'h12';
      (json['nightMode'] as Map<String, dynamic>)['start'] = '00:00';
      expect(defaults.hourCycle, 'h23');
      expect(defaults.nightStart, '22:00');
      expect(defaults.toJson()['hourCycle'], 'h23');
      expect((defaults.toJson()['nightMode'] as Map)['start'], '22:00');
    });

    test('corrupt JSON, JSON scalars and missing storage are safe', () {
      for (final raw in <String?>[
        null,
        '',
        '   ',
        '{',
        '{"version":1,}',
        'not JSON',
        'null',
        'true',
        'false',
        '1',
        '"text"',
        '[]',
        '{}',
        '{"version":2,"hourCycle":"h12"}',
      ]) {
        expect(ClockSettings.decode(raw), defaults, reason: '$raw');
      }
    });

    test(
      'encode/decode and map round trips preserve all valid preferences',
      () {
        final cases = <ClockSettings>[
          defaults,
          const ClockSettings(
            hourCycle: 'h12',
            showSeconds: false,
            showMilliseconds: true,
            textIntensity: 0.15,
            nightEnabled: true,
            nightStart: '23:59',
            nightEnd: '00:00',
            nightIntensity: 1.0,
            keepAwake: true,
          ),
          const ClockSettings(showMilliseconds: false, textIntensity: 0.654321),
        ];
        for (final settings in cases) {
          expect(ClockSettings.fromJson(settings.toJson()), settings);
          expect(ClockSettings.decode(settings.encode()), settings);
          expect(
            ClockSettings.decode(settings.encode()).encode(),
            settings.encode(),
          );
        }
      },
    );

    test(
      'normalization is idempotent and encoding rejects no invalid doubles',
      () {
        const invalid = ClockSettings(
          hourCycle: 'unknown',
          textIntensity: double.nan,
          nightStart: '25:99',
          nightEnd: '7:00',
          nightIntensity: double.infinity,
        );
        final normalized = ClockSettings.decode(invalid.encode());
        expect(normalized, defaults);
        expect(normalized.copyWith(), normalized);
        expect(ClockSettings.decode(normalized.encode()), normalized);
        final clamped = ClockSettings.fromJson(<String, Object?>{
          'version': 1,
          'textIntensity': -1,
          'nightMode': <String, Object?>{'textIntensity': 2},
        });
        expect(ClockSettings.fromJson(clamped.toJson()), clamped);
      },
    );

    test('equality compares all nine preferences and hashCode supports collections', () {
      final equal = ClockSettings.fromJson(defaults.toJson());
      expect(equal, defaults);
      expect(defaults, equal);
      expect(equal.hashCode, defaults.hashCode);
      expect(<ClockSettings>{defaults, equal}, hasLength(1));
      expect(defaults == Object(), isFalse);
      final variants = <ClockSettings>[
        defaults.copyWith(hourCycle: 'h12'),
        defaults.copyWith(showSeconds: false),
        defaults.copyWith(showMilliseconds: false),
        defaults.copyWith(textIntensity: 0.8),
        defaults.copyWith(nightEnabled: true),
        defaults.copyWith(nightStart: '21:00'),
        defaults.copyWith(nightEnd: '08:00'),
        defaults.copyWith(nightIntensity: 0.3),
        defaults.copyWith(keepAwake: true),
      ];
      for (final variant in variants) {
        expect(variant, isNot(defaults));
        expect(ClockSettings.decode(variant.encode()), variant);
        expect(
          ClockSettings.decode(variant.encode()).hashCode,
          variant.hashCode,
        );
      }
      expect(<ClockSettings>{defaults, ...variants}, hasLength(10));
    });
  });

  group('night interval and intensity', () {
    test('night mode is opt-in even inside its configured interval', () {
      final time = DateTime(2026, 10, 16, 23);
      expect(defaults.isNight(time), isFalse);
      expect(defaults.intensityAt(time), 1.0);
    });

    test('cross-midnight range includes start and excludes end precisely', () {
      const settings = ClockSettings(nightEnabled: true);
      final cases = <DateTime, bool>{
        DateTime(2026, 10, 16, 21, 59, 59, 999, 999): false,
        DateTime(2026, 10, 16, 22): true,
        DateTime(2026, 10, 16, 23, 59, 59, 999, 999): true,
        DateTime(2026, 10, 17): true,
        DateTime(2026, 10, 17, 6, 59, 59, 999, 999): true,
        DateTime(2026, 10, 17, 7): false,
        DateTime(2026, 10, 17, 12): false,
      };
      for (final entry in cases.entries) {
        expect(
          settings.isNight(entry.key),
          entry.value,
          reason: '${entry.key}',
        );
        expect(settings.intensityAt(entry.key), entry.value ? 0.25 : 1.0);
      }
    });

    test('same-day range has identical half-open boundary semantics', () {
      const settings = ClockSettings(
        nightEnabled: true,
        nightStart: '09:15',
        nightEnd: '10:30',
      );
      final cases = <DateTime, bool>{
        DateTime(2026, 10, 16): false,
        DateTime(2026, 10, 16, 9, 14, 59, 999, 999): false,
        DateTime(2026, 10, 16, 9, 15): true,
        DateTime(2026, 10, 16, 10, 29, 59, 999, 999): true,
        DateTime(2026, 10, 16, 10, 30): false,
        DateTime(2026, 10, 16, 23, 59): false,
      };
      for (final entry in cases.entries) {
        expect(
          settings.isNight(entry.key),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    test(
      'all minutes follow cross-midnight, same-day and equal-bound rules',
      () {
        const overnight = ClockSettings(nightEnabled: true);
        const daytime = ClockSettings(
          nightEnabled: true,
          nightStart: '09:15',
          nightEnd: '10:30',
        );
        const disabled = ClockSettings(
          nightEnabled: true,
          nightStart: '07:00',
          nightEnd: '07:00',
        );
        for (var minute = 0; minute < 24 * 60; minute++) {
          final time = DateTime(2026, 10, 16, minute ~/ 60, minute % 60);
          expect(overnight.isNight(time), minute >= 22 * 60 || minute < 7 * 60);
          expect(
            daytime.isNight(time),
            minute >= 9 * 60 + 15 && minute < 10 * 60 + 30,
          );
          expect(disabled.isNight(time), isFalse);
          expect(disabled.intensityAt(time), 1.0);
        }
      },
    );

    test('midnight endpoints handle one-minute intervals correctly', () {
      const beforeMidnight = ClockSettings(
        nightEnabled: true,
        nightStart: '23:59',
        nightEnd: '00:00',
      );
      const afterMidnight = ClockSettings(
        nightEnabled: true,
        nightStart: '00:00',
        nightEnd: '00:01',
      );
      final last = DateTime(2026, 12, 31, 23, 59, 59, 999);
      final midnight = DateTime(2027);
      expect(beforeMidnight.isNight(last), isTrue);
      expect(beforeMidnight.isNight(midnight), isFalse);
      expect(afterMidnight.isNight(last), isFalse);
      expect(afterMidnight.isNight(midnight), isTrue);
      expect(afterMidnight.isNight(DateTime(2027, 1, 1, 0, 1)), isFalse);
    });

    test('night intensity never brightens a dimmer daytime preference', () {
      const settings = ClockSettings(
        textIntensity: 0.2,
        nightEnabled: true,
        nightIntensity: 0.8,
      );
      expect(settings.intensityAt(DateTime(2026, 10, 16, 12)), 0.2);
      expect(settings.intensityAt(DateTime(2026, 10, 16, 23)), 0.2);
      expect(
        settings
            .copyWith(nightIntensity: 0.15)
            .intensityAt(DateTime(2026, 10, 16, 23)),
        0.15,
      );
      expect(
        settings
            .copyWith(nightIntensity: 0.2)
            .intensityAt(DateTime(2026, 10, 16, 23)),
        0.2,
      );
    });

    test('night evaluation uses the supplied date-time zone unchanged', () {
      const settings = ClockSettings(nightEnabled: true);
      expect(settings.isNight(DateTime.utc(2026, 10, 16, 22)), isTrue);
      expect(settings.isNight(DateTime.utc(2026, 10, 16, 7)), isFalse);
    });
  });
}
