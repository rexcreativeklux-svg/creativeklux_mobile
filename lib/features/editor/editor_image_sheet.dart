import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/design/design_renderer.dart';
import '../../core/design/image_filters.dart';
import '../../core/design/js_values.dart';
import '../../core/theme/app_colors.dart';
import 'design_editor_controller.dart';
import 'editor_sheets.dart';

/// Edit image — port of the web's `panels/image/EditImagePanel.jsx` (Filters,
/// Adjust and Shadows sections). Writes `filter` (preset or `look-*` id),
/// `adjust` {brightness, contrast, saturation, warmth, hue, blur} and
/// `imgShadow`; the renderer turns those into the same CSS-filter pipeline the
/// web export uses (`core/design/image_filters.dart`).
///
/// Not ported: the tone sliders (tint, highlights, shadows, whites, blacks,
/// vibrance — the renderer can't draw them yet) and the AI image tools
/// (background remover, magic eraser…).
Future<void> showImageEditSheet(BuildContext context, DesignEditorController c, DesignScene scene) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.08),
    backgroundColor: context.colors.surface.withValues(alpha: 1),
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.6),
      child: _ImageEdit(c: c, scene: scene),
    ),
  );
}

class _ImageEdit extends StatefulWidget {
  const _ImageEdit({required this.c, required this.scene});
  final DesignEditorController c;
  final DesignScene scene;

  @override
  State<_ImageEdit> createState() => _ImageEditState();
}

class _ImageEditState extends State<_ImageEdit> {
  var _tab = 0; // 0 Filters · 1 Adjust · 2 Shadows
  var _sliding = false;

  DesignEditorController get c => widget.c;

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final el = c.selected;
        if (el == null || el['type'] != 'image') return const SizedBox(height: 80);
        final id = el['id'] as String;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit image',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: col.gray800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(LucideIcons.chevronDown, size: 18, color: col.gray400),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Filters')),
                  ButtonSegment(value: 1, label: Text('Adjust')),
                  ButtonSegment(value: 2, label: Text('Shadows')),
                ],
                selected: {_tab},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: switch (_tab) {
                0 => _filters(context, el, id),
                1 => _adjust(context, el, id),
                _ => _shadows(context, el, id),
              },
            ),
          ],
        );
      },
    );
  }

  /// A thumbnail of THIS image with [patch] applied, painted by the renderer
  /// itself — so a tile shows exactly what tapping it does.
  Widget _tile(String label, Map<String, dynamic> el, Map<String, dynamic> patch, bool active, VoidCallback onTap) {
    final col = context.colors;
    return SizedBox(
      width: 78,
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 74,
              height: 74,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: col.gray100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: active ? AppColors.blue500 : col.gray200, width: active ? 2 : 1),
              ),
              child: CustomPaint(painter: _ImagePreview(widget.scene, {...el, ...patch})),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: active ? AppColors.blue600 : col.gray600),
          ),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context, Map<String, dynamic> el, String id) {
    final current = '${el['filter'] ?? 'none'}';
    Widget row(List<ImageFilterPreset> list) => Wrap(
      spacing: 6,
      runSpacing: 8,
      children: [
        for (final f in list)
          _tile(f.label, el, {'filter': f.id}, current == f.id, () => c.updateElement(id, {'filter': f.id})),
      ],
    );
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        sectionLabel(context, 'Presets'),
        row(imageFilters),
        for (final g in filterLookGroups) ...[const SizedBox(height: 14), sectionLabel(context, g.label), row(g.looks)],
      ],
    );
  }

  Widget _adjust(BuildContext context, Map<String, dynamic> el, String id) {
    final adjust = asMap(el['adjust']) ?? const <String, dynamic>{};
    final col = context.colors;
    final any = adjust.values.any((v) => (numOf(v) ?? 0) != 0);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final a in imageAdjustments)
          Row(
            children: [
              SizedBox(
                width: 86,
                child: Text(a.label, style: TextStyle(fontSize: 13, color: col.gray700)),
              ),
              Expanded(
                child: Slider(
                  value: (numOf(adjust[a.key]) ?? a.def).clamp(a.min, a.max).toDouble(),
                  min: a.min,
                  max: a.max,
                  onChanged: (v) {
                    // One undo step per slide; the map is copied, never edited
                    // in place (it's shared with the undo history).
                    if (!_sliding) {
                      c.commit();
                      _sliding = true;
                    }
                    c.updateElement(id, {
                      'adjust': {...adjust, a.key: v.roundToDouble()},
                    }, record: false);
                  },
                  onChangeEnd: (_) => _sliding = false,
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '${(numOf(adjust[a.key]) ?? a.def).round()}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12.5, color: col.gray600),
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: any ? () => c.updateElement(id, {'adjust': null}) : null, child: const Text('Reset')),
      ],
    );
  }

  Widget _shadows(BuildContext context, Map<String, dynamic> el, String id) {
    final current = '${el['imgShadow'] ?? 'none'}';
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 8,
          children: [
            for (final s in imageShadows)
              _tile(
                s.label,
                el,
                {'imgShadow': s.id, 'imgShadowParams': null},
                current == s.id,
                () => c.updateElement(id, {'imgShadow': s.id, 'imgShadowParams': null}),
              ),
          ],
        ),
      ],
    );
  }
}

class _ImagePreview extends CustomPainter {
  _ImagePreview(this.scene, this.el) : super(repaint: scene);
  final DesignScene scene;
  final Map<String, dynamic> el;

  @override
  void paint(Canvas canvas, Size size) {
    // The image fitted into the tile with a margin, so shadows have room.
    final w = orNum(el['width'], 1), h = orNum(el['height'], 1);
    final s = (size.width * 0.78) / (w > h ? w : h);
    canvas.save();
    canvas.translate((size.width - w * s) / 2, (size.height - h * s) / 2);
    canvas.scale(s);
    scene.paint(
      canvas,
      {'width': w, 'height': h, 'background': 'transparent'},
      [
        {...el, 'id': 'preview', 'x': 0, 'y': 0, 'rotation': 0, 'opacity': 1},
      ],
      clip: false,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ImagePreview old) => old.el != el;
}
