import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';
import '../../core/api/app_exception.dart';
import 'brand.dart';

/// Brand endpoints — the brand functions from the web's `AuthContext.jsx`
/// (create/update/delete/import, logo upload) plus `brand/manage/lib/useManageApi.js`
/// (members, invites, allocations, AI keys).
///
/// Everything returns [ApiResult]; screens decide what to toast.
class BrandApi {
  BrandApi(this._api);

  final ApiClient _api;

  // ── Brand CRUD ────────────────────────────────────────────────────────────

  /// Smart Import — scrape a website into brand fields.
  /// The fields come back on `data.data` or `data`.
  Future<ApiResult> importFromUrl(String url) => _api.post('/brands/import', body: {'url': url});

  Future<ApiResult> create(Map<String, dynamic> payload) => _api.post('/brands', body: payload);

  Future<Brand?> fetchById(int id) async {
    final res = await _api.get('/brands/$id');
    if (!res.ok) return null;
    return Brand.tryParse(res.body['data'] is Map ? res.body['data'] : res.body);
  }

  /// Multipart POST with `_method=PUT` (Laravel method spoofing), like the web.
  /// [logo] is only sent when it's a new hosted URL — otherwise the backend
  /// keeps the existing logo.
  Future<ApiResult> update(
    int id, {
    required String name,
    String? description,
    String? tagline,
    String? fonts,
    String? industry,
    String? logo,
    String? primaryColor,
    String? secondaryColor,
  }) {
    final form = FormData.fromMap({
      'name': name,
      'description': description ?? '',
      'tagline': tagline ?? '',
      'fonts': fonts ?? '',
      // The web forgets to send this (so Industry edits are lost there); we send it.
      'industry': ?industry,
      if (logo != null && logo.isNotEmpty) 'logo': logo,
      'primary_color': primaryColor ?? '#1e3a8a',
      'secondary_color': secondaryColor ?? '#10b981',
      '_method': 'PUT',
    });
    return _api.post('/brands/$id', body: form);
  }

  Future<ApiResult> delete(int id) => _api.delete('/brands/$id');

  /// Upload an image to the user's gallery (`POST /gallery`) and return its
  /// hosted URL — how the web uploads brand logos.
  Future<String?> uploadImage(List<int> bytes, String filename) async {
    final res = await _api.post(
      '/gallery',
      body: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)}),
    );
    if (!res.ok) throwClassified('uploadImage', res, "Couldn't upload your logo. Please try again.");
    return extractImageUrl(res.body);
  }

  /// First of image / image_url / url / file_url / path / src, top level then
  /// under `data` or `file` (port of `brand/create/components/helpers.js`).
  static String? extractImageUrl(Map<String, dynamic> body) {
    const keys = ['image', 'image_url', 'url', 'file_url', 'path', 'src'];
    for (final source in [body, body['data'], body['file']]) {
      if (source is! Map) continue;
      for (final k in keys) {
        final v = source[k];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  // ── Accepting an invite (/invites/:token) ─────────────────────────────────

  /// Public route; the Bearer token rides along only when signed in.
  /// Data: `{brand:{id,name,logo}, invited_by:{id,name,email}, role, type, expires_at}`.
  Future<ApiResult> invite(String token) => _api.get('/brand-invite/$token');

  Future<ApiResult> acceptInvite(String token) => _api.post('/brand-invite/$token/accept');

  /// The joined brand id, from whichever key the accept response used.
  static int? joinedBrandId(Map<String, dynamic> body) {
    final data = body['data'] is Map ? body['data'] as Map : const {};
    for (final v in [
      (body['brand'] as Map?)?['id'],
      body['brand_id'],
      (data['brand'] as Map?)?['id'],
      data['brand_id'],
    ]) {
      final id = int.tryParse('${v ?? ''}');
      if (id != null) return id;
    }
    return null;
  }

  // ── Members & invites ─────────────────────────────────────────────────────

  Future<ApiResult> members(int brandId) => _api.get('/brands/$brandId/members');

  Future<ApiResult> inviteByEmail(int brandId, String email, String role) =>
      _api.post('/brands/$brandId/members/invite-email', body: {'email': email, 'role': role});

  Future<ApiResult> updateMemberRole(int brandId, Object memberId, String role) =>
      _api.patch('/brands/$brandId/members/$memberId/role', body: {'role': role});

  Future<ApiResult> removeMember(int brandId, Object memberId) => _api.delete('/brands/$brandId/members/$memberId');

  Future<ApiResult> leave(int brandId) => _api.post('/brands/$brandId/leave');

  Future<ApiResult> inviteLinks(int brandId) => _api.get('/brands/$brandId/members/invites');

  Future<ApiResult> createInviteLink(int brandId, String role, int maxUses) =>
      _api.post('/brands/$brandId/members/invite-link', body: {'role': role, 'max_uses': maxUses});

  Future<ApiResult> deleteInviteLink(int brandId, Object inviteId) =>
      _api.delete('/brands/$brandId/members/invites/$inviteId');

  // ── Allocation ────────────────────────────────────────────────────────────

  /// Body key is `{field}_allocation` — a bare `allocation` is rejected.
  Future<ApiResult> updateAllocation(int brandId, String slug, String field, num value) =>
      _api.patch('/brands/$brandId/allocations/$slug', body: {'${field}_allocation': value});

  // ── AI keys (bring your own key) ──────────────────────────────────────────

  Future<ApiResult> aiCredentials(int brandId) => _api.get('/ai-credentials', query: {'brand_id': brandId});

  Future<ApiResult> saveAiCredential({
    required int brandId,
    required String capability,
    required String provider,
    required String apiKey,
    String? model,
    required bool activate,
  }) => _api.post(
    '/ai-credentials',
    body: {
      'brand_id': brandId,
      'capability': capability,
      'provider': provider,
      'api_key': apiKey,
      if (model != null && model.isNotEmpty) 'model': model,
      'activate': activate,
    },
  );

  Future<ApiResult> activateAiCredential(int brandId, Object credId) =>
      _api.post('/ai-credentials/$credId/activate', body: {'brand_id': brandId});

  Future<ApiResult> verifyAiCredential(int brandId, Object credId) =>
      _api.post('/ai-credentials/$credId/verify', body: {'brand_id': brandId});

  Future<ApiResult> revertToSystemKey(int brandId, String capability) =>
      _api.delete('/ai-credentials/system/$capability', query: {'brand_id': brandId});

  Future<ApiResult> deleteAiCredential(int brandId, Object credId) =>
      _api.delete('/ai-credentials/$credId', query: {'brand_id': brandId});
}
