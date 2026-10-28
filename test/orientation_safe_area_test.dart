import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/ui/orientation_frame.dart';

void main() {
  testWidgets('manual rotation turns safe edges once and restores on return', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    MediaQueryData? measured;
    Future<void> show(String orientation) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.fromLTRB(0, 47, 0, 34),
            viewPadding: EdgeInsets.fromLTRB(0, 47, 0, 34),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: OrientationFrame(
              orientation: orientation,
              child: Builder(
                builder: (context) {
                  measured = MediaQuery.of(context);
                  return const SafeArea(child: SizedBox.expand());
                },
              ),
            ),
          ),
        ),
      );
    }

    for (var cycle = 0; cycle < 3; cycle++) {
      await show('landscape');
      expect(measured!.size, const Size(844, 390));
      expect(measured!.padding, const EdgeInsets.fromLTRB(47, 0, 34, 0));
      expect(measured!.viewPadding, measured!.padding);
      expect(tester.takeException(), isNull);
      await show('auto');
      expect(measured!.size, const Size(390, 844));
      expect(measured!.padding, const EdgeInsets.fromLTRB(0, 47, 0, 34));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'already inset embedded web host does not gain native safe edges',
    (tester) async {
      tester.view.physicalSize = const Size(390, 763);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final content = GlobalKey();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 763)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: OrientationFrame(
              orientation: 'auto',
              child: SafeArea(
                minimum: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: SizedBox.expand(key: content),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(content)),
        const Rect.fromLTWH(20, 12, 350, 739),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
