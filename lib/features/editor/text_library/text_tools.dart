import 'dart:async';

import '../../../core/design/js_values.dart';
import '../design_editor_controller.dart';
import 'text_combos.dart';
import 'text_looks.dart';
import 'text_style.dart';

/// What the Text library does to the design — port of the web's
/// `panels/text/useTextTools.js` (minus applyFont, which the Text panel's font
/// picker already covers):
///   applyLook   dress the selected text in an Effects look, or add new text wearing it
///   removeLook  take the look off the selected text
///   insertCombo drop a Templates design as its separate parts, all selected

/// How long a pick waits for its faces before measuring anyway. Boxes hug their
/// words, so measuring in the fallback face would size them for the wrong font —
/// but a stalled request mustn't make the tap do nothing.
const _fontWait = Duration(seconds: 4);

/// The selected element when it's text (useTextInsert's `selectedText`).
Map<String, dynamic>? selectedText(DesignEditorController c) {
  final el = c.selected;
  return el?['type'] == 'text' ? el : null;
}

/// The look the selected text wears, or null.
Map<String, dynamic>? activeLook(DesignEditorController c) => lookById(asMap(selectedText(c)?['textLook'])?['id']);

/// Restyle the selected text in [look], or — nothing selected — add new text
/// wearing it, centred on the page.
Future<void> applyLook(DesignEditorController c, Map<String, dynamic> look) async {
  final selected = selectedText(c);
  if (selected != null) {
    c.updateElement(selected['id'] as String, lookPatch(look, selected));
    return;
  }
  await textLibraryFonts.ensure([lookFace(look)]).timeout(_fontWait, onTimeout: () {});
  c.addElement(lookPatch(look, null, canvasWidth: c.canvasWidth, canvasHeight: c.canvasHeight));
}

/// Take the look (and its effect) off the selected text.
void removeLook(DesignEditorController c) {
  final selected = selectedText(c);
  if (selected == null) return;
  c.updateElement(selected['id'] as String, {'textLook': null, 'textEffect': null});
}

/// Drop [combo] on the page as its separate parts, all selected, as one undo
/// step. Like the web it isn't grouped, and lands centred (no paste offset).
Future<void> insertCombo(DesignEditorController c, Map<String, dynamic> combo) async {
  await textLibraryFonts.ensure(comboFaces(combo)).timeout(_fontWait, onTimeout: () {});
  c.addElements(buildCombo(combo, canvasWidth: c.canvasWidth, canvasHeight: c.canvasHeight), offset: 0);
}
