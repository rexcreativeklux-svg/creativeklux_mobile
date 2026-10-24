import 'dart:convert';

/// Port of the web app's `utils/errorHelper.js` → `classifyResult()`.
///
/// Every API call resolves to one of these instead of throwing, so callers get
/// a consistent shape whether the request failed on the network, failed
/// validation, or succeeded.
enum ApiSource { success, network, validation, backend, infra, rateLimit, unknown }

class ApiResult {
  const ApiResult({
    required this.ok,
    required this.source,
    required this.message,
    this.messageForDevs,
    this.errors,
    this.data,
    this.raw,
    this.status,
  });

  final bool ok;
  final ApiSource source;

  /// Safe to show to the user.
  final String message;

  /// Raw backend message — for logs only.
  final String? messageForDevs;

  /// Laravel-style validation errors keyed by field.
  final Map<String, dynamic>? errors;

  /// `body.data ?? body` on success (same as the web helper).
  final dynamic data;

  /// The whole decoded body (or raw text when it wasn't JSON).
  final dynamic raw;

  /// HTTP status, or null when the request never got a response.
  final int? status;

  /// Decoded body as a map, or an empty map when it isn't one.
  Map<String, dynamic> get body => raw is Map<String, dynamic> ? raw as Map<String, dynamic> : const {};

  static const _generic = {
    ApiSource.network: 'Connection problem. Please try again.',
    ApiSource.validation: 'Please check the form fields.',
    ApiSource.backend: 'Something went wrong on our end. Please try again.',
    ApiSource.infra: 'Service temporarily unavailable. Please try again shortly.',
    ApiSource.unknown: 'An unexpected error occurred.',
  };

  /// The request threw before any response arrived (offline, DNS, timeout).
  factory ApiResult.network(String devMessage) => ApiResult(
    ok: false,
    source: ApiSource.network,
    message: _generic[ApiSource.network]!,
    messageForDevs: devMessage,
  );

  /// Classify a response the same way the web app does.
  factory ApiResult.fromResponse(int status, String text) {
    final isOk = status >= 200 && status < 300;

    dynamic data;
    var parsed = false;
    try {
      data = text.isEmpty ? null : jsonDecode(text);
      parsed = true;
    } catch (_) {}

    // Non-JSON body (proxy error page or plain text).
    if (!parsed) {
      if (isOk) {
        return ApiResult(ok: true, source: ApiSource.success, message: 'OK', data: text, raw: text, status: status);
      }
      final isInfra = (status >= 502 && status <= 504) || (status >= 520 && status <= 530);
      final source = isInfra ? ApiSource.infra : ApiSource.unknown;
      return ApiResult(
        ok: false,
        source: source,
        message: _generic[source]!,
        messageForDevs: 'HTTP $status non-JSON response',
        raw: text,
        status: status,
      );
    }

    final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    final backendMessage = map['message']?.toString();

    if (isOk) {
      return ApiResult(
        ok: true,
        source: ApiSource.success,
        message: backendMessage ?? 'OK',
        data: map['data'] ?? data,
        raw: data,
        status: status,
      );
    }

    if (status == 401) {
      return ApiResult(
        ok: false,
        source: ApiSource.network,
        message: 'You need to sign in again.',
        messageForDevs: backendMessage ?? 'Unauthorized',
        raw: data,
        status: status,
      );
    }

    // Quota / rate limit — may arrive as a real 429 or wrapped in a 5xx.
    final backendText = '${backendMessage ?? ''} ${map['error'] ?? ''}'.toLowerCase();
    if (status == 429 ||
        backendText.contains('quota') ||
        backendText.contains('(429)') ||
        backendText.contains('rate limit') ||
        backendText.contains('rate_limit')) {
      return ApiResult(
        ok: false,
        source: ApiSource.rateLimit,
        message: 'You exceeded your current quota, please check your plan and billing details',
        messageForDevs: backendMessage ?? map['error']?.toString() ?? 'HTTP $status quota/rate-limit',
        raw: data,
        status: status,
      );
    }

    // Laravel validation.
    final errors = map['errors'];
    if (status == 422 || errors is Map) {
      final errMap = errors is Map ? Map<String, dynamic>.from(errors) : <String, dynamic>{};
      String? firstMsg;
      if (errMap.isNotEmpty) {
        final first = errMap.values.first;
        firstMsg = first is List && first.isNotEmpty ? first.first.toString() : first?.toString();
      }
      return ApiResult(
        ok: false,
        source: ApiSource.validation,
        message: firstMsg ?? backendMessage ?? _generic[ApiSource.validation]!,
        messageForDevs: backendMessage ?? 'Validation failed',
        errors: errMap,
        raw: data,
        status: status,
      );
    }

    if (status >= 500) {
      return ApiResult(
        ok: false,
        source: ApiSource.backend,
        message: _generic[ApiSource.backend]!,
        messageForDevs: backendMessage ?? map['error']?.toString() ?? 'HTTP $status',
        raw: data,
        status: status,
      );
    }

    return ApiResult(
      ok: false,
      source: ApiSource.backend,
      message: backendMessage ?? 'Request failed.',
      messageForDevs: backendMessage ?? map['error']?.toString() ?? 'HTTP $status',
      raw: data,
      status: status,
    );
  }
}
