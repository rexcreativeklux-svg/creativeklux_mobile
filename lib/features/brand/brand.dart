import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme/app_colors.dart';

/// One brand from `GET /brands` / `GET /brands/{id}`. The full payload stays
/// on [raw] (allocations, timestamps, anything not typed here).
class Brand {
  const Brand({
    required this.id,
    required this.raw,
    this.name,
    this.logo,
    this.primaryColor,
    this.secondaryColor,
    this.description,
    this.tagline,
    this.industry,
    this.fonts,
    this.url,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String? name;
  final String? logo;
  final String? primaryColor;
  final String? secondaryColor;
  final String? description;
  final String? tagline;
  final String? industry;
  final String? fonts;
  final String? url;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> raw;

  static String? _str(dynamic v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }

  static Brand? tryParse(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'] is num ? (json['id'] as num).toInt() : int.tryParse('${json['id']}');
    if (id == null) return null;
    return Brand(
      id: id,
      raw: json,
      name: _str(json['name']),
      logo: _str(json['logo']),
      primaryColor: _str(json['primary_color']),
      secondaryColor: _str(json['secondary_color']),
      description: _str(json['description']),
      tagline: _str(json['tagline']),
      industry: _str(json['industry']),
      fonts: _str(json['fonts'] ?? json['font']),
      url: _str(json['url']),
      createdAt: DateTime.tryParse('${json['created_at']}'),
      updatedAt: DateTime.tryParse('${json['updated_at']}'),
    );
  }

  // The same display fallbacks as `getDisplayValues()` in Header.jsx / ModalPage.jsx.

  String get displayName => name ?? 'Unknown';

  String get initial => displayName[0].toUpperCase();

  /// Colours can arrive wrapped in backticks from the backend — strip them.
  static String? cleanHex(String? raw) {
    final hex = raw?.replaceAll('`', '').trim() ?? '';
    return RegExp(r'^#[0-9A-F]{6}$', caseSensitive: false).hasMatch(hex) ? hex : null;
  }

  static Color? parseHex(String? raw) {
    final hex = cleanHex(raw);
    return hex == null ? null : Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  Color get color => parseHex(primaryColor) ?? AppColors.brandFallback;

  Color get secondary => parseHex(secondaryColor) ?? const Color(0xFF10B981);

  String get primaryHex => cleanHex(primaryColor) ?? '#1e3a8a';

  String get secondaryHex => cleanHex(secondaryColor) ?? '#10b981';

  /// Absolute logo URL, or null when there's no logo.
  String? get logoUrl => resolveAssetUrl(logo);

  static String? resolveAssetUrl(String? path) {
    final l = path?.trim() ?? '';
    if (l.isEmpty) return null;
    return l.startsWith('http') ? l : '${AppConfig.apiOrigin}${l.startsWith('/') ? '' : '/'}$l';
  }

  /// First ten words of the description, like the web brand picker.
  String get shortDescription {
    final words = (description ?? '').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return 'No description';
    return words.length > 10 ? '${words.take(10).join(' ')} ...' : words.join(' ');
  }

  /// `{field}_allocation` / `{field}_used` from the raw payload.
  num? allocation(String field) => num.tryParse('${raw['${field}_allocation'] ?? ''}');
  num? used(String field) => num.tryParse('${raw['${field}_used'] ?? ''}');
}
