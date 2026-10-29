import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';
import '../../core/api/app_exception.dart';
import '../brand/brand_api.dart';

/// The settings pages' API calls — on the web they're spread over
/// AuthContext.jsx (updateProfile, uploadMedia, inviteTeamMember, fetchTeams,
/// handleDeleteTeam, fetchResells, createResell, deleteResell) and inline
/// `fetch`es in the pages themselves (password, sessions, delete account,
/// apply-promotion-code).
///
/// Every method throws an [AppException] whose message can go straight into a
/// toast, so the screens only have one failure path to handle.
class SettingsApi {
  SettingsApi(this._api);

  final ApiClient _api;

  // ── Profile (profile/page.jsx) ────────────────────────────────────────────

  /// `POST /profile` with any subset of fields (`{name}`, `{profile_pic}`…) —
  /// there is no per-field endpoint (AuthContext `updateProfile`). The caller
  /// re-reads the profile afterwards so the whole app sees the change.
  Future<String> updateProfile(Map<String, dynamic> payload) async {
    final res = await _api.post('/profile', body: payload);
    if (!res.ok) throwClassified('updateProfile', res, "Couldn't update your profile.", showBackendMessage: true);
    return res.body['message']?.toString() ?? 'Profile updated.';
  }

  /// Upload a picture to `POST /gallery` and return its hosted URL — the web's
  /// `uploadMedia` + `pickUploadedUrl` (the same URL-only pattern brand logos
  /// use). Null when the server answered without a URL.
  Future<String?> uploadImage(List<int> bytes, String filename) async {
    final res = await _api.post(
      '/gallery',
      body: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)}),
    );
    if (!res.ok) throwClassified('uploadImage', res, "Couldn't upload your photo. Please try again.");
    return BrandApi.extractImageUrl(res.body);
  }

  /// ⚠️ Unconfirmed endpoint (a to-do on the web too): `PUT /profile/{id}` with
  /// `{current_password, new_password}` is the web's best guess at the userend
  /// route, not a confirmed endpoint.
  Future<void> changePassword(Object userId, String current, String next) async {
    final res = await _api.put('/profile/$userId', body: {'current_password': current, 'new_password': next});
    if (!res.ok) throwClassified('changePassword', res, "Couldn't update your password. Please try again.");
  }

  /// ⚠️ Unconfirmed endpoint (a to-do on the web): `GET /profile/sessions` → `{sessions: [...]}`.
  /// Each session: `{id, device, browser, location, date?, current?}`.
  Future<List<Map<String, dynamic>>> sessions() async {
    final res = await _api.get('/profile/sessions');
    if (!res.ok) throwClassified('sessions', res, "Couldn't load your sessions.");
    return _mapList(res.body['sessions']);
  }

  /// ⚠️ Unconfirmed endpoint (a to-do on the web): `DELETE /profile/sessions/{id}`.
  Future<void> terminateSession(Object id) async {
    final res = await _api.delete('/profile/sessions/$id');
    if (!res.ok) throwClassified('terminateSession', res, 'Failed to terminate session.');
  }

  /// ⚠️ Unconfirmed endpoint (a to-do on the web): `DELETE /profile/delete/{id}`.
  Future<void> deleteAccount(Object userId) async {
    final res = await _api.delete('/profile/delete/$userId');
    if (!res.ok) throwClassified('deleteAccount', res, "Couldn't delete your account. Please try again.");
  }

  // ── Team (team/page.jsx + TeamsList.jsx) ──────────────────────────────────

  /// `GET /teams` → `{teams: [...]}`. Each member: `{id, name, email, phone,
  /// role, status (string or 1/0), custom_domain}`.
  Future<List<Map<String, dynamic>>> teams() async {
    final res = await _api.get('/teams');
    if (!res.ok) throwClassified('teams', res, "Couldn't load your team.");
    return _mapList(res.body['teams']);
  }

  /// `POST /teams {email}`. The web throws `data.error || data.message`.
  Future<void> inviteTeamMember(String email) async {
    final res = await _api.post('/teams', body: {'email': email});
    if (!res.ok) _throwWith('inviteTeamMember', res, 'Could not send invitation.');
  }

  /// `DELETE /teams/{id}` → the server's message, if any.
  Future<String?> removeTeamMember(Object id) async {
    final res = await _api.delete('/teams/$id');
    if (!res.ok) _throwWith('removeTeamMember', res, 'Failed to remove member.');
    return res.body['message']?.toString();
  }

  // ── Resell (resell/page.jsx) ──────────────────────────────────────────────

  /// `GET /resells` → `data.resells || data` (the web accepts either shape).
  /// Each row: `{id, name, email, status (1/0/other), created_at}`.
  Future<List<Map<String, dynamic>>> resells() async {
    final res = await _api.get('/resells');
    if (!res.ok) throwClassified('resells', res, 'Failed to load resell accounts.');
    final raw = res.raw;
    if (raw is List) return _mapList(raw);
    if (raw is Map) return _mapList(raw['resells'] ?? raw['data']);
    return const [];
  }

  /// `POST /resells {email}`.
  Future<void> createResell(String email) async {
    final res = await _api.post('/resells', body: {'email': email});
    if (!res.ok) _throwWith('createResell', res, 'Could not send invitation.');
  }

  /// `DELETE /resells/{id}`.
  Future<void> deleteResell(Object id) async {
    final res = await _api.delete('/resells/$id');
    if (!res.ok) _throwWith('deleteResell', res, 'Failed to remove resell account.');
  }

  // ── Billing (billing/page.jsx) ────────────────────────────────────────────

  /// `POST /apply-promotion-code {code}` → the newly-active package (the
  /// `data` object, same shape as `GET /package`). A 200 without
  /// `success: true` is still a refusal, as on the web.
  Future<Map<String, dynamic>> applyPromotionCode(String code) async {
    final res = await _api.post('/apply-promotion-code', body: {'code': code});
    final data = res.body['data'];
    if (!res.ok || res.body['success'] != true || data is! Map<String, dynamic>) {
      debugPrint('❌ applyPromotionCode failed (HTTP ${res.status}): ${res.messageForDevs ?? res.message}');
      final msg = res.body['message']?.toString();
      throw AppException(
        res.status == null
            ? "We couldn't reach the server. Please check your connection and try again."
            : toUserMessage(msg, "That code isn't recognised. Check it and try again."),
        status: res.status,
      );
    }
    return data;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// The web's team/resell calls throw the server's own words
  /// (`data.error || data.message`), so pass those through when readable.
  Never _throwWith(String context, ApiResult res, String fallback) {
    final body = res.body;
    final own = (body['error'] ?? body['message'])?.toString();
    if (res.status != null && res.status! < 500 && own != null && own.isNotEmpty && res.errors == null) {
      debugPrint('❌ $context failed (HTTP ${res.status}): $own');
      throw AppException(toUserMessage(own, fallback), status: res.status);
    }
    throwClassified(context, res, fallback);
  }

  static List<Map<String, dynamic>> _mapList(Object? v) => [
    if (v is List)
      for (final e in v)
        if (e is Map) Map<String, dynamic>.from(e),
  ];
}
