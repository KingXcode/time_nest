import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'viewport_insets_stub.dart'
    if (dart.library.js_interop) 'viewport_insets_web.dart'
    as platform;

/// Embedded web views already exclude the top/side safe areas in their host.
/// Carry only its remaining bottom control inset into Flutter, before rotation.
class BrowserViewportInsets extends StatefulWidget {
  const BrowserViewportInsets({
    super.key,
    required this.child,
    this.bottomInset,
  });
  final Widget child;
  final ValueNotifier<double>? bottomInset;

  @override
  State<BrowserViewportInsets> createState() => _BrowserViewportInsetsState();
}

class _BrowserViewportInsetsState extends State<BrowserViewportInsets> {
  late final ValueNotifier<double> _inset =
      widget.bottomInset ?? platform.createViewportBottomInset();

  @override
  void dispose() {
    if (widget.bottomInset == null) _inset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: _inset,
    child: widget.child,
    builder: (context, value, child) {
      final media = MediaQuery.of(context);
      final bottom = value.isFinite && value > 0 ? value : 0.0;
      return MediaQuery(
        data: media.copyWith(
          padding: media.padding.copyWith(
            bottom: math.max(media.padding.bottom, bottom),
          ),
          viewPadding: media.viewPadding.copyWith(
            bottom: math.max(media.viewPadding.bottom, bottom),
          ),
        ),
        child: child!,
      );
    },
  );
}
