import 'dart:convert';
import 'dart:ui' as ui;

import 'package:creativeklux/core/design/design_renderer.dart';
import 'package:creativeklux/core/design/image_filters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// A solid [w]×[h] PNG as a data: URL, so image tests need no network.
Future<String> _solidPng(ui.Color color, {int w = 4, int h = 4}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = color);
  final img = await recorder.endRecording().toImage(w, h);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return 'data:image/png;base64,${base64Encode(png!.buffer.asUint8List())}';
}

/// RGBA of one pixel of a rendered design.
Future<List<int>> _pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * image.width + x) * 4;
  return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2), data.getUint8(i + 3)];
}

void expectRgb(List<double> rgba, double r, double g, double b) {
  expect(rgba[0], closeTo(r, 1e-6));
  expect(rgba[1], closeTo(g, 1e-6));
  expect(rgba[2], closeTo(b, 1e-6));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('parseCssFilter', () {
    test('empty / none is the identity', () {
      for (final css in ['', '  ', 'none']) {
        final f = parseCssFilter(css);
        expect(f.isIdentity, isTrue);
        expect(f.matrix.isIdentity, isTrue);
        expect(f.blurSigma, 0);
        expect(f.dropShadow, isNull);
      }
    });

    test('grayscale(1) turns red into its luminance gray', () {
      final m = parseCssFilter('grayscale(1)').matrix;
      expectRgb(m.applyRgba([1, 0, 0, 1]), 0.2126, 0.2126, 0.2126);
    });

    test('brightness(0.5) halves, and percentages read as fractions', () {
      expectRgb(parseCssFilter('brightness(0.5)').matrix.applyRgba([0.8, 0.4, 0.2, 1]), 0.4, 0.2, 0.1);
      expectRgb(parseCssFilter('brightness(50%)').matrix.applyRgba([0.8, 0.4, 0.2, 1]), 0.4, 0.2, 0.1);
      final a = parseCssFilter('saturate(150%)').matrix.values;
      final b = parseCssFilter('saturate(1.5)').matrix.values;
      for (var i = 0; i < 20; i++) {
        expect(a[i], closeTo(b[i], 1e-12));
      }
    });

    test('contrast pivots on mid-gray; invert and opacity', () {
      expectRgb(parseCssFilter('contrast(2)').matrix.applyRgba([0.5, 0.75, 0.25, 1]), 0.5, 1, 0);
      expectRgb(parseCssFilter('invert(1)').matrix.applyRgba([1, 0.25, 0, 1]), 0, 0.75, 1);
      expect(parseCssFilter('opacity(0.3)').alphaScale, closeTo(0.3, 1e-12));
    });

    test('angle units agree', () {
      final deg = parseCssFilter('hue-rotate(180deg)').matrix.values;
      for (final css in ['hue-rotate(0.5turn)', 'hue-rotate(3.14159265358979rad)', 'hue-rotate(200grad)']) {
        final v = parseCssFilter(css).matrix.values;
        for (var i = 0; i < 20; i++) {
          expect(v[i], closeTo(deg[i], 1e-9), reason: css);
        }
      }
      expect(parseCssFilter('hue-rotate(360deg)').matrix.isIdentity, isTrue);
    });

    test('functions compose in order, steps clamp in between', () {
      final f = parseCssFilter('brightness(2) brightness(0.5)');
      expect(f.steps, hasLength(2));
      // Combined matrix: identity. The browser clamps after the first step.
      expect(f.matrix.isIdentity, isTrue);
      final c = f.applyToColor(const ui.Color.from(alpha: 1, red: 0.8, green: 0.2, blue: 0));
      expect(c.r, closeTo(0.5, 1e-6));
      expect(c.g, closeTo(0.2, 1e-6));
    });

    test('blur and drop-shadow', () {
      final f = parseCssFilter('sepia(0.2) blur(3px) blur(4px) drop-shadow(2px -6px 14px rgba(0,0,255,0.4))');
      expect(f.blurSigma, closeTo(5, 1e-9));
      final s = f.dropShadow!;
      expect(s.dx, 2);
      expect(s.dy, -6);
      expect(s.sigma, 7); // CSS blur radius is twice the sigma
      expect(s.color.b, closeTo(1, 1e-6));
      expect(s.color.a, closeTo(0.4, 1e-6));
      // Colour first, blur omitted.
      final t = parseCssFilter('drop-shadow(#ff0000 3px 4px)').dropShadow!;
      expect([t.dx, t.dy, t.sigma], [3, 4, 0]);
      expect(t.color.r, closeTo(1, 1e-6));
      // url() (the web's tone filter) is ignored.
      expect(parseCssFilter('url(#ck-tone-1)').isIdentity, isTrue);
    });
  });

  group('buildImageFilter (same strings as imageAdjust.js)', () {
    test('nothing set → empty', () {
      expect(buildImageFilter({'type': 'image'}), '');
      expect(
        buildImageFilter({
          'filter': 'none',
          'adjust': {'brightness': 0},
          'imgShadow': 'none',
        }),
        '',
      );
    });

    test('preset + adjust (cool warmth) + blur + preset shadow', () {
      final el = {
        'filter': 'noir',
        'adjust': {'brightness': 20, 'warmth': -50, 'hue': 30, 'blur': 4},
        'imgShadow': 'drop',
      };
      expect(
        buildImageFilter(el),
        'grayscale(1) contrast(1.45) brightness(0.92) brightness(1.2) hue-rotate(-17deg) saturate(0.95) '
        'hue-rotate(30deg) blur(4px) drop-shadow(0px 10px 14px rgba(0,0,0,0.4))',
      );
    });

    test('look id, warm warmth, contrast/saturation, custom shadow params', () {
      final el = {
        'filter': 'look-classic',
        'adjust': {'contrast': -15, 'saturation': 33, 'warmth': 40},
        'imgShadow': 'custom',
        'imgShadowParams': {'x': 3, 'y': 4.5, 'blur': 5, 'opacity': 25, 'color': '#f00'},
      };
      expect(
        buildImageFilter(el),
        'grayscale(1) contrast(0.85) saturate(1.33) sepia(0.2) saturate(1.08) '
        'drop-shadow(3px 4.5px 5px rgba(255,0,0,0.25))',
      );
    });

    test('data tables', () {
      expect(filterCssById('sepia'), 'sepia(0.78) contrast(1.05) brightness(1.02)');
      expect(filterCssById('look-fade'), 'contrast(0.8) brightness(1.1) saturate(0.75)');
      expect(filterCssById('nope'), '');
      expect(resolveShadow({'imgShadow': 'none'}), isNull);
      expect(resolveShadow({'imgShadow': 'hard'}), {'x': 6, 'y': 6, 'blur': 4, 'opacity': 55});
      expect(imageShadows, hasLength(42));
      expect(filterLookGroups.expand((g) => g.looks), hasLength(50));
      expect(imageAdjustments.map((a) => a.key), ['brightness', 'contrast', 'saturation', 'warmth', 'hue', 'blur']);
    });
  });

  group('renderDesign applies image filters', () {
    late String red;
    setUpAll(() async => red = await _solidPng(const ui.Color(0xFFFF0000)));

    Map<String, dynamic> canvas(int w, int h) => {'width': w, 'height': h, 'background': '#ffffff'};

    test('no filter leaves the picture alone', () async {
      final img = await renderDesign(canvas(8, 8), [
        {'type': 'image', 'src': red, 'x': 0, 'y': 0, 'width': 8, 'height': 8},
      ]);
      expect(await _pixel(img, 4, 4), [255, 0, 0, 255]);
    });

    test('mono preset → gray, brightness −50 → half red', () async {
      final mono = await renderDesign(canvas(8, 8), [
        {'type': 'image', 'src': red, 'x': 0, 'y': 0, 'width': 8, 'height': 8, 'filter': 'look-classic'},
      ]);
      final p = await _pixel(mono, 4, 4);
      // grayscale(1) of pure red: 0.2126 × 255 ≈ 54.
      for (final ch in p.take(3)) {
        expect(ch, closeTo(54, 2));
      }

      final dim = await renderDesign(canvas(8, 8), [
        {
          'type': 'image',
          'src': red,
          'x': 0,
          'y': 0,
          'width': 8,
          'height': 8,
          'adjust': {'brightness': -50},
        },
      ]);
      final q = await _pixel(dim, 4, 4);
      expect(q[0], closeTo(128, 2));
      expect(q[1], 0);
      expect(q[2], 0);
    });

    test('drop shadow is painted behind, offset, in its colour', () async {
      final img = await renderDesign(canvas(40, 20), [
        {
          'type': 'image',
          'src': red,
          'x': 2,
          'y': 2,
          'width': 10,
          'height': 10,
          'imgShadow': 'custom',
          'imgShadowParams': {'x': 20, 'y': 0, 'blur': 0, 'opacity': 100, 'color': '#0000ff'},
        },
      ]);
      expect(await _pixel(img, 6, 6), [255, 0, 0, 255]); // the picture
      expect(await _pixel(img, 26, 6), [0, 0, 255, 255]); // its shadow
      expect(await _pixel(img, 36, 16), [255, 255, 255, 255]); // untouched
    });

    test('rounded images clip the shadow, as the export does', () async {
      final img = await renderDesign(canvas(40, 20), [
        {
          'type': 'image',
          'src': red,
          'x': 2,
          'y': 2,
          'width': 10,
          'height': 10,
          'borderRadius': 2,
          'imgShadow': 'custom',
          'imgShadowParams': {'x': 20, 'y': 0, 'blur': 0, 'opacity': 100, 'color': '#0000ff'},
        },
      ]);
      expect(await _pixel(img, 6, 6), [255, 0, 0, 255]);
      expect(await _pixel(img, 26, 6), [255, 255, 255, 255]);
    });
  });
}
