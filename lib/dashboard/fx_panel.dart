import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dashboard_client.dart';
import 'dashboard_widgets.dart';

const _fxAccent = Color(0xFF67D8C2);
const _currencies = [
  'CNY',
  'USD',
  'EUR',
  'GBP',
  'JPY',
  'HKD',
  'TWD',
  'SGD',
  'AUD',
  'CAD',
  'KRW',
  'CHF',
];

class FxPanel extends StatefulWidget {
  const FxPanel({
    super.key,
    required this.client,
    required this.base,
    required this.quote,
    required this.amount,
    required this.onChanged,
  });

  final DashboardClient client;
  final String base;
  final String quote;
  final double amount;
  final void Function(String base, String quote, double amount) onChanged;

  @override
  State<FxPanel> createState() => _FxPanelState();
}

class _FxPanelState extends State<FxPanel> {
  late final TextEditingController _amountController;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _plainAmount(widget.amount),
    );
  }

  @override
  void didUpdateWidget(covariant FxPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.amount != widget.amount &&
        double.tryParse(_amountController.text) != widget.amount) {
      _amountController.text = _plainAmount(widget.amount);
      _amountError = null;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  String get _base => _currencies.contains(widget.base) ? widget.base : 'USD';
  String get _quote =>
      _currencies.contains(widget.quote) ? widget.quote : 'CNY';

  void _amountChanged(String input) {
    final amount = double.tryParse(input);
    if (amount == null || !amount.isFinite || amount < 0 || amount > 1e9) {
      setState(() => _amountError = '请输入 0 至 10 亿之间的有效金额。');
      return;
    }
    setState(() => _amountError = null);
    widget.onChanged(_base, _quote, amount);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ApiSection(
        client: widget.client,
        module: 'fx',
        args: {'base': _base, 'quote': _quote},
        sourceLabel: 'Frankfurter · 每日参考汇率',
        sourceUrl: 'https://frankfurter.dev',
        builder: (context, result) {
          final rawRate = result.data['rate'];
          final rate = rawRate is num ? rawRate.toDouble() : double.nan;
          if (!rate.isFinite || rate <= 0) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('此货币对暂未提供有效汇率，请尝试其他货币。'),
            );
          }
          final rawHistory = result.data['history'];
          final history = <_RatePoint>[];
          if (rawHistory is List) {
            for (final entry in rawHistory.whereType<Map>()) {
              final value = entry['rate'];
              final date = entry['date'];
              if (value is num &&
                  value.isFinite &&
                  value > 0 &&
                  date is String) {
                history.add(_RatePoint(date, value.toDouble()));
              }
            }
          }
          history.sort((a, b) => a.date.compareTo(b.date));
          final points = history.length > 31
              ? history.sublist(history.length - 31)
              : history;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${_money(widget.amount, decimals: 2)} $_base 约合',
                style: const TextStyle(color: Color(0xFFA8B5BB), fontSize: 13),
              ),
              const SizedBox(height: 8),
              if (_amountError == null)
                Semantics(
                  label: '换算结果 ${_money(widget.amount * rate)} $_quote',
                  child: ExcludeSemantics(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_money(widget.amount * rate)} $_quote',
                        style: const TextStyle(
                          color: _fxAccent,
                          fontSize: 34,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
              else
                const Text(
                  '请输入有效金额',
                  style: TextStyle(color: Color(0xFFA8B5BB), fontSize: 24),
                ),
              const SizedBox(height: 10),
              Text(
                '1 $_base = ${_rateNumber(rate)} $_quote',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                '汇率日期 ${result.data['date'] ?? '未提供'}',
                style: const TextStyle(color: Color(0xFFA8B5BB), fontSize: 12),
              ),
              const SizedBox(height: 18),
              if (points.length >= 2)
                _RateHistory(points: points)
              else
                const Text(
                  '最近 30 天走势暂无足够数据。',
                  style: TextStyle(color: Color(0xFFA8B5BB), fontSize: 12),
                ),
              const SizedBox(height: 10),
            ],
          );
        },
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _amountController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          TextInputFormatter.withFunction((oldValue, newValue) {
            return RegExp(r'^\d*\.?\d*$').hasMatch(newValue.text)
                ? newValue
                : oldValue;
          }),
        ],
        maxLength: 24,
        onChanged: _amountChanged,
        decoration: InputDecoration(
          labelText: '换算金额',
          border: const OutlineInputBorder(),
          counterText: '',
          errorText: _amountError,
          errorMaxLines: 2,
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: _currencyMenu('从', _base, (v) {
              widget.onChanged(v, _quote, widget.amount);
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: IconButton(
              tooltip: '交换货币',
              onPressed: () => widget.onChanged(_quote, _base, widget.amount),
              icon: const Icon(Icons.swap_horiz_rounded, color: _fxAccent),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ),
          Expanded(
            child: _currencyMenu('至', _quote, (v) {
              widget.onChanged(_base, v, widget.amount);
            }),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        '每日参考数据，节假日可能沿用上一工作日汇率。非实时交易价，也不含银行或支付平台费用。',
        style: TextStyle(color: Color(0xFFA8B5BB), fontSize: 12, height: 1.5),
      ),
    ],
  );

  Widget _currencyMenu(
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label-$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    ),
    items: [
      for (final currency in _currencies)
        DropdownMenuItem(value: currency, child: Text(currency)),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}

class _RatePoint {
  const _RatePoint(this.date, this.rate);
  final String date;
  final double rate;
}

class _RateHistory extends StatelessWidget {
  const _RateHistory({required this.points});
  final List<_RatePoint> points;

  @override
  Widget build(BuildContext context) {
    final values = points.map((point) => point.rate).toList();
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final change = (values.last / values.first - 1) * 100;
    final changeText = '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          children: [
            const Text(
              '近 30 天',
              style: TextStyle(fontSize: 12, color: Color(0xFFA8B5BB)),
            ),
            Text(
              '$changeText · 相对首个数据点',
              style: const TextStyle(fontSize: 12, color: _fxAccent),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          label:
              '近 30 天汇率走势，最低 ${_rateNumber(low)}，最高 ${_rateNumber(high)}，变化 $changeText',
          image: true,
          child: SizedBox(
            height: 82,
            child: CustomPaint(painter: _RateSparkline(values)),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(
              '${points.first.date} → ${points.last.date}',
              style: const TextStyle(fontSize: 11, color: Color(0xFFA8B5BB)),
            ),
            Text(
              '${_rateNumber(low)} — ${_rateNumber(high)}',
              style: const TextStyle(fontSize: 11, color: Color(0xFFA8B5BB)),
            ),
          ],
        ),
      ],
    );
  }
}

class _RateSparkline extends CustomPainter {
  const _RateSparkline(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final span = high - low;
    final inset = 4.0;
    final graphHeight = math.max(0.0, size.height - inset * 2);
    final graphWidth = math.max(0.0, size.width - inset * 2);
    final path = Path();
    Offset point(int i) => Offset(
      inset + graphWidth * i / (values.length - 1),
      span == 0
          ? size.height / 2
          : inset + graphHeight * (1 - (values[i] - low) / span),
    );
    for (var i = 0; i < values.length; i++) {
      final p = point(i);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width - inset, size.height)
      ..lineTo(inset, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x3867D8C2), Color(0x0067D8C2)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _fxAccent
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(point(values.length - 1), 3, Paint()..color = _fxAccent);
  }

  @override
  bool shouldRepaint(covariant _RateSparkline oldDelegate) {
    if (oldDelegate.values.length != values.length) return true;
    for (var i = 0; i < values.length; i++) {
      if (oldDelegate.values[i] != values[i]) return true;
    }
    return false;
  }
}

String _plainAmount(double amount) =>
    amount.isFinite ? amount.toString().replaceFirst(RegExp(r'\.0$'), '') : '1';

String _money(double amount, {int decimals = 2}) {
  if (!amount.isFinite) return '—';
  final parts = amount.toStringAsFixed(decimals).split('.');
  parts[0] = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return parts.join('.');
}

String _rateNumber(double rate) =>
    rate.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
