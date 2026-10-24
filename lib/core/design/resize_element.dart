import 'dart:math' as math;

import 'groups.dart';
import 'js_values.dart';
import 'shapes.dart';

/// What a resize handle MEANS — port of the web's `(lib)/design/resizeElement.js`
/// with the parts of `scaleProps.js` and `clip.js` it needs.
///
///   · a CORNER scales — the box and everything measured in canvas units inside
///     it grow together, so pulling the corner of a headline gives a bigger
///     headline rather than the same type re-wrapped in a wider box;
///   · an EDGE crops — the contents stay exactly where and what size they were,
///     and the box becomes a window showing less of them (`clip`).
///
/// Every function is pure: a SNAPSHOT taken when the gesture started plus the
/// pointer's total travel since. Never the current state plus a per-frame
/// delta — that accumulates rounding error over a drag.

/// Smallest box a gesture may leave behind, in canvas units.
const minBox = 10.0;

const corners = ['topLeft', 'topRight', 'bottomRight', 'bottomLeft'];
const edges = ['top', 'right', 'bottom', 'left'];

// Which way each corner grows; the opposite corner is the anchor.
const _cornerGrowth = {'topLeft': (-1, -1), 'topRight': (1, -1), 'bottomRight': (1, 1), 'bottomLeft': (-1, 1)};

double _n(Object? v) => numOf(v) ?? 0;

// ── clip.js ────────────────────────────────────────────────────────────────

/// A window that hides nothing — the start of a crop on an uncropped element.
Map<String, dynamic> seedClip(Map<String, dynamic> el) => {
  'offsetX': 0.0,
  'offsetY': 0.0,
  'contentW': _n(el['width']),
  'contentH': _n(el['height']),
};

/// A clip reduced to null once it stops hiding anything, so an element dragged
/// back out to its full contents is genuinely uncropped again.
Map<String, dynamic>? normalizeClip(Map<String, dynamic> clip, double width, double height) {
  if (!isClipped(clip)) return null;
  final flush =
      _n(clip['offsetX']).abs() < 0.5 &&
      _n(clip['offsetY']).abs() < 0.5 &&
      (_n(clip['contentW']) - width).abs() < 0.5 &&
      (_n(clip['contentH']) - height).abs() < 0.5;
  return flush ? null : clip;
}

/// A clip scaled for a resize, as a patch (empty when there is none).
Map<String, dynamic> scaledClip(Map<String, dynamic> el, double sx, [double? sy]) {
  final c = asMap(el['clip']);
  if (!isClipped(c)) return {};
  return {
    'clip': {
      'offsetX': _n(c!['offsetX']) * sx,
      'offsetY': _n(c['offsetY']) * (sy ?? sx),
      'contentW': _n(c['contentW']) * sx,
      'contentH': _n(c['contentH']) * (sy ?? sx),
    },
  };
}

// ── scaleProps.js ──────────────────────────────────────────────────────────

/// Canvas-unit scalars that scale by the uniform factor on every element.
/// `strokeWidth` is decided per type: on a library shape it's viewBox units
/// and already scales with the box.
const _uniformKeys = ['fontSize', 'letterSpacing', 'padding', 'borderWidth', 'gap', 'cellRadius'];

bool _strokeIsCanvasUnits(Map<String, dynamic> el) =>
    el['type'] == 'shape' && (primitiveShapes.contains(el['shape']) || !shapes.containsKey(el['shape']));

/// A sticky note's type size belongs to its auto-fit, not to a resize.
bool _fontIsAutoFitted(Map<String, dynamic> el) =>
    el['type'] == 'text' && truthy(el['sticky']) && el['autoFit'] != false;

Object? _scaleRadius(Object? r, double k) {
  if (r is num) return r * k;
  final m = asMap(r);
  if (m == null) return r;
  return {
    for (final key in ['topLeft', 'topRight', 'bottomRight', 'bottomLeft'])
      key: numOf(m[key]) != null ? numOf(m[key])! * k : m[key],
  };
}

/// The canvas-unit properties of [el], scaled — the part of a resize that isn't
/// the box. `bend` tracks the HEIGHT factor (it's consumed as 24·bend/height).
Map<String, dynamic> scaledProps(Map<String, dynamic> el, double k, {double? heightFactor}) {
  final patch = <String, dynamic>{};
  if (!k.isFinite || k == 1) return patch;
  for (final key in _uniformKeys) {
    if (key == 'fontSize' && _fontIsAutoFitted(el)) continue;
    final v = numOf(el[key]);
    if (v != null && v != 0) patch[key] = v * k;
  }
  if (el['borderRadius'] != null) patch['borderRadius'] = _scaleRadius(el['borderRadius'], k);
  if (_strokeIsCanvasUnits(el)) {
    final s = numOf(el['strokeWidth']);
    if (s != null && s != 0) patch['strokeWidth'] = s * k;
  }
  final bend = numOf(el['bend']);
  if (bend != null && bend != 0) patch['bend'] = bend * (heightFactor ?? k);
  return patch;
}

/// A group's members scaled with its box — they're positioned relative to its
/// corner, so their own boxes and canvas-unit props all scale.
List<Map<String, dynamic>> scaleChildren(Object? children, double sx, double sy) {
  if (children is! List) return const [];
  final uni = math.sqrt(sx * sy);
  return [
    for (final raw in children)
      if (asMap(raw) case final c?)
        {
          ...c,
          'x': _n(c['x']) * sx,
          'y': _n(c['y']) * sy,
          'width': _n(c['width']) * sx,
          'height': _n(c['height']) * sy,
          ...scaledProps(c, uni, heightFactor: sy),
          ...scaledClip(c, sx, sy),
          if (c['type'] == 'group') 'children': scaleChildren(c['children'], sx, sy),
        },
  ];
}

// ── resizeElement.js ───────────────────────────────────────────────────────

/// Keep a rotated element's anchor where the user sees it: resizing moves the
/// centre it rotates about, so the new centre is mapped through the rotation.
Map<String, dynamic> withRotationHeld(Map<String, dynamic> snap, Map<String, double> box) {
  final deg = _n(snap['rotation']);
  if (deg == 0) return box;
  final cx = _n(snap['x']) + _n(snap['width']) / 2;
  final cy = _n(snap['y']) + _n(snap['height']) / 2;
  final r = deg * math.pi / 180;
  final cos = math.cos(r), sin = math.sin(r);
  final nx = box['x']! + box['width']! / 2 - cx;
  final ny = box['y']! + box['height']! / 2 - cy;
  return {
    ...box,
    'x': cx + nx * cos - ny * sin - box['width']! / 2,
    'y': cy + nx * sin + ny * cos - box['height']! / 2,
  };
}

/// Canvas-unit contents scaled by [k] (and a crop window with them).
Map<String, dynamic> scaleContents(Map<String, dynamic> snap, double k) {
  if (!k.isFinite || k <= 0 || k == 1) return {};
  return {
    ...scaledProps(snap, k),
    ...scaledClip(snap, k),
    if (snap['type'] == 'group') 'children': scaleChildren(snap['children'], k, k),
  };
}

/// SCALE: a corner drag, box and contents together, aspect locked. The factor
/// is the least-squares fit of the pointer onto the box's diagonal, so a drag
/// along either axis (or between) reads naturally.
Map<String, dynamic> scaleByCorner(Map<String, dynamic> snap, String corner, double dx, double dy) {
  final grow = _cornerGrowth[corner];
  if (grow == null) return {};
  final w = _n(snap['width']) == 0 ? 1.0 : _n(snap['width']);
  final h = _n(snap['height']) == 0 ? 1.0 : _n(snap['height']);
  final wantW = w + dx * grow.$1;
  final wantH = h + dy * grow.$2;
  final k = math.max((w * wantW + h * wantH) / (w * w + h * h), math.max(minBox / w, minBox / h));
  final width = w * k, height = h * k;
  final anchorX = grow.$1 > 0 ? _n(snap['x']) : _n(snap['x']) + w;
  final anchorY = grow.$2 > 0 ? _n(snap['y']) : _n(snap['y']) + h;
  final box = {
    'x': grow.$1 > 0 ? anchorX : anchorX - width,
    'y': grow.$2 > 0 ? anchorY : anchorY - height,
    'width': width,
    'height': height,
  };
  return {...withRotationHeld(snap, box), ...scaleContents(snap, k)};
}

/// CROP: move one edge of the window over the contents. `contentW/H` never
/// change — that invariant is what makes it a crop rather than a resize.
/// Clamped so the window can't collapse or run past its own contents.
Map<String, dynamic> cropByEdge(Map<String, dynamic> snap, String edge, double dx, double dy) {
  final clip = isClipped(snap['clip']) ? asMap(snap['clip'])! : seedClip(snap);
  final horizontal = edge == 'left' || edge == 'right';
  final lead = edge == 'left' || edge == 'top';
  final size = horizontal ? _n(snap['width']) : _n(snap['height']);
  final offset = horizontal ? _n(clip['offsetX']) : _n(clip['offsetY']);
  final content = horizontal ? _n(clip['contentW']) : _n(clip['contentH']);
  final travel = horizontal ? dx : dy;
  final d = lead
      ? travel.clamp(-offset, math.max(-offset, size - minBox))
      : travel.clamp(math.min(minBox - size, content - offset - size), content - offset - size);

  final next = {
    'offsetX': _n(clip['offsetX']),
    'offsetY': _n(clip['offsetY']),
    'contentW': _n(clip['contentW']),
    'contentH': _n(clip['contentH']),
  };
  final box = {'x': _n(snap['x']), 'y': _n(snap['y']), 'width': _n(snap['width']), 'height': _n(snap['height'])};
  if (horizontal) {
    box['width'] = lead ? box['width']! - d : box['width']! + d;
    if (lead) {
      box['x'] = box['x']! + d;
      next['offsetX'] = next['offsetX']! + d;
    }
  } else {
    box['height'] = lead ? box['height']! - d : box['height']! + d;
    if (lead) {
      box['y'] = box['y']! + d;
      next['offsetY'] = next['offsetY']! + d;
    }
  }
  return {
    ...withRotationHeld(snap, box),
    'clip': normalizeClip(next, box['width']!, box['height']!),
    // A group's members must come back untouched — cropping reveals less of
    // them, it doesn't squash them.
    if (snap['type'] == 'group') 'children': snap['children'],
  };
}

/// STRETCH: the box alone, along one axis — for edges on elements that can't be
/// cropped meaningfully (text re-wraps in its box instead).
Map<String, dynamic> stretchByEdge(Map<String, dynamic> snap, String edge, double dx, double dy) {
  final horizontal = edge == 'left' || edge == 'right';
  final lead = edge == 'left' || edge == 'top';
  final size = horizontal ? _n(snap['width']) : _n(snap['height']);
  final travel = horizontal ? dx : dy;
  final d = lead ? math.min(travel, size - minBox) : math.max(travel, minBox - size);
  final box = {'x': _n(snap['x']), 'y': _n(snap['y']), 'width': _n(snap['width']), 'height': _n(snap['height'])};
  if (horizontal) {
    box['width'] = lead ? box['width']! - d : box['width']! + d;
    if (lead) box['x'] = box['x']! + d;
  } else {
    box['height'] = lead ? box['height']! - d : box['height']! + d;
    if (lead) box['y'] = box['y']! + d;
  }
  return withRotationHeld(snap, box);
}
