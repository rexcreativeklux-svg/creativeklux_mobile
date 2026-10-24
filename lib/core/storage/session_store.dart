import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the session between launches — the web app keeps the same two
/// values in localStorage ("token", "user").
///
/// The token goes to the platform keystore; the cached user is not secret and
/// lives in shared preferences so it can be read synchronously-ish on boot.
class SessionStore {
  SessionStore(this._prefs);

  static const _tokenKey = 'token';
  static const _userKey = 'user';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<String?> readToken() => _secure.read(key: _tokenKey);

  Future<void> writeToken(String token) => _secure.write(key: _tokenKey, value: token);

  Map<String, dynamic>? readUser() {
    final raw = _prefs.getString(_userKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeUser(Map<String, dynamic> user) => _prefs.setString(_userKey, jsonEncode(user));

  /// A brand invite opened while signed out — resumed after sign-in
  /// (the web keeps it in localStorage as `ck_pending_invite`).
  String? readPendingInvite() => _prefs.getString(_inviteKey);

  Future<void> writePendingInvite(String? token) =>
      token == null ? _prefs.remove(_inviteKey) : _prefs.setString(_inviteKey, token);

  static const _inviteKey = 'ck_pending_invite';

  Future<void> clear() async {
    await _secure.delete(key: _tokenKey);
    await _prefs.remove(_userKey);
  }
}
