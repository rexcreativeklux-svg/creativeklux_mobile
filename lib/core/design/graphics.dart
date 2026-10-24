import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:path_drawing/path_drawing.dart';

/// Graphics — the "graphic" element type: curated decorative multi-colour
/// vectors (sparkles, badges, doodles…). Port of the web's
/// `(lib)/design/graphics.js`.
///
/// Unlike shapes (single fill, recoloured per element) a graphic bakes its own
/// colours, so it reads as an illustration. The web keeps each one as inner SVG
/// markup on a 100×100 viewBox and rasterises it; here the same markup is kept
/// as a list of [GraphicPart]s painted directly — [paintGraphic] for the stage
/// and export (stretched, like `preserveAspectRatio="none"`) and
/// [paintGraphicPreview] for panel tiles (fitted, keeping aspect).

/// One SVG primitive of a graphic. Colours are 0xAARRGGBB; null = none.
sealed class GraphicPart {
  const GraphicPart({
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
    this.cap = StrokeCap.butt,
    this.join = StrokeJoin.miter,
  });
  final int? fill;
  final int? stroke;
  final double strokeWidth;
  final StrokeCap cap;
  final StrokeJoin join;

  Path toPath();

  void paint(Canvas c) {
    final path = toPath();
    if (fill != null) c.drawPath(path, Paint()..color = Color(fill!));
    if (stroke != null && strokeWidth > 0) {
      c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Color(stroke!)
          ..strokeWidth = strokeWidth
          ..strokeCap = cap
          ..strokeJoin = join,
      );
    }
  }
}

/// `<path d=…>`.
class GPath extends GraphicPart {
  const GPath(this.d, {super.fill, super.stroke, super.strokeWidth, super.cap, super.join});
  final String d;
  @override
  Path toPath() => parseSvgPathData(d);
}

/// `<circle>`.
class GCircle extends GraphicPart {
  const GCircle(this.cx, this.cy, this.r, {super.fill, super.stroke, super.strokeWidth});
  final double cx, cy, r;
  @override
  Path toPath() => Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
}

/// `<line>` (stroke only).
class GLine extends GraphicPart {
  const GLine(this.x1, this.y1, this.x2, this.y2, {super.stroke, super.strokeWidth, super.cap});
  final double x1, y1, x2, y2;
  @override
  Path toPath() => Path()
    ..moveTo(x1, y1)
    ..lineTo(x2, y2);
}

/// `<rect rx transform="rotate(deg cx cy)">`.
class GRect extends GraphicPart {
  const GRect(this.x, this.y, this.w, this.h, {this.rx = 0, this.rotate = 0, super.fill});
  final double x, y, w, h, rx, rotate;
  @override
  Path toPath() {
    final rect = Rect.fromLTWH(x, y, w, h);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(rx)));
    if (rotate == 0) return path;
    // SVG rotate(a cx cy) — about the rect's own centre in every graphic here.
    final t = rotate * math.pi / 180;
    final cs = math.cos(t), sn = math.sin(t);
    final cx = rect.center.dx, cy = rect.center.dy;
    return path.transform(
      Float64List.fromList([
        cs,
        sn,
        0,
        0,
        -sn,
        cs,
        0,
        0,
        0,
        0,
        1,
        0,
        cx - cs * cx + sn * cy,
        cy - sn * cx - cs * cy,
        0,
        1,
      ]),
    );
  }
}

class GraphicDef {
  const GraphicDef(this.key, this.label, this.parts, {this.viewBox = const [100, 100]});
  final String key;
  final String label;
  final List<double> viewBox;
  final List<GraphicPart> parts;
}

const _round = StrokeCap.round;
const _roundJ = StrokeJoin.round;

const graphics = <GraphicDef>[
  GraphicDef('sparkles', 'Sparkles', [
    GPath('M50 14 C54 40 60 46 86 50 C60 54 54 60 50 86 C46 60 40 54 14 50 C40 46 46 40 50 14 Z', fill: 0xFFFBBF24),
    GPath('M80 8 C82 18 84 20 94 22 C84 24 82 26 80 36 C78 26 76 24 66 22 C76 20 78 18 80 8 Z', fill: 0xFFF59E0B),
    GPath('M22 62 C24 72 26 74 36 76 C26 78 24 80 22 90 C20 80 18 78 8 76 C18 74 20 72 22 62 Z', fill: 0xFFFCD34D),
  ]),
  GraphicDef('star', 'Star', [
    GPath(
      'M50 6 L61.8 38.2 L96 38.2 L67 59.5 L79 94 L50 72.4 L21 94 L33 59.5 L4 38.2 L38.2 38.2 Z',
      fill: 0xFFFACC15,
      stroke: 0xFFEAB308,
      strokeWidth: 2,
    ),
  ]),
  GraphicDef('heart', 'Heart', [
    GPath(
      'M50 88 C16 62 4 44 4 26 C4 12 16 4 28 8 C38 11 46 20 50 28 C54 20 62 11 72 8 C84 4 96 12 96 26 C96 44 84 62 50 88 Z',
      fill: 0xFFF43F5E,
    ),
  ]),
  GraphicDef('bolt', 'Bolt', [
    GPath('M56 4 L20 56 H44 L40 96 L80 40 H54 Z', fill: 0xFFF59E0B, stroke: 0xFFD97706, strokeWidth: 2, join: _roundJ),
  ]),
  GraphicDef('check-badge', 'Check', [
    GCircle(50, 50, 42, fill: 0xFF22C55E),
    GPath('M32 52 L45 65 L70 36', stroke: 0xFFFFFFFF, strokeWidth: 8, cap: _round, join: _roundJ),
  ]),
  GraphicDef('sun', 'Sun', [
    GLine(50, 6, 50, 20, stroke: 0xFFF59E0B, strokeWidth: 6, cap: _round),
    GLine(50, 80, 50, 94, stroke: 0xFFF59E0B, strokeWidth: 6, cap: _round),
    GLine(6, 50, 20, 50, stroke: 0xFFF59E0B, strokeWidth: 6, cap: _round),
    GLine(80, 50, 94, 50, stroke: 0xFFF59E0B, strokeWidth: 6, cap: _round),
    GLine(19, 19, 29, 29, stroke: 0xFFF59E0B, strokeWidth: 6, cap: _round),
    GLine(71, 71, 81, 81, stroke: 0xFFF59E0B, strokeWidth: 6, cap: _round),
    GLine(81, 19, 71, 29, stroke: 0xFFF59E0B, strokeWidth: 6, cap: _round),
    GLine(29, 71, 19, 81, stroke: 0xFFF59E0B, strokeWidth: 6, cap: _round),
    GCircle(50, 50, 20, fill: 0xFFFBBF24),
  ]),
  GraphicDef('arrow-doodle', 'Arrow', [
    GPath('M10 30 C40 20 70 30 84 60', stroke: 0xFF6366F1, strokeWidth: 6, cap: _round),
    GPath('M84 60 L70 54 M84 60 L80 45', stroke: 0xFF6366F1, strokeWidth: 6, cap: _round, join: _roundJ),
  ]),
  GraphicDef('underline', 'Underline', [
    GPath(
      'M8 62 C34 52 66 52 92 60 C70 58 40 60 12 70 C36 66 66 66 90 72',
      stroke: 0xFF6366F1,
      strokeWidth: 6,
      cap: _round,
    ),
  ]),
  GraphicDef('quote', 'Quote', [
    GPath('M14 66 V44 C14 30 24 22 40 22 V34 C32 34 28 38 28 46 H40 V66 Z', fill: 0xFFC4B5FD),
    GPath('M56 66 V44 C56 30 66 22 82 22 V34 C74 34 70 38 70 46 H82 V66 Z', fill: 0xFFA78BFA),
  ]),
  GraphicDef('pin', 'Pin', [
    GPath('M50 92 C50 92 80 58 80 38 A30 30 0 1 0 20 38 C20 58 50 92 50 92 Z', fill: 0xFFEF4444),
    GCircle(50, 38, 12, fill: 0xFFFFFFFF),
  ]),
  GraphicDef('confetti', 'Confetti', [
    GRect(14, 20, 12, 12, rx: 2, rotate: 20, fill: 0xFF6366F1),
    GRect(70, 16, 12, 12, rx: 2, rotate: -15, fill: 0xFF22C55E),
    GCircle(82, 60, 7, fill: 0xFFF59E0B),
    GCircle(24, 70, 7, fill: 0xFFEC4899),
    GRect(48, 66, 12, 12, rx: 2, rotate: 35, fill: 0xFF06B6D4),
    GCircle(52, 24, 6, fill: 0xFFFACC15),
  ]),
  GraphicDef('flower', 'Flower', [
    GCircle(50, 26, 15, fill: 0xFFF9A8D4),
    GCircle(50, 74, 15, fill: 0xFFF9A8D4),
    GCircle(26, 50, 15, fill: 0xFFF9A8D4),
    GCircle(74, 50, 15, fill: 0xFFF9A8D4),
    GCircle(50, 50, 14, fill: 0xFFFBBF24),
  ]),
];

final Map<String, GraphicDef> _graphicMap = {for (final g in graphics) g.key: g};

/// Geometry for a graphic key; an unknown key falls back to the first graphic.
GraphicDef graphicDef(Object? key) => _graphicMap[key] ?? graphics.first;

void _parts(Canvas c, GraphicDef def) {
  for (final p in def.parts) {
    p.paint(c);
  }
}

/// `graphicSVG`: the graphic stretched to fill [box] (preserveAspectRatio none).
void paintGraphic(Canvas c, Map<String, dynamic> el, Rect box) {
  final def = graphicDef(el['graphic']);
  if (box.width <= 0 || box.height <= 0) return;
  c.save();
  c.translate(box.left, box.top);
  c.scale(box.width / def.viewBox[0], box.height / def.viewBox[1]);
  _parts(c, def);
  c.restore();
}

/// `graphicPreviewSVG`: fitted into [size], centred, keeping aspect.
void paintGraphicPreview(Canvas c, String key, Size size) {
  final def = graphicDef(key);
  final s = math.min(size.width / def.viewBox[0], size.height / def.viewBox[1]);
  c.save();
  c.translate((size.width - def.viewBox[0] * s) / 2, (size.height - def.viewBox[1] * s) / 2);
  c.scale(s);
  _parts(c, def);
  c.restore();
}
