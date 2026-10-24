import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'js_values.dart';

/// Pure helpers for the "table" design element — port of the web's
/// `(lib)/design/tableUtils.js`.
///
/// A table stores its text as a row-major 2D list of strings,
/// `cells[row][col]`, plus `rows`/`cols` counts kept in sync with it. Every
/// helper returns a PATCH for `updateElement` (never mutates), and `{}` when
/// the edit would be a no-op — callers skip those so the limit doesn't push an
/// empty undo step.

const tableDefaults = <String, dynamic>{
  'borderColor': '#d1d5db',
  'borderWidth': 1,
  'headerRow': true,
  'headerFill': '#f3f4f6',
  'cellFill': '#ffffff',
  'textColor': '#111827',
  'fontSize': 16,
  'align': 'left',
};

int tableRows(Map<String, dynamic> el) => math.max(0, orNum(el['rows'], 0).toInt());
int tableCols(Map<String, dynamic> el) => math.max(0, orNum(el['cols'], 0).toInt());

/// A rows × cols grid of empty strings.
List<List<String>> makeCells(int rows, int cols) => [
  for (var r = 0; r < rows; r++) [for (var c = 0; c < cols; c++) ''],
];

/// [cells] padded/truncated to exactly rows × cols.
List<List<String>> normalizeCells(Object? cells, int rows, int cols) => [
  for (var r = 0; r < rows; r++)
    [
      for (var c = 0; c < cols; c++)
        if (cells is List && r < cells.length && cells[r] is List && c < (cells[r] as List).length)
          '${(cells[r] as List)[c] ?? ''}'
        else
          '',
    ],
];

/// Relative track weights; equal when the table was never hand-resized.
List<double> tableColFractions(Map<String, dynamic> el) => _fractions(el['colFractions'], tableCols(el));
List<double> tableRowFractions(Map<String, dynamic> el) => _fractions(el['rowFractions'], tableRows(el));

List<double> _fractions(Object? raw, int n) =>
    raw is List && raw.length == n ? [for (final f in raw) numOf(f) ?? 1] : List.filled(n, 1.0);

List<T> _insertAt<T>(List<T> list, int index, T value) => [...list.take(index), value, ...list.skip(index)];

/// Insert a blank row after [at] (default: at the end).
Map<String, dynamic> tableAddRow(Map<String, dynamic> el, [int? at]) {
  final rows = tableRows(el), cols = tableCols(el);
  final cells = normalizeCells(el['cells'], rows, cols);
  final index = at == null ? cells.length : math.min(at + 1, cells.length);
  final next = _insertAt(cells, index, List.filled(cols, ''));
  return {
    'cells': next,
    'rows': next.length,
    // Weights are only tracked once the table has been hand-resized.
    if (el['rowFractions'] is List) 'rowFractions': _insertAt(tableRowFractions(el), index, 1.0),
  };
}

/// Insert a blank column after [at] (default: at the end).
Map<String, dynamic> tableAddCol(Map<String, dynamic> el, [int? at]) {
  final rows = tableRows(el), cols = tableCols(el);
  final cells = normalizeCells(el['cells'], rows, cols);
  final index = at == null ? cols : math.min(at + 1, cols);
  return {
    'cells': [for (final row in cells) _insertAt(row, index, '')],
    'cols': cols + 1,
    if (el['colFractions'] is List) 'colFractions': _insertAt(tableColFractions(el), index, 1.0),
  };
}

/// Remove row [at] (default: the last). Keeps at least one row.
Map<String, dynamic> tableRemoveRow(Map<String, dynamic> el, [int? at]) {
  final rows = tableRows(el), cols = tableCols(el);
  if (rows <= 1) return {};
  final cells = normalizeCells(el['cells'], rows, cols);
  final index = at ?? rows - 1;
  final next = [
    for (var r = 0; r < rows; r++)
      if (r != index) cells[r],
  ];
  final fr = tableRowFractions(el);
  return {
    'cells': next,
    'rows': next.length,
    if (el['rowFractions'] is List)
      'rowFractions': [
        for (var r = 0; r < fr.length; r++)
          if (r != index) fr[r],
      ],
  };
}

/// Remove column [at] (default: the last). Keeps at least one column.
Map<String, dynamic> tableRemoveCol(Map<String, dynamic> el, [int? at]) {
  final rows = tableRows(el), cols = tableCols(el);
  if (cols <= 1) return {};
  final cells = normalizeCells(el['cells'], rows, cols);
  final index = at ?? cols - 1;
  final fr = tableColFractions(el);
  return {
    'cells': [
      for (final row in cells)
        [
          for (var c = 0; c < cols; c++)
            if (c != index) row[c],
        ],
    ],
    'cols': cols - 1,
    if (el['colFractions'] is List)
      'colFractions': [
        for (var c = 0; c < fr.length; c++)
          if (c != index) fr[c],
      ],
  };
}

/// Write [value] into cell ([r], [c]).
Map<String, dynamic> tableSetCell(Map<String, dynamic> el, int r, int c, String value) {
  final cells = normalizeCells(el['cells'], tableRows(el), tableCols(el));
  if (r >= 0 && r < cells.length && c >= 0 && c < cells[r].length) cells[r][c] = value;
  return {'cells': cells};
}

/// The text in cell ([r], [c]), or ''.
String tableCell(Map<String, dynamic> el, int r, int c) {
  final cells = el['cells'];
  if (cells is! List || r < 0 || r >= cells.length) return '';
  final row = cells[r];
  return row is List && c >= 0 && c < row.length && row[c] != null ? '${row[c]}' : '';
}

/// Which cell an element-LOCAL point (origin at the table's top-left, before
/// rotation) falls in — the same track maths as the renderer's `_table`
/// (border lines between cells). For the stage's tap-to-edit; null outside.
(int, int)? tableCellAt(Map<String, dynamic> el, Offset local) {
  final rows = tableRows(el), cols = tableCols(el);
  final w = orNum(el['width'], 0), h = orNum(el['height'], 0);
  if (rows == 0 || cols == 0 || local.dx < 0 || local.dy < 0 || local.dx > w || local.dy > h) return null;
  final bw = nnNum(el['borderWidth'], 1);
  int track(double pos, List<double> fr, double size, int n) {
    final sum = fr.fold<double>(0, (a, b) => a + b);
    final content = size - bw * (n + 1);
    var edge = bw;
    for (var i = 0; i < n; i++) {
      edge += (sum == 0 ? 1 / n : fr[i] / sum) * content + bw;
      if (pos < edge) return i;
    }
    return n - 1;
  }

  return (track(local.dy, tableRowFractions(el), h, rows), track(local.dx, tableColFractions(el), w, cols));
}
