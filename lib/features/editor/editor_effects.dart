import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/design/design_renderer.dart';
import '../../core/design/js_values.dart';
import '../../core/theme/app_colors.dart';
import 'design_editor_controller.dart';
import 'editor_sheets.dart';

/// Text and shape effects — ports of the web's `panels/effects/EffectsPanel.jsx`
/// and `ShapeEffectsPanel.jsx`, with their data from `(lib)/design/textEffects.js`
/// and `shapeEffects.js`.
///
/// An effect is stored on the element as `{type, ...0–100 params, color}`
/// (`textEffect` / `shapeEffect`); the renderer already draws every one, so
/// these sheets only write the data. Tiles preview each look with that same
/// renderer, so a tile looks exactly like what it applies.

typedef _Control = (String key, String label, double min, double max, double def);

// ── textEffects.js ───────────────────────────────────────────────────────────

const _textEffects = [
  ('shadow', 'Shadow'),
  ('lift', 'Lift'),
  ('hollow', 'Hollow'),
  ('splice', 'Splice'),
  ('outline', 'Outline'),
  ('echo', 'Echo'),
  ('glow', 'Glow'),
  ('neon', 'Neon'),
  ('background', 'Background'),
];

const Map<String, List<_Control>> _textControls = {
  'shadow': [
    ('offset', 'Offset', 0, 100, 50),
    ('direction', 'Direction', -180, 180, -45),
    ('blur', 'Blur', 0, 100, 20),
    ('transparency', 'Transparency', 0, 100, 40),
  ],
  'lift': [('intensity', 'Intensity', 0, 100, 50)],
  'hollow': [('thickness', 'Thickness', 0, 100, 50)],
  'splice': [
    ('thickness', 'Thickness', 0, 100, 50),
    ('offset', 'Offset', 0, 100, 50),
    ('direction', 'Direction', -180, 180, -45),
  ],
  'outline': [('thickness', 'Thickness', 0, 100, 50)],
  'echo': [('offset', 'Offset', 0, 100, 50), ('direction', 'Direction', -180, 180, -45)],
  'glow': [('intensity', 'Intensity', 0, 100, 50)],
  'neon': [('intensity', 'Intensity', 0, 100, 50)],
  'background': [
    ('roundness', 'Roundness', 0, 100, 50),
    ('spread', 'Spread', 0, 100, 30),
    ('transparency', 'Transparency', 0, 100, 0),
  ],
};

const _textEffectColor = {
  'shadow': '#000000',
  'splice': '#8b5cf6',
  'outline': '#000000',
  'echo': '#b1b1b1',
  'glow': '#ffffff',
  'background': '#000000',
};

/// One-click curated looks; applying one stores `{...config, preset: id}`.
const _textPresets = <(String, String, Map<String, Object>)>[
  ('pop', 'Pop', {'type': 'shadow', 'offset': 72, 'direction': 45, 'blur': 0, 'transparency': 0, 'color': '#111111'}),
  ('retro', 'Retro', {'type': 'echo', 'offset': 72, 'direction': 40, 'color': '#ff5c8a'}),
  ('extrude', '3D', {'type': 'echo', 'offset': 58, 'direction': 45, 'color': '#6b7280'}),
  (
    'soft',
    'Soft',
    {'type': 'shadow', 'offset': 32, 'direction': 90, 'blur': 62, 'transparency': 45, 'color': '#000000'},
  ),
  ('cyber', 'Cyber', {'type': 'glow', 'intensity': 70, 'color': '#22d3ee'}),
  ('neon', 'Neon', {'type': 'neon', 'intensity': 78}),
  ('sticker', 'Sticker', {'type': 'outline', 'thickness': 82, 'color': '#ffffff'}),
  ('marker', 'Marker', {'type': 'background', 'roundness': 28, 'spread': 22, 'transparency': 0, 'color': '#fde047'}),
];

// ── shapeEffects.js ──────────────────────────────────────────────────────────

const _shapeEffects = [('drop', 'Drop'), ('echo', 'Echo'), ('glow', 'Glow')];

const Map<String, List<_Control>> _shapeControls = {
  'drop': [
    ('offset', 'Offset', 0, 100, 40),
    ('direction', 'Direction', -180, 180, 45),
    ('blur', 'Blur', 0, 100, 30),
    ('transparency', 'Transparency', 0, 100, 60),
  ],
  'echo': [('offset', 'Offset', 0, 100, 50), ('direction', 'Direction', -180, 180, 45)],
  'glow': [('intensity', 'Intensity', 0, 100, 50)],
};

const _shapeEffectColor = {'drop': '#000000', 'echo': '#b1b1b1', 'glow': '#8b5cf6'};

const _effectSwatches = [
  '#000000', '#ffffff', '#6b7280', '#ff3131', '#ff66c4', '#8b5cf6', //
  '#5271ff', '#22d3ee', '#00bf63', '#fde047', '#ff914d', '#b1b1b1',
];

Map<String, dynamic> _defaults(String type, Map<String, List<_Control>> controls, Map<String, String> colors) => {
  'type': type,
  for (final c in controls[type] ?? const <_Control>[]) c.$1: c.$5,
  if (colors[type] != null) 'color': colors[type],
};

/// Shared renderer for the tiles — "Ag" in DM Sans and plain shapes need
/// nothing loaded beyond the one font.
DesignScene? _previewScene;
DesignScene get _scene {
  final s = _previewScene ??= DesignScene();
  s.prepare(
    const {'width': 1, 'height': 1},
    const [
      {'type': 'text', 'fontWeight': 'bold'},
    ],
  );
  return s;
}

class _Preview extends CustomPainter {
  _Preview(this.element, this.dark) : super(repaint: _scene);
  final Map<String, dynamic> element;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    _scene.paint(
      canvas,
      {'width': size.width, 'height': size.height, 'background': dark ? '#1f2430' : '#ffffff'},
      [
        {...element, 'id': 'p', 'x': 0, 'y': 0, 'width': size.width, 'height': size.height},
      ],
    );
  }

  @override
  bool shouldRepaint(covariant _Preview old) => old.element.toString() != element.toString() || old.dark != dark;
}

Future<void> showTextEffectsSheet(BuildContext context, DesignEditorController c) =>
    _showEffects(context, c, shape: false);

Future<void> showShapeEffectsSheet(BuildContext context, DesignEditorController c) =>
    _showEffects(context, c, shape: true);

Future<void> _showEffects(BuildContext context, DesignEditorController c, {required bool shape}) {
  final key = shape ? 'shapeEffect' : 'textEffect';
  final effects = shape ? _shapeEffects : _textEffects;
  final controls = shape ? _shapeControls : _textControls;
  final colors = shape ? _shapeEffectColor : _textEffectColor;
  var dragging = false;

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
      child: ListenableBuilder(
        listenable: c,
        builder: (ctx, _) {
          final el = c.selected;
          if (el == null) return const SizedBox(height: 80);
          final id = el['id'] as String;
          final current = asMap(el[key]);
          final type = '${current?['type'] ?? 'none'}';
          final hasEffect = current != null && type != 'none';
          final col = ctx.colors;

          void write(Map<String, dynamic>? value, {bool record = true}) =>
              c.updateElement(id, {key: value}, record: record);

          // A tile previews the effect on "Ag" (text) or the element's own shape.
          Map<String, dynamic> previewOf(Map<String, dynamic> fx, bool dark) => shape
              ? {
                  'type': 'shape',
                  'shape': el['shape'] ?? 'rect',
                  'fill': el['fill'] ?? '#6366f1',
                  'borderRadius': 10,
                  'shapeEffect': fx,
                }
              : {
                  'type': 'text',
                  'content': 'Ag',
                  'fontSize': 28,
                  'fontWeight': 'bold',
                  'textAlign': 'center',
                  'fill': dark ? '#ffffff' : '#111111',
                  'textEffect': fx,
                };

          Widget tile(String label, Map<String, dynamic> fx, bool active, VoidCallback onTap) {
            final dark = !shape && (fx['type'] == 'glow' || fx['type'] == 'neon');
            return SizedBox(
              width: 96,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: onTap,
                    child: Container(
                      height: 62,
                      clipBehavior: Clip.antiAlias,
                      padding: shape ? const EdgeInsets.all(14) : EdgeInsets.zero,
                      decoration: BoxDecoration(
                        color: dark ? const Color(0xFF1F2430) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: active ? AppColors.blue500 : col.gray200, width: active ? 2 : 1),
                      ),
                      child: CustomPaint(painter: _Preview(previewOf(fx, dark), dark), size: Size.infinite),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: active ? AppColors.blue600 : col.gray600,
                    ),
                  ),
                ],
              ),
            );
          }

          final active = controls[type] ?? const <_Control>[];
          final hasColor = colors[type] != null;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Effects',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: col.gray800),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(LucideIcons.chevronDown, size: 18, color: col.gray400),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    sectionLabel(ctx, 'Style'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: [
                        for (final (fxId, label) in effects)
                          tile(
                            label,
                            _defaults(fxId, controls, colors),
                            type == fxId && current?['preset'] == null,
                            // Re-picking the same base effect keeps its params;
                            // a new one seeds defaults. Either way the preset
                            // badge goes.
                            () => write(
                              type == fxId && current?['preset'] == null ? current : _defaults(fxId, controls, colors),
                            ),
                          ),
                      ],
                    ),
                    if (!shape) ...[
                      const SizedBox(height: 16),
                      sectionLabel(ctx, 'Templates'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 10,
                        children: [
                          for (final (pid, label, config) in _textPresets)
                            tile(
                              label,
                              {...config},
                              current?['preset'] == pid,
                              () => write({...config, 'preset': pid}),
                            ),
                        ],
                      ),
                    ],
                    if (hasEffect && (hasColor || active.isNotEmpty)) ...[
                      const SizedBox(height: 16),
                      Divider(color: col.gray100),
                      if (hasColor) ...[
                        sectionLabel(ctx, 'Colour'),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final hex in _effectSwatches)
                              Swatch(
                                value: hex,
                                size: 32,
                                selected: '${current['color'] ?? colors[type]}'.toLowerCase() == hex,
                                // A copy: nested maps are shared with the undo
                                // history, so they're never edited in place.
                                onTap: () =>
                                    write({...Map<String, dynamic>.from(current)..remove('preset'), 'color': hex}),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      for (final (k, label, min, max, def) in active)
                        Row(
                          children: [
                            SizedBox(
                              width: 92,
                              child: Text(label, style: TextStyle(fontSize: 13, color: col.gray700)),
                            ),
                            Expanded(
                              child: Slider(
                                value: (numOf(current[k]) ?? def).clamp(min, max).toDouble(),
                                min: min,
                                max: max,
                                onChanged: (v) {
                                  // One undo step per slide; tweaking detaches
                                  // the value from its preset (it's custom now).
                                  if (!dragging) {
                                    c.commit();
                                    dragging = true;
                                  }
                                  final next = Map<String, dynamic>.from(current)..remove('preset');
                                  write({...next, k: v.roundToDouble()}, record: false);
                                },
                                onChangeEnd: (_) => dragging = false,
                              ),
                            ),
                            SizedBox(
                              width: 36,
                              child: Text(
                                '${(numOf(current[k]) ?? def).round()}',
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 12.5, color: col.gray600),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: FilledButton(
                    onPressed: hasEffect ? () => write(null) : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.blue600,
                      minimumSize: const Size.fromHeight(42),
                    ),
                    child: const Text('Remove effect'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
