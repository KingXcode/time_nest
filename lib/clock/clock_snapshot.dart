import 'clock_settings.dart';

/// All display fields derived from one caller-supplied instant.
///
/// Visibility preferences belong to the view: seconds and milliseconds remain
/// available here even when they are currently hidden.
final class ClockSnapshot {
  const ClockSnapshot._({
    required this.time,
    required this.dateLabel,
    required this.hoursMinutes,
    required this.seconds,
    required this.milliseconds,
    required this.period,
  });

  factory ClockSnapshot.fromDateTime(DateTime now, ClockSettings settings) {
    const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    final isTwelveHour = settings.hourCycle == 'h12';
    final hour = isTwelveHour
        ? (now.hour % 12 == 0 ? 12 : now.hour % 12)
        : now.hour;

    return ClockSnapshot._(
      time: now,
      dateLabel:
          '${now.year}年${now.month}月${now.day}日  '
          '星期${weekdays[now.weekday - 1]}',
      hoursMinutes: '${_twoDigits(hour)}:${_twoDigits(now.minute)}',
      seconds: _twoDigits(now.second),
      milliseconds: (now.millisecond ~/ 100).toString(),
      period: isTwelveHour ? (now.hour < 12 ? 'AM' : 'PM') : null,
    );
  }

  /// The exact supplied value; no new clock read or timezone conversion occurs.
  final DateTime time;
  final String dateLabel;
  final String hoursMinutes;
  final String seconds;

  /// One fractional-second digit, truncated so it never rounds into the next second.
  final String milliseconds;
  final String? period;

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
