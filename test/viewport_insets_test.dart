import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_nest/platform/viewport_insets.dart';
import 'package:time_nest/ui/orientation_frame.dart';

void main() {
  testWidgets(
    'web bottom inset updates without doubling native or side padding',
    (tester) async {
      final inset = ValueNotifier<double>(34);
      addTearDown(inset.dispose);
      late MediaQueryData result;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(393, 852),
            padding: EdgeInsets.fromLTRB(4, 24, 5, 20),
            viewPadding: EdgeInsets.fromLTRB(4, 24, 5, 20),
          ),
          child: BrowserViewportInsets(
            bottomInset: inset,
            child: Builder(
              builder: (context) {
                result = MediaQuery.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(result.padding, const EdgeInsets.fromLTRB(4, 24, 5, 34));
      expect(result.viewPadding.bottom, 34);
      inset.value = 0;
      await tester.pump();
      expect(result.padding.bottom, 20);
      expect(result.viewPadding.bottom, 20);
    },
  );

  testWidgets(
    'injected web bottom inset rotates with the page and clears above keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final inset = ValueNotifier<double>(34);
      addTearDown(inset.dispose);
      late MediaQueryData result;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(393, 852)),
          child: BrowserViewportInsets(
            bottomInset: inset,
            child: OrientationFrame(
              orientation: 'landscape',
              child: Builder(
                builder: (context) {
                  result = MediaQuery.of(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      expect(result.padding.right, 34);
      expect(result.padding.bottom, 0);
      inset.value = 0;
      await tester.pump();
      expect(result.padding, EdgeInsets.zero);
      expect(result.viewPadding, EdgeInsets.zero);
    },
  );
}
