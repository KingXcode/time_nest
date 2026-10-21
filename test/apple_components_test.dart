import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/ui/apple_button.dart';
import 'package:time_nest/ui/apple_theme.dart';

void main() {
  testWidgets('Apple city-style buttons retain left content alignment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appleTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: AppleButton.bordered(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(12),
                ),
                child: const Text('上海'),
              ),
            ),
          ),
        ),
      ),
    );
    final button = tester.getRect(find.byType(AppleButton));
    final label = tester.getRect(find.text('上海'));
    expect(label.left, closeTo(button.left + 12, .01));
    expect(tester.takeException(), isNull);
  });

  for (final alignment in IconAlignment.values) {
    testWidgets('Apple icon label fits a narrow control at $alignment', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appleTheme(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 160,
                  child: AppleButton.textIcon(
                    onPressed: () {},
                    iconAlignment: alignment,
                    icon: const Icon(Icons.expand_more, size: 20),
                    label: const Text(
                      '1000SATS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final button = tester.getRect(find.byType(AppleButton));
      final label = tester.getRect(find.text('1000SATS'));
      final icon = tester.getRect(find.byIcon(Icons.expand_more));
      expect(label.left, greaterThanOrEqualTo(button.left));
      expect(label.right, lessThanOrEqualTo(button.right));
      expect(icon.left, greaterThanOrEqualTo(button.left));
      expect(icon.right, lessThanOrEqualTo(button.right));
    });
  }

  testWidgets('Apple action keeps the original minimum size and padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appleTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: AppleButton.filledIcon(
              onPressed: () {},
              style: FilledButton.styleFrom(
                minimumSize: const Size(132, 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('开始'),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(AppleButton)), const Size(132, 44));
    final icon = tester.getRect(find.byIcon(Icons.play_arrow_rounded));
    final button = tester.getRect(find.byType(AppleButton));
    expect(icon.top - button.top, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Apple controls preserve actions, disabled states and identifying keys',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appleTheme(),
          home: Scaffold(
            body: Column(
              children: [
                AppleButton.filledIcon(
                  key: const Key('start'),
                  onPressed: () => calls++,
                  icon: const Icon(CupertinoIcons.play_fill),
                  label: const Text('开始'),
                ),
                const AppleButton.bordered(
                  key: Key('disabled'),
                  onPressed: null,
                  child: Text('暂停'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(CupertinoButton), findsNWidgets(2));
      expect(find.byKey(const Key('start')), findsOneWidget);
      await tester.tap(find.byKey(const Key('start')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, 1);
      await tester.tap(find.byKey(const Key('disabled')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'existing Web theme retains Material controls and callback behavior',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'ShikeSans'),
          home: Scaffold(
            body: AppleButton.filled(
              key: const Key('start'),
              onPressed: () => calls++,
              child: const Text('开始'),
            ),
          ),
        ),
      );
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(CupertinoButton), findsNothing);
      await tester.tap(find.byKey(const Key('start')));
      await tester.pump();
      expect(calls, 1);
    },
  );
}
