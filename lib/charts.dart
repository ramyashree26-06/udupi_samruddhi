import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

const List<Color> kChartColors = [
  Color(0xFFF26A12),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFF8E24AA),
  Color(0xFFFBC02D),
  Color(0xFF00897B),
  Color(0xFFE53935),
];

void _text(Canvas c, String s, Offset o,
    {double size = 10, Color color = kMuted, bool center = false, bool right = false}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color)),
    textDirection: TextDirection.ltr,
  )..layout();
  var dx = o.dx;
  if (center) dx -= tp.width / 2;
  if (right) dx -= tp.width;
  tp.paint(c, Offset(dx, o.dy));
}

/// Simple orange bar chart.
class BarChart extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  final double height;
  const BarChart({super.key, required this.labels, required this.values, this.height = 200});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _BarPainter(labels, values)),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<String> labels;
  final List<double> values;
  _BarPainter(this.labels, this.values);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0;
    const bottom = 20.0;
    final w = size.width - left;
    final h = size.height - bottom - 6;
    var maxV = 0.0;
    for (final v in values) {
      if (v > maxV) maxV = v;
    }
    if (maxV <= 0) maxV = 1;
    // round the top of the scale
    final mag = math.pow(10, (math.log(maxV) / math.ln10).floor()).toDouble();
    final top = (maxV / mag).ceil() * mag;
    final grid = Paint()
      ..color = kLine
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = 6 + h - h * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      _text(canvas, (top * i / 4).round().toString(), Offset(left - 6, y - 6), right: true);
    }
    if (values.isEmpty) return;
    final slot = w / values.length;
    final bw = math.min(slot * 0.6, 34.0);
    final paint = Paint()..color = kOrange;
    for (var i = 0; i < values.length; i++) {
      final bh = h * values[i] / top;
      final x = left + slot * i + (slot - bw) / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(x, 6 + h - bh, bw, bh),
            topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
        paint,
      );
      final every = math.max(1, (22 / math.max(slot, 1)).ceil());
      if (labels.length > i && i % every == 0) {
        _text(canvas, labels[i], Offset(x + bw / 2, size.height - bottom + 5), center: true, size: 9.5);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => true;
}

/// Donut chart with a small list next to it.
class DonutChart extends StatelessWidget {
  final List<MapEntry<String, double>> items;
  final bool compact; // small donut with the legend underneath
  const DonutChart({super.key, required this.items, this.compact = false});

  @override
  Widget build(BuildContext context) {
    var total = 0.0;
    for (final e in items) {
      total += e.value;
    }
    if (total <= 0) {
      return const SizedBox(
          height: 150, child: Center(child: Text('No sales', style: TextStyle(color: kMuted))));
    }
    if (compact) {
      return Column(
        children: [
          SizedBox(
            width: 90,
            height: 90,
            child: CustomPaint(painter: _DonutPainter([for (final e in items) e.value])),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < items.length && i < 5; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: kChartColors[i % kChartColors.length],
                        shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Expanded(
                    child: Text(items[i].key,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11))),
                Text('${(items[i].value * 100 / total).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
              ]),
            ),
        ],
      );
    }
    return Row(
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: CustomPaint(painter: _DonutPainter([for (final e in items) e.value])),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: kChartColors[i % kChartColors.length],
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(items[i].key,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13))),
                      Text('${(items[i].value * 100 / total).round()}%',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  _DonutPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    var total = 0.0;
    for (final v in values) {
      total += v;
    }
    final rect = Rect.fromLTWH(14, 14, size.width - 28, size.height - 28);
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = 2 * math.pi * values[i] / total;
      final paint = Paint()
        ..color = kChartColors[i % kChartColors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => true;
}

String _k(double v) {
  if (v >= 1000) {
    final k = v / 1000;
    return '${k == k.roundToDouble() ? k.round() : k.toStringAsFixed(1)}K';
  }
  return v.round().toString();
}

/// Smooth orange line with a soft fill under it (phone dashboard).
class LineChart extends StatelessWidget {
  final List<String> labels; // '' = no label under that point
  final List<double> values;
  final double height;
  const LineChart({super.key, required this.labels, required this.values, this.height = 170});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _LinePainter(labels, values)),
      );
}

class _LinePainter extends CustomPainter {
  final List<String> labels;
  final List<double> values;
  _LinePainter(this.labels, this.values);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const bottom = 20.0;
    const topPad = 8.0;
    final w = size.width - left - 6;
    final h = size.height - bottom - topPad;
    var maxV = 0.0;
    for (final v in values) {
      if (v > maxV) maxV = v;
    }
    if (maxV <= 0) maxV = 1;
    final mag = math.pow(10, (math.log(maxV) / math.ln10).floor()).toDouble();
    final top = (maxV / mag).ceil() * mag;
    final grid = Paint()
      ..color = kLine
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = topPad + h - h * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      _text(canvas, _k(top * i / 4), Offset(left - 6, y - 6), right: true, size: 9.5);
    }
    if (values.length < 2) return;
    final n = values.length;
    Offset pt(int i) => Offset(
        left + 4 + (w - 4) * i / (n - 1), topPad + h - h * values[i] / top);
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 0; i < n - 1; i++) {
      final a = pt(i), b = pt(i + 1);
      final mx = (a.dx + b.dx) / 2;
      path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    final area = Path.from(path)
      ..lineTo(pt(n - 1).dx, topPad + h)
      ..lineTo(pt(0).dx, topPad + h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x55F26A12), Color(0x05F26A12)],
        ).createShader(Rect.fromLTWH(left, topPad, w, h)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = kOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < n; i++) {
      if (labels.length > i && labels[i].isNotEmpty) {
        final o = pt(i);
        canvas.drawCircle(Offset(o.dx, o.dy), 3.6, Paint()..color = Colors.white);
        canvas.drawCircle(
            Offset(o.dx, o.dy),
            3.6,
            Paint()
              ..color = kOrange
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8);
        _text(canvas, labels[i], Offset(o.dx, size.height - bottom + 5), center: true, size: 9);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}
