import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';
import 'package:time_nest/dashboard/crypto_chart.dart';
import 'package:time_nest/ui/home_data_modules.dart';

class _Client extends DashboardClient {
  final calls =
      <
        ({
          String module,
          Map<String, dynamic> args,
          Completer<DashboardData> result,
        })
      >[];
  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) {
    final result = Completer<DashboardData>();
    calls.add((module: module, args: args, result: result));
    return result.future;
  }

  @override
  String? readPreferences() => null;
  @override
  bool writePreferences(String raw) => true;
  @override
  void openUrl(String url) {}
}

final _now = DateTime.utc(2026, 10, 22, 10);
DashboardData _weather(num temperature, {bool stale = false}) => DashboardData(
  fetchedAt: _now,
  stale: stale,
  data: {
    'hours': [
      {'time': '2026-10-22T10:00', 'temperature': temperature},
    ],
  },
);
Widget _host(Widget child, {Size size = const Size(320, 180)}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(width: size.width, height: size.height, child: child),
    ),
  ),
);
Widget _weatherWidget(
  _Client client, {
  bool active = true,
  String name = '北京',
  num latitude = 40,
}) => HomeWeatherModule(
  client: client,
  city: {'name': name, 'latitude': latitude, 'longitude': 116},
  active: active,
  now: () => _now,
);

void main() {
  testWidgets(
    'does not poll inactive; resumes and discards old in-flight results',
    (tester) async {
      final client = _Client();
      await tester.pumpWidget(_host(_weatherWidget(client, active: false)));
      await tester.pump(const Duration(minutes: 20));
      expect(client.calls, isEmpty);
      await tester.pumpWidget(_host(_weatherWidget(client)));
      expect(client.calls, hasLength(1));
      await tester.pumpWidget(_host(_weatherWidget(client, active: false)));
      client.calls.first.result.complete(_weather(99));
      await tester.pumpAndSettle();
      expect(find.text('99°C'), findsNothing);
      await tester.pump(const Duration(minutes: 20));
      expect(client.calls, hasLength(1));
      await tester.pumpWidget(_host(_weatherWidget(client)));
      expect(client.calls, hasLength(2));
      client.calls.last.result.complete(_weather(18, stale: true));
      await tester.pumpAndSettle();
      expect(find.text('18°C'), findsOneWidget);
      expect(find.textContaining('旧数据'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'city change never accepts previous city response and tiny cards fit',
    (tester) async {
      final client = _Client();
      await tester.pumpWidget(
        _host(_weatherWidget(client), size: const Size(40, 20)),
      );
      await tester.pumpWidget(
        _host(
          _weatherWidget(client, name: '上海', latitude: 31),
          size: const Size(40, 20),
        ),
      );
      client.calls.first.result.complete(_weather(99));
      client.calls.last.result.complete(_weather(20));
      await tester.pumpAndSettle();
      expect(find.text('20°C'), findsOneWidget);
      expect(find.text('99°C'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'crypto uses real chart parser and retains labelled stale data on failure',
    (tester) async {
      final client = _Client();
      await tester.pumpWidget(
        _host(
          HomeCryptoModule(
            client: client,
            symbol: 'BTCUSDT',
            interval: '1h',
            active: true,
            now: () => _now,
          ),
          size: const Size(100, 50),
        ),
      );
      client.calls.last.result.complete(
        DashboardData(
          fetchedAt: _now,
          data: {
            'symbol': 'BTCUSDT',
            'interval': '1h',
            'candles': [
              {
                'time': 1000,
                'closeTime': 3599999,
                'open': 10,
                'close': 11,
                'high': 12,
                'low': 9,
                'volume': 1,
                'quoteVolume': 10,
              },
            ],
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CryptoChart), findsOneWidget);
      expect(
        find.byKey(const Key('crypto-compact-price-plot')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('crypto-pan-older')), findsNothing);
      expect(find.byKey(const Key('crypto-selection-hint')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 30));
      expect(client.calls, hasLength(2));
      client.calls.last.result.completeError(
        const DashboardException('offline'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CryptoChart), findsOneWidget);
      expect(
        find.byKey(const Key('crypto-compact-price-plot')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('crypto-pan-older')), findsNothing);
      expect(find.byKey(const Key('crypto-selection-hint')), findsNothing);
      expect(find.textContaining('旧数据'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('mismatched crypto response is rejected', (tester) async {
    final client = _Client();
    await tester.pumpWidget(
      _host(
        HomeCryptoModule(
          client: client,
          symbol: 'BTCUSDT',
          interval: '1h',
          active: true,
        ),
      ),
    );
    client.calls.last.result.complete(
      DashboardData(
        fetchedAt: _now,
        data: {'symbol': 'ETHUSDT', 'interval': '1h', 'candles': []},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CryptoChart), findsNothing);
    expect(find.text('暂时无法更新，请稍后重试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
