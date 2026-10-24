import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_drawing/path_drawing.dart';

import 'charts.dart';
import 'css_color.dart';
import 'design_assets.dart';
import 'effects.dart';
import 'gradient.dart';
import 'graphics.dart';
import 'groups.dart';
import 'image_filters.dart';
import 'js_values.dart';
import 'scraive_compat.dart';
import 'shapes.dart';

/// Port of the web's `(lib)/design/renderDesign.js` (`renderDesignToCanvas`):
/// paints a `{canvas, elements}` design with dart:ui directly, so it works
/// offscreen (thumbnails, saving) as well as behind [DesignCanvas].
///
/// Supported: colour / CSS-gradient / image backgrounds; hidden, opacity,
/// rotation, zIndex order, crop windows (`clip`) and group clips; groups; video
/// (as its poster); shapes (primitives + the whole SHAPES library, lines with
/// dash and bend, stroke + strokeDash, shapeEffect shadows); text (wrapping,
/// alignment, vertical layout, underline, letter spacing, every textEffect,
/// sticky-note panel); images (cover / contain, crop, radius, flips,
/// cropRotate, backgroundColor, dashed borders, Adjust / filter looks / drop
/// shadow via `buildImageFilter` — see image_filters.dart); draw; curve; table;
/// grid; frame; chart and graphic (charts.dart / graphics.dart paint the
/// geometry the web turns into SVG).
///
/// Not yet supported (skipped without error): the Adjust tone controls
/// (toneFilter.js: tint, highlights, shadows, whites, blacks, vibrance), image
/// perspective warp and colour tint.

/// Paints a design at its full canvas size (times [pixelRatio]) and returns the image.
/// `canvas` = {width, height, background}; `elements` = raw element maps.
/// [scraive] = true for Scraive-sourced elements (fromScraiveElements with text: true).
Future<ui.Image> renderDesign(
  Map<String, dynamic> canvas,
  List<dynamic> elements, {
  bool scraive = false,
  double pixelRatio = 1,
}) async {
  final width = orNum(canvas['width'], 1080);
  final height = orNum(canvas['height'], 1080);
  final flat = _flatten(fromScraiveElements(elements, text: scraive));
  final bg = _background(canvas);
  final bgIsImage = _isImageBackground(bg);

  // Everything async happens here; the paint below is synchronous.
  final sources = <String>[if (bgIsImage) bg as String, for (final el in flat) ..._imageSources(el)];
  final fonts = DesignFonts();
  final results = await Future.wait([loadDesignImages(sources), fonts.load(_faces(flat))]);
  final images = results[0] as Map<String, ui.Image>;

  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  c.scale(pixelRatio);
  c.clipRect(Rect.fromLTWH(0, 0, width, height));
  final painter = _Painter(c, images, fonts);
  painter.background(bg, bgIsImage, width, height);
  for (final el in flat) {
    painter.element(el);
  }

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(math.max(1, (width * pixelRatio).round()), math.max(1, (height * pixelRatio).round()));
  } finally {
    picture.dispose();
    for (final img in images.values) {
      img.dispose();
    }
  }
}

/// PNG bytes of the render.
Future<Uint8List> renderDesignPng(
  Map<String, dynamic> canvas,
  List<dynamic> elements, {
  bool scraive = false,
  double pixelRatio = 1,
}) async {
  final image = await renderDesign(canvas, elements, scraive: scraive, pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG encoding failed');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

/// Groups expanded into absolute coordinates, and a video painted as its
/// poster still — one without a poster is left out.
List<Map<String, dynamic>> _flatten(List<Map<String, dynamic>> elements) => [
  for (final el in flattenGroups(elements))
    if (el['type'] != 'video')
      el
    else if (el['poster'] is String && (el['poster'] as String).isNotEmpty)
      {...el, 'type': 'image', 'src': el['poster']},
];

Object? _background(Map<String, dynamic> canvas) => truthy(canvas['background']) ? canvas['background'] : '#ffffff';

bool _isImageBackground(Object? bg) => bg is String && RegExp(r'^(https?:|data:|blob:)').hasMatch(bg);

/// The (family, weight, style) faces a set of flattened elements paints with.
List<(String, FontWeight, FontStyle)> _faces(List<Map<String, dynamic>> flat) => [
  for (final el in flat)
    if (el['type'] == 'text')
      (fontFamilyName(el['fontFamily']), fontWeightOf(el['fontWeight']), fontStyleOf(el['fontStyle']))
    else if (el['type'] == 'table') ...[
      (fontFamilyName(el['fontFamily']), FontWeight.w400, FontStyle.normal),
      (fontFamilyName(el['fontFamily']), FontWeight.w600, FontStyle.normal),
    ],
];

/// Live painting for the design editor's stage.
///
/// [renderDesign] loads everything, paints once and throws its images away —
/// right for a thumbnail, far too slow for a drag. A scene keeps what it has
/// loaded for as long as the editor is open, and [paint] is synchronous, so the
/// stage repaints every frame with the SAME painter the export uses: what you
/// edit is pixel-for-pixel what gets saved and downloaded.
///
/// New images and fonts are fetched in the background by [prepare]; listeners
/// are notified as each one lands so the stage can repaint.
class DesignScene extends ChangeNotifier {
  final Map<String, ui.Image> _images = {};
  final Set<String> _requested = {};
  final Set<(String, FontWeight, FontStyle)> _requestedFaces = {};
  final DesignFonts _fonts = DesignFonts();
  bool _disposed = false;

  /// Start loading whatever this design needs that isn't loaded yet.
  void prepare(Map<String, dynamic> canvas, List<Map<String, dynamic>> elements) {
    final flat = _flatten(elements);
    final bg = _background(canvas);
    final sources = <String>[if (_isImageBackground(bg)) bg as String, for (final el in flat) ..._imageSources(el)];
    for (final src in sources) {
      if (!_requested.add(src)) continue;
      loadDesignImage(src).then((img) {
        if (_disposed) {
          img?.dispose();
        } else if (img != null) {
          _images[src] = img;
          notifyListeners();
        }
      });
    }
    final faces = _faces(flat).where(_requestedFaces.add).toList();
    if (faces.isNotEmpty) {
      _fonts.load(faces).then((_) {
        if (!_disposed) notifyListeners();
      });
    }
  }

  /// Text style for one element's face (once loaded) — the inline text editor
  /// uses it so typing looks like the element it replaces.
  TextStyle textStyleFor(Map<String, dynamic> el) =>
      _fonts.styleFor(fontFamilyName(el['fontFamily']), fontWeightOf(el['fontWeight']), fontStyleOf(el['fontStyle']));

  /// Paint the design in canvas units (the caller scales). Elements whose id
  /// is in [skip] are left out — the one being typed into, for instance.
  void paint(
    Canvas c,
    Map<String, dynamic> canvas,
    List<Map<String, dynamic>> elements, {
    Set<String> skip = const {},
    bool clip = true,
    bool background = true,
  }) {
    final width = orNum(canvas['width'], 1080);
    final height = orNum(canvas['height'], 1080);
    final bg = _background(canvas);
    c.save();
    // [clip] false lets effect previews spill a shadow past the page edge.
    if (clip) c.clipRect(Rect.fromLTWH(0, 0, width, height));
    final painter = _Painter(c, _images, _fonts);
    // [background] false paints just the elements — the animation preview
    // draws them one at a time over a background painted once.
    if (background) painter.background(bg, _isImageBackground(bg), width, height);
    // Skipped AFTER groups are expanded, so a group member being typed into is
    // hidden too (members keep their ids when flattened).
    for (final el in _flatten(elements)) {
      if (skip.isEmpty || !skip.contains(el['id'])) painter.element(el);
    }
    c.restore();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
    super.dispose();
  }
}

Iterable<String> _imageSources(Map<String, dynamic> el) sync* {
  final type = el['type'];
  if ((type == 'image' || type == 'frame') && el['src'] is String && (el['src'] as String).isNotEmpty) {
    yield el['src'] as String;
  }
  if (type == 'grid' && el['cells'] is List) {
    for (final cell in el['cells'] as List) {
      final src = asMap(cell)?['src'];
      if (src is String && src.isNotEmpty) yield src;
    }
  }
}

// ── Geometry helpers ────────────────────────────────────────────────────────

/// `radiusCorners` (radius.js): a uniform number or {topLeft, …} → [tl, tr, br, bl].
List<double> radiusCorners(Object? r) {
  double corner(Object? v) {
    final n = numOf(v);
    return (n != null && n.isFinite && n > 0) ? n : 0;
  }

  if (r is num || r is String) return List.filled(4, corner(r));
  final m = asMap(r);
  if (m == null) return const [0, 0, 0, 0];
  return [corner(m['topLeft']), corner(m['topRight']), corner(m['bottomRight']), corner(m['bottomLeft'])];
}

/// A rounded rect with radii scaled down the way canvas `roundRect` (and CSS)
/// does when adjacent corners would overlap.
RRect _rrect(Rect r, List<double> c) {
  final w = r.width.abs();
  final h = r.height.abs();
  var f = 1.0;
  void fit(double side, double a, double b) {
    if (a + b > side && a + b > 0) f = math.min(f, side / (a + b));
  }

  fit(w, c[0], c[1]);
  fit(w, c[3], c[2]);
  fit(h, c[0], c[3]);
  fit(h, c[1], c[2]);
  return RRect.fromRectAndCorners(
    r,
    topLeft: Radius.circular(c[0] * f),
    topRight: Radius.circular(c[1] * f),
    bottomRight: Radius.circular(c[2] * f),
    bottomLeft: Radius.circular(c[3] * f),
  );
}

/// A dashed copy of [p] (canvas `setLineDash`). Zero-length dashes become
/// hairline dots so round caps still draw them.
Path _dashed(Path p, List<double> dash) {
  if (dash.isEmpty) return p;
  final arr = [for (final d in dash) d <= 0 ? 0.01 : d];
  // Canvas repeats an odd-length list twice to make it even.
  final even = arr.length.isOdd ? [...arr, ...arr] : arr;
  if (even.fold<double>(0, (a, b) => a + b) <= 0.05) return p;
  return dashPath(p, dashArray: CircularIntervalList<double>(even));
}

StrokeCap _cap(Object? cap) => switch (cap) {
  'round' => StrokeCap.round,
  'square' => StrokeCap.square,
  _ => StrokeCap.butt,
};

/// `coverScale` (videoCrop.js): how much a box turned by [deg] must grow to
/// keep covering itself.
double _coverScale(double w, double h, double deg) {
  final t = deg.abs() * math.pi / 180;
  if (t == 0 || w == 0 || h == 0) return 1;
  final c = math.cos(t);
  final s = math.sin(t);
  return math.max(c + (h / w) * s, (w / h) * s + c);
}

class _Painter {
  _Painter(this.c, this.images, this.fonts);

  final Canvas c;
  final Map<String, ui.Image> images;
  final DesignFonts fonts;

  Rect _box(Map<String, dynamic> el) =>
      Rect.fromLTWH(nnNum(el['x'], 0), nnNum(el['y'], 0), orNum(el['width'], 0), orNum(el['height'], 0));

  void background(Object? bg, bool isImage, double w, double h) {
    final rect = Rect.fromLTWH(0, 0, w, h);
    if (isImage) {
      c.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
      final img = images[bg];
      if (img != null) _drawCover(img, rect);
      return;
    }
    // A CSS gradient becomes a real shader across the page. Unreadable values
    // fall back to white (the web would leave the canvas's default black).
    c.drawRect(rect, paintFor(bg, rect) ?? (Paint()..color = const Color(0xFFFFFFFF)));
  }

  void element(Map<String, dynamic> source) {
    if (truthy(source['hidden'])) return;
    final opacity = nnNum(source['opacity'], 1).clamp(0.0, 1.0);
    if (opacity <= 0) return;

    final saveCount = c.getSaveCount();
    c.save();
    try {
      // Clip windows inherited from cropped groups — already in canvas space,
      // so they go on BEFORE the element's own rotation.
      final polys = source[clipKey];
      if (polys is List<List<Offset>>) {
        for (final poly in polys) {
          c.clipPath(Path()..addPolygon(poly, true));
        }
      }

      // Rotation is about the element's REAL box (the window, not the content).
      final box = _box(source);
      final rotation = orNum(source['rotation'], 0);
      if (rotation != 0) {
        c.translate(box.center.dx, box.center.dy);
        c.rotate(rotation * math.pi / 180);
        c.translate(-box.center.dx, -box.center.dy);
      }

      // A cropped element's box is a WINDOW onto content laid out at its own
      // size: clip to the box, then draw against the content box.
      if (isClipped(source['clip'])) c.clipRect(box);

      // canvas globalAlpha → one layer, so the element's own overlapping
      // passes (shadow + fill + stroke) fade together.
      if (opacity < 1) c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));

      final el = windowed(source);
      switch (el['type']) {
        case 'draw':
          _draw(el);
        case 'curve':
          _curve(el);
        case 'shape':
          _shape(el);
        case 'text':
          _text(el);
        case 'table':
          _table(el);
        case 'grid':
          _grid(el);
        case 'frame':
          _frame(el);
        case 'image':
          _image(el);
        case 'chart':
          paintChart(c, el, _box(el), textStyle: fonts.styleFor(defaultFontFamily, FontWeight.w400, FontStyle.normal));
        case 'graphic':
          paintGraphic(c, el, _box(el));
      }
    } catch (_) {
      // One malformed element must not cost the whole design.
    } finally {
      c.restoreToCount(saveCount);
    }
  }

  // ── Effects ──

  /// One canvas-style shadow pass: [draw]'s silhouette, tinted, blurred and
  /// offset. A layer with a srcIn colour filter reproduces `shadowColor`
  /// exactly, including the drawing's own alpha.
  void _shadowPass(EffectShadow s, void Function() draw) {
    final paint = Paint()..colorFilter = ColorFilter.mode(s.color, BlendMode.srcIn);
    // Canvas shadowBlur is twice the Gaussian sigma.
    if (s.blur > 0) paint.imageFilter = ui.ImageFilter.blur(sigmaX: s.blur / 2, sigmaY: s.blur / 2);
    c.saveLayer(null, paint);
    c.translate(s.dx, s.dy);
    draw();
    c.restore();
  }

  /// `drawWithShapeEffect`: each shadow layer, then the shape on top.
  void _withShapeEffect(Map<String, dynamic> el, void Function() draw) {
    for (final s in resolveShapeEffect(el)) {
      _shadowPass(s, draw);
    }
    draw();
  }

  // ── draw / curve ──

  void _strokedInViewBox(Map<String, dynamic> el, Path path, {List<double>? dash, bool multiply = false}) {
    final box = _box(el);
    final vw = orNum(el['vbW'], box.width);
    final vh = orNum(el['vbH'], box.height);
    if (vw == 0 || vh == 0) return;
    final paint = paintFor(truthy(el['stroke']) ? el['stroke'] : '#111111', Rect.fromLTWH(0, 0, vw, vh));
    if (paint == null) return;
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = orNum(el['strokeWidth'], 4)
      ..strokeCap = truthy(el['cap']) ? _cap(el['cap']) : StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (multiply) paint.blendMode = BlendMode.multiply;
    c.save();
    c.translate(box.left, box.top);
    c.scale(box.width / vw, box.height / vh);
    c.drawPath(dash == null ? path : _dashed(path, dash), paint);
    c.restore();
  }

  List<Offset> _points(Object? raw) => [
    if (raw is List)
      for (final p in raw)
        if (asMap(p) case final m?) Offset(nnNum(m['x'], 0), nnNum(m['y'], 0)),
  ];

  /// `pointsToPath` (drawUtils.js): a polyline; one point is a tiny line so
  /// round caps draw it as a dot.
  void _draw(Map<String, dynamic> el) {
    final pts = _points(el['points']);
    if (pts.isEmpty) return;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    if (pts.length == 1) {
      path.lineTo(pts[0].dx + 0.01, pts[0].dy);
    } else {
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
    }
    _strokedInViewBox(el, path, multiply: truthy(el['blend']));
  }

  /// `curvePath` (curveUtils.js): straight segments when `sharp`, else a
  /// Catmull-Rom spline through every node, as cubic béziers.
  void _curve(Map<String, dynamic> el) {
    final pts = _points(el['points']);
    if (pts.length < 2) return;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    if (truthy(el['sharp']) || pts.length == 2) {
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
    } else {
      for (var i = 0; i < pts.length - 1; i++) {
        final p0 = i > 0 ? pts[i - 1] : pts[i];
        final p1 = pts[i];
        final p2 = pts[i + 1];
        final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
        path.cubicTo(
          p1.dx + (p2.dx - p0.dx) / 6,
          p1.dy + (p2.dy - p0.dy) / 6,
          p2.dx - (p3.dx - p1.dx) / 6,
          p2.dy - (p3.dy - p1.dy) / 6,
          p2.dx,
          p2.dy,
        );
      }
    }
    final dash = el['dash'] is List ? [for (final d in el['dash'] as List) numOf(d) ?? 0] : null;
    _strokedInViewBox(el, path, dash: dash);
  }

  // ── shape ──

  void _shape(Map<String, dynamic> el) {
    final key = el['shape'];
    final def = shapes[key];
    if (!primitiveShapes.contains(key) && def != null && def.path != null) {
      _libraryShape(el, key as String, def);
    } else {
      // Primitives — and 'rounded', whose library entry has no path (it is a
      // box that takes the element's own borderRadius).
      _primitiveShape(el);
    }
  }

  /// Library shape: its viewBox mapped onto the element box.
  void _libraryShape(Map<String, dynamic> el, String key, ShapeDef def) {
    final box = _box(el);
    final vw = def.viewBox[0];
    final vh = def.viewBox[1];
    if (box.width == 0 || box.height == 0) return;
    final vb = Rect.fromLTWH(0, 0, vw, vh);

    void inViewBox(void Function() f) {
      c.save();
      c.translate(box.left, box.top);
      c.scale(box.width / vw, box.height / vh);
      f();
      c.restore();
    }

    if (def.kind == 'stroke') {
      // Bendable lines honour `bend` (element px → viewBox control offset).
      final bend = orNum(el['bend'], 0);
      final bendVB = bend != 0 ? 24 * bend / orNum(el['height'], 1) : 0.0;
      final path = parseSvgPathData(lineShaftPath(key, bendVB));
      final paint = paintFor(truthy(el['fill']) ? el['fill'] : '#111111', vb);
      if (paint == null) return;
      paint
        ..style = PaintingStyle.stroke
        // The element's own weight wins; the def is only its creation default.
        ..strokeWidth = orNum(el['strokeWidth'], def.strokeW ?? 3)
        ..strokeCap = _cap(def.cap)
        ..strokeJoin = StrokeJoin.round;
      inViewBox(() => c.drawPath(def.dash == null ? path : _dashed(path, def.dash!), paint));
      return;
    }

    final path = parseSvgPathData(def.path!);
    final fill = paintFor(truthy(el['fill']) ? el['fill'] : '#6366f1', vb);
    final sw = orNum(el['strokeWidth'], 0);
    final stroke = (sw != 0 && truthy(el['stroke'])) ? paintFor(el['stroke'], vb) : null;
    stroke
      ?..style = PaintingStyle.stroke
      ..strokeWidth = sw;
    final strokePath = stroke == null ? null : _dashed(path, dashArrayFor(el['strokeDash'], el['strokeWidth']));
    _withShapeEffect(
      el,
      () => inViewBox(() {
        if (fill != null) c.drawPath(path, fill);
        if (stroke != null) c.drawPath(strokePath!, stroke);
      }),
    );
  }

  void _primitiveShape(Map<String, dynamic> el) {
    final box = _box(el);
    final fill = paintFor(truthy(el['fill']) ? el['fill'] : 'transparent', box);
    final sw = orNum(el['strokeWidth'], 0);
    final stroke = sw != 0 ? paintFor(el['stroke'], box) : null;
    stroke
      ?..style = PaintingStyle.stroke
      ..strokeWidth = sw;

    final path = Path();
    if (el['shape'] == 'circle') {
      path.addOval(box);
    } else if (el['shape'] == 'triangle') {
      path
        ..moveTo(box.left + box.width / 2, box.top)
        ..lineTo(box.right, box.bottom)
        ..lineTo(box.left, box.bottom)
        ..close();
    } else {
      final corners = radiusCorners(el['borderRadius']);
      if (corners.any((r) => r > 0)) {
        path.addRRect(_rrect(box, corners));
      } else {
        path.addRect(box);
      }
    }
    final strokePath = stroke == null ? null : _dashed(path, dashArrayFor(el['strokeDash'], el['strokeWidth']));
    _withShapeEffect(el, () {
      if (fill != null) c.drawPath(path, fill);
      if (stroke != null) c.drawPath(strokePath!, stroke);
    });
  }

  // ── text ──

  void _text(Map<String, dynamic> el) {
    final box = _box(el);
    if (truthy(el['background'])) _stickyPanel(el, box);

    final size = orNum(el['fontSize'], 16);
    final align = switch (el['textAlign']) {
      'center' => 'center',
      'right' => 'right',
      _ => 'left',
    };
    final pad = nnNum(el['padding'], 2);
    final base = fonts
        .styleFor(fontFamilyName(el['fontFamily']), fontWeightOf(el['fontWeight']), fontStyleOf(el['fontStyle']))
        .copyWith(fontSize: size, letterSpacing: orNum(el['letterSpacing'], 0));
    final fillValue = truthy(el['fill']) ? el['fill'] : (truthy(el['color']) ? el['color'] : '#111111');
    Paint fillPaint() => paintFor(fillValue, box) ?? (Paint()..color = const Color(0xFF111111));
    final effect = resolveTextEffect(el);

    final x = align == 'center'
        ? box.left + box.width / 2
        : align == 'right'
        ? box.left + box.width - pad
        : box.left + pad;

    final value = el['content'] is String
        ? el['content'] as String
        : (el['text'] is String ? el['text'] as String : '');

    // Word-wrap within the padded width; honour explicit newlines.
    final widths = <String, double>{};
    double measure(String s) => widths[s] ??= (TextPainter(
      text: TextSpan(text: s, style: base),
      textDirection: TextDirection.ltr,
    )..layout()).width;

    final lineMaxW = math.max(1.0, orNum(el['width'], 9999) - pad * 2);
    final lineH = size * orNum(el['lineHeight'], 1.3);
    final lines = <String>[];
    for (final para in value.split('\n')) {
      final words = para.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      var line = '';
      for (final word in words) {
        final test = line.isNotEmpty ? '$line $word' : word;
        if (measure(test) > lineMaxW && line.isNotEmpty) {
          lines.add(line);
          line = word;
        } else {
          line = test;
        }
      }
      lines.add(line);
    }

    // Sticky notes and Scraive text are top-aligned; other text is centred.
    final blockH = lines.length * lineH;
    final firstY = truthy(el['sticky']) || el['verticalAlign'] == 'top'
        ? box.top + pad + size * 0.85
        : box.top + math.max(pad, (box.height - blockH) / 2) + size * 0.85;
    double leftOf(double lw) => align == 'center' ? x - lw / 2 : (align == 'right' ? x - lw : x);

    // "Background" effect: a rounded, padded box hugging the union of the lines.
    final bgFx = effect?.background;
    if (bgFx != null && !truthy(el['background'])) {
      var minL = double.infinity;
      var maxR = double.negativeInfinity;
      for (final line in lines) {
        final lw = measure(line);
        minL = math.min(minL, leftOf(lw));
        maxR = math.max(maxR, leftOf(lw) + lw);
      }
      if (minL.isFinite) {
        final rect = Rect.fromLTWH(
          minL - bgFx.padX,
          firstY - size * 0.8 - bgFx.padY,
          maxR - minL + bgFx.padX * 2,
          blockH + size * 0.2 + bgFx.padY * 2,
        );
        c.drawRRect(_rrect(rect, List.filled(4, bgFx.radius)), Paint()..color = bgFx.color);
      }
    }

    var lineY = firstY;
    for (final line in lines) {
      if (line.isNotEmpty) {
        final left = leftOf(measure(line));
        _drawEffectLine(line, base, left, lineY, effect, fillPaint, fillValue);
        // Underline: a rule matched to the line's measured width.
        if (truthy(el['underline'])) {
          final uy = lineY + size * 0.12;
          final paint = fillPaint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, size * 0.06);
          c.drawLine(Offset(left, uy), Offset(left + measure(line), uy), paint);
        }
      }
      lineY += lineH;
    }
  }

  /// Paint one line with its alphabetic baseline at [baseline].
  void _paintLine(String line, TextStyle style, double left, double baseline) {
    final tp = TextPainter(
      text: TextSpan(text: line, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.paint(c, Offset(left, baseline - ascent));
    tp.dispose();
  }

  /// `drawEffectLine`: splice back copy, shadow layers (back to front), the
  /// outline (double width, since CSS text-stroke is centred), then the fill
  /// unless the text is hollow.
  void _drawEffectLine(
    String line,
    TextStyle base,
    double left,
    double y,
    TextEffect? effect,
    Paint Function() fillPaint,
    Object? fillValue,
  ) {
    void fill() => _paintLine(line, base.copyWith(foreground: fillPaint()), left, y);
    if (effect == null) {
      fill();
      return;
    }
    final back = effect.back;
    if (back != null) {
      _paintLine(line, base.copyWith(foreground: Paint()..color = back.color), left + back.dx, y + back.dy);
    }
    for (final s in effect.shadows.reversed) {
      _shadowPass(s, fill);
    }
    if (effect.strokeWidth != null) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = effect.strokeWidth! * 2
        ..strokeJoin = StrokeJoin.round
        ..color = effect.strokeColor ?? parseCssColor(fillValue) ?? const Color(0xFF111111);
      _paintLine(line, base.copyWith(foreground: paint), left, y);
    }
    if (!effect.hollow) fill();
  }

  /// Sticky-note background: a lifted paper panel (shadow, sheen, folded corner).
  void _stickyPanel(Map<String, dynamic> el, Rect box) {
    final rr = _rrect(box, radiusCorners(el['borderRadius']));
    final paper = paintFor(el['background'], box);
    if (paper != null) {
      _shadowPass(const EffectShadow(0, 8, 18, Color.fromRGBO(0, 0, 0, 0.18)), () => c.drawRRect(rr, paper));
      c.drawRRect(rr, paper);
    }
    c.save();
    c.clipRRect(rr);
    c.drawRect(
      box,
      Paint()
        ..shader = ui.Gradient.linear(
          box.topLeft,
          box.bottomRight,
          const [Color.fromRGBO(255, 255, 255, 0.4), Color.fromRGBO(255, 255, 255, 0), Color.fromRGBO(0, 0, 0, 0.07)],
          const [0, 0.4, 1],
        ),
    );
    final fold = math.max(14.0, (math.min(box.width, box.height) * 0.13).roundToDouble());
    final fx = box.right;
    final fy = box.bottom;
    c.drawPath(
      Path()
        ..moveTo(fx - fold, fy)
        ..lineTo(fx, fy - fold)
        ..lineTo(fx, fy)
        ..close(),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(fx - fold, fy - fold),
          Offset(fx, fy),
          const [Color.fromRGBO(0, 0, 0, 0), Color.fromRGBO(0, 0, 0, 0.16), Color.fromRGBO(0, 0, 0, 0.28)],
          const [0, 0.52, 1],
        ),
    );
    c.restore();
  }

  // ── table ──

  /// `drawTable`: the border colour fills the box, cells leave `borderWidth`
  /// lines showing, then each cell's text, clipped, vertically centred.
  void _table(Map<String, dynamic> el) {
    final box = _box(el);
    final rows = orNum(el['rows'], 0).toInt();
    final cols = orNum(el['cols'], 0).toInt();
    if (rows <= 0 || cols <= 0) return;
    final bw = nnNum(el['borderWidth'], 1);
    c.drawRect(box, Paint()..color = parseCssColor(el['borderColor']) ?? const Color(0xFFD1D5DB));

    List<double> fractions(Object? raw, int n) =>
        raw is List && raw.length == n ? [for (final f in raw) numOf(f) ?? 0] : List.filled(n, 1.0);
    final colFr = fractions(el['colFractions'], cols);
    final rowFr = fractions(el['rowFractions'], rows);
    final colSum = colFr.fold<double>(0, (a, b) => a + b);
    final rowSum = rowFr.fold<double>(0, (a, b) => a + b);
    if (colSum == 0 || rowSum == 0) return;
    final contentW = box.width - bw * (cols + 1);
    final contentH = box.height - bw * (rows + 1);
    final colW = [for (final f in colFr) f / colSum * contentW];
    final rowH = [for (final f in rowFr) f / rowSum * contentH];

    final size = orNum(el['fontSize'], 16);
    final family = fontFamilyName(el['fontFamily']);
    final align = el['align'] == 'center' || el['align'] == 'right' ? el['align'] : 'left';
    const pad = 10.0;
    final cells = el['cells'];
    final textColor = parseCssColor(el['textColor']) ?? const Color(0xFF111827);

    var cy0 = box.top + bw;
    for (var r = 0; r < rows; r++) {
      var cx0 = box.left + bw;
      for (var col = 0; col < cols; col++) {
        final cell = Rect.fromLTWH(cx0, cy0, colW[col], rowH[r]);
        final isHeader = truthy(el['headerRow']) && r == 0;
        final cellFill = isHeader
            ? (parseCssColor(el['headerFill']) ?? const Color(0xFFF3F4F6))
            : (parseCssColor(el['cellFill']) ?? const Color(0xFFFFFFFF));
        c.drawRect(cell, Paint()..color = cellFill);

        final row = cells is List && r < cells.length ? cells[r] : null;
        final text = row is List && col < row.length && row[col] != null ? '${row[col]}' : '';
        if (text.isNotEmpty) {
          final style = fonts
              .styleFor(family, isHeader ? FontWeight.w600 : FontWeight.w400, FontStyle.normal)
              .copyWith(fontSize: size, color: textColor);
          final tp = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          final tx = align == 'center'
              ? cell.center.dx - tp.width / 2
              : align == 'right'
              ? cell.right - pad - tp.width
              : cell.left + pad;
          c.save();
          c.clipRect(cell);
          tp.paint(c, Offset(tx, cell.center.dy - tp.height / 2));
          c.restore();
          tp.dispose();
        }
        cx0 += colW[col] + bw;
      }
      cy0 += rowH[r] + bw;
    }
  }

  // ── grid / frame ──

  /// `gridCellRects` (grids.js) — row-major cells with a uniform gap and
  /// optional per-track weights — each filled with its picture (cover) or the
  /// grey placeholder.
  void _grid(Map<String, dynamic> el) {
    final box = _box(el);
    final rows = math.max(1, orNum(el['rows'], 1).toInt());
    final cols = math.max(1, orNum(el['cols'], 1).toInt());
    final gap = orNum(el['gap'], 0);
    List<double> norm(Object? fr, int n) {
      if (fr is! List || fr.length != n) return List.filled(n, 1 / n);
      final vals = [for (final f in fr) numOf(f) ?? 0];
      final sum = vals.fold<double>(0, (a, b) => a + b);
      return [for (final v in vals) v / (sum == 0 ? 1 : sum)];
    }

    final colW = [for (final f in norm(el['colFr'], cols)) f * (box.width - gap * (cols - 1))];
    final rowH = [for (final f in norm(el['rowFr'], rows)) f * (box.height - gap * (rows - 1))];
    final cr = orNum(el['cellRadius'], 0);
    final cells = el['cells'];

    var y = box.top;
    for (var r = 0; r < rows; r++) {
      var x = box.left;
      for (var col = 0; col < cols; col++) {
        final rect = Rect.fromLTWH(x, y, colW[col], rowH[r]);
        c.save();
        if (cr > 0) {
          c.clipRRect(_rrect(rect, List.filled(4, cr)));
        } else {
          c.clipRect(rect);
        }
        final index = r * cols + col;
        final src = cells is List && index < cells.length ? (asMap(cells[index])?['src']) : null;
        if (src is String && src.isNotEmpty) {
          final img = images[src];
          if (img != null) _drawCover(img, rect);
        } else {
          c.drawRect(rect, Paint()..color = const Color(0xFFE5E7EB));
        }
        c.restore();
        x += colW[col] + gap;
      }
      y += rowH[r] + gap;
    }
  }

  /// A frame: a picture clipped to a shape mask (frames.js), or a grey
  /// placeholder when empty.
  void _frame(Map<String, dynamic> el) {
    final box = _box(el);
    final (viewBox, d) = frameGeo(el['shape']);
    if (box.width == 0 || box.height == 0) return;
    final m = Matrix4Values.translateScale(box.left, box.top, box.width / viewBox[0], box.height / viewBox[1]);
    c.save();
    c.clipPath(parseSvgPathData(d).transform(m));
    _flip(el, box);
    final src = el['src'];
    if (src is String && src.isNotEmpty) {
      final img = images[src];
      if (img != null) _drawCover(img, box);
    } else {
      c.drawRect(box, Paint()..color = const Color(0xFFE5E7EB));
    }
    c.restore();
  }

  // ── image ──

  void _flip(Map<String, dynamic> el, Rect box) {
    final fh = truthy(el['flipH']);
    final fv = truthy(el['flipV']);
    if (!fh && !fv) return;
    c.translate(box.center.dx, box.center.dy);
    c.scale(fh ? -1 : 1, fv ? -1 : 1);
    c.translate(-box.center.dx, -box.center.dy);
  }

  void _image(Map<String, dynamic> el) {
    final src = el['src'];
    final img = src is String ? images[src] : null;
    // A broken or unloadable image is skipped, as on the web.
    if (img == null) return;
    final box = _box(el);
    final corners = radiusCorners(el['borderRadius']);
    final rounded = corners.any((r) => r > 0);
    // Perspective and colour tint are not ported yet. Adjust / filter / shadow
    // are (image_filters.dart); the tone controls inside Adjust are not.
    final css = el['filter'] == null && el['adjust'] == null && el['imgShadow'] == null
        ? CssFilter.none
        : parseCssFilter(buildImageFilter(el));

    c.save();
    if (rounded) c.clipRRect(_rrect(box, corners));

    // The box fill behind the picture — what shows through a `contain` fit's
    // letterboxing or a cutout's removed background. Never filtered (the web
    // draws it with `ctx.filter = "none"`).
    final bgColor = el['backgroundColor'];
    if (bgColor is String && bgColor.trim().isNotEmpty && bgColor != 'transparent' && bgColor != 'none') {
      final p = paintFor(bgColor, box);
      if (p != null) c.drawRect(box, p);
    }

    if (css.isIdentity) {
      _picture(el, img, box);
      c.restore();
    } else {
      // The export sets `ctx.filter` and THEN clips, and a canvas applies the
      // filter to the drawing before the clip — so the blur bleed and the drop
      // shadow are cut to the rounded box (unlike the stage, where CSS rounds
      // the <img> first). Reproduce that: paint unclipped into a layer, then
      // mask it with the rounded rect.
      c.restore();
      if (rounded) c.saveLayer(null, Paint());
      _filtered(css, () => _picture(el, img, box));
      if (rounded) {
        // Clear everything outside the rounded box (a dstIn draw would only
        // touch pixels inside the shape, leaving the rest).
        c.save();
        c.clipPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(c.getLocalClipBounds().expandToInclude(box).inflate(1))
            ..addRRect(_rrect(box, corners)),
        );
        c.drawPaint(Paint()..blendMode = BlendMode.clear);
        c.restore();
        c.restore();
      }
    }

    // Border: stroked down the middle of its width, inset into the box (half
    // inside the edge, half over the picture), corners kept concentric.
    final bw = orNum(el['borderWidth'], 0);
    if (bw > 0) {
      final inset = bw / 2;
      final rect = Rect.fromLTWH(
        box.left + inset,
        box.top + inset,
        math.max(0, box.width - bw),
        math.max(0, box.height - bw),
      );
      final ring = [for (final r in corners) math.max(0.0, r - inset)];
      final path = Path();
      if (ring.any((r) => r > 0)) {
        path.addRRect(_rrect(rect, ring));
      } else {
        path.addRect(rect);
      }
      final dotted = el['borderDash'] == 'dotted';
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bw
        ..strokeCap = dotted ? StrokeCap.round : StrokeCap.butt
        ..color = parseCssColor(truthy(el['borderColor']) ? el['borderColor'] : '#ffffff') ?? const Color(0xFFFFFFFF);
      c.drawPath(_dashed(path, borderDashArray(el['borderDash'], bw)), paint);
    }
  }

  /// The picture itself: flips, cropRotate, then crop / contain / cover.
  void _picture(Map<String, dynamic> el, ui.Image img, Rect box) {
    c.save();
    _flip(el, box);

    // Straighten (a video's crop-mode Rotate, painted on its poster).
    final cropRotate = orNum(el['cropRotate'], 0);
    if (cropRotate != 0) {
      final k = _coverScale(box.width, box.height, cropRotate);
      c.translate(box.center.dx, box.center.dy);
      c.rotate(cropRotate * math.pi / 180);
      c.scale(k, k);
      c.translate(-box.center.dx, -box.center.dy);
    }

    final crop = asMap(el['crop']);
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    if (crop != null && _isCropped(crop)) {
      // The natural sub-rectangle stretched onto the box.
      final srcRect = Rect.fromLTWH(
        nnNum(crop['x'], 0) * iw,
        nnNum(crop['y'], 0) * ih,
        nnNum(crop['w'], 1) * iw,
        nnNum(crop['h'], 1) * ih,
      );
      c.drawImageRect(img, srcRect, box, _imagePaint());
    } else if (el['objectFit'] == 'contain') {
      _drawContain(img, box);
    } else {
      _drawCover(img, box);
    }
    c.restore();
  }

  /// `ctx.filter = <css>` around [draw]: the drop shadow first, then the
  /// drawing through the colour steps and blur.
  ///
  /// Filters run in the element's local space (the flip happens inside
  /// [draw], so a flipped picture's shadow keeps its offset direction).
  /// Blurs use decal tiling: a CSS blur samples transparency past the drawn
  /// pixels, so edges fade instead of smearing.
  void _filtered(CssFilter css, void Function() draw) {
    final shadow = css.dropShadow;
    if (shadow != null) {
      // The shadow is the silhouette of what the filter has produced so far:
      // its alpha (scaled by any opacity()) and its blur, blurred again.
      final sigma = math.sqrt(css.blurSigma * css.blurSigma + shadow.sigma * shadow.sigma);
      final color = shadow.color.withValues(alpha: shadow.color.a * css.alphaScale.clamp(0.0, 1.0));
      final paint = Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn);
      if (sigma > 0) paint.imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal);
      c.saveLayer(null, paint);
      c.translate(shadow.dx, shadow.dy);
      draw();
      c.restore();
    }

    // One ColorFilter per CSS function, chained, so each step clamps like the
    // browser's; then the blur.
    ui.ImageFilter? filter;
    for (final step in css.steps) {
      if (step.isIdentity) continue;
      final f = step.toColorFilter();
      filter = filter == null ? f : ui.ImageFilter.compose(outer: f, inner: filter);
    }
    if (css.blurSigma > 0) {
      final blur = ui.ImageFilter.blur(sigmaX: css.blurSigma, sigmaY: css.blurSigma, tileMode: TileMode.decal);
      filter = filter == null ? blur : ui.ImageFilter.compose(outer: blur, inner: filter);
    }
    if (filter == null) {
      draw();
      return;
    }
    c.saveLayer(null, Paint()..imageFilter = filter);
    draw();
    c.restore();
  }

  bool _isCropped(Map<String, dynamic> crop) =>
      nnNum(crop['x'], 0) > 0.0001 ||
      nnNum(crop['y'], 0) > 0.0001 ||
      nnNum(crop['w'], 1) < 0.9999 ||
      nnNum(crop['h'], 1) < 0.9999;

  Paint _imagePaint() => Paint()
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = true;

  /// object-fit: cover.
  void _drawCover(ui.Image img, Rect dst) {
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    if (dst.width == 0 || dst.height == 0) return;
    final ir = iw / ih;
    final tr = dst.width / dst.height;
    var src = Rect.fromLTWH(0, 0, iw, ih);
    if (ir > tr) {
      final sw = ih * tr;
      src = Rect.fromLTWH((iw - sw) / 2, 0, sw, ih);
    } else {
      final sh = iw / tr;
      src = Rect.fromLTWH(0, (ih - sh) / 2, iw, sh);
    }
    c.drawImageRect(img, src, dst, _imagePaint());
  }

  /// object-fit: contain — the whole picture, letterboxed and centred.
  void _drawContain(ui.Image img, Rect dst) {
    final scale = math.min(dst.width / img.width, dst.height / img.height);
    final w = img.width * scale;
    final h = img.height * scale;
    c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(dst.left + (dst.width - w) / 2, dst.top + (dst.height - h) / 2, w, h),
      _imagePaint(),
    );
  }
}

/// A column-major 4×4 matrix for "translate then scale" (`Path.transform`
/// takes a Float64List; this avoids pulling in vector_math for one matrix).
abstract final class Matrix4Values {
  static Float64List translateScale(double tx, double ty, double sx, double sy) =>
      Float64List.fromList([sx, 0, 0, 0, 0, sy, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1]);
}
