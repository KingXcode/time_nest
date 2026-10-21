import 'dart:async';

import 'package:flutter/material.dart';
import 'package:time_nest/ui/apple_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/toolbox/network_tools_client.dart';
import 'package:time_nest/toolbox/toolbox_screen.dart';

class FixtureNetworkToolsClient implements NetworkToolsClient {
  final calls = <Map<String, dynamic>>[];
  final opened = <String>[];
  final controllers = <StreamController<Map<String, dynamic>>>[];
  int cancellations = 0;
  int environmentReads = 0;
  bool throwOnRun = false;
  bool historyAvailable = true;
  bool clearSucceeds = true;
  int historyReads = 0;
  int clearCalls = 0;
  final historyItems = <Map<String, dynamic>>[];

  @override
  Map<String, dynamic> history() {
    historyReads++;
    return {
      'available': historyAvailable,
      'items': List<Map<String, dynamic>>.from(historyItems),
    };
  }

  @override
  bool clearHistory() {
    clearCalls++;
    if (clearSucceeds) historyItems.clear();
    return clearSucceeds;
  }

  bool throwOnEnvironment = false;
  Map<String, dynamic> environmentData = {
    'online': true,
    'secure': true,
    'effectiveType': '4g',
    'estimatedDownlinkMbps': 10,
    'estimatedRttMs': 50,
    'saveData': false,
  };

  @override
  Map<String, dynamic> environment() {
    environmentReads++;
    if (throwOnEnvironment) throw StateError('not available');
    return environmentData;
  }

  @override
  void openUrl(String url) => opened.add(url);

  @override
  Stream<Map<String, dynamic>> run(
    String kind, {
    Map<String, dynamic> args = const {},
  }) {
    if (throwOnRun) throw StateError('无法连接检测服务。');
    late StreamController<Map<String, dynamic>> controller;
    controller = StreamController(
      onListen: () => calls.add({'kind': kind, ...args}),
      onCancel: () {
        cancellations++;
        // Own the completion in the widget-test zone rather than using the
        // SDK's shared already-completed cancellation future.
        return Future<void>.value();
      },
    );
    controllers.add(controller);
    return controller.stream;
  }

  void emit(Map<String, dynamic> snapshot) => controllers.last.add(snapshot);
}

Future<void> pumpToolbox(
  WidgetTester tester,
  FixtureNetworkToolsClient client, {
  Size size = const Size(1100, 900),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: ToolboxScreen(client: client),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> consent(WidgetTester tester) => tapVisible(
  tester,
  find.descendant(
    of: find.byKey(const ValueKey('toolbox-consent')),
    matching: find.byType(Checkbox),
  ),
);

Future<void> start(WidgetTester tester) =>
    tapVisible(tester, find.byKey(const ValueKey('toolbox-start')));

Future<void> selectTool(WidgetTester tester, String kind) =>
    tapVisible(tester, find.byKey(ValueKey('toolbox-tab-$kind')));

Map<String, dynamic> speedSnapshot({
  String status = 'complete',
  Map<String, dynamic>? result,
}) => {
  'kind': 'speed',
  'status': status,
  'stage': status == 'running' ? 'download' : 'done',
  'progress': status == 'running' ? .5 : 1,
  'result':
      result ??
      {
        'provider': 'Cloudflare',
        'downloadMbps': 42.7,
        'uploadMbps': 18.3,
        'latencyMs': 35.2,
        'jitterMs': 2.1,
        'downloadBytes': 6291456,
        'uploadBytes': 1048576,
        'samples': [34, 36, 35],
        'successful': 3,
        'attempted': 3,
        'completedAt': '2026-10-20T12:34:56Z',
        'warnings': <String>[],
      },
};

void main() {
  testWidgets(
    'opening and changing tabs never auto-run; consent starts unchecked',
    (tester) async {
      final client = FixtureNetworkToolsClient();
      await pumpToolbox(tester, client);
      expect(client.calls, isEmpty);
      expect(client.environmentReads, 1);
      expect(find.text('—'), findsNWidgets(4));
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('toolbox-consent')),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<AppleButton>(find.byKey(const ValueKey('toolbox-start')))
            .onPressed,
        isNull,
      );
      await start(tester);
      await selectTool(tester, 'latency');
      await selectTool(tester, 'dns');
      expect(client.calls, isEmpty);
      expect(client.environmentReads, 1);
      expect(find.text('例如 example.com'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'explicit consent starts one test, cancellation and restart work',
    (tester) async {
      final client = FixtureNetworkToolsClient();
      await pumpToolbox(tester, client);
      await consent(tester);
      await start(tester);
      await start(tester);
      expect(client.calls, [
        {'kind': 'speed'},
      ]);
      client.emit(speedSnapshot(status: 'running'));
      await tester.pumpAndSettle();
      expect(find.text('测量下载'), findsOneWidget);
      expect(find.text('42.7'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('toolbox-cancel')));
      await tester.pumpAndSettle();
      expect(client.cancellations, 1);
      expect(find.text('已取消'), findsOneWidget);
      // A late response from a cancelled subscription cannot replace the snapshot.
      client.controllers.first.add(
        speedSnapshot(result: {'downloadMbps': 9999}),
      );
      await tester.pumpAndSettle();
      expect(find.text('9999'), findsNothing);
      await start(tester);
      expect(client.calls.length, 2);
      expect(find.text('42.7'), findsNothing);
      expect(find.text('—'), findsNWidgets(4));
    },
  );

  testWidgets(
    'switching tools cancels run, resets consent and preserves snapshots',
    (tester) async {
      final client = FixtureNetworkToolsClient();
      await pumpToolbox(tester, client);
      await consent(tester);
      await start(tester);
      client.emit(speedSnapshot(status: 'running'));
      await tester.pumpAndSettle();
      await selectTool(tester, 'latency');
      await tester.pumpAndSettle();
      expect(client.cancellations, 1);
      expect(find.text('检测目标 · 本站托管节点 / GitHub Pages'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('toolbox-consent')),
            )
            .value,
        isFalse,
      );
      expect(client.calls.length, 1);
      await selectTool(tester, 'speed');
      expect(find.text('42.7'), findsOneWidget);
      expect(find.text('已取消'), findsOneWidget);
    },
  );

  testWidgets('disposing cancels subscription; late emissions do not throw', (
    tester,
  ) async {
    final client = FixtureNetworkToolsClient();
    await pumpToolbox(tester, client);
    await consent(tester);
    await start(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(client.cancellations, 1);
    client.emit(speedSnapshot());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('background lifecycle cancels and never resumes automatically', (
    tester,
  ) async {
    final client = FixtureNetworkToolsClient();
    await pumpToolbox(tester, client);
    await consent(tester);
    await start(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    expect(client.cancellations, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('页面已切到后台，本次检测已取消。'), findsOneWidget);
    expect(client.calls.length, 1);
  });

  testWidgets(
    'results show measured values, timestamp and null values as missing',
    (tester) async {
      final client = FixtureNetworkToolsClient();
      await pumpToolbox(tester, client);
      await consent(tester);
      await start(tester);
      client.emit(speedSnapshot());
      await tester.pumpAndSettle();
      expect(find.text('42.7'), findsOneWidget);
      expect(find.text('18.3'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      expect(find.textContaining('检测时间：2026-10-20'), findsOneWidget);
      expect(find.textContaining('6.00 MiB'), findsOneWidget);
      await start(tester);
      client.emit(
        speedSnapshot(
          result: {
            'downloadMbps': null,
            'uploadMbps': double.nan,
            'latencyMs': null,
            'jitterMs': null,
            'warnings': ['下载请求未完成，未估算速度。'],
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('—'), findsNWidgets(4));
      expect(find.text('0.0'), findsNothing);
      expect(find.text('下载请求未完成，未估算速度。'), findsOneWidget);
      expect(find.text('42.7'), findsNothing);
    },
  );

  testWidgets(
    'bridge errors, thrown errors and unfinished streams are visible',
    (tester) async {
      final client = FixtureNetworkToolsClient();
      await pumpToolbox(tester, client);
      await consent(tester);
      await start(tester);
      client.emit({
        'kind': 'speed',
        'status': 'error',
        'message': '服务暂时不可用，请稍后重试。',
        'result': <String, dynamic>{},
      });
      await tester.pumpAndSettle();
      expect(find.text('服务暂时不可用，请稍后重试。'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(4));
      await start(tester);
      client.controllers.last.addError(Exception('请求已超时。'));
      await tester.pumpAndSettle();
      expect(find.text('请求已超时。'), findsOneWidget);
      await start(tester);
      await client.controllers.last.close();
      await tester.pumpAndSettle();
      expect(find.text('检测已中断，未收到完整结果。请稍后重试。'), findsOneWidget);
      client.throwOnRun = true;
      await start(tester);
      expect(find.textContaining('无法连接检测服务。'), findsOneWidget);
    },
  );

  testWidgets(
    'latency uses independent target and accessible real-sample chart',
    (tester) async {
      final client = FixtureNetworkToolsClient();
      await pumpToolbox(tester, client);
      await selectTool(tester, 'latency');
      expect(find.textContaining('向本站托管节点采集 10 次'), findsOneWidget);
      expect(find.text('测速方法与来源 ↗'), findsNothing);
      await consent(tester);
      await start(tester);
      expect(client.calls.last, {'kind': 'latency'});
      client.emit({
        'kind': 'latency',
        'status': 'complete',
        'result': {
          'provider': '本站 HTTPS',
          'latencyMs': 24.6,
          'jitterMs': 2.3,
          'samples': [20, 22, null, 25, 30, 24, 26, 28, 23, 23],
          'successful': 9,
          'attempted': 10,
          'completedAt': '2026-10-20T12:34:56Z',
        },
      });
      await tester.pumpAndSettle();
      expect(find.text('成功 9 / 已尝试 10'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('请求延迟曲线，10 个样本')), findsOneWidget);
      expect(find.text('24.6'), findsOneWidget);
      expect(find.text('2.3'), findsOneWidget);
      expect(find.textContaining('网络丢包率'), findsWidgets);
    },
  );

  testWidgets(
    'DNS validates input, sends type and displays answers and rcode',
    (tester) async {
      final client = FixtureNetworkToolsClient();
      await pumpToolbox(tester, client);
      await selectTool(tester, 'dns');
      await consent(tester);
      await start(tester);
      expect(client.calls, isEmpty);
      expect(find.text('请输入要查询的域名，例如 example.com。'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('toolbox-domain')),
        ' example.com ',
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('toolbox-record-type')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('MX').last);
      await tester.pumpAndSettle();
      await start(tester);
      expect(client.calls.last, {
        'kind': 'dns',
        'name': 'example.com',
        'type': 'MX',
      });
      client.emit({
        'kind': 'dns',
        'status': 'complete',
        'result': {
          'provider': 'Cloudflare',
          'name': 'example.com',
          'type': 'MX',
          'rcode': 0,
          'dnssec': true,
          'answers': [
            {
              'name': 'example.com.',
              'type': 'MX',
              'ttl': 300,
              'data': '10 mail.example.com.',
            },
          ],
          'completedAt': '2026-10-20T12:34:56Z',
        },
      });
      await tester.pumpAndSettle();
      expect(find.text('10 mail.example.com.'), findsOneWidget);
      expect(find.text('TTL 300 秒'), findsOneWidget);
      expect(find.text('DNSSEC 已验证'), findsOneWidget);
      expect(find.text('NOERROR'), findsOneWidget);
      await start(tester);
      client.emit({
        'kind': 'dns',
        'status': 'complete',
        'result': {
          'name': 'example.com',
          'type': 'MX',
          'rcode': 3,
          'answers': [],
        },
      });
      await tester.pumpAndSettle();
      expect(find.text('NXDOMAIN'), findsOneWidget);
      expect(find.text('该域名不存在（NXDOMAIN）。'), findsOneWidget);
      expect(find.text('10 mail.example.com.'), findsNothing);
      for (final code in [2, 5]) {
        await start(tester);
        client.emit({
          'kind': 'dns',
          'status': 'error',
          'message': '公共解析器未能完成查询。',
          'result': {
            'name': 'example.com',
            'type': 'MX',
            'rcode': code,
            'answers': [],
          },
        });
        await tester.pumpAndSettle();
        expect(find.text(code == 2 ? 'SERVFAIL' : 'REFUSED'), findsOneWidget);
        expect(
          find.textContaining(code == 2 ? '公共解析器处理失败' : '公共解析器拒绝'),
          findsOneWidget,
        );
        expect(find.text('本次响应没有此类型的记录。'), findsNothing);
      }
    },
  );

  testWidgets(
    'provider links are explicit and unsupported environment is honest',
    (tester) async {
      final client = FixtureNetworkToolsClient()..throwOnEnvironment = true;
      await pumpToolbox(tester, client);
      expect(find.text('未提供'), findsNWidgets(6));
      await tapVisible(tester, find.text('隐私政策 ↗'));
      await tapVisible(tester, find.text('网站条款 ↗'));
      expect(client.opened, [
        'https://www.cloudflare.com/privacypolicy/',
        'https://www.cloudflare.com/website-terms/',
      ]);
      expect(client.calls, isEmpty);
    },
  );

  testWidgets(
    'history refreshes after results and clears only with confirmation',
    (tester) async {
      final client = FixtureNetworkToolsClient();
      await pumpToolbox(tester, client);
      expect(client.historyReads, 1);
      expect(find.text('暂无本地测试记录'), findsOneWidget);
      await consent(tester);
      await start(tester);
      client.historyItems.add({
        'kind': 'speed',
        'status': 'complete',
        'provider': 'Cloudflare',
        'completedAt': '2026-10-20T12:34:56Z',
        'downloadMbps': 42.7,
        'uploadMbps': 18.3,
        'latencyMs': 35.2,
        'jitterMs': 2.1,
      });
      client.emit(speedSnapshot());
      await tester.pumpAndSettle();
      expect(client.historyReads, 2);
      expect(find.text('下载 42.7 Mbps'), findsOneWidget);
      expect(find.byKey(const ValueKey('toolbox-history-0')), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('toolbox-clear-history')),
      );
      expect(client.clearCalls, 0);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(client.clearCalls, 0);
      expect(client.historyItems, isNotEmpty);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('toolbox-clear-history')),
      );
      await tester.tap(find.widgetWithText(TextButton, '清空'));
      await tester.pumpAndSettle();
      expect(client.clearCalls, 1);
      expect(client.historyItems, isEmpty);
      expect(find.text('暂无本地测试记录'), findsOneWidget);
      expect(
        find.text('42.7'),
        findsOneWidget,
        reason: 'Clearing history does not erase current result.',
      );
    },
  );

  testWidgets(
    'history never presents DNS, failed numbers, or more than 20 records',
    (tester) async {
      final client = FixtureNetworkToolsClient();
      client.historyItems.add({
        'kind': 'dns',
        'name': 'private.example',
        'status': 'complete',
      });
      client.historyItems.add({
        'kind': 'speed',
        'status': 'cancelled',
        'downloadMbps': 999,
      });
      for (var i = 0; i < 22; i++) {
        client.historyItems.add({
          'kind': 'latency',
          'status': 'complete',
          'provider': '本站 HTTPS',
          'completedAt': '2026-10-20T12:34:56Z',
          'latencyMs': 20 + i,
          'jitterMs': null,
        });
      }
      await pumpToolbox(tester, client);
      expect(find.textContaining('private.example'), findsNothing);
      expect(find.textContaining('999'), findsNothing);
      expect(find.text('抖动 — ms'), findsNWidgets(4));
      expect(find.text('展开全部 20 条'), findsOneWidget);
      await tapVisible(tester, find.text('展开全部 20 条'));
      expect(find.byKey(const ValueKey('toolbox-history-19')), findsOneWidget);
      expect(find.byKey(const ValueKey('toolbox-history-20')), findsNothing);
      expect(client.calls, isEmpty);
      client.historyAvailable = false;
      await tapVisible(
        tester,
        find.byKey(const ValueKey('toolbox-refresh-history')),
      );
      expect(find.textContaining('浏览器存储不可用'), findsOneWidget);
      client.clearSucceeds = false;
      await tapVisible(
        tester,
        find.byKey(const ValueKey('toolbox-clear-history')),
      );
      await tester.tap(find.widgetWithText(TextButton, '清空'));
      await tester.pumpAndSettle();
      expect(find.text('无法清空本地记录，请检查浏览器存储权限后重试。'), findsOneWidget);
      expect(client.historyItems, isNotEmpty);
      expect(client.calls, isEmpty);
    },
  );

  for (final scenario in [
    (size: const Size(320, 700), scale: 1.0, name: '320px'),
    (size: const Size(700, 320), scale: 1.0, name: 'landscape'),
    (size: const Size(320, 700), scale: 2.0, name: '320px with 2x text'),
    (size: const Size(1440, 900), scale: 2.0, name: 'desktop with 2x text'),
  ]) {
    testWidgets('toolbox fits ${scenario.name} including long DNS data', (
      tester,
    ) async {
      final client = FixtureNetworkToolsClient();
      client.historyItems.add({
        'kind': 'speed',
        'status': 'complete',
        'provider': 'Cloudflare',
        'completedAt': '2026-10-20T12:34:56Z',
        'downloadMbps': 42.7,
        'uploadMbps': 18.3,
        'latencyMs': 35.2,
        'jitterMs': null,
      });
      await pumpToolbox(
        tester,
        client,
        size: scenario.size,
        scale: scenario.scale,
      );
      expect(tester.takeException(), isNull);
      await consent(tester);
      await start(tester);
      client.emit(speedSnapshot());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await selectTool(tester, 'latency');
      expect(tester.takeException(), isNull);
      await selectTool(tester, 'dns');
      await tester.enterText(
        find.byKey(const ValueKey('toolbox-domain')),
        'example.com',
      );
      await consent(tester);
      await start(tester);
      client.emit({
        'kind': 'dns',
        'status': 'complete',
        'result': {
          'name': 'example.com',
          'type': 'TXT',
          'rcode': 0,
          'answers': [
            {
              'name': 'a-very-long-subdomain.example.com.',
              'type': 'TXT',
              'ttl': 3600,
              'data':
                  'v=verification; token=${List.filled(12, 'abcdef1234567890').join()}',
            },
          ],
        },
      });
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('toolbox-dns-answer-0')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
