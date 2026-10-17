import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/clock/timer_controller.dart';
import 'package:time_nest/clock/clock_settings.dart';

void main() {
  test(
    'presets preserve unrelated preferences and old v1 settings migrate',
    () {
      final old = ClockSettings.decode(
        '{"version":1,"hourCycle":"h12","keepAwake":true}',
      );
      expect(old.showDate, isTrue);
      final source = old.copyWith(orientation: 'landscape');
      for (final preset in ['office', 'bedside', 'minimal']) {
        final result = source.applyPreset(preset);
        expect(result.preset, preset);
        expect(result.hourCycle, 'h12');
        expect(result.keepAwake, isTrue);
        expect(result.orientation, 'landscape');
        expect(ClockSettings.decode(result.encode()), result);
      }
      expect(source.applyPreset('minimal').showDate, isFalse);
      expect(
        source.applyPreset('bedside').intensityAt(DateTime(2026, 1, 1, 23)),
        .2,
      );
    },
  );

  late DateTime now;
  late String saved;
  late int alerts;
  late TimerController timer;
  setUp(() {
    now = DateTime(2026, 10, 17, 12);
    saved = '';
    alerts = 0;
    timer = TimerController(
      now: () => now,
      save: (raw) {
        saved = raw;
        return true;
      },
      onComplete: () => alerts++,
    );
  });
  tearDown(() => timer.dispose());

  test('countdown pauses, survives reload and resumes remaining duration', () {
    timer.configure(countdownValue: 1);
    timer.start(timer.countdown);
    now = now.add(const Duration(seconds: 17));
    timer.pause(timer.countdown);
    expect(timer.countdown.label, '00:43');
    now = now.add(const Duration(hours: 2));
    final restored = TimerController(
      raw: saved,
      now: () => now,
      save: (_) => true,
    );
    addTearDown(restored.dispose);
    expect(restored.countdown.status, 'paused');
    restored.start(restored.countdown);
    now = now.add(const Duration(seconds: 43));
    restored.sample();
    expect(restored.countdown.status, 'complete');
  });

  test(
    'running reload uses deadline; completed focus is counted exactly once',
    () {
      timer.configure(focusValue: 1);
      timer.selectMode('focus');
      timer.start(timer.focus);
      now = now.add(const Duration(minutes: 2));
      final restored = TimerController(
        raw: saved,
        now: () => now,
        save: (raw) {
          saved = raw;
          return true;
        },
      );
      expect(restored.mode, 'focus');
      expect(restored.focus.status, 'complete');
      expect(restored.todayFocus, 1);
      restored.sample();
      restored.sample();
      expect(restored.todayFocus, 1);
      restored.dispose();
      final again = TimerController(
        raw: saved,
        now: () => now,
        save: (_) => true,
      );
      addTearDown(again.dispose);
      expect(again.todayFocus, 1);
    },
  );

  test(
    'background return completes only current phase, waits for explicit rest',
    () {
      timer.configure(focusValue: 1);
      timer.start(timer.focus);
      timer.setVisible(false);
      now = now.add(const Duration(hours: 3));
      timer.setVisible(true);
      expect(timer.focus.phase, 'focus');
      expect(timer.focus.status, 'complete');
      expect(timer.todayFocus, 1);
      expect(alerts, 1);
      timer.setVisible(true);
      expect(alerts, 1);
      timer.start(timer.focus);
      expect(timer.focus.phase, 'shortBreak');
      expect(timer.focus.label, '05:00');
    },
  );

  test(
    'four completed focus sessions produce long rest, resets do not count',
    () {
      timer.configure(focusValue: 1, shortValue: 1, longValue: 10);
      for (var round = 1; round <= 4; round++) {
        timer.start(timer.focus);
        now = now.add(const Duration(minutes: 1));
        timer.sample();
        expect(timer.todayFocus, round);
        timer.start(timer.focus);
        expect(timer.focus.phase, round == 4 ? 'longBreak' : 'shortBreak');
        now = now.add(Duration(minutes: round == 4 ? 10 : 1));
        timer.sample();
      }
      timer.reset(timer.focus);
      expect(timer.todayFocus, 4);
      expect(timer.focus.phase, 'focus');
    },
  );

  test(
    'yesterday completion does not count today and next day resets daily count',
    () {
      now = DateTime(2026, 10, 17, 23, 58);
      timer.configure(focusValue: 1);
      timer.start(timer.focus);
      now = DateTime(2026, 10, 18, 1);
      timer.sample();
      expect(timer.todayFocus, 0);
      expect(timer.cycleCount, 1);
      timer.reset(timer.focus);
      timer.start(timer.focus);
      now = now.add(const Duration(minutes: 1));
      timer.sample();
      expect(timer.todayFocus, 1);
      now = now.add(const Duration(days: 1));
      timer.sample();
      expect(timer.todayFocus, 0);
    },
  );

  test(
    'mode switching and duration editing preserve active independent sessions',
    () {
      timer.start(timer.countdown);
      timer.start(timer.focus);
      final end = timer.countdown.deadline;
      timer.configure(countdownValue: 15, focusValue: 50);
      timer.selectMode('clock');
      expect(timer.countdown.deadline, end);
      expect(timer.countdownMinutes, 5);
      expect(timer.focusMinutes, 25);
      now = now.add(const Duration(minutes: 5));
      timer.sample();
      expect(timer.countdown.status, 'complete');
      expect(timer.focus.status, 'running');
    },
  );

  test('malformed storage and storage failure preserve usable timer', () {
    for (final raw in [
      'broken',
      '[]',
      '{"version":99}',
      jsonEncode({
        'version': 1,
        'countdownMinutes': -1,
        'countdown': {'status': 'running', 'deadline': 'bad'},
      }),
    ]) {
      final item = TimerController(
        raw: raw,
        now: () => now,
        save: (_) => false,
      );
      item.start(item.countdown);
      expect(item.countdown.running, isTrue);
      expect(item.storageAvailable, isFalse);
      item.dispose();
    }
  });
}
