import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';

import '../../../core/design/design_assets.dart';
import '../../../core/design/effects.dart';
import '../../../core/design/js_values.dart';
import '../editor_sheets.dart' show cssFontFamily, editorFonts;

/// Design-Editor's text styling → this editor's text fields — port of the
/// web's `panels/text/textStyle.js`.
///
/// The Text library's templates and effects are Design-Editor's data, which
/// describes text in its own vocabulary: a shadow, an outline, a background
/// plate, a stack of outlines, a 3D extrude — all at once. A text element here
/// has ONE `textEffect` (see core/design/effects.dart), so the most defining
/// one wins: a plate changes the whole block, an extrude or an outline changes
/// every glyph, a shadow is the subtlest. Params are back-solved from the
/// effects' size-relative formulas, so they scale with the text.
///
/// Nothing here changes how text is drawn — it only writes fields the renderer
/// already reads.

/// Families that should fall back to a script face rather than a sans.
const _scriptFamilies = {
  'Alex Brush', 'Allura', 'Great Vibes', 'Kaushan Script', 'Pacifico', 'Parisienne', //
  'Pinyon Script', 'Sacramento', 'Satisfy', 'Yellowtail', 'Caveat', 'Kalam',
  'Patrick Hand', 'Permanent Marker', 'Rock Salt', 'Shadows Into Light',
};
const _serifFamilies = {
  'Bodoni Moda', 'Cormorant Garamond', 'DM Serif Display', 'Libre Baskerville', 'Lora', //
  'Playfair Display', 'Prata', 'Marcellus', 'Italiana', 'Abril Fatface', 'Bevan', 'Alfa Slab One',
};

/// "Anton" → "'Anton', sans-serif" — the CSS family string a text element
/// stores. A family the font list knows uses its exact string, so the font
/// picker shows it as the active font.
String? kluxFamily(Object? name) {
  if (name is! String || name.isEmpty) return null;
  if (editorFonts.contains(name)) return cssFontFamily(name);
  final generic = _scriptFamilies.contains(name)
      ? 'cursive'
      : _serifFamilies.contains(name)
      ? 'serif'
      : 'sans-serif';
  return "'$name', $generic";
}

/// Neither renderer has a text case — it's baked into the words.
Object? transformed(Object? content, Object? mode) {
  if (content is! String || mode == null || mode == '' || mode == 'none') return content;
  if (mode == 'uppercase') return content.toUpperCase();
  if (mode == 'lowercase') return content.toLowerCase();
  if (mode == 'capitalize') return content.replaceAllMapped(RegExp(r'\b\w'), (m) => m[0]!.toUpperCase());
  return content;
}

/// JS `Math.round(n * 100) / 100`.
double round2(double n) => jsRound(n * 100) / 100;

int _clamp100(double n) => math.max(0, math.min(100, jsRound(n)));
bool _isClear(Object? c) => !truthy(c) || c == 'transparent' || c == 'none';

/// A CSS colour as a hex and an alpha — text effects take them separately.
({String hex, double alpha}) splitColor(Object? color) {
  final c = (truthy(color) ? '$color' : '#000000').trim();
  final hex = RegExp(r'^#([0-9a-f]{3}|[0-9a-f]{6})([0-9a-f]{2})?$', caseSensitive: false).firstMatch(c);
  if (hex != null) {
    final a = hex[2] != null ? int.parse(hex[2]!, radix: 16) / 255 : 1.0;
    return (hex: '#${hex[1]}', alpha: a);
  }
  final inner = RegExp(r'^rgba?\(([^)]+)\)', caseSensitive: false).firstMatch(c)?[1];
  if (inner != null) {
    // parseFloat: leading number, junk after it ignored; none → NaN.
    final rgb = inner.split(',').map((s) {
      final m = RegExp(r'^\s*[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?').firstMatch(s);
      return m == null ? double.nan : double.parse(m[0]!.trim());
    }).toList();
    if (rgb.length >= 3) {
      final h = rgb
          .take(3)
          .map((v) => (v.isNaN ? 0 : math.max(0, math.min(255, jsRound(v)))).toRadixString(16).padLeft(2, '0'))
          .join();
      return (hex: '#$h', alpha: rgb.length > 3 ? rgb[3] : 1.0);
    }
  }
  return (hex: c, alpha: 1.0);
}

/// A pixel shadow → the "shadow" effect's direction / offset / blur params.
Map<String, dynamic> _shadowParams(Map<String, dynamic> shadow, double size) {
  final dx = numOf(shadow['offsetX']) ?? 0;
  final dy = nnNum(shadow['offsetY'], 4);
  final split = splitColor(truthy(shadow['color']) ? shadow['color'] : 'rgba(0,0,0,0.25)');
  return {
    'color': split.hex,
    'direction': jsRound(math.atan2(dy, dx) * 180 / math.pi),
    'offset': _clamp100(math.sqrt(dx * dx + dy * dy) / (size * 0.5) * 100),
    'blur': _clamp100(nnNum(shadow['blur'], 4) / (size * 0.8) * 100),
    'transparency': _clamp100((1 - split.alpha) * 100),
  };
}

/// The one `textEffect` that best stands for a Design-Editor style, and the
/// fill to go with it (hollow text keeps its outline colour as its fill, since
/// that's what the renderer strokes hollow text with).
///
/// [s]: `{fontSize, fill, textShadow, textStroke, backgroundColor, cornerRadius,
/// padding, outlines, extrude, plate}` — px at fontSize.
({Object? fill, Map<String, dynamic>? textEffect}) effectFrom(Map<String, dynamic> s) {
  final size = orNum(s['fontSize'], 16);
  final fill = s['fill'];
  final plate = asMap(s['plate']);

  // A plate behind the words.
  final plateColor = truthy(plate?['fill'])
      ? plate!['fill']
      : (!_isClear(s['backgroundColor']) ? s['backgroundColor'] : null);
  if (plateColor != null) {
    final split = splitColor(plateColor);
    final padX = plate != null ? nnNum(plate['padX'], 0.3) : nnNum(s['padding'], 0) / size;
    final roundness = plate != null
        ? (plate['shape'] == 'pill' ? 100.0 : 25.0)
        : nnNum(s['cornerRadius'], 0) / (size * 0.6) * 100;
    return (
      fill: fill,
      textEffect: {
        'type': 'background',
        'color': split.hex,
        'transparency': _clamp100((1 - split.alpha) * 100),
        'roundness': _clamp100(roundness),
        'spread': _clamp100((padX - 0.18) / 0.5 * 100),
      },
    );
  }

  // A 3D edge — a hard shadow as deep as the extrude.
  final extrude = asMap(s['extrude']);
  if (truthy(extrude?['depth'])) {
    return (
      fill: fill,
      textEffect: {
        'type': 'shadow',
        'color': splitColor(extrude!['color']).hex,
        'direction': jsRound(nnNum(extrude['angle'], 45)),
        'offset': _clamp100(numOf(extrude['depth'])! / (size * 0.5) * 100),
        'blur': 0,
        'transparency': 0,
      },
    );
  }

  // An outline — a single stroke, or the outermost of a stack.
  final textStroke = asMap(s['textStroke']);
  final outlines = s['outlines'] is List ? s['outlines'] as List : const [];
  final (double, Object?)? stroke = truthy(textStroke?['enabled']) && (numOf(textStroke!['width']) ?? 0) > 0
      ? (numOf(textStroke['width'])!, textStroke['color'])
      : outlines.isNotEmpty
      ? ((numOf(asMap(outlines.first)?['width']) ?? double.nan) / 2, asMap(outlines.first)?['color'])
      : null;
  final textShadow = asMap(s['textShadow']);
  final shadow = truthy(textShadow?['enabled']) ? textShadow : null;

  if (stroke != null && _isClear(fill)) {
    final strokeHex = splitColor(stroke.$2).hex;
    final thickness = _clamp100(stroke.$1 / (size * 0.06) * 100);
    if (shadow != null) {
      final p = _shadowParams(shadow, size);
      return (
        fill: strokeHex,
        textEffect: {
          'type': 'splice',
          'thickness': thickness,
          'offset': p['offset'],
          'direction': p['direction'],
          'color': p['color'],
        },
      );
    }
    return (fill: strokeHex, textEffect: {'type': 'hollow', 'thickness': thickness});
  }
  if (stroke != null) {
    return (
      fill: fill,
      textEffect: {
        'type': 'outline',
        'color': splitColor(stroke.$2).hex,
        'thickness': _clamp100(stroke.$1 / (size * 0.07) * 100),
      },
    );
  }
  if (shadow != null) return (fill: fill, textEffect: {'type': 'shadow', ..._shadowParams(shadow, size)});
  return (fill: fill, textEffect: null);
}

// ── Measuring ────────────────────────────────────────────────────────────────

/// The faces the Text library measures with. Boxes hug their words, so they
/// must be measured in the face they're set in — the same google_fonts styles
/// the renderer paints with (see DesignFonts). Listeners hear when a batch of
/// faces lands, so previews re-measure (the web's `useFontsVersion`).
class TextLibraryFonts extends ChangeNotifier {
  final DesignFonts _fonts = DesignFonts();
  final Set<(String, FontWeight, FontStyle)> _requested = {};

  /// Bumped whenever faces land.
  int version = 0;

  /// The (family, weight, style) a text element is set in.
  static (String, FontWeight, FontStyle) faceOf(Map<String, dynamic> el) =>
      (fontFamilyName(el['fontFamily']), fontWeightOf(el['fontWeight']), fontStyleOf(el['fontStyle']));

  /// Load whatever of [faces] isn't loaded yet; completes once they have
  /// (or failed and fell back — DesignFonts never throws).
  Future<void> ensure(Iterable<(String, FontWeight, FontStyle)> faces) async {
    final fresh = faces.where(_requested.add).toList();
    if (fresh.isEmpty) return _pending ?? Future.value();
    final load = _fonts.load(fresh).then((_) {
      version++;
      notifyListeners();
    });
    _pending = Future.wait([?_pending, load]);
    return _pending;
  }

  Future<void>? _pending;

  /// The face for an element, sized and spaced as the renderer sets it.
  TextStyle styleFor(Map<String, dynamic> el) {
    final (family, w, s) = faceOf(el);
    return _fonts
        .styleFor(family, w, s)
        .copyWith(fontSize: orNum(el['fontSize'], 16), letterSpacing: numOf(el['letterSpacing']) ?? 0);
  }
}

/// The one set of measuring faces the library shares.
final textLibraryFonts = TextLibraryFonts();

/// A text box hugging its words gets this much slack, so a face a hair wider doesn't wrap.
const _hugSlack = 1.04;

/// A line's width in [style] — letter spacing included, as the renderer
/// measures it (the web adds `letterSpacing × characters` to measureText).
double _lineWidth(String line, TextStyle style) {
  if (line.isEmpty) return 0;
  final tp = TextPainter(
    text: TextSpan(text: line, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

/// Word-wrap one paragraph to a width, as the DOM's pre-wrap would.
int _wrapCount(String para, double maxWidth, TextStyle style) {
  var lines = 0;
  var line = '';
  for (final word in para.split(' ')) {
    final next = line.isNotEmpty ? '$line $word' : word;
    if (line.isNotEmpty && _lineWidth(next, style) > maxWidth) {
      lines++;
      line = word;
    } else {
      line = next;
    }
  }
  return lines + 1;
}

/// How far an effect's ink reaches past the glyphs — a shadow's offset and
/// blur, an outline. The box has to make room for it.
double _inkReach(Map<String, dynamic> el) {
  final d = resolveTextEffect(el);
  if (d == null) return 0;
  var reach = 0.0;
  for (final s in d.shadows) {
    reach = math.max(reach, math.max(s.dx.abs(), s.dy.abs()) + s.blur);
  }
  if (d.back != null) reach = math.max(reach, math.max(d.back!.dx.abs(), d.back!.dy.abs()));
  if (d.strokeWidth != null) reach = math.max(reach, d.strokeWidth! / 2);
  return reach.ceilToDouble();
}

/// The box a text element needs for its words — measured with the face it's
/// set in, grown for its effect's ink and plate.
///
/// [fixedWidth] wraps to that width instead of hugging the words. [styleOf]
/// overrides the measuring face (tests); it defaults to [textLibraryFonts].
({double width, double height, double padding}) measureTextBox(
  Map<String, dynamic> el, {
  double? fixedWidth,
  TextStyle Function(Map<String, dynamic> el)? styleOf,
}) {
  final size = orNum(el['fontSize'], 16);
  final lh = orNum(el['lineHeight'], 1.3);
  final style = (styleOf ?? textLibraryFonts.styleFor)(el);
  final paras = '${el['content'] ?? ''}'.split('\n');
  final basePad = nnNum(el['basePadding'], 4) + _inkReach(el);
  final plate = resolveTextEffect(el)?.background;
  final padX = basePad + (plate?.padX ?? 0);
  final padY = basePad + (plate?.padY ?? 0);

  double contentWidth;
  var lines = paras.length;
  if (fixedWidth != null && fixedWidth != 0) {
    contentWidth = fixedWidth - padX * 2;
    lines = paras.fold(0, (n, p) => n + _wrapCount(p, contentWidth, style));
  } else {
    contentWidth = paras.map((p) => _lineWidth(p, style)).reduce(math.max) * _hugSlack;
  }

  return (
    width: (contentWidth + padX * 2).ceilToDouble(),
    height: (lines * size * lh + padY * 2).ceilToDouble(),
    padding: basePad,
  );
}
