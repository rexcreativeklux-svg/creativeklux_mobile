import 'dart:math' as math;
import 'dart:ui';

import 'js_values.dart';

/// Ports of the web's `(lib)/design/groups.js` (flattenGroups and what it
/// needs) and `clip.js` (isClipped / windowed) — only the parts the renderer
/// uses.
///
/// A group is `{type: 'group', x, y, width, height, rotation, opacity,
/// children: [...]}` with children positioned relative to its corner. The
/// renderer flattens groups into absolute coordinates first and never has to
/// know they exist.

/// Key the flattened children carry their inherited clip windows under:
/// a list of polygons already in canvas space (successive clips intersect).
const clipKey = '__clip';

/// True when an element's `clip` window actually hides something.
bool isClipped(Object? clip) {
  final c = asMap(clip);
  if (c == null) return false;
  final w = numOf(c['contentW']);
  final h = numOf(c['contentH']);
  return w != null && h != null && w.isFinite && h.isFinite && w > 0 && h > 0;
}

/// The element to draw for a cropped (windowed) element: same element, but
/// its box is the CONTENT box rather than the window. The caller clips to the
/// real box first; this only moves the content.
Map<String, dynamic> windowed(Map<String, dynamic> el) {
  final c = asMap(el['clip']);
  if (!isClipped(c)) return el;
  return {
    ...el,
    'x': nnNum(el['x'], 0) - orNum(c!['offsetX'], 0),
    'y': nnNum(el['y'], 0) - orNum(c['offsetY'], 0),
    'width': numOf(c['contentW']),
    'height': numOf(c['contentH']),
  }..remove('clip');
}

Offset _rotatePoint(double px, double py, double cx, double cy, double deg) {
  final r = deg * math.pi / 180;
  final cos = math.cos(r);
  final sin = math.sin(r);
  final dx = px - cx;
  final dy = py - cy;
  return Offset(cx + dx * cos - dy * sin, cy + dx * sin + dy * cos);
}

/// A group's children in absolute canvas coordinates. A rotated group rotates
/// its children around its own centre (as the DOM wrapper does) and adds its
/// angle to theirs; opacity multiplies through.
List<Map<String, dynamic>> _absoluteChildren(Map<String, dynamic> group) {
  final angle = orNum(group['rotation'], 0);
  final gAlpha = nnNum(group['opacity'], 1);
  final gx = orNum(group['x'], 0);
  final gy = orNum(group['y'], 0);
  final gw = orNum(group['width'], 0);
  final gh = orNum(group['height'], 0);
  final cx = gx + gw / 2;
  final cy = gy + gh / 2;

  // A cropped group is a WINDOW onto its contents: members are laid out from
  // an origin behind the box, and the box becomes a mask the painter applies.
  final win = isClipped(group['clip']) ? asMap(group['clip']) : null;
  final originX = gx - (win == null ? 0 : orNum(win['offsetX'], 0));
  final originY = gy - (win == null ? 0 : orNum(win['offsetY'], 0));

  final polys = <List<Offset>>[...?(group[clipKey] as List<List<Offset>>?)];
  if (win != null) {
    polys.add([
      for (final (px, py) in [(gx, gy), (gx + gw, gy), (gx + gw, gy + gh), (gx, gy + gh)])
        angle != 0 ? _rotatePoint(px, py, cx, cy, angle) : Offset(px, py),
    ]);
  }

  final children = group['children'];
  if (children is! List) return const [];
  return [
    for (final raw in children)
      if (asMap(raw) case final child?) _placeChild(child, originX, originY, cx, cy, angle, gAlpha, group, polys),
  ];
}

Map<String, dynamic> _placeChild(
  Map<String, dynamic> child,
  double originX,
  double originY,
  double cx,
  double cy,
  double angle,
  double gAlpha,
  Map<String, dynamic> group,
  List<List<Offset>> polys,
) {
  final w = orNum(child['width'], 0);
  final h = orNum(child['height'], 0);
  var x = originX + orNum(child['x'], 0);
  var y = originY + orNum(child['y'], 0);
  if (angle != 0) {
    final c = _rotatePoint(x + w / 2, y + h / 2, cx, cy, angle);
    x = c.dx - w / 2;
    y = c.dy - h / 2;
  }
  final hidden = truthy(child['hidden']) || truthy(group['hidden']);
  return {
    ...child,
    'x': x,
    'y': y,
    'rotation': orNum(child['rotation'], 0) + angle,
    'opacity': nnNum(child['opacity'], 1) * gAlpha,
    'hidden': hidden ? true : null,
    if (polys.isNotEmpty) clipKey: polys,
  };
}

/// Expand every group into its children, recursively, preserving stacking order.
List<Map<String, dynamic>> flattenGroups(List<Map<String, dynamic>> elements) {
  final out = <Map<String, dynamic>>[];
  for (final el in elements) {
    if (el['type'] == 'group') {
      out.addAll(flattenGroups(_absoluteChildren(el)));
    } else {
      out.add(el);
    }
  }
  return out;
}
