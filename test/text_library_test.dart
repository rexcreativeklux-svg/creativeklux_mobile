import 'package:creativeklux/core/design/shapes.dart';
import 'package:creativeklux/features/editor/design_editor_controller.dart';
import 'package:creativeklux/features/editor/text_library/text_combo_data.dart';
import 'package:creativeklux/features/editor/text_library/text_combos.dart';
import 'package:creativeklux/features/editor/text_library/text_library_section.dart';
import 'package:creativeklux/features/editor/text_library/text_looks.dart';
import 'package:creativeklux/features/editor/text_library/text_style.dart';
import 'package:creativeklux/features/editor/text_library/text_tools.dart';
import 'package:creativeklux/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// A deterministic measuring face: the test font, no network.
TextStyle _style(Map<String, dynamic> el) => TextStyle(fontSize: (el['fontSize'] as num).toDouble());

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('data matches the web', () {
    test('themes, combos, looks', () {
      expect(comboThemes.length, 28);
      expect(textCombos.length, 404);
      expect(textCombos.map((c) => c['id']).toSet().length, 404);
      expect(textLooks.length, 391);
      expect(lookRowGroups.length, 21);
      expect(lookRowGroups.first.label, 'Trending');
      expect(lookRowGroups.fold<int>(0, (n, r) => n + r.items.length), 391);
      for (final (id, _) in comboThemes) {
        expect(combosInTheme(id), isNotEmpty, reason: id);
      }
    });

    test('every look a combo names exists, every shape type maps', () {
      for (final combo in textCombos) {
        for (final part in combo['parts'] as List) {
          if (part['look'] != null) expect(lookById(part['look']), isNotNull, reason: '${combo['id']}');
        }
      }
    });
  });

  group('buildCombo', () {
    const w = 1080.0, h = 1350.0;

    void expectOnPage(List<Map<String, dynamic>> els) {
      final b = elementsBounds(els);
      expect(b.left, greaterThanOrEqualTo(-0.5));
      expect(b.top, greaterThanOrEqualTo(-0.5));
      expect(b.right, lessThanOrEqualTo(w + 0.5));
      expect(b.bottom, lessThanOrEqualTo(h + 0.5));
      // Centred on the page.
      expect(b.center.dx, closeTo(w / 2, 1));
      expect(b.center.dy, closeTo(h / 2, 1));
    }

    test('mega sale: parts, types, inside the canvas', () {
      final combo = comboById('combo-mega-sale')!;
      final els = buildCombo(combo, canvasWidth: w, canvasHeight: h, styleOf: _style);
      final parts = combo['parts'] as List;
      expect(els.length, parts.length);
      for (var i = 0; i < els.length; i++) {
        expect(els[i]['type'], parts[i]['type'] == 'text' ? 'text' : 'shape');
        expect(els[i]['width'], greaterThan(0));
        expect(els[i]['height'], greaterThan(0));
      }
      expectOnPage(els);
    });

    test('every combo builds onto the page, shapes resolve to library keys', () {
      for (final combo in textCombos) {
        final els = buildCombo(combo, canvasWidth: w, canvasHeight: h, styleOf: _style);
        expect(els, isNotEmpty, reason: '${combo['id']}');
        expect(els.length, (combo['parts'] as List).length, reason: '${combo['id']} dropped a part');
        for (final el in els) {
          if (el['type'] == 'shape') expect(shapes.containsKey(el['shape']), isTrue, reason: '${el['shape']}');
          if (el['type'] == 'text') {
            expect(el['content'], isA<String>());
            expect(el['content'], el['text']);
            expect(el.containsKey('basePadding'), isFalse);
          }
        }
        // About half the page's width: scaled from the 1:1 build, so ceil'd
        // box sizes and ink reach can land a few px over.
        final b = elementsBounds(els);
        expect(b.width, lessThanOrEqualTo(w * 0.55 * 1.02), reason: '${combo['id']}');
        expectOnPage(els);
      }
    });

    test('a ring part lands straight, inside its ring', () {
      final combo = textCombos.firstWhere((c) => (c['parts'] as List).any((p) => p['ring'] != null));
      final els = buildCombo(combo, canvasWidth: w, canvasHeight: h, styleOf: _style);
      expect(els.where((e) => e['type'] == 'text'), isNotEmpty);
      expectOnPage(els);
    });
  });

  group('looks', () {
    final selected = <String, dynamic>{
      'id': 't1',
      'type': 'text',
      'content': 'hello world',
      'fontSize': 50,
      'x': 10,
      'y': 20,
      'width': 300,
      'height': 80,
    };

    test('lookPatch restyles selected text (uppercase look, plate → background)', () {
      final look = lookById('tfx-brushMark-crimson')!;
      final patch = lookPatch(look, selected);
      expect(patch['textLook'], {'id': 'tfx-brushMark-crimson'});
      expect(patch['content'], 'HELLO WORLD');
      expect(patch['text'], 'HELLO WORLD');
      expect(patch['fontFamily'], "'Anton', sans-serif");
      expect(patch['fill'], '#FF2D55');
      expect((patch['textEffect'] as Map)['type'], 'background');
      // A look never moves or resizes the box.
      expect(patch.containsKey('x'), isFalse);
      expect(patch.containsKey('width'), isFalse);
    });

    test('outline stack → outline effect; nothing selected → a new centred element', () {
      final look = lookById('tfx-sticker-candy')!;
      expect((lookPatch(look, selected)['textEffect'] as Map)['type'], 'outline');
      final el = lookPatch(look, null, canvasWidth: 1000, canvasHeight: 600, styleOf: _style);
      expect(el['type'], 'text');
      expect(el['content'], 'Your text');
      expect(el['fontSize'], 54); // 9% of 600
      final cx = (el['x'] as num) + (el['width'] as num) / 2;
      final cy = (el['y'] as num) + (el['height'] as num) / 2;
      expect(cx, closeTo(500, 0.01));
      expect(cy, closeTo(300, 0.01));
    });

    test('effectFrom: extrude → hard shadow, hollow outline keeps stroke colour', () {
      final extruded = effectFrom({
        'fontSize': 80,
        'fill': '#fff',
        'extrude': {'depth': 8, 'color': '#000000', 'angle': 120},
      });
      expect(extruded.textEffect!['type'], 'shadow');
      expect(extruded.textEffect!['direction'], 120);
      final hollow = effectFrom({
        'fontSize': 80,
        'fill': 'transparent',
        'textStroke': {'enabled': true, 'width': 3, 'color': 'rgba(255,0,0,0.5)'},
      });
      expect(hollow.textEffect!['type'], 'hollow');
      expect(hollow.fill, '#ff0000');
    });
  });

  test('applyLook / insertCombo / removeLook on the controller', () async {
    final c = DesignEditorController(
      designId: 1,
      name: 'T',
      canvas: {'width': 1080, 'height': 1080},
      elements: const [],
    );
    final combo = comboById('combo-mega-sale')!;
    await insertCombo(c, combo);
    expect(c.elements.length, (combo['parts'] as List).length);
    expect(c.selectedIds.length, c.elements.length);

    c.select(c.elements.firstWhere((e) => e['type'] == 'text')['id'] as String);
    await applyLook(c, lookById('tfx-badge-snow')!);
    expect(activeLook(c)?['id'], 'tfx-badge-snow');
    removeLook(c);
    expect(activeLook(c), isNull);
    expect(c.selected!['textEffect'], isNull);
  });

  testWidgets('TextLibrarySection renders in a 300px panel and switches', (tester) async {
    final c = DesignEditorController(
      designId: 1,
      name: 'T',
      canvas: {'width': 1080, 'height': 1080},
      elements: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [TextLibrarySection(c: c)],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Templates'), findsOneWidget);
    expect(find.text('Sale & promo'), findsOneWidget);
    await tester.tap(find.text('Effects'));
    await tester.pump();
    expect(find.text('Trending'), findsOneWidget);
    await tester.tap(find.text('See all').first);
    await tester.pump();
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Let the font loader's (failed, fetching is off) timeouts run out.
    await tester.pumpWidget(const SizedBox());
    // DesignFonts loads faces one after another, each with its own timeout.
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(seconds: 11));
    }
  });
}
