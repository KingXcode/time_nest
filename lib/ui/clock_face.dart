import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../clock/clock_controller.dart';
import '../clock/clock_settings.dart';

const clockBackground = Color(0xFF08090B);
const clockForeground = Color(0xFFE8E9EB);

class ClockFace extends StatelessWidget {
  const ClockFace({super.key, required this.clock, required this.settings});

  final ClockController clock;
  final ClockSettings settings;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: clock.accessibleTime,
    builder: (context, description, child) => Semantics(
      label: description,
      liveRegion: false,
      excludeSemantics: true,
      child: child!,
    ),
    child: RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: clock.intensity,
        builder: (context, intensity, _) {
          final color = Color.lerp(
            clockBackground,
            clockForeground,
            intensity,
          )!;
          final dateColor = Color.lerp(
            clockBackground,
            const Color(0xFF989DA5),
            intensity,
          )!;
          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 180;
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: compact ? 22 : 30,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: ValueListenableBuilder<String>(
                          valueListenable: clock.date,
                          builder: (context, date, _) => Text(
                            date,
                            key: const Key('clock-date'),
                            style: TextStyle(
                              color: dateColor,
                              fontSize: 18,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 10 : 26),
                    SizedBox(
                      width: constraints.maxWidth,
                      height: math.max(
                        1,
                        math.min(
                          240,
                          constraints.maxHeight - (compact ? 32 : 56),
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            _Digits(
                              clock.hoursMinutes,
                              5,
                              200,
                              color,
                              fieldKey: 'clock-hm',
                            ),
                            if (settings.showSeconds)
                              _Digits(
                                clock.seconds,
                                3,
                                130,
                                color,
                                prefix: ':',
                                fieldKey: 'clock-seconds',
                              ),
                            if (settings.effectiveMilliseconds)
                              _Digits(
                                clock.milliseconds,
                                4,
                                80,
                                Color.lerp(clockBackground, color, .72)!,
                                prefix: '.',
                                fieldKey: 'clock-milliseconds',
                              ),
                            if (settings.hourCycle == 'h12') ...[
                              const SizedBox(width: 20),
                              SizedBox(
                                width: 64,
                                child: ValueListenableBuilder<String?>(
                                  valueListenable: clock.period,
                                  builder: (context, period, _) => Text(
                                    period ?? '',
                                    style: TextStyle(
                                      fontFamily: 'ClockDigits',
                                      fontSize: 42,
                                      height: 1,
                                      color: dateColor,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

class _Digits extends StatelessWidget {
  const _Digits(
    this.value,
    this.characters,
    this.size,
    this.color, {
    this.prefix = '',
    required this.fieldKey,
  });

  final ValueNotifier<String> value;
  final int characters;
  final double size;
  final Color color;
  final String prefix;
  final String fieldKey;

  @override
  Widget build(BuildContext context) => SizedBox(
    // Roboto Mono has a 0.6 em advance. The constraint stays fixed across ticks.
    width: characters * size * .6,
    child: RepaintBoundary(
      child: ValueListenableBuilder<String>(
        valueListenable: value,
        builder: (context, value, _) => Text(
          '$prefix$value',
          key: Key(fieldKey),
          maxLines: 1,
          softWrap: false,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: 'ClockDigits',
            fontSize: size,
            fontWeight: FontWeight.w400,
            height: 1,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ),
  );
}
