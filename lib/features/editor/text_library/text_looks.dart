import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../../core/design/js_values.dart';
import 'text_look_data.dart';
import 'text_style.dart';

/// The Text panel's Effects library — port of the web's
/// `panels/text/looks/lookStyle.js`, over the data generated from
/// `lookData.js` (text_look_data.dart).
///
/// A look is a map: `{id, label, base: {fontFamily, fontSize, fill, …},
/// outlines?, plate?, extrude?, sample?}` — Design-Editor's still styling.

/// How many looks a category row shows before "See all".
const lookRowCount = 8;

/// What a new text box wearing an EFFECT says (templates bring their own words).
const _effectContent = 'Your text';

final Map<String, dynamic> _looks = jsonDecode(looksJson) as Map<String, dynamic>;

/// Every look, by id (LOOKS).
Map<String, dynamic> get textLooks => _looks;

/// A look by id, with its id on it — or null.
Map<String, dynamic>? lookById(Object? id) {
  if (id is! String || id.isEmpty) return null;
  final look = asMap(_looks[id]);
  return look == null ? null : {'id': id, ...look};
}

/// One Effects category row: its id, label and looks.
typedef LookRow = ({String id, String label, List<Map<String, dynamic>> items});

/// The Effects tab's category rows, each with its looks (LOOK_ROW_GROUPS).
final List<LookRow> lookRowGroups = [
  for (final row in jsonDecode(lookRowsJson) as List)
    (id: '${row['id']}', label: '${row['label']}', items: [for (final id in row['items'] as List) ?lookById(id)]),
];

/// The words a card previews: effects all say the same word, templates say their own.
String lookPreviewText(Map<String, dynamic> look) => truthy(look['sample']) ? '${look['sample']}' : lookSample;

/// The words a NEW text box wearing this look lands with.
String lookContent(Map<String, dynamic> look) => truthy(look['sample']) ? '${look['sample']}' : _effectContent;

/// A look's own px values, scaled from the size it was authored at to [fontSize].
({double k, Map<String, dynamic> style}) _scaledLook(Map<String, dynamic> look, double fontSize) {
  final base = asMap(look['base']) ?? const {};
  final baseSize = numOf(base['fontSize']) ?? 0;
  final k = fontSize > 0 && baseSize > 0 ? fontSize / baseSize : 1.0;
  double px(Object? v) => (numOf(v) ?? 0) * k;
  final shadow = asMap(base['textShadow']);
  final stroke = asMap(base['textStroke']);
  final bg = asMap(base['textBackground']);
  final extrude = asMap(look['extrude']);
  // Keys stay present even when null: a template part lays its own fields
  // over these, and the web's spread lets a present-but-undefined key win too.
  return (
    k: k,
    style: <String, dynamic>{
      'fontSize': fontSize,
      'fill': base['fill'],
      'textShadow': shadow == null
          ? null
          : {...shadow, 'offsetX': px(shadow['offsetX']), 'offsetY': px(shadow['offsetY']), 'blur': px(shadow['blur'])},
      'textStroke': stroke == null ? null : {...stroke, 'width': px(stroke['width'])},
      'backgroundColor': truthy(bg?['enabled']) ? bg!['color'] : null,
      'cornerRadius': px(bg?['cornerRadius']),
      'outlines': look['outlines'] is List
          ? [
              for (final o in look['outlines'] as List) {...?asMap(o), 'width': px(asMap(o)?['width'])},
            ]
          : null,
      'extrude': extrude == null ? null : {...extrude, 'depth': px(extrude['depth'])},
      'plate': look['plate'],
    },
  );
}

/// Design-Editor's still styling for a look at a size — the shape a template
/// part is written in, so a part naming a `look` can lay its own fields over it.
Map<String, dynamic> lookBaseFields(Map<String, dynamic> look, double fontSize) {
  final (:k, :style) = _scaledLook(look, fontSize);
  final base = asMap(look['base']) ?? const {};
  return {
    ...style,
    'fontFamily': base['fontFamily'],
    'fontWeight': base['fontWeight'],
    'fontStyle': base['fontStyle'],
    'lineHeight': base['lineHeight'],
    'letterSpacing': (numOf(base['letterSpacing']) ?? 0) * k,
    'textTransform': base['textTransform'],
  };
}

/// The element fields that dress text in a look (the web's `lookPatch`).
/// Content, box and position are the element's own — a look decides how text
/// looks, never what it says or where it sits (case aside: there is no text
/// case here, so it's in the words).
Map<String, dynamic> lookFields(Map<String, dynamic> look, double fontSize, String content) {
  final s = lookBaseFields(look, fontSize);
  final (:fill, :textEffect) = effectFrom(s);
  return {
    'textLook': {'id': look['id']},
    'content': transformed(content, s['textTransform']),
    'fontFamily': kluxFamily(s['fontFamily']),
    'fontWeight': s['fontWeight'],
    'fontStyle': truthy(s['fontStyle']) ? s['fontStyle'] : 'normal',
    'fill': fill,
    'lineHeight': s['lineHeight'],
    'letterSpacing': round2(numOf(s['letterSpacing']) ?? 0),
    'textEffect': textEffect,
  };
}

/// A whole text element wearing a look, centred on ([cx], [cy]) — what a card
/// previews and what a pick drops on the page.
Map<String, dynamic> lookElement(
  Map<String, dynamic> look, {
  required String content,
  required double fontSize,
  double cx = 0,
  double cy = 0,
  TextStyle Function(Map<String, dynamic> el)? styleOf,
}) {
  final el = <String, dynamic>{
    'type': 'text',
    'textAlign': 'center',
    'fontSize': fontSize,
    ...lookFields(look, fontSize, content),
  };
  final box = measureTextBox(el, styleOf: styleOf);
  return {
    ...el,
    'text': el['content'],
    'padding': box.padding,
    'width': box.width,
    'height': box.height,
    'x': cx - box.width / 2,
    'y': cy - box.height / 2,
    'rotation': 0,
    'opacity': 1,
  };
}

/// The size a new text box wearing a look lands at (useTextTools.applyLook).
double newLookFontSize(double canvasWidth, double canvasHeight) =>
    math.max(24, jsRound(math.min(canvasWidth, canvasHeight) * 0.09)).toDouble();

/// What applying [look] writes — useTextTools.applyLook without the editor.
///
/// With [selectedText] (a text element), the PATCH that restyles it in place:
/// its own size and words, the look's face, fill, spacing and effect (the box
/// isn't re-measured — the web doesn't either). With none, the whole NEW text
/// element to add: the look's sample words (or "Your text") at 9% of the
/// page's shorter side (24 at least), centred on the page.
Map<String, dynamic> lookPatch(
  Map<String, dynamic> look,
  Map<String, dynamic>? selectedText, {
  double canvasWidth = 1080,
  double canvasHeight = 1080,
  TextStyle Function(Map<String, dynamic> el)? styleOf,
}) {
  if (selectedText != null) {
    final words = selectedText['content'] ?? selectedText['text'] ?? '';
    final patch = lookFields(look, orNum(selectedText['fontSize'], 40), '$words');
    return {...patch, 'text': patch['content']};
  }
  return lookElement(
    look,
    content: lookContent(look),
    fontSize: newLookFontSize(canvasWidth, canvasHeight),
    cx: canvasWidth / 2,
    cy: canvasHeight / 2,
    styleOf: styleOf,
  );
}

/// The face a look is set in, to load before measuring a new box for it.
(String, FontWeight, FontStyle) lookFace(Map<String, dynamic> look) {
  final base = asMap(look['base']) ?? const {};
  return TextLibraryFonts.faceOf({
    'fontFamily': kluxFamily(base['fontFamily']),
    'fontWeight': base['fontWeight'] ?? 400,
    'fontStyle': base['fontStyle'] ?? 'normal',
  });
}
