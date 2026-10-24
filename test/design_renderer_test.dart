import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:creativeklux/core/design/design_renderer.dart';
import 'package:creativeklux/core/design/scraive_compat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // No network in tests: the renderer must fall back to the default face.
  GoogleFonts.config.allowRuntimeFetching = false;

  final canvas = <String, dynamic>{
    'width': 400,
    'height': 300,
    'background': 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
  };
  final elements = <dynamic>[
    {
      'type': 'shape',
      'shape': 'rect',
      'x': 10,
      'y': 10,
      'width': 120,
      'height': 60,
      'fill': '#ffffff',
      'borderRadius': 12,
    },
    {'type': 'shape', 'shape': 'circle', 'x': 150, 'y': 10, 'width': 60, 'height': 60, 'fill': 'rgba(255, 0, 0, 0.8)'},
    {
      'type': 'shape',
      'shape': 'star5',
      'x': 230,
      'y': 10,
      'width': 60,
      'height': 60,
      'fill': '#fde047',
      'stroke': '#111111',
      'strokeWidth': 2,
      'shapeEffect': {'type': 'drop'},
    },
    {
      'type': 'text',
      'x': 20,
      'y': 90,
      'width': 200,
      'height': 100,
      'content': 'A long headline that has to wrap onto more than one line',
      'fontSize': 18,
      'fontWeight': '700',
      'fontFamily': "'Playfair Display', serif",
      'textAlign': 'center',
      'fill': '#ffffff',
      'textEffect': {'type': 'shadow'},
    },
    {
      'type': 'rectangle',
      'x': 240,
      'y': 200,
      'width': 140,
      'height': 80,
      'fill': '#000000',
      'fillOpacity': 50,
      'cornerRadius': 8,
    },
    {
      'type': 'text-heading',
      'x': 240,
      'y': 200,
      'width': 140,
      'height': 80,
      'content': 'scraive heading',
      'textTransform': 'uppercase',
      'fontSize': 20,
      'fill': '#ffffff',
    },
  ];

  test('renders a mixed design to a PNG of the canvas size', () async {
    final png = await renderDesignPng(canvas, elements, scraive: true, pixelRatio: 2);
    expect(png, isNotEmpty);
    // PNG signature, then the IHDR width/height (big-endian).
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    final header = ByteData.sublistView(png, 16, 24);
    expect(header.getUint32(0), 800);
    expect(header.getUint32(4), 600);

    final image = await renderDesign(canvas, elements);
    expect(image.width, 400);
    expect(image.height, 300);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    // The rounded rect at (10,10)-(130,70) is white.
    final i = (40 * 400 + 60) * 4;
    expect(bytes!.getUint8(i), 255);
    expect(bytes.getUint8(i + 1), 255);
    expect(bytes.getUint8(i + 2), 255);
  });

  test('fromScraiveElements translates shapes and text', () {
    final out = fromScraiveElements(elements.sublist(4), text: true);
    expect(out[0]['type'], 'shape');
    expect(out[0]['shape'], 'rect');
    expect(out[0]['fill'], 'rgba(0, 0, 0, 0.5)');
    expect(out[0]['borderRadius'], 8);
    expect(out[0].containsKey('fillOpacity'), isFalse);
    expect(out[1]['type'], 'text');
    expect(out[1]['content'], 'SCRAIVE HEADING');
    expect(out[1]['verticalAlign'], 'top');
    expect(out[1]['padding'], 5);
    expect(out[1]['lineHeight'], 1.2);
  });
}
