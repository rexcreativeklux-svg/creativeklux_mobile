import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/design/js_values.dart';
import '../../core/theme/app_colors.dart';
import 'design_editor_controller.dart';
import 'editor_sheets.dart';

/// Element animations — port of the web's `(lib)/design/animations.js` and
/// `panels/animate/AnimatePanel.jsx`.
///
/// Stored as `el.animation = {type, speed}`. Like the web, it's an in-editor
/// PREVIEW only: downloads and thumbnails are a single still frame. The CSS
/// keyframes become [AnimFrame]s the stage applies while previewing.

const animations = [
  ('fade', 'Fade', false),
  ('rise', 'Rise', false),
  ('pan', 'Pan', false),
  ('drift', 'Drift', false),
  ('pop', 'Pop', false),
  ('wipe', 'Wipe', false),
  ('tumble', 'Tumble', false),
  ('stomp', 'Stomp', false),
  ('block', 'Block', false),
  ('neon', 'Neon', false),
  ('breathe', 'Breathe', true),
  ('pulse', 'Pulse', true),
];

/// "Featured" page styles — one animation across every element.
const pagePresets = [
  ('simple', 'Simple', 'fade'),
  ('sleek', 'Sleek', 'rise'),
  ('fun', 'Fun', 'pop'),
  ('party', 'Party', 'pulse'),
  ('corporate', 'Corporate', 'pan'),
  ('chill', 'Chill', 'drift'),
];

const animSpeeds = [('slow', 'Slow', 1.6), ('medium', 'Medium', 1.0), ('fast', 'Fast', 0.6)];

const _baseDuration = 0.7; // seconds at "medium"

/// One frame of an element's animation: how to draw it at that moment.
class AnimFrame {
  const AnimFrame({
    this.opacity = 1,
    this.dx = 0,
    this.dy = 0,
    this.scale = 1,
    this.rotation = 0,
    this.revealX = 1,
    this.revealY = 1,
  });
  final double opacity, dx, dy, scale, rotation;

  /// Visible fraction from the left (wipe) / top (block), via a clip.
  final double revealX, revealY;

  static const rest = AnimFrame();
}

/// Total preview length of an element's animation in seconds, or 0.
double animationLength(Object? anim) {
  final a = asMap(anim);
  final def = animations.where((d) => d.$1 == a?['type']).firstOrNull;
  if (def == null) return 0;
  final mult = animSpeeds.where((s) => s.$1 == a?['speed']).firstOrNull?.$3 ?? 1.0;
  return _baseDuration * mult * (def.$3 ? 3 : 1);
}

// cubic-bezier(0.22, 1, 0.36, 1) — the web's entrance easing.
const _enter = Cubic(0.22, 1, 0.36, 1);

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Piecewise keyframes [(offset, value)], linear between stops.
double _keys(List<(double, double)> k, double t) {
  for (var i = 1; i < k.length; i++) {
    if (t <= k[i].$1) {
      final span = k[i].$1 - k[i - 1].$1;
      return _lerp(k[i - 1].$2, k[i].$2, span == 0 ? 1 : (t - k[i - 1].$1) / span);
    }
  }
  return k.last.$2;
}

/// The frame [elapsed] seconds into an element's animation (KEYFRAMES_CSS).
AnimFrame animationFrame(Object? anim, double elapsed) {
  final a = asMap(anim);
  final def = animations.where((d) => d.$1 == a?['type']).firstOrNull;
  if (def == null) return AnimFrame.rest;
  final mult = animSpeeds.where((s) => s.$1 == a?['speed']).firstOrNull?.$3 ?? 1.0;
  final dur = _baseDuration * mult;
  final loops = def.$3 ? 3 : 1;
  if (elapsed >= dur * loops) return AnimFrame.rest;
  final raw = ((elapsed % dur) / dur).clamp(0.0, 1.0);
  // Loops ease in-out; entrances use the web's cubic-bezier.
  final t = def.$3 ? Curves.easeInOut.transform(raw) : _enter.transform(raw);
  return switch (def.$1) {
    'fade' => AnimFrame(opacity: t),
    'rise' => AnimFrame(opacity: t, dy: 26 * (1 - t)),
    'pan' => AnimFrame(opacity: t, dx: -36 * (1 - t)),
    'drift' => AnimFrame(opacity: t, dy: -26 * (1 - t)),
    'pop' => AnimFrame(opacity: _keys([(0, 0), (0.6, 1), (1, 1)], t), scale: _keys([(0, 0.6), (0.6, 1.08), (1, 1)], t)),
    'wipe' => AnimFrame(revealX: t),
    'tumble' => AnimFrame(opacity: t, dy: 24 * (1 - t), rotation: -12 * (1 - t)),
    'stomp' => AnimFrame(
      opacity: _keys([(0, 0), (0.6, 1), (1, 1)], t),
      scale: _keys([(0, 1.6), (0.6, 0.94), (1, 1)], t),
    ),
    'block' => AnimFrame(revealY: t),
    'neon' => AnimFrame(
      opacity: _keys([(0, 0), (0.1, 1), (0.15, 0.3), (0.25, 1), (0.32, 0.5), (0.42, 1), (1, 1)], raw),
    ),
    'breathe' => AnimFrame(scale: 1 + 0.06 * math.sin(math.pi * t)),
    'pulse' => AnimFrame(opacity: 1 - 0.55 * math.sin(math.pi * t)),
    _ => AnimFrame.rest,
  };
}

/// The Animate sheet. [onPlay] previews on the stage after a pick.
Future<void> showAnimateSheet(BuildContext context, DesignEditorController c, {required VoidCallback onPlay}) {
  var tab = c.selected == null ? 'page' : 'element';
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.08),
    backgroundColor: context.colors.surface.withValues(alpha: 1),
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setTab) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.6),
        child: ListenableBuilder(
          listenable: c,
          builder: (ctx, _) {
            final col = ctx.colors;
            final el = c.selected;
            final els = c.elements;
            final page = tab == 'page';
            // The page shows a type only when every element shares it.
            final firstType = asMap(els.firstOrNull?['animation'])?['type'];
            final pageType = els.isNotEmpty && els.every((e) => asMap(e['animation'])?['type'] == firstType)
                ? firstType
                : null;
            final activeType = page ? pageType : asMap(el?['animation'])?['type'];
            final activeSpeed =
                '${(page ? asMap(els.firstOrNull?['animation']) : asMap(el?['animation']))?['speed'] ?? 'medium'}';
            final canEdit = page ? els.isNotEmpty : el != null;

            void setPage(String? type, [String? speed]) {
              c.commit();
              c.updateElements({
                for (final e in els)
                  e['id'] as String: {
                    'animation': type == null ? null : {'type': type, 'speed': speed ?? activeSpeed},
                  },
              }, record: false);
              if (type != null) onPlay();
            }

            void setOne(String? type, [String? speed]) {
              if (el == null) return;
              c.updateElement(el['id'] as String, {
                'animation': type == null ? null : {'type': type, 'speed': speed ?? activeSpeed},
              });
              if (type != null) onPlay();
            }

            void pick(String? type, [String? speed]) => page ? setPage(type, speed) : setOne(type, speed);

            Widget tile(String label, bool active, VoidCallback onTap) => SizedBox(
              width: 96,
              child: OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: active ? col.blueTint : null,
                  foregroundColor: active ? AppColors.blue600 : col.gray700,
                  side: BorderSide(color: active ? AppColors.blue500 : col.gray200, width: active ? 2 : 1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            );

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Animate',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: col.gray800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Play',
                        onPressed: onPlay,
                        icon: Icon(LucideIcons.play, size: 18, color: AppColors.blue600),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: Icon(LucideIcons.chevronDown, size: 18, color: col.gray400),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'page', label: Text('Page')),
                      ButtonSegment(value: 'element', label: Text('Selected')),
                    ],
                    selected: {tab},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setTab(() => tab = s.first),
                  ),
                ),
                Flexible(
                  child: !canEdit
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            page ? 'Add elements to the page to animate them.' : 'Select an element to animate it.',
                            style: TextStyle(fontSize: 12.5, color: col.gray400),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          children: [
                            if (page) ...[
                              sectionLabel(ctx, 'Featured'),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final (_, label, anim) in pagePresets)
                                    tile(label, pageType == anim, () => setPage(anim)),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                            sectionLabel(ctx, 'General'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final (id, label, _) in animations) tile(label, activeType == id, () => pick(id)),
                              ],
                            ),
                            if (activeType != null) ...[
                              const SizedBox(height: 16),
                              sectionLabel(ctx, 'Speed'),
                              Wrap(
                                spacing: 6,
                                children: [
                                  for (final (id, label, _) in animSpeeds)
                                    ChoiceChip(
                                      label: Text(label),
                                      selected: activeSpeed == id,
                                      onSelected: (_) => pick('$activeType', id),
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
                      onPressed: canEdit && activeType != null ? () => pick(null) : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue600,
                        minimumSize: const Size.fromHeight(42),
                      ),
                      child: const Text('Remove animation'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
