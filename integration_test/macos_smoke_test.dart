import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:time_nest/dashboard/crypto_feed_native.dart';
import 'package:time_nest/dashboard/dashboard_client_native.dart';
import 'package:time_nest/main.dart';
import 'package:time_nest/platform/browser_client_native.dart';
import 'package:time_nest/platform/native_runtime.dart';
import 'package:time_nest/platform/native_store.dart';
import 'package:time_nest/toolbox/network_tools_client_native.dart';

// Live acceptance: run explicitly on a network-connected Mac, not in Web CI.
// fvm flutter test integration_test/macos_smoke_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Mac host, persistence, REST, live book/trades, DNS and Flutter UI',
    (tester) async {
      await tester.runAsync(initializeNativeRuntime);
      await tester.pumpWidget(const ShikeApp());
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final runtime = NativeRuntime.current!;
        final browser = MacBrowserClient(runtime);
        expect(browser.state.nativeApp, isTrue);
        expect(browser.state.fullscreenSupported, isTrue);
        expect(browser.state.wakeSupported, isTrue);
        expect(browser.state.storageAvailable, isTrue);
        const key = 'shike.macos.smoke.v1';
        try {
          expect(runtime.write(key, 'persistent-value'), isTrue);
          expect(
            NativeStore(runtime.store.directory).read(key),
            'persistent-value',
          );
        } finally {
          runtime.write(key, null);
        }
        final client = MacDashboardClient(runtime);
        final pairs = await client.load('cryptoPairs', {});
        expect((pairs.data['pairs'] as List).length, greaterThan(100));
        final rules = await client.load('cryptoBookRules', {
          'symbol': 'BTCUSDT',
        });
        expect((rules.data['rules'] as List).first['symbol'], 'BTCUSDT');
        final quotes = await client.load('cryptoQuotes', {'symbol': 'BTCUSDT'});
        expect((quotes.data['quotes'] as List).first['price'], greaterThan(0));
        final candles = await client.load('cryptoCandles', {
          'symbol': 'BTCUSDT',
          'interval': '1h',
        });
        expect(candles.data['candles'], hasLength(500));
        expect((candles.data['candles'] as List).first['time'], isA<int>());
        final feed = MacCryptoFeed(runtime);
        final received = <String>{};
        final live = Completer<void>(), reset = Completer<void>();
        final errors = <Object>[];
        var resetting = false;
        final subscription = feed
            .subscribe('BTCUSDT', '1h', orderBook: true, trades: true)
            .listen((event) {
              final type = event['type'] as String;
              if (['quote', 'candle', 'depth', 'trades'].contains(type)) {
                expect(event['eventTime'], isA<int>());
                received.add(type);
              }
              if (type == 'depth') {
                final book = event['book'] as Map;
                expect(book['lastUpdateId'], isA<int>());
                expect((book['bids'] as List).length, greaterThan(20));
                expect((book['asks'] as List).length, greaterThan(20));
                if (resetting &&
                    event['bookEpoch'] == 1 &&
                    !reset.isCompleted) {
                  reset.complete();
                }
              }
              if (received.length == 4 && !live.isCompleted) live.complete();
            }, onError: errors.add);
        try {
          await live.future.timeout(const Duration(seconds: 45));
          resetting = true;
          expect(feed.resetOrderBook(), 1);
          await reset.future.timeout(const Duration(seconds: 25));
          expect(errors, isEmpty);
          debugPrint(
            'MAC_SMOKE live REST/quote/candle/depth/trades/reset passed',
          );
        } finally {
          await subscription.cancel();
        }
        expect(feed.resetOrderBook(), isNull);
        final network = MacNetworkToolsClient(runtime);
        final dns = await network
            .run('dns', args: {'name': 'example.com', 'type': 'A'})
            .last
            .timeout(const Duration(seconds: 25));
        expect(dns['status'], 'complete', reason: '$dns');
        expect((dns['result'] as Map)['answers'], isNotEmpty);
        await runtime.channel.invokeMethod<void>('keepAwake', true);
        var state = await runtime.channel.invokeMapMethod<String, dynamic>(
          'state',
        );
        expect(state?['wakeStatus'], 'active');
        await runtime.channel.invokeMethod<void>('keepAwake', false);
        state = await runtime.channel.invokeMapMethod<String, dynamic>('state');
        expect(state?['wakeStatus'], 'off');
        final wasFullscreen = state?['fullscreen'] == true;
        await runtime.channel.invokeMethod<void>('fullscreen');
        Future<void> waitFullscreen(bool value) async {
          for (var attempt = 0; attempt < 30; attempt++) {
            final current = await runtime.channel
                .invokeMapMethod<String, dynamic>('state');
            if (current?['fullscreen'] == value) return;
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          fail('Native fullscreen did not reach $value');
        }

        try {
          await waitFullscreen(!wasFullscreen);
          // AppKit updates styleMask before the animation has finished.
          await Future<void>.delayed(const Duration(seconds: 1));
        } finally {
          await runtime.channel.invokeMethod<void>('fullscreen');
          await waitFullscreen(wasFullscreen);
        }
        browser.dispose();
        debugPrint(
          'MAC_SMOKE persistent store / DNS / display sleep assertion passed',
        );
      });
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
