/// Calendar-only dates use UTC so a daylight-saving transition never removes
/// or duplicates a day. The caller chooses the appropriate local calendar date.
DateTime holidayDate(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

String holidayDateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

class HolidayDay {
  const HolidayDay({
    required this.date,
    required this.name,
    required this.isOffDay,
  });
  final DateTime date;
  final String name;
  final bool isOffDay;
}

class HolidayPlan {
  const HolidayPlan({
    required this.start,
    required this.end,
    required this.leaveDates,
  });
  final DateTime start;
  final DateTime end;
  final List<DateTime> leaveDates;
  int get length => end.difference(start).inDays + 1;
  int get leaveDays => leaveDates.length;
  bool contains(DateTime date) {
    final day = holidayDate(date);
    return !day.isBefore(start) && !day.isAfter(end);
  }
}

class HolidayCountdown {
  const HolidayCountdown({
    required this.start,
    required this.end,
    required this.workdays,
  });
  final DateTime start;
  final DateTime end;
  final int workdays;
  int get length => end.difference(start).inDays + 1;
}

class HolidaySchedule {
  HolidaySchedule({
    required this.year,
    required this.known,
    this.boundaryKnown = true,
    Iterable<HolidayDay> days = const [],
  }) : days = {for (final day in days) holidayDateKey(day.date): day};

  factory HolidaySchedule.fromJson(
    Map<String, dynamic> json, {
    required int year,
  }) {
    final days = <HolidayDay>[];
    for (final value in (json['days'] as List? ?? const [])) {
      if (value is! Map || value['isOffDay'] is! bool) continue;
      final text = value['date']?.toString() ?? '';
      final parsed = DateTime.tryParse(text);
      if (parsed == null ||
          parsed.year != year ||
          holidayDateKey(parsed) != text) {
        continue;
      }
      days.add(
        HolidayDay(
          date: holidayDate(parsed),
          name: value['name']?.toString() ?? '节假日',
          isOffDay: value['isOffDay'] as bool,
        ),
      );
    }
    return HolidaySchedule(
      year: year,
      known: json['known'] == true,
      boundaryKnown: json['boundaryKnown'] == true,
      days: days,
    );
  }

  final int year;
  final bool known;
  final bool boundaryKnown;
  final Map<String, HolidayDay> days;

  /// Null means official adjustments are unavailable; never silently infer a
  /// leave recommendation from weekends in an unknown year.
  bool? isRestDay(DateTime date) {
    if (!known || date.year != year) return null;
    final explicit = days[holidayDateKey(date)];
    if (explicit != null) return explicit.isOffDay;
    if (date.month == 12 && !boundaryKnown) return null;
    return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
  }

  HolidayDay? adjustment(DateTime date) => days[holidayDateKey(date)];

  HolidayCountdown? nextBreak(DateTime now) {
    if (!known) return null;
    var cursor = holidayDate(now);
    if (cursor.year < year) cursor = DateTime.utc(year);
    if (cursor.year != year || (!boundaryKnown && cursor.month == 12)) {
      return null;
    }
    var workdays = 0;
    while (cursor.year == year && isRestDay(cursor) == false) {
      workdays++;
      cursor = cursor.add(const Duration(days: 1));
    }
    if (cursor.year != year ||
        isRestDay(cursor) != true ||
        (!boundaryKnown && cursor.month == 12)) {
      return null;
    }
    final start = cursor;
    while (isRestDay(cursor.add(const Duration(days: 1))) == true) {
      if (!boundaryKnown && cursor.add(const Duration(days: 1)).month == 12) {
        break;
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return HolidayCountdown(start: start, end: cursor, workdays: workdays);
  }

  /// Best result within the selected year and the 120 days starting at [now].
  /// Prefer the longest break, then fewer leave days, then the earliest start.
  HolidayPlan? bestPlan(
    DateTime now, {
    required int budget,
    int horizonDays = 120,
    int maxSpan = 16,
  }) {
    if (!known || horizonDays < 1 || maxSpan < 1) return null;
    final today = holidayDate(now);
    final horizon = today.add(Duration(days: horizonDays - 1));
    var first = today;
    if (first.year < year) first = DateTime.utc(year);
    final knownEnd = boundaryKnown
        ? DateTime.utc(year, 12, 31)
        : DateTime.utc(year, 11, 30);
    final last = knownEnd.isBefore(horizon) ? knownEnd : horizon;
    if (first.year != year || first.isAfter(last)) return null;
    final allowed = budget.clamp(0, 5);
    HolidayPlan? best;
    for (
      var start = first;
      !start.isAfter(last);
      start = start.add(const Duration(days: 1))
    ) {
      final leave = <DateTime>[];
      var hasRest = false;
      for (var span = 0; span < maxSpan; span++) {
        final end = start.add(Duration(days: span));
        if (end.isAfter(last)) break;
        final rest = isRestDay(end);
        if (rest == null) break;
        if (!rest) {
          leave.add(end);
        } else {
          hasRest = true;
        }
        if (leave.length > allowed) break;
        if (!hasRest) continue;
        final candidate = HolidayPlan(
          start: start,
          end: end,
          leaveDates: List.unmodifiable(leave),
        );
        if (best == null ||
            candidate.length > best.length ||
            (candidate.length == best.length &&
                candidate.leaveDays < best.leaveDays)) {
          best = candidate;
        }
      }
    }
    return best;
  }
}
