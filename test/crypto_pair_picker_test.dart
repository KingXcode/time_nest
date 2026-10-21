import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/crypto_market.dart';
import 'package:time_nest/dashboard/crypto_pair_picker.dart';
import 'package:time_nest/dashboard/dashboard_client.dart';

const _current = CryptoPair(
  symbol: 'BTCUSDT',
  baseAsset: 'BTC',
  quoteAsset: 'USDT',
);

class _CatalogClient implements DashboardClient {
  bool fail = false, stale = false;
  String? warning;
  Completer<DashboardData>? pending;
  final refreshes = <bool>[];
  List<Map<String, String>> pairs = [
    {'symbol': 'BTCUSDT', 'baseAsset': 'BTC', 'quoteAsset': 'USDT'},
    {'symbol': 'ETHUSDT', 'baseAsset': 'ETH', 'quoteAsset': 'USDT'},
    {'symbol': 'SOLUSDT', 'baseAsset': 'SOL', 'quoteAsset': 'USDT'},
    {'symbol': 'BTCUSDC', 'baseAsset': 'BTC', 'quoteAsset': 'USDC'},
    {'symbol': 'ETHBTC', 'baseAsset': 'ETH', 'quoteAsset': 'BTC'},
    {'symbol': 'SOLBTC', 'baseAsset': 'SOL', 'quoteAsset': 'BTC'},
  ];

  DashboardData response() => DashboardData(
    data: {'pairs': pairs},
    fetchedAt: DateTime.utc(2026, 10, 21),
    stale: stale,
    warning: warning,
    cached: stale,
  );

  @override
  Future<DashboardData> load(
    String module,
    Map<String, dynamic> args, {
    bool refresh = false,
  }) async {
    expect(module, 'cryptoPairs');
    expect(args, isEmpty);
    refreshes.add(refresh);
    if (pending != null) return pending!.future;
    if (fail) throw const DashboardException('连接超时，请重试。');
    return response();
  }

  @override
  String? readPreferences() => null;
  @override
  bool writePreferences(String raw) => true;
  @override
  void openUrl(String url) {}
}

class _Host extends StatefulWidget {
  const _Host({required this.client, required this.chooseQuote});
  final DashboardClient client;
  final bool chooseQuote;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  CryptoPair current = _current;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      children: [
        Text(current.symbol, key: const Key('host-selection')),
        FilledButton(
          key: const Key('open-picker'),
          onPressed: () async {
            final pair = await showCryptoPairPicker(
              context,
              client: widget.client,
              current: current,
              chooseQuote: widget.chooseQuote,
            );
            if (mounted && pair != null) setState(() => current = pair);
          },
          child: const Text('选择'),
        ),
      ],
    ),
  );
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _open(
  WidgetTester tester,
  _CatalogClient client, {
  bool quote = false,
  double textScale = 1,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Dashboard header')),
        body: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: _Host(client: client, chooseQuote: quote),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-picker')));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

String _selected(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('host-selection'))).data!;

void main() {
  testWidgets(
    'base picker only lists current quote and searches pair or name',
    (tester) async {
      _size(tester, const Size(1200, 900));
      final client = _CatalogClient();
      await _open(tester, client);
      expect(client.refreshes, [false]);
      expect(find.text('计价币 USDT'), findsOneWidget);
      expect(find.byKey(const Key('crypto-select-BTCUSDT')), findsOneWidget);
      expect(find.byKey(const Key('crypto-select-ETHUSDT')), findsOneWidget);
      expect(find.byKey(const Key('crypto-select-BTCUSDC')), findsNothing);
      expect(find.byKey(const Key('crypto-select-ETHBTC')), findsNothing);
      final selectedSemantics = tester.widgetList<Semantics>(
        find.ancestor(
          of: find.byKey(const Key('crypto-select-BTCUSDT')),
          matching: find.byType(Semantics),
        ),
      );
      expect(
        selectedSemantics.any((s) => s.properties.selected == true),
        isTrue,
      );
      await tester.enterText(
        find.byKey(const Key('crypto-pair-search')),
        '以太坊',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('crypto-select-ETHUSDT')), findsOneWidget);
      expect(find.byKey(const Key('crypto-select-BTCUSDT')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('crypto-pair-search')),
        'eth / usdt',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('crypto-select-ETHUSDT')));
      await tester.pumpAndSettle();
      expect(_selected(tester), 'ETHUSDT');
      expect(find.byKey(const Key('crypto-pair-picker')), findsNothing);
    },
  );

  testWidgets(
    'quote picker counts catalog pairs and preserves available base',
    (tester) async {
      _size(tester, const Size(1200, 900));
      await _open(tester, _CatalogClient(), quote: true);
      expect(find.text('3 种计价币'), findsOneWidget);
      expect(find.text('3 个可用交易对'), findsOneWidget);
      await tester.tap(find.byKey(const Key('crypto-quote-USDC')));
      await tester.pumpAndSettle();
      expect(_selected(tester), 'BTCUSDC');
    },
  );

  testWidgets('missing base drills down without committing; back and cancel', (
    tester,
  ) async {
    _size(tester, const Size(1200, 900));
    await _open(tester, _CatalogClient(), quote: true);
    await tester.tap(find.byKey(const Key('crypto-quote-BTC')));
    await tester.pumpAndSettle();
    expect(_selected(tester), 'BTCUSDT');
    expect(find.text('计价币 BTC'), findsOneWidget);
    expect(find.byKey(const Key('crypto-select-ETHBTC')), findsOneWidget);
    expect(find.byKey(const Key('crypto-select-ETHUSDT')), findsNothing);
    await tester.tap(find.byKey(const Key('crypto-pair-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crypto-quote-USDT')), findsOneWidget);
    await tester.tap(find.byKey(const Key('crypto-quote-BTC')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crypto-pair-close')));
    await tester.pumpAndSettle();
    expect(_selected(tester), 'BTCUSDT');
    await tester.tap(find.byKey(const Key('open-picker')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crypto-quote-USDT')), findsOneWidget);
    await tester.tap(find.byKey(const Key('crypto-quote-BTC')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crypto-select-SOLBTC')));
    await tester.pumpAndSettle();
    expect(_selected(tester), 'SOLBTC');
  });

  testWidgets('escape and system back cancel the complete selection', (
    tester,
  ) async {
    _size(tester, const Size(1200, 900));
    final client = _CatalogClient();
    await _open(tester, client, quote: true);
    await tester.tap(find.byKey(const Key('crypto-quote-BTC')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_selected(tester), 'BTCUSDT');
    expect(find.byKey(const Key('crypto-pair-picker')), findsNothing);
    await tester.tap(find.byKey(const Key('open-picker')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_selected(tester), 'BTCUSDT');
    expect(find.byKey(const Key('crypto-pair-picker')), findsNothing);
    expect(client.refreshes, [false, false]);
  });

  testWidgets('unavailable metadata is not replaced with invented pairs', (
    tester,
  ) async {
    _size(tester, const Size(1200, 900));
    final client = _CatalogClient()..fail = true;
    await _open(tester, client);
    expect(find.text('交易对列表暂不可用'), findsOneWidget);
    expect(find.byKey(const Key('crypto-select-BTCUSDT')), findsNothing);
    client.fail = false;
    await tester.tap(find.byKey(const Key('crypto-pair-retry')));
    await tester.pumpAndSettle();
    expect(client.refreshes, [false, true]);
    expect(find.byKey(const Key('crypto-select-BTCUSDT')), findsOneWidget);
  });

  testWidgets('cached and refresh failure states remain visible and truthful', (
    tester,
  ) async {
    _size(tester, const Size(1200, 900));
    final client = _CatalogClient()..stale = true;
    await _open(tester, client);
    expect(find.textContaining('正在使用缓存'), findsOneWidget);
    client.fail = true;
    await tester.tap(find.byKey(const Key('crypto-pair-refresh')));
    await tester.pumpAndSettle();
    expect(client.refreshes, [false, true]);
    expect(find.textContaining('更新失败，仍显示此前'), findsOneWidget);
    expect(find.byKey(const Key('crypto-select-BTCUSDT')), findsOneWidget);
    client.fail = false;
    client.stale = false;
    await tester.tap(find.byKey(const Key('crypto-pair-refresh')));
    await tester.pumpAndSettle();
    expect(find.textContaining('正在使用缓存'), findsNothing);
    expect(find.textContaining('更新失败'), findsNothing);
  });

  testWidgets('empty and malformed catalogs fail visibly', (tester) async {
    _size(tester, const Size(1200, 900));
    final client = _CatalogClient()..pairs = [];
    await _open(tester, client);
    expect(find.text('交易对列表暂不可用'), findsOneWidget);
    client.pairs = [
      {'symbol': 'BAD', 'baseAsset': 'BTC', 'quoteAsset': 'USDT'},
    ];
    await tester.tap(find.byKey(const Key('crypto-pair-retry')));
    await tester.pumpAndSettle();
    expect(find.text('交易对列表暂不可用'), findsOneWidget);
    expect(find.byKey(const Key('crypto-select-BAD')), findsNothing);
  });

  testWidgets('mobile fills root viewport, respecting safe area and keyboard', (
    tester,
  ) async {
    _size(tester, const Size(320, 844));
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    await _open(tester, _CatalogClient(), textScale: 2);
    final rect = tester.getRect(find.byKey(const Key('crypto-pair-picker')));
    expect(rect, const Rect.fromLTWH(0, 0, 320, 844));
    expect(
      tester.getTopLeft(find.byKey(const Key('crypto-pair-close'))).dy,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('crypto-pair-search')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byKey(const Key('crypto-pair-search')), 'ETH');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('crypto-select-ETHUSDT')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crypto-select-ETHUSDT')));
    await tester.pumpAndSettle();
    expect(_selected(tester), 'ETHUSDT');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'short mobile keyboard viewport and large text remain scrollable',
    (tester) async {
      _size(tester, const Size(568, 320));
      tester.view.padding = const FakeViewPadding(top: 24);
      await _open(tester, _CatalogClient(), textScale: 3);
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('crypto-pair-close')));
      await tester.pumpAndSettle();
      expect(_selected(tester), 'BTCUSDT');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop is spacious and remains bounded on a short viewport', (
    tester,
  ) async {
    _size(tester, const Size(1440, 1000));
    await _open(tester, _CatalogClient());
    expect(
      tester.getSize(find.byKey(const Key('crypto-pair-picker'))),
      const Size(900, 760),
    );
    tester.view.physicalSize = const Size(680, 620);
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const Key('crypto-pair-picker')));
    expect(rect.left, greaterThanOrEqualTo(24));
    expect(rect.top, greaterThanOrEqualTo(24));
    expect(rect.right, lessThanOrEqualTo(656));
    expect(rect.bottom, lessThanOrEqualTo(596));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone landscape fills the page and still respects side safe areas',
    (tester) async {
      _size(tester, const Size(736, 414));
      tester.view.padding = const FakeViewPadding(
        left: 44,
        right: 44,
        bottom: 21,
      );
      await _open(tester, _CatalogClient());
      expect(
        tester.getRect(find.byKey(const Key('crypto-pair-picker'))),
        const Rect.fromLTWH(0, 0, 736, 414),
      );
      expect(
        tester.getTopRight(find.byKey(const Key('crypto-pair-close'))).dx,
        lessThanOrEqualTo(692),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fresh catalog warnings remain visible and Unicode names are searchable',
    (tester) async {
      _size(tester, const Size(1200, 900));
      final client = _CatalogClient()..warning = '部分交易对暂不可用，请稍后刷新。';
      client.pairs.add({
        'symbol': '币安人生USDT',
        'baseAsset': '币安人生',
        'quoteAsset': 'USDT',
      });
      await _open(tester, client);
      expect(find.textContaining('部分交易对暂不可用'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('crypto-pair-search')),
        '币安人生',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('crypto-select-币安人生USDT')));
      await tester.pumpAndSettle();
      expect(_selected(tester), '币安人生USDT');
    },
  );

  testWidgets('thousands of catalog entries stay virtualized and searchable', (
    tester,
  ) async {
    _size(tester, const Size(1200, 900));
    final client = _CatalogClient()
      ..pairs = [
        for (var i = 0; i < 3000; i++)
          {
            'symbol': 'ASSET${i.toString().padLeft(4, '0')}USDT',
            'baseAsset': 'ASSET${i.toString().padLeft(4, '0')}',
            'quoteAsset': 'USDT',
          },
      ];
    await _open(tester, client);
    expect(find.text('3000 个交易对'), findsOneWidget);
    expect(find.byKey(const Key('crypto-select-ASSET2999USDT')), findsNothing);
    expect(find.byType(InkWell).evaluate().length, lessThan(40));
    await tester.enterText(
      find.byKey(const Key('crypto-pair-search')),
      'asset2999',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('crypto-select-ASSET2999USDT')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('crypto-select-ASSET2999USDT')));
    await tester.pumpAndSettle();
    expect(_selected(tester), 'ASSET2999USDT');
  });

  testWidgets('closing while loading is safe and later opening starts clean', (
    tester,
  ) async {
    _size(tester, const Size(390, 844));
    final pending = Completer<DashboardData>();
    final client = _CatalogClient()..pending = pending;
    await _open(tester, client, settle: false);
    await tester.tap(find.byKey(const Key('crypto-pair-close')));
    await tester.pumpAndSettle();
    pending.complete(client.response());
    await tester.pumpAndSettle();
    expect(_selected(tester), 'BTCUSDT');
    expect(tester.takeException(), isNull);
    client.pending = null;
    await tester.tap(find.byKey(const Key('open-picker')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crypto-select-BTCUSDT')), findsOneWidget);
    expect(client.refreshes, [false, false]);
  });
}
