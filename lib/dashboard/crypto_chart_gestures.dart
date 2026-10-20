import 'dart:async';

import 'package:flutter/gestures.dart';

enum _Action { pending, pan, track, box, pinch, finishing }

/// Arbitrates chart gestures with the surrounding vertical page scroll.
/// Mouse navigation and touch tracking deliberately have different rules.
class CryptoChartGestureRecognizer extends OneSequenceGestureRecognizer {
  bool Function()? tracking;
  bool Function(PointerDeviceKind)? selecting;
  void Function(PointerDeviceKind)? onInput;
  void Function(Offset)? onTrack, onDoubleClick, onBoxStart, onBoxUpdate;
  void Function(Offset)? onPanStart, onPanUpdate, onPinchStart;
  void Function(double)? onPinchUpdate;
  void Function(bool)? onBoxEnd;
  void Function()? onEnd;

  final _points = <int, Offset>{};
  _Action _action = _Action.pending;
  PointerDeviceKind _kind = PointerDeviceKind.touch;
  Offset _origin = Offset.zero, _last = Offset.zero;
  Offset? _lastClick;
  Timer? _hold, _click;
  double _distance = 1;
  bool _selecting = false;

  bool get _mouse => _kind == PointerDeviceKind.mouse;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      (event.kind != PointerDeviceKind.mouse || _points.isEmpty) &&
      (event.kind != PointerDeviceKind.mouse ||
          event.buttons == kPrimaryMouseButton) &&
      super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _points[event.pointer] = event.localPosition;
    if (_points.length == 1) {
      _kind = event.kind;
      _origin = _last = event.localPosition;
      _action = _Action.pending;
      _selecting = selecting?.call(_kind) ?? false;
      onInput?.call(_kind);
      if (_mouse) {
        resolve(GestureDisposition.accepted);
      } else if (tracking?.call() ?? false) {
        _action = _Action.track;
        resolve(GestureDisposition.accepted);
        onTrack?.call(_origin);
      } else if (!_selecting) {
        _hold = Timer(const Duration(milliseconds: 400), () {
          if (_points.length != 1 || _action != _Action.pending) return;
          _action = _Action.track;
          resolve(GestureDisposition.accepted);
          onTrack?.call(_last);
        });
      }
    } else if (_points.length == 2 && !_mouse) {
      _hold?.cancel();
      _click?.cancel();
      _lastClick = null;
      if (_action == _Action.box) onBoxEnd?.call(true);
      _action = _Action.pinch;
      final pair = _points.values.toList();
      _distance = (pair[0] - pair[1]).distance.clamp(1.0, double.infinity);
      resolve(GestureDisposition.accepted);
      onPinchStart?.call((pair[0] + pair[1]) / 2);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_points.containsKey(event.pointer)) return;
    if (event is PointerMoveEvent) {
      _points[event.pointer] = event.localPosition;
      if (_action == _Action.pinch && _points.length >= 2) {
        final pair = _points.values.take(2).toList();
        onPinchUpdate?.call((pair[0] - pair[1]).distance / _distance);
        return;
      }
      if (_action == _Action.finishing) return;
      final delta = event.localPosition - _origin;
      if (_action == _Action.pending && delta.distance > kTouchSlop) {
        _hold?.cancel();
        _click?.cancel();
        _lastClick = null;
        if (!_mouse && delta.dy.abs() > delta.dx.abs()) {
          // Let the ancestor Scrollable win vertical gestures.
          resolve(GestureDisposition.rejected);
          return;
        }
        _action = _selecting ? _Action.box : _Action.pan;
        resolve(GestureDisposition.accepted);
        if (_action == _Action.box) {
          onBoxStart?.call(_origin);
        } else {
          _last = _origin;
          onPanStart?.call(_origin);
        }
      }
      switch (_action) {
        case _Action.pan:
          onPanUpdate?.call(event.localPosition - _last);
        case _Action.track:
          onTrack?.call(event.localPosition);
        case _Action.box:
          onBoxUpdate?.call(event.localPosition);
        default:
          break;
      }
      _last = event.localPosition;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _hold?.cancel();
      final cancelled = event is PointerCancelEvent;
      if (_action == _Action.box) onBoxEnd?.call(cancelled);
      if (_action == _Action.pending && !cancelled && _mouse) {
        final previous = _lastClick;
        if (previous != null &&
            (event.localPosition - previous).distance <= kDoubleTapSlop) {
          _click?.cancel();
          _lastClick = null;
          onDoubleClick?.call(event.localPosition);
        } else {
          _lastClick = event.localPosition;
          _click?.cancel();
          _click = Timer(kDoubleTapTimeout, () => _lastClick = null);
        }
      }
      _points.remove(event.pointer);
      if (_points.isNotEmpty) _action = _Action.finishing;
      resolve(GestureDisposition.accepted);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    _hold?.cancel();
    if (_points.remove(pointer) != null) {
      if (_action == _Action.box) onBoxEnd?.call(true);
      stopTrackingPointer(pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _hold?.cancel();
    _action = _Action.pending;
    onEnd?.call();
  }

  @override
  String get debugDescription => 'crypto chart navigation';

  @override
  void dispose() {
    _hold?.cancel();
    _click?.cancel();
    super.dispose();
  }
}
