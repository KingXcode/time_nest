import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/dashboard/crypto_feed_native.dart';
import 'package:time_nest/dashboard/dashboard_client_native.dart';
import 'package:time_nest/platform/browser_client_native.dart';
import 'package:time_nest/platform/native_runtime.dart';
import 'package:time_nest/platform/native_store.dart';
import 'package:time_nest/toolbox/network_tools_client_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late NativeRuntime runtime;
  late List<MethodCall> calls;
  const channel = MethodChannel('com.kingxcode.shike/macos');
  const codec = StandardMethodCodec();
  void host(Map<String, dynamic> value) {
    ServicesBinding.instance.channelBuffers.push(
      channel.name,
      codec.encodeMethodCall(MethodCall('serviceEvent', jsonEncode(value))),
      (_) {},
    );
  }

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('shike-native-test-');
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'supportDirectory') return directory.path;
          if (call.method == 'state') {
            return {
              'visible': true,
              'wakeSupported': true,
              'wakeStatus': 'off',
              'fullscreenSupported': true,
            };
          }
          if (call.method == 'serviceCall') {
            final args = call.arguments as Map;
            dynamic value = true;
            if (args['method'] == 'environment') value = '{"online":true}';
            if (args['method'] == 'request') {
              value = jsonEncode({
                'data': {'value': 123},
                'fetchedAt': '2026-10-21T00:00:00.000Z',
              });
            }
            scheduleMicrotask(
              () => host({'type': 'reply', 'id': args['id'], 'value': value}),
            );
          }
          return null;
        });
    runtime = NativeRuntime();
    await runtime.initialize();
  });
  tearDown(() {
    runtime.dispose();
    NativeRuntime.current = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });

  test('settings and timer persist atomically across native store instances; rejected writes preserve the old data', () async {
    final browser = MacBrowserClient(runtime);
    expect(browser.state.nativeApp, true);
    expect(browser.state.fullscreenSupported, true);
    expect(browser.writeSettings('{"keepAwake":true}'), true);
    expect(browser.writeTimer('{"remaining":42}'), true);
    expect(browser.markIntroSeen(), true);
    await Future<void>.delayed(Duration.zero);
    final reopened = NativeStore(directory);
    expect(reopened.read('shike.settings.v1'), '{"keepAwake":true}');
    expect(reopened.read('shike.timer.v1'), '{"remaining":42}');
    expect(reopened.read('shike.intro.v1'), '1');
    final saved = reopened.file.readAsStringSync();
    expect(reopened.write('untrusted.key', 'x'), false);
    expect(
      reopened.write('shike.too-large', 'x' * NativeStore.maxBytes),
      false,
    );
    expect(reopened.file.readAsStringSync(), saved);
    browser.dispose();
  });

  test('native stream packets preserve integer IDs, cancel exactly once and ignore late updates', () async {
    final feed = MacCryptoFeed(runtime);
    final stream = feed.subscribe(
      'BTCUSDT',
      '1h',
      orderBook: true,
      trades: true,
    );
    expect(feed.resetOrderBook(), null);
    final events = <Map<String, dynamic>>[];
    final subscription = stream.listen(events.add);
    await Future<void>.delayed(Duration.zero);
    final start =
        calls
                .lastWhere(
                  (c) =>
                      c.method == 'serviceCall' &&
                      (c.arguments as Map)['method'] == 'subscribe',
                )
                .arguments
            as Map;
    final token = (start['args'] as Map)['token'];
    host({
      'type': 'event',
      'token': token,
      'value': {
        'type': 'candle',
        'eventTime': 1761011050000,
        'bookEpoch': 0,
        'updateId': 1234567890123,
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(events.single['eventTime'], isA<int>());
    expect(events.single['updateId'], 1234567890123);
    expect(feed.resetOrderBook(), 1);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(feed.resetOrderBook(), null);
    host({
      'type': 'event',
      'token': token,
      'value': {'type': 'quote'},
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(
      calls.where(
        (c) =>
            c.method == 'serviceCall' &&
            (c.arguments as Map)['method'] == 'cancel',
      ),
      hasLength(1),
    );
  });

  test('dashboard uses the shared worker and preferences file while native links reject unsafe schemes', () async {
    final client = MacDashboardClient(runtime);
    final value = await client.load('weather', {
      'latitude': 31.2,
      'longitude': 121.4,
    });
    expect(value.data['value'], 123);
    expect(client.writePreferences('{"cryptoSymbol":"ETHUSDT"}'), true);
    expect(client.readPreferences(), '{"cryptoSymbol":"ETHUSDT"}');
    client.openUrl('file:///etc/passwd');
    client.openUrl('https://user:secret@example.com');
    client.openUrl('https://example.com');
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c.method == 'openUrl').map((c) => c.arguments), [
      'https://example.com',
    ]);
  });

  test('network tools remain on demand and terminate their native subscription on completion', () async {
    final client = MacNetworkToolsClient(runtime);
    final result = client.run(
      'dns',
      args: {'name': 'example.com', 'type': 'A'},
    );
    expect(
      calls.where(
        (c) =>
            c.method == 'serviceCall' &&
            (c.arguments as Map)['method'] == 'subscribe',
      ),
      isEmpty,
    );
    final completed = result.toList();
    await Future<void>.delayed(Duration.zero);
    final start =
        calls
                .lastWhere(
                  (c) =>
                      c.method == 'serviceCall' &&
                      (c.arguments as Map)['method'] == 'subscribe',
                )
                .arguments
            as Map;
    final token = (start['args'] as Map)['token'];
    host({
      'type': 'event',
      'token': token,
      'value': {'status': 'complete', 'kind': 'dns', 'result': {}},
    });
    expect((await completed).single['status'], 'complete');
    await Future<void>.delayed(Duration.zero);
    expect(
      calls.where(
        (c) =>
            c.method == 'serviceCall' &&
            (c.arguments as Map)['method'] == 'cancel',
      ),
      hasLength(1),
    );
  });
}
