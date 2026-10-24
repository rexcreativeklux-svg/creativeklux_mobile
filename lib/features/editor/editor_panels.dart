import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/design/design_assets.dart';
import '../../core/design/design_renderer.dart';
import '../../core/design/js_values.dart';
import '../../core/design/shape_categories.dart';
import '../../core/design/shapes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../brand/brand.dart';
import 'design_editor_controller.dart';
import 'editor_video.dart';
import 'element_libraries/element_libraries_section.dart';
import 'text_library/text_library_section.dart';
import 'editor_sheets.dart';

/// Dropping new things onto the page — the web's `insert` API (DesignEditor.jsx
/// insertText / insertShape / insertImageUrl). Everything lands centred and
/// selected.
class EditorInserts {
  EditorInserts(this.c);

  final DesignEditorController c;

  double get _cx => c.canvasWidth / 2;
  double get _cy => c.canvasHeight / 2;

  void text({String content = 'Your text', double fontSize = 40, Object fontWeight = 'normal', String? fontFamily}) {
    final w = math.min(420, c.canvasWidth * 0.7).toDouble();
    final h = (fontSize * 1.5).roundToDouble();
    c.addElement({
      'type': 'text',
      'content': content,
      'text': content,
      'x': _cx - w / 2,
      'y': _cy - h / 2,
      'width': w,
      'height': h,
      'fontSize': fontSize,
      'fontWeight': fontWeight,
      'fill': '#111111',
      'textAlign': 'center',
      'fontFamily': ?fontFamily,
    });
  }

  /// Sized to the shape's own aspect, capped at a third of the page. 'rounded'
  /// is a primitive rect with a corner radius; line shapes default to black.
  void shape(String key) {
    final rounded = key == 'rounded';
    final def = shapes[key];
    final base = math.min(c.canvasWidth, c.canvasHeight) * 0.32;
    final aspect = def == null ? 1.0 : def.viewBox[0] / def.viewBox[1];
    final w = aspect >= 1 ? base : base * aspect;
    final h = aspect >= 1 ? base / aspect : base;
    final stroke = def?.kind == 'stroke';
    c.addElement({
      'type': 'shape',
      'shape': rounded ? 'rect' : key,
      'x': _cx - w / 2,
      'y': _cy - h / 2,
      'width': w.roundToDouble(),
      'height': h.roundToDouble(),
      'fill': stroke ? '#111111' : '#6366f1',
      'borderRadius': rounded ? (math.min(w, h) * 0.14).roundToDouble() : 0,
    });
  }

  /// A sticky note: a square text box on a coloured panel, top-aligned, whose
  /// type size auto-fits the box (web: insertStickyNote).
  void stickyNote([String color = '#FEF08A']) {
    final size = (math.min(c.canvasWidth, c.canvasHeight) * 0.24).roundToDouble();
    c.addElement({
      'type': 'text',
      'content': 'Write a note',
      'text': 'Write a note',
      'x': _cx - size / 2,
      'y': _cy - size / 2,
      'width': size,
      'height': size,
      'fontSize': math.max(18, (size * 0.11).roundToDouble()),
      'fontWeight': 'normal',
      'fill': '#1f2937',
      'textAlign': 'left',
      'background': color,
      'padding': (size * 0.1).roundToDouble(),
      'borderRadius': 10,
      'sticky': true,
      'autoFit': true,
    });
  }

  /// A hosted image at 60% of the page width (or its own width, if smaller),
  /// keeping its aspect.
  /// A hosted video at 60% of the page width (see editor_video.dart).
  Future<void> videoUrl(String src) => insertVideo(c, src);

  Future<void> imageUrl(String src) async {
    final img = await loadDesignImage(src);
    final natW = img?.width.toDouble() ?? c.canvasWidth * 0.4;
    final natH = img?.height.toDouble() ?? c.canvasWidth * 0.4;
    img?.dispose();
    final w = math.min(c.canvasWidth * 0.6, natW);
    final h = w * (natH / natW);
    c.addElement({'type': 'image', 'src': src, 'x': _cx - w / 2, 'y': _cy - h / 2, 'width': w, 'height': h});
  }
}

Widget _panelPadding({required List<Widget> children}) =>
    ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: children);

// ── Text (TextPanel.jsx) ──────────────────────────────────────────────────────

class TextPanel extends StatelessWidget {
  const TextPanel({super.key, required this.insert, required this.onPickFont});

  final EditorInserts insert;
  final VoidCallback onPickFont;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget preset(String label, double size, Object weight, double preview, FontWeight previewWeight) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.gray200),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => insert.text(content: label, fontSize: size, fontWeight: weight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Text(
              label,
              style: TextStyle(fontSize: preview, fontWeight: previewWeight, color: c.gray800),
            ),
          ),
        ),
      ),
    );

    return _panelPadding(
      children: [
        FilledButton.icon(
          onPressed: () => insert.text(content: 'Your text', fontWeight: 'bold'),
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('Add a text box'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blue600,
            minimumSize: const Size.fromHeight(42),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 18),
        sectionLabel(context, 'Default text styles'),
        preset('Add a heading', 72, 'bold', 22, FontWeight.w700),
        preset('Add a subheading', 44, 600, 17, FontWeight.w600),
        preset('Add a little bit of body text', 26, 'normal', 13.5, FontWeight.w400),
        const SizedBox(height: 10),
        sectionLabel(context, 'Fonts'),
        OutlinedButton.icon(
          onPressed: onPickFont,
          icon: const Icon(LucideIcons.type, size: 16),
          label: const Text('Change the selected text’s font'),
          style: OutlinedButton.styleFrom(
            foregroundColor: c.gray700,
            side: BorderSide(color: c.gray200),
            minimumSize: const Size.fromHeight(42),
          ),
        ),
        const SizedBox(height: 20),
        // Templates | Effects libraries (text/templates + text/looks).
        TextLibrarySection(c: insert.c),
      ],
    );
  }
}

// ── Elements → Shapes (ElementsPanel / ShapesBrowser) ─────────────────────────

class ElementsPanel extends StatelessWidget {
  const ElementsPanel({super.key, required this.insert, required this.previews});

  final EditorInserts insert;

  /// Shared scene for the shape thumbnails — shapes need no images or fonts,
  /// so its synchronous paint is all a preview takes.
  final DesignScene previews;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        sectionLabel(context, 'Sticky notes'),
        Wrap(
          spacing: 8,
          children: [
            for (final color in ['#FEF08A', '#FBCFE8', '#BFDBFE', '#BBF7D0', '#FED7AA'])
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => insert.stickyNote(color),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Color(int.parse('FF${color.substring(1)}', radix: 16)),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 2))],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // Graphics, Charts, Tables, Frames, Grids (collapsible).
        ElementLibrariesSection(c: insert.c),
        const SizedBox(height: 16),
        for (final (_, label, keys) in shapeCategories)
          if (keys.isNotEmpty) ...[
            sectionLabel(context, label),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (key, name) in keys)
                  Tooltip(
                    message: name,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => insert.shape(key),
                      child: Container(
                        width: 58,
                        height: 58,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: context.colors.gray50, borderRadius: BorderRadius.circular(8)),
                        child: CustomPaint(painter: _ShapePreview(previews, key)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

class _ShapePreview extends CustomPainter {
  _ShapePreview(this.scene, this.shape);
  final DesignScene scene;
  final String shape;

  @override
  void paint(Canvas canvas, Size size) {
    final def = shapes[shape];
    final aspect = def == null ? 1.0 : def.viewBox[0] / def.viewBox[1];
    final w = aspect >= 1 ? size.width : size.height * aspect;
    final h = aspect >= 1 ? size.width / aspect : size.height;
    canvas.translate((size.width - w) / 2, (size.height - h) / 2);
    scene.paint(
      canvas,
      {'width': w, 'height': h, 'background': 'transparent'},
      [
        {
          'id': shape,
          'type': 'shape',
          'shape': shape == 'rounded' ? 'rect' : shape,
          'x': 0,
          'y': 0,
          'width': w,
          'height': h,
          'fill': def?.kind == 'stroke' ? '#334155' : '#6366f1',
          if (shape == 'rounded') 'borderRadius': w * 0.18,
        },
      ],
    );
  }

  @override
  bool shouldRepaint(covariant _ShapePreview old) => old.shape != shape;
}

// ── Brand (BrandPanel.jsx) ────────────────────────────────────────────────────

class BrandPanel extends StatelessWidget {
  const BrandPanel({super.key, required this.c, required this.insert, required this.brand});

  final DesignEditorController c;
  final EditorInserts insert;
  final Brand? brand;

  @override
  Widget build(BuildContext context) {
    final b = brand;
    if (b == null) {
      return Center(
        child: Text('No active brand', style: TextStyle(color: context.colors.gray400)),
      );
    }
    final colors = [b.primaryColor, b.secondaryColor].whereType<String>().where((s) => s.isNotEmpty).toList();
    final fonts = [
      for (final f in (b.fonts ?? '').split(','))
        if (f.trim().isNotEmpty) f.trim(),
    ];
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final el = c.selected;
        // A brand colour paints the selection's fill, or the page when nothing
        // is selected — the web panel's "apply" behaviour.
        void applyColor(String hex) {
          if (el == null) {
            c.setBackground(hex);
          } else {
            c.updateElement(el['id'] as String, {'fill': hex, if (el['type'] == 'text') 'color': hex});
          }
        }

        return _panelPadding(
          children: [
            Text(
              b.name ?? 'Brand',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.colors.gray900),
            ),
            const SizedBox(height: 14),
            if (b.logoUrl != null) ...[
              sectionLabel(context, 'Logo'),
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => insert.imageUrl(b.logoUrl!),
                  child: Container(
                    width: 96,
                    height: 96,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.colors.gray50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.colors.gray200),
                    ),
                    child: MediaImage(b.logoUrl!, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (colors.isNotEmpty) ...[
              sectionLabel(context, el == null ? 'Colours — tap to set the background' : 'Colours — tap to apply'),
              Wrap(
                spacing: 8,
                children: [for (final hex in colors) Swatch(value: hex, size: 44, onTap: () => applyColor(hex))],
              ),
              const SizedBox(height: 16),
            ],
            if (fonts.isNotEmpty) ...[
              sectionLabel(context, 'Fonts — tap to add text'),
              for (final f in fonts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(f, style: TextStyle(fontSize: 15, color: context.colors.gray900)),
                  trailing: const Icon(LucideIcons.plus, size: 16),
                  onTap: () => insert.text(content: f, fontFamily: cssFontFamily(f)),
                ),
            ],
          ],
        );
      },
    );
  }
}

// ── Layers (LayersPanel / Position → Layers) ──────────────────────────────────

class LayersPanel extends StatelessWidget {
  const LayersPanel({super.key, required this.c});

  final DesignEditorController c;

  static String _label(Map<String, dynamic> el) => switch (el['type']) {
    'text' =>
      '${el['content'] ?? el['text'] ?? ''}'.trim().isEmpty
          ? 'Text'
          : '${el['content'] ?? el['text']}'.replaceAll('\n', ' '),
    'shape' => 'Shape · ${el['shape'] ?? ''}',
    'image' => 'Image',
    'video' => 'Video',
    'group' => 'Group of ${(el['children'] as List?)?.length ?? 0}',
    final t => '$t'[0].toUpperCase() + '$t'.substring(1),
  };

  static IconData _icon(Map<String, dynamic> el) => switch (el['type']) {
    'text' => LucideIcons.type,
    'shape' => LucideIcons.shapes,
    'image' => LucideIcons.image,
    'video' => LucideIcons.video,
    'group' => LucideIcons.group,
    _ => LucideIcons.square,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        // Front-most first, like every layers list; the array is back-first.
        final front = c.elements.reversed.toList();
        if (front.isEmpty) {
          return Center(
            child: Text('Nothing on the page yet', style: TextStyle(color: context.colors.gray400)),
          );
        }
        return ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
          buildDefaultDragHandles: false,
          itemCount: front.length,
          onReorderItem: (from, to) {
            final list = [...front];
            final item = list.removeAt(from);
            list.insert(to, item);
            c.reorderElements(list.reversed.toList());
          },
          itemBuilder: (context, i) {
            final el = front[i];
            final id = el['id'] as String;
            final selected = c.selectedIds.contains(id);
            final hidden = truthy(el['hidden']);
            final locked = truthy(el['locked']);
            final col = context.colors;
            return Container(
              key: ValueKey(id),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: selected ? col.blueTint : col.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: selected ? AppColors.blue500 : col.gray200),
              ),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: ReorderableDragStartListener(
                  index: i,
                  child: Icon(LucideIcons.gripVertical, size: 16, color: col.gray400),
                ),
                title: Row(
                  children: [
                    Icon(_icon(el), size: 15, color: col.gray500),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _label(el),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: hidden ? col.gray400 : col.gray800),
                      ),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: hidden ? 'Show' : 'Hide',
                      icon: Icon(hidden ? LucideIcons.eyeOff : LucideIcons.eye, size: 16, color: col.gray500),
                      onPressed: () => c.updateElement(id, {'hidden': !hidden}),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: locked ? 'Unlock' : 'Lock',
                      icon: Icon(locked ? LucideIcons.lock : LucideIcons.lockOpen, size: 16, color: col.gray500),
                      onPressed: () => c.updateElement(id, {'locked': !locked}),
                    ),
                  ],
                ),
                onTap: () => c.select(id),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Resize (resize/ResizePanel.jsx + resizePresets.js) ────────────────────────

const _resizeGroups = [
  (
    'Standard',
    [('Landscape', 2016.0, 1512.0, '4:3'), ('Portrait', 1512.0, 2016.0, '3:4'), ('Square', 1512.0, 1512.0, '1:1')],
  ),
  (
    'Social media',
    [
      ('Instagram Story', 1080.0, 1920.0, '9:16'),
      ('Instagram Post', 1080.0, 1080.0, '1:1'),
      ('Instagram Portrait', 1080.0, 1350.0, '4:5'),
      ('Instagram Reel', 1080.0, 1920.0, '9:16'),
      ('TikTok Post', 1080.0, 1920.0, '9:16'),
      ('YouTube Thumbnail', 1280.0, 720.0, '16:9'),
      ('YouTube Channel Art', 2560.0, 1440.0, '16:9'),
      ('Facebook Post', 1200.0, 628.0, '1.91:1'),
      ('Facebook Cover', 820.0, 312.0, '2.63:1'),
      ('LinkedIn Banner', 1584.0, 396.0, '4:1'),
      ('Pinterest Pin', 1000.0, 1500.0, '2:3'),
      ('Twitter / X Post', 1600.0, 900.0, '16:9'),
    ],
  ),
  (
    'Marketplace',
    [
      ('Etsy', 2048.0, 2048.0, '1:1'),
      ('eBay', 1600.0, 1600.0, '1:1'),
      ('Shopify Product', 2048.0, 2048.0, '1:1'),
      ('Amazon Product', 2000.0, 2000.0, '1:1'),
    ],
  ),
];

class ResizePanel extends StatelessWidget {
  const ResizePanel({super.key, required this.c});

  final DesignEditorController c;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final col = context.colors;
        return _panelPadding(
          children: [
            Text(
              'Current size: ${c.canvasWidth.round()} × ${c.canvasHeight.round()} px',
              style: TextStyle(fontSize: 12.5, color: col.gray500),
            ),
            const SizedBox(height: 4),
            Text(
              'Everything on the page is refitted to the new size.',
              style: TextStyle(fontSize: 12, color: col.gray400),
            ),
            const SizedBox(height: 14),
            for (final (title, presets) in _resizeGroups) ...[
              sectionLabel(context, title),
              for (final (label, w, h, ratio) in presets)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: _RatioBox(w: w, h: h),
                  title: Text(label, style: TextStyle(fontSize: 13.5, color: col.gray800)),
                  subtitle: Text(
                    '${w.round()} × ${h.round()} · $ratio',
                    style: TextStyle(fontSize: 11.5, color: col.gray400),
                  ),
                  trailing: c.canvasWidth == w && c.canvasHeight == h
                      ? Icon(LucideIcons.check, size: 16, color: AppColors.blue600)
                      : null,
                  onTap: () {
                    c.resizeCanvas(w, h);
                    Toast.success('Resized to $label');
                  },
                ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _RatioBox extends StatelessWidget {
  const _RatioBox({required this.w, required this.h});
  final double w, h;

  @override
  Widget build(BuildContext context) {
    final long = math.max(w, h);
    return SizedBox(
      width: 28,
      height: 28,
      child: Center(
        child: Container(
          width: 26 * w / long,
          height: 26 * h / long,
          decoration: BoxDecoration(
            border: Border.all(color: context.colors.gray400, width: 1.5),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}
