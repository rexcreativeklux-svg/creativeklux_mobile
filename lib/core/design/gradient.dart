import 'dart:math' as math;
import 'dart:ui';

import 'css_color.dart';

/// Port of the web's `(lib)/design/gradient.js`.
///
/// A gradient is stored exactly as CSS writes it — `linear-gradient(135deg,
/// #f0a 0%, #05f 100%)` — in the same `fill` property that otherwise holds a
/// plain colour. The web exporter turns that into a CanvasGradient; here it
/// becomes a [Shader] laid across a box, with the same rules (CSS angle
/// convention, corner-to-corner gradient line, evenly spread unpositioned stops).

/// Is this value a gradient rather than a plain colour?
bool isGradient(Object? value) =>
    value is String && RegExp(r'^\s*(linear|radial)-gradient\s*\(', caseSensitive: false).hasMatch(value);

class GradientStop {
  const GradientStop(this.color, this.offset);
  final String color;
  final double offset;
}

class GradientSpec {
  const GradientSpec(this.kind, this.angle, this.stops);
  final String kind; // 'linear' | 'radial'
  final double angle;
  final List<GradientStop> stops;
}

/// Split on the commas BETWEEN stops — a plain split would tear
/// `rgba(0, 0, 0, .5)` into four arguments.
List<String> _splitArgs(String body) {
  final parts = <String>[];
  var depth = 0;
  final current = StringBuffer();
  for (final char in body.split('')) {
    if (char == '(') depth++;
    if (char == ')') depth--;
    if (char == ',' && depth == 0) {
      parts.add(current.toString().trim());
      current.clear();
    } else {
      current.write(char);
    }
  }
  if (current.toString().trim().isNotEmpty) parts.add(current.toString().trim());
  return parts;
}

const _angleKeywords = {
  'to top': 0.0,
  'to right': 90.0,
  'to bottom': 180.0,
  'to left': 270.0,
  'to top right': 45.0,
  'to right top': 45.0,
  'to bottom right': 135.0,
  'to right bottom': 135.0,
  'to bottom left': 225.0,
  'to left bottom': 225.0,
  'to top left': 315.0,
  'to left top': 315.0,
};

double? _angleOf(String token) {
  final text = token.trim().toLowerCase();
  final deg = RegExp(r'^(-?[\d.]+)deg$').firstMatch(text);
  if (deg != null) return double.tryParse(deg.group(1)!);
  return _angleKeywords[text];
}

/// A gradient string → spec, or null when it isn't one we can read.
GradientSpec? parseGradient(Object? value) {
  if (!isGradient(value)) return null;
  final v = value as String;
  final open = v.indexOf('(');
  final kind = v.substring(0, open).trim().toLowerCase().startsWith('radial') ? 'radial' : 'linear';
  final close = v.lastIndexOf(')');
  if (close <= open) return null;
  final args = _splitArgs(v.substring(open + 1, close));
  if (args.isEmpty) return null;

  // The angle is optional. CSS defaults to `to bottom` without one.
  final leading = _angleOf(args[0]);
  final angle = leading ?? 180;
  final tokens = leading == null ? args : args.sublist(1);

  final parsed = <(String, double?)>[];
  for (final t in tokens) {
    final m = RegExp(r'^(.*?)\s+([\d.]+)%$').firstMatch(t);
    final stop = m != null ? (m.group(1)!.trim(), double.tryParse(m.group(2)!)! / 100) : (t.trim(), null);
    if (stop.$1.isNotEmpty) parsed.add(stop);
  }
  if (parsed.length < 2) return null;

  // Offsets are spread over EVERY token, as the web does — a radial gradient's
  // leading `circle` counts as a slot there and is only dropped when its colour
  // fails to parse, so the remaining stops land where the web puts them.
  final stops = <GradientStop>[];
  for (var i = 0; i < parsed.length; i++) {
    final offset = (parsed[i].$2 ?? i / (parsed.length - 1)).clamp(0.0, 1.0).toDouble();
    stops.add(GradientStop(parsed[i].$1, offset));
  }
  return GradientSpec(kind, angle, stops);
}

/// A shader for `value` laid across `box` (in the canvas's CURRENT space), or
/// null when the value isn't a readable gradient.
Shader? gradientShader(Object? value, Rect box) {
  final spec = parseGradient(value);
  if (spec == null) return null;

  final colors = <Color>[];
  final offsets = <double>[];
  for (final stop in spec.stops) {
    // An unreadable colour would lose the whole gradient; drop just that stop.
    final c = parseCssColor(stop.color);
    if (c == null) continue;
    colors.add(c);
    offsets.add(stop.offset);
  }
  if (colors.isEmpty) return null;
  if (colors.length == 1) {
    colors.add(colors.first);
    offsets.add(1);
  }

  final center = box.center;
  if (spec.kind == 'radial') {
    final radius = math.max(box.width, box.height) / 2;
    return Gradient.radial(center, radius <= 0 ? 1 : radius, colors, offsets);
  }
  // CSS angles run CLOCKWISE FROM UP, hence the negated cosine.
  final rad = spec.angle * math.pi / 180;
  final dx = math.sin(rad);
  final dy = -math.cos(rad);
  // Long enough that the corners land on the ends of the gradient line (the
  // CSS rule) — otherwise a 45° gradient finishes early.
  var length = (box.width * dx).abs() + (box.height * dy).abs();
  if (length <= 0) length = 1;
  return Gradient.linear(
    Offset(center.dx - dx * length / 2, center.dy - dy * length / 2),
    Offset(center.dx + dx * length / 2, center.dy + dy * length / 2),
    colors,
    offsets,
  );
}

/// Port of `fillStyleFor`: a paint for a colour or gradient value, positioned
/// across `box`. Null when the value paints nothing we can read.
Paint? paintFor(Object? value, Rect box) {
  if (isGradient(value)) {
    final shader = gradientShader(value, box);
    if (shader != null) return Paint()..shader = shader;
    return null;
  }
  final c = parseCssColor(value);
  if (c == null) return null;
  return Paint()..color = c;
}
