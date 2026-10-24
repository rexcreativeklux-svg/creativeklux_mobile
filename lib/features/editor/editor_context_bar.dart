import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/app_exception.dart';
import '../../core/design/design_assets.dart';
import '../../core/design/groups.dart';
import '../../core/design/js_values.dart';
import '../../core/design/shapes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import '../brand/brand.dart';
import '../brand/brand_api.dart';
import 'design_editor_controller.dart';
import '../../core/design/design_renderer.dart';
import 'editor_animate.dart';
import 'editor_effects.dart';
import 'editor_image_sheet.dart';
import 'editor_video.dart';
import 'element_libraries/element_sheets.dart';
import 'editor_sheets.dart';

/// The contextual toolbar — port of the web's `EditorContextBar.jsx` plus the
/// element pill's actions (`EditorElementMenu.jsx`). On a phone it's one
/// horizontally scrolling strip above the panel rail; what it holds depends
/// on what's selected.
class EditorContextBar extends StatelessWidget {
  const EditorContextBar({
    super.key,
    required this.c,
    required this.brand,
    required this.brandApi,
    required this.onEditText,
    required this.onFitView,
    required this.scene,
    required this.onPlayAnimation,
  });

  /// Preview the page's animations on the stage.
  final VoidCallback onPlayAnimation;

  /// The editor's live scene — its images are already loaded, so the image
  /// sheet's previews draw instantly.
  final DesignScene scene;
  final DesignEditorController c;
  final Brand? brand;
  final BrandApi brandApi;
  final ValueChanged<String> onEditText;
  final VoidCallback onFitView;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final sel = c.selectedElements;
        final el = sel.firstOrNull;
        final items = <Widget>[
          if (el == null)
            ..._page(context)
          else if (sel.length > 1)
            ..._multi(context, sel)
          else ...[
            ..._typeTools(context, el),
            _divider(context),
            ..._common(context, el, sel),
          ],
        ];
        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: context.colors.surface,
            border: Border(top: BorderSide(color: context.colors.gray200)),
          ),
          child: ListView(
            // A new selection starts the strip from its first tool, not
            // wherever the last element's tools were scrolled to.
            key: ValueKey(sel.map((e) => e['id']).join(',')),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            children: items,
          ),
        );
      },
    );
  }

  Widget _divider(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: VerticalDivider(width: 1, color: context.colors.gray200),
  );

  // ── Nothing selected: the page ─────────────────────────────────────────────

  List<Widget> _page(BuildContext context) => [
    _Tool(
      leading: Swatch(value: c.canvas['background'] ?? '#ffffff', size: 24),
      label: 'Background',
      onTap: () => showColorSheet(context, c, title: 'Background', background: true, gradients: true, brand: brand),
    ),
    _Tool(icon: LucideIcons.scan, label: 'Fit to screen', onTap: onFitView),
    _Tool(
      icon: LucideIcons.wandSparkles,
      label: 'Animate',
      onTap: () => showAnimateSheet(context, c, onPlay: onPlayAnimation),
    ),
    _Tool(icon: LucideIcons.clipboardPaste, label: 'Paste', onTap: _paste),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Center(
        child: Text(
          'Tap to select · long-press to select more',
          style: TextStyle(fontSize: 12, color: context.colors.gray400),
        ),
      ),
    ),
  ];

  // ── Several selected (the web's multi-select pill) ─────────────────────────

  List<Widget> _multi(BuildContext context, List<Map<String, dynamic>> sel) {
    final ids = [for (final s in sel) s['id'] as String];
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Center(
          child: Text(
            '${sel.length} selected',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.colors.gray800),
          ),
        ),
      ),
      _Tool(icon: LucideIcons.group, label: 'Group', onTap: () => c.groupElements(ids)),
      _Tool(icon: LucideIcons.clipboardCopy, label: 'Copy', onTap: _copy),
      _Tool(icon: LucideIcons.copy, label: 'Duplicate', onTap: () => c.duplicateElements(ids)),
      _Tool(icon: LucideIcons.x, label: 'Deselect', onTap: () => c.select(null)),
      _Tool(icon: LucideIcons.trash2, label: 'Delete', danger: true, onTap: () => c.removeElements(ids)),
    ];
  }

  Future<void> _copy() async {
    final text = c.copySelection();
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      // The in-memory mirror still pastes.
    }
    Toast.success('Copied');
  }

  Future<void> _paste() async {
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (_) {}
    if (!c.paste(text)) Toast.info('Nothing to paste', description: 'Copy an element first.');
  }

  // ── Per type ───────────────────────────────────────────────────────────────

  List<Widget> _typeTools(BuildContext context, Map<String, dynamic> el) {
    final id = el['id'] as String;
    final locked = truthy(el['locked']);
    if (locked) {
      return [
        _Tool(icon: LucideIcons.lock, label: 'Locked', onTap: () => c.updateElement(id, {'locked': false})),
      ];
    }

    switch (el['type']) {
      case 'text':
        final size = orNum(el['fontSize'], 16);
        final bold = fontWeightOf(el['fontWeight']).value >= 600;
        final italic = el['fontStyle'] == 'italic';
        final underline = truthy(el['underline']);
        final align = '${el['textAlign'] ?? 'left'}';
        return [
          _Tool(icon: LucideIcons.pencil, label: 'Edit', onTap: () => onEditText(id)),
          _Tool(
            icon: LucideIcons.type,
            label: fontFamilyName(el['fontFamily']),
            onTap: () => showFontSheet(context, c, brand: brand),
          ),
          _Stepper(
            value: size,
            onChanged: (v) => c.updateElement(id, {'fontSize': v}),
            onTapValue: () => _sliderSheet(context, 'Font size', 'fontSize', 6, 400, size),
          ),
          _Tool(
            leading: Swatch(value: el['fill'] ?? el['color'] ?? '#111111', size: 24),
            label: 'Colour',
            onTap: () => showColorSheet(
              context,
              c,
              title: 'Text colour',
              keys: const ['fill', 'color'],
              fallback: '#111111',
              gradients: true,
              brand: brand,
            ),
          ),
          _Toggle(
            icon: LucideIcons.bold,
            on: bold,
            onTap: () => c.updateElement(id, {'fontWeight': bold ? 'normal' : 'bold'}),
          ),
          _Toggle(
            icon: LucideIcons.italic,
            on: italic,
            onTap: () => c.updateElement(id, {'fontStyle': italic ? 'normal' : 'italic'}),
          ),
          _Toggle(
            icon: LucideIcons.underline,
            on: underline,
            onTap: () => c.updateElement(id, {'underline': !underline}),
          ),
          _Toggle(
            icon: switch (align) {
              'center' => LucideIcons.textAlignCenter,
              'right' => LucideIcons.textAlignEnd,
              _ => LucideIcons.textAlignStart,
            },
            on: false,
            // Cycles left → centre → right, like the web's align button.
            onTap: () => c.updateElement(id, {
              'textAlign': switch (align) {
                'left' => 'center',
                'center' => 'right',
                _ => 'left',
              },
            }),
          ),
          _Tool(
            icon: LucideIcons.letterText,
            label: 'Spacing',
            onTap: () =>
                _sliderSheet(context, 'Letter spacing', 'letterSpacing', -10, 60, orNum(el['letterSpacing'], 0)),
          ),
          _Tool(icon: LucideIcons.sparkles, label: 'Effects', onTap: () => showTextEffectsSheet(context, c)),
        ];

      case 'shape':
        final stroke = shapes[el['shape']]?.kind == 'stroke';
        final primitive = primitiveShapes.contains(el['shape']) || !shapes.containsKey(el['shape']);
        return [
          _Tool(
            leading: Swatch(value: el['fill'] ?? '#6366f1', size: 24),
            label: stroke ? 'Colour' : 'Fill',
            onTap: () => showColorSheet(
              context,
              c,
              title: stroke ? 'Line colour' : 'Fill',
              keys: const ['fill'],
              fallback: '#6366f1',
              gradients: !stroke,
              brand: brand,
            ),
          ),
          if (!stroke)
            _Tool(
              leading: Swatch(value: truthy(el['stroke']) ? el['stroke'] : 'transparent', size: 24),
              label: 'Outline',
              onTap: () async {
                // Give an outline something to show before picking its colour.
                if (orNum(el['strokeWidth'], 0) == 0) c.updateElement(id, {'strokeWidth': 4, 'stroke': '#111111'});
                await showColorSheet(
                  context,
                  c,
                  title: 'Outline',
                  keys: const ['stroke'],
                  fallback: '#111111',
                  brand: brand,
                );
              },
            ),
          if (!stroke && orNum(el['strokeWidth'], 0) > 0)
            _Tool(
              icon: LucideIcons.lineSquiggle,
              label: 'Weight',
              onTap: () => _sliderSheet(context, 'Outline weight', 'strokeWidth', 0, 60, orNum(el['strokeWidth'], 0)),
            ),
          if (!stroke)
            _Tool(icon: LucideIcons.sparkles, label: 'Effects', onTap: () => showShapeEffectsSheet(context, c)),
          if (primitive && el['shape'] != 'circle' && el['shape'] != 'triangle')
            _Tool(
              icon: LucideIcons.squareRoundCorner,
              label: 'Corners',
              onTap: () => _sliderSheet(
                context,
                'Corner rounding',
                'borderRadius',
                0,
                (orNum(el['width'], 100) < orNum(el['height'], 100)
                        ? orNum(el['width'], 100)
                        : orNum(el['height'], 100)) /
                    2,
                numOf(el['borderRadius']) ?? 0,
              ),
            ),
        ];

      case 'image':
        // `flipH` / `flipV` — the keys the renderer (and the web) read.
        final flipX = truthy(el['flipH']);
        final flipY = truthy(el['flipV']);
        return [
          _Tool(
            icon: LucideIcons.slidersHorizontal,
            label: 'Edit image',
            onTap: () => showImageEditSheet(context, c, scene),
          ),
          _Tool(icon: LucideIcons.replace, label: 'Replace', onTap: () => _replaceImage(id)),
          _Toggle(icon: LucideIcons.flipHorizontal2, on: flipX, onTap: () => c.updateElement(id, {'flipH': !flipX})),
          _Toggle(icon: LucideIcons.flipVertical2, on: flipY, onTap: () => c.updateElement(id, {'flipV': !flipY})),
          if (isClipped(el['clip']))
            _Tool(
              icon: LucideIcons.crop,
              label: 'Uncrop',
              // Back to the full contents: the window grows to the content box.
              onTap: () {
                final clip = asMap(el['clip'])!;
                c.updateElement(id, {
                  'x': orNum(el['x'], 0) - orNum(clip['offsetX'], 0),
                  'y': orNum(el['y'], 0) - orNum(clip['offsetY'], 0),
                  'width': numOf(clip['contentW']),
                  'height': numOf(clip['contentH']),
                  'clip': null,
                });
              },
            ),
        ];

      case 'video':
        final flipX = truthy(el['flipH']);
        final flipY = truthy(el['flipV']);
        return [
          _Tool(icon: LucideIcons.clapperboard, label: 'Edit video', onTap: () => showVideoSheet(context, c)),
          _Tool(icon: LucideIcons.replace, label: 'Replace', onTap: () => replaceVideoFromPhone(c, id, brandApi)),
          _Toggle(icon: LucideIcons.flipHorizontal2, on: flipX, onTap: () => c.updateElement(id, {'flipH': !flipX})),
          _Toggle(icon: LucideIcons.flipVertical2, on: flipY, onTap: () => c.updateElement(id, {'flipV': !flipY})),
        ];

      case 'chart':
        return [_Tool(icon: LucideIcons.table2, label: 'Edit data', onTap: () => showChartDataSheet(context, c))];

      case 'table':
        return [
          _Tool(icon: LucideIcons.table, label: 'Edit table', onTap: () => showTableEditSheet(context, c)),
          for (final (key, label, fallback) in [
            ('headerFill', 'Header', '#111827'),
            ('cellFill', 'Cells', '#ffffff'),
            ('textColor', 'Text', '#111111'),
            ('borderColor', 'Lines', '#e5e7eb'),
          ])
            _Tool(
              leading: Swatch(value: el[key] ?? fallback, size: 24),
              label: label,
              onTap: () =>
                  showColorSheet(context, c, title: '$label colour', keys: [key], fallback: fallback, brand: brand),
            ),
        ];

      case 'grid':
        return [_Tool(icon: LucideIcons.layoutGrid, label: 'Grid', onTap: () => showGridSheet(context, c))];

      case 'frame':
        return [
          _Tool(icon: LucideIcons.replace, label: 'Replace', onTap: () => pickFrameImage(context, c, id)),
          _Tool(icon: LucideIcons.frame, label: 'Frame', onTap: () => showFrameImageSheet(context, c)),
        ];

      case 'group':
        return [_Tool(icon: LucideIcons.ungroup, label: 'Ungroup', onTap: () => c.ungroup(id))];

      default:
        return const [];
    }
  }

  // ── Every element ──────────────────────────────────────────────────────────

  List<Widget> _common(BuildContext context, Map<String, dynamic> el, List<Map<String, dynamic>> sel) {
    final id = el['id'] as String;
    final locked = truthy(el['locked']);
    final ids = [for (final s in sel) s['id'] as String];
    return [
      if (!locked)
        _Tool(
          icon: LucideIcons.wandSparkles,
          label: 'Animate',
          onTap: () => showAnimateSheet(context, c, onPlay: onPlayAnimation),
        ),
      if (!locked) _Tool(icon: LucideIcons.blend, label: 'Transparency', onTap: () => showOpacitySheet(context, c)),
      if (!locked) _Tool(icon: LucideIcons.layers2, label: 'Position', onTap: () => showArrangeSheet(context, c)),
      _Tool(icon: LucideIcons.copy, label: 'Duplicate', onTap: () => c.duplicateElements(ids)),
      _Tool(icon: LucideIcons.clipboardCopy, label: 'Copy', onTap: _copy),
      _Tool(
        icon: locked ? LucideIcons.lockOpen : LucideIcons.lock,
        label: locked ? 'Unlock' : 'Lock',
        onTap: () => c.updateElement(id, {'locked': !locked}),
      ),
      if (!locked) _Tool(icon: LucideIcons.trash2, label: 'Delete', danger: true, onTap: () => c.removeElements(ids)),
    ];
  }

  Future<void> _replaceImage(String id) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    Toast.info('Uploading…');
    try {
      final url = await brandApi.uploadImage(await file.readAsBytes(), file.name);
      if (url == null) throw AppException('The upload returned no file URL.');
      // Same box, new picture; any crop belonged to the old one.
      c.updateElement(id, {'src': url, 'clip': null});
      Toast.success('Image replaced');
    } catch (err) {
      Toast.error(toUserMessage(err, "Couldn't replace the image."));
    }
  }

  /// A single numeric property on a slider — one undo step per slide.
  Future<void> _sliderSheet(BuildContext context, String title, String key, double min, double max, double value) {
    var committed = false;
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      backgroundColor: context.colors.surface.withValues(alpha: 1),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => ListenableBuilder(
        listenable: c,
        builder: (ctx, _) {
          final el = c.selected;
          final v = (numOf(el?[key]) ?? value).clamp(min, max).toDouble();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ctx.colors.gray800),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: v,
                          min: min,
                          max: max,
                          onChanged: el == null
                              ? null
                              : (n) {
                                  if (!committed) {
                                    c.commit();
                                    committed = true;
                                  }
                                  c.updateElement(el['id'] as String, {key: n.roundToDouble()}, record: false);
                                },
                          onChangeEnd: (_) => committed = false,
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          v.round().toString(),
                          textAlign: TextAlign.right,
                          style: TextStyle(fontWeight: FontWeight.w600, color: ctx.colors.gray800),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({this.icon, this.leading, required this.label, required this.onTap, this.danger = false});

  final IconData? icon;
  final Widget? leading;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.red600 : context.colors.gray700;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading ?? Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.icon, required this.on, required this.onTap});

  final IconData icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: IconButton(
      onPressed: onTap,
      isSelected: on,
      style: IconButton.styleFrom(
        backgroundColor: on ? context.colors.blueTint : null,
        foregroundColor: on ? AppColors.blue600 : context.colors.gray700,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(icon, size: 17),
    ),
  );
}

/// − [size] + — the web's font-size control. Tapping the number opens a slider.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged, required this.onTapValue});

  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onTapValue;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget btn(IconData icon, double next) => SizedBox(
      width: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        onPressed: next < 1 ? null : () => onChanged(next),
        icon: Icon(icon, size: 15, color: c.gray600),
      ),
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: c.gray200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(LucideIcons.minus, (value - 1).roundToDouble()),
          GestureDetector(
            onTap: onTapValue,
            child: SizedBox(
              width: 36,
              child: Text(
                value.round().toString(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray900),
              ),
            ),
          ),
          btn(LucideIcons.plus, (value + 1).roundToDouble()),
        ],
      ),
    );
  }
}
