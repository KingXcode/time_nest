import 'dart:convert';

import 'package:flutter/material.dart';

import 'dashboard_client.dart';

const dashboardAccent = Color(0xFF85B6FF);
const dashboardMuted = Color(0xFF9BACBF);
const dashboardBackground = Color(0xFF101824);
const dashboardSurface = Color(0xFF182332);
const dashboardBorder = Color(0xFF2C3B4E);

ThemeData dashboardTheme(ThemeData base) {
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(7));
  final button = TextButton.styleFrom(
    minimumSize: const Size(0, 32),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: shape,
    textStyle: const TextStyle(fontFamily: 'ShikeSans', fontSize: 12),
  );
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: dashboardAccent,
      onPrimary: dashboardBackground,
      surface: dashboardSurface,
      onSurface: const Color(0xFFE7EEF8),
      outline: dashboardBorder,
    ),
    scaffoldBackgroundColor: dashboardBackground,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textTheme: base.textTheme
        .apply(fontFamily: 'ShikeSans')
        .copyWith(
          bodyMedium: const TextStyle(
            fontFamily: 'ShikeSans',
            fontSize: 13,
            height: 1.4,
            color: Color(0xFFE7EEF8),
          ),
          bodySmall: const TextStyle(
            fontFamily: 'ShikeSans',
            fontSize: 11,
            height: 1.4,
            color: dashboardMuted,
          ),
          titleMedium: const TextStyle(
            fontFamily: 'ShikeSans',
            fontSize: 15,
            color: Color(0xFFE7EEF8),
            fontWeight: FontWeight.w600,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: dashboardBackground,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 46,
      titleTextStyle: TextStyle(
        fontFamily: 'ShikeSans',
        fontSize: 16,
        color: Color(0xFFE7EEF8),
        fontWeight: FontWeight.w600,
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: button),
    outlinedButtonTheme: OutlinedButtonThemeData(style: button),
    filledButtonTheme: FilledButtonThemeData(style: button),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(32, 32),
        padding: const EdgeInsets.all(6),
        iconSize: 17,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: shape,
      side: const BorderSide(color: dashboardBorder),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      labelPadding: const EdgeInsets.symmetric(horizontal: 5),
      labelStyle: const TextStyle(
        fontFamily: 'ShikeSans',
        fontSize: 12,
        color: Color(0xFFE7EEF8),
      ),
      selectedColor: const Color(0xFF2C4364),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: dashboardBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: dashboardBorder),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    ),
    dividerTheme: const DividerThemeData(
      color: dashboardBorder,
      space: 16,
      thickness: 1,
    ),
  );
}

class DashboardColumns extends StatelessWidget {
  const DashboardColumns({
    super.key,
    required this.children,
    this.minWidth = 450,
  });
  final List<Widget> children;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns =
          (box.maxWidth /
                  (minWidth * MediaQuery.textScalerOf(context).scale(1)))
              .floor()
              .clamp(1, 2);
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children)
            SizedBox(
              width: (box.maxWidth - (columns - 1) * 12) / columns,
              child: child,
            ),
        ],
      );
    },
  );
}

/// One asynchronous result at a time. Request generations keep fast input
/// changes from letting an older network response replace the current result.
class ApiSection extends StatefulWidget {
  const ApiSection({
    super.key,
    required this.client,
    required this.module,
    required this.args,
    required this.builder,
    this.sourceLabel,
    this.sourceUrl,
    this.compact = false,
  });

  final DashboardClient client;
  final String module;
  final Map<String, dynamic> args;
  final Widget Function(BuildContext, DashboardData) builder;
  final String? sourceLabel;
  final String? sourceUrl;
  final bool compact;

  @override
  State<ApiSection> createState() => _ApiSectionState();
}

class _ApiSectionState extends State<ApiSection> {
  DashboardData? _result;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ApiSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module != widget.module ||
        oldWidget.client != widget.client ||
        jsonEncode(oldWidget.args) != jsonEncode(widget.args)) {
      _result = null;
      _error = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    final generation = ++_generation;
    if (!_loading) setState(() => _loading = true);
    try {
      final result = await widget.client.load(
        widget.module,
        widget.args,
        refresh: refresh,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _result = result;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error.toString().replaceFirst(RegExp(r'^Exception: '), '');
        _loading = false;
      });
    }
  }

  String _updated(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loading && result == null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: widget.compact ? 10 : 20),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Flexible(
                  child: Text(
                    '正在获取最新数据…',
                    style: TextStyle(color: dashboardMuted),
                  ),
                ),
              ],
            ),
          ),
        if (result != null) widget.builder(context, result),
        if (_error != null || result?.warning != null || result?.stale == true)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF242A2A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  [
                    if (result?.stale == true) '当前为上次保存的数据，可能已过时。',
                    ?_error,
                    if (result?.warning != null) result!.warning!,
                  ].join(' '),
                  style: const TextStyle(color: Color(0xFFD1D7D5), height: 1.5),
                ),
              ),
            ),
          ),
        SizedBox(height: widget.compact ? 3 : 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.sourceLabel != null)
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: widget.sourceUrl == null
                    ? null
                    : () => widget.client.openUrl(widget.sourceUrl!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${widget.sourceLabel} ↗',
                    style: const TextStyle(color: dashboardMuted, fontSize: 11),
                  ),
                ),
              ),
            if (result != null)
              Text(
                '${result.stale
                    ? '旧数据'
                    : result.cached
                    ? '缓存'
                    : '更新'} ${_updated(result.fetchedAt)}',
                style: const TextStyle(color: dashboardMuted, fontSize: 11),
              ),
            TextButton.icon(
              onPressed: _loading ? null : () => _load(refresh: true),
              icon: Icon(
                _loading ? Icons.hourglass_top_rounded : Icons.refresh_rounded,
                size: 15,
              ),
              label: Text(
                _loading
                    ? '更新中'
                    : _error == null
                    ? '刷新'
                    : '重试',
              ),
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 12),
                minimumSize: Size(
                  widget.compact ? 0 : 54,
                  widget.compact ? 26 : 32,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
