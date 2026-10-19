import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/dashboard_client_stub.dart';
import 'package:time_nest/dashboard/local_market_panel.dart';
import 'package:time_nest/dashboard/local_market_source.dart';
import 'package:time_nest/dashboard/market_chart.dart';
import 'package:time_nest/dashboard/market_history.dart';
import 'package:time_nest/dashboard/native_market_history.dart';

// Synthetic fixtures. These are never imported by the application.
Map<String, dynamic> payload({String index = 'shanghai', bool stale = false}) =>
    {
      'schemaVersion': 1,
      'indexId': index,
      'code': {
        'shanghai': 'sh.000001',
        'csi300': 'sh.000300',
        'shenzhen': 'sz.399001',
      }[index],
      'frequency': 'd',
      'timezone': 'Asia/Shanghai',
      'startDate': '2026-09-19',
      'endDate': '2026-10-18',
      'fetchedAt': '2026-10-18T23:40:00+00:00',
      'cached': true,
      'freshness': stale ? 'stale' : 'unverified',
      'warning': null,
      'rows': [
        {'date': '2026-10-15', 'close': 100.0},
        {'date': '2026-10-16', 'close': 101.0},
      ],
    };

LocalMarketHistorySource source(Map<String, dynamic> value) =>
    LocalMarketHistorySource(
      request: (_, {refresh = false}) async => value,
      now: () => DateTime.utc(2026, 10, 19),
    );

void main() {
  test(
    'adapter preserves dates and fetched time without claiming freshness',
    () async {
      await expectLater(
        source(payload()).load('shanghai'),
        completion(isA<MarketHistory>()),
      );
      final history = await source(payload()).load('shanghai');
      expect(history.asOf!.label, '2026-10-16');
      expect(history.fetchedAt, DateTime.utc(2026, 10, 18, 23, 40));
      expect(history.freshness, HistoryFreshness.unverified);
      expect(history.source.name, contains('BaoStock'));
      expect(history.source.url.host, 'www.baostock.com');
      final stale = await source(payload(stale: true)).load('shanghai');
      expect(stale.freshness, HistoryFreshness.stale);
    },
  );

  test(
    'adapter forwards refresh and rejects unsupported indices before transport',
    () async {
      final requests = <String>[];
      final adapter = LocalMarketHistorySource(
        request: (index, {refresh = false}) async {
          requests.add('$index:$refresh');
          return payload(index: index);
        },
        now: () => DateTime.utc(2026, 10, 19),
      );
      await expectLater(
        adapter.load('csi300', refresh: true),
        completion(isA<MarketHistory>()),
      );
      await expectLater(adapter.load('star50'), throwsFormatException);
      expect(requests, ['csi300:true']);
    },
  );

  test('identity, timezone, schema and date-window mismatches never reach the plot', () async {
    for (final mutation in <Map<String, dynamic>>[
      {'indexId': 'shenzhen'},
      {'code': 'sz.399001'},
      {'schemaVersion': 2},
      {'frequency': 'm'},
      {'timezone': 'UTC'},
      {'cached': 'true'},
      {'freshness': 'verifiedThroughDate'},
      {'fetchedAt': '2026-10-19T07:40:00'},
      {'fetchedAt': '2026-10-20T07:40:00Z'},
      {'endDate': '2026-10-19'},
      {
        'rows': [
          {'date': '2026-09-18', 'close': 101},
        ],
      },
    ]) {
      await expectLater(
        source({...payload(), ...mutation}).load('shanghai'),
        throwsFormatException,
        reason: mutation.toString(),
      );
    }
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'local panel at 320px/$scale uses native graph and date interaction',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var index = 'shanghai';
        final calls = <String>[];
        final adapter = LocalMarketHistorySource(
          request: (id, {refresh = false}) async {
            calls.add(id);
            return payload(index: id);
          },
          now: () => DateTime.utc(2026, 10, 19),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: LocalMarketPanel(
                        client: MemoryDashboardClient(),
                        indexId: index,
                        source: adapter,
                        onChanged: (value, period) =>
                            setState(() => index = value),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CloseHistoryChart), findsOneWidget);
        expect(find.byType(MarketChart), findsNothing);
        expect(find.textContaining('仅供个人研究，不构成投资建议'), findsOneWidget);
        expect(find.text('2026-10-16 · 收盘 101.00 点'), findsOneWidget);
        tester.widget<Slider>(find.byType(Slider)).onChanged!(0);
        await tester.pump();
        expect(find.text('2026-10-15 · 收盘 100.00 点'), findsOneWidget);
        expect(calls, ['shanghai']);
        final chip = find.widgetWithText(ChoiceChip, '沪深300');
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(find.text('沪深300 · 每日收盘点位'), findsOneWidget);
        expect(calls, ['shanghai', 'csi300']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'unsupported saved index asks for a choice instead of substituting data',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalMarketPanel(
              client: MemoryDashboardClient(),
              indexId: 'star50',
              source: source(payload()),
              onChanged: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NativeMarketHistory), findsNothing);
      expect(find.textContaining('请选择上方指数'), findsOneWidget);
    },
  );
}
