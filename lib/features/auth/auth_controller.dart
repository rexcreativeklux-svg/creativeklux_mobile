import 'package:flutter/widgets.dart';

import '../../core/api/api_client.dart';
import '../../core/api/app_exception.dart';
import '../../core/storage/session_store.dart';
import '../../core/ui/toast.dart';
import '../brand/brand.dart';
import '../brand/brand_api.dart';

/// The Flutter counterpart of the web app's `AuthProvider`
/// (`src/context/AuthContext.jsx`): session, profile, brands, active package.
///
/// Feature-specific API calls (gallery, teams, creatives…) do NOT go here —
/// the web file grew to 4,000 lines that way. Each feature gets its own
/// repository that takes the shared [ApiClient].
class AuthController extends ChangeNotifier {
  AuthController(this._store) {
    api = ApiClient(tokenProvider: () => _token)..onUnauthorized = _handleUnauthorized;
    // Back in the app after the brands failed to load (phone woke up offline,
    // say)? Try again without making the user find a button.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (_token != null && _brandsFailed && !_brandsLoading) fetchBrands();
      },
    );
  }

  late final AppLifecycleListener _lifecycle;

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  final SessionStore _store;
  late final ApiClient api;

  /// Brand endpoints, sharing this session's client.
  late final BrandApi brandApi = BrandApi(api);

  String? _token;
  Map<String, dynamic>? _user;
  bool _loading = true;

  List<Brand> _brands = const [];
  bool _brandsLoading = true;

  /// The last brands request failed (network, server). Not the same as "no
  /// brands": the gate must offer Retry, never "Create your first brand" —
  /// that invited a duplicate brand whenever the phone woke up offline.
  bool _brandsFailed = false;
  Brand? _activeBrand;
  int? _switchingBrandId;

  Map<String, dynamic>? _activePackage;
  bool _packageLoading = true;

  /// Set by [register] so [verifyEmail] can send `user_id` (the web keeps it
  /// in sessionStorage as "pendingUserId").
  String? _pendingUserId;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _token != null;

  /// True until the stored session has been confirmed (or ruled out).
  bool get loading => _loading;

  List<Brand> get brands => _brands;
  bool get brandsLoading => _brandsLoading;
  bool get brandsFailed => _brandsFailed;
  Brand? get activeBrand => _activeBrand;
  int? get switchingBrandId => _switchingBrandId;

  Map<String, dynamic>? get activePackage => _activePackage;
  bool get packageLoading => _packageLoading;

  /// `/profile` sends `is_email_verified` and/or `email_verified_at`.
  bool get isVerified =>
      _user != null && (_user!['is_email_verified'] == true || (_user!['email_verified_at'] ?? '') != '');

  String get username => (_user?['username'] ?? _user?['name'] ?? '').toString();
  String get email => (_user?['email'] ?? '').toString();

  /// Port of `packageToSubscription(pkg).planName` (billing/billingData.js).
  String get planName {
    final name = _activePackage?['name']?.toString();
    if (_activePackage == null) return 'Free plan';
    if (name == null || name.isEmpty) return 'Current plan';
    return RegExp(r'plan|package|tier|subscription', caseSensitive: false).hasMatch(name) ? name : '$name plan';
  }

  // ── Boot ──────────────────────────────────────────────────────────────────

  /// Restore a stored session. Mirrors the two mount effects in AuthContext.
  Future<void> restore() async {
    final stored = await _store.readToken();
    if (stored == null) {
      _loading = false;
      _brandsLoading = false;
      _packageLoading = false;
      notifyListeners();
      return;
    }
    _token = stored;
    _user = _store.readUser();
    notifyListeners();
    await _bootstrap();
  }

  /// Profile → brands → package. A FAILED profile read keeps the skeleton up
  /// until brands answers too, so an expired session goes straight to /login
  /// instead of flashing the dashboard first (see the note in AuthContext).
  Future<void> _bootstrap() async {
    final profile = await fetchProfile();
    if (_token == null) return; // 401 already cleared the session
    if (profile != null) _setLoading(false);
    await fetchBrands();
    _setLoading(false);
    await fetchPackage();
  }

  Future<void> _saveToken(String token) async {
    final changed = token != _token;
    _token = token;
    await _store.writeToken(token);
    if (changed) {
      _loading = true;
      notifyListeners();
      await _bootstrap();
    }
  }

  void _setLoading(bool value) {
    if (_loading == value) return;
    _loading = value;
    notifyListeners();
  }

  void _handleUnauthorized() {
    if (_token == null) return;
    _clearSession();
  }

  void _clearSession() {
    _token = null;
    _user = null;
    _brands = const [];
    _brandsFailed = false;
    _activeBrand = null;
    _activePackage = null;
    _loading = false;
    _brandsLoading = false;
    _packageLoading = false;
    _store.clear();
    notifyListeners();
  }

  // ── Profile & package ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> fetchProfile() async {
    final res = await api.get('/profile');
    if (!res.ok) {
      // Don't log out on a failed read — only a 401 does that (handled globally).
      debugPrint('Profile fetch failed: ${res.messageForDevs}');
      return null;
    }
    final data = res.body;
    _user = data;
    await _store.writeUser(data);
    notifyListeners();
    return data;
  }

  Future<void> fetchPackage() async {
    final res = await api.get('/package');
    if (res.ok && res.body['success'] == true && res.body['data'] is Map<String, dynamic>) {
      _activePackage = res.body['data'] as Map<String, dynamic>;
    } else {
      debugPrint('Package fetch failed: ${res.messageForDevs ?? res.message}');
    }
    _packageLoading = false;
    notifyListeners();
  }

  // ── Brands ────────────────────────────────────────────────────────────────

  Future<List<Brand>> fetchBrands() async {
    if (_token == null) return const [];
    _brandsLoading = true;
    notifyListeners();

    final res = await api.get('/brands');
    if (!res.ok) {
      if (res.status != 401) Toast.error("Couldn't load brands. Please try again later.");
      // Keep whatever loaded last time — a dropped connection says nothing
      // about the brands themselves.
      _brandsFailed = true;
    } else {
      _brandsFailed = false;
      final list = res.body['data'];
      _brands = list is List ? list.map(Brand.tryParse).whereType<Brand>().toList() : const [];

      // The user's saved `active_brand_id` is the single source of truth.
      final preferred = int.tryParse('${_user?['active_brand_id'] ?? ''}');
      _activeBrand = preferred == null ? null : _brands.where((b) => b.id == preferred).firstOrNull;
    }

    _brandsLoading = false;
    notifyListeners();
    return _brands;
  }

  /// Brand invite token waiting for the user to sign in (see /invites/:token).
  String? get pendingInvite => _store.readPendingInvite();

  Future<void> setPendingInvite(String? token) async {
    await _store.writePendingInvite(token);
    notifyListeners();
  }

  /// Drop the local active brand without a network call (after leaving or
  /// deleting it) — the brand gate then asks the user to pick another.
  void clearActiveBrand() {
    _activeBrand = null;
    notifyListeners();
  }

  /// Switch the active brand via `POST /brands/{id}/switch`. The UI only flips
  /// once the backend confirms. Returns true on success.
  Future<bool> setActiveBrand(Brand brand) async {
    if (_activeBrand?.id == brand.id) return true;

    _switchingBrandId = brand.id;
    notifyListeners();
    try {
      final res = await api.post('/brands/${brand.id}/switch');
      if (!res.ok) {
        Toast.error(res.message.isNotEmpty ? res.message : "Couldn't switch brand. Please try again.");
        return false;
      }
      _activeBrand = brand;
      _user = {...?_user, 'active_brand_id': brand.id};
      await _store.writeUser(_user!);
      Toast.success('Switched to ${brand.name ?? 'your brand'}.');
      return true;
    } finally {
      _switchingBrandId = null;
      notifyListeners();
    }
  }

  // ── Auth flows ────────────────────────────────────────────────────────────

  /// Returns the success message to toast.
  Future<String> login(String email, String password) async {
    final res = await api.post('/login', body: {'email': email, 'password': password}, auth: false);
    if (!res.ok) throwClassified('login', res, 'Invalid email or password.');

    final token = res.body['token']?.toString();
    if (token == null || token.isEmpty) {
      throw AppException('Signed in, but no session token was returned. Please try again.', status: res.status);
    }
    await _saveToken(token);
    return res.body['message']?.toString() ?? 'Login successful';
  }

  Future<String> register(String name, String email, String password, String licenseCode) async {
    final res = await api.post(
      '/register',
      body: {
        'name': name,
        'email': email,
        'password': password,
        'license_code': licenseCode.isEmpty ? null : licenseCode,
      },
      auth: false,
    );
    if (!res.ok) throwClassified('register', res, 'Registration failed. Please try again.');

    final user = res.body['user'];
    final id = (user is Map ? (user['id'] ?? user['user_id']) : null) ?? res.body['id'];
    _pendingUserId = id?.toString();
    return res.body['message']?.toString() ?? 'Check your email for the verification code!';
  }

  Future<String> verifyEmail(String code) async {
    final userId = _pendingUserId ?? _user?['id']?.toString();
    if (userId == null) throw AppException('Session expired. Please register again.');

    final res = await api.post('/update-verification-code', body: {'user_id': userId, 'code': code}, auth: false);
    if (!res.ok) {
      throwClassified('verifyEmail', res, 'The code is incorrect or has expired.', showBackendMessage: true);
    }

    _pendingUserId = null;
    final user = res.body['user'];
    if (user is Map<String, dynamic>) {
      _user = user;
      await _store.writeUser(user);
    }
    final token = res.body['token']?.toString();
    if (token != null && token.isNotEmpty) {
      await _saveToken(token);
    } else if (_token != null) {
      // Already signed in (unverified user) — refresh so the gate sees the flag.
      await fetchProfile();
    }
    notifyListeners();
    return res.body['message']?.toString() ?? 'Email verified successfully!';
  }

  Future<void> resendVerificationEmail(String email) async {
    final res = await api.post('/resend-verification-email', body: {'email': email}, auth: false);
    if (!res.ok) {
      throwClassified(
        'resendVerificationEmail',
        res,
        "Couldn't resend the code. Please try again.",
        showBackendMessage: true,
      );
    }
  }

  /// Password reset · step 1 — email a 6-digit code.
  Future<String> sendResetCode(String email) async {
    final res = await api.post('/password/forgot-password', body: {'email': email}, auth: false);
    if (!res.ok) throwClassified('sendResetCode', res, "Couldn't send the code. Please try again.");
    return res.body['message']?.toString() ?? 'Check your email for the reset code.';
  }

  /// Password reset · step 2 — verify the code.
  Future<void> verifyResetCode(String email, String code) async {
    final res = await api.post('/password/verify-reset-code', body: {'email': email, 'code': code}, auth: false);
    if (!res.ok) throwClassified('verifyResetCode', res, 'The code is incorrect or has expired.');
  }

  /// Password reset · step 3 — set the new password.
  Future<String> resetPassword({
    required String email,
    required String code,
    required String password,
    required String passwordConfirmation,
  }) async {
    final res = await api.post(
      '/password/reset-password',
      body: {'email': email, 'code': code, 'password': password, 'password_confirmation': passwordConfirmation},
      auth: false,
    );
    if (!res.ok) throwClassified('resetPassword', res, "Couldn't reset your password. Please try again.");
    return res.body['message']?.toString() ?? 'Your password has been changed successfully.';
  }

  /// Best-effort server logout; the local session is always cleared.
  Future<void> logout() async {
    if (_token != null) {
      final res = await api.post('/logout');
      if (!res.ok) debugPrint('⚠️ logout — server call failed: ${res.messageForDevs}');
    }
    _clearSession();
  }
}
