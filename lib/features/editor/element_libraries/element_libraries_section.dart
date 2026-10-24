import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_drawing/path_drawing.dart';

import '../../../core/design/charts.dart';
import '../../../core/design/frames.dart';
import '../../../core/design/graphics.dart';
import '../../../core/design/grids.dart';
import '../../../core/design/shapes.dart';
import '../../../core/theme/app_colors.dart';
import '../design_editor_controller.dart';
import 'element_inserts.dart';

/// The Elements panel's libraries beyond shapes — ports of the web's
/// `panels/elements/` GraphicsLibrary, ChartsLibrary, TablesLibrary,
/// FramesLibrary and GridsLibrary.
///
/// The web drills into one category at a time from a "Browse categories" tile
/// grid; in a 300px column (or a ~42%-height phone panel) collapsible sections
/// read better, so each category is a header (same icon and gradient as the
/// web's CategoryTile) that opens its library inline. It's a plain Column —
/// drop it into the Elements panel's ListView.
class ElementLibrariesSection extends StatefulWidget {
  const ElementLibrariesSection({super.key, required this.c, this.onInserted, this.initiallyOpen = const {}});

  final DesignEditorController c;

  /// Called after anything is inserted — e.g. to close the phone panel so the
  /// new element is visible.
  final VoidCallback? onInserted;

  /// Category ids open at first: 'graphics' | 'charts' | 'tables' | 'frames' | 'grids'.
  final Set<String> initiallyOpen;

  @override
  State<ElementLibrariesSection> createState() => _ElementLibrariesSectionState();
}

// The web's category gradients (categories.js) — decorative tiles that look
// the same in both themes, so literal colours, like the web's Tailwind pairs.
const _categories = [
  ('graphics', 'Graphics', LucideIcons.sparkles, Color(0xFFFBBF24), Color(0xFFEA580C)),
  ('charts', 'Charts', LucideIcons.chartColumn, Color(0xFFA78BFA), Color(0xFF9333EA)),
  ('tables', 'Tables', LucideIcons.table, Color(0xFFFB923C), Color(0xFFD97706)),
  ('frames', 'Frames', LucideIcons.frame, Color(0xFF2DD4BF), Color(0xFF059669)),
  ('grids', 'Grids', LucideIcons.grid3x3, Color(0xFFF472B6), Color(0xFFC026D3)),
];

class _ElementLibrariesSectionState extends State<ElementLibrariesSection> {
  late final Set<String> _open = {...widget.initiallyOpen};

  void _done(String _) => widget.onInserted?.call();

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (id, label, icon, from, to) in _categories) ...[
          _Header(
            label: label,
            icon: icon,
            gradient: [from, to],
            open: _open.contains(id),
            onTap: () => setState(() => _open.contains(id) ? _open.remove(id) : _open.add(id)),
          ),
          if (_open.contains(id))
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 14),
              child: switch (id) {
                'graphics' => GraphicsLibrary(onPick: (k) => _done(insertGraphic(c, k))),
                'charts' => ChartsLibrary(onPick: (t) => _done(insertChart(c, t))),
                'tables' => TablesLibrary(
                  onPick: (r, col) => _done(insertTable(c, rows: r, cols: col)),
                ),
                'frames' => FramesLibrary(onPick: (k) => _done(insertFrame(c, k))),
                _ => GridsLibrary(
                  onPick: (r, col) => _done(insertGrid(c, rows: r, cols: col)),
                ),
              },
            )
          else
            const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.open,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    return Material(
      color: col.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: col.gray200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
                ),
                child: Icon(icon, size: 17, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: col.gray800),
                ),
              ),
              Icon(open ? LucideIcons.chevronDown : LucideIcons.chevronRight, size: 18, color: col.gray400),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared tile grid ──────────────────────────────────────────────────────────

/// Square tiles in as many columns as fit (3 in the 300px side panel, more on
/// a wide phone), like the web's `grid grid-cols-3 gap-2`.
Widget _tileGrid({required int count, required Widget Function(int i, double size) tile, double minTile = 82}) {
  return LayoutBuilder(
    builder: (context, box) {
      const gap = 8.0;
      final cols = math.max(3, ((box.maxWidth + gap) / (minTile + gap)).floor());
      final size = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (var i = 0; i < count; i++) SizedBox(width: size, height: size, child: tile(i, size))],
      );
    },
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.onTap, required this.child, this.tooltip, this.padding = 8});
  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    final tile = Material(
      color: col.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: col.gray200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(padding: EdgeInsets.all(padding), child: child),
      ),
    );
    return tooltip == null ? tile : Tooltip(message: tooltip, child: tile);
  }
}

Widget _hint(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(text, style: TextStyle(fontSize: 12, color: context.colors.gray500)),
);

// ── Graphics (GraphicsLibrary.jsx) ────────────────────────────────────────────

class GraphicsLibrary extends StatelessWidget {
  const GraphicsLibrary({super.key, required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    // Previews use the same geometry as the canvas/export, so they can't drift.
    return _tileGrid(
      count: graphics.length,
      tile: (i, _) => _Tile(
        tooltip: graphics[i].label,
        padding: 10,
        onTap: () => onPick(graphics[i].key),
        child: CustomPaint(painter: _GraphicPreview(graphics[i].key), size: Size.infinite),
      ),
    );
  }
}

class _GraphicPreview extends CustomPainter {
  _GraphicPreview(this.keyName);
  final String keyName;
  @override
  void paint(Canvas canvas, Size size) => paintGraphicPreview(canvas, keyName, size);
  @override
  bool shouldRepaint(covariant _GraphicPreview old) => old.keyName != keyName;
}

// ── Charts (ChartsLibrary.jsx) ────────────────────────────────────────────────

class ChartsLibrary extends StatelessWidget {
  const ChartsLibrary({super.key, required this.onPick});

  /// Receives the chart type id ('bar' | 'line' | 'pie' | 'donut').
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    // The web shows an icon per type; here each tile is a real miniature
    // painted by paintChart, which is more telling at thumb size.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hint(context, 'Add a chart, then edit its data from the toolbar.'),
        LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (id, label) in chartTypes)
                  SizedBox(
                    width: w,
                    child: _Tile(
                      onTap: () => onPick(id),
                      tooltip: '$label chart',
                      child: Column(
                        children: [
                          SizedBox(
                            height: 62,
                            child: CustomPaint(painter: _ChartPreview(id), size: Size.infinite),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: col.gray600),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ChartPreview extends CustomPainter {
  _ChartPreview(this.type);
  final String type;

  @override
  void paint(Canvas canvas, Size size) {
    // Laid out at a "real" size so the label text is proportionate, then
    // scaled down into the tile.
    const w = 300.0, h = 198.0;
    final s = math.min(size.width / w, size.height / h);
    canvas.save();
    canvas.translate((size.width - w * s) / 2, (size.height - h * s) / 2);
    canvas.scale(s);
    paintChart(canvas, {'chart': type, 'width': w, 'height': h}, const Rect.fromLTWH(0, 0, w, h));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChartPreview old) => old.type != type;
}

// ── Frames (FramesLibrary.jsx / FramePreview.jsx) ─────────────────────────────

class FramesLibrary extends StatelessWidget {
  const FramesLibrary({super.key, required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hint(context, 'Add a frame, then tap Replace in its toolbar to fill it.'),
        _tileGrid(
          count: frameLibrary.length,
          tile: (i, _) {
            final (key, label) = frameLibrary[i];
            return _Tile(
              tooltip: label,
              onTap: () => onPick(key),
              // The shape as a grey fill with an image glyph — "drop a photo here".
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(painter: _FramePreview(key, col.gray200), size: Size.infinite),
                  Icon(LucideIcons.imagePlus, size: 16, color: col.gray400),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _FramePreview extends CustomPainter {
  _FramePreview(this.frameKey, this.color);
  final String frameKey;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final (vb, d) = frameGeo(frameKey);
    final s = math.min(size.width / vb[0], size.height / vb[1]);
    canvas.save();
    canvas.translate((size.width - vb[0] * s) / 2, (size.height - vb[1] * s) / 2);
    canvas.scale(s);
    canvas.drawPath(parseSvgPathData(d), Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FramePreview old) => old.frameKey != frameKey || old.color != color;
}

// ── Grids (GridsLibrary.jsx / GridPreview.jsx) ────────────────────────────────

class GridsLibrary extends StatelessWidget {
  const GridsLibrary({super.key, required this.onPick});
  final void Function(int rows, int cols) onPick;

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hint(context, 'Add a grid, then tap a cell’s picture button to fill it.'),
        _tileGrid(
          count: gridPresets.length,
          tile: (i, _) {
            final (rows, cols) = gridPresets[i];
            return _Tile(
              tooltip: '$rows × $cols grid',
              onTap: () => onPick(rows, cols),
              child: Column(
                children: [
                  for (var r = 0; r < rows; r++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: r == 0 ? 0 : 4),
                        child: Row(
                          children: [
                            for (var c = 0; c < cols; c++)
                              Expanded(
                                child: Container(
                                  margin: EdgeInsets.only(left: c == 0 ? 0 : 4),
                                  decoration: BoxDecoration(color: col.gray200, borderRadius: BorderRadius.circular(3)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Tables (TablesLibrary.jsx) ────────────────────────────────────────────────

class TablesLibrary extends StatefulWidget {
  const TablesLibrary({super.key, required this.onPick});
  final void Function(int rows, int cols) onPick;

  @override
  State<TablesLibrary> createState() => _TablesLibraryState();
}

class _TablesLibraryState extends State<TablesLibrary> {
  static const _maxRows = 8;
  static const _maxCols = 6;
  static const _limit = 50; // sanity cap for the custom size

  // The web sizes by hovering; touch has no hover, so a tap inserts that size
  // and a long-press-drag sizes the region first, inserting on release.
  var _hover = (3, 3);
  var _rows = 3;
  var _cols = 3;

  void _add(int r, int c) => widget.onPick(r.clamp(1, _limit), c.clamp(1, _limit));

  (int, int) _cellAt(Offset p, double cell, double gap) =>
      (((p.dy / (cell + gap)).floor() + 1).clamp(1, _maxRows), ((p.dx / (cell + gap)).floor() + 1).clamp(1, _maxCols));

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Insert a table',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: col.gray500),
              ),
            ),
            Text(
              '${_hover.$1} × ${_hover.$2}',
              style: TextStyle(fontSize: 12, color: col.gray400, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) {
            const gap = 5.0;
            final cell = math.min(30.0, (box.maxWidth - gap * (_maxCols - 1)) / _maxCols);
            return Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTapUp: (d) {
                  final (r, c) = _cellAt(d.localPosition, cell, gap);
                  setState(() => _hover = (r, c));
                  _add(r, c);
                },
                onLongPressStart: (d) => setState(() => _hover = _cellAt(d.localPosition, cell, gap)),
                onLongPressMoveUpdate: (d) => setState(() => _hover = _cellAt(d.localPosition, cell, gap)),
                onLongPressEnd: (_) => _add(_hover.$1, _hover.$2),
                child: SizedBox(
                  width: cell * _maxCols + gap * (_maxCols - 1),
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < _maxRows * _maxCols; i++)
                        Builder(
                          builder: (context) {
                            final on = i ~/ _maxCols < _hover.$1 && i % _maxCols < _hover.$2;
                            return Container(
                              width: cell,
                              height: cell,
                              decoration: BoxDecoration(
                                color: on ? col.blueTint : col.gray50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: on ? AppColors.blue500 : col.gray200),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        _label(context, 'Popular sizes'),
        Row(
          children: [
            for (final (r, c) in const [(2, 2), (3, 3), (2, 4), (4, 2)]) ...[
              if (r != 2 || c != 2) const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _add(r, c),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: col.gray600,
                    side: BorderSide(color: col.gray200),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('$r × $c', style: const TextStyle(fontSize: 12.5)),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        _label(context, 'Custom size'),
        Row(
          children: [
            CountStepper(value: _rows, max: _limit, label: 'Rows', onChanged: (v) => setState(() => _rows = v)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('×', style: TextStyle(color: col.gray400)),
            ),
            CountStepper(value: _cols, max: _limit, label: 'Cols', onChanged: (v) => setState(() => _cols = v)),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () => _add(_rows, _cols),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue600,
                  minimumSize: const Size(0, 34),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Add', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: context.colors.gray400),
    ),
  );
}

/// Compact − value + stepper (EditorContextBar's `Stepper`; also the custom
/// table size fields). Clamped to [min]–[max].
class CountStepper extends StatelessWidget {
  const CountStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.min = 1,
    this.max = 12,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final String? label;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    Widget btn(IconData icon, int next, String tip) => SizedBox(
      width: 30,
      height: 32,
      child: IconButton(
        tooltip: label == null ? null : '$tip ${label!.toLowerCase()}',
        padding: EdgeInsets.zero,
        onPressed: next < min || next > max ? null : () => onChanged(next),
        icon: Icon(icon, size: 14, color: col.gray600),
      ),
    );
    return Container(
      height: 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: col.gray200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(LucideIcons.minus, value - 1, 'Fewer'),
          SizedBox(
            width: 24,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: col.gray800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          btn(LucideIcons.plus, value + 1, 'More'),
        ],
      ),
    );
  }
}
