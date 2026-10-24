import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:creativeklux/core/design/charts.dart';
import 'package:creativeklux/core/design/design_renderer.dart';
import 'package:creativeklux/core/design/graphics.dart';
import 'package:creativeklux/core/design/grids.dart';
import 'package:creativeklux/core/design/table_utils.dart';
import 'package:creativeklux/features/editor/design_editor_controller.dart';
import 'package:creativeklux/core/theme/app_theme.dart';
import 'package:creativeklux/features/editor/element_libraries/element_inserts.dart';
import 'package:creativeklux/features/editor/element_libraries/element_libraries_section.dart';
import 'package:creativeklux/features/editor/element_libraries/element_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Future<ByteData> _rgba(List<Map<String, dynamic>> elements, {double w = 400, double h = 300}) async {
  final image = await renderDesign({'width': w, 'height': h, 'background': '#ffffff'}, elements);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return bytes!;
}

Color _px(ByteData b, int x, int y, {int w = 400}) {
  final i = (y * w + x) * 4;
  return Color.fromARGB(b.getUint8(i + 3), b.getUint8(i), b.getUint8(i + 1), b.getUint8(i + 2));
}

bool _near(Color a, Color b, [int tol = 6]) =>
    ((a.r - b.r) * 255).abs() <= tol && ((a.g - b.g) * 255).abs() <= tol && ((a.b - b.b) * 255).abs() <= tol;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const white = Color(0xFFFFFFFF);
  const indigo = Color(0xFF6366F1);

  test('a bar chart draws its bars in the palette at the right heights', () async {
    // 400×300 at the origin: padX 32, plot 336 wide, step 84, bars 50.4 wide;
    // padTop 30, baseY 30 + 222 = 252; max 90 → Apr is full height.
    final b = await _rgba([
      {'type': 'chart', 'chart': 'bar', 'x': 0, 'y': 0, 'width': 400, 'height': 300},
    ]);
    // Jan (40/90): bar from y≈153 to 252, x 48.8..99.2.
    expect(_near(_px(b, 74, 200), indigo), isTrue);
    expect(_near(_px(b, 74, 140), white), isTrue);
    // Apr (90/90) in the 4th colour (#ef4444) reaches the top of the plot.
    expect(_near(_px(b, 326, 40), const Color(0xFFEF4444)), isTrue);
    // Between bars stays white.
    expect(_near(_px(b, 112, 200), white), isTrue);
  });

  test('pie and donut: slices round the centre, donut hole white', () async {
    final pie = await _rgba([
      {'type': 'chart', 'chart': 'pie', 'x': 0, 'y': 0, 'width': 400, 'height': 300},
    ]);
    final donut = await _rgba([
      {'type': 'chart', 'chart': 'donut', 'x': 0, 'y': 0, 'width': 400, 'height': 300},
    ]);
    // Centre (136, 150), r = min(120, 126) = 120. The first slice starts at 12
    // o'clock going clockwise, so just right of top is slice 0 (indigo).
    expect(_near(_px(pie, 146, 50), indigo), isTrue);
    expect(_near(_px(pie, 136, 150), white), isFalse);
    expect(_near(_px(donut, 136, 150), white), isTrue);
    expect(_near(_px(donut, 146, 50), indigo), isTrue);
    // Legend swatch for Jan at x≈264.
    expect(_px(pie, 268, 125) != white, isTrue);
  });

  test('line chart with custom data and colours draws a stroked line', () async {
    final b = await _rgba([
      {
        'type': 'chart',
        'chart': 'line',
        'x': 0,
        'y': 0,
        'width': 400,
        'height': 300,
        'colors': ['#ff0000'],
        'data': [
          {'label': 'A', 'value': 10},
          {'label': 'B', 'value': 10},
        ],
      },
    ]);
    // Both points at max → a flat red line along y = 30 from x 32 to 368.
    expect(_near(_px(b, 200, 30), const Color(0xFFFF0000), 20), isTrue);
    expect(_near(_px(b, 200, 120), white), isTrue);
  });

  test('a graphic stretches to its box with its own colours', () async {
    final b = await _rgba([
      {'type': 'graphic', 'graphic': 'check-badge', 'x': 100, 'y': 50, 'width': 200, 'height': 200},
      {'type': 'graphic', 'graphic': 'heart', 'x': 0, 'y': 0, 'width': 80, 'height': 40},
    ]);
    // Badge circle (#22c55e) centred at (200,150) r = 84; its tick is white.
    expect(_near(_px(b, 200, 90), const Color(0xFF22C55E)), isTrue);
    expect(_near(_px(b, 100 + 90, 50 + 130), white, 30), isTrue);
    // Outside the circle's corner stays white.
    expect(_near(_px(b, 105, 55), white), isTrue);
    // Heart stretched to 80×40: its body at (40, 20).
    expect(_near(_px(b, 40, 20), const Color(0xFFF43F5E)), isTrue);
  });

  test('unknown graphic keys fall back; every graphic has paintable parts', () {
    expect(graphicDef('nope').key, 'sparkles');
    for (final g in graphics) {
      expect(g.parts, isNotEmpty);
      for (final p in g.parts) {
        expect(p.toPath().getBounds().isEmpty && p is! GLine, isFalse, reason: g.key);
      }
    }
  });

  test('renderDesignPng encodes a chart + graphic design', () async {
    final png = await renderDesignPng(
      {'width': 200, 'height': 100},
      [
        {'type': 'chart', 'chart': 'donut', 'x': 0, 'y': 0, 'width': 120, 'height': 100},
        {'type': 'graphic', 'graphic': 'confetti', 'x': 120, 'y': 0, 'width': 80, 'height': 80},
      ],
    );
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  group('widgets', () {
    // A phone-width but tall surface, so every control is on screen to tap.
    setUp(() {
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(400, 2000);
      view.devicePixelRatio = 1;
    });
    tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset());

    DesignEditorController make() =>
        DesignEditorController(designId: 1, name: 'x', canvas: {'width': 1080, 'height': 1080}, elements: const []);

    Future<void> host(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(width: 300, child: ListView(children: [child])),
        ),
      ),
    );

    testWidgets('ElementLibrariesSection opens sections and inserts', (tester) async {
      final c = make();
      var inserted = 0;
      await host(tester, ElementLibrariesSection(c: c, onInserted: () => inserted++));
      for (final label in ['Graphics', 'Charts', 'Tables', 'Frames', 'Grids']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Charts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Donut'));
      expect(c.selected!['chart'], 'donut');

      await tester.tap(find.text('Tables'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 × 4'));
      expect(c.selected!['type'], 'table');
      expect(c.selected!['cols'], 4);
      expect(inserted, 2);
    });

    testWidgets('chart data and table sheets edit the selected element', (tester) async {
      final c = make();
      insertChart(c);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(onPressed: () => showChartDataSheet(context, c), child: const Text('chart')),
                  TextButton(onPressed: () => showTableEditSheet(context, c), child: const Text('table')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('chart'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add row'));
      await tester.pump();
      expect((c.selected!['data'] as List).length, 5);
      await tester.enterText(find.widgetWithText(TextField, 'Jan'), 'January');
      expect((c.selected!['data'] as List).first['label'], 'January');
      await tester.tap(find.byIcon(LucideIcons.chartLine));
      expect(c.selected!['chart'], 'line');
      Navigator.of(tester.element(find.text('Chart data'))).pop();
      await tester.pumpAndSettle();

      insertTable(c, rows: 2, cols: 2);
      await tester.tap(find.text('table'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add column'));
      await tester.pump();
      expect(c.selected!['cols'], 3);
      await tester.enterText(find.byType(TextField).first, 'Name');
      expect(c.selected!['cells'][0][0], 'Name');
    });
  });

  group('inserts + data helpers', () {
    DesignEditorController make() =>
        DesignEditorController(designId: 1, name: 'x', canvas: {'width': 1080, 'height': 1080}, elements: const []);

    test('insertChart / insertGraphic / insertTable / insertGrid / insertFrame', () {
      final c = make();
      final chartId = insertChart(c, 'pie');
      final chart = c.byId(chartId)!;
      expect(chart['type'], 'chart');
      expect(chart['width'], 648);
      expect(chart['height'], 428);
      expect((chart['data'] as List).length, defaultChartData.length);
      expect(c.selected!['id'], chartId);

      final table = c.byId(insertTable(c, rows: 2, cols: 4))!;
      expect(table['cells'], [
        ['', '', '', ''],
        ['', '', '', ''],
      ]);
      expect(table['headerFill'], '#f3f4f6');

      final grid = c.byId(insertGrid(c, rows: 2, cols: 3))!;
      expect((grid['cells'] as List).length, 6);
      expect(gridCellRects(grid).length, 6);

      final frame = c.byId(insertFrame(c, 'frame-circle'))!;
      expect(frame['src'], isNull);
      expect(c.byId(insertGraphic(c, 'sun'))!['width'], closeTo(302, 1));
    });

    test('table helpers add/remove tracks and hit-test cells', () {
      final el = <String, dynamic>{
        'rows': 2,
        'cols': 2,
        'width': 200,
        'height': 100,
        'cells': [
          ['a', 'b'],
          ['c', 'd'],
        ],
      };
      expect(tableAddRow(el, 0)['cells'], [
        ['a', 'b'],
        ['', ''],
        ['c', 'd'],
      ]);
      expect(tableRemoveCol(el, 0)['cells'], [
        ['b'],
        ['d'],
      ]);
      expect(tableRemoveRow({...el, 'rows': 1}), isEmpty);
      expect(tableSetCell(el, 1, 1, 'z')['cells'][1][1], 'z');
      expect(el['cells'][1][1], 'd'); // never mutated
      expect(tableCellAt(el, const Offset(150, 80)), (1, 1));
      expect(tableCellAt(el, const Offset(10, 10)), (0, 0));
      expect(tableCellAt(el, const Offset(250, 10)), isNull);
    });

    test('grid cell patch keeps the other cells', () {
      final el = <String, dynamic>{
        'rows': 1,
        'cols': 2,
        'gap': 10,
        'width': 210,
        'height': 100,
        'cells': [
          {'src': 'a'},
          {'src': null},
        ],
      };
      final cells = gridCellSrcPatch(el, 1, 'b')['cells'] as List;
      expect(cells[0]['src'], 'a');
      expect(cells[1]['src'], 'b');
      expect(gridCellAt(el, const Offset(105, 50)), isNull); // the gap
      expect(gridCellAt(el, const Offset(150, 50)), 1);
      expect(resizeGridCells(el['cells'], 2, 2).length, 4);
    });
  });
}
