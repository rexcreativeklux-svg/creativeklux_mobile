import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';

/// Magic Studio history + the source-image upload, for the editor panel.
///
/// Port of the slice of `(lib)/magic-studio-api.js` the panel needs that
/// `features/studio/magic_design.dart` doesn't already cover: `getMagicHistory`
/// (+ `expandMagicHistoryRecord`), `deleteMagicHistoryItem`, `pickHostedUrl`,
/// and of `pollSchedule.js` (cadence + staleness for runs still in flight).
/// Generating itself goes through `MagicApi.run` from magic_design.dart.

/// CDN base for turning an S3 object key into a hosted URL (magic-studio-api.js).
const magicCdnBase = 'https://d3r8chxzp8ea06.cloudfront.net';

/// A full URL passes through; a bare S3 key is resolved against the CDN.
String? resolveMagicMediaUrl(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(v)) return v;
  return '$magicCdnBase/${v.replaceFirst(RegExp(r'^/+'), '')}';
}

/// The hosted URL out of an upload response. ⚠️ The gallery endpoint nests its
/// result under `file` — the envelope that's easiest to miss; `data` and the top
/// level are tried after it (magic-studio-api.js `pickHostedUrl`).
String? pickHostedUrl(dynamic response) {
  final r = response is Map ? response : const {};
  final data = r['data'];
  final roots = [r['file'], data is Map ? data['file'] : null, data, r];
  for (final root in roots) {
    if (root is! Map) continue;
    for (final k in ['image_url', 'url', 'file_url', 's3_key']) {
      final url = resolveMagicMediaUrl(root[k]);
      if (url != null) return url;
    }
  }
  return null;
}

// ── pollSchedule.js ───────────────────────────────────────────────────────────

/// When a record still saying "processing" is treated as abandoned — what stops
/// a crashed job from spinning a loading tile on every visit forever.
const magicStaleAfter = Duration(minutes: 15);

/// Tight at first (a 1x image can land in ~46s), slack later (4x ≈ 4 min).
Duration magicNextPollDelay(Duration elapsed) => elapsed < const Duration(seconds: 30)
    ? const Duration(seconds: 3)
    : elapsed < const Duration(minutes: 2)
    ? const Duration(seconds: 5)
    : const Duration(seconds: 10);

/// Time since an API timestamp; zero when unreadable — "only just started" is
/// the safe answer, it keeps an in-flight run on screen.
Duration magicElapsedSince(String? iso, {DateTime? now}) {
  final at = iso == null ? null : DateTime.tryParse(iso);
  if (at == null) return Duration.zero;
  final d = (now ?? DateTime.now()).difference(at);
  return d.isNegative ? Duration.zero : d;
}

// ── History items ────────────────────────────────────────────────────────────

/// One tile of history — one generated asset, a text-only result, or a run
/// still in flight ([pending]).
class MagicHistoryItem {
  const MagicHistoryItem({
    required this.id,
    required this.generationId,
    required this.type,
    this.url,
    this.thumbnail,
    this.content,
    this.prompt,
    this.startedAt,
    this.createdAt,
    this.pending = false,
  });

  /// `<generationId>:<index>` — one record can carry a whole batch, and each
  /// tile needs its own identity. DELETE takes [generationId].
  final String id;
  final String generationId;

  /// "image" | "video" | "audio" | "text", or null for a pending run.
  final String? type;
  final String? url;
  final String? thumbnail;
  final String? content;
  final String? prompt;
  final String? startedAt;
  final String? createdAt;
  final bool pending;
}

const _pendingStatuses = ['processing', 'pending', 'queued', 'in_progress'];
final _videoExt = RegExp(r'\.(mp4|webm|mov|mkv|m4v)(\?|#|$)', caseSensitive: false);
final _audioExt = RegExp(r'\.(mp3|wav|ogg|m4a|aac|flac)(\?|#|$)', caseSensitive: false);

String _inferType(Map record, String? url) {
  final explicit = '${record['type'] ?? record['content_type'] ?? ''}'.toLowerCase();
  if (const ['image', 'video', 'audio', 'text'].contains(explicit)) return explicit;
  if (record['video_url'] != null || _videoExt.hasMatch(url ?? '')) return 'video';
  if (record['audio_url'] != null || _audioExt.hasMatch(url ?? '')) return 'audio';
  return url != null ? 'image' : 'text';
}

/// Every asset one record produced. ⚠️ A multi-variation run is ONE record with
/// its assets in `meta.outputs: [{key, url}]`; `url` holds only the first.
List<({String url, String? thumbnail})> _recordAssets(Map record) {
  final meta = record['meta'];
  final outputs = meta is Map ? meta['outputs'] : null;
  if (outputs is List && outputs.isNotEmpty) {
    return [
      for (final o in outputs.whereType<Map>())
        if ((resolveMagicMediaUrl(o['url']) ?? resolveMagicMediaUrl(o['key'])) case final url?)
          (url: url, thumbnail: resolveMagicMediaUrl(o['thumbnail'])),
    ];
  }
  final url = [
    'url',
    's3_key',
    'image_url',
    'video_url',
    'audio_url',
  ].map((k) => resolveMagicMediaUrl(record[k])).firstWhere((u) => u != null, orElse: () => null);
  if (url == null) return const [];
  final thumb = [
    'thumbnail',
    'poster',
    'thumbnail_s3_key',
  ].map((k) => resolveMagicMediaUrl(record[k])).firstWhere((u) => u != null, orElse: () => null);
  return [(url: url, thumbnail: thumb)];
}

/// One raw record → the tiles it becomes (magic-studio-api.js
/// `expandMagicHistoryRecord`): one per asset, one text tile, one pending tile,
/// or nothing for a failed / empty record.
List<MagicHistoryItem> expandMagicHistoryRecord(dynamic record) {
  if (record is! Map) return const [];
  final gid = '${record['id'] ?? record['_id'] ?? ''}';
  final status = '${record['status'] ?? ''}'.toLowerCase();
  if (status == 'failed') return const [];
  final prompt = record['prompt'] is String ? record['prompt'] as String : null;
  final createdAt = '${record['generated_at'] ?? record['created_at'] ?? ''}';
  final startedAt = record['created_at'] is String ? record['created_at'] as String : null;

  if (_pendingStatuses.contains(status)) {
    final meta = record['meta'];
    return [
      MagicHistoryItem(
        id: '$gid:pending',
        generationId: gid,
        type: meta is Map && meta['content_type'] is String ? meta['content_type'] as String : null,
        prompt: prompt,
        startedAt: startedAt,
        createdAt: createdAt,
        pending: true,
      ),
    ];
  }

  final assets = _recordAssets(record);
  if (assets.isEmpty) {
    // ⚠️ `transcript` is its own column — a text-only result still counts.
    final content = record['content'] ?? record['text'] ?? record['transcript'];
    if (content == null || '$content'.isEmpty) return const [];
    return [
      MagicHistoryItem(
        id: '$gid:0',
        generationId: gid,
        type: 'text',
        content: '$content',
        prompt: prompt,
        startedAt: startedAt,
        createdAt: createdAt,
      ),
    ];
  }

  return [
    for (var i = 0; i < assets.length; i++)
      MagicHistoryItem(
        id: '$gid:$i',
        generationId: gid,
        type: _inferType(record, assets[i].url),
        url: assets[i].url,
        thumbnail: assets[i].thumbnail,
        prompt: prompt,
        startedAt: startedAt,
        createdAt: createdAt,
      ),
  ];
}

class MagicHistoryApi {
  MagicHistoryApi(this._api);

  final ApiClient _api;

  /// History for one tool, newest first, pending runs included. Null when the
  /// load failed (the panel shows its empty state either way, like the web).
  Future<List<MagicHistoryItem>?> list(String tool) async {
    final res = await _api.post('/magic-studio/history', body: {'tool': tool});
    if (!res.ok) return null;
    final raw = res.raw;
    final list = raw is List ? raw : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
    return [for (final r in list) ...expandMagicHistoryRecord(r)];
  }

  /// Delete one generation record (every tile of its batch goes with it).
  /// Returns null on success, else the message to show.
  Future<String?> delete(String generationId) async {
    final res = await _api.delete('/magic-studio/$generationId');
    if (res.ok) return null;
    final b = res.body;
    final msg = '${b['message'] ?? b['error'] ?? ''}';
    return msg.isNotEmpty ? msg : "Couldn't delete that item. Please try again.";
  }

  /// Host a local image in the gallery (`POST /gallery`) so the backend can
  /// fetch it as `image_url` — how the web's uploadMedia feeds Variations.
  Future<String?> uploadImage(List<int> bytes, String filename) async {
    final res = await _api.post(
      '/gallery',
      body: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)}),
    );
    if (!res.ok) return null;
    return pickHostedUrl(res.raw);
  }
}
