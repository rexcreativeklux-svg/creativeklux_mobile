import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/design/css_color.dart';
import '../../core/design/design_renderer.dart';
import '../../core/design/js_values.dart';
import '../../core/design/resize_element.dart';
import '../../core/design/shapes.dart';
import '../../core/theme/app_colors.dart';
import 'design_editor_controller.dart';
import 'editor_animate.dart';

/// The artboard: paints the design live and owns every pointer gesture on it.
/// Port of the web editor's stage (DesignEditor.jsx), `EditorElement`'s drag
/// and `SelectionChrome`'s handles.
///
/// Gestures (touch-first — there's no Shift or mouse wheel on a phone):
///   · drag an element → move it (the whole selection if it's part of one),
///     snapping to the page's centre lines;
///   · corner handle → scale, aspect locked; edge handle → crop;
///   · the round handle above the box → rotate (snaps near every 45°);
///   · tap a selected text element → edit it in place;
///   · tap empty space → clear the selection; drag it → pan the view;
///   · two fingers anywhere → pinch-zoom the view.
///
/// Everything is done with one raw [Listener] rather than nested gesture
/// detectors: handles, elements and the view all compete for the same
/// pointers, and deciding that by our own hit test is the only arrangement
/// that never drops a drag to the wrong winner.
class DesignStage extends StatefulWidget {
  const DesignStage({
    super.key,
    required this.controller,
    required this.scene,
    required this.editingId,
    required this.onStartEdit,
    required this.onCommitText,
    this.drawTool,
    this.onTapAgain,
  });

  /// A second tap on a selected non-text element, with the point in the
  /// element's own unrotated box.
  final void Function(String id, Offset local)? onTapAgain;

  /// While set, one finger draws (or erases) instead of selecting; two still
  /// zoom. The web's Tools → Draw mode (DesignEditor.jsx onDraw*).
  final DrawTool? drawTool;

  final DesignEditorController controller;
  final DesignScene scene;

  /// The text element being typed into, or null.
  final String? editingId;
  final ValueChanged<String> onStartEdit;

  /// Called with the new text when an inline edit finishes.
  final void Function(String id, String text) onCommitText;

  @override
  State<DesignStage> createState() => DesignStageState();
}

/// A freehand tool: 'pen' | 'marker' | 'highlighter' | 'eraser'.
class DrawTool {
  const DrawTool({required this.type, required this.color, required this.size, required this.opacity});
  final String type;
  final String color;
  final double size;
  final double opacity;
}

/// A finished stroke as a `draw` element — port of `strokeToElement`
/// (`(lib)/design/drawUtils.js`): the points normalised into the element's own
/// box, padded by the stroke width so the line isn't clipped at its edges.
Map<String, dynamic> strokeToElement(List<Offset> points, DrawTool tool) {
  final pad = tool.size;
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final p in points) {
    minX = math.min(minX, p.dx);
    minY = math.min(minY, p.dy);
    maxX = math.max(maxX, p.dx);
    maxY = math.max(maxY, p.dy);
  }
  minX -= pad;
  minY -= pad;
  final w = math.max(maxX + pad - minX, 1.0), h = math.max(maxY + pad - minY, 1.0);
  return {
    'type': 'draw',
    'x': minX,
    'y': minY,
    'width': w,
    'height': h,
    'vbW': w,
    'vbH': h,
    'points': [
      for (final p in points) {'x': p.dx - minX, 'y': p.dy - minY},
    ],
    'stroke': tool.color,
    'strokeWidth': tool.size,
    'opacity': tool.opacity,
    'cap': tool.type == 'marker' ? 'butt' : 'round',
    if (tool.type == 'highlighter') 'blend': 'multiply',
  };
}

enum _Grab { none, move, corner, edge, rotate, pan, pinch, draw, lineEnd, bend }

class DesignStageState extends State<DesignStage> with SingleTickerProviderStateMixin {
  // Animation preview: seconds since Play, or -1 when not playing.
  Ticker? _animTicker;
  double _animElapsed = -1;

  /// Play every element's animation once as a preview (AnimatePanel onPlay).
  void playAnimations() {
    final total = c.elements.fold<double>(0, (m, el) => math.max(m, animationLength(el['animation'])));
    _animTicker?.dispose();
    if (total <= 0) return;
    _animTicker = createTicker((d) {
      final t = d.inMicroseconds / 1e6;
      if (t > total + 0.05) {
        _animTicker?.stop();
        setState(() => _animElapsed = -1);
      } else {
        setState(() => _animElapsed = t);
      }
    })..start();
  }

  static const _handleHit = 22.0; // touch radius around a handle, screen px
  static const _rotateGap = 30.0; // rotate handle distance above the box
  static const _slop = 5.0;
  static const _snapPx = 7.0;

  // View: zoom is relative to "fit the page"; pan is in screen px.
  double _zoom = 1;
  Offset _pan = Offset.zero;
  Size _viewport = Size.zero;

  // Gesture state.
  final Map<int, Offset> _pointers = {};
  _Grab _grab = _Grab.none;
  String? _handle;
  Offset _downAt = Offset.zero;
  bool _moved = false;
  bool _committed = false;
  String? _hitId;
  bool _hitWasSelected = false;
  Map<String, Map<String, dynamic>> _snaps = {};
  Offset _rotateCenter = Offset.zero;
  double _rotateA0 = 0;
  // Pinch.
  double _pinchD0 = 1;
  double _pinchZoom0 = 1;
  Offset _pinchFocal0 = Offset.zero;
  Offset _pinchPan0 = Offset.zero;
  // Centre-line guides shown while snapped.
  bool _guideV = false, _guideH = false;
  // Edge hold-to-stretch.
  static const _holdDelay = Duration(milliseconds: 400);
  Timer? _holdTimer;
  bool _stretch = false;
  // The stroke being drawn, in canvas units.
  final List<Offset> _stroke = [];
  // The end that stays put while a line endpoint is dragged.
  Offset _lineFixed = Offset.zero;

  final _text = TextEditingController();
  final _textFocus = FocusNode();
  String? _editingShown;

  DesignEditorController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _textFocus.addListener(() {
      if (!_textFocus.hasFocus) _finishEdit();
    });
  }

  @override
  void didUpdateWidget(DesignStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.editingId;
    if (id != null && id != _editingShown) {
      final el = c.byId(id);
      _text.text = '${el?['content'] ?? el?['text'] ?? ''}';
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
      _editingShown = id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _textFocus.requestFocus());
    } else if (id == null) {
      _editingShown = null;
    }
  }

  @override
  void dispose() {
    _animTicker?.dispose();
    _holdTimer?.cancel();
    _text.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  void _finishEdit() {
    final id = _editingShown;
    if (id == null) return;
    _editingShown = null;
    widget.onCommitText(id, _text.text);
  }

  /// Reset zoom and pan to "whole page in view".
  void fit() => setState(() {
    _zoom = 1;
    _pan = Offset.zero;
  });

  // ── Geometry ───────────────────────────────────────────────────────────────

  double get _fitScale {
    if (_viewport.isEmpty) return 1;
    return math.min((_viewport.width - 32) / c.canvasWidth, (_viewport.height - 32) / c.canvasHeight).clamp(0.01, 50);
  }

  double get _scale => _fitScale * _zoom;

  Offset get _origin =>
      Offset(_viewport.width / 2, _viewport.height / 2) - Offset(c.canvasWidth, c.canvasHeight) * _scale / 2 + _pan;

  Offset _toCanvas(Offset screen) => (screen - _origin) / _scale;
  Offset _toScreen(Offset canvas) => _origin + canvas * _scale;

  static Rect _box(Map<String, dynamic> el) =>
      Rect.fromLTWH(orNum(el['x'], 0), orNum(el['y'], 0), orNum(el['width'], 0), orNum(el['height'], 0));

  static double _rad(Map<String, dynamic> el) => orNum(el['rotation'], 0) * math.pi / 180;

  /// A point of [el]'s box (local, unrotated canvas coords) rotated about its centre.
  static Offset _rotated(Map<String, dynamic> el, Offset local) {
    final box = _box(el);
    final a = _rad(el);
    final d = local - box.center;
    return box.center + Offset(d.dx * math.cos(a) - d.dy * math.sin(a), d.dx * math.sin(a) + d.dy * math.cos(a));
  }

  static bool _contains(Map<String, dynamic> el, Offset p, double tolerance) {
    final box = _box(el).inflate(tolerance);
    final a = -_rad(el);
    final d = p - box.center;
    final local = box.center + Offset(d.dx * math.cos(a) - d.dy * math.sin(a), d.dx * math.sin(a) + d.dy * math.cos(a));
    return box.contains(local);
  }

  /// Top-most visible element under a canvas point.
  String? _hitElement(Offset p) {
    for (final el in c.elements.reversed) {
      if (truthy(el['hidden'])) continue;
      if (_contains(el, p, 4 / _scale)) return el['id'] as String;
    }
    return null;
  }

  /// Clicking INTO a group: while a group (or one of its members) is selected,
  /// a press on a member picks that member, which then moves, resizes and
  /// edits like any element while staying inside its group. One level deep,
  /// as on the web.
  String? _memberUnder(Offset p) {
    final sel = c.selectedElements;
    if (sel.length != 1) return null;
    final s = sel.first;
    final group = s['type'] == 'group' ? s : (s['groupId'] != null ? c.byId('${s['groupId']}') : null);
    if (group == null) return null;
    for (final ch in (group['children'] as List? ?? const []).reversed) {
      if (ch is! Map || truthy(ch['hidden'])) continue;
      final view = DesignEditorController.childView(group, Map<String, dynamic>.from(ch));
      if (_contains(view, p, 4 / _scale)) return ch['id'] as String;
    }
    return null;
  }

  /// "Straight" lines run across a 12-unit-high viewBox, so rotation + length
  /// describes them fully — they get endpoint handles instead of a box
  /// (`isStraightLine` in shapes.js).
  static bool isStraightLine(Map<String, dynamic> el) {
    final def = el['type'] == 'shape' ? shapes[el['shape']] : null;
    return def != null && def.kind == 'stroke' && def.viewBox[1] <= 12;
  }

  /// A straight line's two ends in canvas space (`lineEndpoints`).
  static (Offset, Offset) lineEnds(Map<String, dynamic> el) {
    final b = _box(el);
    final r = _rad(el);
    final h = Offset(math.cos(r), math.sin(r)) * (b.width / 2);
    return (b.center - h, b.center + h);
  }

  /// The bend handle: the chord's midpoint pushed out along its perpendicular
  /// by `bend` (canvas units, signed) — `bendPoint` in DesignEditor.jsx.
  static (Offset point, Offset mid, Offset perp) bendHandle(Map<String, dynamic> el) {
    final (p1, p2) = lineEnds(el);
    final mid = (p1 + p2) / 2;
    final d = p2 - p1;
    final len = d.distance == 0 ? 1.0 : d.distance;
    final perp = Offset(d.dy / len, -d.dx / len);
    return (mid + perp * orNum(el['bend'], 0), mid, perp);
  }

  /// Screen positions of the selected element's handles.
  Map<String, Offset> _handles(Map<String, dynamic> el) {
    if (isStraightLine(el)) {
      final (p1, p2) = lineEnds(el);
      return {
        'p1': _toScreen(p1),
        'p2': _toScreen(p2),
        if (shapes[el['shape']]?.bendable ?? false) 'bend': _toScreen(bendHandle(el).$1),
      };
    }
    final b = _box(el);
    final screenW = b.width * _scale, screenH = b.height * _scale;
    // The box's own "up", so the rotate grip turns with the element.
    final up = Offset(math.sin(_rad(el)), -math.cos(_rad(el)));
    final top = _toScreen(_rotated(el, b.topCenter));
    return {
      'topLeft': _toScreen(_rotated(el, b.topLeft)),
      'topRight': _toScreen(_rotated(el, b.topRight)),
      'bottomRight': _toScreen(_rotated(el, b.bottomRight)),
      'bottomLeft': _toScreen(_rotated(el, b.bottomLeft)),
      // Edge grips only where there's room for them between the corners.
      if (screenW > 56) 'top': top,
      if (screenW > 56) 'bottom': _toScreen(_rotated(el, b.bottomCenter)),
      if (screenH > 56) 'left': _toScreen(_rotated(el, b.centerLeft)),
      if (screenH > 56) 'right': _toScreen(_rotated(el, b.centerRight)),
      'rotate': top + up * _rotateGap,
    };
  }

  String? _hitHandle(Offset screen) {
    final sel = c.selectedElements;
    if (sel.length != 1 || truthy(sel.first['locked']) || widget.editingId != null) return null;
    String? best;
    var bestD = _handleHit;
    _handles(sel.first).forEach((name, pos) {
      final d = (pos - screen).distance;
      if (d < bestD) {
        bestD = d;
        best = name;
      }
    });
    return best;
  }

  // ── Pointers ───────────────────────────────────────────────────────────────

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      _startPinch();
      return;
    }
    if (_pointers.length > 2) return;
    if (widget.editingId != null) {
      // A tap outside the text being edited ends the edit.
      _textFocus.unfocus();
    }

    _downAt = e.localPosition;
    _moved = false;
    _committed = false;
    _hitId = null;

    if (widget.drawTool != null) {
      _grab = _Grab.draw;
      final p = _toCanvas(e.localPosition);
      if (widget.drawTool!.type == 'eraser') {
        _eraseAt(p);
      } else {
        setState(
          () => _stroke
            ..clear()
            ..add(p),
        );
      }
      return;
    }

    final handle = _hitHandle(e.localPosition);
    if (handle != null) {
      final el = c.selectedElements.first;
      _snaps = {el['id'] as String: Map<String, dynamic>.from(el)};
      _handle = handle;
      if (handle == 'p1' || handle == 'p2') {
        // Drag one end; the other stays put.
        final (p1, p2) = lineEnds(el);
        _lineFixed = handle == 'p1' ? p2 : p1;
        _grab = _Grab.lineEnd;
      } else if (handle == 'bend') {
        _grab = _Grab.bend;
      } else if (handle == 'rotate') {
        _grab = _Grab.rotate;
        _rotateCenter = _toScreen(_box(el).center);
        final v = e.localPosition - _rotateCenter;
        _rotateA0 = math.atan2(v.dy, v.dx);
      } else {
        _grab = corners.contains(handle) ? _Grab.corner : _Grab.edge;
        // Press and HOLD an edge to stretch instead of crop — the phone's
        // stand-in for the web's Shift+drag. The hold has to come before any
        // movement, so a normal drag still crops straight away.
        if (_grab == _Grab.edge) {
          _holdTimer = Timer(_holdDelay, () {
            if (_grab != _Grab.edge || _moved) return;
            HapticFeedback.mediumImpact();
            setState(() => _stretch = true);
          });
        }
      }
      return;
    }

    final p = _toCanvas(e.localPosition);
    final hit = _memberUnder(p) ?? _hitElement(p);
    if (hit != null) {
      _hitId = hit;
      _hitWasSelected = c.selectedIds.contains(hit);
      final before = [...c.selectedIds];
      // Pressing an element outside the selection makes it the selection;
      // pressing one inside keeps the group so the whole selection moves.
      if (!_hitWasSelected) c.select(hit);
      _snaps = {
        for (final el in c.selectedElements)
          if (!truthy(el['locked'])) el['id'] as String: Map<String, dynamic>.from(el),
      };
      _grab = _Grab.move;
      // Long-press adds the element to the selection (or takes it out) — the
      // phone's Shift-click. Only before any movement; the press is then spent.
      _holdTimer = Timer(_holdDelay, () {
        if (_grab != _Grab.move || _moved) return;
        HapticFeedback.mediumImpact();
        c.setSelection(
          before.contains(hit) ? (before.toList()..remove(hit)) : [...before.where((id) => id != hit), hit],
        );
        _grab = _Grab.none;
        _snaps = {};
      });
    } else {
      _grab = _Grab.pan;
      _pinchPan0 = _pan;
    }
  }

  /// The eraser removes whole strokes: any draw element whose box the finger
  /// passes over (web: eraseAt).
  void _eraseAt(Offset p) {
    final hit = c.elements.reversed
        .where((el) => el['type'] == 'draw' && _box(el).contains(p))
        .map((el) => el['id'] as String)
        .firstOrNull;
    if (hit != null) c.removeElements([hit]);
  }

  void _startPinch() {
    // A second finger turns whatever was happening into a zoom of the view.
    _stroke.clear();
    _grab = _Grab.pinch;
    _guideV = _guideH = false;
    final pts = _pointers.values.toList();
    _pinchD0 = math.max(1, (pts[0] - pts[1]).distance);
    _pinchZoom0 = _zoom;
    _pinchFocal0 = (pts[0] + pts[1]) / 2;
    _pinchPan0 = _pan;
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    final delta = e.localPosition - _downAt;
    if (!_moved && delta.distance < _slop && _grab != _Grab.pinch && _grab != _Grab.draw) return;
    _moved = true;
    _holdTimer?.cancel();

    switch (_grab) {
      case _Grab.draw:
        final p = _toCanvas(e.localPosition);
        if (widget.drawTool?.type == 'eraser') {
          _eraseAt(p);
        } else {
          setState(() => _stroke.add(p));
        }
      case _Grab.pinch:
        if (_pointers.length < 2) return;
        final pts = _pointers.values.toList();
        final d = math.max(1.0, (pts[0] - pts[1]).distance);
        final focal = (pts[0] + pts[1]) / 2;
        final zoom = (_pinchZoom0 * d / _pinchD0).clamp(0.25, 8.0);
        // Keep the canvas point under the fingers' midpoint where it was.
        final s0 = _fitScale * _pinchZoom0, s1 = _fitScale * zoom;
        final center = Offset(_viewport.width / 2, _viewport.height / 2);
        final canvasPt = (_pinchFocal0 - (center + _pinchPan0)) / s0;
        setState(() {
          _zoom = zoom;
          _pan = focal - center - canvasPt * s1;
        });
      case _Grab.pan:
        setState(() => _pan = _pinchPan0 + delta);
      case _Grab.move:
        _dragMove(delta / _scale);
      case _Grab.corner || _Grab.edge:
        _dragResize(delta / _scale);
      case _Grab.rotate:
        _dragRotate(e.localPosition);
      case _Grab.lineEnd:
        final snap = _snaps.values.first;
        final p = _toCanvas(e.localPosition), f = _lineFixed;
        final mid = (f + p) / 2;
        final len = math.max((p - f).distance, 1.0);
        final h = orNum(snap['height'], 12);
        _beginGesture();
        c.updateElement(snap['id'] as String, {
          'x': mid.dx - len / 2,
          'y': mid.dy - h / 2,
          'width': len,
          'rotation': math.atan2(p.dy - f.dy, p.dx - f.dx) * 180 / math.pi,
        }, record: false);
      case _Grab.bend:
        final snap = _snaps.values.first;
        final (_, mid, perp) = bendHandle(snap);
        final p = _toCanvas(e.localPosition);
        _beginGesture();
        c.updateElement(snap['id'] as String, {
          'bend': (p.dx - mid.dx) * perp.dx + (p.dy - mid.dy) * perp.dy,
        }, record: false);
      case _Grab.none:
        break;
    }
  }

  void _beginGesture() {
    if (_committed) return;
    _committed = true;
    c.commit();
  }

  void _dragMove(Offset d) {
    if (_snaps.isEmpty) return;
    _beginGesture();
    // Snap the moving box's centre to the page's centre lines.
    var dx = d.dx, dy = d.dy;
    var bounds = Rect.zero;
    for (final s in _snaps.values) {
      final r = _box(s).shift(d);
      bounds = bounds == Rect.zero ? r : bounds.expandToInclude(r);
    }
    final tol = _snapPx / _scale;
    final offX = c.canvasWidth / 2 - bounds.center.dx;
    final offY = c.canvasHeight / 2 - bounds.center.dy;
    _guideV = offX.abs() < tol;
    _guideH = offY.abs() < tol;
    if (_guideV) dx += offX;
    if (_guideH) dy += offY;
    c.updateElements({
      for (final MapEntry(:key, :value) in _snaps.entries)
        key: {'x': orNum(value['x'], 0) + dx, 'y': orNum(value['y'], 0) + dy},
    }, record: false);
  }

  void _dragResize(Offset d) {
    final snap = _snaps.values.firstOrNull;
    if (snap == null) return;
    _beginGesture();
    // The pointer moves in canvas space; the box is reasoned about in its own.
    final a = -_rad(snap);
    final local = Offset(d.dx * math.cos(a) - d.dy * math.sin(a), d.dx * math.sin(a) + d.dy * math.cos(a));
    final patch = _grab == _Grab.corner
        ? scaleByCorner(snap, _handle!, local.dx, local.dy)
        : _stretch
        ? stretchByEdge(snap, _handle!, local.dx, local.dy)
        : cropByEdge(snap, _handle!, local.dx, local.dy);
    if (patch.isNotEmpty) c.updateElement(snap['id'] as String, patch, record: false);
  }

  void _dragRotate(Offset screen) {
    final snap = _snaps.values.firstOrNull;
    if (snap == null) return;
    _beginGesture();
    final v = screen - _rotateCenter;
    var deg = orNum(snap['rotation'], 0) + (math.atan2(v.dy, v.dx) - _rotateA0) * 180 / math.pi;
    deg = ((deg % 360) + 360) % 360;
    // No Shift key on a phone: snap when close to a multiple of 45°.
    final nearest = (deg / 45).round() * 45.0;
    if ((deg - nearest).abs() < 4) deg = nearest % 360;
    c.updateElement(snap['id'] as String, {'rotation': deg}, record: false);
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    _holdTimer?.cancel();
    if (_stretch) setState(() => _stretch = false);
    if (_grab == _Grab.draw) {
      final tool = widget.drawTool;
      if (tool != null && tool.type != 'eraser' && _stroke.isNotEmpty) {
        c.addElement(strokeToElement(_stroke, tool));
        // No selection box mid-drawing — it would sit over the next stroke.
        c.select(null);
      }
      setState(_stroke.clear);
      _grab = _Grab.none;
      return;
    }
    if (_grab == _Grab.pinch) {
      if (_pointers.isEmpty) _grab = _Grab.none;
      return;
    }
    if (!_moved) {
      if (_grab == _Grab.pan) {
        c.select(null);
      } else if (_grab == _Grab.move && _hitId != null && _hitWasSelected) {
        // A second tap on a selected text element edits it.
        final el = c.byId(_hitId!);
        if (el != null && el['type'] == 'text' && !truthy(el['locked'])) {
          widget.onStartEdit(_hitId!);
        } else if (el != null && !truthy(el['locked'])) {
          // Other elements get the tap in their own unrotated box (table cell,
          // grid cell…) — the screen decides what it opens.
          final box = _box(el);
          final a = -_rad(el);
          final d = _toCanvas(_downAt) - box.center;
          final local =
              Offset(d.dx * math.cos(a) - d.dy * math.sin(a), d.dx * math.sin(a) + d.dy * math.cos(a)) +
              Offset(box.width / 2, box.height / 2);
          widget.onTapAgain?.call(_hitId!, local);
        }
      }
    }
    if (_guideV || _guideH) setState(() => _guideV = _guideH = false);
    _grab = _Grab.none;
    _snaps = {};
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        _viewport = box.biggest;
        return ClipRect(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _up,
            onPointerSignal: (s) {
              // Mouse wheel / trackpad zoom on desktop and web.
              if (s is PointerScrollEvent) {
                setState(() => _zoom = (_zoom * (s.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(0.25, 8.0));
              }
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _StagePainter(
                      state: this,
                      repaint: Listenable.merge([c, widget.scene]),
                      pasteboard: colors.gray100,
                      accent: AppColors.blue500,
                    ),
                  ),
                ),
                if (widget.editingId != null) _textEditor(widget.editingId!),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The inline text editor, laid over the element it replaces (which the
  /// painter skips while it's open) and styled to match it.
  Widget _textEditor(String id) {
    final el = c.byId(id);
    if (el == null) return const SizedBox.shrink();
    final b = _box(el);
    final topLeft = _toScreen(b.topLeft);
    final w = b.width * _scale, h = b.height * _scale;
    final size = orNum(el['fontSize'], 16) * _scale;
    final align = switch (el['textAlign']) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    final color = parseCssColor(el['fill']) ?? parseCssColor(el['color']) ?? const Color(0xFF111111);
    final style = widget.scene
        .textStyleFor(el)
        .copyWith(
          fontSize: size,
          color: color,
          letterSpacing: orNum(el['letterSpacing'], 0) * _scale,
          height: orNum(el['lineHeight'], 1.3),
        );
    final top = truthy(el['sticky']) || el['verticalAlign'] == 'top';
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: math.max(w, 40),
      height: math.max(h, size * 1.5),
      child: Transform.rotate(
        angle: _rad(el),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: AppColors.blue500, width: 1.5)),
          child: Align(
            alignment: top ? Alignment.topCenter : Alignment.center,
            child: TextField(
              controller: _text,
              focusNode: _textFocus,
              maxLines: null,
              textAlign: align,
              style: style,
              cursorColor: AppColors.blue500,
              decoration: InputDecoration.collapsed(hintText: '', hintStyle: style),
            ),
          ),
        ),
      ),
    );
  }
}

class _StagePainter extends CustomPainter {
  _StagePainter({required this.state, required Listenable repaint, required this.pasteboard, required this.accent})
    : super(repaint: repaint);

  final DesignStageState state;
  final Color pasteboard;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = state.c;
    final scale = state._scale;
    final origin = state._origin;
    canvas.drawRect(Offset.zero & size, Paint()..color = pasteboard);

    // Artboard shadow, then the design itself in canvas units.
    final page = origin & Size(c.canvasWidth * scale, c.canvasHeight * scale);
    canvas.drawRect(
      page.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0x22000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    if (state._animElapsed < 0) {
      state.widget.scene.paint(
        canvas,
        c.canvas,
        c.elements,
        skip: {if (state.widget.editingId != null) state.widget.editingId!},
      );
    } else {
      _paintAnimated(canvas, state._animElapsed);
    }
    // The stroke being drawn, painted as the draw element it will become.
    final tool = state.widget.drawTool;
    if (tool != null && state._stroke.isNotEmpty) {
      final pts = state._stroke;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      if (pts.length == 1) path.lineTo(pts.first.dx + 0.01, pts.first.dy);
      final color = parseCssColor(tool.color) ?? const Color(0xFF111827);
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: color.a * tool.opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = tool.size
          ..strokeCap = tool.type == 'marker' ? StrokeCap.butt : StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = tool.type == 'highlighter' ? BlendMode.multiply : BlendMode.srcOver,
      );
    }
    canvas.restore();

    // Centre guides while a move is snapped to them.
    final guide = Paint()
      ..color = const Color(0xFFEC4899)
      ..strokeWidth = 1;
    if (state._guideV) canvas.drawLine(Offset(page.center.dx, page.top), Offset(page.center.dx, page.bottom), guide);
    if (state._guideH) canvas.drawLine(Offset(page.left, page.center.dy), Offset(page.right, page.center.dy), guide);

    // Selection chrome, in screen space so it stays the same size at any zoom
    // and isn't clipped by the artboard edge.
    final sel = c.selectedElements;
    if (sel.isEmpty || state.widget.editingId != null || state._animElapsed >= 0) return;
    final outline = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final el in sel) {
      // Straight lines are edited by their ends; a box would fight them.
      if (sel.length == 1 && DesignStageState.isStraightLine(el)) continue;
      final b = DesignStageState._box(el);
      final pts = [
        b.topLeft,
        b.topRight,
        b.bottomRight,
        b.bottomLeft,
      ].map((p) => state._toScreen(DesignStageState._rotated(el, p))).toList();
      canvas.drawPath(Path()..addPolygon(pts, true), outline);
    }
    if (sel.length != 1) return;
    final el = sel.first;
    if (truthy(el['locked'])) {
      // A locked element gets no grips — just a small lock badge.
      final p = state._toScreen(DesignStageState._rotated(el, DesignStageState._box(el).topRight));
      canvas.drawCircle(p, 9, Paint()..color = accent);
      final icon = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.lock.codePoint),
          style: TextStyle(fontFamily: Icons.lock.fontFamily, fontSize: 11, color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      icon.paint(canvas, p - Offset(icon.width / 2, icon.height / 2));
      return;
    }
    final handles = state._handles(el);
    final fill = Paint()..color = Colors.white;
    final ring = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final shadow = Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    if (DesignStageState.isStraightLine(el)) {
      for (final MapEntry(key: name, value: p) in handles.entries) {
        canvas.drawCircle(p + const Offset(0, 1), 8, shadow);
        canvas.drawCircle(p, 8, name == 'bend' ? (Paint()..color = accent) : fill);
        canvas.drawCircle(p, 8, ring);
      }
      return;
    }
    final top = handles['top'] ?? state._toScreen(DesignStageState._rotated(el, DesignStageState._box(el).topCenter));
    canvas.drawLine(top, handles['rotate']!, ring);
    handles.forEach((name, p) {
      if (name == 'rotate') {
        canvas.drawCircle(p + const Offset(0, 1), 11, shadow);
        canvas.drawCircle(p, 11, fill);
        canvas.drawCircle(p, 11, ring);
        final icon = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(Icons.rotate_right.codePoint),
            style: TextStyle(fontFamily: Icons.rotate_right.fontFamily, fontSize: 14, color: accent),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        icon.paint(canvas, p - Offset(icon.width / 2, icon.height / 2));
      } else if (corners.contains(name)) {
        canvas.drawCircle(p + const Offset(0, 1), 7, shadow);
        canvas.drawCircle(p, 7, fill);
        canvas.drawCircle(p, 7, ring);
      } else {
        // Edge grips are pills along their edge.
        final horizontal = name == 'top' || name == 'bottom';
        final a = DesignStageState._rad(el);
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(a);
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: horizontal ? 22 : 7, height: horizontal ? 7 : 22),
          const Radius.circular(4),
        );
        // Filled in the accent while held into stretch mode.
        final stretching = state._stretch && state._handle == name;
        canvas.drawRRect(r.shift(const Offset(0, 1)), shadow);
        canvas.drawRRect(r, stretching ? (Paint()..color = accent) : fill);
        canvas.drawRRect(r, ring);
        canvas.restore();
      }
    });
  }

  /// The animation preview: the page, then each element drawn on its own with
  /// that moment's frame applied about its centre (the CSS keyframes'
  /// transform-origin), and wipe/block as a growing clip.
  void _paintAnimated(Canvas canvas, double t) {
    final c = state.c;
    final scene = state.widget.scene;
    final w = c.canvasWidth, h = c.canvasHeight;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, h));
    scene.paint(canvas, c.canvas, const []);
    for (final el in c.elements) {
      final f = animationFrame(el['animation'], t);
      final box = DesignStageState._box(el);
      canvas.save();
      canvas.translate(f.dx, f.dy);
      if (f.revealX < 1 || f.revealY < 1) {
        canvas.clipRect(
          Rect.fromLTWH(box.left, box.top, box.width * f.revealX.clamp(0, 1), box.height * f.revealY.clamp(0, 1)),
        );
      }
      canvas.translate(box.center.dx, box.center.dy);
      canvas.rotate(f.rotation * math.pi / 180);
      canvas.scale(f.scale);
      canvas.translate(-box.center.dx, -box.center.dy);
      final faded = f.opacity < 1;
      if (faded) canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, f.opacity.clamp(0, 1)));
      scene.paint(canvas, c.canvas, [el], background: false, clip: false);
      if (faded) canvas.restore();
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => true;
}
