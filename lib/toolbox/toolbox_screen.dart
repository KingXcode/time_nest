import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dashboard/dashboard_widgets.dart';
import 'network_tools_client.dart';

const _toolKinds = ['speed', 'latency', 'dns'];
const _toolNames = {'speed': '网速测试', 'latency': '延迟检测', 'dns': 'DNS 查询'};
const _toolIcons = {
  'speed': Icons.speed_rounded,
  'latency': Icons.monitor_heart_outlined,
  'dns': Icons.dns_outlined,
};
const _mint = Color(0xFF91D8C8);
const _warning = Color(0xFFF0C58B);

/// Browser network diagnostics. Opening the screen never starts a request.
class ToolboxScreen extends StatefulWidget {
  const ToolboxScreen({super.key, this.client});

  final NetworkToolsClient? client;

  @override
  State<ToolboxScreen> createState() => _ToolboxScreenState();
}

class _ToolboxScreenState extends State<ToolboxScreen>
    with WidgetsBindingObserver {
  NetworkToolsClient? _ownedClient;
  NetworkToolsClient get _client =>
      widget.client ?? (_ownedClient ??= createNetworkToolsClient());
  late final Map<String, dynamic> _environment = _readEnvironment();
  final _domain = TextEditingController();
  final _snapshots = <String, Map<String, dynamic>>{};
  StreamSubscription<Map<String, dynamic>>? _subscription;
  String _kind = 'speed';
  String _recordType = 'A';
  String? _activeKind;
  String? _domainError;
  bool _consent = false;
  bool _cancelling = false;
  bool _historyExpanded = false;
  bool _historyClearFailed = false;
  Map<String, dynamic>? _historySnapshot;
  Map<String, dynamic> get _history => _historySnapshot ??= _readHistory();
  int _generation = 0;

  Map<String, dynamic> _readEnvironment() {
    try {
      return _client.environment();
    } catch (_) {
      return const {};
    }
  }

  Map<String, dynamic> _readHistory() {
    try {
      return _client.history();
    } catch (_) {
      return {'available': false, 'items': <Map<String, dynamic>>[]};
    }
  }

  void _refreshHistory() => setState(() {
    _historySnapshot = _readHistory();
    _historyClearFailed = false;
  });

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('清空本机测试记录？'),
        content: const Text('将移除本浏览器保存的测速和延迟摘要。清空后无法恢复，不影响当前页面的检测结果。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    var cleared = false;
    try {
      cleared = _client.clearHistory();
    } catch (_) {
      // Storage can become unavailable after the page has opened.
    }
    setState(() {
      _historyClearFailed = !cleared;
      _historySnapshot = _readHistory();
      if (cleared) _historyExpanded = false;
    });
  }

  Map<String, dynamic> get _snapshot => _snapshots[_kind] ?? const {};
  Map<String, dynamic> get _result {
    final value = _snapshot['result'];
    return value is Map ? Map<String, dynamic>.from(value) : const {};
  }

  String get _status => _snapshot['status'] as String? ?? 'idle';
  bool get _busy => _activeKind != null || _cancelling;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_stop(message: '页面已切到后台，本次检测已取消。'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    unawaited(_subscription?.cancel());
    _domain.dispose();
    super.dispose();
  }

  Future<void> _stop({String message = '已取消。已完成的部分结果保留在此页。'}) async {
    final active = _activeKind;
    if (active == null) return;
    ++_generation;
    final subscription = _subscription;
    _subscription = null;
    setState(() {
      _activeKind = null;
      _cancelling = true;
      _snapshots[active] = {
        ...?_snapshots[active],
        'status': 'cancelled',
        'message': message,
      };
    });
    try {
      await subscription?.cancel();
    } catch (_) {
      // Generation invalidation still prevents stale updates after cancellation.
    } finally {
      if (mounted) {
        setState(() {
          _cancelling = false;
          _historySnapshot = _readHistory();
        });
      }
    }
  }

  void _select(String kind) {
    if (kind == _kind) return;
    unawaited(_stop(message: '切换工具后，本次检测已取消。'));
    setState(() {
      _kind = kind;
      _consent = false;
    });
  }

  Future<void> _start() async {
    if (!_consent || _busy) return;
    final kind = _kind;
    final name = _domain.text.trim();
    if (kind == 'dns' && name.isEmpty) {
      setState(() => _domainError = '请输入要查询的域名，例如 example.com。');
      return;
    }
    final generation = ++_generation;
    final previous = _subscription;
    _subscription = null;
    setState(() {
      _domainError = null;
      _activeKind = kind;
      _snapshots[kind] = {
        'kind': kind,
        'status': 'running',
        'stage': kind == 'dns' ? 'dns' : 'warmup',
        'progress': 0.0,
        'result': <String, dynamic>{},
      };
    });
    try {
      await previous?.cancel();
      if (!mounted || generation != _generation) return;
      _subscription = _client
          .run(
            kind,
            args: kind == 'dns'
                ? {'name': name, 'type': _recordType}
                : const {},
          )
          .listen(
            (snapshot) {
              if (!mounted || generation != _generation) return;
              setState(() {
                _snapshots[kind] = Map<String, dynamic>.from(snapshot);
                if (snapshot['status'] != 'running') {
                  _activeKind = null;
                  _historySnapshot = _readHistory();
                }
              });
            },
            onError: (Object error) {
              if (!mounted || generation != _generation) return;
              _showError(kind, error);
            },
            onDone: () {
              if (!mounted || generation != _generation) return;
              if (_activeKind == kind) {
                _showError(kind, '检测已中断，未收到完整结果。请稍后重试。');
              }
            },
          );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _showError(kind, error);
    }
  }

  void _showError(String kind, Object error) {
    setState(() {
      _activeKind = null;
      _historySnapshot = _readHistory();
      _snapshots[kind] = {
        ...?_snapshots[kind],
        'status': 'error',
        'message': error.toString().replaceFirst(RegExp(r'^Exception: '), ''),
      };
    });
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: dashboardTheme(Theme.of(context)),
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('工具箱')),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            key: const ValueKey('toolbox-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(context),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final kind in _toolKinds)
                          ChoiceChip(
                            key: ValueKey('toolbox-tab-$kind'),
                            label: Text(_toolNames[kind]!),
                            avatar: Icon(_toolIcons[kind], size: 18),
                            selected: _kind == kind,
                            showCheckmark: false,
                            onSelected: (_) => _select(kind),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide =
                            constraints.maxWidth >= 850 &&
                            MediaQuery.textScalerOf(context).scale(1) < 1.5;
                        final side = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _environmentCard(),
                            const SizedBox(height: 12),
                            _scopeCard(),
                          ],
                        );
                        if (!wide) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _toolCard(context),
                              const SizedBox(height: 16),
                              side,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: _toolCard(context)),
                            const SizedBox(width: 16),
                            Expanded(flex: 3, child: side),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _historyCard(),
                    const SizedBox(height: 18),
                    const Text(
                      '按需检测 · DNS 查询仅保留在当前页面 · 不在后台持续测速',
                      style: TextStyle(fontSize: 11, color: dashboardMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _header(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Row(
        children: [
          Icon(Icons.hub_outlined, color: _mint, size: 16),
          SizedBox(width: 8),
          Text(
            'NETWORK LAB',
            style: TextStyle(
              fontFamily: 'ShikeSans',
              fontSize: 11,
              letterSpacing: 1.8,
              color: _mint,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        '看清此刻的网络',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w600, fontSize: 25),
      ),
      const SizedBox(height: 5),
      const Text(
        '轻量测速、请求延迟与域名解析。按需开始，不自动消耗测试流量。',
        style: TextStyle(color: dashboardMuted, height: 1.5),
      ),
    ],
  );

  Widget _toolCard(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(_toolIcons[_kind], color: dashboardAccent, size: 22),
            Text(switch (_kind) {
              'speed' => '轻量网速测试',
              'latency' => 'HTTPS 请求延迟',
              _ => '公共 DNS 查询',
            }, style: Theme.of(context).textTheme.titleMedium),
            _Badge(_statusLabel, color: _statusColor),
          ],
        ),
        const SizedBox(height: 9),
        Text(switch (_kind) {
          'speed' => '连接 Cloudflare，测量本次小流量传输的下载、上传表现与请求延迟。',
          'latency' => '向本站托管节点采集 10 次 HTTPS 请求样本，另有 1 次预热，观察往返耗时与波动。',
          _ => '通过 Cloudflare 公共解析器查询域名记录，不代表设备当前使用的本地 DNS。',
        }, style: const TextStyle(color: dashboardMuted, height: 1.55)),
        const SizedBox(height: 10),
        Text(
          _kind == 'latency'
              ? '检测目标 · 本站托管节点 / GitHub Pages'
              : '服务提供方 · Cloudflare',
          style: const TextStyle(fontSize: 11, color: _mint),
        ),
        const SizedBox(height: 20),
        if (_kind == 'dns') ...[
          _dnsForm(),
          const SizedBox(height: 18),
        ] else ...[
          _metrics(context),
          const SizedBox(height: 16),
          if (_kind == 'latency') ...[
            _latencyChart(),
            const SizedBox(height: 16),
          ],
        ],
        if (_status != 'idle') ...[_runStatus(), const SizedBox(height: 16)],
        if (_kind == 'dns' &&
            (_result['answers'] is List || _result['rcode'] is num)) ...[
          _dnsResults(),
          const SizedBox(height: 16),
        ],
        _disclosure(),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const ValueKey('toolbox-consent'),
          value: _consent,
          onChanged: _busy
              ? null
              : (value) => setState(() => _consent = value ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          visualDensity: VisualDensity.standard,
          title: Text(
            _kind == 'latency'
                ? '我已了解本次会向本站托管节点（GitHub Pages）发送 10 次采样与 1 次预热的小流量 HTTPS 请求，服务方会收到访客 IP 地址。'
                : '我已了解流量消耗，以及向 Cloudflare 发送 IP 地址${_kind == 'dns' ? '和查询域名' : ''}的范围，并同意其隐私政策与网站条款。',
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
        if (_kind != 'latency')
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: [
              _link('隐私政策', 'https://www.cloudflare.com/privacypolicy/'),
              _link('网站条款', 'https://www.cloudflare.com/website-terms/'),
              _link(
                _kind == 'dns' ? 'DoH 服务说明' : '测速方法与来源',
                _kind == 'dns'
                    ? 'https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/'
                    : 'https://github.com/cloudflare/speedtest',
              ),
            ],
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: const ValueKey('toolbox-start'),
              onPressed: _consent && !_busy ? _start : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(132, 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(switch (_kind) {
                'speed' => '开始测速',
                'latency' => '开始检测',
                _ => '查询 DNS',
              }),
            ),
            if (_activeKind != null)
              OutlinedButton.icon(
                key: const ValueKey('toolbox-cancel'),
                onPressed: _stop,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(100, 44),
                ),
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('取消检测'),
              ),
            if (!_consent)
              const Text(
                '请先勾选知情同意',
                style: TextStyle(fontSize: 11, color: dashboardMuted),
              ),
            if (_cancelling)
              const Text(
                '正在停止请求…',
                style: TextStyle(fontSize: 12, color: dashboardMuted),
              ),
          ],
        ),
      ],
    ),
  );

  String get _statusLabel => switch (_status) {
    'running' => '检测中',
    'complete' => '已完成',
    'cancelled' => '已取消',
    'error' => '未完成',
    _ => '等待开始',
  };

  Color get _statusColor => switch (_status) {
    'complete' => _mint,
    'error' => _warning,
    'running' => dashboardAccent,
    _ => dashboardMuted,
  };

  Widget _metrics(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final columns = constraints.maxWidth >= 270 * scale ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
      final items = [
        if (_kind == 'speed') ...[
          _Metric(
            label: '下载速度',
            value: _number(_result['downloadMbps']),
            unit: 'Mbps',
            icon: Icons.south_rounded,
            color: dashboardAccent,
            prominent: true,
          ),
          _Metric(
            label: '上传速度',
            value: _number(_result['uploadMbps']),
            unit: 'Mbps',
            icon: Icons.north_rounded,
            color: _mint,
            prominent: true,
          ),
        ],
        _Metric(
          label: 'HTTP 往返延迟',
          value: _number(_result['latencyMs']),
          unit: 'ms',
          icon: Icons.swap_horiz_rounded,
          color: dashboardAccent,
        ),
        _Metric(
          label: '延迟抖动',
          value: _number(_result['jitterMs']),
          unit: 'ms',
          icon: Icons.multiline_chart_rounded,
          color: _mint,
        ),
      ];
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item in items) SizedBox(width: width, child: item),
        ],
      );
    },
  );

  Widget _latencyChart() {
    final raw = _result['samples'];
    final samples = raw is List
        ? raw.map((e) => e is num && e.isFinite ? e.toDouble() : null).toList()
        : <double?>[];
    final valid = samples.whereType<double>().toList();
    final attempted = _result['attempted'];
    final successful = _result['successful'];
    final summary = valid.isEmpty
        ? '尚无请求延迟样本'
        : '请求延迟曲线，${samples.length} 个样本，'
              '最小 ${_number(valid.reduce(math.min))} 毫秒，'
              '最大 ${_number(valid.reduce(math.max))} 毫秒。';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dashboardBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              const Text('请求时间线', style: TextStyle(fontSize: 12)),
              Text(
                attempted is num && successful is num
                    ? '成功 $successful / 已尝试 $attempted'
                    : '10 次 HTTPS 请求',
                style: const TextStyle(fontSize: 11, color: dashboardMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            label: summary,
            child: ExcludeSemantics(
              child: SizedBox(
                height: 88,
                child: valid.isEmpty
                    ? const Center(
                        child: Text(
                          '开始后显示真实请求样本',
                          style: TextStyle(color: dashboardMuted, fontSize: 12),
                        ),
                      )
                    : CustomPaint(painter: _LatencyPainter(samples)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '曲线中的空缺表示请求失败；不据此推算网络丢包率。',
            style: TextStyle(fontSize: 11, color: dashboardMuted),
          ),
        ],
      ),
    );
  }

  Widget _runStatus() {
    final progress = _snapshot['progress'];
    final value = progress is num && progress.isFinite
        ? progress.toDouble().clamp(0.0, 1.0)
        : null;
    final stage = switch (_snapshot['stage']) {
      'warmup' => '准备连接',
      'latency' => '采集延迟样本',
      'download' => '测量下载',
      'upload' => '测量上传',
      'dns' => '查询解析记录',
      'done' => '检测结束',
      _ => '正在检测',
    };
    final warnings = _result['warnings'];
    final timestamp = _result['completedAt'] ?? _result['startedAt'];
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_status == 'running') ...[
            Text(stage, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 9),
            LinearProgressIndicator(
              value: value,
              minHeight: 4,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: dashboardBorder,
              semanticsLabel: stage,
            ),
            const SizedBox(height: 9),
          ],
          if (_snapshot['message'] is String)
            Text(
              _snapshot['message'] as String,
              key: const ValueKey('toolbox-status-message'),
              style: TextStyle(color: _statusColor, fontSize: 12, height: 1.5),
            ),
          if (warnings is List)
            for (final warning in warnings.whereType<String>())
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  warning,
                  style: const TextStyle(color: _warning, fontSize: 12),
                ),
              ),
          if (_kind == 'speed' &&
              (_result['downloadBytes'] is num ||
                  _result['uploadBytes'] is num))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '已传输测试数据：下载 ${_bytes(_result['downloadBytes'])} · '
                '上传 ${_bytes(_result['uploadBytes'])}（不含协议开销）',
                style: const TextStyle(fontSize: 11, color: dashboardMuted),
              ),
            ),
          if (timestamp is String && DateTime.tryParse(timestamp) != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_result['completedAt'] == null ? '开始时间' : '检测时间'}：'
                '${_formatTime(DateTime.parse(timestamp))}',
                style: const TextStyle(fontSize: 11, color: dashboardMuted),
              ),
            ),
          if (_status == 'complete' && _kind != 'dns')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '仅代表当前浏览器到本次目标服务的连接表现。',
                style: TextStyle(fontSize: 11, color: dashboardMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dnsForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const ValueKey('toolbox-domain'),
        controller: _domain,
        enabled: !_busy,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _start(),
        onChanged: (_) {
          if (_domainError != null) setState(() => _domainError = null);
        },
        decoration: InputDecoration(
          labelText: '域名',
          hintText: '例如 example.com',
          errorText: _domainError,
          errorMaxLines: 3,
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: const ValueKey('toolbox-record-type'),
        initialValue: _recordType,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '记录类型'),
        items: [
          for (final type in ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS'])
            DropdownMenuItem(value: type, child: Text(type)),
        ],
        onChanged: _busy
            ? null
            : (value) => setState(() => _recordType = value ?? 'A'),
      ),
    ],
  );

  Widget _dnsResults() {
    final rawAnswers = _result['answers'];
    final answers = rawAnswers is List
        ? rawAnswers.whereType<Map>().toList()
        : <Map>[];
    final rcode = _result['rcode'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Text('解析结果 · ${answers.length} 条'),
            if (rcode is num)
              _Badge(switch (rcode) {
                0 => 'NOERROR',
                3 => 'NXDOMAIN',
                2 => 'SERVFAIL',
                5 => 'REFUSED',
                _ => 'RCODE $rcode',
              }, color: rcode == 0 ? _mint : _warning),
            if (_result['dnssec'] is bool)
              _Badge(
                _result['dnssec'] == true ? 'DNSSEC 已验证' : '无 DNSSEC 验证标记',
                color: dashboardMuted,
              ),
          ],
        ),
        if (_result['name'] is String) ...[
          const SizedBox(height: 10),
          SelectableText(
            '${_result['name']} · ${_result['type'] ?? ''}',
            style: const TextStyle(fontSize: 12, color: dashboardMuted),
          ),
        ],
        if (answers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(switch (rcode) {
              0 => '本次响应没有此类型的记录。',
              3 => '该域名不存在（NXDOMAIN）。',
              2 => '公共解析器处理失败（SERVFAIL），请稍后重试。',
              5 => '公共解析器拒绝本次查询（REFUSED）。',
              null => '未收到可确认的解析结果。',
              _ => '公共解析器返回错误（RCODE $rcode），未获得可用结果。',
            }, style: const TextStyle(color: dashboardMuted, height: 1.5)),
          ),
        for (var index = 0; index < answers.length; index++)
          Container(
            key: ValueKey('toolbox-dns-answer-$index'),
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dashboardBackground,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: dashboardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 5,
                  children: [
                    _Badge('${answers[index]['type'] ?? '未知'}', color: _mint),
                    Text(
                      answers[index]['ttl'] is num
                          ? 'TTL ${answers[index]['ttl']} 秒'
                          : 'TTL 未提供',
                      style: const TextStyle(
                        fontSize: 11,
                        color: dashboardMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  '${answers[index]['name'] ?? ''}',
                  style: const TextStyle(fontSize: 11, color: dashboardMuted),
                ),
                const SizedBox(height: 5),
                SelectableText(
                  '${answers[index]['data'] ?? '未提供记录内容'}',
                  style: const TextStyle(fontSize: 13, height: 1.6),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _disclosure() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: dashboardAccent.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: dashboardAccent.withValues(alpha: .18)),
    ),
    child: Text(
      switch (_kind) {
        'speed' =>
          '开始前请知悉：本轮应用测试数据最多 7 MiB，另有 HTTPS 协议开销，'
              '可能计入流量费用。仅传输生成的测试数据，不上传个人文件。'
              'Cloudflare 会收到访客 IP 地址。支持中途取消；切换工具、离开页面或切到后台会停止检测。'
              '轻量模式不适合认证宽带峰值或运营商标称带宽。',
        'latency' =>
          '开始前请知悉：向本站托管节点（GitHub Pages）发送 10 次采样与 1 次预热的 HTTPS 请求，'
              '每次响应约 27 字节，另有协议开销；服务方会收到访客 IP 地址。这里测量的是 HTTP 请求往返时间，'
              '不是 ICMP Ping，也不是网络丢包率检测。切换工具、离开页面或切到后台会取消。',
        _ =>
          '开始前请知悉：查询域名和访客 IP 地址将发送给 Cloudflare 公共 DNS。'
              '请勿输入私密或公司内网域名。结果来自公共解析器，不是本机 DNS 配置或 DNS 泄漏检测。'
              '仅查询，不修改任何网络设置。',
      },
      style: const TextStyle(fontSize: 12, color: dashboardMuted, height: 1.65),
    ),
  );

  Widget _environmentCard() {
    final online = _environment['online'];
    final secure = _environment['secure'];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('浏览器连接信息', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 13),
          _fact(
            '连接状态',
            online == true
                ? '在线'
                : online == false
                ? '离线'
                : '未提供',
          ),
          _fact(
            '安全上下文',
            secure == true
                ? '是'
                : secure == false
                ? '否'
                : '未提供',
          ),
          _fact('有效连接类型', _environment['effectiveType']?.toString() ?? '未提供'),
          _fact(
            '估计下行',
            _environment['estimatedDownlinkMbps'] is num
                ? '${_number(_environment['estimatedDownlinkMbps'])} Mbps'
                : '未提供',
          ),
          _fact(
            '估计往返延迟',
            _environment['estimatedRttMs'] is num
                ? '${_number(_environment['estimatedRttMs'])} ms'
                : '未提供',
          ),
          _fact(
            '节省流量模式',
            _environment['saveData'] == true
                ? '已启用'
                : _environment['saveData'] == false
                ? '未启用'
                : '未提供',
          ),
          const Divider(height: 24),
          const Text(
            '以上是打开页面时的浏览器报告与估计，不是测速结果。浏览器未开放的字段显示“未提供”。',
            style: TextStyle(fontSize: 11, color: dashboardMuted, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _fact(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 4,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: dashboardMuted),
        ),
        Text(value, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );

  Widget _scopeCard() => const _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.info_outline_rounded, color: _mint, size: 21),
        SizedBox(height: 10),
        Text('网页能测到什么？', style: TextStyle(fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Text(
          '这里关注当前浏览器到公共服务的连接表现。VPN、代理、设备负载与服务端距离都会影响结果。',
          style: TextStyle(fontSize: 12, color: dashboardMuted, height: 1.6),
        ),
        SizedBox(height: 10),
        Text(
          '受浏览器权限限制，不读取 Wi-Fi 名称、运营商、信号强度或本地 IP，也不提供原生 ICMP、路由追踪和局域网扫描。',
          style: TextStyle(fontSize: 12, color: dashboardMuted, height: 1.6),
        ),
      ],
    ),
  );

  Widget _historyCard() {
    final raw = _history['items'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .where(
                (item) => item['kind'] == 'speed' || item['kind'] == 'latency',
              )
              .take(20)
              .toList()
        : <Map>[];
    final visible = _historyExpanded ? items : items.take(5).toList();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '本地测试记录',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    key: const ValueKey('toolbox-refresh-history'),
                    onPressed: _refreshHistory,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('刷新记录'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('toolbox-clear-history'),
                    onPressed: items.isEmpty || _busy ? null : _clearHistory,
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('清空记录'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            '仅在本浏览器保存最近 20 次测速与延迟摘要，不保存 IP、DNS 查询域名或记录内容。',
            style: TextStyle(color: dashboardMuted, fontSize: 11, height: 1.6),
          ),
          if (_history['available'] != true || _historyClearFailed) ...[
            const SizedBox(height: 10),
            Text(
              _historyClearFailed
                  ? '无法清空本地记录，请检查浏览器存储权限后重试。'
                  : '浏览器存储不可用。工具仍可使用，但测试记录可能无法保存。',
              style: const TextStyle(
                color: _warning,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
          if (items.isEmpty) ...[
            const SizedBox(height: 15),
            const Text(
              '暂无本地测试记录',
              style: TextStyle(color: dashboardMuted, fontSize: 12),
            ),
          ],
          for (var index = 0; index < visible.length; index++) ...[
            const Divider(height: 24),
            _historyItem(visible[index], index),
          ],
          if (items.length > 5) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() => _historyExpanded = !_historyExpanded),
                child: Text(
                  _historyExpanded ? '收起记录' : '展开全部 ${items.length} 条',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _historyItem(Map item, int index) {
    final complete = item['status'] == 'complete';
    final timestamp = item['completedAt'];
    final date = timestamp is String ? DateTime.tryParse(timestamp) : null;
    final speed = item['kind'] == 'speed';
    final status = complete
        ? '已完成'
        : item['status'] == 'cancelled'
        ? '已取消'
        : '未完成';
    return Column(
      key: ValueKey('toolbox-history-$index'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 9,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(speed ? '网速测试' : '延迟检测', style: const TextStyle(fontSize: 12)),
            _Badge(status, color: complete ? _mint : dashboardMuted),
            Text(
              item['provider'] is String
                  ? item['provider'] as String
                  : (speed ? 'Cloudflare' : '本站 HTTPS'),
              style: const TextStyle(fontSize: 11, color: dashboardMuted),
            ),
            Text(
              date == null ? '时间未提供' : _formatTime(date),
              style: const TextStyle(fontSize: 11, color: dashboardMuted),
            ),
          ],
        ),
        if (complete) ...[
          const SizedBox(height: 9),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              if (speed) ...[
                Text(
                  '下载 ${_number(item['downloadMbps'])} Mbps',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  '上传 ${_number(item['uploadMbps'])} Mbps',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              Text(
                'HTTP 延迟 ${_number(item['latencyMs'])} ms',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                '抖动 ${_number(item['jitterMs'])} ms',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _link(String label, String url) => TextButton(
    onPressed: () => _client.openUrl(url),
    child: Text('$label ↗', style: const TextStyle(fontSize: 11)),
  );
}

String _number(dynamic value) {
  if (value is! num || !value.isFinite || value < 0) return '—';
  return value.toStringAsFixed(value >= 100 ? 0 : 1);
}

String _bytes(dynamic value) {
  if (value is! num || !value.isFinite || value < 0) return '未提供';
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(2)} MiB';
  }
  return '${(value / 1024).toStringAsFixed(1)} KiB';
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}（本地时间）';
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: dashboardSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: dashboardBorder),
    ),
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: .2)),
    ),
    child: Text(text, style: TextStyle(fontSize: 10, color: color)),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    this.prominent = false,
  });
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: dashboardBackground,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: dashboardBorder.withValues(alpha: .6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11, color: dashboardMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 7,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: value == '—' ? 'ShikeSans' : 'ClockDigits',
                fontFamilyFallback: const ['ShikeSans'],
                fontSize: prominent ? 30 : 23,
                color: prominent ? color : null,
                height: 1.1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                unit,
                style: const TextStyle(fontSize: 11, color: dashboardMuted),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _LatencyPainter extends CustomPainter {
  _LatencyPainter(this.samples);
  final List<double?> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = dashboardBorder
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = 8 + (size.height - 16) * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final valid = samples.whereType<double>().toList();
    if (valid.isEmpty) return;
    final min = valid.reduce(math.min);
    final max = valid.reduce(math.max);
    final range = math.max(max - min, 10.0);
    final line = Paint()
      ..color = _mint
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = _mint;
    Offset? previous;
    for (var i = 0; i < samples.length; i++) {
      final value = samples[i];
      if (value == null) {
        previous = null;
        continue;
      }
      final x = 4 + (size.width - 8) * i / math.max(9, samples.length - 1);
      final y = size.height - 12 - ((value - min) / range) * (size.height - 24);
      final point = Offset(x, y);
      if (previous != null) canvas.drawLine(previous, point, line);
      canvas.drawCircle(point, 3, dot);
      previous = point;
    }
  }

  @override
  bool shouldRepaint(covariant _LatencyPainter oldDelegate) =>
      oldDelegate.samples != samples;
}
