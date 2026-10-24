import 'package:creativeklux/core/design/design_renderer.dart';
import 'package:creativeklux/core/design/resize_element.dart';
import 'package:creativeklux/core/theme/app_theme.dart';
import 'package:creativeklux/features/editor/design_editor_controller.dart';
import 'package:creativeklux/features/editor/design_stage.dart';
import 'package:creativeklux/features/editor/editor_animate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

DesignEditorController _controller() => DesignEditorController(
  designId: 1,
  name: 'Test',
  canvas: {'width': 1000, 'height': 1000, 'background': '#ffffff'},
  elements: [
    {'id': 'box', 'type': 'shape', 'shape': 'rect', 'x': 100, 'y': 100, 'width': 200, 'height': 100, 'fill': '#ff0000'},
    {'id': 'title', 'type': 'text', 'content': 'Hello', 'x': 500, 'y': 600, 'width': 300, 'height': 80, 'fontSize': 40},
  ],
);

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('resize maths (resizeElement.js port)', () {
    final snap = {'x': 100.0, 'y': 100.0, 'width': 200.0, 'height': 100.0, 'fontSize': 20.0, 'type': 'text'};

    test('a corner scales box and contents together, aspect locked', () {
      final p = scaleByCorner(snap, 'bottomRight', 200, 100);
      expect(p['width'], closeTo(400, 0.01));
      expect(p['height'], closeTo(200, 0.01));
      expect(p['x'], 100); // the opposite corner is the anchor
      expect(p['fontSize'], closeTo(40, 0.01));
    });

    test('an edge crops: the window shrinks, the contents keep their size', () {
      final p = cropByEdge(snap, 'left', 50, 0);
      expect(p['x'], 150);
      expect(p['width'], 150);
      final clip = p['clip'] as Map;
      expect(clip['contentW'], 200);
      expect(clip['offsetX'], 50);
      // Dragging back out to the edge uncrops completely.
      expect(cropByEdge(snap, 'left', 0, 0)['clip'], isNull);
    });

    test('a crop can never run past its own contents', () {
      final p = cropByEdge(snap, 'right', 500, 0);
      expect(p['width'], 200);
    });
  });

  group('controller (useDesignEditor.js port)', () {
    test('one undo step per mutation; undo and redo restore', () {
      final c = _controller();
      c.updateElement('box', {'x': 300});
      c.updateElement('box', {'fill': '#00ff00'});
      expect(c.byId('box')!['x'], 300);
      c.undo();
      expect(c.byId('box')!['fill'], '#ff0000');
      c.undo();
      expect(c.byId('box')!['x'], 100);
      c.redo();
      expect(c.byId('box')!['x'], 300);
      expect(c.dirty, isTrue);
    });

    test('locked elements survive delete; duplicates are offset and selected', () {
      final c = _controller();
      c.updateElement('box', {'locked': true});
      c.removeElements(['box', 'title']);
      expect(c.elements.map((e) => e['id']), ['box']);
      c.duplicateElements(['box']);
      expect(c.elements.length, 2);
      expect(c.selected!['x'], 124);
    });

    test('resizing the canvas refits elements proportionally', () {
      final c = _controller();
      c.resizeCanvas(500, 500);
      expect(c.byId('box')!['width'], 100);
      expect(c.byId('title')!['fontSize'], 20);
    });

    test('grouping rebases members onto the group corner; ungroup restores them', () {
      final c = _controller();
      c.groupElements(['box', 'title']);
      expect(c.elements.length, 1);
      final g = c.elements.single;
      expect(g['type'], 'group');
      expect([g['x'], g['y'], g['width'], g['height']], [100, 100, 700, 580]);
      expect(((g['children'] as List).last as Map)['x'], 400);
      c.ungroup(g['id'] as String);
      expect(c.byId('title')!['x'], 500);
      expect(c.byId('box')!['y'], 100);
    });

    test('copy → paste adds fresh copies, offset; foreign clipboard text is ignored', () {
      final c = _controller();
      c.select('box');
      final text = c.copySelection();
      expect(DesignEditorController.decodeClipboard('hello'), isNull);
      expect(c.paste(text), isTrue);
      expect(c.elements.length, 3);
      expect(c.selected!['id'], isNot('box'));
      expect(c.selected!['x'], 124);
    });

    test('applying a template replaces the design, undoably', () {
      final c = _controller();
      c.replaceDesign(
        {'width': 500, 'height': 500},
        [
          {'type': 'shape', 'shape': 'circle', 'x': 0, 'y': 0, 'width': 10, 'height': 10},
        ],
      );
      expect(c.elements.single['shape'], 'circle');
      c.undo();
      expect(c.elements.length, 2);
      expect(c.canvasWidth, 1000);
    });

    test('a group member moves in absolute terms and stays inside its group', () {
      final c = _controller();
      c.groupElements(['box', 'title']);
      final g = c.elements.single['id'] as String;
      // Rotate the group 90°: the member's view swings about the group centre.
      c.updateElement(g, {'rotation': 90});
      final view = c.byId('box')!;
      expect(view['groupId'], g);
      expect(view['rotation'], 90);
      // Moving the view by +10 in x and reading it back is an exact round trip.
      c.updateElement('box', {'x': (view['x'] as num) + 10});
      expect(c.byId('box')!['x'], closeTo((view['x'] as num) + 10, 0.001));
      expect(c.byId('box')!['y'], closeTo(view['y'] as num, 0.001));
      expect(c.elements.length, 1);
    });

    test('deleting a member below two dissolves the group', () {
      final c = _controller();
      c.groupElements(['box', 'title']);
      c.removeElements(['title']);
      expect(c.elements.single['id'], 'box');
      expect(c.elements.single['x'], closeTo(100, 0.001));
      expect(c.elements.single.containsKey('groupId'), isFalse);
    });

    test('animation frames: entrances start hidden and end at rest', () {
      final rise = {'type': 'rise', 'speed': 'medium'};
      expect(animationLength(rise), closeTo(0.7, 1e-9));
      expect(animationFrame(rise, 0).opacity, 0);
      expect(animationFrame(rise, 0).dy, closeTo(26, 0.01));
      expect(animationFrame(rise, 0.7).opacity, 1);
      expect(animationLength({'type': 'pulse', 'speed': 'fast'}), closeTo(0.7 * 0.6 * 3, 1e-9));
      expect(animationFrame(null, 0.2).scale, 1);
    });

    test('layer order moves', () {
      final c = _controller();
      c.moveLayer('title', 'back');
      expect(c.elements.first['id'], 'title');
    });
  });

  group('stage gestures', () {
    Future<(DesignEditorController, List<String>)> pump(WidgetTester tester, {DrawTool? draw}) async {
      final c = _controller();
      final edits = <String>[];
      final scene = DesignScene();
      addTearDown(scene.dispose);
      tester.view.physicalSize = const Size(1032, 1032);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: DesignStage(
              controller: c,
              scene: scene,
              editingId: null,
              onStartEdit: edits.add,
              onCommitText: (_, _) {},
              drawTool: draw,
            ),
          ),
        ),
      );
      return (c, edits);
    }

    // 1032 viewport, 16px margins → the 1000-unit page maps 1:1 at (16, 16).
    Offset screen(double x, double y) => Offset(16 + x, 16 + y);

    testWidgets('dragging an element moves it, as one undo step', (tester) async {
      final (c, _) = await pump(tester);
      final g = await tester.startGesture(screen(200, 150));
      await g.moveBy(const Offset(30, 0));
      await g.moveBy(const Offset(30, 40));
      await g.up();
      expect(c.selectedIds, ['box']);
      expect(c.byId('box')!['x'], closeTo(160, 0.01));
      expect(c.byId('box')!['y'], closeTo(140, 0.01));
      c.undo();
      expect(c.byId('box')!['x'], 100);
    });

    testWidgets('the corner handle scales the selection', (tester) async {
      final (c, _) = await pump(tester);
      c.select('box');
      await tester.pump();
      final g = await tester.startGesture(screen(300, 200)); // bottom-right corner
      await g.moveBy(const Offset(100, 50));
      await g.up();
      expect(c.byId('box')!['width'], closeTo(300, 0.5));
      expect(c.byId('box')!['height'], closeTo(150, 0.5));
    });

    testWidgets('an edge drag crops; holding the edge first stretches', (tester) async {
      final (c, _) = await pump(tester);
      c.select('box');
      await tester.pump();
      // Right edge: drag straight away → a crop window (contents keep 200).
      var g = await tester.startGesture(screen(300, 150));
      await g.moveBy(const Offset(-50, 0));
      await g.up();
      expect(c.byId('box')!['width'], closeTo(150, 0.5));
      expect((c.byId('box')!['clip'] as Map)['contentW'], 200);
      c.undo();

      // Hold, then drag → a real resize, no clip.
      g = await tester.startGesture(screen(300, 150));
      await tester.pump(const Duration(milliseconds: 500));
      await g.moveBy(const Offset(100, 0));
      await g.up();
      await tester.pump();
      expect(c.byId('box')!['width'], closeTo(300, 0.5));
      expect(c.byId('box')!['clip'], isNull);
    });

    testWidgets('long-press adds to the selection and takes back out', (tester) async {
      final (c, _) = await pump(tester);
      await tester.tapAt(screen(200, 150));
      expect(c.selectedIds, ['box']);
      await tester.longPressAt(screen(650, 640));
      expect(c.selectedIds, unorderedEquals(['box', 'title']));
      await tester.longPressAt(screen(200, 150));
      expect(c.selectedIds, ['title']);
    });

    testWidgets('draw mode turns a stroke into a draw element; the eraser removes it', (tester) async {
      const pen = DrawTool(type: 'pen', color: '#111827', size: 6, opacity: 1);
      final (c, _) = await pump(tester, draw: pen);
      final g = await tester.startGesture(screen(600, 100));
      await g.moveBy(const Offset(100, 50));
      await g.moveBy(const Offset(50, 50));
      await g.up();
      final stroke = c.elements.last;
      expect(stroke['type'], 'draw');
      expect(stroke['x'], closeTo(594, 0.5)); // padded by the stroke width
      expect((stroke['points'] as List).length, 3);
      expect(c.byId('box'), isNotNull); // nothing was selected or moved

      c.undo(); // back to two elements, then erase a fresh stroke
      c.addElement(strokeToElement([const Offset(600, 100), const Offset(700, 150)], pen));
      await tester.pumpWidget(const SizedBox());
      final (c2, _) = await pump(
        tester,
        draw: const DrawTool(type: 'eraser', color: '', size: 20, opacity: 1),
      );
      c2.addElement(strokeToElement([const Offset(600, 100), const Offset(700, 150)], pen));
      await tester.tapAt(screen(650, 125));
      expect(c2.elements.where((e) => e['type'] == 'draw'), isEmpty);
    });

    testWidgets('a straight line is edited by its endpoints', (tester) async {
      final (c, _) = await pump(tester);
      final id = c.addElement({
        'type': 'shape',
        'shape': 'line-solid',
        'x': 200,
        'y': 800,
        'width': 400,
        'height': 12,
        'fill': '#111111',
      });
      await tester.pump();
      // Drag the right end (600, 806) up to (600, 606): the left end stays.
      final g = await tester.startGesture(screen(600, 806));
      await g.moveTo(screen(500, 806));
      await g.moveTo(screen(600, 606));
      await g.up();
      final (p1, p2) = DesignStageState.lineEnds(c.byId(id)!);
      expect(p1.dx, closeTo(200, 0.5));
      expect(p1.dy, closeTo(806, 0.5));
      expect(p2.dx, closeTo(600, 0.5));
      expect(p2.dy, closeTo(606, 0.5));
    });

    testWidgets('tapping into a selected group selects the member under the finger', (tester) async {
      final (c, _) = await pump(tester);
      c.groupElements(['box', 'title']);
      await tester.pump();
      await tester.tapAt(screen(650, 640));
      expect(c.selectedIds, ['title']);
      final g = await tester.startGesture(screen(650, 640));
      await g.moveBy(const Offset(20, 0));
      await g.moveBy(const Offset(20, 0));
      await g.up();
      expect(c.byId('title')!['x'], closeTo(540, 0.5));
      expect(c.elements.length, 1); // still grouped
    });

    testWidgets('tapping empty space clears the selection', (tester) async {
      final (c, _) = await pump(tester);
      c.select('box');
      await tester.tapAt(screen(900, 100));
      expect(c.selectedIds, isEmpty);
    });

    testWidgets('a second tap on selected text starts editing it', (tester) async {
      final (c, edits) = await pump(tester);
      await tester.tapAt(screen(650, 640));
      expect(c.selectedIds, ['title']);
      expect(edits, isEmpty);
      await tester.tapAt(screen(650, 640));
      expect(edits, ['title']);
    });
  });
}
