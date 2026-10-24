import 'package:flutter/foundation.dart';

import 'api_result.dart';

/// A user-safe error: [message] can go straight into a toast.
/// Port of the Error objects thrown by `utils/authErrors.js`.
class AppException implements Exception {
  AppException(this.message, {this.source, this.status, this.messageForDevs, this.field});

  final String message;
  final ApiSource? source;
  final int? status;
  final String? messageForDevs;

  /// Set when the error belongs to one form field (e.g. "email").
  final String? field;

  @override
  String toString() => message;
}

final _technicalPatterns = <RegExp>[
  RegExp(r'endpoint not found', caseSensitive: false),
  RegExp(r'\bnot\s*found\b', caseSensitive: false),
  RegExp(r'failed to fetch', caseSensitive: false),
  RegExp(r'load failed', caseSensitive: false),
  RegExp(r'network\s*error', caseSensitive: false),
  RegExp(r'socketexception', caseSensitive: false),
  RegExp(r'\bcors\b', caseSensitive: false),
  RegExp(r'unexpected token', caseSensitive: false),
  RegExp(r'is not valid json', caseSensitive: false),
  RegExp(r'invalid response', caseSensitive: false),
  RegExp(r'unexpected server response', caseSensitive: false),
  RegExp(r'<!doctype', caseSensitive: false),
  RegExp(r'<html', caseSensitive: false),
  RegExp(r'internal server error', caseSensitive: false),
  RegExp(r'bad gateway', caseSensitive: false),
  RegExp(r'service unavailable', caseSensitive: false),
  RegExp(r'timeout', caseSensitive: false),
  RegExp(r'\b(4\d{2}|5\d{2})\b'),
];

/// Port of `toUserMessage()` — passes readable backend messages through and
/// masks technical ones with [fallback].
String toUserMessage(Object? error, [String fallback = 'Something went wrong. Please try again.']) {
  final raw = (error is AppException ? error.message : error?.toString() ?? '').trim();
  if (raw.isEmpty) return fallback;
  if (_technicalPatterns.any((re) => re.hasMatch(raw))) return fallback;
  return raw;
}

/// Port of `throwClassifiedAuthError()` — turns a failed [ApiResult] into a
/// user-safe [AppException] that never blames credentials for a network or
/// server fault.
Never throwClassified(String context, ApiResult result, String fallback, {bool showBackendMessage = false}) {
  final status = result.status;
  final devMsg = result.messageForDevs ?? result.message;
  final isTransport = status == null;

  debugPrint(
    isTransport
        ? '❌ $context — couldn\'t reach the server. Raw: $devMsg'
        : '❌ $context failed [${result.source.name}] (HTTP $status): $devMsg',
  );

  String userMessage;
  if (isTransport) {
    userMessage = "We couldn't reach the server. Please check your connection and try again.";
  } else if (result.source == ApiSource.rateLimit) {
    userMessage = result.message;
  } else if (status >= 500) {
    const generic = 'Something went wrong on our end. Please try again shortly.';
    final backendMsg = result.messageForDevs ?? '';
    userMessage = showBackendMessage && !RegExp(r'sqlstate|exception', caseSensitive: false).hasMatch(backendMsg)
        ? toUserMessage(backendMsg, generic)
        : generic;
  } else if (result.source == ApiSource.validation) {
    final all = (result.errors ?? {}).values
        .expand((v) => v is List ? v : [v])
        .where((v) => v != null && v.toString().isNotEmpty)
        .map((v) => v.toString())
        .toList();
    userMessage = all.isNotEmpty ? all.join(', ') : result.message;
  } else {
    final raw = (result.messageForDevs ?? '').trim();
    userMessage = raw.isNotEmpty && raw.toLowerCase() != 'unauthorized' ? raw : fallback;
  }

  throw AppException(userMessage, source: result.source, status: status, messageForDevs: devMsg);
}
