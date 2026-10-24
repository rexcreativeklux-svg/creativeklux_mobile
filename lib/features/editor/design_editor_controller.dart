import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../../core/design/groups.dart';
import '../../core/design/js_values.dart';
import '../../core/design/resize_element.dart';
import '../../core/design/scraive_compat.dart';

/// The single source of truth for the design editor — port of the web's
/// `design/[id]/_components/useDesignEditor.js`.
///
/// A design is `{canvas, elements}`: canvas = `{width, height, background}`,
/// elements = maps with `{id, type, x, y, width, height, rotation, opacity, …}`.
/// Array order IS the stacking order (back → front).
///
/// Selection is a list, but every contextual control acts on the FIRST
/// selected element — the web's convention.
class DesignEditorController extends ChangeNotifier {
  DesignEditorController({
    required this.designId,
    required String name,
    required Map<String, dynamic> canvas,
    required List<dynamic> elements,
    this.notes = '',
    this.raw = const {},
  }) : _name = name,
       _savedName = name {
    final seed = normalizeForEditor(canvas, elements);
    _canvas = seed.$1;
    _elements = seed.$2;
  }

  final int designId;

  /// The API record it was opened from (type/sub_type for publishing).
  final Map<String, dynamic> raw;

  /// Notes ride inside the same canvas JSON blob as the design (web behaviour).
  String notes;

  static const _maxHistory = 60;
  static int _uid = 0;

  static String nextElementId() => 'el_${++_uid}_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

  late Map<String, dynamic> _canvas;
  late List<Map<String, dynamic>> _elements;
  List<String> _selectedIds = [];
  String _name;
  String _savedName;
  bool _dirty = false;

  final List<(Map<String, dynamic>, List<Map<String, dynamic>>)> _past = [];
  final List<(Map<String, dynamic>, List<Map<String, dynamic>>)> _future = [];

  Map<String, dynamic> get canvas => _canvas;
  List<Map<String, dynamic>> get elements => _elements;
  List<String> get selectedIds => _selectedIds;
  String get name => _name;
  bool get dirty => _dirty || _name != _savedName;
  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;

  double get canvasWidth => orNum(_canvas['width'], 1080);
  double get canvasHeight => orNum(_canvas['height'], 1080);

  /// The selection in element (stacking) order. A group MEMBER, reached by
  /// tapping into its group, comes back as its absolute view (see [byId]), so
  /// everything downstream treats it as an ordinary element.
  List<Map<String, dynamic>> get selectedElements {
    final wanted = _selectedIds.toSet();
    final direct = [
      for (final el in _elements)
        if (wanted.contains(el['id'])) el,
    ];
    if (direct.length == wanted.length) return direct;
    return [for (final id in _selectedIds) ?byId(id)];
  }

  Map<String, dynamic>? get selected => selectedElements.firstOrNull;

  /// An element by id — top level first, then one level into groups, where a
  /// member is returned in ABSOLUTE canvas terms with `groupId` set
  /// (`findAnyElement` / `childAsElement` in groups.js).
  Map<String, dynamic>? byId(String id) {
    final direct = _elements.where((e) => e['id'] == id).firstOrNull;
    if (direct != null) return direct;
    final group = groupOf(id);
    if (group == null) return null;
    final child = (group['children'] as List).whereType<Map>().firstWhere((c) => c['id'] == id);
    return childView(group, Map<String, dynamic>.from(child));
  }

  /// The group that owns member [id], or null.
  Map<String, dynamic>? groupOf(String id) => _elements
      .where((e) => e['type'] == 'group' && (e['children'] as List? ?? const []).any((c) => c is Map && c['id'] == id))
      .firstOrNull;

  /// Where a group's contents start — a cropped group's box is a window, so
  /// members are laid out from an origin behind it (`groupOrigin`).
  static Offset _groupOrigin(Map<String, dynamic> g) {
    final clip = isClipped(g['clip']) ? asMap(g['clip']) : null;
    return Offset(
      orNum(g['x'], 0) - (clip == null ? 0 : orNum(clip['offsetX'], 0)),
      orNum(g['y'], 0) - (clip == null ? 0 : orNum(clip['offsetY'], 0)),
    );
  }

  static Offset _rotateAbout(Offset p, Offset c, double deg) {
    final r = deg * math.pi / 180;
    final d = p - c;
    return c + Offset(d.dx * math.cos(r) - d.dy * math.sin(r), d.dx * math.sin(r) + d.dy * math.cos(r));
  }

  static Offset _groupCentre(Map<String, dynamic> g) =>
      Offset(orNum(g['x'], 0) + orNum(g['width'], 0) / 2, orNum(g['y'], 0) + orNum(g['height'], 0) / 2);

  /// A member as an ordinary element: its box swung through the group's
  /// rotation about the group's centre, the group's angle added to its own.
  static Map<String, dynamic> childView(Map<String, dynamic> group, Map<String, dynamic> child) {
    final angle = orNum(group['rotation'], 0);
    final w = orNum(child['width'], 0), h = orNum(child['height'], 0);
    final o = _groupOrigin(group);
    var centre = o + Offset(orNum(child['x'], 0) + w / 2, orNum(child['y'], 0) + h / 2);
    if (angle != 0) centre = _rotateAbout(centre, _groupCentre(group), angle);
    return {
      ...child,
      'x': centre.dx - w / 2,
      'y': centre.dy - h / 2,
      'rotation': orNum(child['rotation'], 0) + angle,
      'groupId': group['id'],
    };
  }

  /// A group with one member patched. The patch is ABSOLUTE (it's the only kind
  /// the editor deals in), so position and rotation are converted back to the
  /// group-relative, unrotated form the member is stored in (`patchGroupChild`).
  /// Resizing a member doesn't resize the group — its box is the user's.
  static Map<String, dynamic> _patchGroupChild(Map<String, dynamic> group, String childId, Map<String, dynamic> patch) {
    final angle = orNum(group['rotation'], 0);
    final o = _groupOrigin(group);
    return {
      ...group,
      'children': [
        for (final raw in group['children'] as List)
          if (raw is Map && raw['id'] == childId)
            () {
              final child = Map<String, dynamic>.from(raw);
              final rest = {...patch}
                ..remove('x')
                ..remove('y')
                ..remove('rotation')
                ..remove('groupId');
              final next = _patched(child, rest);
              if (patch.containsKey('rotation')) next['rotation'] = orNum(patch['rotation'], 0) - angle;
              if (!patch.containsKey('x') && !patch.containsKey('y')) return next;
              final view = childView(group, child);
              final w = orNum(next['width'], 0), h = orNum(next['height'], 0);
              var centre = Offset(
                (numOf(patch['x']) ?? orNum(view['x'], 0)) + w / 2,
                (numOf(patch['y']) ?? orNum(view['y'], 0)) + h / 2,
              );
              if (angle != 0) centre = _rotateAbout(centre, _groupCentre(group), -angle);
              next['x'] = centre.dx - w / 2 - o.dx;
              next['y'] = centre.dy - h / 2 - o.dy;
              return next;
            }()
          else
            raw,
      ],
    };
  }

  // ── Normalising ────────────────────────────────────────────────────────────

  static Map<String, dynamic> _normalizeElement(Map<String, dynamic> el) {
    final next = <String, dynamic>{
      'id': nextElementId(),
      'type': 'text',
      'rotation': 0,
      'opacity': 1,
      ...el,
      'x': numOf(el['x']) ?? 0,
      'y': numOf(el['y']) ?? 0,
      'width': orNum(el['width'], 120),
      'height': orNum(el['height'], 40),
    };
    if (next['type'] == 'group' && next['children'] is List) {
      next['children'] = [
        for (final c in next['children'] as List)
          if (asMap(c) case final m?) _normalizeElement(m),
      ];
    }
    return next;
  }

  /// Ids/defaults on every element, Scraive shapes translated.
  static (Map<String, dynamic>, List<Map<String, dynamic>>) normalizeForEditor(
    Map<String, dynamic> canvas,
    List<dynamic> elements,
  ) => (
    {
      ...canvas,
      'width': orNum(canvas['width'], 1080),
      'height': orNum(canvas['height'], 1080),
      'background': truthy(canvas['background']) ? canvas['background'] : '#ffffff',
    },
    fromScraiveElements(elements).map(_normalizeElement).toList(),
  );

  // ── History ────────────────────────────────────────────────────────────────

  (Map<String, dynamic>, List<Map<String, dynamic>>) _snapshot() =>
      (Map<String, dynamic>.from(_canvas), [for (final e in _elements) Map<String, dynamic>.from(e)]);

  /// Push the current state onto the undo stack before a mutation. Gestures
  /// call this once at their start and then patch with `record: false`, so a
  /// whole drag is one undo step.
  void commit() {
    _past.add(_snapshot());
    if (_past.length > _maxHistory) _past.removeAt(0);
    _future.clear();
    _dirty = true;
  }

  void undo() {
    if (_past.isEmpty) return;
    _future.add(_snapshot());
    final (c, e) = _past.removeLast();
    _canvas = c;
    _elements = e;
    _pruneSelection();
    _dirty = true;
    notifyListeners();
  }

  void redo() {
    if (_future.isEmpty) return;
    _past.add(_snapshot());
    final (c, e) = _future.removeLast();
    _canvas = c;
    _elements = e;
    _pruneSelection();
    _dirty = true;
    notifyListeners();
  }

  void _pruneSelection() {
    final ids = {for (final e in _elements) e['id']};
    _selectedIds = _selectedIds.where(ids.contains).toList();
  }

  // ── Selection ──────────────────────────────────────────────────────────────

  void select(String? id) {
    _selectedIds = id == null ? [] : [id];
    notifyListeners();
  }

  void setSelection(List<String> ids) {
    _selectedIds = ids.toSet().toList();
    notifyListeners();
  }

  void toggleSelection(String id) {
    _selectedIds = _selectedIds.contains(id) ? (_selectedIds.toList()..remove(id)) : [..._selectedIds, id];
    notifyListeners();
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  /// A group's box is only a frame around its members, so resizing it has to
  /// carry them; a patch that already names `children` did that itself.
  static Map<String, dynamic> _patched(Map<String, dynamic> el, Map<String, dynamic> patch) {
    if (el['type'] != 'group' || patch.containsKey('children')) return {...el, ...patch};
    final w = numOf(patch['width']) ?? orNum(el['width'], 0);
    final h = numOf(patch['height']) ?? orNum(el['height'], 0);
    final ow = orNum(el['width'], w), oh = orNum(el['height'], h);
    if (w == ow && h == oh) return {...el, ...patch};
    return {...el, ...patch, 'children': scaleChildren(el['children'], ow == 0 ? 1 : w / ow, oh == 0 ? 1 : h / oh)};
  }

  /// Patch one element by id — top level OR a group member. The id decides
  /// where the write lands, so no caller has to know about groups.
  void updateElement(String id, Map<String, dynamic> patch, {bool record = true}) =>
      updateElements({id: patch}, record: record);

  /// Many patches (`{id: patch}`) in one update — a multi-selection drag. A
  /// patch may also name a group member; it's folded into its group.
  void updateElements(Map<String, Map<String, dynamic>> patches, {bool record = true}) {
    if (patches.isEmpty) return;
    if (record) commit();
    _elements = [
      for (final el in _elements)
        if (patches[el['id']] != null)
          _patched(el, patches[el['id']]!)
        else if (el['type'] == 'group')
          (el['children'] as List? ?? const []).fold<Map<String, dynamic>>(
            el,
            (g, c) =>
                c is Map && patches[c['id']] != null ? _patchGroupChild(g, c['id'] as String, patches[c['id']]!) : g,
          )
        else
          el,
    ];
    _dirty = true;
    notifyListeners();
  }

  String addElement(Map<String, dynamic> el) {
    commit();
    final withId = <String, dynamic>{'id': nextElementId(), 'rotation': 0, 'opacity': 1, ...el};
    _elements = [..._elements, withId];
    _selectedIds = [withId['id'] as String];
    notifyListeners();
    return withId['id'] as String;
  }

  /// Delete as ONE undo step. Locked elements stay — a lock means "don't touch".
  void removeElements(List<String> ids) {
    final doomed = ids.toSet();
    if (doomed.isEmpty) return;
    commit();
    final next = <Map<String, dynamic>>[];
    for (final el in _elements) {
      if (doomed.contains(el['id'])) {
        if (truthy(el['locked'])) next.add(el);
        continue;
      }
      if (el['type'] != 'group') {
        next.add(el);
        continue;
      }
      // Deleting a MEMBER takes it out of its group. A group worn down to
      // fewer than two stops being a group — its last member goes back onto
      // the page where it was.
      final children = (el['children'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
      final kept = [
        for (final ch in children)
          if (!doomed.contains(ch['id']) || truthy(ch['locked'])) ch,
      ];
      if (kept.length == children.length) {
        next.add(el);
      } else if (kept.length >= 2) {
        next.add({...el, 'children': kept});
      } else {
        next.addAll([
          for (final ch in kept) {...childView(el, ch)}..remove('groupId'),
        ]);
      }
    }
    _elements = next;
    _selectedIds = _selectedIds.where((id) => !doomed.contains(id)).toList();
    notifyListeners();
  }

  static Map<String, dynamic> _clone(Map<String, dynamic> el) {
    final copy = <String, dynamic>{...el, 'id': nextElementId()};
    if (asMap(el['clip']) case final clip?) copy['clip'] = {...clip};
    if (el['type'] == 'group' && el['children'] is List) {
      copy['children'] = [
        for (final c in el['children'] as List)
          if (asMap(c) case final m?) _clone(m),
      ];
    }
    return copy;
  }

  /// Copies offset by 24, which become the selection ("duplicate then drag").
  void duplicateElements(List<String> ids) {
    final wanted = ids.toSet();
    final copies = [
      for (final el in _elements)
        if (wanted.contains(el['id'])) {..._clone(el), 'x': orNum(el['x'], 0) + 24, 'y': orNum(el['y'], 0) + 24},
    ];
    if (copies.isEmpty) return;
    commit();
    _elements = [..._elements, ...copies];
    _selectedIds = [for (final c in copies) c['id'] as String];
    notifyListeners();
  }

  /// Reorder z-index: 'front' | 'back' | 'forward' | 'backward'.
  void moveLayer(String id, String dir) {
    final idx = _elements.indexWhere((e) => e['id'] == id);
    if (idx == -1) return;
    commit();
    final arr = [..._elements];
    final item = arr.removeAt(idx);
    switch (dir) {
      case 'front':
        arr.add(item);
      case 'back':
        arr.insert(0, item);
      case 'forward':
        arr.insert(math.min(idx + 1, arr.length), item);
      default:
        arr.insert(math.max(idx - 1, 0), item);
    }
    _elements = arr;
    notifyListeners();
  }

  /// Replace the whole stack (the Layers list's drag-to-restack).
  void reorderElements(List<Map<String, dynamic>> next) {
    commit();
    _elements = next;
    notifyListeners();
  }

  /// Replace the whole design (applying a template) — undoable.
  void replaceDesign(Map<String, dynamic> canvas, List<dynamic> elements) {
    commit();
    final next = normalizeForEditor(canvas, elements);
    _canvas = next.$1;
    _elements = next.$2;
    _selectedIds = [];
    notifyListeners();
  }

  void setBackground(Object background) {
    commit();
    _canvas = {..._canvas, 'background': background};
    notifyListeners();
  }

  /// Fold two or more elements into a group, in place of the FRONT-MOST member
  /// — so it lands where its contents already were in the stack. Members keep
  /// their order and properties; only x/y are rebased onto the group's corner
  /// (`groups.js` makeGroup). Locked members are skipped.
  void groupElements(List<String> ids) {
    final wanted = ids.toSet();
    final members = [
      for (final el in _elements)
        if (wanted.contains(el['id']) && !truthy(el['locked'])) el,
    ];
    if (members.length < 2) return;
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final el in members) {
      final x = orNum(el['x'], 0), y = orNum(el['y'], 0);
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x + orNum(el['width'], 0));
      maxY = math.max(maxY, y + orNum(el['height'], 0));
    }
    final group = <String, dynamic>{
      'id': nextElementId(),
      'type': 'group',
      'x': minX,
      'y': minY,
      'width': maxX - minX,
      'height': maxY - minY,
      'rotation': 0,
      'opacity': 1,
      'children': [
        for (final el in members) {...el, 'x': orNum(el['x'], 0) - minX, 'y': orNum(el['y'], 0) - minY},
      ],
    };
    final memberIds = {for (final m in members) m['id']};
    final frontIndex = _elements.lastIndexWhere((e) => memberIds.contains(e['id']));
    commit();
    final rest = [
      for (final e in _elements)
        if (!memberIds.contains(e['id'])) e,
    ];
    final insertAt = _elements.take(frontIndex).where((e) => !memberIds.contains(e['id'])).length;
    rest.insert(insertAt, group);
    _elements = rest;
    _selectedIds = [group['id'] as String];
    notifyListeners();
  }

  /// Paste: elements added as ONE undo step with fresh ids all the way down —
  /// what arrives may be a copy of something already on the page. Offset so a
  /// paste over its own original is visible.
  void addElements(List<Map<String, dynamic>> incoming, {double offset = 24}) {
    if (incoming.isEmpty) return;
    final copies = [
      for (final el in incoming)
        {..._clone(_normalizeElement(el)), 'x': orNum(el['x'], 0) + offset, 'y': orNum(el['y'], 0) + offset},
    ];
    commit();
    _elements = [..._elements, ...copies];
    _selectedIds = [for (final c in copies) c['id'] as String];
    notifyListeners();
  }

  // ── Clipboard (elementClipboard.js) ────────────────────────────────────────
  // Elements go on the SYSTEM clipboard as JSON behind a versioned key, so the
  // most recent copy wins whatever it was and a copy survives into another
  // design. The in-memory mirror only keeps Paste working if the system
  // clipboard refuses or is replaced by plain text we can't use.

  static const _clipboardKey = 'creative-klux/design-elements@1';
  static List<Map<String, dynamic>>? _clipboardMirror;

  bool get canPaste => _clipboardMirror != null;

  String copySelection() {
    final els = [for (final el in selectedElements) Map<String, dynamic>.from(el)];
    _clipboardMirror = els;
    notifyListeners();
    return jsonEncode({_clipboardKey: els});
  }

  /// Elements out of clipboard text, or null when it's anything else.
  static List<Map<String, dynamic>>? decodeClipboard(String? text) {
    if (text == null || !text.contains(_clipboardKey)) return null;
    try {
      final list = (jsonDecode(text) as Map)[_clipboardKey];
      return list is List && list.isNotEmpty ? [for (final e in list) Map<String, dynamic>.from(e as Map)] : null;
    } catch (_) {
      return null;
    }
  }

  /// Paste [systemText] if it holds elements, else the in-memory mirror.
  bool paste(String? systemText) {
    final els = decodeClipboard(systemText) ?? _clipboardMirror;
    if (els == null) return false;
    addElements(els);
    return true;
  }

  /// Unfold a group back into its members, at the group's depth.
  void ungroup(String id) {
    final idx = _elements.indexWhere((e) => e['id'] == id);
    if (idx == -1 || _elements[idx]['type'] != 'group' || truthy(_elements[idx]['locked'])) return;
    final members = flattenGroups([_elements[idx]]).map((m) => {...m}..remove(clipKey)).toList();
    if (members.isEmpty) return;
    commit();
    _elements = [..._elements]..replaceRange(idx, idx + 1, members);
    _selectedIds = [for (final m in members) m['id'] as String];
    notifyListeners();
  }

  /// Resize the canvas AND refit every element proportionally, as one step.
  /// Images scale uniformly about their moved centre, so pictures never
  /// stretch; the background goes white so any new margin isn't the old colour.
  void resizeCanvas(double width, double height) {
    if (width <= 0 || height <= 0) return;
    commit();
    final sx = width / canvasWidth, sy = height / canvasHeight;
    final uni = math.sqrt(sx * sy);
    if (sx != 1 || sy != 1) {
      _elements = [for (final el in _elements) _refit(el, sx, sy, uni)];
    }
    _canvas = {..._canvas, 'width': width, 'height': height, 'background': '#ffffff'};
    notifyListeners();
  }

  static Map<String, dynamic> _refit(Map<String, dynamic> el, double sx, double sy, double uni) {
    final next = {...el};
    final x = orNum(el['x'], 0), y = orNum(el['y'], 0), w = orNum(el['width'], 0), h = orNum(el['height'], 0);
    if (el['type'] == 'image' || el['type'] == 'video') {
      final cx = x + w / 2, cy = y + h / 2;
      next['width'] = w * uni;
      next['height'] = h * uni;
      next['x'] = cx * sx - w * uni / 2;
      next['y'] = cy * sy - h * uni / 2;
    } else {
      next['x'] = x * sx;
      next['y'] = y * sy;
      next['width'] = w * sx;
      next['height'] = h * sy;
    }
    next.addAll(scaledProps(el, uni, heightFactor: sy));
    next.addAll(scaledClip(el, sx, sy));
    if (el['type'] == 'group') next['children'] = scaleChildren(el['children'], sx, sy);
    return next;
  }

  /// Notes ride in the canvas JSON (web: EditorNotes); editing them is an
  /// unsaved change like any other, but not an undo step.
  void setNotes(String value) {
    if (value == notes) return;
    notes = value;
    _dirty = true;
    notifyListeners();
  }

  void rename(String value) {
    _name = value.trim().isEmpty ? 'Untitled design' : value.trim();
    notifyListeners();
  }

  void markSaved() {
    _dirty = false;
    _savedName = _name;
    notifyListeners();
  }

  /// The JSON the web stores in the `canvas` column.
  String toCanvasJson() => jsonEncode({'canvas': _canvas, 'elements': _elements, 'notes': notes});
}
