import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'clock_settings.dart';
import 'clock_snapshot.dart';

/// One wall-clock snapshot per update. Never accumulate elapsed frame time.
class ClockController {
  ClockController({
    required TickerProvider vsync,
    required this._settings,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _ticker = vsync.createTicker((_) => _sample());
    _sample();
    _schedule();
  }

  final DateTime Function() _now;
  late final Ticker _ticker;
  Timer? _timer;
  ClockSettings _settings;
  bool _visible = true;
  bool _disposed = false;

  final date = ValueNotifier('');
  final hoursMinutes = ValueNotifier('');
  final seconds = ValueNotifier('');
  final milliseconds = ValueNotifier('');
  final period = ValueNotifier<String?>(null);
  final intensity = ValueNotifier(1.0);
  final nightActive = ValueNotifier(false);
  // Excludes milliseconds, is not a live region, and changes at most each second.
  final accessibleTime = ValueNotifier('');

  void updateSettings(ClockSettings settings) {
    _settings = settings;
    _restart();
  }

  void setVisible(bool visible, {bool resample = false}) {
    if (_disposed) return;
    if (_visible == visible && !resample) return;
    _visible = visible;
    _restart();
  }

  void _restart() {
    _ticker.stop();
    _timer?.cancel();
    _timer = null;
    if (_disposed || !_visible) return;
    _sample();
    _schedule();
  }

  void _sample() {
    if (_disposed || !_visible) return;
    final now = _now();
    final snapshot = ClockSnapshot.fromDateTime(now, _settings);
    date.value = snapshot.dateLabel;
    hoursMinutes.value = snapshot.hoursMinutes;
    seconds.value = snapshot.seconds;
    milliseconds.value = snapshot.milliseconds;
    period.value = snapshot.period;
    intensity.value = _settings.intensityAt(now);
    nightActive.value = _settings.isNight(now);
    accessibleTime.value =
        '${snapshot.dateLabel} ${snapshot.hoursMinutes}'
        '${_settings.showSeconds ? ':${snapshot.seconds}' : ''}'
        '${snapshot.period == null ? '' : ' ${snapshot.period}'}';
  }

  void _schedule() {
    if (_disposed || !_visible) return;
    if (_settings.effectiveMilliseconds) {
      if (!_ticker.isActive) _ticker.start();
      return;
    }
    // No frame loop without milliseconds. Align to the next second/minute,
    // but always re-read DateTime.now() when the timer fires.
    final quantum = _settings.showSeconds ? 1000 : 60000;
    final delay = quantum - _now().millisecondsSinceEpoch % quantum;
    _timer = Timer(Duration(milliseconds: delay), () {
      _timer = null;
      _sample();
      _schedule();
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _ticker.dispose();
    date.dispose();
    hoursMinutes.dispose();
    seconds.dispose();
    milliseconds.dispose();
    period.dispose();
    intensity.dispose();
    nightActive.dispose();
    accessibleTime.dispose();
  }
}
