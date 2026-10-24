import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/media.dart';
import 'app_colors.dart';
import 'skins_data.dart';

export 'skins_data.dart' show skinSpecs;

/// Skins — whole-app appearance packs (a palette + a wallpaper), and the photo
/// wallpaper that can sit behind any of them. Port of the web's
/// `appearance/skins.js`, `appearance/wallpapers.js` and `app/skins.css`.
///
/// The web re-points CSS variables so every `bg-surface` / `text-gray-*` /
/// `bg-blue-600` follows. Here the same happens through [AppColors]: a skin's
/// seven authored values become the whole gray ramp (mixed in oklab, exactly
/// as skins.css does), and its accent replaces the app blue.
///
/// The skin data itself is GENERATED from the web's files —
/// `node tool/skins/gen.mjs <web repo> lib/core/theme/skins_data.dart`.

const defaultSkinId = 'default';

/// One skin in the line-up. `default` ("None") has no palettes: it is the
/// absence of a skin, so the app as designed can't drift from itself.
class SkinSpec {
  const SkinSpec({required this.id, required this.label, this.light, this.dark});

  final String id;
  final String label;
  final SkinPalette? light;
  final SkinPalette? dark;

  SkinPalette? palette(bool isDark) => isDark ? dark : light;
}

/// The seven authored values (skins.css header) plus the art.
class SkinPalette {
  const SkinPalette({
    required this.base,
    required this.page,
    required this.surface,
    required this.ink,
    required this.accent,
    required this.accentStrong,
    required this.accentSoft,
    required this.layers,
    this.image,
  });

  /// Opaque — every mix resolves against it.
  final Color base;

  /// `bg-page`: translucent, the window the art is seen through.
  final Color page;

  /// `bg-surface`: translucent too, but only slightly.
  final Color surface;
  final Color ink;
  final Color accent;
  final Color accentStrong;
  final Color accentSoft;

  /// Gradient art, TOP layer first (CSS order).
  final List<SkinLayer> layers;

  /// An illustrated plate (SVG asset) painted over the gradients.
  final String? image;
}

/// The gradient forms skins.css uses — nothing more.
sealed class SkinLayer {
  const SkinLayer();

  const factory SkinLayer.linear({required double angle, required List<Color> colors, required List<double> stops}) =
      _Linear;

  /// An ellipse: radii and centre as fractions of the box (`W% H% at X% Y%`).
  const factory SkinLayer.radial({
    required double rx,
    required double ry,
    required double cx,
    required double cy,
    required List<Color> colors,
    required List<double> stops,
  }) = _Radial;

  /// A dot centred in every tile (star fields, petal drifts).
  const factory SkinLayer.dots({
    required Color color,
    required double radius,
    required double tileWidth,
    required double tileHeight,
  }) = _Dots;

  /// A thin rule at the start of every tile (grids).
  const factory SkinLayer.lines({
    required double angle,
    required Color color,
    required double thickness,
    required double tileWidth,
    required double tileHeight,
  }) = _Lines;

  /// `repeating-linear-gradient`: a band [width] wide every [period].
  const factory SkinLayer.stripes({
    required double angle,
    required Color color,
    required double width,
    required double period,
  }) = _Stripes;
}

class _Linear extends SkinLayer {
  const _Linear({required this.angle, required this.colors, required this.stops});
  final double angle;
  final List<Color> colors;
  final List<double> stops;
}

class _Radial extends SkinLayer {
  const _Radial({
    required this.rx,
    required this.ry,
    required this.cx,
    required this.cy,
    required this.colors,
    required this.stops,
  });
  final double rx, ry, cx, cy;
  final List<Color> colors;
  final List<double> stops;
}

class _Dots extends SkinLayer {
  const _Dots({required this.color, required this.radius, required this.tileWidth, required this.tileHeight});
  final Color color;
  final double radius, tileWidth, tileHeight;
}

class _Lines extends SkinLayer {
  const _Lines({
    required this.angle,
    required this.color,
    required this.thickness,
    required this.tileWidth,
    required this.tileHeight,
  });
  final double angle;
  final Color color;
  final double thickness, tileWidth, tileHeight;
}

class _Stripes extends SkinLayer {
  const _Stripes({required this.angle, required this.color, required this.width, required this.period});
  final double angle;
  final Color color;
  final double width, period;
}

SkinSpec skinById(String? id) => skinSpecs.firstWhere((s) => s.id == id, orElse: () => skinSpecs.first);

// ── Palette derivation (the "derived tokens" block of skins.css) ───────────

/// `color-mix(in oklab, a p, b)` for opaque colours.
Color mixOklab(Color a, Color b, double p) {
  final la = _toOklab(a);
  final lb = _toOklab(b);
  return _fromOklab([for (var i = 0; i < 3; i++) la[i] * p + lb[i] * (1 - p)]);
}

double _toLinear(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _toSrgb(double c) => c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

List<double> _toOklab(Color c) {
  final r = _toLinear(c.r), g = _toLinear(c.g), b = _toLinear(c.b);
  final l = math.pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1 / 3).toDouble();
  final m = math.pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1 / 3).toDouble();
  final s = math.pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1 / 3).toDouble();
  return [
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  ];
}

Color _fromOklab(List<double> lab) {
  final l = math.pow(lab[0] + 0.3963377774 * lab[1] + 0.2158037573 * lab[2], 3).toDouble();
  final m = math.pow(lab[0] - 0.1055613458 * lab[1] - 0.0638541728 * lab[2], 3).toDouble();
  final s = math.pow(lab[0] - 0.0894841775 * lab[1] - 1.2914855480 * lab[2], 3).toDouble();
  double ch(double v) => _toSrgb(v).clamp(0.0, 1.0);
  return Color.from(
    alpha: 1,
    red: ch(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    green: ch(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    blue: ch(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
  );
}

/// The app palette a skin produces — skins.css's ramp, step for step.
AppColors appColorsForSkin(SkinPalette p, {required bool dark}) {
  Color ramp(double pct) => mixOklab(p.ink, p.base, pct / 100);
  return AppColors(
    page: p.page,
    surface: p.surface,
    gray50: ramp(4),
    gray100: ramp(8),
    gray200: ramp(16),
    gray300: ramp(28),
    gray400: ramp(44),
    gray500: ramp(58),
    gray600: ramp(68),
    gray700: ramp(78),
    gray800: ramp(88),
    gray900: ramp(96),
    // blue-50: the accent 8% into the base.
    blueTint: mixOklab(p.accent, p.base, 0.08),
    redTint: (dark ? AppColors.dark : AppColors.light).redTint,
  );
}

/// A photo with no skin: the normal palette with glass page + surface.
AppColors appColorsForGlass({required bool dark}) {
  final base = dark ? AppColors.dark : AppColors.light;
  return AppColors(
    page: dark ? glassPageDark : glassPageLight,
    surface: dark ? glassSurfaceDark : glassSurfaceLight,
    gray50: base.gray50,
    gray100: base.gray100,
    gray200: base.gray200,
    gray300: base.gray300,
    gray400: base.gray400,
    gray500: base.gray500,
    gray600: base.gray600,
    gray700: base.gray700,
    gray800: base.gray800,
    gray900: base.gray900,
    blueTint: base.blueTint,
    redTint: base.redTint,
  );
}

// ── Wallpaper (wallpapers.js) ────────────────────────────────────────────────

/// A Pexels photo behind the app. Stored whole (not just the URL) so the
/// picker can redraw the chosen tile and credit the photographer offline.
class Wallpaper {
  const Wallpaper({required this.id, required this.url, required this.thumb, required this.photographer});

  final String id;
  final String url;
  final String thumb;
  final String photographer;

  Map<String, dynamic> toJson() => {'id': id, 'url': url, 'thumb': thumb, 'photographer': photographer};

  static Wallpaper? fromJson(Object? j) {
    if (j is! Map) return null;
    final url = '${j['url'] ?? ''}';
    if (!url.startsWith('http')) return null;
    return Wallpaper(
      id: '${j['id'] ?? url}',
      url: url,
      thumb: '${j['thumb'] ?? url}',
      photographer: '${j['photographer'] ?? ''}',
    );
  }
}

// ── The choice (persisted, like the web's localStorage keys) ─────────────────

class SkinController extends ChangeNotifier {
  SkinController(this._prefs) : _skinId = skinById(_prefs.getString(_skinKey)).id, _wallpaper = _readWallpaper(_prefs);

  static const _skinKey = 'ck:skin';
  static const _wallpaperKey = 'ck:wallpaper';

  final SharedPreferences _prefs;
  String _skinId;
  Wallpaper? _wallpaper;

  String get skinId => _skinId;
  SkinSpec get skin => skinById(_skinId);
  Wallpaper? get wallpaper => _wallpaper;

  /// Anything painting behind the app (a skin's art or a photo)?
  bool get active => _skinId != defaultSkinId || _wallpaper != null;

  static Wallpaper? _readWallpaper(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_wallpaperKey);
      return raw == null ? null : Wallpaper.fromJson(jsonDecode(raw));
    } catch (_) {
      // A half-restored preference is worse than none.
      return null;
    }
  }

  void setSkin(String id) {
    final next = skinById(id).id;
    if (next == _skinId) return;
    _skinId = next;
    _prefs.setString(_skinKey, next);
    notifyListeners();
  }

  void setWallpaper(Wallpaper? w) {
    if (w?.url == _wallpaper?.url) return;
    _wallpaper = w;
    if (w == null) {
      _prefs.remove(_wallpaperKey);
    } else {
      _prefs.setString(_wallpaperKey, jsonEncode(w.toJson()));
    }
    notifyListeners();
  }

  /// The palette the app should use right now.
  AppColors colorsFor({required bool dark}) {
    final p = skin.palette(dark);
    if (p != null) return appColorsForSkin(p, dark: dark);
    if (_wallpaper != null) return appColorsForGlass(dark: dark);
    return dark ? AppColors.dark : AppColors.light;
  }
}

// ── Painting the backdrop ───────────────────────────────────────────────────

/// What sits behind the whole app: the base colour, the skin's gradients, its
/// illustrated plate, and a photo over all of it when one is chosen — the
/// stack `:root[data-skin]` + `:root[data-wallpaper]` paint on the web.
/// With nothing chosen it is just [fallback] (the plain app surface).
class SkinBackdrop extends StatelessWidget {
  const SkinBackdrop({super.key, required this.palette, required this.wallpaper, required this.fallback});

  final SkinPalette? palette;
  final Wallpaper? wallpaper;
  final Color fallback;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: p?.base ?? fallback),
        if (p != null) CustomPaint(painter: SkinArtPainter(p.layers)),
        if (p?.image != null) SvgPicture.asset(p!.image!, fit: BoxFit.cover),
        if (wallpaper != null) MediaImage(wallpaper!.url, fit: BoxFit.cover),
      ],
    );
  }
}

/// Paints a skin's gradient layers (bottom layer first, as CSS stacks them).
class SkinArtPainter extends CustomPainter {
  SkinArtPainter(this.layers);

  final List<SkinLayer> layers;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);
    for (final layer in layers.reversed) {
      switch (layer) {
        case _Linear(:final angle, :final colors, :final stops):
          // CSS angles: 0deg points up, 180deg down; the gradient line is
          // long enough for its ends to touch opposite corners.
          final a = angle * math.pi / 180;
          final dir = Offset(math.sin(a), -math.cos(a));
          final len = (size.width * math.sin(a)).abs() + (size.height * math.cos(a)).abs();
          final c = rect.center;
          canvas.drawRect(
            rect,
            Paint()..shader = ui.Gradient.linear(c - dir * (len / 2), c + dir * (len / 2), colors, stops),
          );
        case _Radial(:final rx, :final ry, :final cx, :final cy, :final colors, :final stops):
          // A unit circle scaled to the ellipse's radii.
          final m = Matrix4.identity()
            ..translateByDouble(cx * size.width, cy * size.height, 0, 1)
            ..scaleByDouble(rx * size.width, ry * size.height, 1, 1);
          canvas.drawRect(
            rect,
            Paint()..shader = ui.Gradient.radial(Offset.zero, 1, colors, stops, TileMode.clamp, m.storage),
          );
        case _Dots(:final color, :final radius, :final tileWidth, :final tileHeight):
          final paint = Paint()..color = color;
          for (var y = tileHeight / 2; y < size.height + tileHeight; y += tileHeight) {
            for (var x = tileWidth / 2; x < size.width + tileWidth; x += tileWidth) {
              canvas.drawCircle(Offset(x, y), radius, paint);
            }
          }
        case _Lines(:final angle, :final color, :final thickness, :final tileWidth, :final tileHeight):
          final paint = Paint()..color = color;
          final vertical = (angle % 180).round() == 90;
          if (vertical) {
            for (var x = 0.0; x < size.width; x += tileWidth) {
              canvas.drawRect(Rect.fromLTWH(x, 0, thickness, size.height), paint);
            }
          } else {
            for (var y = 0.0; y < size.height; y += tileHeight) {
              canvas.drawRect(Rect.fromLTWH(0, y, size.width, thickness), paint);
            }
          }
        case _Stripes(:final angle, :final color, :final width, :final period):
          final paint = Paint()..color = color;
          final vertical = (angle % 180).round() == 90;
          final extent = vertical ? size.width : size.height;
          for (var p = 0.0; p < extent; p += period) {
            canvas.drawRect(
              vertical ? Rect.fromLTWH(p, 0, width, size.height) : Rect.fromLTWH(0, p, size.width, width),
              paint,
            );
          }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SkinArtPainter old) => old.layers != layers;
}

/// The colour for the app's chrome — the top bar, the bottom nav and the
/// home tab strip. Under a skin or a photo it's the translucent PAGE colour,
/// so the wallpaper carries through the header and the footer instead of
/// stopping at them; otherwise the plain surface, as before.
extension SkinChrome on BuildContext {
  Color get chromeColor => watch<SkinController>().active ? colors.page : colors.surface;
}
