import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../../core/design/js_values.dart';
import '../../../core/design/shapes.dart';
import 'text_combo_data.dart';
import 'text_looks.dart';
import 'text_style.dart';

/// The Text panel's TEMPLATES ("combos": a few text boxes, sometimes a shape,
/// designed together) — ports of the web's `panels/text/templates/textCombos.js`
/// (catalogue + search) and `buildCombo.js` (combo → this editor's elements),
/// over the data generated into text_combo_data.dart.
///
/// Building a combo:
///   1. scales every number by `scale` (a card uses 1; a page insert picks one
///      that suits the page — see [buildCombo]);
///   2. dresses a part that names a `look` in that Effects look first, then lays
///      the part's own fields over it;
///   3. translates the result into our own fields — one textEffect, a `shape`
///      key, lines coloured by `fill` (see text_style.dart);
///   4. MEASURES each text box in its face, so a box hugs its words — which is
///      why parts are placed by their centres: a measured width differs from
///      font to font, and a centre can't move.
///
/// Curved text is Design-Editor's alone: a part on a badge's ring or with a
/// `curve` lands straight, inside the ring where the curve would have run.

/// Every combo, each stamped with its `theme`, in theme order (TEXT_COMBOS).
final List<Map<String, dynamic>> textCombos = [
  for (final c in jsonDecode(textCombosJson) as List) c as Map<String, dynamic>,
];

/// A combo by id, or null.
Map<String, dynamic>? comboById(String id) => textCombos.where((c) => c['id'] == id).firstOrNull;

/// The combos in one theme ('all' = every combo).
List<Map<String, dynamic>> combosInTheme(String theme) => theme == 'all'
    ? textCombos
    : [
        for (final c in textCombos)
          if (c['theme'] == theme) c,
      ];

/// The combos matching a search — every word must appear in the combo's name,
/// its words, its tags or its theme.
List<Map<String, dynamic>> searchCombos(String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return textCombos;
  final themeLabel = {for (final (id, label) in comboThemes) id: label.toLowerCase()};
  return [
    for (final combo in textCombos)
      if (() {
        final content = [
          for (final p in combo['parts'] as List)
            if (p['type'] == 'text') p['content'],
        ].join(' ');
        final haystack = '${combo['label']} $content ${combo['tags'] ?? ''} ${themeLabel[combo['theme']]}'
            .toLowerCase();
        return words.every(haystack.contains);
      }())
        combo,
  ];
}

/// The text defaults a combo part starts from — centred, tight leading, a small inset.
const _textDefaults = <String, dynamic>{
  'fontWeight': 400,
  'textAlign': 'center',
  'lineHeight': 1.1,
  'padding': 4,
  'fill': '#111827',
};

/// Design-Editor shape types our library has under another name.
const _shapeAliases = {
  'rect': 'rect',
  'circle': 'circle',
  'star4': 'star4',
  'star5': 'star5',
  'hexagon': 'hexagon',
  'triangle': 'triangle',
  'heart-rounded': 'heart',
  'banner-ribbon': 'ribbon',
  'cloud-fluffy': 'cloud2',
};

/// Design-Editor's rules (drawn from `stroke`) → our line shapes (drawn from `fill`).
const _lineAliases = {
  'straight': 'line-solid',
  'dashed': 'line-dashed',
  'dotted': 'line-dotted',
  'arrow': 'line-arrow',
  'line-wavy': 'line-wavy',
};

/// Our straight lines are drawn in a 12-unit-tall viewBox (see shapes.dart).
const _lineViewBoxHeight = 12.0;

String? _shapeKeyFor(Object? type) => _shapeAliases[type] ?? (shapes.containsKey('tt-$type') ? 'tt-$type' : null);

typedef _StyleOf = TextStyle Function(Map<String, dynamic> el)?;

/// A text part, scaled, dressed in its look, and translated into our fields.
Map<String, dynamic> _buildText(Map<String, dynamic> part, double scale, _StyleOf styleOf) {
  final own = Map<String, dynamic>.of(part)
    ..removeWhere((k, _) => const {'at', 'look', 'width', 'ring', 'curve', 'type'}.contains(k));
  final size = orNum(part['fontSize'], 24) * scale;
  final look = lookById(part['look']);

  // Design-Editor's vocabulary first, at this size: defaults → look → part.
  final s = <String, dynamic>{
    ..._textDefaults,
    if (look != null) ...lookBaseFields(look, size),
    ...own,
    'fontSize': size,
  };
  double px(Object? v) => (numOf(v) ?? 0) * scale;
  if (own['letterSpacing'] != null) s['letterSpacing'] = px(own['letterSpacing']);
  if (own['padding'] != null) s['padding'] = px(own['padding']);
  if (own['cornerRadius'] != null) s['cornerRadius'] = px(own['cornerRadius']);
  if (asMap(own['textShadow']) case final ts?) {
    s['textShadow'] = {
      ...ts,
      'offsetX': px(ts['offsetX']),
      'offsetY': px(ts['offsetY'] ?? 4),
      'blur': px(ts['blur'] ?? 4),
    };
  }
  if (asMap(own['textStroke']) case final st?) {
    s['textStroke'] = {...st, 'width': px(st['width'])};
    // A part's own outline replaces its look's outline stack.
    s['outlines'] = null;
  }

  final (:fill, :textEffect) = effectFrom(s);
  final content = transformed(s['content'], s['textTransform']);
  final decoration = s['textDecoration'];
  final el = <String, dynamic>{
    'type': 'text',
    'content': content,
    'text': content,
    'fontFamily': kluxFamily(s['fontFamily']),
    'fontSize': size,
    'fontWeight': s['fontWeight'],
    'fontStyle': truthy(s['fontStyle']) ? s['fontStyle'] : 'normal',
    'fill': fill,
    'textAlign': s['textAlign'],
    'lineHeight': s['lineHeight'],
    'letterSpacing': round2(numOf(s['letterSpacing']) ?? 0),
    'textEffect': ?textEffect,
    if (decoration is String && decoration.contains('underline')) 'underline': true,
    'rotation': truthy(s['rotation']) ? s['rotation'] : 0,
    'opacity': s['opacity'] ?? 1,
    'basePadding': s['padding'],
  };

  final at = part['at'] as List;
  final cx = (numOf(at[0]) ?? 0) * scale;
  var cy = (numOf(at[1]) ?? 0) * scale;
  final width = numOf(part['width']);
  final fixedWidth = width != null && width != 0 ? width * scale : null;

  // On a ring: straight words inside the circle, where the arc's middle ran.
  if (asMap(part['ring']) case final ring?) {
    final radius = (numOf(ring['radius']) ?? 0) * scale;
    final inset = radius * 0.72;
    cy += ring['side'] == 'bottom' ? inset : -inset;
    final chord = 2 * math.sqrt(radius * radius - inset * inset) * 0.95;
    final natural = measureTextBox(el, styleOf: styleOf);
    if (natural.width > chord) {
      final k = chord / natural.width;
      el['fontSize'] = math.max(6.0, size * k);
      el['letterSpacing'] = round2((el['letterSpacing'] as double) * k);
    }
  }

  final box = measureTextBox(el, fixedWidth: fixedWidth, styleOf: styleOf);
  el.remove('basePadding');
  return {
    ...el,
    'padding': box.padding,
    'width': box.width,
    'height': box.height,
    'x': cx - box.width / 2,
    'y': cy - box.height / 2,
  };
}

/// One shape part (a plate, a ring, an ornament, a rule), centred on its `at`.
Map<String, dynamic>? _buildShape(Map<String, dynamic> part, double scale) {
  final at = part['at'] as List;
  final cx = (numOf(at[0]) ?? 0) * scale;
  final cy = (numOf(at[1]) ?? 0) * scale;
  final common = <String, dynamic>{
    'type': 'shape',
    'rotation': truthy(part['rotation']) ? part['rotation'] : 0,
    'opacity': part['opacity'] ?? 1,
  };

  final line = _lineAliases[part['type']];
  if (line != null) {
    final weight = orNum(part['strokeWidth'], orNum(part['height'], 2)) * scale;
    final w = (numOf(part['width']) ?? 0) * scale;
    final h = part['type'] == 'line-wavy'
        ? math.max(_lineViewBoxHeight, (numOf(part['height']) ?? 0) * scale)
        : _lineViewBoxHeight;
    return {
      ...common,
      'shape': line,
      'fill': truthy(part['stroke']) ? part['stroke'] : '#111111',
      // A line's stroke is in viewBox units, stretched with the box's height.
      'strokeWidth': weight * _lineViewBoxHeight / h,
      'width': w,
      'height': h,
      'x': cx - w / 2,
      'y': cy - h / 2,
    };
  }

  final key = _shapeKeyFor(part['type']);
  if (key == null) return null;
  final w = (numOf(part['width']) ?? 0) * scale;
  final h = (numOf(part['height']) ?? 0) * scale;
  final primitive = key == 'rect' || key == 'circle' || key == 'triangle';
  final strokePx = (numOf(part['strokeWidth']) ?? 0) * scale;
  final stroked = strokePx > 0 && truthy(part['stroke']) && part['stroke'] != 'none';
  final fill = part['fill'];
  return {
    ...common,
    'shape': key,
    'fill': !truthy(fill) || fill == 'none' ? 'transparent' : fill,
    if (stroked) ...{
      'stroke': part['stroke'],
      // Primitives draw a CSS border (px); library paths stroke in viewBox units.
      'strokeWidth': primitive ? strokePx : strokePx * 100 / math.max(1, math.min(w, h)),
      if (part['strokeStyle'] == 'dashed' || part['strokeStyle'] == 'dotted') 'strokeDash': part['strokeStyle'],
    },
    'borderRadius': key == 'rect' ? (numOf(part['cornerRadius']) ?? 0) * scale : 0,
    'width': w,
    'height': h,
    'x': cx - w / 2,
    'y': cy - h / 2,
  };
}

/// The box around a set of elements, turned boxes included.
Rect elementsBounds(List<Map<String, dynamic>> elements) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final el in elements) {
    final w = numOf(el['width']) ?? 0, h = numOf(el['height']) ?? 0;
    final cx = (numOf(el['x']) ?? 0) + w / 2;
    final cy = (numOf(el['y']) ?? 0) + h / 2;
    final turn = (numOf(el['rotation']) ?? 0) * math.pi / 180;
    final cos = math.cos(turn).abs(), sin = math.sin(turn).abs();
    final halfW = (w * cos + h * sin) / 2;
    final halfH = (w * sin + h * cos) / 2;
    minX = math.min(minX, cx - halfW);
    maxX = math.max(maxX, cx + halfW);
    minY = math.min(minY, cy - halfH);
    maxY = math.max(maxY, cy + halfH);
  }
  if (!minX.isFinite) return Rect.zero;
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// A combo's elements, in its own frame, at a scale — what a card previews.
({List<Map<String, dynamic>> elements, Rect bounds}) buildComboElements(
  Map<String, dynamic> combo, {
  double scale = 1,
  TextStyle Function(Map<String, dynamic> el)? styleOf,
}) {
  final elements = <Map<String, dynamic>>[
    for (final p in combo['parts'] as List)
      ?(p['type'] == 'text' ? _buildText(asMap(p)!, scale, styleOf) : _buildShape(asMap(p)!, scale)),
  ];
  return (elements: elements, bounds: elementsBounds(elements));
}

/// How much of the page's width a new combo takes, and the limits on its scale.
const _pageShare = 0.55;
const _minScale = 0.25;
const _maxScale = 4.0;

/// A combo sized for a page and centred on it — what the Text panel inserts
/// (the web's `comboOnPage`). Built once at 1:1 to learn its natural size, then
/// again at the scale that makes it take about half the page's width (and no
/// more than 80% of its height), measured afresh at that size.
///
/// Returns the elements in stacking order, in absolute page coordinates.
List<Map<String, dynamic>> buildCombo(
  Map<String, dynamic> combo, {
  required double canvasWidth,
  required double canvasHeight,
  TextStyle Function(Map<String, dynamic> el)? styleOf,
}) {
  final natural = buildComboElements(combo, styleOf: styleOf).bounds;
  final byWidth = canvasWidth * _pageShare / (natural.width == 0 ? 1 : natural.width);
  final byHeight = canvasHeight * 0.8 / (natural.height == 0 ? 1 : natural.height);
  final scale = math.max(_minScale, math.min(_maxScale, math.min(byWidth, byHeight)));

  final (:elements, :bounds) = buildComboElements(combo, scale: scale, styleOf: styleOf);
  final dx = canvasWidth / 2 - bounds.center.dx;
  final dy = canvasHeight / 2 - bounds.center.dy;
  return [
    for (final el in elements)
      {...el, 'x': jsRound(((el['x'] as num) + dx) * 100) / 100, 'y': jsRound(((el['y'] as num) + dy) * 100) / 100},
  ];
}

/// Every face (and cut) a combo is set in — loaded before a pick is measured
/// (the web's `comboFontQueries`).
Set<(String, FontWeight, FontStyle)> comboFaces(Map<String, dynamic> combo) => {
  for (final p in combo['parts'] as List)
    if (p['type'] == 'text')
      if (kluxFamily(p['fontFamily'] ?? lookById(p['look'])?['base']?['fontFamily']) case final family?)
        TextLibraryFonts.faceOf({
          'fontFamily': family,
          'fontWeight': p['fontWeight'] ?? lookById(p['look'])?['base']?['fontWeight'] ?? 400,
          'fontStyle': p['fontStyle'] ?? lookById(p['look'])?['base']?['fontStyle'] ?? 'normal',
        }),
};
