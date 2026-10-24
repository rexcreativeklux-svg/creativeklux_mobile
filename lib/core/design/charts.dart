import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'css_color.dart';
import 'js_values.dart';

/// Chart geometry — the "chart" element type (bar / line / pie / donut). Port
/// of the web's `(lib)/design/charts.js`.
///
/// The web builds the chart ONCE as an SVG string and both the editor and the
/// export rasterise it. Here the same geometry is painted straight onto the
/// canvas by [paintChart], which the renderer calls for the stage and the
/// export alike — so the two still can't drift.
///
/// Element shape: `{type: 'chart', chart, data: [{label, value}], colors?, width, height}`.

const chartTypes = [('bar', 'Bar'), ('line', 'Line'), ('pie', 'Pie'), ('donut', 'Donut')];

const chartPalette = ['#6366f1', '#22c55e', '#f59e0b', '#ef4444', '#06b6d4', '#a855f7', '#ec4899', '#84cc16'];

const defaultChartData = [
  {'label': 'Jan', 'value': 40},
  {'label': 'Feb', 'value': 70},
  {'label': 'Mar', 'value': 55},
  {'label': 'Apr', 'value': 90},
];

/// A fresh, editable copy of [defaultChartData] (what insertChart seeds).
List<Map<String, dynamic>> defaultChartDataCopy() => [for (final d in defaultChartData) Map<String, dynamic>.from(d)];

// SVG colours the web hard-codes into the chart.
const _axis = Color(0xFFE5E7EB);
const _label = Color(0xFF6B7280);
const _legend = Color(0xFF374151);
const _white = Color(0xFFFFFFFF);

/// `num()` in charts.js: non-finite → 0.
double _num(Object? v) {
  final n = numOf(v);
  return (n != null && n.isFinite) ? n : 0;
}

/// The chart's data rows: `el.data` when non-empty, else the sample data.
List<Map<String, dynamic>> chartData(Map<String, dynamic> el) {
  final raw = el['data'];
  final rows = <Map<String, dynamic>>[
    if (raw is List)
      for (final d in raw) ?asMap(d),
  ];
  return rows.isNotEmpty ? rows : defaultChartDataCopy();
}

List<Color> _colors(Map<String, dynamic> el) {
  final raw = el['colors'];
  final list = <Color>[
    if (raw is List)
      for (final c in raw) ?parseCssColor(c),
  ];
  return list.isNotEmpty ? list : [for (final c in chartPalette) parseCssColor(c)!];
}

/// Paint a chart element into [box]. The web lays the SVG out at the rounded
/// element size and stretches it onto the box, so this does the same.
/// [textStyle] supplies the face (the web asks for DM Sans).
void paintChart(Canvas c, Map<String, dynamic> el, Rect box, {TextStyle textStyle = const TextStyle()}) {
  final w = math.max(1, orNum(el['width'], 1).round()).toDouble();
  final h = math.max(1, orNum(el['height'], 1).round()).toDouble();
  if (box.width <= 0 || box.height <= 0) return;
  final data = chartData(el);
  final colors = _colors(el);
  final type = truthy(el['chart']) ? '${el['chart']}' : 'bar';

  c.save();
  c.translate(box.left, box.top);
  c.scale(box.width / w, box.height / h);
  final p = _ChartPainter(c, textStyle);
  if (type == 'line') {
    p.line(data, w, h, colors);
  } else if (type == 'pie' || type == 'donut') {
    p.pie(data, w, h, colors, type == 'donut');
  } else {
    p.bar(data, w, h, colors);
  }
  c.restore();
}

class _ChartPainter {
  _ChartPainter(this.c, this.style);
  final Canvas c;
  final TextStyle style;

  /// SVG `<text>`: [y] is the alphabetic baseline; [anchor] 'middle' centres on [x].
  void _text(String s, double x, double y, double size, Color color, {bool middle = false}) {
    if (s.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: style.copyWith(fontSize: size, color: color, fontWeight: FontWeight.w400),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.paint(c, Offset(middle ? x - tp.width / 2 : x, y - ascent));
    tp.dispose();
  }

  void _baseline(double padX, double plotW, double baseY) => c.drawLine(
    Offset(padX, baseY),
    Offset(padX + plotW, baseY),
    Paint()
      ..color = _axis
      ..strokeWidth = 1,
  );

  /// `Math.max(...values, 1)`.
  double _max(List<Map<String, dynamic>> data) => data.map((d) => _num(d['value'])).fold<double>(1, math.max);

  void bar(List<Map<String, dynamic>> data, double w, double h, List<Color> colors) {
    final padX = w * 0.08;
    final padTop = h * 0.1;
    final padBot = h * 0.16;
    final plotW = w - padX * 2;
    final plotH = h - padTop - padBot;
    final baseY = padTop + plotH;
    final max = _max(data);
    final n = data.isEmpty ? 1 : data.length;
    final step = plotW / n;
    final bw = step * 0.6;
    final fs = math.max(9, (h * 0.05).round()).toDouble();

    _baseline(padX, plotW, baseY);
    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      final bh = plotH * (_num(d['value']) / max);
      final x = padX + step * i + (step - bw) / 2;
      final y = baseY - bh;
      if (bh > 0) {
        c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, bw, bh), const Radius.circular(3)),
          Paint()..color = colors[i % colors.length],
        );
      }
      _text('${d['label'] ?? ''}', x + bw / 2, baseY + fs * 1.4, fs, _label, middle: true);
    }
  }

  void line(List<Map<String, dynamic>> data, double w, double h, List<Color> colors) {
    final padX = w * 0.08;
    final padTop = h * 0.1;
    final padBot = h * 0.16;
    final plotW = w - padX * 2;
    final plotH = h - padTop - padBot;
    final baseY = padTop + plotH;
    final max = _max(data);
    final n = data.isEmpty ? 1 : data.length;
    final step = n > 1 ? plotW / (n - 1) : 0.0;
    final fs = math.max(9, (h * 0.05).round()).toDouble();
    final color = colors[0];

    final pts = [
      for (var i = 0; i < data.length; i++)
        Offset(padX + (n > 1 ? step * i : plotW / 2), baseY - plotH * (_num(data[i]['value']) / max)),
    ];

    _baseline(padX, plotW, baseY);
    if (pts.length > 1) {
      c.drawPath(
        Path()..addPolygon(pts, false),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = color
          ..strokeWidth = math.max(2, h * 0.012)
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    final r = math.max(2.5, h * 0.014);
    for (var i = 0; i < pts.length; i++) {
      c.drawCircle(pts[i], r, Paint()..color = _white);
      c.drawCircle(
        pts[i],
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = color
          ..strokeWidth = 2,
      );
      _text('${data[i]['label'] ?? ''}', pts[i].dx, baseY + fs * 1.4, fs, _label, middle: true);
    }
  }

  void pie(List<Map<String, dynamic>> data, double w, double h, List<Color> colors, bool donut) {
    final cx = w * 0.34;
    final cy = h * 0.5;
    final r = math.min(w * 0.3, h * 0.42);
    final sum = data.fold<double>(0, (a, d) => a + _num(d['value']));
    final total = sum == 0 ? 1.0 : sum;
    final fs = math.max(9, (h * 0.055).round()).toDouble();
    final center = Offset(cx, cy);
    final circle = Rect.fromCircle(center: center, radius: r);

    var a0 = -math.pi / 2;
    for (var i = 0; i < data.length; i++) {
      final frac = _num(data[i]['value']) / total;
      final paint = Paint()..color = colors[i % colors.length];
      if (frac >= 0.999) {
        c.drawCircle(center, r, paint);
      } else if (frac > 0) {
        final sweep = frac * math.pi * 2;
        c.drawPath(
          Path()
            ..moveTo(cx, cy)
            ..arcTo(circle, a0, sweep, false)
            ..close(),
          paint,
        );
        a0 += sweep;
      }
    }
    if (donut) c.drawCircle(center, r * 0.55, Paint()..color = _white);

    // Legend on the right.
    final lx = w * 0.66;
    final lh = math.min(h * 0.14, fs * 1.8);
    final sw = lh * 0.55;
    final startY = cy - (data.length * lh) / 2;
    for (var i = 0; i < data.length; i++) {
      final yy = startY + i * lh;
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(lx, yy, sw, sw), const Radius.circular(2)),
        Paint()..color = colors[i % colors.length],
      );
      _text('${data[i]['label'] ?? ''}', lx + sw * 1.5, yy + sw * 0.85, fs, _legend);
    }
  }
}
