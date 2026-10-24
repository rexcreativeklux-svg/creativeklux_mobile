import 'dart:convert';

import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';

/// Port of copilot/_data/copilotApi.js — the one place that knows the Copilot
/// endpoints, plus the slice of AuthContext's integrations helpers the
/// Plugins screen drives (catalogue / connect / accounts / select / disconnect).
///
/// ⚠️ THE PREFIX IS `/api/creativeklux-userend/`, the app's own — `ApiClient`
/// already points there, so every path below is relative to it.
///
/// ⚠️ The chat REQUEST SHAPE IS PROVISIONAL on the web too (`{ message }` plus
/// `copilot_id` / `conversation_id`); see the header of copilotApi.js.
///
/// Unlike [ApiClient], these THROW a [CopilotFailure]: the store's optimistic
/// writes roll back on a throw, exactly as the web's do.
class CopilotApi {
  CopilotApi(this._api);
  final ApiClient _api;

  // ── Copilots (the backend calls them agents) ─────────────────────────────

  /// `GET copilots` — the whole catalog for the signed-in brand (raw body).
  Future<dynamic> listCopilots() async => _assertOk(await _api.get('/copilots'), 'Could not load your copilots.');

  /// `GET copilots/{id}` — one copilot, with the channel link block beside `data`.
  Future<dynamic> getCopilot(String id) async =>
      _assertOk(await _api.get('/copilots/$id'), 'Could not load that copilot.');

  /// ⚠️ `name` IS REQUIRED — an empty body answers 422.
  Future<dynamic> createCopilot(Map<String, dynamic> payload) async =>
      _assertOk(await _api.post('/copilots', body: payload), 'Could not create the copilot.');

  Future<dynamic> patchCopilot(String id, Map<String, dynamic> patch) async =>
      _assertOk(await _api.put('/copilots/$id', body: patch), 'Could not save that change.');

  Future<dynamic> destroyCopilot(String id) async =>
      _assertOk(await _api.delete('/copilots/$id'), 'Could not delete that copilot.');

  // ── Conversation ─────────────────────────────────────────────────────────

  /// Ask a copilot something. ⚠️ `copilot_id` is what makes the copilots
  /// differ — without it the server answers with a generic agent.
  ///
  /// Not run through the 200-can-fail guard, same as the web: whatever a 2xx
  /// carries is shown as the reply, so an unexpected shape is visible.
  Future<dynamic> sendChat({required String message, String? copilotId, Object? conversationId}) async {
    final res = await _api.post(
      '/copilot/chat',
      body: {'message': message, 'copilot_id': ?copilotId, 'conversation_id': ?conversationId},
      timeout: const Duration(minutes: 3),
    );
    if (!res.ok) throw CopilotFailure.from(res);
    return res.raw;
  }

  /// One copilot's whole message history, oldest first (`GET copilots/{id}/messages`).
  ///
  /// ⚠️ `has_more` means the list is paged and the paging parameter hasn't
  /// been named yet — so a long history shows only its first page, as on the web.
  Future<List<Map<String, dynamic>>> fetchMessages(String copilotId) async {
    final data = _assertOk(await _api.get('/copilots/$copilotId/messages'), 'Could not load the conversation.');
    final rows = data is Map && data['data'] is List ? (data['data'] as List) : const [];
    final list = [
      for (final r in rows)
        if (r is Map) Map<String, dynamic>.from(r),
    ];
    int ms(Map r) => DateTime.tryParse('${r['created_at'] ?? ''}')?.millisecondsSinceEpoch ?? 0;
    int id(Map r) => int.tryParse('${r['id']}') ?? 0;
    list.sort((a, b) {
      final t = ms(a) - ms(b);
      return t != 0 ? t : id(a) - id(b);
    });
    return list;
  }

  // ── Integrations (AuthContext.jsx integrationsRequest + friends) ─────────
  // Each returns the raw body; failures throw with the SERVER'S OWN WORDS.

  /// `GET integrations/catalogue` — what is connected, waiting for an account
  /// choice, and each row's label. Under `catalogue` (was `integrations`).
  Future<List<Map<String, dynamic>>> integrationCatalogue(int? brandId) async {
    final data = _integrationOk(await _api.get('/integrations/catalogue', query: {'brand_id': ?brandId}));
    final rows = data['catalogue'] ?? data['integrations'];
    return [
      if (rows is List)
        for (final r in rows)
          if (r is Map) Map<String, dynamic>.from(r),
    ];
  }

  /// `POST integrations/{platform}/connect` → the single-use consent URL.
  Future<String> connectIntegration(String platform, int? brandId) async {
    final data = _integrationOk(await _api.post('/integrations/$platform/connect', body: {'brand_id': ?brandId}));
    final url = data['authorize_url'] ?? data['redirect_url'];
    if (url is! String || url.isEmpty) {
      throw const CopilotFailure(detail: 'The connect endpoint returned no authorize URL.');
    }
    return url;
  }

  /// `GET integrations/{platform}/accounts` → `{ accounts, selected, message? }`.
  Future<(List<Map<String, dynamic>>, String?)> integrationAccounts(String platform, int? brandId) async {
    final data = _integrationOk(await _api.get('/integrations/$platform/accounts', query: {'brand_id': ?brandId}));
    final list = data['accounts'];
    return (
      [
        if (list is List)
          for (final a in list)
            if (a is Map) Map<String, dynamic>.from(a),
      ],
      data['message']?.toString(),
    );
  }

  /// `POST integrations/{platform}/select` — finishes a connection that needed
  /// an account choice. Returns the server's message, if any.
  Future<String?> selectIntegrationAccount(String platform, Object accountId, int? brandId) async {
    final data = _integrationOk(
      await _api.post('/integrations/$platform/select', body: {'brand_id': ?brandId, 'account_id': accountId}),
    );
    return data['message']?.toString();
  }

  /// `DELETE integrations/{platform}` — drops the brand's stored tokens.
  Future<void> disconnectIntegration(String platform, int? brandId) async {
    _integrationOk(await _api.delete('/integrations/$platform', body: brandId == null ? null : {'brand_id': brandId}));
  }

  // ── Guards ───────────────────────────────────────────────────────────────

  /// ⚠️ A 200 CAN STILL BE A FAILURE: `status: false` / `"error"` arrives on a
  /// 200 and would otherwise read as an empty list or a missing reply.
  static dynamic _assertOk(ApiResult res, String fallback) {
    if (!res.ok) throw CopilotFailure.from(res);
    final body = res.raw;
    if (body is Map && (body['status'] == false || body['status'] == 'error')) {
      throw CopilotFailure(status: res.status, detail: '${body['message'] ?? body['error'] ?? fallback}');
    }
    return body;
  }

  /// The integrations helpers also treat `success: false` as a refusal, and
  /// lead with the first validation message.
  static Map<String, dynamic> _integrationOk(ApiResult res) {
    final body = res.body;
    if (!res.ok || body['status'] == 'error' || body['success'] == false) {
      final errors = body['errors'];
      String? first;
      if (errors is Map && errors.isNotEmpty) {
        final v = errors.values.first;
        first = v is List && v.isNotEmpty ? '${v.first}' : '$v';
      }
      throw CopilotFailure(
        status: res.status,
        detail: first ?? body['message']?.toString() ?? 'Request failed (HTTP ${res.status ?? '—'}).',
      );
    }
    return body;
  }
}

/// Port of `describeApiError` — a failed request in the server's own words.
///
/// ⚠️ IT REPORTS THE SERVER'S OWN SENTENCE. While the backend is half-deployed
/// "Target class [CopilotController] does not exist" is the line that tells the
/// backend dev what's missing; paraphrasing it would throw that away.
class CopilotFailure implements Exception {
  const CopilotFailure({this.status, required this.detail, this.fields = const []});

  factory CopilotFailure.from(ApiResult res) {
    final raw = res.raw;
    final detail =
        (raw is String && raw.isNotEmpty ? raw : null) ??
        (raw is Map ? (raw['message'] ?? raw['error'])?.toString() : null) ??
        res.messageForDevs ??
        'Request failed';
    return CopilotFailure(
      status: res.status,
      detail: detail.length > 600 ? '${detail.substring(0, 600)}…' : detail,
      fields: res.errors?.keys.toList() ?? const [],
    );
  }

  /// A thrown non-API error (a missing name, a decode failure).
  factory CopilotFailure.of(Object error) =>
      error is CopilotFailure ? error : CopilotFailure(detail: '$error'.replaceFirst('Exception: ', ''));

  final int? status;
  final String detail;
  final List<String> fields;

  /// "500 — Target class … — Fields: name"
  String get text => [
    status != null ? '$status' : 'Network error',
    detail,
    if (fields.isNotEmpty) 'Fields: ${fields.join(', ')}',
  ].join(' — ');

  @override
  String toString() => text;
}

/// The copilot's words out of a reply whose shape is not settled — the last
/// resort is the raw JSON, so a reply under an unguessed key is still visible.
String replyTextFrom(dynamic data) {
  if (data is Map) {
    for (final k in ['reply', 'response', 'message', 'text']) {
      final v = data[k];
      if (v is String) return v;
    }
    final inner = data['data'];
    if (inner is Map && inner['reply'] is String) return inner['reply'] as String;
  }
  if (data == null) return 'Empty response.';
  if (data is String) return data;
  return const JsonEncoder.withIndent('  ').convert(data);
}
