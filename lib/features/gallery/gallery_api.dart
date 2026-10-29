import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/api/app_exception.dart';
import '../../core/config.dart';
import '../brand/brand_api.dart';

// ── Media types (port of components/gallery/mediaTypes.js + utils/helpers.js) ──

/// One tab of the gallery: Images · Videos · Audio · Docs, in that order.
class MediaType {
  const MediaType(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

const mediaTypes = <MediaType>[
  MediaType('image', 'Images', LucideIcons.image),
  MediaType('video', 'Videos', LucideIcons.film),
  MediaType('audio', 'Audio', LucideIcons.audioLines),
  MediaType('document', 'Docs', LucideIcons.fileText),
];

MediaType mediaTypeMeta(String id) => mediaTypes.firstWhere((t) => t.id == id, orElse: () => mediaTypes.first);

/// Max upload size per category (FILE_LIMITS).
const fileLimits = <String, int>{
  'image': 5 * 1024 * 1024,
  'video': 50 * 1024 * 1024,
  'audio': 10 * 1024 * 1024,
  'document': 5 * 1024 * 1024,
};

/// ⚠️ MIRRORS THE BACKEND'S `mimes:` RULE EXACTLY (SUPPORTED_EXTENSIONS on the
/// web). Laravel keys off the extension, so classification is extension-first:
/// a looser check would let a .heic through only for the API to refuse it.
const supportedExtensions = <String, List<String>>{
  'image': ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
  'video': ['mp4', 'mov', 'avi', 'webm', 'mkv', 'm4v'],
  'audio': ['mp3', 'wav', 'm4a', 'ogg', 'aac', 'flac'],
  'document': ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'txt', 'csv'],
};

/// "jpg, jpeg, png…" for error copy (describeSupportedTypes).
String describeSupportedTypes() => supportedExtensions.values.expand((e) => e).join(', ');

/// Lowercase extension without the dot, ignoring any query/hash.
String extensionOf(String name) {
  final clean = name.toLowerCase().split('?').first.split('#').first;
  final dot = clean.lastIndexOf('.');
  return dot < 0 ? '' : clean.substring(dot + 1);
}

/// Categorise a file the way the backend will (getFileCategory); null =
/// unsupported, which the caller reports before uploading.
String? fileCategory(String name, {String? mime}) {
  final ext = extensionOf(name);
  for (final e in supportedExtensions.entries) {
    if (e.value.contains(ext)) return e.key;
  }
  // No usable extension (e.g. a URL without one) — fall back to the MIME
  // type, but only where it maps onto a supported extension.
  final m = (mime ?? '').toLowerCase();
  if (m.isNotEmpty) {
    final sub = m.split('/').last.split(';').first;
    for (final e in supportedExtensions.entries) {
      if (e.value.contains(sub)) return e.key;
    }
    if (m == 'image/jpg') return 'image';
  }
  return null;
}

const _videoExts = ['mp4', 'webm', 'mov', 'avi', 'mkv', 'm4v', 'ogv'];
const _audioExts = ['mp3', 'wav', 'ogg', 'm4a', 'aac', 'flac', 'opus', 'weba'];
const _docExts = ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'txt', 'csv', 'rtf', 'md', 'json'];

// ── Items ────────────────────────────────────────────────────────────────────

/// One gallery file, in the shape every gallery surface consumes
/// (normalizeGalleryItem in AuthContext.jsx). Pexels results use it too.
class GalleryMedia {
  const GalleryMedia({
    required this.id,
    required this.rawType,
    required this.src,
    required this.filename,
    this.downloadUrl,
    this.poster,
  });

  factory GalleryMedia.fromJson(Map<String, dynamic> m) => GalleryMedia(
    id: m['id'],
    rawType: '${m['type'] ?? ''}',
    src: '${m['image_url'] ?? ''}',
    filename: '${m['image_name'] ?? ''}',
  );

  final Object? id;

  /// The backend's `type` — "" on legacy images.
  final String rawType;
  final String src;
  final String filename;

  /// Full-resolution file for Download (Pexels' original), when it differs.
  final String? downloadUrl;

  /// A still for video tiles. Only Pexels results carry one — the backend
  /// stores none, so a gallery video tile shows a film mark instead.
  final String? poster;

  bool get isStock => '$id'.startsWith('px-');

  /// classifyMediaType(): trust the backend's type, else sniff the extension.
  String get type {
    final raw = rawType.toLowerCase().trim();
    if (const ['image', 'video', 'audio', 'document'].contains(raw)) return raw;
    final ext = extensionOf(filename.isNotEmpty ? filename : src);
    if (_videoExts.contains(ext)) return 'video';
    if (_audioExts.contains(ext)) return 'audio';
    if (_docExts.contains(ext)) return 'document';
    return 'image';
  }

  /// A short extension badge ("PDF"), or "FILE" (extBadge in MediaCard.jsx).
  String get extBadge {
    final name = (filename.isNotEmpty ? filename : src).toLowerCase();
    final ext = extensionOf(name);
    return ext.isNotEmpty && ext.length <= 5 && ext != name ? ext.toUpperCase() : 'FILE';
  }
}

/// One page of a type: the items plus the Laravel paginator's numbers.
class GalleryPage {
  const GalleryPage(this.items, {required this.page, required this.lastPage, this.total});
  final List<GalleryMedia> items;
  final int page;
  final int lastPage;

  /// `meta.total` — null when the response wasn't paginated (or failed).
  final int? total;
}

/// The gallery endpoints the page drives — `fetchGalleryPage`, `uploadMedia`
/// and `deleteImage` in the web's AuthContext.
///
/// `EditorApi.gallery()` reads the same list, but drops the paginator's
/// `total`, which the tab badges need — hence this small sibling.
class GalleryApi {
  GalleryApi(this._api);

  final ApiClient _api;

  /// How many items to request per page (PER_PAGE in useGalleryMedia.js).
  static const perPage = 30;

  /// `GET /gallery?type=&per_page=&page=`. Like the web it never throws: a
  /// failure is an empty page, so the UI degrades instead of crashing.
  Future<GalleryPage> page(String type, {int page = 1, int perPage = perPage}) async {
    final res = await _api.get('/gallery', query: {'per_page': perPage, 'page': page, 'type': type});
    if (!res.ok) {
      debugPrint('❌ [gallery] page fetch failed: ${res.messageForDevs}');
      return GalleryPage(const [], page: page, lastPage: page);
    }
    final body = res.body;
    final files = body['files'];
    // Paginator object: items under `.data`, page info alongside.
    if (files is Map && files['data'] is List) {
      final rows = _items(files['data'] as List);
      int n(Object? v, int fallback) => int.tryParse('${v ?? ''}') ?? fallback;
      return GalleryPage(
        rows,
        page: n(files['current_page'], page),
        lastPage: n(files['last_page'], 1),
        total: n(files['total'], rows.length),
      );
    }
    // Legacy flat array — infer there's more only if we got a full page.
    final flat = files is List ? files : (body['data'] is List ? body['data'] as List : const []);
    final rows = _items(flat);
    return GalleryPage(rows, page: page, lastPage: rows.length < perPage ? page : page + 1);
  }

  static List<GalleryMedia> _items(List rows) => [
    for (final r in rows)
      if (r is Map) GalleryMedia.fromJson(Map<String, dynamic>.from(r)),
  ];

  /// `POST /gallery` (multipart `file`). Throws an [AppException] in the
  /// backend's words — its validation names the exact reason.
  Future<String?> upload({String? path, List<int>? bytes, required String filename}) async {
    final file = path != null
        ? await MultipartFile.fromFile(path, filename: filename)
        : MultipartFile.fromBytes(bytes!, filename: filename);
    final res = await _api.post(
      '/gallery',
      body: FormData.fromMap({'file': file}),
      timeout: const Duration(minutes: 5),
    );
    if (!res.ok) throwClassified('uploadMedia', res, 'Upload failed. Please try again.');
    return BrandApi.extractImageUrl(res.body);
  }

  /// `DELETE /gallery/{id}` — returns the backend's message on failure.
  Future<String?> delete(Object id) async {
    final res = await _api.delete('/gallery/$id');
    if (res.ok) return null;
    return res.body['message']?.toString() ?? res.message;
  }

  // ── Pexels stock (through the WEB APP's /api/pexels) ──────────────────────
  // The key stays on that server, exactly as on the web; CORS doesn't apply
  // to a phone, so the app calls the route directly.

  static Future<List<GalleryMedia>> searchStock(String query, {required bool videos}) async {
    final res = await Dio().get<Map<String, dynamic>>(
      '${AppConfig.webAppUrl}/api/pexels',
      queryParameters: {'query': query, 'type': videos ? 'videos' : 'photos'},
    );
    final data = res.data ?? const {};
    if (data['error'] != null) throw Exception('${data['error']}');
    if (!videos) {
      return [
        for (final p in (data['photos'] is List ? data['photos'] as List : const []).whereType<Map>())
          if (p['src'] is Map)
            GalleryMedia(
              id: 'px-${p['id']}',
              rawType: 'image',
              src: '${(p['src'] as Map)['medium'] ?? (p['src'] as Map)['original']}',
              filename: 'pexels-${p['id']}.jpg',
              downloadUrl: '${(p['src'] as Map)['original'] ?? (p['src'] as Map)['large']}',
            ),
      ];
    }
    // The HD file when there is one, else the first (getVideoUrl).
    String? pick(Object? files) {
      final all = (files is List ? files : const []).whereType<Map>().where((f) => f['link'] != null).toList();
      if (all.isEmpty) return null;
      return '${(all.where((f) => f['quality'] == 'hd').firstOrNull ?? all.first)['link']}';
    }

    return [
      for (final v in (data['videos'] is List ? data['videos'] as List : const []).whereType<Map>())
        if (pick(v['video_files']) case final link?)
          GalleryMedia(
            id: 'px-${v['id']}',
            rawType: 'video',
            src: link,
            filename: 'pexels-${v['id']}.mp4',
            downloadUrl: link,
            poster: v['image']?.toString(),
          ),
    ];
  }
}
