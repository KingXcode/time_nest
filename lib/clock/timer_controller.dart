import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

int _number(Object? value, int fallback, int min, int max) =>
    value is int && value >= min && value <= max ? value : fallback;
String _choice(Object? value, List<String> options, String fallback) =>
    value is String && options.contains(value) ? value : fallback;
String _day(DateTime time) => '${time.year}-${time.month}-${time.day}';

class TimerSession {
  TimerSession({this.phase = 'countdown'});
  String phase;
  String status = 'idle';
  int durationMs = 0;
  int remainingMs = 0;
  int? deadline;
  bool get running => status == 'running';
  bool get active => running || status == 'paused';
  String get label {
    final seconds = (remainingMs / 1000).ceil();
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  void reset(int minutes) {
    status = 'idle';
    deadline = null;
    durationMs = remainingMs = minutes * 60000;
  }

  Map<String, Object?> toJson() => {
    'phase': phase,
    'status': status,
    'durationMs': durationMs,
    'remainingMs': remainingMs,
    'deadline': deadline,
  };

  void restore(Object? raw, int fallbackMinutes, {required bool focus}) {
    if (raw is! Map) {
      reset(fallbackMinutes);
      return;
    }
    phase = focus
        ? _choice(raw['phase'], ['focus', 'shortBreak', 'longBreak'], 'focus')
        : 'countdown';
    status = _choice(raw['status'], [
      'idle',
      'running',
      'paused',
      'complete',
    ], 'idle');
    durationMs = _number(
      raw['durationMs'],
      fallbackMinutes * 60000,
      60000,
      180 * 60000,
    );
    remainingMs = _number(raw['remainingMs'], durationMs, 0, durationMs);
    final end = raw['deadline'];
    deadline = end is int && end > 0 && end < 8640000000000000 ? end : null;
    if (running && deadline == null) status = 'paused';
    if (status == 'complete') remainingMs = 0;
    if (!running) deadline = null;
  }
}

/// Countdown and focus sessions are independent. Persist deadlines, not ticks:
/// a delayed callback, reload or hidden page never accumulates timer drift.
class TimerController extends ChangeNotifier {
  TimerController({
    required this.save,
    DateTime Function()? now,
    String? raw,
    this.onComplete,
  }) : _now = now ?? DateTime.now {
    _restore(raw);
    sample(notify: false, alert: false);
    _schedule();
  }

  final bool Function(String) save;
  final DateTime Function() _now;
  final VoidCallback? onComplete;
  final countdown = TimerSession();
  final focus = TimerSession(phase: 'focus');
  String mode = 'clock';
  int countdownMinutes = 5;
  int focusMinutes = 25;
  int shortBreakMinutes = 5;
  int longBreakMinutes = 15;
  int cycleCount = 0;
  int todayFocus = 0;
  String statsDate = '';
  bool sound = true;
  bool storageAvailable = true;
  bool _visible = true;
  bool _disposed = false;
  Timer? _timer;

  int minutesFor(TimerSession session) => switch (session.phase) {
    'focus' => focusMinutes,
    'shortBreak' => shortBreakMinutes,
    'longBreak' => longBreakMinutes,
    _ => countdownMinutes,
  };

  void _restore(String? raw) {
    Map value = {};
    try {
      final decoded = jsonDecode(raw ?? '{}');
      if (decoded is Map && decoded['version'] == 1) value = decoded;
    } on FormatException {
      /* Use defaults for damaged storage. */
    }
    mode = _choice(value['mode'], ['clock', 'countdown', 'focus'], 'clock');
    countdownMinutes = _number(value['countdownMinutes'], 5, 1, 180);
    focusMinutes = _number(value['focusMinutes'], 25, 1, 180);
    shortBreakMinutes = _number(value['shortBreakMinutes'], 5, 1, 60);
    longBreakMinutes = _number(value['longBreakMinutes'], 15, 1, 60);
    cycleCount = _number(value['cycleCount'], 0, 0, 1000000);
    statsDate = value['statsDate'] is String
        ? value['statsDate'] as String
        : '';
    todayFocus = _number(value['todayFocus'], 0, 0, 1000000);
    sound = value['sound'] is bool ? value['sound'] as bool : true;
    countdown.restore(value['countdown'], countdownMinutes, focus: false);
    focus.restore(value['focus'], focusMinutes, focus: true);
  }

  String encode() => jsonEncode({
    'version': 1,
    'mode': mode,
    'countdownMinutes': countdownMinutes,
    'focusMinutes': focusMinutes,
    'shortBreakMinutes': shortBreakMinutes,
    'longBreakMinutes': longBreakMinutes,
    'cycleCount': cycleCount,
    'statsDate': statsDate,
    'todayFocus': todayFocus,
    'sound': sound,
    'countdown': countdown.toJson(),
    'focus': focus.toJson(),
  });

  void _persist() {
    storageAvailable = save(encode());
  }

  void _changed() {
    _persist();
    notifyListeners();
    _schedule();
  }

  void selectMode(String value) {
    if (!['clock', 'countdown', 'focus'].contains(value)) return;
    mode = value;
    sample(notify: false);
    _changed();
  }

  void configure({
    int? countdownValue,
    int? focusValue,
    int? shortValue,
    int? longValue,
    bool? soundValue,
  }) {
    // Duration controls are disabled while their session is active.
    if (!countdown.active && countdownValue != null) {
      countdownMinutes = countdownValue.clamp(1, 180);
      countdown.reset(countdownMinutes);
    }
    if (!focus.active) {
      focusMinutes = (focusValue ?? focusMinutes).clamp(1, 180);
      shortBreakMinutes = (shortValue ?? shortBreakMinutes).clamp(1, 60);
      longBreakMinutes = (longValue ?? longBreakMinutes).clamp(1, 60);
      if (focus.status == 'idle') focus.reset(minutesFor(focus));
    }
    sound = soundValue ?? sound;
    _changed();
  }

  void start(TimerSession session) {
    sample(notify: false);
    if (session.running) return;
    if (session.status == 'complete') {
      if (session == focus) {
        session.phase = session.phase == 'focus'
            ? (cycleCount % 4 == 0 ? 'longBreak' : 'shortBreak')
            : 'focus';
      }
      session.reset(minutesFor(session));
    }
    if (session.status == 'idle') session.reset(minutesFor(session));
    session.deadline = _now().millisecondsSinceEpoch + session.remainingMs;
    session.status = 'running';
    _changed();
  }

  void pause(TimerSession session) {
    sample(notify: false);
    if (!session.running) return;
    session.status = 'paused';
    session.deadline = null;
    _changed();
  }

  void reset(TimerSession session) {
    if (session == focus) session.phase = 'focus';
    session.reset(minutesFor(session));
    _changed();
  }

  void sample({bool notify = true, bool alert = true}) {
    if (_disposed) return;
    final now = _now();
    var changed = false;
    if (statsDate != _day(now)) {
      statsDate = _day(now);
      todayFocus = 0;
      changed = true;
    }
    var finished = false;
    for (final session in [countdown, focus]) {
      if (!session.running) continue;
      session.remainingMs = (session.deadline! - now.millisecondsSinceEpoch)
          .clamp(0, session.durationMs);
      if (session.remainingMs == 0) {
        if (session == focus && session.phase == 'focus') {
          cycleCount++;
          if (_day(DateTime.fromMillisecondsSinceEpoch(session.deadline!)) ==
              statsDate) {
            todayFocus++;
          }
        }
        session.status = 'complete';
        session.deadline = null;
        finished = changed = true;
      }
    }
    if (changed) _persist();
    if (notify) notifyListeners();
    if (finished && alert && sound && _visible) onComplete?.call();
  }

  void setVisible(bool value) {
    _visible = value;
    if (value) sample();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed || !_visible) return;
    final delay = countdown.running || focus.running
        ? 1000 - _now().millisecondsSinceEpoch % 1000
        : 60000;
    _timer = Timer(Duration(milliseconds: delay), () {
      sample();
      _schedule();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
