import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/ui/apple_button.dart';
import 'package:time_nest/ui/apple_theme.dart';

void main() {
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
