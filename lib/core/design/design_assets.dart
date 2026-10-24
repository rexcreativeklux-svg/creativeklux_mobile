import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

/// What the renderer has to fetch before it can paint: images and fonts.
///
/// The web renderer awaits each image inside its paint loop and calls
/// `waitForFonts` first. A dart:ui Canvas is synchronous, so everything is
/// loaded up front, in parallel, and the painter only reads the results.

// ── Images ──────────────────────────────────────────────────────────────────

/// Plain Dio, not the app's ApiClient: design images live on public CDNs and
/// must not carry the user's bearer token.
final Dio _dio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    responseType: ResponseType.bytes,
  ),
);

/// Encoded bytes by URL, most recent last. Bytes rather than decoded images:
/// a ui.Image is per render (and disposed after it), but a feed re-rendering
/// the same template shouldn't download its photos again.
final LinkedHashMap<String, Uint8List> _byteCache = LinkedHashMap();
const _byteCacheMax = 40;

/// Decoded images are capped at this long side. A design paints a photo at a
/// few hundred to ~1600px; decoding a 6000px original at full size would cost
/// ~140MB of memory for nothing.
const _decodeMaxSide = 2048;

Future<Uint8List?> _bytesFor(String src) async {
  final cached = _byteCache.remove(src);
  if (cached != null) return _byteCache[src] = cached;

  Uint8List? bytes;
  if (src.startsWith('data:')) {
    bytes = UriData.parse(src).contentAsBytes();
  } else if (src.startsWith('http://') || src.startsWith('https://')) {
    final res = await _dio.get<List<int>>(src);
    final data = res.data;
    if (data == null) return null;
    bytes = data is Uint8List ? data : Uint8List.fromList(data);
  } else {
    // blob: and relative paths only mean something inside the web app.
    return null;
  }

  _byteCache[src] = bytes;
  while (_byteCache.length > _byteCacheMax) {
    _byteCache.remove(_byteCache.keys.first);
  }
  return bytes;
}

/// Load and decode one image; null on any failure (the painter skips it,
/// exactly as the web's `catch { /* skip broken image */ }` does).
Future<ui.Image?> loadDesignImage(String src) async {
  try {
    final bytes = await _bytesFor(src);
    if (bytes == null) return null;
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final long = math.max(descriptor.width, descriptor.height);
    final scale = long > _decodeMaxSide ? _decodeMaxSide / long : 1.0;
    final codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  } catch (_) {
    return null;
  }
}

/// Load every source at once; failures are simply absent from the result.
Future<Map<String, ui.Image>> loadDesignImages(Iterable<String> sources) async {
  final unique = sources.toSet().toList();
  final loaded = await Future.wait(unique.map(loadDesignImage));
  return {
    for (var i = 0; i < unique.length; i++)
      if (loaded[i] != null) unique[i]: loaded[i]!,
  };
}

// ── Fonts ───────────────────────────────────────────────────────────────────

const defaultFontFamily = 'DM Sans';

const _genericFamilies = {
  'serif',
  'sans-serif',
  'monospace',
  'cursive',
  'fantasy',
  'system-ui',
  'ui-sans-serif',
  'ui-serif',
  'ui-monospace',
  'inherit',
  'initial',
};

/// A CSS font-family value (`"'Playfair Display', serif"`) → the first named
/// family, unquoted. Generic or missing → the editor's default, DM Sans.
String fontFamilyName(Object? raw) {
  if (raw is! String) return defaultFontFamily;
  final first = raw.split(',').first.trim().replaceAll(RegExp('^[\'"]+|[\'"]+\$'), '').trim();
  if (first.isEmpty || _genericFamilies.contains(first.toLowerCase())) return defaultFontFamily;
  return first;
}

/// CSS font-weight (`700`, `"600"`, `"bold"`) → [FontWeight].
FontWeight fontWeightOf(Object? raw) {
  double? n;
  if (raw is num) {
    n = raw.toDouble();
  } else if (raw is String) {
    final s = raw.trim().toLowerCase();
    n = switch (s) {
      'normal' || '' => 400,
      'bold' || 'bolder' => 700,
      'lighter' => 300,
      _ => double.tryParse(s),
    };
  }
  final index = ((n ?? 400) / 100).round().clamp(1, 9) - 1;
  return FontWeight.values[index];
}

FontStyle fontStyleOf(Object? raw) => (raw == 'italic' || raw == 'oblique') ? FontStyle.italic : FontStyle.normal;

/// Text styles for the faces a design uses, resolved before painting.
class DesignFonts {
  final Map<String, TextStyle> _styles = {};

  /// Successful loads, kept for the session so a feed of designs doesn't wait
  /// on google_fonts again for faces it already has.
  static final Map<String, TextStyle> _loaded = {};

  static String _key(String family, FontWeight w, FontStyle s) => '$family|${w.value}|${s.name}';

  /// Load every (family, weight, style) the design asks for. A face that fails
  /// (unknown to Google Fonts, offline, fetching disabled) falls back to DM Sans
  /// in the same weight, and failing that to the platform default.
  Future<void> load(Iterable<(String, FontWeight, FontStyle)> faces) async {
    for (final (family, w, s) in faces.toSet()) {
      final key = _key(family, w, s);
      if (_styles.containsKey(key)) continue;
      var style = await _loadOne(family, w, s);
      if (style == null && family != defaultFontFamily) style = await _loadOne(defaultFontFamily, w, s);
      _styles[key] = style ?? TextStyle(fontWeight: w, fontStyle: s);
    }
  }

  TextStyle styleFor(String family, FontWeight w, FontStyle s) =>
      _styles[_key(family, w, s)] ?? TextStyle(fontWeight: w, fontStyle: s);

  /// One face via google_fonts, or null.
  ///
  /// Guarded in its own error zone because google_fonts reports a failed load
  /// twice: through `pendingFonts()` AND as an unhandled error from a `.then`
  /// it chains internally. Outside a zone that second copy surfaces as an
  /// uncaught async error (and fails tests that disable runtime fetching).
  static Future<TextStyle?> _loadOne(String family, FontWeight w, FontStyle s) {
    final key = _key(family, w, s);
    final hit = _loaded[key];
    if (hit != null) return Future.value(hit);

    final done = Completer<TextStyle?>();
    runZonedGuarded(
      () async {
        final style = GoogleFonts.getFont(family, fontWeight: w, fontStyle: s);
        await GoogleFonts.pendingFonts();
        _loaded[key] = style;
        if (!done.isCompleted) done.complete(style);
      },
      (error, stack) {
        if (!done.isCompleted) done.complete(null);
      },
    );
    return done.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
  }
}
