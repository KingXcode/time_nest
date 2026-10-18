import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/market_history.dart';
import 'package:time_nest/dashboard/native_market_history.dart';

// Synthetic, deterministic test data. Never imported by application code.
MarketHistory fixture({
  String indexId = 'shanghai',
  List<Object?>? rows,
  HistoryFreshness freshness = HistoryFreshness.unverified,
}) => MarketHistory.fromRows(
  indexId: indexId,
  rows:
      rows ??
      [
        {'date': '2026-10-12', 'close': 100},
        {'date': '2026-10-13', 'close': 105},
        {'date': '2026-10-16', 'close': 102},
      ],
  source: MarketHistoryAttribution(
    name: '测试来源（非真实行情）',
    url: Uri.parse('https://example.com/test-fixture'),
    timingNote: '测试收盘序列，不用于市场判断。',
  ),
  fetchedAt: DateTime.utc(2026, 10, 18, 1, 30),
  freshness: freshness,
);

class PendingSource implements MarketHistorySource {
  final requests = <({String indexId, bool refresh})>[];
  final results = <Completer<MarketHistory>>[];

  @override
  Future<MarketHistory> load(String indexId, {bool refresh = false}) {
    requests.add((indexId: indexId, refresh: refresh));
    final result = Completer<MarketHistory>();
    results.add(result);
    return result.future;
  }
}

Widget app(
  PendingSource source, {
  String indexId = 'shanghai',
  double scale = 1,
  ValueChanged<Uri>? openSource,
}) => MaterialApp(
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: NativeMarketHistory(
            source: source,
            indexId: indexId,
            openSource: openSource ?? (_) {},
            requestTimeout: const Duration(seconds: 2),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test(
    'strict exchange dates are date-only and reject normalized invalid dates',
    () {
      expect(MarketSessionDate.parse('2024-02-29').label, '2024-02-29');
      for (final value in [
        '2026-02-29',
        '2026-02-30',
        '2026-13-01',
        '2026-10-00',
        '2026-1-01',
        '2026-10-16T00:00:00Z',
        '0000-01-01',
      ]) {
        expect(() => MarketSessionDate.parse(value), throwsFormatException);
      }
      expect(fixture().asOf!.label, '2026-10-16');
      expect(fixture().fetchedAt, DateTime.utc(2026, 10, 18, 1, 30));
      expect(fixture().freshness, HistoryFreshness.unverified);
    },
  );

  test(
    'reject malformed, nonpositive, nonfinite, unordered and future data',
    () {
      for (final value in [0, -1, double.nan, double.infinity, '100', null]) {
        expect(
          () => fixture(
            rows: [
              {'date': '2026-10-16', 'close': value},
            ],
          ),
          throwsFormatException,
        );
      }
      for (final rows in <List<Object?>>[
        [null],
        [
          {'date': null, 'close': 1},
        ],
        [
          {'date': '2026-10-19', 'close': 1},
        ],
        [
          {'date': '2026-10-16', 'close': 1},
          {'date': '2026-10-16', 'close': 2},
        ],
        [
          {'date': '2026-10-16', 'close': 1},
          {'date': '2026-10-15', 'close': 2},
        ],
        List.filled(5001, {'date': '2026-10-16', 'close': 1}),
      ]) {
        expect(() => fixture(rows: rows), throwsFormatException);
      }
      expect(
        () => fixture(indexId: 'https://example.com'),
        throwsFormatException,
      );
      expect(() => fixture().closes.clear(), throwsUnsupportedError);
      for (final url in [
        'javascript:alert(1)',
        'http://example.com',
        'https://u:p@example.com',
      ]) {
        expect(
          () => MarketHistoryAttribution(
            name: 'Source',
            url: Uri.parse(url),
            timingNote: 'Daily',
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'Shanghai session validation does not shift the date to device timezone',
    () {
      final history = MarketHistory(
        indexId: 'shanghai',
        closes: [
          MarketClose(date: MarketSessionDate.parse('2026-10-19'), close: 1),
        ],
        source: fixture().source,
        fetchedAt: DateTime.utc(2026, 10, 18, 16, 1),
      );
      expect(history.asOf!.label, '2026-10-19');
    },
  );

  test('plot geometry is finite, respects bounds, flat and single records', () {
    for (final values in [
      <double>[],
      [100.0],
      [100.0, 100.0],
      [1e-300, 1e308],
      [100.0, 105.0, 102.0],
    ]) {
      final painter = CloseHistoryPainter(values: values, selectedIndex: 0);
      final points = painter.positions(const Size(254, 220));
      expect(points.length, values.length);
      for (final point in points) {
        expect(point.dx.isFinite && point.dy.isFinite, isTrue);
        expect(point.dx, inInclusiveRange(8, 246));
        expect(point.dy, inInclusiveRange(8, 212));
      }
      if (values.isNotEmpty && values.every((v) => v == values.first)) {
        expect(points.every((p) => p.dy == 110), isTrue);
      }
      expect(painter.positions(Size.zero), isEmpty);
    }
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'native plot fits 320px at $scale scale with source and accessible selection',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final source = PendingSource();
        final opened = <Uri>[];
        await tester.pumpWidget(
          app(source, scale: scale, openSource: opened.add),
        );
        expect(find.text('正在获取收盘历史…'), findsOneWidget);
        expect(find.byType(CloseHistoryChart), findsNothing);
        source.results.single.complete(fixture());
        await tester.pumpAndSettle();
        expect(find.text('数据截至：2026-10-16（上海交易日）'), findsOneWidget);
        expect(find.textContaining('2026-10-18 09:30 UTC+8'), findsOneWidget);
        expect(find.text('时效未核实，请以来源说明为准。'), findsOneWidget);
        expect(find.text('2026-10-16 · 收盘 102.00 点'), findsOneWidget);
        final slider = tester.widget<Slider>(find.byType(Slider));
        expect(slider.semanticFormatterCallback!(0), contains('2026-10-12'));
        slider.onChanged!(0);
        await tester.pump();
        expect(find.text('2026-10-12 · 收盘 100.00 点'), findsOneWidget);
        final sourceButton = find.widgetWithText(TextButton, '来源：测试来源（非真实行情）');
        await tester.ensureVisible(sourceButton);
        await tester.tap(sourceButton);
        expect(opened.single.toString(), 'https://example.com/test-fixture');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'plot touch and keyboard slider selection expose the selected close',
    (tester) async {
      final source = PendingSource();
      await tester.pumpWidget(app(source));
      source.results[0].complete(fixture());
      await tester.pumpAndSettle();
      final plot = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is CloseHistoryPainter,
      );
      await tester.tapAt(tester.getTopLeft(plot) + const Offset(8, 110));
      await tester.pump();
      expect(find.text('2026-10-12 · 收盘 100.00 点'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('2026-10-13 · 收盘 105.00 点'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(find.text('2026-10-12 · 收盘 100.00 点'), findsOneWidget);
    },
  );

  testWidgets(
    'refresh failure retains old date and marks prior result; retry recovers',
    (tester) async {
      final source = PendingSource();
      await tester.pumpWidget(app(source));
      source.results[0].complete(fixture(freshness: HistoryFreshness.stale));
      await tester.pumpAndSettle();
      expect(find.text('来源标记为旧数据，可能已过时。'), findsOneWidget);
      await tester.ensureVisible(find.text('重新获取'));
      await tester.tap(find.text('重新获取'));
      await tester.pump();
      expect(source.requests.last.refresh, isTrue);
      expect(find.text('保留上次获取结果，可能已过时。'), findsOneWidget);
      source.results[1].completeError(Exception('private transport details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('private transport'), findsNothing);
      expect(find.text('暂时无法获取收盘历史，请稍后重试。'), findsOneWidget);
      expect(find.text('数据截至：2026-10-16（上海交易日）'), findsOneWidget);
      await tester.ensureVisible(find.text('重新获取'));
      await tester.tap(find.text('重新获取'));
      source.results[2].complete(
        fixture(freshness: HistoryFreshness.verifiedThroughDate),
      );
      await tester.pumpAndSettle();
      expect(find.text('来源已确认截至所示交易日。'), findsOneWidget);
      expect(find.text('保留上次获取结果，可能已过时。'), findsNothing);
    },
  );

  testWidgets(
    'index changes, source changes, timeout and disposal ignore old responses',
    (tester) async {
      final source = PendingSource();
      await tester.pumpWidget(app(source));
      await tester.pumpWidget(app(source, indexId: 'shenzhen'));
      source.results[0].complete(fixture());
      await tester.pump();
      expect(find.byType(CloseHistoryChart), findsNothing);
      source.results[1].complete(fixture(indexId: 'shenzhen'));
      await tester.pumpAndSettle();
      expect(find.text('深证成指 · 每日收盘点位'), findsOneWidget);
      final replacement = PendingSource();
      await tester.pumpWidget(app(replacement, indexId: 'shenzhen'));
      expect(find.byType(CloseHistoryChart), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('获取超时，请稍后重试。'), findsOneWidget);
      replacement.results[0].complete(fixture(indexId: 'shenzhen'));
      await tester.pump();
      expect(find.byType(CloseHistoryChart), findsNothing);
      await tester.tap(find.text('重新获取'));
      await tester.pumpWidget(const SizedBox());
      replacement.results[1].complete(fixture(indexId: 'shenzhen'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty history has no chart; a single point does not claim a trend',
    (tester) async {
      final source = PendingSource();
      await tester.pumpWidget(app(source));
      source.results[0].complete(fixture(rows: []));
      await tester.pumpAndSettle();
      expect(find.text('来源没有返回可显示的历史数据。'), findsOneWidget);
      expect(find.byType(CloseHistoryChart), findsNothing);
      await tester.tap(find.text('重新获取'));
      source.results[1].complete(
        fixture(
          rows: [
            {'date': '2026-10-16', 'close': 100},
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('仅有一个收盘记录，暂不能形成走势。'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
    },
  );

  testWidgets(
    'mismatched series is never displayed and unknown IDs do not call the source',
    (tester) async {
      final source = PendingSource();
      await tester.pumpWidget(app(source));
      source.results[0].complete(fixture(indexId: 'shenzhen'));
      await tester.pumpAndSettle();
      expect(find.text('数据格式未通过校验，暂不绘图。'), findsOneWidget);
      expect(find.byType(CloseHistoryChart), findsNothing);
      await tester.pumpWidget(app(source, indexId: 'invalid'));
      await tester.pumpAndSettle();
      expect(source.requests.length, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
