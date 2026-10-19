import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'crypto_market.dart';
import 'dashboard_widgets.dart';

const cryptoUp = Color(0xFF67D8AB);
const cryptoDown = Color(0xFFFF8A92);

class CryptoChart extends StatefulWidget {
  const CryptoChart({
    super.key,
    required this.candles,
    required this.asset,
    required this.fetchedAt,
  });
  final List<CryptoCandle> candles;
  final String asset;
  final DateTime fetchedAt;

  @override
  State<CryptoChart> createState() => _CryptoChartState();
}

class _CryptoChartState extends State<CryptoChart> {
  int? _selectedTime;

  @override
  Widget build(BuildContext context) {
    final rows = widget.candles;
    if (rows.isEmpty) return const Text('币安暂未返回该周期的 K 线。');
    var index = _selectedTime == null
        ? rows.length - 1
        : rows.indexWhere((row) => row.time == _selectedTime);
    if (index < 0) index = 0;
    final selected = rows[index];
    final forming =
        selected.closeTime >= widget.fetchedAt.millisecondsSinceEpoch;
    void select(int value) => setState(() {
      _selectedTime = value == rows.length - 1 ? null : rows[value].time;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${cryptoTime(selected.time)} UTC+8${forming ? ' · 未收盘' : ''}',
          key: const Key('crypto-candle-time'),
          style: const TextStyle(color: dashboardMuted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            Text('开 ${cryptoPrice(selected.open)}'),
            Text('高 ${cryptoPrice(selected.high)}'),
            Text('低 ${cryptoPrice(selected.low)}'),
            Text('收 ${cryptoPrice(selected.close)}'),
            Text('量 ${cryptoVolume(selected.volume)} ${widget.asset}'),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) {
            void point(Offset position) {
              final plotWidth = math.max(1.0, box.maxWidth - 64);
              final picked = ((position.dx - 4) / plotWidth * rows.length)
                  .floor();
              select(picked.clamp(0, rows.length - 1));
            }

            return Semantics(
              label: 'K 线与成交量图，绿色上涨、红色下跌，可用下方滑杆选择时间',
              child: GestureDetector(
                key: const Key('crypto-candles'),
                onTapDown: (details) => point(details.localPosition),
                onHorizontalDragUpdate: (details) =>
                    point(details.localPosition),
                child: SizedBox(
                  height: 280,
                  child: CustomPaint(painter: _CandlePainter(rows, index)),
                ),
              ),
            );
          },
        ),
        if (rows.length > 1)
          Slider(
            key: const Key('crypto-candle-slider'),
            value: index.toDouble(),
            max: (rows.length - 1).toDouble(),
            divisions: rows.length - 1,
            semanticFormatterCallback: (value) =>
                cryptoTime(rows[value.round()].time),
            label: cryptoTime(selected.time),
            onChanged: (value) => select(value.round()),
          ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 4,
          children: [
            Text(cryptoTime(rows.first.time)),
            Text(cryptoTime(rows.last.time)),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '点击图表或拖动滑杆查看开高低收。K 线按 UTC 分周期，时间显示为 UTC+8；最后一根可能尚未收盘。',
          style: TextStyle(color: dashboardMuted, fontSize: 12, height: 1.6),
        ),
      ],
    );
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.rows, this.selected);
  final List<CryptoCandle> rows;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    final right = size.width - 60;
    final width = right - 4;
    final bottom = size.height - 60;
    final rawLow = rows.map((r) => r.low).reduce(math.min);
    final rawHigh = rows.map((r) => r.high).reduce(math.max);
    final pad = math.max((rawHigh - rawLow) * .08, rawHigh * .001);
    final low = rawLow - pad, high = rawHigh + pad;
    double y(double price) =>
        10 + (high - price) / (high - low) * (bottom - 10);
    void label(String text, Offset offset, {Color color = dashboardMuted}) {
      final p = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: 10, fontFamily: 'ShikeSans'),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 58);
      p.paint(canvas, offset);
    }

    final grid = Paint()
      ..color = const Color(0xFF283332)
      ..strokeWidth = .5;
    for (var i = 0; i <= 4; i++) {
      final price = low + (high - low) * i / 4;
      canvas.drawLine(Offset(4, y(price)), Offset(right, y(price)), grid);
      label(cryptoPrice(price), Offset(right + 5, y(price) - 6));
    }
    final step = width / rows.length;
    final bodyWidth = (step * .65).clamp(.8, 12.0);
    final maxVolume = math.max(1.0, rows.map((r) => r.volume).reduce(math.max));
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final x = 4 + step * (i + .5);
      final pen = Paint()
        ..color = row.close >= row.open ? cryptoUp : cryptoDown
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, y(row.high)), Offset(x, y(row.low)), pen);
      final top = math.min(y(row.open), y(row.close));
      canvas.drawRect(
        Rect.fromLTWH(
          x - bodyWidth / 2,
          top,
          bodyWidth,
          math.max(1, (y(row.open) - y(row.close)).abs()),
        ),
        pen,
      );
      final height = row.volume / maxVolume * 36;
      canvas.drawRect(
        Rect.fromLTWH(
          x - bodyWidth / 2,
          size.height - 5 - height,
          bodyWidth,
          height,
        ),
        pen..color = pen.color.withValues(alpha: .55),
      );
    }
    label('成交量', Offset(5, bottom + 6));
    final x = 4 + step * (selected + .5);
    canvas.drawLine(
      Offset(x, 5),
      Offset(x, size.height),
      Paint()
        ..color = Colors.white54
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      Offset(x, y(rows[selected].close)),
      3,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CandlePainter old) =>
      old.rows != rows || old.selected != selected;
}
