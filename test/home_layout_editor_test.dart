import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/clock/clock_controller.dart';
import 'package:time_nest/clock/clock_settings.dart';
import 'package:time_nest/clock/home_layout.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/dashboard_preferences.dart';
import 'package:time_nest/ui/home_layout_editor.dart';

class _Client extends DashboardClient {
  int writes = 0;
  @override
  String? readPreferences() => null;
  @override
  bool writePreferences(String raw) {
    writes++;
    return true;
  }

  @override
  void openUrl(String url) {}
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async => DashboardData(data: {}, fetchedAt: DateTime(2026));
}

class _Harness extends StatefulWidget {
  const _Harness({super.key, this.desktop = false, this.landscape = true});
  final bool desktop, landscape;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness>
    with SingleTickerProviderStateMixin {
  static const settings = ClockSettings(showMilliseconds: false);
  late final ClockController clock = ClockController(
    vsync: this,
    settings: settings,
    now: () => DateTime(2026, 10, 22),
  );
  final client = _Client();
  final preferences = DashboardPreferences();
  HomeLayout layout = HomeLayout();
  HomeLayoutEditResult? lastResult;
  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Builder(
        builder: (context) => TextButton(
          child: const Text('Open editor'),
          onPressed: () async {
            final result = await Navigator.of(context)
                .push<HomeLayoutEditResult>(
                  MaterialPageRoute(
                    builder: (_) => HomeLayoutEditor(
                      layout: layout,
                      clock: clock,
                      settings: settings,
                      client: client,
                      preferences: preferences,
                      desktop: widget.desktop,
                      landscape: widget.landscape,
                    ),
                  ),
                );
            lastResult = result;
            if (result != null) layout = result.layout;
          },
        ),
      ),
    ),
  );
}

Future<_HarnessState> _open(
  WidgetTester tester, {
  bool desktop = false,
  bool landscape = true,
  int quarterTurns = 0,
  double textScale = 1,
  Size size = const Size(1000, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: RotatedBox(quarterTurns: quarterTurns, child: child),
      ),
      home: _Harness(key: key, desktop: desktop, landscape: landscape),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
  return key.currentState!;
}

Rect _module(WidgetTester tester, String id) =>
    tester.getRect(find.byKey(ValueKey('edit-$id')));
Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('save-layout')));
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  testWidgets(
    'drag changes only selected module and saves a normalized draft',
    (tester) async {
      final host = await _open(tester);
      final before = _module(tester, 'time');
      final date = _module(tester, 'date');
      final gesture = await tester.startGesture(before.center);
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 35));
      await tester.pump();
      await gesture.up();
      expect(_module(tester, 'time').top, greaterThan(before.top));
      expect(_module(tester, 'date'), date);
      expect(
        host.layout.enabled,
        isFalse,
        reason: 'An open draft must not mutate persisted input',
      );
      await _save(tester);
      expect(host.lastResult, isNotNull);
      expect(host.layout.landscape['time']!.y, greaterThan(.17));
      expect(host.layout.portrait['time']!.y, .20);
      expect(
        host.client.writes,
        0,
        reason: 'Only the caller persists Save results',
      );
      await _close(tester);
    },
  );

  testWidgets(
    'wheel resizes selected module, not the module under the pointer',
    (tester) async {
      await _open(tester);
      final time = _module(tester, 'time');
      final date = _module(tester, 'date');
      await tester.tap(find.byKey(const Key('select-date')));
      await tester.pump();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: time.center,
          scrollDelta: const Offset(0, 60),
        ),
      );
      await tester.pump();
      expect(_module(tester, 'date').width, lessThan(date.width));
      expect(_module(tester, 'time'), time);
      await _close(tester);
    },
  );

  testWidgets('two-pointer pinch changes size without changing other modules', (
    tester,
  ) async {
    await _open(tester);
    final before = _module(tester, 'time');
    final date = _module(tester, 'date');
    final a = await tester.startGesture(
      before.center - const Offset(45, 0),
      pointer: 1,
    );
    final b = await tester.startGesture(
      before.center + const Offset(45, 0),
      pointer: 2,
    );
    await tester.pump();
    await a.moveTo(before.center - const Offset(30, 0));
    await b.moveTo(before.center + const Offset(30, 0));
    await tester.pump();
    await a.moveTo(before.center - const Offset(20, 0));
    await b.moveTo(before.center + const Offset(20, 0));
    await tester.pump();
    expect(_module(tester, 'time').width, lessThan(before.width));
    expect(_module(tester, 'date'), date);
    await a.up();
    await b.up();
    await _close(tester);
  });

  testWidgets('orientation drafts are independent and save survives reopen', (
    tester,
  ) async {
    final host = await _open(tester);
    await tester.tap(find.byTooltip('缩小'));
    await tester.pump();
    final wideWidth = _module(tester, 'time').width;
    await tester.tap(find.byKey(const Key('edit-portrait')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('select-date')));
    await tester.tap(find.byTooltip('缩小'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('edit-landscape')));
    await tester.pump();
    expect(_module(tester, 'time').width, closeTo(wideWidth, .01));
    await _save(tester);
    expect(host.layout.landscape['time']!.width, closeTo(.72, .0001));
    expect(host.layout.portrait['time']!.width, .94);
    expect(host.layout.portrait['date']!.width, closeTo(.792, .0001));
    expect(host.layout.landscape['date']!.width, .8);
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    expect(_module(tester, 'time').width, closeTo(wideWidth, .01));
    await _close(tester);
  });

  testWidgets('cancel drops draft and reopen uses unchanged input', (
    tester,
  ) async {
    final host = await _open(tester);
    final original = _module(tester, 'time');
    await tester.tap(find.byTooltip('缩小'));
    await tester.pump();
    await tester.tap(find.byTooltip('取消'));
    await tester.pumpAndSettle();
    expect(host.lastResult, isNull);
    expect(host.layout, HomeLayout());
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    expect(_module(tester, 'time'), original);
    expect(host.client.writes, 0);
    await _close(tester);
  });

  testWidgets(
    'desktop forces landscape and viewport resize keeps normalized geometry',
    (tester) async {
      final host = await _open(tester, desktop: true, landscape: false);
      expect(find.byKey(const Key('edit-portrait')), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('edit-landscape')))
            .selected,
        isTrue,
      );
      for (final size in [
        const Size(400, 700),
        const Size(1200, 500),
        const Size(650, 400),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pump();
        final preview = tester.getRect(find.byKey(const Key('layout-preview')));
        final time = _module(tester, 'time');
        expect(time.width / preview.width, closeTo(.8, .0001));
        expect((time.left - preview.left) / preview.width, closeTo(.1, .0001));
        expect(tester.takeException(), isNull);
      }
      await _save(tester);
      expect(host.layout.landscape['time']!.width, .8);
      expect(host.layout.portrait['time']!.width, .94);
      await _close(tester);
    },
  );

  testWidgets(
    'rotated preview drag follows canvas axes rather than screen axes',
    (tester) async {
      final host = await _open(tester, quarterTurns: 1);
      final center = tester.getCenter(find.byKey(const Key('edit-time')));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(0, 24));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.up();
      await _save(tester);
      final time = host.layout.landscape['time']!;
      expect(
        time.x,
        greaterThan(.1),
        reason: 'Screen down is canvas right after a clockwise quarter turn',
      );
      expect(time.y, closeTo(.17, .0001));
      await _close(tester);
    },
  );

  testWidgets(
    '667 by 375 landscape preview and controls fit without overflow',
    (tester) async {
      await _open(tester, size: const Size(667, 375));
      expect(tester.takeException(), isNull);
      final preview = tester.getSize(find.byKey(const Key('layout-preview')));
      expect(preview.width, greaterThan(200));
      expect(preview.height, greaterThan(100));
      await tester.tap(find.byKey(const Key('select-date')));
      await tester.pump();
      await tester.ensureVisible(find.text('坐标与大小'));
      await tester.tap(find.text('坐标与大小'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await _close(tester);
    },
  );

  testWidgets(
    'precision rejects invalid input, cancels cleanly and clamps confirmed values',
    (tester) async {
      final host = await _open(tester);
      final original = _module(tester, 'time');
      await tester.tap(find.text('坐标与大小'));
      await tester.pumpAndSettle();
      for (final invalid in ['bad', 'NaN', 'Infinity', '']) {
        await tester.enterText(find.byType(TextField).first, invalid);
        await tester.tap(find.text('确定'));
        await tester.pump();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('请输入有效数字'), findsOneWidget);
      }
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(_module(tester, 'time'), original);
      await tester.tap(find.text('坐标与大小'));
      await tester.pumpAndSettle();
      final values = ['80', '-10', '60', '20'];
      for (var i = 0; i < values.length; i++) {
        await tester.enterText(find.byType(TextField).at(i), values[i]);
      }
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await _save(tester);
      final time = host.layout.landscape['time']!;
      expect(time.x, closeTo(.4, .0001));
      expect(time.y, 0);
      expect(time.width, .6);
      expect(time.height, .2);
      expect(tester.takeException(), isNull);
      await _close(tester);
    },
  );

  testWidgets('reset restores only selected orientation', (tester) async {
    final host = await _open(tester);
    await tester.tap(find.byTooltip('缩小'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('edit-portrait')));
    await tester.pump();
    await tester.tap(find.byTooltip('缩小'));
    await tester.pump();
    await tester.tap(find.text('重置'));
    await tester.pump();
    await _save(tester);
    expect(host.layout.landscape['time']!.width, closeTo(.72, .0001));
    expect(
      host.layout.portrait.map((k, v) => MapEntry(k, v.toJson())),
      HomeLayout.defaults(false).map((k, v) => MapEntry(k, v.toJson())),
    );
    await _close(tester);
  });

  testWidgets('cancelled touch then cancelled editor leaves reopen untouched', (
    tester,
  ) async {
    final host = await _open(tester);
    final original = _module(tester, 'time');
    final gesture = await tester.startGesture(original.center);
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    await tester.tap(find.byTooltip('取消'));
    await tester.pumpAndSettle();
    expect(host.lastResult, isNull);
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    expect(_module(tester, 'time'), original);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  for (final size in [const Size(320, 568), const Size(667, 375)]) {
    testWidgets('editor fits $size at 200 percent text scale', (tester) async {
      await _open(tester, size: size, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('layout-preview')), findsOneWidget);
      expect(find.byKey(const Key('save-layout')), findsOneWidget);
      await tester.tap(find.byKey(const Key('edit-portrait')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _close(tester);
    });
  }
}
