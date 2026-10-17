import 'package:flutter/material.dart';

/// Rotates the entire navigator, including dialogs, without requiring an OS lock.
class OrientationFrame extends StatelessWidget {
  const OrientationFrame({
    super.key,
    required this.orientation,
    required this.child,
  });
  final String orientation;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final landscape = box.maxWidth > box.maxHeight;
      final rotate =
          (orientation == 'landscape' && !landscape) ||
          (orientation == 'portrait' && landscape);
      final media = MediaQuery.of(context);
      EdgeInsets turn(EdgeInsets e) =>
          EdgeInsets.fromLTRB(e.top, e.right, e.bottom, e.left);
      return RotatedBox(
        quarterTurns: rotate ? 1 : 0,
        child: MediaQuery(
          data: rotate
              ? media.copyWith(
                  size: Size(box.maxHeight, box.maxWidth),
                  padding: turn(media.padding),
                  viewPadding: turn(media.viewPadding),
                  viewInsets: turn(media.viewInsets),
                  systemGestureInsets: turn(media.systemGestureInsets),
                )
              : media,
          child: child,
        ),
      );
    },
  );
}
