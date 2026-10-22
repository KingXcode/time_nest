import 'package:flutter/material.dart';

import '../clock/clock_controller.dart';
import '../clock/clock_settings.dart';
import '../clock/home_layout.dart';
import '../dashboard/dashboard_client.dart';
import '../dashboard/dashboard_preferences.dart';
import 'clock_face.dart';
import 'home_data_modules.dart';

bool usesDesktopHomeLayout(BuildContext context) => !const [
  TargetPlatform.android,
  TargetPlatform.iOS,
].contains(Theme.of(context).platform);

class HomeLayoutCanvas extends StatelessWidget {
  const HomeLayoutCanvas({
    super.key,
    required this.layout,
    required this.landscape,
    required this.clock,
    required this.settings,
    required this.client,
    required this.preferences,
    required this.active,
  });
  final HomeLayout layout;
  final bool landscape, active;
  final ClockController clock;
  final ClockSettings settings;
  final DashboardClient client;
  final DashboardPreferences preferences;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        for (final entry in layout.forOrientation(landscape).entries)
          if (entry.value.visible && (entry.key != 'date' || settings.showDate))
            Positioned(
              key: ValueKey('home-${entry.key}'),
              left: box.maxWidth * entry.value.x,
              top: box.maxHeight * entry.value.y,
              width: box.maxWidth * entry.value.width,
              height: box.maxHeight * entry.value.height,
              child: HomeModuleContent(
                id: entry.key,
                clock: clock,
                settings: settings,
                client: client,
                preferences: preferences,
                active: active,
              ),
            ),
      ],
    ),
  );
}

class HomeModuleContent extends StatelessWidget {
  const HomeModuleContent({
    super.key,
    required this.id,
    required this.clock,
    required this.settings,
    required this.client,
    required this.preferences,
    required this.active,
  });
  final String id;
  final ClockController clock;
  final ClockSettings settings;
  final DashboardClient client;
  final DashboardPreferences preferences;
  final bool active;
  @override
  Widget build(BuildContext context) => switch (id) {
    'time' => ClockFace(
      clock: clock,
      settings: settings.copyWith(showDate: false),
      maxTimeHeight: double.infinity,
    ),
    'date' => ValueListenableBuilder<double>(
      valueListenable: clock.intensity,
      builder: (context, intensity, _) => FittedBox(
        fit: BoxFit.contain,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: ValueListenableBuilder<String>(
            valueListenable: clock.date,
            builder: (_, date, _) => Text(
              date,
              style: TextStyle(
                fontSize: 24,
                color: Color.lerp(
                  clockBackground,
                  const Color(0xFF989DA5),
                  intensity,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    'weather' => HomeWeatherModule(
      client: client,
      city: preferences.city,
      active: active,
    ),
    _ => HomeCryptoModule(
      client: client,
      symbol: preferences.cryptoSymbol,
      interval: preferences.cryptoInterval,
      active: active,
    ),
  };
}
