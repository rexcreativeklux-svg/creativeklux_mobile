import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/api/app_exception.dart';
import '../../../core/design/charts.dart';
import '../../../core/design/grids.dart';
import '../../../core/design/js_values.dart';
import '../../../core/design/table_utils.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import '../design_editor_controller.dart';
import '../editor_sheets.dart';
import 'element_libraries_section.dart' show CountStepper;

/// Editing tables, charts, grids and frames after they're on the page — the
/// table / chart / grid / frame branches of the web's `EditorContextBar.jsx`
/// (its ChartDataPopover, RoundingPopover, Stepper, ReplaceImageButton…).
///
/// On the web they're toolbar buttons and popovers; here each is a bottom sheet
/// that leaves the artboard visible above it, acts on the SELECTED element and
/// applies live, like editor_sheets.dart.

/// The sheet chrome these share: title row + body, at most [heightFactor] of
/// the screen. [enableDrag] false for sheets with a drawing surface.
Future<void> elementSheet(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) body,
  double heightFactor = 0.55,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: enableDrag,
    // Light scrim: the point of these sheets is watching the design change.
    barrierColor: Colors.black.withValues(alpha: 0.08),
    backgroundColor: context.colors.surface.withValues(alpha: 1),
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => Padding(
      // Keep text fields above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * heightFactor),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ctx.colors.gray800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(LucideIcons.chevronDown, size: 18, color: ctx.colors.gray400),
                  ),
                ],
              ),
            ),
            Flexible(child: body(ctx)),
          ],
        ),
      ),
    ),
  );
}

/// The selected element if it is of [type], else null (the sheet then shows
/// nothing — e.g. after an undo removed it).
Map<String, dynamic>? _selectedOf(DesignEditorController c, String type) {
  final el = c.selected;
  return el != null && el['type'] == type ? el : null;
}

Widget _toggle(
  BuildContext context, {
  required IconData icon,
  required bool active,
  required VoidCallback onTap,
  String? tooltip,
}) {
  final col = context.colors;
  return Tooltip(
    message: tooltip ?? '',
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 36,
        decoration: BoxDecoration(
          color: active ? col.blueTint : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppColors.blue500 : col.gray200),
        ),
        child: Icon(icon, size: 17, color: active ? AppColors.blue600 : col.gray600),
      ),
    ),
  );
}

ButtonStyle _outlined(BuildContext context) => OutlinedButton.styleFrom(
  foregroundColor: context.colors.gray700,
  side: BorderSide(color: context.colors.gray200),
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
);

/// Text fields that edit the element as you type: the FIRST keystroke into a
/// field records one undo step, the rest of that field's typing rides on it
/// (the web records every keystroke; one step per field is kinder to undo).
class _UndoOnce {
  Object? _key;
  bool record(Object key) {
    if (_key == key) return false;
    _key = key;
    return true;
  }
}

// ── Chart (ChartDataPopover + the chart-type toggles) ─────────────────────────

const chartTypeIcons = {
  'bar': LucideIcons.chartColumn,
  'line': LucideIcons.chartLine,
  'pie': LucideIcons.chartPie,
  'donut': LucideIcons.circleDashed,
};

/// Chart type + editable label/value rows for the selected chart.
Future<void> showChartDataSheet(BuildContext context, DesignEditorController c) => elementSheet(
  context,
  title: 'Chart data',
  heightFactor: 0.6,
  body: (_) => _ChartData(c: c),
);

class _ChartData extends StatefulWidget {
  const _ChartData({required this.c});
  final DesignEditorController c;
  @override
  State<_ChartData> createState() => _ChartDataState();
}

class _ChartDataState extends State<_ChartData> {
  final _labels = <TextEditingController>[];
  final _values = <TextEditingController>[];
  final _undo = _UndoOnce();

  DesignEditorController get c => widget.c;

  @override
  void dispose() {
    for (final t in [..._labels, ..._values]) {
      t.dispose();
    }
    super.dispose();
  }

  /// Keep one controller pair per row; only overwrite a field's text when the
  /// data changed from elsewhere (undo), so the caret isn't reset mid-typing.
  void _sync(List<Map<String, dynamic>> rows) {
    while (_labels.length > rows.length) {
      _labels.removeLast().dispose();
      _values.removeLast().dispose();
    }
    for (var i = 0; i < rows.length; i++) {
      final label = '${rows[i]['label'] ?? ''}';
      final value = _fmt(rows[i]['value']);
      if (i >= _labels.length) {
        _labels.add(TextEditingController(text: label));
        _values.add(TextEditingController(text: value));
        continue;
      }
      if (_labels[i].text != label) _labels[i].text = label;
      if ((numOf(_values[i].text) ?? 0) != (numOf(rows[i]['value']) ?? 0)) _values[i].text = value;
    }
  }

  static String _fmt(Object? v) {
    final n = numOf(v) ?? 0;
    return n == n.roundToDouble() ? '${n.round()}' : '$n';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final el = _selectedOf(c, 'chart');
        if (el == null) return const SizedBox(height: 80);
        final id = el['id'] as String;
        final raw = el['data'];
        // Same as the web: an empty chart edits one blank row.
        var rows = <Map<String, dynamic>>[
          if (raw is List)
            for (final d in raw) ?asMap(d),
        ];
        if (rows.isEmpty) {
          rows = [
            {'label': '', 'value': 0},
          ];
        }
        _sync(rows);
        final col = context.colors;

        void setData(List<Map<String, dynamic>> data, {Object? undoKey}) =>
            c.updateElement(id, {'data': data}, record: undoKey == null || _undo.record(undoKey));

        void setRow(int i, String key, Object value) => setData([
          for (var k = 0; k < rows.length; k++)
            if (k == i) {...rows[k], key: value} else rows[k],
        ], undoKey: '$id:$i:$key');

        final type = truthy(el['chart']) ? '${el['chart']}' : 'bar';
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            sectionLabel(context, 'Chart type'),
            Row(
              children: [
                for (final (t, label) in chartTypes) ...[
                  _toggle(
                    context,
                    icon: chartTypeIcons[t]!,
                    tooltip: '$label chart',
                    active: type == t,
                    onTap: () => c.updateElement(id, {'chart': t}),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 16),
            sectionLabel(context, 'Data'),
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(int.parse('FF${chartPalette[i % chartPalette.length].substring(1)}', radix: 16)),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _labels[i],
                        decoration: _dense('Label'),
                        style: TextStyle(fontSize: 13, color: col.gray800),
                        onChanged: (v) => setRow(i, 'label', v),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 76,
                      child: TextField(
                        controller: _values[i],
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
                        decoration: _dense('0'),
                        style: TextStyle(
                          fontSize: 13,
                          color: col.gray800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        // Number('') is 0 on the web too.
                        onChanged: (v) {
                          final n = double.tryParse(v) ?? 0;
                          setRow(i, 'value', n == n.roundToDouble() ? n.round() : n);
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove row',
                      // The last row stays — a chart needs something to draw.
                      onPressed: rows.length <= 1 ? null : () => setData([...rows]..removeAt(i)),
                      icon: Icon(LucideIcons.trash2, size: 16, color: col.gray400),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => setData([
                ...rows,
                {'label': 'New', 'value': 0},
              ]),
              icon: const Icon(LucideIcons.plus, size: 15),
              label: const Text('Add row'),
              style: _outlined(context),
            ),
          ],
        );
      },
    );
  }
}

InputDecoration _dense(String hint) => InputDecoration(
  hintText: hint,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
);

// ── Table (the table branch: colours, header row, align, rows/cols, cells) ────

/// Everything the web's table toolbar offers, plus editing every cell's text
/// (the web edits cells inline on the canvas; on a phone a grid of fields
/// is easier to hit than a 40px cell on a zoomed-out page).
Future<void> showTableEditSheet(BuildContext context, DesignEditorController c) => elementSheet(
  context,
  title: 'Table',
  heightFactor: 0.7,
  body: (_) => _TableEdit(c: c),
);

/// Edit one cell — call from the stage when a table cell is tapped (find the
/// cell with `tableCellAt` from core/design/table_utils.dart). Also offers the
/// web's "delete selected row / column" for that cell.
Future<void> showTableCellSheet(BuildContext context, DesignEditorController c, int row, int col) => elementSheet(
  context,
  title: 'Cell ${row + 1}, ${col + 1}',
  body: (_) => _TableCell(c: c, row: row, col: col),
);

/// Colour chips for the table's four colour keys, opening the shared colour sheet.
Widget _tableColours(BuildContext context, DesignEditorController c, Map<String, dynamic> el) {
  final col = context.colors;
  Widget chip(String label, String key, String fallback) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showColorSheet(context, c, title: '$label colour', keys: [key], fallback: fallback),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Swatch(value: truthy(el[key]) ? el[key] as Object : fallback, size: 34),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 11, color: col.gray600)),
          ],
        ),
      ),
    ),
  );
  return Row(
    children: [
      chip('Header', 'headerFill', '#f3f4f6'),
      chip('Cells', 'cellFill', '#ffffff'),
      chip('Text', 'textColor', '#111827'),
      chip('Border', 'borderColor', '#d1d5db'),
    ],
  );
}

/// Apply a table_utils patch; `{}` (the 1×1 limit) does nothing, so hitting
/// the limit doesn't push an empty undo step.
void _tableEdit(DesignEditorController c, String id, Map<String, dynamic> patch) {
  if (patch.isNotEmpty) c.updateElement(id, patch);
}

class _TableEdit extends StatefulWidget {
  const _TableEdit({required this.c});
  final DesignEditorController c;
  @override
  State<_TableEdit> createState() => _TableEditState();
}

class _TableEditState extends State<_TableEdit> {
  final _fields = <(int, int), TextEditingController>{};
  final _undo = _UndoOnce();

  DesignEditorController get c => widget.c;

  @override
  void dispose() {
    for (final t in _fields.values) {
      t.dispose();
    }
    super.dispose();
  }

  TextEditingController _field(int r, int col, String text) {
    final t = _fields.putIfAbsent((r, col), () => TextEditingController(text: text));
    if (t.text != text) t.text = text;
    return t;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final el = _selectedOf(c, 'table');
        if (el == null) return const SizedBox(height: 80);
        final id = el['id'] as String;
        final col = context.colors;
        final rows = tableRows(el), cols = tableCols(el);
        final header = el['headerRow'] != false;
        final align = '${el['align'] ?? 'left'}';
        // Drop controllers for cells that no longer exist.
        _fields.removeWhere((k, t) {
          final gone = k.$1 >= rows || k.$2 >= cols;
          if (gone) t.dispose();
          return gone;
        });

        Widget action(IconData icon, String label, Map<String, dynamic> Function(Map<String, dynamic>) fn) => Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _tableEdit(c, id, fn(el)),
            icon: Icon(icon, size: 15),
            label: Text(label, overflow: TextOverflow.ellipsis),
            style: _outlined(context),
          ),
        );

        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            sectionLabel(context, 'Colours'),
            _tableColours(context, c, el),
            const SizedBox(height: 14),
            Row(
              children: [
                _toggle(
                  context,
                  icon: LucideIcons.panelTop,
                  tooltip: 'Header row',
                  active: header,
                  onTap: () => c.updateElement(id, {'headerRow': !header}),
                ),
                const SizedBox(width: 6),
                Text('Header row', style: TextStyle(fontSize: 12.5, color: col.gray600)),
                const Spacer(),
                for (final (a, icon) in const [
                  ('left', LucideIcons.textAlignStart),
                  ('center', LucideIcons.textAlignCenter),
                  ('right', LucideIcons.textAlignEnd),
                ]) ...[
                  const SizedBox(width: 6),
                  _toggle(
                    context,
                    icon: icon,
                    tooltip: 'Align $a',
                    active: align == a,
                    onTap: () => c.updateElement(id, {'align': a}),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            sectionLabel(context, 'Rows & columns'),
            Row(
              children: [
                action(LucideIcons.betweenHorizontalEnd, 'Add row', (e) => tableAddRow(e)),
                const SizedBox(width: 8),
                action(LucideIcons.betweenVerticalEnd, 'Add column', (e) => tableAddCol(e)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                action(LucideIcons.minus, 'Last row', (e) => tableRemoveRow(e)),
                const SizedBox(width: 8),
                action(LucideIcons.minus, 'Last column', (e) => tableRemoveCol(e)),
              ],
            ),
            const SizedBox(height: 16),
            sectionLabel(context, 'Cells'),
            // Horizontally scrollable when the columns don't fit.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var r = 0; r < rows; r++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          for (var k = 0; k < cols; k++)
                            Container(
                              width: 112,
                              margin: const EdgeInsets.only(right: 4),
                              child: TextField(
                                controller: _field(r, k, tableCell(el, r, k)),
                                decoration: _dense(''),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: col.gray800,
                                  fontWeight: header && r == 0 ? FontWeight.w600 : FontWeight.w400,
                                ),
                                onChanged: (v) {
                                  // Read the freshest element: another field may have just written.
                                  final now = c.byId(id);
                                  if (now == null) return;
                                  c.updateElement(id, tableSetCell(now, r, k, v), record: _undo.record('$id:$r:$k'));
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TableCell extends StatefulWidget {
  const _TableCell({required this.c, required this.row, required this.col});
  final DesignEditorController c;
  final int row;
  final int col;
  @override
  State<_TableCell> createState() => _TableCellState();
}

class _TableCellState extends State<_TableCell> {
  late final TextEditingController _text;
  final _undo = _UndoOnce();

  @override
  void initState() {
    super.initState();
    final el = _selectedOf(widget.c, 'table');
    _text = TextEditingController(text: el == null ? '' : tableCell(el, widget.row, widget.col));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final el = _selectedOf(c, 'table');
    if (el == null) return const SizedBox(height: 80);
    final id = el['id'] as String;

    // The web's "Delete selected row/column": the clicked cell's track.
    void remove(Map<String, dynamic> patch) {
      if (patch.isEmpty) return;
      c.updateElement(id, patch);
      Navigator.pop(context);
    }

    Widget btn(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label, overflow: TextOverflow.ellipsis),
        style: _outlined(context),
      ),
    );

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        TextField(
          controller: _text,
          autofocus: true,
          minLines: 1,
          maxLines: 3,
          decoration: _dense('Cell text'),
          onChanged: (v) {
            final now = c.byId(id);
            if (now != null) {
              c.updateElement(id, tableSetCell(now, widget.row, widget.col, v), record: _undo.record(id));
            }
          },
          onSubmitted: (_) => Navigator.pop(context),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            btn(LucideIcons.betweenHorizontalEnd, 'Row below', () => _tableEdit(c, id, tableAddRow(el, widget.row))),
            const SizedBox(width: 8),
            btn(LucideIcons.betweenVerticalEnd, 'Column right', () => _tableEdit(c, id, tableAddCol(el, widget.col))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            btn(LucideIcons.trash2, 'Delete row', () => remove(tableRemoveRow(el, widget.row))),
            const SizedBox(width: 8),
            btn(LucideIcons.trash2, 'Delete column', () => remove(tableRemoveCol(el, widget.col))),
          ],
        ),
      ],
    );
  }
}

// ── Grid (rows/cols steppers, gap, corner rounding, cell pictures) ────────────

/// The grid branch of the context bar: Rows / Cols steppers (1–12), Gap,
/// corner rounding, plus a cell map to fill or clear each cell's picture (the
/// web's double-click / drop-on-cell).
Future<void> showGridSheet(BuildContext context, DesignEditorController c) => elementSheet(
  context,
  title: 'Grid',
  heightFactor: 0.65,
  body: (_) => _GridEdit(c: c),
);

class _GridEdit extends StatefulWidget {
  const _GridEdit({required this.c});
  final DesignEditorController c;
  @override
  State<_GridEdit> createState() => _GridEditState();
}

class _GridEditState extends State<_GridEdit> {
  var _sliding = false;

  DesignEditorController get c => widget.c;

  /// One undo step per slide.
  void _slide(String id, Map<String, dynamic> patch) {
    c.updateElement(id, patch, record: !_sliding);
    _sliding = true;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final el = _selectedOf(c, 'grid');
        if (el == null) return const SizedBox(height: 80);
        final id = el['id'] as String;
        final col = context.colors;
        final rows = math.max(1, orNum(el['rows'], 1).toInt());
        final cols = math.max(1, orNum(el['cols'], 1).toInt());
        final gap = nnNum(el['gap'], 8).clamp(0.0, 40.0);
        final maxR = math.max(1.0, gridCellMaxRadius(el));
        final radius = nnNum(el['cellRadius'], 0).clamp(0.0, maxR);
        final cells = el['cells'];

        Widget slider(String label, double value, double max, ValueChanged<double> onChanged) => Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(label, style: TextStyle(fontSize: 13, color: col.gray700)),
            ),
            Expanded(
              child: Slider(value: value, max: max, onChanged: onChanged, onChangeEnd: (_) => _sliding = false),
            ),
            SizedBox(
              width: 32,
              child: Text(
                '${value.round()}',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.5, color: col.gray600),
              ),
            ),
          ],
        );

        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Row(
              children: [
                Text('Rows', style: TextStyle(fontSize: 13, color: col.gray700)),
                const SizedBox(width: 8),
                // A count change resets the track weights to equal.
                CountStepper(
                  value: rows,
                  label: 'Rows',
                  onChanged: (v) =>
                      c.updateElement(id, {'rows': v, 'cells': resizeGridCells(cells, v, cols), 'rowFr': null}),
                ),
                const Spacer(),
                Text('Cols', style: TextStyle(fontSize: 13, color: col.gray700)),
                const SizedBox(width: 8),
                CountStepper(
                  value: cols,
                  label: 'Cols',
                  onChanged: (v) =>
                      c.updateElement(id, {'cols': v, 'cells': resizeGridCells(cells, rows, v), 'colFr': null}),
                ),
              ],
            ),
            const SizedBox(height: 8),
            slider('Gap', gap, 40, (v) => _slide(id, {'gap': v.roundToDouble()})),
            slider('Corners', radius, maxR, (v) => _slide(id, {'cellRadius': v.roundToDouble()})),
            const SizedBox(height: 8),
            sectionLabel(context, 'Pictures — tap a cell'),
            AspectRatio(
              aspectRatio: orNum(el['width'], 1) / orNum(el['height'], 1),
              child: LayoutBuilder(
                builder: (context, box) {
                  // The grid's own cell layout, scaled into the sheet.
                  final s = box.maxWidth / orNum(el['width'], 1);
                  return Stack(
                    children: [
                      for (final cell in gridCellRects(el))
                        Positioned(
                          left: cell.rect.left * s,
                          top: cell.rect.top * s,
                          width: cell.rect.width * s,
                          height: cell.rect.height * s,
                          child: _GridCellTile(
                            src: _cellSrc(el, cell.index),
                            onTap: () => showFrameImageSheet(context, c, cellIndex: cell.index),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A grid cell's picture URL, or null.
Object? _cellSrc(Map<String, dynamic> el, int index) {
  final cells = el['cells'];
  if (cells is! List || index < 0 || index >= cells.length) return null;
  return asMap(cells[index])?['src'];
}

class _GridCellTile extends StatelessWidget {
  const _GridCellTile({required this.src, required this.onTap});
  final Object? src;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    final url = src is String && (src as String).startsWith('http') ? src as String : null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: col.gray200, borderRadius: BorderRadius.circular(4)),
        child: url != null
            ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox())
            : Icon(LucideIcons.imagePlus, size: 18, color: col.gray400),
      ),
    );
  }
}

// ── Frame / grid-cell picture (ReplaceImageButton, fillFrame, fillGridCell) ───

/// Fill, replace or detach the picture of the selected frame — or, with
/// [cellIndex], of one cell of the selected grid. Frames also get the web's
/// Flip horizontal / vertical toggles.
Future<void> showFrameImageSheet(BuildContext context, DesignEditorController c, {int? cellIndex}) => elementSheet(
  context,
  title: cellIndex == null ? 'Frame' : 'Grid cell ${cellIndex + 1}',
  body: (ctx) => ListenableBuilder(
    listenable: c,
    builder: (ctx, _) {
      final el = c.selected;
      final ok = el != null && (cellIndex == null ? el['type'] == 'frame' : el['type'] == 'grid');
      if (!ok) return const SizedBox(height: 80);
      final id = el['id'] as String;
      final src = cellIndex == null ? el['src'] : _cellSrc(el, cellIndex);
      final filled = src is String && src.isNotEmpty;

      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await pickFrameImage(context, c, id, cellIndex: cellIndex);
            },
            icon: const Icon(LucideIcons.imageUp, size: 16),
            label: Text(filled ? 'Replace image' : 'Choose from phone'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.blue600,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          if (filled) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  c.updateElement(id, cellIndex == null ? {'src': null} : gridCellSrcPatch(el, cellIndex, null)),
              icon: const Icon(LucideIcons.imageOff, size: 16),
              label: Text(cellIndex == null ? 'Detach image' : 'Remove image'),
              style: _outlined(ctx),
            ),
          ],
          if (cellIndex == null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _toggle(
                  ctx,
                  icon: LucideIcons.flipHorizontal2,
                  tooltip: 'Flip horizontal',
                  active: truthy(el['flipH']),
                  onTap: () => c.updateElement(id, {'flipH': !truthy(el['flipH'])}),
                ),
                const SizedBox(width: 8),
                _toggle(
                  ctx,
                  icon: LucideIcons.flipVertical2,
                  tooltip: 'Flip vertical',
                  active: truthy(el['flipV']),
                  onTap: () => c.updateElement(id, {'flipV': !truthy(el['flipV'])}),
                ),
              ],
            ),
          ],
        ],
      );
    },
  ),
);

/// Pick a photo, upload it (`POST /gallery`) and set it as frame [id]'s
/// picture, or grid cell [cellIndex]'s. Usable directly as a "Replace" tool.
///
/// The web shows the local file at once and swaps the durable URL in after;
/// the app has no blob URLs, so it waits for the upload (with a toast) rather
/// than writing a multi-megabyte data URL into the design.
Future<void> pickFrameImage(BuildContext context, DesignEditorController c, String id, {int? cellIndex}) async {
  final brandApi = context.read<AuthController>().brandApi;
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (file == null) return;
  Toast.info('Uploading…');
  try {
    final url = await brandApi.uploadImage(await file.readAsBytes(), file.name);
    if (url == null) throw AppException('The upload returned no file URL.');
    // The freshest element, so a cell filled while this upload was in flight
    // isn't clobbered (setGridCellSrc on the web).
    final now = c.byId(id);
    if (now == null) return;
    c.updateElement(id, cellIndex == null ? {'src': url} : gridCellSrcPatch(now, cellIndex, url));
  } catch (err) {
    Toast.error(toUserMessage(err, "Couldn't upload the image."));
  }
}
