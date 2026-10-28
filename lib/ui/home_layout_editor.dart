import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../clock/clock_controller.dart';
import '../clock/clock_settings.dart';
import '../clock/home_layout.dart';
import '../dashboard/crypto_market.dart';
import '../dashboard/crypto_pair_picker.dart';
import '../dashboard/dashboard_client.dart';
import '../dashboard/dashboard_preferences.dart';
import '../dashboard/weather_panel.dart';
import 'clock_face.dart';
import 'home_layout_canvas.dart';

class HomeLayoutEditResult {
  const HomeLayoutEditResult(this.layout, this.preferences);
  final HomeLayout layout;
  final DashboardPreferences preferences;
}

/// The entire edit session is a local draft. Only the explicit Save route result
/// is persisted by the caller; back, Escape and Cancel never write preferences.
class HomeLayoutEditor extends StatefulWidget {
  const HomeLayoutEditor({
    super.key,
    required this.layout,
    required this.clock,
    required this.settings,
    required this.client,
    required this.preferences,
    required this.desktop,
    this.landscape = true,
  });
  final HomeLayout layout;
  final ClockController clock;
  final ClockSettings settings;
  final DashboardClient client;
  final DashboardPreferences preferences;
  final bool desktop, landscape;
  @override
  State<HomeLayoutEditor> createState() => _HomeLayoutEditorState();
}

class _HomeLayoutEditorState extends State<HomeLayoutEditor> {
  late HomeLayout _draft = widget.layout.copyWith(enabled: true);
  late final DashboardPreferences _prefs = DashboardPreferences.decode(
    widget.preferences.encode(),
  );
  late bool _wide = widget.desktop || widget.landscape;
  String _selected = 'time';
  String? _placementMessage;
  final _canvasKey = GlobalKey();
  Offset _canvasPoint(Offset global) =>
      (_canvasKey.currentContext!.findRenderObject()! as RenderBox)
          .globalToLocal(global);
  HomeModuleLayout? _gestureStart;
  Offset _focalStart = Offset.zero;
  HomeModuleLayout get _item => _draft.forOrientation(_wide)[_selected]!;
  void _change(HomeModuleLayout value) => setState(() {
    final current = _draft.forOrientation(_wide);
    // Hiding is not a geometry edit: preserve legacy/off-grid positions.
    final previous = current[_selected]!;
    final hiding = previous.visible && !value.visible;
    final constrained = hiding
        ? previous.copyWith(visible: false)
        : HomeLayout.constrainEdit(_selected, value, wide: _wide);
    if (current.entries.any(
      (entry) =>
          entry.key != _selected &&
          HomeLayout.overlaps(constrained, entry.value),
    )) {
      _placementMessage = '位置与其他组件重叠，请移到空白处或使用「一键整理」。';
      return;
    }
    _placementMessage = null;
    final modules = {...current, _selected: constrained};
    _draft = _wide
        ? _draft.copyWith(landscape: modules)
        : _draft.copyWith(portrait: modules);
  });
  void _zoom(double factor) {
    final item = _item;
    final maxFactor = math.min(1 / item.width, 1 / item.height);
    final minFactor = math.max(.12 / item.width, .06 / item.height);
    final scale = factor.clamp(minFactor, maxFactor);
    final w = item.width * scale, h = item.height * scale;
    _change(
      item.copyWith(
        width: w,
        height: h,
        x: item.x + (item.width - w) / 2,
        y: item.y + (item.height - h) / 2,
      ),
    );
  }

  Future<void> _precise() async {
    final item = _item;
    final result = await showDialog<HomeModuleLayout>(
      context: context,
      builder: (_) =>
          _PreciseLayoutDialog(label: homeModuleLabels[_selected]!, item: item),
    );
    if (mounted && result != null) _change(result);
  }

  Future<void> _city() async {
    Map<String, dynamic>? chosen;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: WeatherPanel(
              client: widget.client,
              city: _prefs.city,
              onCityChanged: (city) {
                chosen = city;
                Navigator.pop(context);
              },
            ),
          ),
        ),
      ),
    );
    if (mounted && chosen != null) setState(() => _prefs.city = chosen);
  }

  Future<void> _pair() async {
    final pair = await showCryptoPairPicker(
      context,
      client: widget.client,
      current:
          cryptoPairForSymbol(_prefs.cryptoSymbol) ??
          const CryptoPair(
            symbol: 'BTCUSDT',
            baseAsset: 'BTC',
            quoteAsset: 'USDT',
          ),
      chooseQuote: false,
    );
    if (mounted && pair != null) {
      setState(() => _prefs.cryptoSymbol = pair.symbol);
    }
  }

  Widget _controls() => SingleChildScrollView(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final id in homeModules)
              ChoiceChip(
                key: ValueKey('select-$id'),
                label: Text(homeModuleLabels[id]!),
                selected: _selected == id,
                onSelected: (_) => setState(() {
                  _selected = id;
                  _gestureStart = null;
                  _placementMessage = null;
                }),
              ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                '${homeModuleLabels[_selected]} · ${(_item.width * 100).round()} × ${(_item.height * 100).round()}%',
              ),
            ),
            Switch(
              key: const Key('module-visible'),
              value: _item.visible,
              onChanged: (v) => _change(_item.copyWith(visible: v)),
            ),
            const Text('显示'),
          ],
        ),
        Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: '缩小',
              onPressed: () => _zoom(.9),
              icon: const Icon(Icons.remove),
            ),
            IconButton(
              tooltip: '放大',
              onPressed: () => _zoom(1.1),
              icon: const Icon(Icons.add),
            ),
            TextButton(onPressed: _precise, child: const Text('坐标与大小')),
            if (_selected == 'weather')
              TextButton(
                onPressed: _city,
                child: Text(_prefs.city?['name']?.toString() ?? '选择城市'),
              ),
            if (_selected == 'crypto') ...[
              TextButton(onPressed: _pair, child: Text(_prefs.cryptoSymbol)),
              DropdownButton<String>(
                value: _prefs.cryptoInterval,
                items: [
                  for (final entry in cryptoIntervals.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.key)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _prefs.cryptoInterval = v);
                },
              ),
            ],
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              key: const Key('arrange-layout'),
              onPressed: () => setState(() {
                final arranged = HomeLayout.arranged(
                  _draft.forOrientation(_wide),
                  wide: _wide,
                );
                _draft = _wide
                    ? _draft.copyWith(landscape: arranged)
                    : _draft.copyWith(portrait: arranged);
                _placementMessage = null;
              }),
              icon: const Icon(Icons.grid_view_rounded, size: 18),
              label: const Text('一键整理'),
            ),
            TextButton(
              onPressed: () =>
                  _change(_item.copyWith(x: (1 - _item.width) / 2)),
              child: const Text('水平居中'),
            ),
          ],
        ),
        if (_placementMessage != null)
          Text(
            _placementMessage!,
            style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
          ),
        const Text(
          '网格吸附 · 统一边距 · 防止重叠\n拖拽移动 / 双指或滚轮缩放，方向键按网格调整',
          style: TextStyle(fontSize: 12, color: Color(0xFF98A2AF)),
        ),
        if (_selected == 'date' && !widget.settings.showDate)
          const Text('展示设置中的日期已关闭；开启后首页才显示日期。', style: TextStyle(fontSize: 12)),
      ],
    ),
  );
  Widget _preview() => Padding(
    padding: const EdgeInsets.all(16),
    child: Center(
      child: AspectRatio(
        aspectRatio: _wide ? 16 / 9 : 9 / 16,
        child: DecoratedBox(
          key: const Key('layout-preview'),
          decoration: BoxDecoration(
            color: clockBackground,
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: LayoutBuilder(
            builder: (context, box) => Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (_) => _zoom(math.exp(-event.scrollDelta.dy * .002)),
                  );
                }
              },
              child: Stack(
                key: _canvasKey,
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _LayoutGridPainter()),
                    ),
                  ),
                  for (final entry in _draft.forOrientation(_wide).entries)
                    if (entry.value.visible)
                      Positioned(
                        left: entry.value.x * box.maxWidth,
                        top: entry.value.y * box.maxHeight,
                        width: entry.value.width * box.maxWidth,
                        height: entry.value.height * box.maxHeight,
                        child: Semantics(
                          label: '${homeModuleLabels[entry.key]}，拖动或缩放',
                          selected: _selected == entry.key,
                          child: GestureDetector(
                            key: ValueKey('edit-${entry.key}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() {
                              _selected = entry.key;
                              _placementMessage = null;
                            }),
                            onScaleStart: (details) {
                              setState(() {
                                _selected = entry.key;
                                _placementMessage = null;
                              });
                              _gestureStart = _item;
                              _focalStart = _canvasPoint(details.focalPoint);
                            },
                            onScaleUpdate: (details) {
                              final start = _gestureStart;
                              if (start == null) return;
                              final scale = details.scale.clamp(
                                math.max(.12 / start.width, .06 / start.height),
                                math.min(1 / start.width, 1 / start.height),
                              );
                              final w = start.width * scale,
                                  h = start.height * scale;
                              final delta =
                                  _canvasPoint(details.focalPoint) -
                                  _focalStart;
                              _change(
                                start.copyWith(
                                  x:
                                      start.x +
                                      delta.dx / box.maxWidth +
                                      (start.width - w) / 2,
                                  y:
                                      start.y +
                                      delta.dy / box.maxHeight +
                                      (start.height - h) / 2,
                                  width: w,
                                  height: h,
                                ),
                              );
                            },
                            onScaleEnd: (_) => _gestureStart = null,
                            child: DecoratedBox(
                              position: DecorationPosition.foreground,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _selected == entry.key
                                      ? const Color(0xFF67D8C2)
                                      : Colors.white12,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: IgnorePointer(
                                child: HomeModuleContent(
                                  id: entry.key,
                                  clock: widget.clock,
                                  settings: widget.settings,
                                  client: widget.client,
                                  preferences: _prefs,
                                  active: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF10151B),
    appBar: AppBar(
      title: const Text('布局预览'),
      leading: IconButton(
        tooltip: '取消',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _placementMessage = null;
            final defaults = HomeLayout.defaults(_wide);
            _draft = _wide
                ? _draft.copyWith(landscape: defaults)
                : _draft.copyWith(portrait: defaults);
          }),
          child: const Text('重置'),
        ),
        TextButton(
          key: const Key('save-layout'),
          onPressed: () =>
              Navigator.pop(context, HomeLayoutEditResult(_draft, _prefs)),
          child: const Text('保存'),
        ),
      ],
    ),
    body: SafeArea(
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          final delta = event.logicalKey == LogicalKeyboardKey.arrowLeft
              ? const Offset(-.02, 0)
              : event.logicalKey == LogicalKeyboardKey.arrowRight
              ? const Offset(.02, 0)
              : event.logicalKey == LogicalKeyboardKey.arrowUp
              ? const Offset(0, -.02)
              : event.logicalKey == LogicalKeyboardKey.arrowDown
              ? const Offset(0, .02)
              : null;
          if (delta == null) return KeyEventResult.ignored;
          _change(_item.copyWith(x: _item.x + delta.dx, y: _item.y + delta.dy));
          return KeyEventResult.handled;
        },
        child: Column(
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!widget.desktop) ...[
                  ChoiceChip(
                    key: const Key('edit-portrait'),
                    label: const Text('竖屏'),
                    selected: !_wide,
                    onSelected: (_) => setState(() {
                      _wide = false;
                      _gestureStart = null;
                      _placementMessage = null;
                    }),
                  ),
                  const SizedBox(width: 8),
                ],
                ChoiceChip(
                  key: const Key('edit-landscape'),
                  label: Text(widget.desktop ? '电脑 · 横屏布局' : '横屏'),
                  selected: _wide,
                  onSelected: (_) => setState(() {
                    _wide = true;
                    _gestureStart = null;
                    _placementMessage = null;
                  }),
                ),
                const SizedBox(width: 12),
                const Text('启用'),
                Switch(
                  key: const Key('layout-enabled'),
                  value: _draft.enabled,
                  onChanged: (v) =>
                      setState(() => _draft = _draft.copyWith(enabled: v)),
                ),
              ],
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (_, box) =>
                    (box.maxWidth > 760 ||
                        (box.maxWidth > 520 && box.maxHeight < 380))
                    ? Row(
                        children: [
                          Expanded(child: _preview()),
                          SizedBox(
                            width: box.maxWidth > 760 ? 300 : 230,
                            child: _controls(),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: _preview()),
                          SizedBox(
                            height: math.min(190, box.maxHeight * .45),
                            child: _controls(),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PreciseLayoutDialog extends StatefulWidget {
  const _PreciseLayoutDialog({required this.label, required this.item});
  final String label;
  final HomeModuleLayout item;
  @override
  State<_PreciseLayoutDialog> createState() => _PreciseLayoutDialogState();
}

class _PreciseLayoutDialogState extends State<_PreciseLayoutDialog> {
  late final fields =
      [widget.item.x, widget.item.y, widget.item.width, widget.item.height]
          .map((v) => TextEditingController(text: (v * 100).toStringAsFixed(1)))
          .toList();
  String? _error;
  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.label} · 精确调整'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: fields[i],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: ['横坐标 %', '纵坐标 %', '宽度 %', '高度 %'][i],
                ),
              ),
            ),
          const Text('坐标按 2% 网格吸附，保留边距与最小尺寸；重叠调整不会应用。'),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () {
          final values = fields.map((f) => double.tryParse(f.text)).toList();
          if (!values.every((v) => v != null && v.isFinite)) {
            setState(() => _error = '请输入有效数字');
            return;
          }
          Navigator.pop(
            context,
            widget.item.copyWith(
              x: values[0]! / 100,
              y: values[1]! / 100,
              width: values[2]! / 100,
              height: values[3]! / 100,
            ),
          );
        },
        child: const Text('确定'),
      ),
    ],
  );
}

class _LayoutGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x1867D8C2)
      ..strokeWidth = .5;
    // Major 10% guides keep the small preview readable; edits use a 2% grid.
    for (var i = 1; i < 10; i++) {
      canvas.drawLine(
        Offset(size.width * i / 10, 0),
        Offset(size.width * i / 10, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, size.height * i / 10),
        Offset(size.width, size.height * i / 10),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LayoutGridPainter oldDelegate) => false;
}
