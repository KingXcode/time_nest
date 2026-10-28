import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/clock/clock_controller.dart';
import 'package:time_nest/clock/clock_settings.dart';
import 'package:time_nest/clock/home_layout.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';
import 'package:time_nest/ui/home_layout_canvas.dart';
import 'package:time_nest/ui/home_data_modules.dart';
import 'package:time_nest/ui/home_layout_editor.dart';

class _Client extends DashboardClient {
  @override
  String? readPreferences() => null;
  @override
  bool writePreferences(String raw) => true;
  @override
  void openUrl(String url) {}
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async => DashboardData(
    fetchedAt: DateTime.now(),
    data: module == 'weather'
        ? {
            'hours': [
              {'time': '${DateTime.now().year}-12-31T10:00', 'temperature': 22},
            ],
          }
        : {
            'symbol': args['symbol'],
            'interval': args['interval'],
            'candles': [
              for (var i = 0; i < 5; i++)
                {
                  'time': 1792663200000 + i * 3600000,
                  'closeTime': 1792663200000 + (i + 1) * 3600000 - 1,
                  'open': 100 + i,
                  'high': 105 + i,
                  'low': 98 + i,
                  'close': 102 + i,
                  'volume': 20,
                  'quoteVolume': 2000,
                },
            ],
          },
  );
}

class _PendingClient extends _Client {
  final result = Completer<DashboardData>();
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) => result.future;
}

class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.module,
    required this.item,
    required this.editor,
    required this.wide,
    required this.desktop,
  });
  final String module;
  final HomeModuleLayout item;
  final bool editor, wide, desktop;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  static const settings = ClockSettings(showMilliseconds: false);
  late final clock = ClockController(vsync: this, settings: settings)
    ..setVisible(false);
  final client = _Client();
  final preferences = DashboardPreferences(
    city: {'name': '北京', 'latitude': 40, 'longitude': 116},
  );
  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modules = {
      for (final entry in HomeLayout.defaults(widget.wide).entries)
        entry.key: entry.key == widget.module
            ? widget.item
            : entry.value.copyWith(visible: false),
    };
    final layout = HomeLayout(
      enabled: true,
      portrait: modules,
      landscape: modules,
    );
    return widget.editor
        ? HomeLayoutEditor(
            layout: layout,
            clock: clock,
            settings: settings,
            client: client,
            preferences: preferences,
            desktop: widget.desktop,
            landscape: widget.wide,
          )
        : Scaffold(
            body: SizedBox.expand(
              key: const Key('canvas-bounds'),
              child: HomeLayoutCanvas(
                layout: layout,
                landscape: widget.wide,
                clock: clock,
                settings: settings,
                client: client,
                preferences: preferences,
                active: true,
              ),
            ),
          );
  }
}

// Transform both corners: getRect alone would miss the old inner FittedBox's
// paint scale and centered horizontal gutters.
Rect _paintRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

Finder _card(String module) => find.byKey(
  ValueKey('home-card-${module == 'crypto' ? 'cryptoCandles' : module}'),
);
void _expectRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, .01));
  expect(actual.right, closeTo(expected.right, .01));
  expect(actual.top, closeTo(expected.top, .01));
  expect(actual.bottom, closeTo(expected.bottom, .01));
}

Future<void> _mount(
  WidgetTester tester, {
  required String module,
  required HomeModuleLayout item,
  required bool editor,
  required bool wide,
  required bool desktop,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: _Host(
        key: UniqueKey(),
        module: module,
        item: item,
        editor: editor,
        wide: wide,
        desktop: desktop,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final module in ['weather', 'crypto']) {
    testWidgets(
      '$module card reaches bottom while protecting only overlapping content',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(393, 852);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
        addTearDown(tester.view.reset);
        for (final y in [.8, .78, .5]) {
          await _mount(
            tester,
            module: module,
            item: HomeModuleLayout(x: 0, y: y, width: 1, height: .2),
            editor: false,
            wide: false,
            desktop: false,
          );
          final card = _card(module);
          final decorated = tester.widget<DecoratedBox>(card);
          final protection = (decorated.child! as Padding).padding
              .resolve(TextDirection.ltr)
              .bottom;
          final rect = _paintRect(tester, card);
          expect(rect.bottom, closeTo(852 * (y + .2), .01));
          final expected = (34 - 852 * (1 - y - .2)).clamp(0.0, 34.0);
          expect(protection, closeTo(expected, .01));
          final content = find
              .descendant(of: card, matching: find.byType(ClipRect))
              .first;
          expect(
            _paintRect(tester, content).bottom,
            closeTo(rect.bottom - expected, .01),
          );
          expect(_paintRect(tester, content).bottom, lessThanOrEqualTo(818.01));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'editor controls reach bottom with scrollable last-row protection',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
      addTearDown(tester.view.reset);
      await _mount(
        tester,
        module: 'weather',
        item: HomeModuleLayout(x: 0, y: .5, width: 1, height: .2),
        editor: true,
        wide: false,
        desktop: false,
      );
      final previewCard = tester.widget<DecoratedBox>(_card('weather'));
      expect(
        (previewCard.child! as Padding).padding
            .resolve(TextDirection.ltr)
            .bottom,
        0,
        reason: 'Miniature preview is not at the physical device edge',
      );
      final scroll = find.byType(SingleChildScrollView);
      expect(tester.getRect(scroll).bottom, 852);
      expect(
        tester
            .widget<SingleChildScrollView>(scroll)
            .padding!
            .resolve(TextDirection.ltr)
            .bottom,
        46,
      );
      await tester.drag(scroll, const Offset(0, -1000));
      await tester.pumpAndSettle();
      final lastRow = find.textContaining('网格吸附 · 统一边距');
      expect(tester.getRect(lastRow).bottom, lessThanOrEqualTo(818));
      final arrange = find.byKey(const Key('arrange-layout'));
      expect(arrange.hitTestable(), findsOneWidget);
      expect(tester.getRect(arrange).bottom, lessThanOrEqualTo(818));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  const profiles = [
    (
      name: 'mobile portrait',
      size: Size(390, 844),
      wide: false,
      desktop: false,
    ),
    (
      name: 'mobile landscape',
      size: Size(667, 375),
      wide: true,
      desktop: false,
    ),
    (name: 'desktop', size: Size(1200, 700), wide: true, desktop: true),
  ];
  const shapes = [Size(.9, .12), Size(.4, .3), Size(.2, .8)];
  for (final module in ['weather', 'crypto']) {
    for (final profile in profiles) {
      testWidgets(
        '$module homepage painted edges match bounds for ${profile.name}',
        (tester) async {
          await tester.binding.setSurfaceSize(profile.size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          for (final shape in shapes) {
            for (final x in [0.0, 1 - shape.width]) {
              final item = HomeModuleLayout(
                x: x,
                y: .05,
                width: shape.width,
                height: shape.height,
              );
              await _mount(
                tester,
                module: module,
                item: item,
                editor: false,
                wide: profile.wide,
                desktop: profile.desktop,
              );
              final canvas = _paintRect(
                tester,
                find.byKey(const Key('canvas-bounds')),
              );
              final expected = Rect.fromLTWH(
                canvas.left + canvas.width * x,
                canvas.top + canvas.height * item.y,
                canvas.width * item.width,
                canvas.height * item.height,
              );
              _expectRect(_paintRect(tester, _card(module)), expected);
              expect(tester.takeException(), isNull);
            }
          }
          await tester.pumpWidget(const SizedBox());
        },
      );

      testWidgets(
        '$module editor painted bounds match selection and drag to gutters for ${profile.name}',
        (tester) async {
          await tester.binding.setSurfaceSize(profile.size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          for (final shape in shapes) {
            final item = HomeModuleLayout(
              x: .05,
              y: .05,
              width: shape.width,
              height: shape.height,
            );
            await _mount(
              tester,
              module: module,
              item: item,
              editor: true,
              wide: profile.wide,
              desktop: profile.desktop,
            );
            await tester.ensureVisible(find.byKey(ValueKey('select-$module')));
            await tester.tap(find.byKey(ValueKey('select-$module')));
            await tester.pumpAndSettle();
            final selection = find.byKey(ValueKey('edit-$module'));
            final outline = tester.widget<DecoratedBox>(
              find
                  .descendant(
                    of: selection,
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            );
            expect(
              outline.position,
              DecorationPosition.foreground,
              reason:
                  'Selection outline must remain visible above the filled card',
            );
            _expectRect(
              _paintRect(tester, _card(module)),
              _paintRect(tester, selection),
            );
            final preview = _paintRect(
              tester,
              find.byKey(const Key('layout-preview')),
            );
            for (final right in [false, true]) {
              final bounds = _paintRect(tester, selection);
              final gesture = await tester.startGesture(
                Offset(
                  right ? bounds.right - 1 : bounds.left + 1,
                  bounds.center.dy,
                ),
              );
              final direction = right ? 1.0 : -1.0;
              await gesture.moveBy(Offset(direction * 24, 0));
              await tester.pump();
              await gesture.moveBy(Offset(direction * preview.width * 2, 0));
              await tester.pump();
              await gesture.up();
              await tester.pump();
              final actual = _paintRect(tester, _card(module));
              _expectRect(actual, _paintRect(tester, selection));
              expect(
                right ? actual.right : actual.left,
                closeTo(
                  right
                      ? preview.right - preview.width * .02
                      : preview.left + preview.width * .02,
                  .01,
                ),
              );
            }
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'weather card keeps full painted bounds in setup loading error and data states',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<void> mount(_Client client, {bool setup = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  key: const Key('state-card-bounds'),
                  width: 700,
                  height: 90,
                  child: HomeWeatherModule(
                    key: UniqueKey(),
                    client: client,
                    city: setup
                        ? null
                        : {'name': '北京', 'latitude': 40, 'longitude': 116},
                    active: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      void check() {
        _expectRect(
          _paintRect(tester, _card('weather')),
          _paintRect(tester, find.byKey(const Key('state-card-bounds'))),
        );
        expect(tester.takeException(), isNull);
      }

      await mount(_Client(), setup: true);
      expect(find.text('在布局设置中选择城市'), findsOneWidget);
      check();
      final pending = _PendingClient();
      await mount(pending);
      check();
      pending.result.completeError(const DashboardException('测试错误'));
      await tester.pump();
      check();
      await mount(_Client());
      await tester.pump();
      expect(find.text('22°C'), findsOneWidget);
      check();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
