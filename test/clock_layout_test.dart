import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/main.dart';
import 'package:time_nest/platform/browser_client.dart';
import 'package:time_nest/platform/browser_client_stub.dart';

class _MacBrowser extends MemoryBrowserClient {
  _MacBrowser() : super(introSeen: true);

  @override
  BrowserState get state => const BrowserState(nativeApp: true);
}

// Also run by macos_clock_layout_test with real SF font metrics on macOS.
void main() {
  testWidgets('Mac clock fits each digit group without spare character slots', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 21, 10, 50, 22);
    await tester.pumpWidget(ShikeApp(browser: _MacBrowser(), now: () => now));
    await tester.pump();
    final widths = <String, double>{};
    for (final time in [
      now,
      DateTime(2026, 10, 21, 11, 11, 11, 111),
      DateTime(2026, 10, 21, 18, 8, 8, 888),
      DateTime(2026, 10, 21, 20, 59, 59, 999),
    ]) {
      now = time;
      await tester.pump(const Duration(milliseconds: 50));
      for (final key in ['clock-hm', 'clock-seconds', 'clock-milliseconds']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byKey(Key(key)),
        );
        final intrinsicWidth = paragraph.getMaxIntrinsicWidth(double.infinity);
        expect(
          paragraph.size.width,
          closeTo(intrinsicWidth, .01),
          reason: '$key must use its actual font metrics at $time',
        );
        widths.putIfAbsent(key, () => paragraph.size.width);
        expect(
          paragraph.size.width,
          closeTo(widths[key]!, .01),
          reason: '$key must stay stable across ticks with tabular figures',
        );
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
