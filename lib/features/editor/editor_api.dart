import 'dart:convert';

import 'package:flutter/painting.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';
import '../../core/design/design_assets.dart';
import '../../core/design/js_values.dart';

/// A design opened for editing (port of `toEditorDesign` in design/[id]/page.jsx).
class EditorDesign {
  const EditorDesign({
    required this.id,
    required this.name,
    required this.canvas,
    required this.elements,
    required this.notes,
    required this.raw,
  });

  final int id;
  final String name;
  final Map<String, dynamic> canvas;
  final List<dynamic> elements;
  final String notes;
  final Map<String, dynamic> raw;
}

/// One file in the user's gallery (`GET /gallery`).
class GalleryItem {
  const GalleryItem({required this.id, required this.type, required this.src, required this.name});
  final Object? id;
  final String type;
  final String src;
  final String name;
}

/// Calls the design editor makes — `fetchDesignById`, `updateDesignById` and
/// `fetchGalleryPage` in the web's AuthContext.
class EditorApi {
  EditorApi(this._api);

  final ApiClient _api;

  /// The raw design record, unwrapped from `{data: …}`; null when it can't load.
  Future<Map<String, dynamic>?> fetchRaw(int id) async {
    final res = await _api.get('/creative-designs/$id');
    if (!res.ok) return null;
    final payload = res.data;
    if (payload is List) {
      return payload.whereType<Map<String, dynamic>>().where((d) => '${d['id']}' == '$id').firstOrNull;
    }
    return payload is Map<String, dynamic> && payload['id'] != null ? payload : null;
  }

  /// Load and normalise into the editor's shape:
  ///   · a structured design (canvas + elements) → as-is;
  ///   · a raster creative (image only) → one full-bleed image element sized
  ///     to the picture, so it's editable like any other layer;
  ///   · nothing usable → a blank 1080 square.
  Future<EditorDesign?> load(int id) async {
    final raw = await fetchRaw(id);
    if (raw == null) return null;

    dynamic parsed = raw['canvas'];
    if (parsed is String) {
      try {
        parsed = jsonDecode(parsed);
      } catch (_) {
        parsed = null;
      }
    }
    Map<String, dynamic>? canvas;
    var elements = <dynamic>[];
    var notes = '';
    if (parsed is Map) {
      if (parsed['canvas'] is Map && parsed['elements'] is List) {
        canvas = Map<String, dynamic>.from(parsed['canvas'] as Map);
        elements = parsed['elements'] as List;
      }
      if (parsed['notes'] is String) {
        notes = parsed['notes'] as String;
      } else if (parsed['width'] != null && parsed['height'] != null) {
        canvas = Map<String, dynamic>.from(parsed);
      }
    }

    final name = truthy(raw['name']) ? '${raw['name']}' : 'Untitled design';
    final image = [raw['image_url'], raw['image']].whereType<String>().where((s) => s.isNotEmpty).firstOrNull;
    final rid = int.tryParse('${raw['id']}') ?? id;

    if (canvas != null && (elements.isNotEmpty || image == null)) {
      return EditorDesign(id: rid, name: name, canvas: canvas, elements: elements, notes: notes, raw: raw);
    }
    if (image != null) {
      final size = await _imageSize(image) ?? const Size(1080, 1080);
      return EditorDesign(
        id: rid,
        name: name,
        canvas: {'width': size.width, 'height': size.height, 'background': '#ffffff'},
        elements: [
          {'type': 'image', 'src': image, 'x': 0, 'y': 0, 'width': size.width, 'height': size.height},
        ],
        notes: notes,
        raw: raw,
      );
    }
    return EditorDesign(
      id: rid,
      name: name,
      canvas: canvas ?? {'width': 1080, 'height': 1080, 'background': '#ffffff'},
      elements: elements,
      notes: notes,
      raw: raw,
    );
  }

  /// `PUT /creative-designs/{id}` — name, the canvas JSON blob, and a fresh
  /// preview (`data:image/png;base64,…`) when one could be painted.
  Future<ApiResult> save(int id, {required String name, required String canvasJson, String? thumbnail}) =>
      _api.put('/creative-designs/$id', body: {'name': name, 'canvas': canvasJson, 'thumbnail': ?thumbnail});

  /// One page of the user's uploads of [type] ("image" | "video" …), newest first.
  /// The paginated backend nests a Laravel paginator under `files`; older
  /// responses put a plain array there.
  Future<(List<GalleryItem>, bool hasMore)> gallery({String type = 'image', int page = 1}) async {
    final res = await _api.get('/gallery', query: {'per_page': 30, 'page': page, 'type': type});
    if (!res.ok) return (const <GalleryItem>[], false);
    final body = res.body;
    final files = body['files'];
    List<dynamic> rows;
    var more = false;
    if (files is Map && files['data'] is List) {
      rows = files['data'] as List;
      more = (numOf(files['current_page']) ?? 1) < (numOf(files['last_page']) ?? 1);
    } else {
      rows = files is List ? files : (body['data'] is List ? body['data'] as List : const []);
    }
    return (
      [
        for (final r in rows.whereType<Map>())
          if (r['image_url'] is String && (r['image_url'] as String).isNotEmpty)
            GalleryItem(
              id: r['id'],
              type: '${r['type'] ?? type}',
              src: r['image_url'] as String,
              name: '${r['image_name'] ?? ''}',
            ),
      ],
      more,
    );
  }

  static Future<Size?> _imageSize(String src) async {
    final img = await loadDesignImage(src);
    if (img == null) return null;
    final size = Size(img.width.toDouble(), img.height.toDouble());
    img.dispose();
    return size;
  }
}
