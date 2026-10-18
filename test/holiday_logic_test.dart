import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/holiday_logic.dart';

HolidayDay day(String date, bool off) =>
    HolidayDay(date: DateTime.parse(date), name: '测试假期', isOffDay: off);

void main() {
  test('missing following-year notice excludes December from planning', () {
    final schedule = HolidaySchedule(
      year: 2026,
      known: true,
      boundaryKnown: false,
      days: [day('2026-12-31', true)],
    );
    expect(schedule.isRestDay(DateTime(2026, 12, 5)), isNull);
    expect(schedule.isRestDay(DateTime(2026, 12, 31)), true);
    expect(schedule.bestPlan(DateTime(2026, 12, 1), budget: 5), isNull);
    expect(schedule.nextBreak(DateTime(2026, 12, 31)), isNull);
    expect(schedule.bestPlan(DateTime(2026, 11, 25), budget: 5)!.end.month, 11);
  });
  test(
    'weekends rest, explicit false overrides Saturday, weekday true rests',
    () {
      final schedule = HolidaySchedule(
        year: 2026,
        known: true,
        days: [day('2026-10-10', false), day('2026-10-09', true)],
      );
      expect(schedule.isRestDay(DateTime(2026, 10, 10)), false);
      expect(schedule.isRestDay(DateTime(2026, 10, 11)), true);
      expect(schedule.isRestDay(DateTime(2026, 10, 9)), true);
      expect(schedule.isRestDay(DateTime(2026, 10, 12)), false);
    },
  );

  test('unknown year has no inferred official rest or leave plans', () {
    final schedule = HolidaySchedule(
      year: 2027,
      known: false,
      days: [day('2027-01-01', true)],
    );
    expect(schedule.isRestDay(DateTime(2027, 1, 2)), isNull);
    expect(schedule.nextBreak(DateTime(2027)), isNull);
    expect(schedule.bestPlan(DateTime(2027), budget: 5), isNull);
  });

  test('zero leave selects earliest longest unmodified rest block', () {
    final schedule = HolidaySchedule(year: 2026, known: true);
    final plan = schedule.bestPlan(DateTime(2026, 10, 19), budget: 0)!;
    expect(holidayDateKey(plan.start), '2026-10-24');
    expect(plan.length, 2);
    expect(plan.leaveDays, 0);
  });

  test('leave costs use real working days, including adjusted weekend', () {
    final schedule = HolidaySchedule(
      year: 2026,
      known: true,
      days: [day('2026-10-10', false), day('2026-10-09', true)],
    );
    final plan = schedule.bestPlan(
      DateTime(2026, 10, 9),
      budget: 1,
      horizonDays: 3,
    )!;
    expect(plan.length, 3);
    expect(plan.leaveDates.map(holidayDateKey), ['2026-10-10']);
    expect(
      schedule
          .bestPlan(DateTime(2026, 10, 9), budget: 0, horizonDays: 3)!
          .length,
      1,
    );
  });

  test(
    '0 through 5 day budgets never overspend and maximum length is bounded',
    () {
      final schedule = HolidaySchedule(year: 2026, known: true);
      for (var budget = 0; budget <= 5; budget++) {
        final plan = schedule.bestPlan(DateTime(2026, 10, 19), budget: budget)!;
        expect(plan.leaveDays, lessThanOrEqualTo(budget));
        expect(plan.length, lessThanOrEqualTo(16));
        expect(
          plan.leaveDates.every((date) => schedule.isRestDay(date) == false),
          true,
        );
      }
      expect(schedule.bestPlan(DateTime(2026, 10, 19), budget: 5)!.length, 9);
    },
  );

  test(
    'year boundary is never crossed and unknown adjacent year is not used',
    () {
      final schedule = HolidaySchedule(
        year: 2026,
        known: true,
        days: [day('2026-12-31', true)],
      );
      final plan = schedule.bestPlan(DateTime(2026, 12, 30), budget: 5)!;
      expect(holidayDateKey(plan.end), '2026-12-31');
      expect(schedule.isRestDay(DateTime(2027, 1, 2)), isNull);
      expect(schedule.nextBreak(DateTime(2026, 12, 31))!.length, 1);
      expect(schedule.bestPlan(DateTime(2027), budget: 5), isNull);
      expect(schedule.nextBreak(DateTime(2027)), isNull);
    },
  );

  test('selected future year still respects horizon measured from today', () {
    final schedule = HolidaySchedule(year: 2027, known: true);
    expect(schedule.bestPlan(DateTime(2026, 1, 1), budget: 5), isNull);
    final plan = schedule.bestPlan(DateTime(2026, 12, 28), budget: 0)!;
    expect(holidayDateKey(plan.start), '2027-01-02');
  });

  test(
    'working-day countdown includes a working today and adjusted Saturday',
    () {
      final schedule = HolidaySchedule(
        year: 2026,
        known: true,
        days: [day('2026-10-10', false)],
      );
      expect(schedule.nextBreak(DateTime(2026, 10, 9))!.workdays, 2);
      expect(
        holidayDateKey(schedule.nextBreak(DateTime(2026, 10, 9))!.start),
        '2026-10-11',
      );
      expect(schedule.nextBreak(DateTime(2026, 10, 11))!.workdays, 0);
    },
  );

  test('ties spend less leave before preferring earlier dates', () {
    final schedule = HolidaySchedule(
      year: 2026,
      known: true,
      days: [day('2026-10-12', true)],
    );
    final plan = schedule.bestPlan(
      DateTime(2026, 10, 8),
      budget: 1,
      horizonDays: 5,
    )!;
    expect(holidayDateKey(plan.start), '2026-10-09');
    expect(plan.length, 4);
    expect(plan.leaveDays, 1);
  });

  test('parser preserves false and ignores malformed and wrong-year days', () {
    final schedule = HolidaySchedule.fromJson({
      'known': true,
      'days': [
        {'date': '2026-10-10', 'name': '调休', 'isOffDay': false},
        {'date': '2026-02-30', 'isOffDay': true},
        {'date': '2027-01-01', 'isOffDay': true},
        {'date': '2026-10-11', 'isOffDay': 'false'},
      ],
    }, year: 2026);
    expect(schedule.days.length, 1);
    expect(schedule.isRestDay(DateTime(2026, 10, 10)), false);
  });

  test(
    'calendar-only normalization remains stable across time and leap dates',
    () {
      expect(
        holidayDate(DateTime(2024, 2, 29, 23)).add(const Duration(days: 1)),
        DateTime.utc(2024, 3, 1),
      );
      expect(holidayDateKey(DateTime(2026, 1, 2, 23)), '2026-01-02');
    },
  );
}
