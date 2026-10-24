import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/design/design_renderer.dart';
import '../../../core/theme/app_colors.dart';
import '../design_editor_controller.dart';
import 'text_combo_data.dart';
import 'text_combos.dart';
import 'text_looks.dart';
import 'text_style.dart';
import 'text_tools.dart';

/// The Text panel's library switch — port of the bottom of the web's
/// `panels/TextPanel.jsx` with `text/templates/TextTemplatesTab.jsx`,
/// `TextComboGrid.jsx`, `TextComboCard.jsx` and `text/looks/TextLookRows.jsx`,
/// `TextLookView.jsx`, `TextLookCard.jsx`, `HorizontalStrip.jsx`:
///   Templates — ready-made text designs: two or three text boxes in different
///               fonts and effects, sometimes a shape behind, in a two-up grid by
///               theme. One lands as its separate parts, all selected.
///   Effects   — text looks in category rows. They restyle the selected text, or
///               add new text wearing the look.
///
/// Meant to sit under the Text panel's own content (it's not scrollable itself).
/// Cards are painted by the design renderer from the very elements a pick
/// lands, so a card can't show something the page won't.
///
/// Differences from the web, for a phone:
///   - "See all" drills in within this section (the web swaps the whole panel),
///     scrolling the section into view and back to the row on Back.
///   - The template grid shows [_pageSize] cards at a time with "Show more":
///     the web draws only cards near view, which a panel built as one list
///     child can't tell — and every card pulls its fonts.
class TextLibrarySection extends StatefulWidget {
  const TextLibrarySection({super.key, required this.c, this.query = ''});

  final DesignEditorController c;

  /// The panel's search, if it has one: non-empty shows matching templates
  /// instead of the switch (the web's search results' Templates block).
  final String query;

  @override
  State<TextLibrarySection> createState() => _TextLibrarySectionState();
}

const _pageSize = 20;

class _TextLibrarySectionState extends State<TextLibrarySection> {
  /// One renderer for every card — fonts load once and each landing repaints.
  final DesignScene _scene = DesignScene();
  final GlobalKey _topKey = GlobalKey();
  final Map<String, GlobalKey> _rowKeys = {};

  String _library = 'templates';
  String _theme = 'all';
  int _shown = _pageSize;
  LookRow? _openGroup;

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
  }

  void _reveal(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 200));
    });
  }

  void _openSeeAll(LookRow row) {
    setState(() => _openGroup = row);
    _reveal(_topKey);
  }

  void _back() {
    final row = _openGroup;
    setState(() => _openGroup = null);
    if (row != null) _reveal(_rowKeys[row.id]!);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // The controller for the active look; the fonts so cards re-measure.
      listenable: Listenable.merge([widget.c, textLibraryFonts]),
      builder: (context, _) {
        final q = widget.query.trim();
        final Widget body;
        if (q.isNotEmpty) {
          body = _searchResults(context, q);
        } else if (_openGroup != null) {
          body = _lookView(context, _openGroup!);
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Segmented(value: _library, onChanged: (v) => setState(() => _library = v)),
              const SizedBox(height: 16),
              if (_library == 'templates') _templates(context) else _lookRows(context),
            ],
          );
        }
        return KeyedSubtree(key: _topKey, child: body);
      },
    );
  }

  // ── Templates ──────────────────────────────────────────────────────────────

  Widget _templates(BuildContext context) {
    final combos = combosInTheme(_theme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ThemeChips(
          value: _theme,
          onChanged: (id) => setState(() {
            _theme = id;
            _shown = _pageSize;
          }),
        ),
        const SizedBox(height: 12),
        _comboGrid(context, combos),
      ],
    );
  }

  Widget _comboGrid(BuildContext context, List<Map<String, dynamic>> combos) {
    final shown = combos.take(_shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TwoUp(
          aspect: 5 / 4,
          children: [
            for (final combo in shown)
              _ComboCard(
                key: ValueKey(combo['id']),
                combo: combo,
                scene: _scene,
                onTap: () => insertCombo(widget.c, combo),
              ),
          ],
        ),
        if (combos.length > shown.length) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => setState(() => _shown += _pageSize),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.gray700,
              side: BorderSide(color: context.colors.gray200),
              minimumSize: const Size.fromHeight(40),
            ),
            child: Text('Show more (${combos.length - shown.length})'),
          ),
        ],
      ],
    );
  }

  Widget _searchResults(BuildContext context, String q) {
    final matches = searchCombos(q);
    if (matches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No templates found.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: context.colors.gray400),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_SectionTitle('Templates'), const SizedBox(height: 8), _comboGrid(context, matches)],
    );
  }

  // ── Effects ────────────────────────────────────────────────────────────────

  Widget _lookRows(BuildContext context) {
    final active = activeLook(widget.c);
    final col = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (active != null) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
            decoration: BoxDecoration(color: col.blueTint, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${active['label']}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: col.gray700),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => removeLook(widget.c),
                  icon: const Icon(LucideIcons.x, size: 14),
                  label: const Text('Remove'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.blue600,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        for (final row in lookRowGroups) ...[
          Row(
            key: _rowKeys.putIfAbsent(row.id, GlobalKey.new),
            children: [
              Expanded(child: _SectionTitle(row.label)),
              if (row.items.length > lookRowCount)
                TextButton(
                  onPressed: () => _openSeeAll(row),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.blue600,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('See all'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 112 * 2 / 3,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: math.min(lookRowCount, row.items.length),
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final look = row.items[i];
                return SizedBox(
                  width: 112,
                  child: _LookCard(
                    key: ValueKey(look['id']),
                    look: look,
                    scene: _scene,
                    active: look['id'] == active?['id'],
                    onTap: () => applyLook(widget.c, look),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }

  /// "See all": every look in one category, two-up, with a way back.
  Widget _lookView(BuildContext context, LookRow group) {
    final active = activeLook(widget.c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _back,
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
              icon: Icon(LucideIcons.chevronLeft, size: 18, color: context.colors.gray600),
            ),
            Expanded(
              child: Text(
                group.label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.colors.gray800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _TwoUp(
          aspect: 3 / 2,
          children: [
            for (final look in group.items)
              _LookCard(
                key: ValueKey(look['id']),
                look: look,
                scene: _scene,
                active: look['id'] == active?['id'],
                onTap: () => applyLook(widget.c, look),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Pieces ───────────────────────────────────────────────────────────────────

/// PanelSection's sub-heading.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.colors.gray700),
  );
}

/// positionControls.jsx `Segmented`: Templates | Effects.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    Widget option(String id, String label, String tip) {
      final on = id == value;
      return Expanded(
        child: Tooltip(
          message: tip,
          child: GestureDetector(
            onTap: () => onChanged(id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? col.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                boxShadow: on ? const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))] : null,
              ),
              child: Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? col.gray900 : col.gray500),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: col.gray100, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          option('templates', 'Templates', 'Ready-made text designs'),
          const SizedBox(width: 4),
          option('effects', 'Effects', 'Outlines, 3D, neon, stickers — on new or selected text'),
        ],
      ),
    );
  }
}

/// TextTemplatesTab's theme filter: one row of pills that scrolls sideways —
/// twenty-eight pills wrapped would be eight lines.
class _ThemeChips extends StatelessWidget {
  const _ThemeChips({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final chips = [('all', 'All'), ...comboThemes];
    final col = context.colors;
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final (id, label) = chips[i];
          final on = id == value;
          return Material(
            color: on ? AppColors.blue600 : col.gray100,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => onChanged(id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? Colors.white : col.gray600),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// TextComboGrid's two-up grid, as rows (the section isn't its own scroller).
class _TwoUp extends StatelessWidget {
  const _TwoUp({required this.aspect, required this.children});
  final double aspect;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: Row(
              children: [
                Expanded(
                  child: AspectRatio(aspectRatio: aspect, child: children[i]),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: i + 1 < children.length
                      ? AspectRatio(aspectRatio: aspect, child: children[i + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

typedef _Art = ({List<Map<String, dynamic>> elements, Rect bounds});

/// Built art, per card and fonts version — rebuilding a section mustn't
/// re-measure every card, but a face landing must.
final Map<String, _Art> _artCache = {};
int _artVersion = -1;

_Art? _artFor(String key, _Art Function() build) {
  if (_artVersion != textLibraryFonts.version) {
    _artCache.clear();
    _artVersion = textLibraryFonts.version;
  }
  final hit = _artCache[key];
  if (hit != null) return hit;
  try {
    return _artCache[key] = build();
  } catch (error) {
    debugPrint('❌ Text library card "$key" failed to build: $error');
    return null;
  }
}

/// Load what a card's art is set in: into the scene (to paint) and the
/// measuring faces (so the boxes are re-measured in the right face).
void _prepare(DesignScene scene, List<Map<String, dynamic>> elements) {
  scene.prepare(const {'width': 1, 'height': 1}, elements);
  textLibraryFonts.ensure([
    for (final el in elements)
      if (el['type'] == 'text') TextLibraryFonts.faceOf(el),
  ]);
}

/// TextComboCard — a template as the grid shows it. Light ground in both
/// themes, as in Canva: the designs are made for a page, and most are dark ink.
class _ComboCard extends StatelessWidget {
  const _ComboCard({super.key, required this.combo, required this.scene, required this.onTap});
  final Map<String, dynamic> combo;
  final DesignScene scene;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final art = _artFor('combo:${combo['id']}', () => buildComboElements(combo));
    if (art != null) _prepare(scene, art.elements);
    return Tooltip(
      message: '${combo['label']}',
      child: Material(
        color: AppColors.light.gray100,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: art == null ? const SizedBox.expand() : CustomPaint(painter: _ArtPainter(scene, art, 0.1)),
        ),
      ),
    );
  }
}

/// The size a look card's word is set at before it's fitted to the card.
const _lookPreviewSize = 96.0;

/// TextLookCard — one look drawn as the text a pick produces. Dark ground:
/// most looks are made for footage and several are white ink.
class _LookCard extends StatelessWidget {
  const _LookCard({super.key, required this.look, required this.scene, required this.active, required this.onTap});
  final Map<String, dynamic> look;
  final DesignScene scene;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final art = _artFor('look:${look['id']}', () {
      final el = lookElement(look, content: lookPreviewText(look), fontSize: _lookPreviewSize);
      return (
        elements: [el],
        bounds: Rect.fromLTWH(el['x'] as double, el['y'] as double, el['width'] as double, el['height'] as double),
      );
    });
    if (art != null) _prepare(scene, art.elements);
    return Tooltip(
      message: '${look['label']}',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: active ? Border.all(color: AppColors.blue500, width: 2) : null,
        ),
        child: Material(
          color: AppColors.light.gray900,
          borderRadius: BorderRadius.circular(active ? 6 : 8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: art == null ? const SizedBox.expand() : CustomPaint(painter: _ArtPainter(scene, art, 0.12)),
          ),
        ),
      ),
    );
  }
}

/// ElementArt — a still picture of a few elements, fitted and centred in the
/// card with a margin kept clear round it. Painted at the elements' own size
/// and scaled down, so text sizes and effects keep their proportions.
class _ArtPainter extends CustomPainter {
  _ArtPainter(this.scene, this.art, this.inset) : super(repaint: scene);
  final DesignScene scene;
  final _Art art;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final b = art.bounds;
    if (b.width <= 0 || b.height <= 0 || size.isEmpty) return;
    final scale = math.min(size.width * (1 - inset * 2) / b.width, size.height * (1 - inset * 2) / b.height);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2 - b.center.dx * scale, size.height / 2 - b.center.dy * scale);
    canvas.scale(scale);
    scene.paint(canvas, const {'width': 1, 'height': 1, 'background': 'transparent'}, art.elements, clip: false);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) => !identical(old.art, art) || old.inset != inset;
}
