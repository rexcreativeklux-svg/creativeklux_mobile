import 'dart:math' as math;
import 'dart:ui';

import 'css_color.dart';
import 'js_values.dart';

/// Image Adjust / Filter / Shadow — port of the web's
/// `(lib)/design/imageAdjust.js` and `(lib)/design/filterLooks.js`, plus a
/// small CSS `filter` evaluator so the Dart renderer can paint what the web
/// hands to `ctx.filter`.
///
/// On the web every image setting resolves to ONE CSS filter string
/// ([buildImageFilter]); the stage puts it on the `<img>` and the exporter on
/// `ctx.filter`. Dart has no CSS filter engine, so [parseCssFilter] turns the
/// same string into a colour-matrix chain, a blur and a drop shadow, which the
/// renderer paints with layers.
///
/// Not ported: the tone controls (tint / highlights / shadows / whites /
/// blacks / vibrance, `toneFilter.js`). They need an SVG tone curve the web
/// adds to the DOM and references as `url(#…)`; [buildImageFilter] leaves them
/// out and [parseCssFilter] ignores any `url()`.

// ── Data ──

class ImageFilterPreset {
  const ImageFilterPreset(this.id, this.label, this.css);
  final String id;
  final String label;
  final String css;
}

class FilterLookGroup {
  const FilterLookGroup(this.id, this.label, this.looks);
  final String id;
  final String label;
  final List<ImageFilterPreset> looks;
}

class ImageAdjustment {
  const ImageAdjustment(this.key, this.label, this.min, this.max, this.def);
  final String key;
  final String label;
  final double min;
  final double max;
  final double def;
}

/// A drop-shadow preset: offset, blur and opacity (0–100, black). `none` has
/// no params (all null), like the web's `{ id: "none", label: "None" }`.
class ImageShadowPreset {
  const ImageShadowPreset(this.id, this.label, [this.x, this.y, this.blur, this.opacity]);
  final String id;
  final String label;
  final double? x;
  final double? y;
  final double? blur;
  final double? opacity;

  Map<String, dynamic>? get params => blur == null ? null : {'x': x, 'y': y, 'blur': blur, 'opacity': opacity};
}

/// IMAGE_FILTERS — the photo editor's presets.
const imageFilters = <ImageFilterPreset>[
  ImageFilterPreset('none', 'None', ''),
  ImageFilterPreset('noir', 'Noir', 'grayscale(1) contrast(1.45) brightness(0.92)'),
  ImageFilterPreset('fade', 'Fade', 'contrast(0.85) brightness(1.12) saturate(0.82) sepia(0.12)'),
  ImageFilterPreset('mono', 'Mono', 'grayscale(1) contrast(1.1)'),
  ImageFilterPreset('process', 'Process', 'contrast(1.2) saturate(1.55) hue-rotate(-12deg)'),
  ImageFilterPreset('tonal', 'Tonal', 'grayscale(1) contrast(1.22) brightness(1.05)'),
  ImageFilterPreset('chrome', 'Chrome', 'saturate(1.5) contrast(1.18) brightness(1.05)'),
  ImageFilterPreset('sepia', 'Sepia', 'sepia(0.78) contrast(1.05) brightness(1.02)'),
];

/// IMAGE_ADJUSTMENTS — slider ranges (−100…100; hue ±180; blur 0…40 px).
const imageAdjustments = <ImageAdjustment>[
  ImageAdjustment('brightness', 'Brightness', -100, 100, 0),
  ImageAdjustment('contrast', 'Contrast', -100, 100, 0),
  ImageAdjustment('saturation', 'Saturation', -100, 100, 0),
  ImageAdjustment('warmth', 'Warmth', -100, 100, 0),
  ImageAdjustment('hue', 'Hue', -180, 180, 0),
  ImageAdjustment('blur', 'Blur', 0, 40, 0),
];

/// IMAGE_SHADOWS — the "Shadows" strip presets.
const imageShadows = <ImageShadowPreset>[
  ImageShadowPreset('none', 'None'),
  ImageShadowPreset('drop', 'Drop', 0, 10, 14, 40),
  ImageShadowPreset('glow', 'Glow', 0, 0, 14, 50),
  ImageShadowPreset('soft', 'Soft', 0, 9, 14, 35),
  ImageShadowPreset('hard', 'Hard', 6, 6, 4, 55),
  ImageShadowPreset('bottom', 'Bottom', 0, 18, 22, 42),
  ImageShadowPreset('angled', 'Angled', 14, 14, 16, 38),
  ImageShadowPreset('left', 'Left', -14, 10, 16, 38),
  ImageShadowPreset('right', 'Right', 16, 10, 16, 38),
  ImageShadowPreset('top', 'Top', 0, -14, 16, 34),
  ImageShadowPreset('long', 'Long', 0, 30, 30, 28),
  ImageShadowPreset('subtle', 'Subtle', 0, 4, 8, 22),
  ImageShadowPreset('contact', 'Contact', 0, 3, 3, 52),
  ImageShadowPreset('diffuse', 'Diffuse', 0, 12, 34, 30),
  ImageShadowPreset('haze', 'Haze', 0, 0, 42, 22),
  ImageShadowPreset('drama', 'Drama', 10, 20, 10, 65),
  ImageShadowPreset('bottomRight', 'Bottom R', 18, 18, 18, 40),
  ImageShadowPreset('bottomLeft', 'Bottom L', -18, 18, 18, 40),
  ImageShadowPreset('topRight', 'Top R', 18, -16, 18, 36),
  ImageShadowPreset('topLeft', 'Top L', -18, -16, 18, 36),
  ImageShadowPreset('hardBottom', 'Hard btm', 0, 8, 2, 60),
  ImageShadowPreset('hardRight', 'Hard R', 10, 6, 2, 58),
  ImageShadowPreset('hardLeft', 'Hard L', -10, 6, 2, 58),
  ImageShadowPreset('block', 'Block', 8, 8, 0, 65),
  ImageShadowPreset('deep', 'Deep', 8, 16, 6, 72),
  ImageShadowPreset('longRight', 'Long R', 34, 12, 24, 26),
  ImageShadowPreset('longLeft', 'Long L', -34, 12, 24, 26),
  ImageShadowPreset('longTop', 'Long top', 0, -32, 24, 26),
  ImageShadowPreset('tall', 'Tall', 0, 44, 16, 30),
  ImageShadowPreset('stretch', 'Stretch', 40, 40, 20, 24),
  ImageShadowPreset('feather', 'Feather', 0, 10, 38, 24),
  ImageShadowPreset('mist', 'Mist', 0, 6, 46, 18),
  ImageShadowPreset('cloud', 'Cloud', 0, 14, 50, 20),
  ImageShadowPreset('lift', 'Lift', 0, -4, 24, 32),
  ImageShadowPreset('pillow', 'Pillow', 0, 0, 30, 26),
  ImageShadowPreset('glowSoft', 'Glow soft', 0, 0, 34, 38),
  ImageShadowPreset('glowStrong', 'Glow +', 0, 0, 20, 62),
  ImageShadowPreset('halo', 'Halo', 0, 0, 44, 30),
  ImageShadowPreset('card', 'Card', 0, 6, 12, 28),
  ImageShadowPreset('cardSoft', 'Card soft', 0, 10, 20, 22),
  ImageShadowPreset('sticker', 'Sticker', 3, 4, 6, 40),
  ImageShadowPreset('spotlight', 'Spotlight', 0, 10, 14, 50),
];

/// DEFAULT_SHADOW — seeds the fine controls when no shadow is set.
const defaultShadow = <String, Object>{'x': 0, 'y': 10, 'blur': 14, 'opacity': 40, 'color': '#000000'};

/// FILTER_LOOK_GROUPS (filterLooks.js) — Canva's named looks. Ids carry a
/// `look-` prefix so they can share `el.filter` with [imageFilters].
const filterLookGroups = <FilterLookGroup>[
  FilterLookGroup('natural', 'Natural', [
    ImageFilterPreset('look-fresco', 'Fresco', 'brightness(1.05) contrast(0.92) saturate(0.85) hue-rotate(-6deg)'),
    ImageFilterPreset('look-belvedere', 'Belvedere', 'contrast(1.08) saturate(0.9) sepia(0.1)'),
    ImageFilterPreset('look-flint', 'Flint', 'brightness(1.04) contrast(0.88) saturate(0.7)'),
    ImageFilterPreset('look-luna', 'Luna', 'brightness(1.06) contrast(0.9) saturate(0.8) hue-rotate(-10deg)'),
    ImageFilterPreset('look-aero', 'Aero', 'brightness(1.08) saturate(0.75) sepia(0.06)'),
    ImageFilterPreset('look-myst', 'Myst', 'contrast(0.85) brightness(0.9) saturate(0.6) hue-rotate(-8deg)'),
  ]),
  FilterLookGroup('warm', 'Warm', [
    ImageFilterPreset('look-bali', 'Bali', 'sepia(0.15) saturate(1.1) brightness(1.04)'),
    ImageFilterPreset('look-capri', 'Capri', 'sepia(0.2) saturate(1.15) hue-rotate(-8deg)'),
    ImageFilterPreset('look-latte', 'Latte', 'sepia(0.35) brightness(1.05) contrast(0.95)'),
    ImageFilterPreset('look-bronz', 'Bronz', 'sepia(0.5) saturate(1.4) brightness(1.05)'),
    ImageFilterPreset('look-sandi', 'Sandi', 'sepia(0.45) saturate(1.6) hue-rotate(-12deg)'),
    ImageFilterPreset('look-sangri', 'Sangri', 'sepia(0.3) saturate(1.3) hue-rotate(-25deg)'),
  ]),
  FilterLookGroup('cool', 'Cool', [
    ImageFilterPreset('look-scandi', 'Scandi', 'hue-rotate(-8deg) saturate(0.85) brightness(1.05)'),
    ImageFilterPreset('look-nordic', 'Nordic', 'hue-rotate(-14deg) saturate(0.8) contrast(1.05)'),
    ImageFilterPreset('look-astro', 'Astro', 'hue-rotate(-20deg) saturate(0.9) brightness(0.98)'),
    ImageFilterPreset(
      'look-arctic',
      'Arctic',
      'grayscale(0.35) sepia(0.3) hue-rotate(170deg) saturate(1.4) brightness(1.06)',
    ),
    ImageFilterPreset(
      'look-polar',
      'Polar',
      'grayscale(0.45) sepia(0.45) hue-rotate(180deg) saturate(1.8) brightness(1.05)',
    ),
    ImageFilterPreset(
      'look-tundra',
      'Tundra',
      'grayscale(0.3) sepia(0.2) hue-rotate(130deg) saturate(1.2) brightness(1.1)',
    ),
  ]),
  FilterLookGroup('vivid', 'Vivid', [
    ImageFilterPreset('look-chroma', 'Chroma', 'saturate(1.6) contrast(1.1)'),
    ImageFilterPreset('look-rustiq', 'Rustiq', 'saturate(1.4) sepia(0.15) contrast(1.1)'),
    ImageFilterPreset('look-eldar', 'Eldar', 'saturate(1.3) contrast(1.2) brightness(0.95)'),
    ImageFilterPreset('look-zeal', 'Zeal', 'saturate(1.8) hue-rotate(-6deg)'),
    ImageFilterPreset('look-aria', 'Aria', 'saturate(1.5) brightness(1.08)'),
    ImageFilterPreset('look-stark', 'Stark', 'contrast(1.35) saturate(1.3)'),
  ]),
  FilterLookGroup('soft', 'Soft', [
    ImageFilterPreset('look-aura', 'Aura', 'brightness(1.1) contrast(0.85) saturate(0.85)'),
    ImageFilterPreset('look-hazel', 'Hazel', 'sepia(0.2) contrast(0.88) brightness(1.06)'),
    ImageFilterPreset(
      'look-whimsi',
      'Whimsi',
      'grayscale(0.2) sepia(0.2) hue-rotate(-40deg) brightness(1.08) contrast(0.9)',
    ),
    ImageFilterPreset(
      'look-rose',
      'Rose',
      'grayscale(0.35) sepia(0.4) hue-rotate(-45deg) saturate(1.5) brightness(1.06) contrast(0.9)',
    ),
    ImageFilterPreset(
      'look-oceanic',
      'Oceanic',
      'grayscale(0.35) sepia(0.35) hue-rotate(80deg) saturate(1.1) contrast(0.88) brightness(1.04)',
    ),
    ImageFilterPreset(
      'look-nimbus',
      'Nimbus',
      'grayscale(0.35) sepia(0.4) hue-rotate(210deg) saturate(1.4) brightness(1.08) contrast(0.88)',
    ),
  ]),
  FilterLookGroup('vintage', 'Vintage', [
    ImageFilterPreset('look-vinto', 'Vinto', 'sepia(0.25) contrast(0.9) saturate(0.85)'),
    ImageFilterPreset('look-fade', 'Fade', 'contrast(0.8) brightness(1.1) saturate(0.75)'),
    ImageFilterPreset('look-antiq', 'Antiq', 'sepia(0.55) contrast(0.92) brightness(1.02)'),
    ImageFilterPreset('look-nostalg', 'Nostalg', 'sepia(0.35) saturate(1.2) contrast(0.9) brightness(1.05)'),
    ImageFilterPreset(
      'look-dream',
      'Dream',
      'grayscale(0.2) sepia(0.2) hue-rotate(160deg) brightness(1.12) contrast(0.85)',
    ),
    ImageFilterPreset('look-retro', 'Retro', 'grayscale(0.2) sepia(0.3) hue-rotate(50deg) contrast(1.1) saturate(1.1)'),
  ]),
  FilterLookGroup('mono', 'Mono', [
    ImageFilterPreset('look-classic', 'Classic', 'grayscale(1)'),
    ImageFilterPreset('look-ink', 'Ink', 'grayscale(1) contrast(1.3)'),
    ImageFilterPreset('look-noir', 'Noir', 'grayscale(1) contrast(1.5) brightness(0.9)'),
    ImageFilterPreset('look-film', 'Film', 'grayscale(1) contrast(0.85) brightness(1.08)'),
    ImageFilterPreset('look-newspaper', 'Newspaper', 'grayscale(1) contrast(1.1) brightness(0.8)'),
    ImageFilterPreset('look-slate', 'Slate', 'grayscale(1) sepia(0.2) hue-rotate(170deg) saturate(1.5)'),
  ]),
  FilterLookGroup('colorpop', 'Color Pop', [
    ImageFilterPreset('look-outrun', 'Outrun', 'sepia(0.6) saturate(2.4) hue-rotate(-15deg) contrast(1.1)'),
    ImageFilterPreset('look-heatwave', 'Heatwave', 'sepia(0.7) saturate(3) hue-rotate(-30deg)'),
    ImageFilterPreset(
      'look-amethyst',
      'Amethyst',
      'grayscale(1) sepia(0.4) hue-rotate(220deg) saturate(2) brightness(1.1)',
    ),
    ImageFilterPreset('look-minty', 'Minty', 'grayscale(0.5) sepia(0.5) hue-rotate(80deg) saturate(1.8)'),
    ImageFilterPreset('look-hibiscus', 'Hibiscus', 'grayscale(0.4) sepia(0.4) hue-rotate(150deg) saturate(1.6)'),
    ImageFilterPreset('look-poster', 'Poster', 'contrast(1.6) saturate(1.5)'),
    ImageFilterPreset('look-xpro-minus', 'X-Pro -', 'hue-rotate(-20deg) contrast(1.25) saturate(1.4) brightness(0.95)'),
    ImageFilterPreset('look-xpro-plus', 'X-Pro +', 'sepia(0.3) contrast(1.3) saturate(1.6) brightness(1.05)'),
  ]),
];

/// NO_LOOK — "None", shown first on its own.
const noLook = ImageFilterPreset('none', 'None', '');

/// FEATURED_LOOKS — the panel strip: None + the first five Natural looks.
final List<ImageFilterPreset> featuredLooks = [noLook, ...filterLookGroups[0].looks.take(5)];

final Map<String, ImageFilterPreset> _looksById = {
  for (final g in filterLookGroups)
    for (final l in g.looks) l.id: l,
};

/// `lookCssById`: the CSS for a look id, or '' for none / not a look.
String lookCssById(Object? id) => _looksById[id]?.css ?? '';

/// `shadowById`.
ImageShadowPreset? shadowById(Object? id) {
  for (final s in imageShadows) {
    if (s.id == id) return s;
  }
  return null;
}

/// `filterCssById`: an image preset's CSS, else a named look's, else ''.
String filterCssById(Object? id) {
  for (final f in imageFilters) {
    if (f.id == id) return f.css;
  }
  return lookCssById(id);
}

/// `resolveShadow`: custom params (`el.imgShadowParams`) win, else the named
/// preset's. Null when there's no shadow.
Map<String, dynamic>? resolveShadow(Map<String, dynamic>? el) {
  final id = el?['imgShadow'];
  if (!truthy(id) || id == 'none') return null;
  final custom = el!['imgShadowParams'];
  if (truthy(custom)) return asMap(custom) ?? const {};
  return shadowById(id)?.params;
}

// ── buildImageFilter ──

/// JS `Math.round(n * 1000) / 1000`.
double _r3(double n) => jsRound(n * 1000) / 1000;

/// A number as JS template literals print it (`1`, not `1.0`).
String jsNumberString(num n) {
  final d = n.toDouble();
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d > 0 ? 'Infinity' : '-Infinity';
  if (d == d.truncateToDouble() && d.abs() < 1e21) return d.toInt().toString();
  return d.toString();
}

/// A raw JSON value interpolated into a template string (`${a.hue}`).
String _raw(Object? v) => v is num ? jsNumberString(v) : '$v';

double _num(Object? v) => numOf(v) ?? double.nan;

/// `hexToRgba`: #rgb / #rrggbb → `rgba(r,g,b,a)` (alpha rounded to 3 places).
String hexToRgba(Object? hex, [double alpha = 1]) {
  var h = (truthy(hex) ? '$hex' : '#000000').replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  // parseInt(h, 16) reads the leading hex digits and stops at the first other.
  final digits = RegExp(r'^\s*[0-9a-fA-F]+').firstMatch(h)?.group(0)?.trim();
  final n = digits == null ? null : int.tryParse(digits, radix: 16);
  final a = jsNumberString(_r3(alpha));
  if (n == null) return 'rgba(0,0,0,$a)';
  return 'rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},$a)';
}

/// `shadowDropCss`: a CSS drop-shadow for {x, y, blur, opacity, color}.
/// [scale] < 1 shrinks it for small previews, as on the web.
String shadowDropCss(Map<String, dynamic>? sh, [double scale = 1]) {
  if (sh == null || sh['blur'] == null) return '';
  final x = _r3(_num(sh['x']) * scale);
  final y = _r3(_num(sh['y']) * scale);
  final blur = _num(sh['blur']);
  final b = scale < 1 ? math.max(0.5, blur * 0.35) : blur;
  final color = hexToRgba(truthy(sh['color']) ? sh['color'] : '#000000', _num(sh['opacity']) / 100);
  return 'drop-shadow(${jsNumberString(x)}px ${jsNumberString(y)}px ${jsNumberString(_r3(b))}px $color)';
}

/// `buildImageFilter(el)`: the element's filter preset, Adjust values and
/// shadow as one CSS filter string — the same string the web produces, except
/// that the tone controls (toneFilter.js `url(#…)`) are left out. '' when
/// nothing is set.
String buildImageFilter(Map<String, dynamic>? el) {
  final a = asMap(el?['adjust']) ?? const <String, dynamic>{};
  final parts = <String>[];

  final preset = filterCssById(el?['filter']);
  if (preset.isNotEmpty) parts.add(preset);

  String r3(double v) => jsNumberString(_r3(v));
  if (truthy(a['brightness'])) parts.add('brightness(${r3(1 + _num(a['brightness']) / 100)})');
  if (truthy(a['contrast'])) parts.add('contrast(${r3(1 + _num(a['contrast']) / 100)})');
  if (truthy(a['saturation'])) parts.add('saturate(${r3(1 + _num(a['saturation']) / 100)})');
  if (truthy(a['warmth'])) {
    // Warm → sepia + a touch more saturation; cool → a slight blue hue shift.
    final w = _num(a['warmth']);
    if (w > 0) {
      parts.add('sepia(${r3((w / 100) * 0.5)})');
      parts.add('saturate(${r3(1 + (w / 100) * 0.2)})');
    } else {
      parts.add('hue-rotate(${jsNumberString(jsRound(w * 0.35))}deg)');
      parts.add('saturate(${r3(1 + (w / 100) * 0.1)})');
    }
  }
  if (truthy(a['hue'])) parts.add('hue-rotate(${_raw(a['hue'])}deg)');
  // Tone (tint / highlights / shadows / whites / blacks / vibrance) would go
  // here on the web as an SVG `url(#…)` filter — not supported in Dart.
  if (truthy(a['blur'])) parts.add('blur(${_raw(a['blur'])}px)');

  final sp = resolveShadow(el);
  if (sp != null) parts.add(shadowDropCss(sp));

  return parts.join(' ');
}

// ── CSS filter evaluation ──

/// A 4×5 colour matrix, row-major, with the offset column NORMALISED (0…1),
/// i.e. the W3C Filter Effects form. [toFlutter] rescales the offsets to the
/// 0…255 that [ColorFilter.matrix] expects.
class CssColorMatrix {
  /// [values] must hold 20 entries.
  const CssColorMatrix(this.values);
  final List<double> values;

  static const identity = CssColorMatrix([1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]);

  bool get isIdentity {
    for (var i = 0; i < 20; i++) {
      if ((values[i] - identity.values[i]).abs() > 1e-9) return false;
    }
    return true;
  }

  /// `other` applied after this one (`other × this`).
  CssColorMatrix then(CssColorMatrix other) {
    final a = other.values;
    final b = values;
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var col = 0; col < 5; col++) {
        var s = col == 4 ? a[r * 5 + 4] : 0.0;
        for (var k = 0; k < 4; k++) {
          s += a[r * 5 + k] * b[k * 5 + col];
        }
        out[r * 5 + col] = s;
      }
    }
    return CssColorMatrix(out);
  }

  /// Applies the matrix to unpremultiplied RGBA in 0…1. With [clamp] (the
  /// default, like every filter primitive) the result is clamped to 0…1.
  List<double> applyRgba(List<double> rgba, {bool clamp = true}) {
    final out = List<double>.filled(4, 0);
    for (var r = 0; r < 4; r++) {
      var s = values[r * 5 + 4];
      for (var k = 0; k < 4; k++) {
        s += values[r * 5 + k] * rgba[k];
      }
      out[r] = clamp ? s.clamp(0.0, 1.0) : s;
    }
    return out;
  }

  /// [applyRgba] on a [Color].
  Color applyColor(Color c, {bool clamp = true}) {
    final o = applyRgba([c.r, c.g, c.b, c.a], clamp: clamp);
    return Color.from(alpha: o[3], red: o[0], green: o[1], blue: o[2]);
  }

  List<double> toFlutter() => [for (var i = 0; i < 20; i++) i % 5 == 4 ? values[i] * 255 : values[i]];

  ColorFilter toColorFilter() => ColorFilter.matrix(toFlutter());
}

/// A CSS `drop-shadow()`: offset, Gaussian sigma (CSS blur radius / 2) and colour.
class CssDropShadow {
  const CssDropShadow(this.dx, this.dy, this.sigma, this.color);
  final double dx;
  final double dy;
  final double sigma;
  final Color color;
}

/// A parsed CSS filter string.
///
/// * [steps] — one colour matrix per colour function, in order. Painting them
///   as a chain keeps the clamp a browser applies after every function
///   (`brightness(1.2) saturate(0.8)` loses highlights the single combined
///   [matrix] would keep).
/// * [matrix] — all [steps] composed into one (no intermediate clamping).
/// * [blurSigma] — the Gaussian sigma of all `blur()`s combined.
/// * [dropShadow] — the first `drop-shadow()`, if any.
///
/// Approximations (CSS applies each function to the previous one's output):
/// * Colour functions after a `blur()` are applied before it. Exact for blurs
///   of opaque interiors; edges differ only by clamping. [buildImageFilter]
///   always puts blur after the colour functions, so it is exact there.
/// * The drop shadow is the silhouette of the colour-filtered, blurred image
///   (its alpha only changes through `opacity()`, and blur widens it — both
///   are honoured). Functions AFTER a drop-shadow are treated as if they came
///   before it, so they don't touch the shadow; [buildImageFilter] always puts
///   the shadow last. Only the first drop-shadow is used.
/// * `url()` (SVG filter references) and unknown functions are ignored.
class CssFilter {
  const CssFilter({this.steps = const [], this.blurSigma = 0, this.dropShadow});

  final List<CssColorMatrix> steps;
  final double blurSigma;
  final CssDropShadow? dropShadow;

  static const none = CssFilter();

  CssColorMatrix get matrix => steps.fold(CssColorMatrix.identity, (m, s) => m.then(s));

  /// Product of the alpha scales (`opacity()`); the other functions keep alpha.
  double get alphaScale => steps.fold(1.0, (k, s) => k * s.values[18]);

  bool get isIdentity => blurSigma <= 0 && dropShadow == null && steps.every((s) => s.isIdentity);

  /// Applies the colour steps to one colour, clamping after each like CSS.
  Color applyToColor(Color c) => steps.fold(c, (acc, s) => s.applyColor(acc));
}

final _fnRe = RegExp(r'([a-zA-Z-]+)\(((?:[^()]|\([^()]*\))*)\)');

/// Parses a CSS `filter` value (see [CssFilter] for what is approximated).
/// Accepts numbers and percentages (`saturate(150%)`), `deg`/`rad`/`grad`/`turn`
/// angles, and `px` lengths. Invalid or unknown functions are skipped.
CssFilter parseCssFilter(String css) {
  final s = css.trim();
  if (s.isEmpty || s == 'none') return CssFilter.none;
  final steps = <CssColorMatrix>[];
  var blurVar = 0.0; // variances add when Gaussian blurs are chained
  CssDropShadow? shadow;
  for (final m in _fnRe.allMatches(s)) {
    final name = m.group(1)!.toLowerCase();
    final arg = m.group(2)!.trim();
    switch (name) {
      case 'brightness':
        steps.add(_brightness(_amount(arg, 1, clamp: false)));
      case 'contrast':
        steps.add(_contrast(_amount(arg, 1, clamp: false)));
      case 'saturate':
        steps.add(_saturate(_amount(arg, 1, clamp: false)));
      case 'grayscale':
        steps.add(_grayscale(_amount(arg, 1)));
      case 'sepia':
        steps.add(_sepia(_amount(arg, 1)));
      case 'invert':
        steps.add(_invert(_amount(arg, 1)));
      case 'opacity':
        steps.add(_opacity(_amount(arg, 1)));
      case 'hue-rotate':
        steps.add(_hueRotate(_angle(arg)));
      case 'blur':
        final r = arg.isEmpty ? 0.0 : (_length(arg) ?? 0);
        blurVar += r * r; // blur(r): the radius IS the standard deviation
      case 'drop-shadow':
        shadow ??= _dropShadow(arg);
      // url() and anything else: ignored.
    }
  }
  return CssFilter(steps: steps, blurSigma: math.sqrt(blurVar), dropShadow: shadow);
}

/// A `<number> | <percentage>` amount; missing → [def]. Negative is invalid in
/// CSS, so it's floored at 0. Grayscale/sepia/invert/opacity clamp at 1.
double _amount(String arg, double def, {bool clamp = true}) {
  if (arg.isEmpty) return def;
  final pct = arg.endsWith('%');
  var v = double.tryParse(pct ? arg.substring(0, arg.length - 1).trim() : arg);
  if (v == null) return def;
  if (pct) v /= 100;
  v = math.max(0, v);
  return clamp ? math.min(1, v) : v;
}

/// An angle in degrees; missing or a bare 0 → 0.
double _angle(String arg) {
  final m = RegExp(r'^(-?[\d.]+(?:e-?\d+)?)\s*(deg|rad|grad|turn)?$').firstMatch(arg.trim().toLowerCase());
  if (m == null) return 0;
  final v = double.tryParse(m.group(1)!) ?? 0;
  switch (m.group(2)) {
    case 'rad':
      return v * 180 / math.pi;
    case 'grad':
      return v * 0.9;
    case 'turn':
      return v * 360;
    default:
      return v;
  }
}

/// A length in px (unitless only for 0 in CSS; accepted here too).
double? _length(String token) {
  final m = RegExp(r'^(-?[\d.]+(?:e-?\d+)?)(px)?$').firstMatch(token.trim().toLowerCase());
  return m == null ? null : double.tryParse(m.group(1)!);
}

/// `drop-shadow(<color>? <x> <y> <blur>? <color>?)`.
CssDropShadow? _dropShadow(String arg) {
  // Split on whitespace outside parentheses, so `rgba(0, 0, 0, .4)` stays whole.
  final tokens = <String>[];
  var depth = 0;
  final buf = StringBuffer();
  for (final ch in arg.split('')) {
    if (ch == '(') depth++;
    if (ch == ')') depth--;
    if (depth == 0 && ch.trim().isEmpty) {
      if (buf.isNotEmpty) tokens.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  if (buf.isNotEmpty) tokens.add(buf.toString());

  final lengths = <double>[];
  Color? color;
  for (final t in tokens) {
    final len = _length(t);
    if (len != null) {
      lengths.add(len);
    } else {
      color ??= parseCssColor(t);
    }
  }
  if (lengths.length < 2) return null;
  final blur = lengths.length > 2 ? math.max(0.0, lengths[2]) : 0.0;
  // No colour → `currentcolor`; black is what an <img> context resolves to.
  return CssDropShadow(lengths[0], lengths[1], blur / 2, color ?? const Color(0xFF000000));
}

// The W3C Filter Effects matrices (https://www.w3.org/TR/filter-effects-1/).

CssColorMatrix _rgb(List<double> m3, [double offset = 0]) => CssColorMatrix([
  m3[0], m3[1], m3[2], 0, offset, //
  m3[3], m3[4], m3[5], 0, offset,
  m3[6], m3[7], m3[8], 0, offset,
  0, 0, 0, 1, 0,
]);

CssColorMatrix _brightness(double a) => _rgb([a, 0, 0, 0, a, 0, 0, 0, a]);

CssColorMatrix _contrast(double a) => _rgb([a, 0, 0, 0, a, 0, 0, 0, a], 0.5 - 0.5 * a);

CssColorMatrix _invert(double a) => _rgb([1 - 2 * a, 0, 0, 0, 1 - 2 * a, 0, 0, 0, 1 - 2 * a], a);

CssColorMatrix _opacity(double a) => CssColorMatrix([1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, a, 0]);

CssColorMatrix _saturate(double s) => _rgb([
  0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, //
  0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s,
  0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s,
]);

CssColorMatrix _grayscale(double a) {
  final g = 1 - a;
  return _rgb([
    0.2126 + 0.7874 * g, 0.7152 - 0.7152 * g, 0.0722 - 0.0722 * g, //
    0.2126 - 0.2126 * g, 0.7152 + 0.2848 * g, 0.0722 - 0.0722 * g,
    0.2126 - 0.2126 * g, 0.7152 - 0.7152 * g, 0.0722 + 0.9278 * g,
  ]);
}

CssColorMatrix _sepia(double a) {
  final g = 1 - a;
  return _rgb([
    0.393 + 0.607 * g, 0.769 - 0.769 * g, 0.189 - 0.189 * g, //
    0.349 - 0.349 * g, 0.686 + 0.314 * g, 0.168 - 0.168 * g,
    0.272 - 0.272 * g, 0.534 - 0.534 * g, 0.131 + 0.869 * g,
  ]);
}

CssColorMatrix _hueRotate(double deg) {
  final r = deg * math.pi / 180;
  final c = math.cos(r);
  final s = math.sin(r);
  return _rgb([
    0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, //
    0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283,
    0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072,
  ]);
}
