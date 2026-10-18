import 'dart:convert';

import 'package:flutter/material.dart';

import 'dashboard_client.dart';

const dashboardAccent = Color(0xFF67D8C2);
const dashboardMuted = Color(0xFFA0AAA9);

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
  });

  final DashboardClient client;
  final String module;
  final Map<String, dynamic> args;
  final Widget Function(BuildContext, DashboardData) builder;
  final String? sourceLabel;
  final String? sourceUrl;

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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Row(
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
        const SizedBox(height: 12),
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
                minimumSize: const Size(64, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
