import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'js_values.dart';

/// Grid geometry — the "grid" element type: a rows × cols layout of image
/// cells (Canva-style photo grids). Port of the web's `(lib)/design/grids.js`.
///
/// Cells are laid out row-major with a uniform `gap`, honouring optional
/// per-track weights (`colFr` / `rowFr`). The renderer's `_grid` uses the same
/// arithmetic; this file is the one the editor UI (insert, steppers, cell
/// hit-testing) reads.

/// Layouts offered in the Grids library (rows, cols).
const gridPresets = [(1, 2), (2, 1), (2, 2), (1, 3), (3, 1), (2, 3), (3, 2), (3, 3)];

/// [fr] normalised to length [n] summing to 1; equal weights when missing or
/// the wrong length (e.g. after a rows/cols change).
List<double> normFractions(Object? fr, int n) {
  if (fr is! List || fr.length != n) return List.filled(n, 1 / n);
  final vals = [for (final f in fr) numOf(f) ?? 0];
  final sum = vals.fold<double>(0, (a, b) => a + b);
  return [for (final v in vals) v / (sum == 0 ? 1 : sum)];
}

/// One cell rectangle in element-local coordinates.
typedef GridCell = ({Rect rect, int index, int row, int col});

/// `gridCellRects`: every cell, row-major, origin at the element's top-left.
List<GridCell> gridCellRects(Map<String, dynamic> el) {
  final r = math.max(1, orNum(el['rows'], 1).toInt());
  final c = math.max(1, orNum(el['cols'], 1).toInt());
  final gap = orNum(el['gap'], 0);
  final w = orNum(el['width'], 0), h = orNum(el['height'], 0);
  final colW = [for (final f in normFractions(el['colFr'], c)) f * (w - gap * (c - 1))];
  final rowH = [for (final f in normFractions(el['rowFr'], r)) f * (h - gap * (r - 1))];
  final out = <GridCell>[];
  var y = 0.0;
  for (var row = 0; row < r; row++) {
    var x = 0.0;
    for (var col = 0; col < c; col++) {
      out.add((rect: Rect.fromLTWH(x, y, colW[col], rowH[row]), index: row * c + col, row: row, col: col));
      x += colW[col] + gap;
    }
    y += rowH[row] + gap;
  }
  return out;
}

/// The cell index under an element-LOCAL point, or null (a gap or outside).
int? gridCellAt(Map<String, dynamic> el, Offset local) {
  for (final cell in gridCellRects(el)) {
    if (cell.rect.contains(local)) return cell.index;
  }
  return null;
}

/// Fresh empty-cell list for a rows × cols grid.
List<Map<String, dynamic>> makeGridCells(int rows, int cols) => [
  for (var i = 0; i < math.max(1, rows) * math.max(1, cols); i++) {'src': null},
];

/// Resize a grid's cell list to rows × cols, keeping filled cells by index.
List<Map<String, dynamic>> resizeGridCells(Object? cells, int rows, int cols) => [
  for (var i = 0; i < math.max(1, rows) * math.max(1, cols); i++)
    if (cells is List && i < cells.length && asMap(cells[i]) != null) {...asMap(cells[i])!} else {'src': null},
];

/// Patch writing [src] into one cell without touching the others.
Map<String, dynamic> gridCellSrcPatch(Map<String, dynamic> el, int index, String? src) {
  final rows = math.max(1, orNum(el['rows'], 1).toInt());
  final cols = math.max(1, orNum(el['cols'], 1).toInt());
  final cells = resizeGridCells(el['cells'], rows, cols);
  if (index >= 0 && index < cells.length) cells[index] = {...cells[index], 'src': src};
  return {'cells': cells};
}

/// Half the shortest cell edge — the largest sensible corner radius
/// (EditorContextBar `gridCellMaxRadius`).
double gridCellMaxRadius(Map<String, dynamic> el) {
  final rects = gridCellRects(el);
  if (rects.isEmpty) return math.min(orNum(el['width'], 0), orNum(el['height'], 0)) / 2;
  return (math.min(rects.first.rect.width, rects.first.rect.height) / 2).roundToDouble();
}
