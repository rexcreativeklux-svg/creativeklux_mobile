import 'dart:math' as math;
import 'dart:ui';

import 'css_color.dart';
import 'js_values.dart';

/// Ports of the web's `textEffects.js` (resolveTextEffect) and
/// `shapeEffects.js` (resolveShapeEffect): an effect stored on an element as
/// `{type, ...0–100 params, color}` → concrete shadow / stroke / panel sizes in
/// px, scaled to the font size (text) or the shape's smaller side (shapes).

class EffectShadow {
  const EffectShadow(this.dx, this.dy, this.blur, this.color);
  final double dx;
  final double dy;

  /// Canvas `shadowBlur` units (the Gaussian sigma is half of this).
  final double blur;
  final Color color;
}

class TextEffect {
  const TextEffect({
    this.shadows = const [],
    this.strokeWidth,
    this.strokeColor,
    this.hollow = false,
    this.back,
    this.background,
  });

  final List<EffectShadow> shadows;
  final double? strokeWidth;
  final Color? strokeColor;

  /// Hollow / splice: stroke only, no glyph fill.
  final bool hollow;

  /// Splice: a solid, offset copy behind the glyphs (blur unused).
  final EffectShadow? back;
  final TextBackground? background;
}

class TextBackground {
  const TextBackground(this.color, this.radius, this.padX, this.padY);
  final Color color;
  final double radius;
  final double padX;
  final double padY;
}

/// `rgba(hex, a)` from textEffects.js. The web only reads hex here; any CSS
/// colour is accepted so an rgb() effect colour doesn't collapse to black.
Color _rgba(Object? color, double a) {
  final c = parseCssColor(color) ?? const Color(0xFF000000);
  return c.withValues(alpha: a.clamp(0.0, 1.0));
}

double _n(Object? v, double d) => numOf(v) ?? d;

const _textEffectColor = {
  'shadow': '#000000',
  'splice': '#8b5cf6',
  'outline': '#000000',
  'echo': '#b1b1b1',
  'glow': '#ffffff',
  'background': '#000000',
};

({double dx, double dy}) _vec(double deg, double dist) {
  final r = deg * math.pi / 180;
  return (dx: math.cos(r) * dist, dy: math.sin(r) * dist);
}

/// The element's text effect, resolved; null when there is none.
TextEffect? resolveTextEffect(Map<String, dynamic> el) {
  final e = asMap(el['textEffect']);
  final type = e?['type'];
  if (e == null || !truthy(type) || type == 'none') return null;

  final size = orNum(el['fontSize'], 16);
  final fill = truthy(el['fill']) ? el['fill'] : (truthy(el['color']) ? el['color'] : '#111111');
  final color = truthy(e['color']) ? e['color'] : (_textEffectColor[type] ?? '#000000');

  switch (type) {
    case 'shadow':
      final v = _vec(_n(e['direction'], -45), _n(e['offset'], 50) / 100 * size * 0.5);
      final blur = _n(e['blur'], 20) / 100 * size * 0.8;
      final a = 1 - _n(e['transparency'], 40) / 100;
      return TextEffect(shadows: [EffectShadow(v.dx, v.dy, blur, _rgba(color, a))]);
    case 'lift':
      final i = _n(e['intensity'], 50) / 100;
      return TextEffect(
        shadows: [
          EffectShadow(
            0,
            size * 0.06 * (0.6 + i),
            size * (0.14 + 0.3 * i),
            Color.fromRGBO(0, 0, 0, ((0.18 + 0.32 * i) * 100).round() / 100),
          ),
        ],
      );
    case 'hollow':
      final width = math.max(0.5, _n(e['thickness'], 50) / 100 * size * 0.06);
      return TextEffect(strokeWidth: width, strokeColor: parseCssColor(fill), hollow: true);
    case 'splice':
      final width = math.max(0.5, _n(e['thickness'], 50) / 100 * size * 0.06);
      final v = _vec(_n(e['direction'], -45), _n(e['offset'], 50) / 100 * size * 0.5);
      return TextEffect(
        strokeWidth: width,
        strokeColor: parseCssColor(fill),
        hollow: true,
        back: EffectShadow(v.dx, v.dy, 0, parseCssColor(color) ?? const Color(0xFF000000)),
      );
    case 'outline':
      final width = math.max(0.5, _n(e['thickness'], 50) / 100 * size * 0.07);
      return TextEffect(strokeWidth: width, strokeColor: parseCssColor(color) ?? const Color(0xFF000000));
    case 'echo':
      final v = _vec(_n(e['direction'], -45), _n(e['offset'], 50) / 100 * size * 0.5);
      return TextEffect(
        shadows: [
          EffectShadow(v.dx * 0.5, v.dy * 0.5, 0, _rgba(color, 0.5)),
          EffectShadow(v.dx, v.dy, 0, _rgba(color, 0.3)),
        ],
      );
    case 'glow':
      final b = size * (0.15 + 0.5 * (_n(e['intensity'], 50) / 100));
      return TextEffect(
        shadows: [EffectShadow(0, 0, b, _rgba(color, 0.9)), EffectShadow(0, 0, b * 2, _rgba(color, 0.6))],
      );
    case 'neon':
      final b = size * (0.15 + 0.5 * (_n(e['intensity'], 50) / 100));
      return TextEffect(
        shadows: [EffectShadow(0, 0, b, _rgba(fill, 0.9)), EffectShadow(0, 0, b * 2.2, _rgba(fill, 0.55))],
      );
    case 'background':
      final a = 1 - _n(e['transparency'], 0) / 100;
      final spread = _n(e['spread'], 30) / 100 * size * 0.5;
      return TextEffect(
        background: TextBackground(
          _rgba(color, a),
          _n(e['roundness'], 50) / 100 * size * 0.6,
          spread + size * 0.18,
          spread + size * 0.05,
        ),
      );
  }
  return null;
}

const _shapeEffectColor = {'drop': '#000000', 'echo': '#b1b1b1', 'glow': '#8b5cf6'};

/// The shadow layers for an element's `shapeEffect`; empty when there is none.
List<EffectShadow> resolveShapeEffect(Map<String, dynamic> el) {
  final e = asMap(el['shapeEffect']);
  final type = e?['type'];
  if (e == null || !truthy(type) || type == 'none') return const [];

  // The smaller side: on a long thin bar the width would throw the shadow far.
  final size = math.max(8.0, math.min(orNum(el['width'], 0), orNum(el['height'], 0)));
  final color = truthy(e['color']) ? e['color'] : (_shapeEffectColor[type] ?? '#000000');

  switch (type) {
    case 'drop':
      final v = _vec(_n(e['direction'], 45), _n(e['offset'], 40) / 100 * size * 0.25);
      final blur = _n(e['blur'], 30) / 100 * size * 0.4;
      final alpha = 1 - _n(e['transparency'], 60) / 100;
      return [EffectShadow(v.dx, v.dy, blur, _rgba(color, alpha))];
    case 'echo':
      final dist = _n(e['offset'], 50) / 100 * size * 0.3;
      final a = _vec(_n(e['direction'], 45), dist);
      final b = _vec(_n(e['direction'], 45), dist * 2);
      return [EffectShadow(a.dx, a.dy, 0, _rgba(color, 0.5)), EffectShadow(b.dx, b.dy, 0, _rgba(color, 0.25))];
    case 'glow':
      final i = _n(e['intensity'], 50) / 100;
      final blur = size * (0.06 + 0.34 * i);
      return [
        EffectShadow(0, 0, blur * 0.5, _rgba(color, 0.3 + 0.5 * i)),
        EffectShadow(0, 0, blur, _rgba(color, 0.2 + 0.4 * i)),
      ];
  }
  return const [];
}
