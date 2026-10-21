import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'crypto_market.dart';
import 'dashboard_client.dart';
import 'dashboard_widgets.dart';

/// Selection is local to this route until a complete, available pair is chosen.
/// The root navigator keeps the mobile sheet above the dashboard's own header.
Future<CryptoPair?> showCryptoPairPicker(
  BuildContext context, {
  required DashboardClient client,
  required CryptoPair current,
  required bool chooseQuote,
}) => showDialog<CryptoPair>(
  context: context,
  useRootNavigator: true,
  useSafeArea: false,
  barrierColor: Colors.black.withValues(alpha: .64),
  builder: (context) => Theme(
    data: dashboardTheme(Theme.of(context)),
    child: _CryptoPairPicker(
      client: client,
      current: current,
      chooseQuote: chooseQuote,
    ),
  ),
);

class _CryptoPairPicker extends StatefulWidget {
  const _CryptoPairPicker({
    required this.client,
    required this.current,
    required this.chooseQuote,
  });

  final DashboardClient client;
  final CryptoPair current;
  final bool chooseQuote;

  @override
  State<_CryptoPairPicker> createState() => _CryptoPairPickerState();
}

class _CryptoPairPickerState extends State<_CryptoPairPicker> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  List<CryptoPair>? _pairs;
  late bool _showQuotes = widget.chooseQuote;
  late String _quote = widget.current.quoteAsset;
  bool _loading = true;
  bool _stale = false;
  String? _error, _warning;

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _searchChanged() {
    setState(() {});
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _load({bool refresh = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await widget.client.load(
        'cryptoPairs',
        const {},
        refresh: refresh,
      );
      final pairs = readCryptoPairs(response.data)
        ..sort((a, b) {
          if (a.symbol == b.symbol) return 0;
          if (a.symbol == widget.current.symbol) return -1;
          if (b.symbol == widget.current.symbol) return 1;
          return a.baseAsset.compareTo(b.baseAsset);
        });
      if (!mounted) return;
      registerCryptoPairs(pairs);
      setState(() {
        _pairs = pairs;
        _stale = response.stale;
        _warning = response.warning;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is DashboardException
            ? error.message
            : '暂时无法加载交易对列表，请重试。';
      });
    }
  }

  void _chooseQuote(String quote) {
    final matching = _pairs!.where(
      (pair) =>
          pair.quoteAsset == quote &&
          pair.baseAsset == widget.current.baseAsset,
    );
    if (matching.isNotEmpty) {
      Navigator.of(context).pop(matching.first);
      return;
    }
    _search.clear();
    setState(() {
      _quote = quote;
      _showQuotes = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _backToQuotes() {
    _search.clear();
    setState(() {
      _quote = widget.current.quoteAsset;
      _showQuotes = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  String _normalized(String text) =>
      text.toUpperCase().replaceAll(RegExp(r'[\s/_-]'), '');

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).shortestSide < 600;
    final content = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: SizedBox(
        key: const Key('crypto-pair-picker'),
        width: mobile ? double.infinity : 900,
        height: mobile ? double.infinity : 760,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => box.maxHeight < 240
                ? _list(headerInList: true)
                : Column(
                    children: [
                      _header(),
                      const Divider(height: 1),
                      Expanded(child: _list()),
                    ],
                  ),
          ),
        ),
      ),
    );
    return mobile
        ? Dialog.fullscreen(backgroundColor: dashboardSurface, child: content)
        : Dialog(
            backgroundColor: dashboardSurface,
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(24),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: dashboardBorder),
            ),
            child: content,
          );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
    child: Row(
      children: [
        if (widget.chooseQuote && !_showQuotes)
          IconButton(
            key: const Key('crypto-pair-back'),
            tooltip: '返回计价币',
            onPressed: _backToQuotes,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              _showQuotes ? '选择计价币' : '选择币种',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        IconButton(
          key: const Key('crypto-pair-refresh'),
          tooltip: '刷新交易对列表',
          onPressed: _loading ? null : () => _load(refresh: true),
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          icon: _loading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 22),
        ),
        IconButton(
          key: const Key('crypto-pair-close'),
          tooltip: '关闭',
          onPressed: () => Navigator.of(context).pop(),
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          icon: const Icon(Icons.close_rounded, size: 22),
        ),
      ],
    ),
  );

  Widget _list({bool headerInList = false}) {
    final query = _normalized(_search.text);
    final pairs = (_pairs ?? const <CryptoPair>[])
        .where(
          (pair) =>
              pair.quoteAsset == _quote &&
              (query.isEmpty ||
                  _normalized(
                    '${pair.symbol} ${pair.baseAsset} ${pair.name} '
                    '${pair.baseAsset}/${pair.quoteAsset}',
                  ).contains(query)),
        )
        .toList();
    final counts = <String, int>{};
    for (final pair in _pairs ?? const <CryptoPair>[]) {
      counts.update(pair.quoteAsset, (n) => n + 1, ifAbsent: () => 1);
    }
    final quotes =
        counts.keys
            .where(
              (quote) => query.isEmpty || _normalized(quote).contains(query),
            )
            .toList()
          ..sort((a, b) {
            if (a == b) return 0;
            if (a == widget.current.quoteAsset) return -1;
            if (b == widget.current.quoteAsset) return 1;
            return a.compareTo(b);
          });
    final itemCount = _showQuotes ? quotes.length : pairs.length;
    return CustomScrollView(
      key: const Key('crypto-pair-list'),
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (headerInList) ...[
          SliverToBoxAdapter(child: _header()),
          const SliverToBoxAdapter(child: Divider(height: 1)),
        ],
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _showQuotes
                      ? '当前交易对 ${widget.current.baseAsset} / '
                            '${widget.current.quoteAsset}'
                      : '计价币 $_quote',
                  style: const TextStyle(
                    color: dashboardAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _showQuotes
                      ? '切换计价币时优先保留 ${widget.current.baseAsset}；'
                            '没有对应交易对时，再选择币种。'
                      : widget.chooseQuote
                      ? '${widget.current.baseAsset} 暂无 $_quote 交易对，'
                            '请在下方选择币种。'
                      : '仅显示以 $_quote 计价的可用交易对。',
                  style: const TextStyle(color: dashboardMuted, fontSize: 13),
                ),
                const SizedBox(height: 18),
                TextField(
                  key: const Key('crypto-pair-search'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: _showQuotes ? '搜索计价币' : '搜索币种、名称或交易对',
                    prefixIcon: const Icon(Icons.search_rounded, size: 22),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            onPressed: _search.clear,
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                  ),
                ),
                if (_pairs != null &&
                    (_stale || _error != null || _warning != null)) ...[
                  const SizedBox(height: 12),
                  _notice(
                    _error != null
                        ? '更新失败，仍显示此前的交易对列表。$_error'
                        : _warning ?? '正在使用缓存的交易对列表，可能不是最新。',
                  ),
                ],
                if (_pairs != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _showQuotes ? '$itemCount 种计价币' : '$itemCount 个交易对',
                    style: const TextStyle(color: dashboardMuted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_pairs == null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _loading
                  ? const Center(child: Text('正在加载交易对…'))
                  : _empty(
                      Icons.cloud_off_rounded,
                      '交易对列表暂不可用',
                      _error ?? '请刷新后重试。',
                      retry: true,
                    ),
            ),
          )
        else if (itemCount == 0)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _empty(
                Icons.search_off_rounded,
                query.isEmpty ? '暂无可用交易对' : '没有匹配的结果',
                query.isEmpty ? '当前列表中没有 $_quote 交易对，可刷新后重试。' : '试试其他代码或名称。',
                retry: query.isEmpty,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            sliver: SliverList.builder(
              itemCount: itemCount,
              itemBuilder: (context, index) => _showQuotes
                  ? _quoteRow(quotes[index], counts[quotes[index]]!)
                  : _pairRow(pairs[index]),
            ),
          ),
      ],
    );
  }

  Widget _notice(String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF3A3020),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Color(0xFFFFD38B), fontSize: 12),
    ),
  );

  Widget _empty(
    IconData icon,
    String title,
    String detail, {
    bool retry = false,
  }) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 32, color: dashboardMuted),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: dashboardMuted, fontSize: 13),
        ),
        if (retry) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            key: const Key('crypto-pair-retry'),
            onPressed: _loading ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      ],
    ),
  );

  Widget _pairRow(CryptoPair pair) => _row(
    key: ValueKey('crypto-select-${pair.symbol}'),
    title: pair.baseAsset,
    detail: pair.name == pair.baseAsset
        ? '${pair.baseAsset} / ${pair.quoteAsset}'
        : '${pair.name} · ${pair.baseAsset} / ${pair.quoteAsset}',
    selected: pair.symbol == widget.current.symbol,
    onTap: () => Navigator.of(context).pop(pair),
  );

  Widget _quoteRow(String quote, int count) => _row(
    key: ValueKey('crypto-quote-$quote'),
    title: quote,
    detail: '$count 个可用交易对',
    selected: quote == widget.current.quoteAsset,
    onTap: () => _chooseQuote(quote),
  );

  Widget _row({
    required Key key,
    required String title,
    required String detail,
    required bool selected,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? const Color(0xFF253B56) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: const TextStyle(
                          color: dashboardMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.chevron_right,
                  size: 22,
                  color: selected ? dashboardAccent : dashboardMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
