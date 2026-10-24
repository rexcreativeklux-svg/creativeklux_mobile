import 'dart:math' as math;

import '../../../core/design/charts.dart';
import '../../../core/design/design_assets.dart';
import '../../../core/design/graphics.dart';
import '../../../core/design/grids.dart';
import '../../../core/design/shapes.dart';
import '../../../core/design/table_utils.dart';
import '../design_editor_controller.dart';

/// Ports of the web editor's insert API for the Elements libraries and the
/// Signature tool (DesignEditor.jsx insertTable / insertGrid / insertFrame /
/// insertGraphic / insertChart, and `tools/signature/insertSignature.js`).
///
/// Every insert lands centred on the page and selected (addElement selects),
/// and returns the new element's id.

double _cx(DesignEditorController c) => (c.canvasWidth / 2).roundToDouble();
double _cy(DesignEditorController c) => (c.canvasHeight / 2).roundToDouble();

/// Size the table to a comfortable fraction of the page, with a per-cell floor
/// so a large table never collapses into unreadable slivers.
String insertTable(DesignEditorController c, {int rows = 3, int cols = 3}) {
  final w = math.min(c.canvasWidth * 0.7, math.max(cols * 120.0, (c.canvasWidth * 0.4).roundToDouble()));
  final h = math.min(c.canvasHeight * 0.7, math.max(rows * 52.0, (c.canvasHeight * 0.28).roundToDouble()));
  return c.addElement({
    'type': 'table',
    'rows': rows,
    'cols': cols,
    'cells': makeCells(rows, cols),
    'x': _cx(c) - w / 2,
    'y': _cy(c) - h / 2,
    'width': w.roundToDouble(),
    'height': h.roundToDouble(),
    ...tableDefaults,
  });
}

/// An empty rows × cols photo grid, a square at 55% of the short side.
String insertGrid(DesignEditorController c, {int rows = 2, int cols = 2}) {
  final base = (math.min(c.canvasWidth, c.canvasHeight) * 0.55).roundToDouble();
  return c.addElement({
    'type': 'grid',
    'rows': rows,
    'cols': cols,
    'gap': 8,
    'cells': makeGridCells(rows, cols),
    'x': _cx(c) - base / 2,
    'y': _cy(c) - base / 2,
    'width': base,
    'height': base,
  });
}

/// An empty frame (an image clipped to a shape), sized to the frame's aspect
/// and capped at 42% of the short side — matching insertShape.
String insertFrame(DesignEditorController c, String frameKey) {
  final (viewBox, _) = frameGeo(frameKey);
  final aspect = viewBox[1] == 0 ? 1.0 : viewBox[0] / viewBox[1];
  final base = math.min(c.canvasWidth, c.canvasHeight) * 0.42;
  final w = aspect >= 1 ? base : base * aspect;
  final h = aspect >= 1 ? base / aspect : base;
  return c.addElement({
    'type': 'frame',
    'shape': frameKey,
    'src': null,
    'x': _cx(c) - w / 2,
    'y': _cy(c) - h / 2,
    'width': w.roundToDouble(),
    'height': h.roundToDouble(),
  });
}

/// A decorative graphic, sized to its aspect at 28% of the short side.
String insertGraphic(DesignEditorController c, String graphicKey) {
  final vb = graphicDef(graphicKey).viewBox;
  final aspect = vb[1] == 0 ? 1.0 : vb[0] / vb[1];
  final base = math.min(c.canvasWidth, c.canvasHeight) * 0.28;
  final w = aspect >= 1 ? base : base * aspect;
  final h = aspect >= 1 ? base / aspect : base;
  return c.addElement({
    'type': 'graphic',
    'graphic': graphicKey,
    'x': _cx(c) - w / 2,
    'y': _cy(c) - h / 2,
    'width': w.roundToDouble(),
    'height': h.roundToDouble(),
  });
}

/// A chart ('bar' | 'line' | 'pie' | 'donut') seeded with sample data.
String insertChart(DesignEditorController c, [String chartType = 'bar']) {
  final w = (math.min(c.canvasWidth, c.canvasHeight) * 0.6).roundToDouble();
  final h = (w * 0.66).roundToDouble();
  return c.addElement({
    'type': 'chart',
    'chart': chartType,
    'data': defaultChartDataCopy(),
    'x': _cx(c) - w / 2,
    'y': _cy(c) - h / 2,
    'width': w,
    'height': h,
  });
}

// ── Signature (insertSignature.js) ───────────────────────────────────────────

/// A typed signature goes on as a TEXT element, not a rasterised image: it
/// stays crisp at any zoom, exports through the normal text path and needs no
/// upload. Same box as the web's insertText for a 64px preset.
String insertSignatureText(
  DesignEditorController c, {
  required String name,
  String? fontFamily,
  String color = '#111827',
}) {
  const fontSize = 64.0;
  final w = math.min(420.0, c.canvasWidth * 0.7);
  const h = fontSize * 1.5;
  return c.addElement({
    'type': 'text',
    'content': name,
    'text': name,
    'x': _cx(c) - w / 2,
    'y': _cy(c) - h / 2,
    'width': w,
    'height': h,
    'fontSize': fontSize,
    'fontWeight': 400,
    'fill': color,
    'textAlign': 'center',
    'fontFamily': ?fontFamily,
  });
}

/// A drawn or uploaded signature — a genuine picture, so an image element
/// (insertImageUrl): 60% of the page width or its own width if smaller,
/// keeping its aspect. Pass [naturalSize] when it's already known (a drawn
/// signature) to skip decoding the image again.
Future<String> insertSignatureImage(DesignEditorController c, String src, {(double, double)? naturalSize}) async {
  var nat = naturalSize;
  if (nat == null) {
    final img = await loadDesignImage(src);
    nat = img == null ? null : (img.width.toDouble(), img.height.toDouble());
    img?.dispose();
  }
  final natW = nat?.$1 ?? c.canvasWidth * 0.4;
  final natH = nat?.$2 ?? c.canvasWidth * 0.4;
  final w = math.min(c.canvasWidth * 0.6, natW);
  final h = w * (natH / natW);
  return c.addElement({'type': 'image', 'src': src, 'x': _cx(c) - w / 2, 'y': _cy(c) - h / 2, 'width': w, 'height': h});
}
