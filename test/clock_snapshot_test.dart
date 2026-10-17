import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/clock/clock_settings.dart';
import 'package:time_nest/clock/clock_snapshot.dart';

void main() {
  const defaults = ClockSettings();
  const twelveHour = ClockSettings(hourCycle: 'h12');

  group('snapshot formatting', () {
    test(
      'documented example uses one instant and no component punctuation',
      () {
        final now = DateTime(2026, 10, 16, 14, 47, 8, 357);
        final snapshot = ClockSnapshot.fromDateTime(now, defaults);
        expect(snapshot.time, same(now));
        expect(snapshot.dateLabel, '2026年10月16日  星期五');
        expect(snapshot.hoursMinutes, '14:47');
        expect(snapshot.seconds, '08');
        expect(snapshot.milliseconds, '357');
        expect(snapshot.period, isNull);
        expect(snapshot.seconds, isNot(contains(':')));
        expect(snapshot.milliseconds, isNot(contains('.')));
      },
    );

    test('midnight and single-digit components are zero-padded', () {
      final midnight = ClockSnapshot.fromDateTime(
        DateTime(2026, 1, 2),
        defaults,
      );
      expect(midnight.dateLabel, '2026年1月2日  星期五');
      expect(midnight.hoursMinutes, '00:00');
      expect(midnight.seconds, '00');
      expect(midnight.milliseconds, '000');
      final padded = ClockSnapshot.fromDateTime(
        DateTime(2026, 1, 2, 1, 2, 3, 7),
        defaults,
      );
      expect(padded.hoursMinutes, '01:02');
      expect(padded.seconds, '03');
      expect(padded.milliseconds, '007');
    });

    test(
      'milliseconds have exactly three digits at every formatting boundary',
      () {
        const cases = <int, String>{
          0: '000',
          1: '001',
          7: '007',
          9: '009',
          10: '010',
          99: '099',
          100: '100',
          357: '357',
          999: '999',
        };
        for (final entry in cases.entries) {
          final snapshot = ClockSnapshot.fromDateTime(
            DateTime(2026, 10, 16, 23, 59, 59, entry.key),
            defaults,
          );
          expect(snapshot.milliseconds, entry.value);
          expect(snapshot.milliseconds, hasLength(3));
          expect(snapshot.hoursMinutes, '23:59');
          expect(snapshot.seconds, '59');
        }
      },
    );

    test(
      'microseconds do not round milliseconds or carry into another second',
      () {
        final now = DateTime(2026, 12, 31, 23, 59, 59, 999, 999);
        final snapshot = ClockSnapshot.fromDateTime(now, defaults);
        expect(snapshot.time, same(now));
        expect(snapshot.dateLabel, '2026年12月31日  星期四');
        expect(snapshot.hoursMinutes, '23:59');
        expect(snapshot.seconds, '59');
        expect(snapshot.milliseconds, '999');
      },
    );

    test('all weekday labels are correct from Monday through Sunday', () {
      const names = <String>['一', '二', '三', '四', '五', '六', '日'];
      for (var index = 0; index < names.length; index++) {
        final day = 12 + index;
        final snapshot = ClockSnapshot.fromDateTime(
          DateTime(2026, 10, day),
          defaults,
        );
        expect(snapshot.dateLabel, '2026年10月${12 + index}日  星期${names[index]}');
      }
    });

    test('hidden fields are still derived without destroying preferences', () {
      final now = DateTime(2026, 10, 16, 14, 47, 8, 357);
      for (final settings in <ClockSettings>[
        const ClockSettings(showSeconds: false),
        const ClockSettings(showMilliseconds: false),
        const ClockSettings(showSeconds: false, showMilliseconds: false),
      ]) {
        final snapshot = ClockSnapshot.fromDateTime(now, settings);
        expect(snapshot.hoursMinutes, '14:47');
        expect(snapshot.seconds, '08');
        expect(snapshot.milliseconds, '357');
        expect(settings.effectiveMilliseconds, isFalse);
      }
    });

    test('retains supplied UTC/local DateTime without timezone conversion', () {
      final times = <DateTime>[
        DateTime.utc(2026, 10, 16, 23, 59, 58, 123),
        DateTime(2026, 10, 16, 23, 59, 58, 123),
      ];
      for (final time in times) {
        final snapshot = ClockSnapshot.fromDateTime(time, defaults);
        expect(snapshot.time, same(time));
        expect(snapshot.time.isUtc, time.isUtc);
        expect(snapshot.dateLabel, '2026年10月16日  星期五');
        expect(snapshot.hoursMinutes, '23:59');
        expect(snapshot.seconds, '58');
        expect(snapshot.milliseconds, '123');
      }
    });
  });

  group('12-hour and 24-hour cycles', () {
    const cases = <(int, String, String)>[
      (0, '12', 'AM'),
      (1, '01', 'AM'),
      (2, '02', 'AM'),
      (3, '03', 'AM'),
      (4, '04', 'AM'),
      (5, '05', 'AM'),
      (6, '06', 'AM'),
      (7, '07', 'AM'),
      (8, '08', 'AM'),
      (9, '09', 'AM'),
      (10, '10', 'AM'),
      (11, '11', 'AM'),
      (12, '12', 'PM'),
      (13, '01', 'PM'),
      (14, '02', 'PM'),
      (15, '03', 'PM'),
      (16, '04', 'PM'),
      (17, '05', 'PM'),
      (18, '06', 'PM'),
      (19, '07', 'PM'),
      (20, '08', 'PM'),
      (21, '09', 'PM'),
      (22, '10', 'PM'),
      (23, '11', 'PM'),
    ];

    for (final (hour, expectedHour, expectedPeriod) in cases) {
      test('hour $hour displays in both cycles', () {
        final time = DateTime(2026, 10, 16, hour, 9, 8, 7);
        final h12 = ClockSnapshot.fromDateTime(time, twelveHour);
        final h23 = ClockSnapshot.fromDateTime(time, defaults);
        expect(h12.hoursMinutes, '$expectedHour:09');
        expect(h12.period, expectedPeriod);
        expect(h23.hoursMinutes, '${hour.toString().padLeft(2, '0')}:09');
        expect(h23.period, isNull);
        expect(h12.dateLabel, h23.dateLabel);
        expect(h12.seconds, h23.seconds);
        expect(h12.milliseconds, h23.milliseconds);
        expect(h12.time, same(h23.time));
      });
    }

    test('noon changes AM to PM without changing the calendar date', () {
      final before = ClockSnapshot.fromDateTime(
        DateTime(2026, 10, 16, 11, 59, 59, 999),
        twelveHour,
      );
      final noon = ClockSnapshot.fromDateTime(
        DateTime(2026, 10, 16, 12),
        twelveHour,
      );
      expect(before.hoursMinutes, '11:59');
      expect(before.seconds, '59');
      expect(before.milliseconds, '999');
      expect(before.period, 'AM');
      expect(noon.hoursMinutes, '12:00');
      expect(noon.seconds, '00');
      expect(noon.milliseconds, '000');
      expect(noon.period, 'PM');
      expect(noon.dateLabel, before.dateLabel);
    });

    test('midnight changes PM to AM and advances date together', () {
      final before = ClockSnapshot.fromDateTime(
        DateTime(2026, 10, 16, 23, 59, 59, 999),
        twelveHour,
      );
      final midnight = ClockSnapshot.fromDateTime(
        DateTime(2026, 10, 17),
        twelveHour,
      );
      expect(before.hoursMinutes, '11:59');
      expect(before.period, 'PM');
      expect(before.dateLabel, '2026年10月16日  星期五');
      expect(midnight.hoursMinutes, '12:00');
      expect(midnight.period, 'AM');
      expect(midnight.dateLabel, '2026年10月17日  星期六');
      expect(midnight.seconds, '00');
      expect(midnight.milliseconds, '000');
    });
  });

  group('calendar and atomic rollover boundaries', () {
    final cases = <(DateTime, String, String)>[
      (
        DateTime.utc(2026, 10, 31, 23, 59, 59, 999),
        '2026年10月31日  星期六',
        '2026年11月1日  星期日',
      ),
      (
        DateTime.utc(2026, 4, 30, 23, 59, 59, 999),
        '2026年4月30日  星期四',
        '2026年5月1日  星期五',
      ),
      (
        DateTime.utc(2026, 12, 31, 23, 59, 59, 999),
        '2026年12月31日  星期四',
        '2027年1月1日  星期五',
      ),
      (
        DateTime.utc(2024, 2, 28, 23, 59, 59, 999),
        '2024年2月28日  星期三',
        '2024年2月29日  星期四',
      ),
      (
        DateTime.utc(2024, 2, 29, 23, 59, 59, 999),
        '2024年2月29日  星期四',
        '2024年3月1日  星期五',
      ),
      (
        DateTime.utc(2025, 2, 28, 23, 59, 59, 999),
        '2025年2月28日  星期五',
        '2025年3月1日  星期六',
      ),
      (
        DateTime.utc(2000, 2, 28, 23, 59, 59, 999),
        '2000年2月28日  星期一',
        '2000年2月29日  星期二',
      ),
      (
        DateTime.utc(2100, 2, 28, 23, 59, 59, 999),
        '2100年2月28日  星期日',
        '2100年3月1日  星期一',
      ),
    ];

    for (final (time, beforeLabel, afterLabel) in cases) {
      test('$beforeLabel rolls over atomically to $afterLabel', () {
        final nextTime = time.add(const Duration(milliseconds: 1));
        final before = ClockSnapshot.fromDateTime(time, defaults);
        final after = ClockSnapshot.fromDateTime(nextTime, defaults);
        expect(before.time, same(time));
        expect(before.dateLabel, beforeLabel);
        expect(before.hoursMinutes, '23:59');
        expect(before.seconds, '59');
        expect(before.milliseconds, '999');
        expect(after.time, same(nextTime));
        expect(after.dateLabel, afterLabel);
        expect(after.hoursMinutes, '00:00');
        expect(after.seconds, '00');
        expect(after.milliseconds, '000');
      });
    }

    test(
      'second, minute and hour rollovers use only the new supplied instant',
      () {
        final cases = <(DateTime, String, String)>[
          (DateTime.utc(2026, 10, 16, 14, 47, 8, 999), '14:47', '09'),
          (DateTime.utc(2026, 10, 16, 14, 47, 59, 999), '14:48', '00'),
          (DateTime.utc(2026, 10, 16, 14, 59, 59, 999), '15:00', '00'),
        ];
        for (final (time, hoursMinutes, seconds) in cases) {
          final snapshot = ClockSnapshot.fromDateTime(
            time.add(const Duration(milliseconds: 1)),
            defaults,
          );
          expect(snapshot.dateLabel, '2026年10月16日  星期五');
          expect(snapshot.hoursMinutes, hoursMinutes);
          expect(snapshot.seconds, seconds);
          expect(snapshot.milliseconds, '000');
        }
      },
    );

    test(
      'non-monotonic clock changes and repeated reads introduce no state',
      () {
        final later = DateTime.utc(2030, 1, 1, 23, 59, 59, 999);
        final earlier = DateTime.utc(2026, 10, 16, 1, 2, 3, 4);
        final first = ClockSnapshot.fromDateTime(later, defaults);
        final backward = ClockSnapshot.fromDateTime(earlier, defaults);
        final repeated = ClockSnapshot.fromDateTime(later, defaults);
        expect(backward.time, same(earlier));
        expect(backward.dateLabel, '2026年10月16日  星期五');
        expect(backward.hoursMinutes, '01:02');
        expect(backward.seconds, '03');
        expect(backward.milliseconds, '004');
        expect(first.time, same(later));
        expect(repeated.time, same(later));
        expect(repeated.dateLabel, first.dateLabel);
        expect(repeated.hoursMinutes, first.hoursMinutes);
        expect(repeated.seconds, first.seconds);
        expect(repeated.milliseconds, first.milliseconds);
      },
    );
  });
}
