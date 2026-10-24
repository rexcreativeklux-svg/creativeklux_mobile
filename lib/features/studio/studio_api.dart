import 'dart:async';
import 'dart:convert';

import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';
import '../../core/design/design_renderer.dart';
import '../../core/design/scraive_compat.dart';

/// The AI chat studio's endpoints — `createChatSession`, `creativeAiChat`,
/// `fetchChatSessions`, `fetchChatSession`, `generateCustomCreative` and
/// `saveDesign` from the web's AuthContext.
class StudioApi {
  StudioApi(this._api);

  final ApiClient _api;

  // ── Sessions ──────────────────────────────────────────────────────────────

  /// Start a chat thread for the brand; returns its id, or null.
  Future<String?> createSession(int brandId) async {
    final res = await _api.post('/creative/session', body: {'brand_id': brandId});
    if (!res.ok) return null;
    final b = res.body;
    final data = b['data'] is Map ? b['data'] as Map : const {};
    final session = b['session'] is Map ? b['session'] as Map : const {};
    final id = b['session_id'] ?? b['id'] ?? data['session_id'] ?? data['id'] ?? session['id'];
    return id?.toString();
  }

  /// `{session_id, title, status: open|complete, messages: count, started}`, newest first.
  Future<ApiResult> sessions(int brandId) => _api.get('/creative/sessions/$brandId');

  Future<ApiResult> session(String id) => _api.get('/creative/session/$id');

  // ── Chat ──────────────────────────────────────────────────────────────────

  /// One chat turn. Not streamed — the whole reply comes back at once.
  /// The body is exactly the fields the endpoint validates.
  Future<ApiResult> send({
    required int brandId,
    required String message,
    required List<String> images,
    String? logo,
    String? model,
    String? sessionId,
  }) => _api.post(
    '/creatives/ai-creative',
    body: {
      'brand_id': brandId,
      'message': message,
      'save_chat': 'true',
      'details': null,
      'images': images.isEmpty ? null : images.take(10).toList(),
      'logo': logo,
      'model': model,
      'session_id': sessionId,
    },
  );

  // ── Building designs (create-design engine) ───────────────────────────────

  /// Build [count] designs from the chat's brief, five per request, one
  /// request after another; each finished batch is handed to [onBatch] so the
  /// preview can fill in as they land. Returns the failure messages.
  Future<List<String>> createDesigns(
    Map<String, dynamic> payload, {
    required int count,
    required void Function(List<Map<String, dynamic>> variations) onBatch,
  }) async {
    final creativeType = '${payload.remove('creativeType') ?? ''}'.replaceAll('_creative', '');
    final categoryType = payload.remove('categoryType');
    payload.remove('templates');
    final generatedAt = payload.remove('generatedAt');

    final failures = <String>[];
    for (var left = count; left > 0; left -= 5) {
      final batch = left < 5 ? left : 5;
      final body = {
        'generation_data': {
          'brand_details': {
            'creative_type': creativeType,
            'create_sub_type': categoryType,
            ...payload,
            'variations': batch,
          },
          'generatedAt': generatedAt,
        },
      };
      var res = await _api.post('/creatives/create-design', body: body);
      // Queued jobs are polled every 3s until they leave queued/processing.
      final jobId = res.body['job_id'];
      while (res.ok && jobId != null && (res.body['status'] == 'queued' || res.body['status'] == 'processing')) {
        await Future<void>.delayed(const Duration(seconds: 3));
        res = await _api.post('/creatives/redesign/$jobId');
      }
      if (!res.ok) {
        failures.add(res.message);
        continue;
      }
      final variations = res.body['variations'];
      onBatch([
        if (variations is List)
          for (final v in variations)
            if (v is Map) {...Map<String, dynamic>.from(v), 'source': 'scraive'},
      ]);
    }
    return failures;
  }

  // ── Saving ────────────────────────────────────────────────────────────────

  /// Save designs to the brand's library. Each carries a client-rendered
  /// thumbnail (data URL) — the backend stores it and returns a CDN URL.
  /// Returns the new design ids (may be empty if the backend didn't say).
  Future<({bool ok, String message, List<int> ids})> save(
    int brandId,
    List<Map<String, dynamic>> variations,
    String creativeType,
  ) async {
    final type = (creativeType.isEmpty || creativeType == 'general' ? 'ads' : creativeType).replaceAll('_creative', '');
    final designs = <Map<String, dynamic>>[];
    for (final v in variations) {
      final canvas = Map<String, dynamic>.from(v['canvas'] as Map? ?? const {'width': 1080, 'height': 1080});
      final raw = (v['elements'] as List?) ?? const [];
      final scraive = v['source'] == 'scraive';
      final elements = scraive ? fromScraiveElements(raw, text: true) : raw;
      String? thumbnail;
      try {
        final png = await renderDesignPng(canvas, elements);
        thumbnail = 'data:image/png;base64,${base64Encode(png)}';
      } catch (_) {
        // A broken preview must never block the save.
      }
      final copy = v['copy'] is Map ? v['copy'] as Map : const {};
      final score = int.tryParse('${copy['performance_score'] ?? ''}'.split('/').first.trim()) ?? 0;
      designs.add({
        'name': v['name'] ?? 'Untitled Design',
        'score': score,
        'copy': jsonEncode(copy),
        'canvas': {'canvas': canvas, 'elements': elements},
        'thumbnail': ?thumbnail,
        'type': type,
        'sub_type': '${v['category'] ?? ''}'.isEmpty ? 'image' : '${v['category']}'.toLowerCase(),
      });
    }

    final res = await _api.post('/creative-designs', body: {'brand_id': brandId, 'creativedesigns': designs});
    if (!res.ok) {
      // A plan limit (403) puts the readable text in `message`.
      return (ok: false, message: res.message.isNotEmpty ? res.message : 'Failed to save designs', ids: <int>[]);
    }
    final created = res.body['creatives'];
    return (
      ok: true,
      message: res.body['message']?.toString() ?? 'Design(s) saved successfully',
      ids: [
        if (created is List)
          for (final c in created)
            if (c is Map && int.tryParse('${c['id']}') != null) int.parse('${c['id']}'),
      ],
    );
  }
}
