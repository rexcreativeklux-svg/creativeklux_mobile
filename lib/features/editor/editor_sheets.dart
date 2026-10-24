import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/design/design_assets.dart';
import '../../core/design/gradient.dart';
import '../../core/design/js_values.dart';
import '../../core/theme/app_colors.dart';
import '../brand/brand.dart';
import 'design_editor_controller.dart';

/// The editor's contextual pickers — ports of the web's ColorPanel, FontPanel,
/// the opacity popover and the Position → Arrange tab. On the web they open as
/// side panels; here they're bottom sheets that leave the artboard visible
/// above them, and every change applies live.

// ── Fonts (`(lib)/design/fonts.js` EDITOR_FONTS) ──────────────────────────────

const editorFonts = [
  'Inter', 'Poppins', 'Montserrat', 'Roboto', 'Open Sans', 'Lato', 'Raleway', 'Work Sans', 'Nunito', //
  'Rubik', 'Oswald', 'Bebas Neue', 'Anton', 'Archivo', 'Josefin Sans', 'Fredoka', 'Righteous', //
  'Playfair Display', 'Merriweather', 'Lora', 'PT Serif', 'DM Serif Display', 'Cormorant Garamond', //
  'Libre Baskerville', 'Abril Fatface', 'Pacifico', 'Lobster', 'Dancing Script', 'Caveat', 'Great Vibes', //
  'Sacramento', 'Satisfy', 'Permanent Marker', 'Bungee',
];

/// The CSS value the web stores for a family, by its category.
String cssFontFamily(String name) {
  const serif = {
    'Playfair Display', 'Merriweather', 'Lora', 'PT Serif', 'DM Serif Display', //
    'Cormorant Garamond', 'Libre Baskerville', 'Abril Fatface',
  };
  const display = {
    'Pacifico', 'Lobster', 'Dancing Script', 'Caveat', 'Great Vibes', //
    'Sacramento', 'Satisfy', 'Permanent Marker', 'Bungee',
  };
  final generic = serif.contains(name) ? 'serif' : (display.contains(name) ? 'cursive' : 'sans-serif');
  return "'$name', $generic";
}

TextStyle _fontPreview(String family, {double size = 16}) {
  try {
    return GoogleFonts.getFont(family, fontSize: size);
  } catch (_) {
    return TextStyle(fontSize: size);
  }
}

// ── Shared chrome ─────────────────────────────────────────────────────────────

Future<void> _sheet(BuildContext context, {required String title, required Widget Function(BuildContext) body}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    // Light scrim: the point of these sheets is watching the design change.
    barrierColor: Colors.black.withValues(alpha: 0.08),
    backgroundColor: context.colors.surface.withValues(alpha: 1),
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.55),
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
  );
}

Widget sectionLabel(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(
    text.toUpperCase(),
    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: context.colors.gray400),
  ),
);

/// A colour or CSS gradient chip, painted with the renderer's own `paintFor`
/// so a gradient looks exactly as it will on the design.
class Swatch extends StatelessWidget {
  const Swatch({super.key, required this.value, this.selected = false, this.size = 36, this.onTap});

  final Object value;
  final bool selected;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: selected ? AppColors.blue500 : Colors.transparent, width: 2),
        ),
        child: ClipOval(
          child: CustomPaint(painter: _SwatchPainter(value), foregroundPainter: _RingPainter(context.colors.gray200)),
        ),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.value);
  final Object value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final p = paintFor(value, rect);
    if (p != null) canvas.drawRect(rect, p);
  }

  @override
  bool shouldRepaint(covariant _SwatchPainter old) => old.value != value;
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawCircle(
    size.center(Offset.zero),
    size.width / 2 - 0.5,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke,
  );

  @override
  bool shouldRepaint(covariant _RingPainter old) => false;
}

// ── Colour ────────────────────────────────────────────────────────────────────

const _defaultSwatches = [
  '#000000', '#545454', '#737373', '#a6a6a6', '#d9d9d9', '#ffffff', //
  '#ff3131', '#ff5757', '#ff66c4', '#cb6ce6', '#8c52ff', '#5e17eb', //
  '#0097b2', '#0cc0df', '#5ce1e6', '#38b6ff', '#5271ff', '#004aad', //
  '#00bf63', '#7ed957', '#c1ff72', '#ffde59', '#ffbd59', '#ff914d',
];

const _gradientPresets = [
  'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
  'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)',
  'linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)',
  'linear-gradient(135deg, #43e97b 0%, #38f9d7 100%)',
  'linear-gradient(135deg, #fa709a 0%, #fee140 100%)',
  'linear-gradient(135deg, #30cfd0 0%, #330867 100%)',
  'linear-gradient(135deg, #ff9a9e 0%, #fecfef 100%)',
  'linear-gradient(135deg, #ffecd2 0%, #fcb69f 100%)',
  'linear-gradient(180deg, #1e3c72 0%, #2a5298 100%)',
  'linear-gradient(135deg, #f6d365 0%, #fda085 100%)',
  'linear-gradient(135deg, #232526 0%, #414345 100%)',
  'radial-gradient(circle, #ffffff 0%, #cfd9df 100%)',
];

String? _toHex(Object? v) {
  if (v is! String) return null;
  final s = v.trim();
  return RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(s) ? (s.startsWith('#') ? s : '#$s').toLowerCase() : null;
}

/// "Colours in this design" — every solid colour already used.
List<String> designColors(DesignEditorController c) {
  final out = <String>{};
  void add(Object? v) {
    final h = _toHex(v);
    if (h != null) out.add(h);
  }

  add(c.canvas['background']);
  for (final el in c.elements) {
    for (final k in ['fill', 'color', 'stroke', 'background', 'borderColor', 'textColor']) {
      add(el[k]);
    }
  }
  return out.toList();
}

/// Pick a colour for [keys] of the selected element — or, with [background],
/// for the page. [gradients] offers the CSS gradient presets too (fills and
/// backgrounds; never an outline, which can't hold one).
Future<void> showColorSheet(
  BuildContext context,
  DesignEditorController c, {
  required String title,
  List<String> keys = const [],
  String fallback = '#000000',
  bool background = false,
  bool gradients = false,
  Brand? brand,
}) {
  return _sheet(
    context,
    title: title,
    body: (ctx) => ListenableBuilder(
      listenable: c,
      builder: (ctx, _) {
        final el = c.selected;
        final current = background
            ? c.canvas['background']
            : keys.map((k) => el?[k]).firstWhere(truthy, orElse: () => fallback);

        void apply(String value) {
          if (background) {
            c.setBackground(value);
          } else if (el != null) {
            c.updateElement(el['id'] as String, {for (final k in keys) k: value});
          }
        }

        Widget row(List<String> values) => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final v in values) Swatch(value: v, selected: '$current'.toLowerCase() == v, onTap: () => apply(v)),
          ],
        );

        final brandColors = [brand?.primaryColor, brand?.secondaryColor].map(_toHex).whereType<String>().toList();
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _HexField(current: _toHex(current) ?? '#000000', onSubmit: apply),
            const SizedBox(height: 16),
            if (designColors(c).isNotEmpty) ...[
              sectionLabel(ctx, 'Colours in this design'),
              row(designColors(c)),
              const SizedBox(height: 16),
            ],
            if (brandColors.isNotEmpty) ...[
              sectionLabel(ctx, 'Brand colours'),
              row(brandColors),
              const SizedBox(height: 16),
            ],
            sectionLabel(ctx, 'Default colours'),
            row(_defaultSwatches),
            if (gradients) ...[const SizedBox(height: 16), sectionLabel(ctx, 'Gradients'), row(_gradientPresets)],
          ],
        );
      },
    ),
  );
}

class _HexField extends StatefulWidget {
  const _HexField({required this.current, required this.onSubmit});
  final String current;
  final ValueChanged<String> onSubmit;

  @override
  State<_HexField> createState() => _HexFieldState();
}

class _HexFieldState extends State<_HexField> {
  late final _ctrl = TextEditingController(text: widget.current.substring(1));

  @override
  void didUpdateWidget(_HexField old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) _ctrl.text = widget.current.substring(1);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Swatch(value: widget.current, size: 40),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _ctrl,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]'))],
            style: TextStyle(fontSize: 14, color: c.gray900, fontFeatures: const [FontFeature.tabularFigures()]),
            decoration: InputDecoration(
              counterText: '',
              prefixText: '#',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) {
              if (v.length == 6) widget.onSubmit('#${v.toLowerCase()}');
            },
          ),
        ),
      ],
    );
  }
}

// ── Font ──────────────────────────────────────────────────────────────────────

Future<void> showFontSheet(BuildContext context, DesignEditorController c, {Brand? brand}) {
  return _sheet(
    context,
    title: 'Font',
    body: (ctx) {
      final brandFonts = [
        for (final f in (brand?.fonts ?? '').split(','))
          if (f.trim().isNotEmpty && editorFonts.contains(f.trim())) f.trim(),
      ];
      return ListenableBuilder(
        listenable: c,
        builder: (ctx, _) {
          final el = c.selected;
          final active = fontFamilyName(el?['fontFamily']);
          Widget tile(String f) => ListTile(
            dense: true,
            title: Text(f, style: _fontPreview(f, size: 17).copyWith(color: ctx.colors.gray900)),
            trailing: active == f ? Icon(LucideIcons.check, size: 16, color: AppColors.blue600) : null,
            onTap: el == null ? null : () => c.updateElement(el['id'] as String, {'fontFamily': cssFontFamily(f)}),
          );
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (brandFonts.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: sectionLabel(ctx, 'Brand fonts')),
                ...brandFonts.map(tile),
                Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: sectionLabel(ctx, 'All fonts')),
              ],
              ...editorFonts.map(tile),
            ],
          );
        },
      );
    },
  );
}

// ── Opacity ───────────────────────────────────────────────────────────────────

Future<void> showOpacitySheet(BuildContext context, DesignEditorController c) {
  var committed = false;
  return _sheet(
    context,
    title: 'Transparency',
    body: (ctx) => ListenableBuilder(
      listenable: c,
      builder: (ctx, _) {
        final el = c.selected;
        final value = nnNum(el?['opacity'], 1).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          child: Row(
            children: [
              Expanded(
                child: Slider(
                  value: value,
                  onChangeStart: (_) => committed = false,
                  onChanged: el == null
                      ? null
                      : (v) {
                          // One undo step for the whole slide.
                          if (!committed) {
                            c.commit();
                            committed = true;
                          }
                          c.updateElement(el['id'] as String, {'opacity': v}, record: false);
                        },
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${(value * 100).round()}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.w600, color: ctx.colors.gray800),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

// ── Arrange (Position panel) ──────────────────────────────────────────────────

Future<void> showArrangeSheet(BuildContext context, DesignEditorController c) {
  return _sheet(
    context,
    title: 'Position',
    body: (ctx) => ListenableBuilder(
      listenable: c,
      builder: (ctx, _) {
        final el = c.selected;
        if (el == null) return const SizedBox(height: 80);
        final id = el['id'] as String;

        Widget btn(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 15),
            label: Text(label, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              foregroundColor: ctx.colors.gray800,
              side: BorderSide(color: ctx.colors.gray200),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        );

        // Align to page — `(lib)/design/alignToPage.js` for one element: the
        // element's own (unrotated) box against the page edges and centre.
        void align(String how) {
          final w = orNum(el['width'], 0), h = orNum(el['height'], 0);
          final patch = switch (how) {
            'left' => {'x': 0.0},
            'center' => {'x': (c.canvasWidth - w) / 2},
            'right' => {'x': c.canvasWidth - w},
            'top' => {'y': 0.0},
            'middle' => {'y': (c.canvasHeight - h) / 2},
            _ => {'y': c.canvasHeight - h},
          };
          c.updateElement(id, patch);
        }

        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            sectionLabel(ctx, 'Layer'),
            Row(
              children: [
                btn(LucideIcons.arrowUp, 'Forward', () => c.moveLayer(id, 'forward')),
                const SizedBox(width: 8),
                btn(LucideIcons.arrowDown, 'Backward', () => c.moveLayer(id, 'backward')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                btn(LucideIcons.bringToFront, 'To front', () => c.moveLayer(id, 'front')),
                const SizedBox(width: 8),
                btn(LucideIcons.sendToBack, 'To back', () => c.moveLayer(id, 'back')),
              ],
            ),
            const SizedBox(height: 16),
            sectionLabel(ctx, 'Align to page'),
            Row(
              children: [
                btn(LucideIcons.alignStartVertical, 'Left', () => align('left')),
                const SizedBox(width: 8),
                btn(LucideIcons.alignCenterVertical, 'Centre', () => align('center')),
                const SizedBox(width: 8),
                btn(LucideIcons.alignEndVertical, 'Right', () => align('right')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                btn(LucideIcons.alignStartHorizontal, 'Top', () => align('top')),
                const SizedBox(width: 8),
                btn(LucideIcons.alignCenterHorizontal, 'Middle', () => align('middle')),
                const SizedBox(width: 8),
                btn(LucideIcons.alignEndHorizontal, 'Bottom', () => align('bottom')),
              ],
            ),
            const SizedBox(height: 16),
            sectionLabel(ctx, 'Rotation'),
            Slider(
              value: orNum(el['rotation'], 0).clamp(0.0, 360.0),
              max: 360,
              divisions: 72,
              label: '${orNum(el['rotation'], 0).round()}°',
              onChanged: (v) => c.updateElement(id, {'rotation': v}, record: false),
              onChangeStart: (_) => c.commit(),
            ),
          ],
        );
      },
    ),
  );
}
