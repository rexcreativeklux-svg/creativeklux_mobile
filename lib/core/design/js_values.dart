/// Small helpers for reading design JSON with the web's JavaScript semantics.
///
/// The layout JSON is written by JS, and the web renderer leans on JS's loose
/// rules (`el.fontSize || 16`, `if (el.hidden)`, `Number("12")`). Reproducing
/// them in one place keeps the Dart port's branches reading like the original.
library;

/// JS truthiness: null, false, 0, NaN and '' are falsy.
bool truthy(Object? v) {
  if (v == null || v == false) return false;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  return true;
}

/// `Number(v)` for numbers and numeric strings; null otherwise.
double? numOf(Object? v) {
  if (v is num) return v.isNaN ? null : v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  if (v is bool) return v ? 1 : 0;
  return null;
}

/// `v || fallback` for a number: missing, zero or junk → fallback.
double orNum(Object? v, double fallback) {
  final n = numOf(v);
  return (n == null || n == 0) ? fallback : n;
}

/// `v ?? fallback` for a number: only missing (or unreadable) → fallback.
double nnNum(Object? v, double fallback) => numOf(v) ?? fallback;

/// JS `Math.round`: halves round toward +infinity (Dart's `round` goes away
/// from zero, which differs for negative halves like -45.5).
int jsRound(double v) => (v + 0.5).floor();

/// A map view of a JSON object, or null.
Map<String, dynamic>? asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry('$k', val));
  return null;
}
