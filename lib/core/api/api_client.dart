import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'api_result.dart';

/// Thin wrapper over Dio — the Flutter counterpart of the web app's
/// `authFetch` (AuthContext.jsx).
///
/// Never throws: every call resolves to an [ApiResult]. Statuses are not
/// treated as exceptions (`validateStatus` accepts all), so a 422 or 500 is
/// classified the same way the web helper does it.
///
/// A 401 on an authenticated call fires [onUnauthorized], which the auth
/// controller uses to drop the session — the web app does the same globally.
class ApiClient {
  ApiClient({required this.tokenProvider});

  /// Reads the current bearer token at request time.
  final String? Function() tokenProvider;

  /// Called when an authenticated request comes back 401.
  VoidCallback? onUnauthorized;

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      // Plain text so ApiResult can tell JSON from an HTML error page itself.
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      // Laravel only answers auth failures with a JSON 401 when the request
      // expects JSON — without this it redirects to a login page instead.
      headers: {'Accept': 'application/json'},
    ),
  );

  Future<ApiResult> get(String path, {Map<String, dynamic>? query, bool auth = true}) =>
      _send('GET', path, query: query, auth: auth);

  /// [timeout] overrides the 60s receive timeout for slow AI calls; [cancel]
  /// lets a Stop button abandon the request (it resolves as a network result).
  Future<ApiResult> post(String path, {Object? body, bool auth = true, Duration? timeout, CancelToken? cancel}) =>
      _send('POST', path, body: body, auth: auth, timeout: timeout, cancel: cancel);

  Future<ApiResult> put(String path, {Object? body, bool auth = true}) => _send('PUT', path, body: body, auth: auth);

  Future<ApiResult> patch(String path, {Object? body, bool auth = true}) =>
      _send('PATCH', path, body: body, auth: auth);

  Future<ApiResult> delete(String path, {Object? body, Map<String, dynamic>? query, bool auth = true}) =>
      _send('DELETE', path, body: body, query: query, auth: auth);

  Future<ApiResult> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    required bool auth,
    Duration? timeout,
    CancelToken? cancel,
  }) async {
    final token = auth ? tokenProvider() : null;
    try {
      final res = await _dio.request<String>(
        path,
        data: body,
        queryParameters: query,
        cancelToken: cancel,
        options: Options(
          method: method,
          receiveTimeout: timeout,
          contentType: body is FormData ? null : Headers.jsonContentType,
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
      final status = res.statusCode ?? 0;
      if (auth && status == 401) {
        debugPrint('401 on $method $path → session expired');
        onUnauthorized?.call();
      }
      return ApiResult.fromResponse(status, res.data ?? '');
    } on DioException catch (e) {
      debugPrint('❌ $method $path failed before a response: ${e.type} ${e.message}');
      return ApiResult.network(e.message ?? e.type.name);
    }
  }
}
