import 'dart:math' as math;

import 'js_values.dart';
import 'shapes.dart';

/// Port of the web's `(lib)/design/scraiveCompat.js` — read designs authored in
/// Scraive (the Design-Editor).
///
/// Scraive stores a shape AS its type (`{type: "rectangle"}`), where we store
/// `{type: "shape", shape: "rect"}`; a renderer that doesn't know the type skips
/// it silently, so a Scraive template kept its text and lost every band, card
/// and badge. Everything here is a pure translation into our own format.
/// Elements already in our format pass through untouched, and translated fields
/// are removed as they're consumed, so running it twice changes nothing.

/// Scraive shape type → our `shape` key, where the names differ.
const _shapeAliases = {
  'rectangle': 'rect',
  'oval': 'circle',
  'star7': 'star6',
  'speech-bubble-round': 'bubble-round',
  'speech-bubble-square': 'bubble-square',
  'thought-bubble': 'bubble',
  'cloud-basic': 'cloud',
  'cloud-fluffy': 'cloud2',
  'heart-classic': 'heart',
  'heart-rounded': 'heart',
  'banner-ribbon': 'ribbon',
  'teardrop-classic': 'teardrop',
  'teardrop-rounded': 'teardrop',
  'blob-1': 'blob',
  'blob-2': 'blob2',
  'flowchart-process': 'rect',
  'flowchart-decision': 'diamond',
  'flowchart-terminator': 'stadium',
  'flowchart-document': 'document',
  'gradient-box': 'rect',
  'badge': 'rect',
};

/// Scraive lines are drawn from `stroke`; our line shapes take their colour
/// from `fill`, so these swap the two.
const _lineAliases = {
  'straight': 'line-solid',
  'dashed': 'line-dashed',
  'dotted': 'line-dotted',
  'arrow': 'line-arrow',
  'double-arrow': 'line-arrow-both',
};

const _scraiveImageKeys = ['fitMode', 'flipHorizontal', 'flipVertical', 'cornerRadius', 'border'];
const _scraiveTextKeys = [
  'textTransform',
  'textDecoration',
  'textShadow',
  'textStroke',
  'backgroundColor',
  'cornerRadius',
];

int _clamp100(double n) => math.max(0, math.min(100, jsRound(n)));

/// A number as JS would print it in a string (`0.5`, `1`, not `1.0`).
String _jsNum(double n) => n == n.truncateToDouble() ? n.toInt().toString() : n.toString();

/// Scraive's opacities are 0–100 (occasionally 0–1). Folded into the colour,
/// since our shapes have no separate fill/stroke opacity.
Object? _withOpacity(Object? color, Object? opacity) {
  final o = numOf(opacity);
  if (color is! String || o == null) return color;
  final a = o > 1 ? o / 100 : o;
  if (a >= 1) return color;
  final hex = RegExp(r'^#([0-9a-f]{3}|[0-9a-f]{6})$', caseSensitive: false).firstMatch(color)?.group(1);
  if (hex != null) {
    final full = hex.length == 3 ? hex.split('').map((c) => '$c$c').join() : hex;
    final rgb = [0, 2, 4].map((i) => int.parse(full.substring(i, i + 2), radix: 16)).toList();
    return 'rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, ${_jsNum(a)})';
  }
  final inner = RegExp(r'^rgba?\(([^)]+)\)', caseSensitive: false).firstMatch(color)?.group(1);
  final rgb = inner?.split(',');
  if (rgb != null && rgb.length >= 3) return 'rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, ${_jsNum(a)})';
  return color;
}

/// Scraive paints nothing for "none" (or no colour).
Object _paint(Object? c) => (!truthy(c) || c == 'none') ? 'transparent' : c!;

/// The colours of a CSS gradient, for `gradient-box`'s two-stop fill.
String _gradientBoxFill(Map<String, dynamic> el) {
  final colours = RegExp(
    r'#[0-9a-f]{3,8}\b|rgba?\([^)]*\)',
    caseSensitive: false,
  ).allMatches('${el['gradient'] ?? ''}').map((m) => m.group(0)!).toList();
  final a = colours.isNotEmpty ? colours[0] : '#3B82F6';
  final b = colours.length > 1 ? colours[1] : '#1D4ED8';
  return 'linear-gradient(135deg, $a 0%, $b 100%)';
}

Map<String, dynamic> _without(Map<String, dynamic> el, List<String> keys) {
  final next = Map<String, dynamic>.of(el);
  for (final k in keys) {
    next.remove(k);
  }
  return next;
}

Map<String, dynamic> _toShape(Map<String, dynamic> el, String shapeKey) {
  final type = el['type'];
  final cornerRadius = el['cornerRadius'];
  final next = _without(el, [
    'type',
    'fillOpacity',
    'strokeOpacity',
    'cornerRadius',
    'strokeStyle',
    'shadow',
    'gradient',
  ]);
  next['type'] = 'shape';
  next['shape'] = shapeKey;
  next['fill'] = _paint(_withOpacity(el['fill'], el['fillOpacity']));
  final stroke = el['stroke'];
  if (truthy(stroke) && stroke != 'none') {
    next['stroke'] = _withOpacity(stroke, el['strokeOpacity']);
  } else {
    // `undefined` on the web — dropped by JSON, so dropped here too.
    next.remove('stroke');
  }

  // `rectangle` keeps the radius the data carries (pill buttons at radius =
  // height / 2); `rect` and `badge` always round.
  if (type == 'rectangle') {
    if ((numOf(cornerRadius) ?? 0) > 0) next['borderRadius'] = cornerRadius;
  } else if (type == 'rect') {
    next['borderRadius'] = cornerRadius ?? 12;
  } else if (type == 'badge') {
    next['borderRadius'] = 8;
  } else if (type == 'gradient-box') {
    next['fill'] = _gradientBoxFill(el);
    next['borderRadius'] = el['borderRadius'] ?? 12;
  }

  final strokeStyle = el['strokeStyle'];
  if (strokeStyle == 'dashed' || strokeStyle == 'dotted') next['strokeDash'] = strokeStyle;

  final shadow = asMap(el['shadow']);
  if (shadow != null && truthy(shadow['enabled'])) {
    final dx = orNum(shadow['offsetX'], 0);
    final dy = nnNum(shadow['offsetY'], 10);
    next['shapeEffect'] = {
      'type': 'drop',
      'color': truthy(shadow['color']) ? shadow['color'] : '#000000',
      'direction': jsRound(math.atan2(dy, dx) * 180 / math.pi),
      'offset': 40,
      'blur': 30,
      'transparency': 60,
    };
  }
  return next;
}

Map<String, dynamic> _toLine(Map<String, dynamic> el, String shapeKey) {
  final next = _without(el, ['type', 'strokeOpacity', 'strokeStyle']);
  next['type'] = 'shape';
  next['shape'] = shapeKey;
  next['fill'] = _withOpacity(truthy(el['stroke']) ? el['stroke'] : '#000000', el['strokeOpacity']);
  next['strokeWidth'] = truthy(el['strokeWidth']) ? el['strokeWidth'] : 2;
  return next;
}

/// Scraive's textTransform, baked into the content.
Object? _transformed(Object? content, Object? mode) {
  if (content is! String) return content;
  if (mode == 'uppercase') return content.toUpperCase();
  if (mode == 'lowercase') return content.toLowerCase();
  if (mode == 'capitalize') {
    return content.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }
  return content;
}

/// Scraive text carries a background box, an outline and a shadow; ours has
/// ONE `textEffect` slot, so the most visible one wins. Params are back-solved
/// from textEffects' size-relative formulas to land near Scraive's pixels.
Map<String, dynamic>? _textEffectFrom(Map<String, dynamic> el) {
  final size = orNum(el['fontSize'], 16);
  final bg = el['backgroundColor'];
  if (truthy(bg) && bg != 'transparent' && bg != 'none') {
    return {
      'type': 'background',
      'color': bg,
      'transparency': 0,
      'roundness': _clamp100(orNum(el['cornerRadius'], 0) / (size * 0.6) * 100),
      'spread': 0,
    };
  }
  final stroke = asMap(el['textStroke']);
  if (stroke != null && truthy(stroke['enabled']) && (numOf(stroke['width']) ?? 0) > 0) {
    return {
      'type': 'outline',
      'color': truthy(stroke['color']) ? stroke['color'] : '#000000',
      'thickness': _clamp100(numOf(stroke['width'])! / (size * 0.07) * 100),
    };
  }
  final shadow = asMap(el['textShadow']);
  if (shadow != null && truthy(shadow['enabled'])) {
    final dx = orNum(shadow['offsetX'], 0);
    final dy = nnNum(shadow['offsetY'], 4);
    return {
      'type': 'shadow',
      'color': truthy(shadow['color']) ? shadow['color'] : '#000000',
      'direction': jsRound(math.atan2(dy, dx) * 180 / math.pi),
      'offset': _clamp100(math.sqrt(dx * dx + dy * dy) / (size * 0.5) * 100),
      'blur': _clamp100(nnNum(shadow['blur'], 4) / (size * 0.8) * 100),
      'transparency': 40,
    };
  }
  return null;
}

Map<String, dynamic> _toText(Map<String, dynamic> el, bool layout) {
  final next = _without(el, _scraiveTextKeys);
  next['type'] = 'text';

  final tt = el['textTransform'];
  if (truthy(tt) && tt != 'none' && el.containsKey('content')) {
    next['content'] = _transformed(el['content'], tt);
  }
  final deco = el['textDecoration'];
  if (deco is String && deco.contains('underline')) next['underline'] = true;
  if (!truthy(el['textEffect'])) {
    final effect = _textEffectFrom(el);
    if (effect != null) next['textEffect'] = effect;
  }

  // Scraive lays text out from the top of the box, 5px in, at 1.2 and in
  // black — ours centres it at 1.3 with 2px in #111. Only on request: see
  // [fromScraiveElement].
  if (layout && !truthy(el['verticalAlign'])) {
    next['verticalAlign'] = 'top';
    next['padding'] = el['padding'] ?? 5;
    next['lineHeight'] = truthy(el['lineHeight']) ? el['lineHeight'] : 1.2;
    if (!truthy(el['fill']) && !truthy(el['color'])) next['fill'] = '#000000';
  }
  return next;
}

Map<String, dynamic> _toImage(Map<String, dynamic> el) {
  final next = _without(el, _scraiveImageKeys);
  if (truthy(el['fitMode']) && !truthy(el['objectFit'])) next['objectFit'] = el['fitMode'];
  if (truthy(el['flipHorizontal']) && el['flipH'] == null) next['flipH'] = true;
  if (truthy(el['flipVertical']) && el['flipV'] == null) next['flipV'] = true;
  if (el['cornerRadius'] != null && el['borderRadius'] == null) next['borderRadius'] = el['cornerRadius'];
  final border = asMap(el['border']);
  if (border != null && truthy(border['enabled']) && (numOf(border['width']) ?? 0) > 0 && el['borderWidth'] == null) {
    next['borderWidth'] = border['width'];
    next['borderColor'] = truthy(border['color']) ? border['color'] : '#ffffff';
  }
  return next;
}

/// Translate one Scraive element into our format; ours come back as-is.
///
/// [text] opts into Scraive's text LAYOUT (top-aligned, its padding and line
/// height). A plain `{type: "text"}` looks identical in both formats and ours
/// stay vertically centred, so only a caller that KNOWS the design came from
/// Scraive (a fetched template, a redesign result) sets it.
Map<String, dynamic> fromScraiveElement(Map<String, dynamic> input, {bool text = false}) {
  var el = input;

  // Scraive hides with `visible: false`; we hide with `hidden`.
  if (el['visible'] == false && el['hidden'] == null) {
    el = _without(el, ['visible'])..['hidden'] = true;
  }
  final type = el['type'];

  // `{type:"shape", shape:"rectangle"}` — Scraive's wrapped spelling.
  if (type == 'shape') {
    final alias = _shapeAliases[el['shape']];
    return alias != null ? (Map<String, dynamic>.of(el)..['shape'] = alias) : el;
  }

  // Scraive's text presets (text-title, text-heading, …) are plain text with a
  // default style already on the element.
  if (type is String && type.startsWith('text')) {
    final needs =
        type != 'text' || (text && !truthy(el['verticalAlign'])) || _scraiveTextKeys.any((k) => el[k] != null);
    return needs ? _toText(el, text) : el;
  }

  if (type == 'image') {
    return _scraiveImageKeys.any((k) => el[k] != null) ? _toImage(el) : el;
  }

  // Scraive keeps a group's members as { originalElement, relativeX, relativeY };
  // ours are plain elements positioned relative to the group's corner.
  final childrenData = el['childrenData'];
  if (type == 'group' && childrenData is List && el['children'] == null) {
    final next = _without(el, ['childrenData']);
    next['children'] = [
      for (final raw in childrenData)
        if (asMap(raw) case final c?)
          fromScraiveElement({
            ...(asMap(c['originalElement']) ?? c),
            'x': c['relativeX'] ?? 0,
            'y': c['relativeY'] ?? 0,
          }, text: text),
    ];
    return next;
  }

  final line = _lineAliases[type];
  if (line != null) return _toLine(el, line);
  final shapeKey =
      _shapeAliases[type] ?? ((primitiveShapes.contains(type) || shapes.containsKey(type)) ? type as String : null);
  if (shapeKey != null) return _toShape(el, shapeKey);

  return el;
}

/// Translate a whole element list. Also puts it in stacking order first: older
/// Scraive designs carry a `zIndex`, and array order is the only stacking the
/// renderer reads. Non-object entries are dropped.
List<Map<String, dynamic>> fromScraiveElements(List<dynamic> elements, {bool text = false}) {
  var ordered = [for (final e in elements) ?asMap(e)];
  if (ordered.any((e) => e['zIndex'] != null)) {
    final indexed = [for (var i = 0; i < ordered.length; i++) (i, ordered[i])];
    indexed.sort((a, b) {
      final az = numOf(a.$2['zIndex']) ?? a.$1.toDouble();
      final bz = numOf(b.$2['zIndex']) ?? b.$1.toDouble();
      return az == bz ? a.$1 - b.$1 : az.compareTo(bz);
    });
    ordered = [
      for (final (_, e) in indexed) _without(e, ['zIndex']),
    ];
  }
  return [for (final el in ordered) fromScraiveElement(el, text: text)];
}
