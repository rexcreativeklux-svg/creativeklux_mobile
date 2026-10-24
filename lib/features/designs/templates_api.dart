import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/config.dart';

// Port of the web's app/(components)/studio/templatesApi.js — the Klux
// (public Scraive) template pool behind the home rail's "Templates" tab, plus
// the share-link resolver and the "More like this" picker.
//
// ── THE PUBLIC TEMPLATE ENDPOINT ────────────────────────────────────────────
//   POST https://api.scraive.com/api/design-templates/public-template-fetch
//   body { "type": "image" }            ← required; an empty body returns []
//   →    { "designs": [ …~20 rows… ] }
//
// It is PUBLIC (no token), takes NO filters and NO pagination, and every call
// answers a RANDOM 20 out of a ~200+ library. So it can't be searched or paged
// server-side, and it can't be used to look one template up by slug — that goes
// through the template's own CDN object instead (see fetchTemplateBySlug).
//
// A row carries the full layout (`canvas` + `elements`, Scraive format). Its
// `thumbnail` is NOT a preview — it's the URL of one photo used INSIDE the
// layout — so cards paint the layout and only fall back to that photo.

/// The public template pool. Absolute — this one lives on Scraive, not our API.
const publicTemplatesEndpoint = 'https://api.scraive.com/api/design-templates/public-template-fetch';

/// CDN the web serves its media from (same default as the web's
/// NEXT_PUBLIC_CDN_URL).
const _cdnBase = 'https://d3r8chxzp8ea06.cloudfront.net';

/// Every public template's layout sits under this prefix as
/// `<slug>.json` — the whole library is published by one Scraive account.
/// The web has to proxy this through /api/template-layout because of a
/// CloudFront CORS quirk; a mobile app isn't subject to CORS, so it reads the
/// object straight off the CDN.
const _templateObjectPrefix = 'scraive/templates/30';

/// Where one template's layout lives on the CDN.
String templateLayoutUrl(String slug) => '$_cdnBase/$_templateObjectPrefix/${Uri.encodeComponent(slug.trim())}.json';

/// How many sibling cards the details sheet shows under "More like this".
const relatedDisplayLimit = 3;

/// One template in the card contract `normalizeTemplate()` produces on the web.
/// Display strings are already humanized; the `*Key` fields keep the raw
/// backend values, because saving sends those (`sub_type`), not what the UI shows.
@immutable
class KluxTemplate {
  const KluxTemplate({
    required this.id,
    required this.title,
    required this.canvas,
    required this.elements,
    this.subtitle,
    this.meta,
    this.premium = false,
    this.thumbnail,
    this.slug,
    this.format,
    this.formatKey,
    this.category,
    this.designType,
    this.orientation,
    this.mediaType,
    this.typeSize,
    this.createdAt,
    this.updatedAt,
    this.pricing,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? meta;
  final bool premium;
  final String? thumbnail;
  final Map<String, dynamic> canvas;
  final List<dynamic> elements;

  final String? slug;
  final String? format;
  final String? formatKey;
  final String? category;
  final String? designType;
  final String? orientation;
  final String? mediaType;
  final String? typeSize;
  final String? createdAt;
  final String? updatedAt;

  /// "free" | "premium" | null — lowercased raw value.
  final String? pricing;

  /// Stable key for caches: the slug when there is one (a shared link
  /// resolved off the CDN is keyed by slug, a pool row by numeric id).
  String get cacheKey => slug ?? id;

  bool isSameAs(KluxTemplate other) => other.id == id || (slug != null && other.slug != null && other.slug == slug);
}

// ── Helpers (same names as the web module) ──────────────────────────────────

/// First present, non-empty value from a list of candidate keys.
Object? _pick(Map row, List<String> keys) {
  for (final k in keys) {
    final v = row[k];
    if (v != null && v != '') return v;
  }
  return null;
}

String? _pickStr(Map row, List<String> keys) => _pick(row, keys)?.toString();

/// "instagram_portrait" → "Instagram portrait".
String? humanize(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final spaced = value.replaceAll(RegExp(r'[_-]+'), ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Portrait / Landscape / Square from the canvas.
String? orientationOf(Map<String, dynamic> canvas) {
  final w = num.tryParse('${canvas['width']}') ?? 0;
  final h = num.tryParse('${canvas['height']}') ?? 0;
  if (w == 0 || h == 0) return null;
  if (w == h) return 'Square';
  return h > w ? 'Portrait' : 'Landscape';
}

/// Parse a layout that may arrive as an object or as a JSON string, on any of
/// the keys the backend has used. Returns null when there's nothing to paint.
({Map<String, dynamic> canvas, List<dynamic> elements})? readLayout(Map row) {
  Object? layout = row['canvas'] ?? row['design'] ?? row['data'];
  if (layout is String) {
    try {
      layout = jsonDecode(layout);
    } catch (_) {
      return null;
    }
  }
  if (layout is! Map) return null;

  // Either { canvas: {...}, elements: [...] } or a bare canvas spec next to a
  // sibling `elements` array on the row itself (the shape the pool sends).
  final inner = layout['canvas'];
  final Map? canvas = inner is Map ? inner : (layout['width'] != null && layout['height'] != null ? layout : null);
  final elements = layout['elements'] is List
      ? layout['elements'] as List
      : row['elements'] is List
      ? row['elements'] as List
      : const [];
  if (canvas == null || elements.isEmpty) return null;
  return (canvas: Map<String, dynamic>.from(canvas), elements: elements);
}

/// Map ONE raw pool row onto the card contract. Rows without a usable layout
/// return null — a card with nothing to paint is worse than one card fewer.
KluxTemplate? normalizeTemplate(Object? raw, int index) {
  final row = raw is Map ? raw : const {};
  final layout = readLayout(row);
  if (layout == null) return null;

  final size = _pickStr(row, ['type_size']);
  final category = humanize(_pick(row, ['sub_category', 'category']));
  final pricing = (_pickStr(row, ['pricing']) ?? '').toLowerCase();
  final subtitle = [?category, ?size].join(' · ');

  return KluxTemplate(
    id: _pickStr(row, ['id', 'uuid', '_id', 'slug']) ?? 'template-$index',
    title: _pickStr(row, ['name', 'title', 'design_name', 'label']) ?? 'Untitled',
    // Stands in for an author, which this endpoint doesn't send.
    subtitle: subtitle.isEmpty ? null : subtitle,
    meta: _pickStr(row, ['updated_at', 'created_at', 'modified_at', 'date']),
    premium: pricing == 'premium',
    // Kept only as a last-resort image; the card paints canvas/elements.
    thumbnail: _pickStr(row, ['thumbnail', 'thumbnail_url', 'preview', 'preview_url']),
    canvas: layout.canvas,
    elements: layout.elements,
    slug: _pickStr(row, ['slug']),
    format: humanize(_pick(row, ['sub_category'])),
    formatKey: _pickStr(row, ['sub_category']),
    category: humanize(_pick(row, ['category'])),
    designType: humanize(_pick(row, ['design_type'])),
    orientation: humanize(_pick(row, ['orientation'])),
    mediaType: humanize(_pick(row, ['type'])),
    typeSize: size,
    createdAt: _pickStr(row, ['created_at']),
    updatedAt: _pickStr(row, ['updated_at', 'modified_at']),
    pricing: pricing.isEmpty ? null : pricing,
  );
}

/// Newest first. The id tiebreak matters: the pool was seeded in bulk, so most
/// of it shares a timestamp to the second, and the endpoint shuffles its order
/// on every call.
int byNewest(KluxTemplate a, KluxTemplate b) {
  DateTime at(KluxTemplate t) => DateTime.tryParse(t.updatedAt ?? t.createdAt ?? '') ?? DateTime(1970);
  final byDate = at(b).compareTo(at(a));
  if (byDate != 0) return byDate;
  return (num.tryParse(b.id) ?? 0).compareTo(num.tryParse(a.id) ?? 0);
}

/// Find the rows in the body: `{ designs: [...] }`, with the other shapes
/// tolerated so a backend tweak can't blank the grid.
List<dynamic> _extractRows(Object? body) {
  if (body is List) return body;
  if (body is! Map) return const [];
  final direct = body['designs'] ?? body['data'] ?? body['templates'] ?? body['items'] ?? body['results'];
  if (direct is List) return direct;
  if (direct is Map) {
    final nested = direct['data'] ?? direct['designs'] ?? direct['templates'] ?? direct['items'];
    if (nested is List) return nested;
  }
  return const [];
}

/// Build a card-contract template from a CDN layout plus a share link's hints
/// — the cold-resolve counterpart to [normalizeTemplate]. What the CDN object
/// can't say is left null and the sheet drops those rows by itself.
KluxTemplate buildTemplateFromLayout({
  required String slug,
  required Map<String, dynamic> canvas,
  required List<dynamic> elements,
  String? title,
  String? formatKey,
  String? designTypeKey,
  String? pricing,
}) {
  final w = (num.tryParse('${canvas['width']}') ?? 0).round();
  final h = (num.tryParse('${canvas['height']}') ?? 0).round();
  final size = w > 0 && h > 0 ? '${w}x$h' : null;
  final format = humanize(formatKey);
  final tier = (pricing ?? '').toLowerCase();
  final subtitle = [?format, ?size].join(' · ');
  return KluxTemplate(
    id: slug,
    // The link is the only source of a title.
    title: (title ?? '').isNotEmpty ? title! : 'Klux template',
    subtitle: subtitle.isEmpty ? null : subtitle,
    premium: tier == 'premium',
    canvas: canvas,
    elements: elements,
    slug: slug,
    format: format,
    formatKey: formatKey,
    designType: humanize(designTypeKey),
    orientation: orientationOf(canvas),
    typeSize: size,
    pricing: tier.isEmpty ? null : tier,
  );
}

/// The query string one template is shared with: `template=<slug>` plus the
/// optional name/format/kind/tier hints the web reads back. The CDN object
/// holds only the layout, so those four ride in the URL.
String buildTemplateShareQuery(KluxTemplate t) => Uri(
  queryParameters: {
    'template': t.slug ?? t.id,
    'name': t.title,
    'format': ?t.formatKey,
    'kind': ?t.designType?.toLowerCase(),
    'tier': ?t.pricing,
  },
).query;

/// The web's share link for a template — the home page reopens its details
/// modal from it, so it works for anyone, app or not.
String templateShareUrl(KluxTemplate t) => '${AppConfig.webAppUrl}/?${buildTemplateShareQuery(t)}';

// ── "More like this" ────────────────────────────────────────────────────────
// There is no "related" endpoint, so siblings are picked locally from rows we
// already hold. `formatKey` outweighs everything: it's the field a user shops
// by ("more Instagram templates"); the rest only break ties.

const _relatedWeights = <(String Function(KluxTemplate), int)>[
  (_formatKeyOf, 6),
  (_designTypeOf, 3),
  (_categoryOf, 2),
  (_orientationOf, 1),
  (_pricingOf, 1), // free next to free, premium next to premium
];

String _formatKeyOf(KluxTemplate t) => t.formatKey ?? '';
String _designTypeOf(KluxTemplate t) => t.designType ?? '';
String _categoryOf(KluxTemplate t) => t.category ?? '';
String _orientationOf(KluxTemplate t) => t.orientation ?? '';
String _pricingOf(KluxTemplate t) => t.pricing ?? '';

int relatednessScore(KluxTemplate item, KluxTemplate candidate) {
  var score = 0;
  for (final (field, weight) in _relatedWeights) {
    final a = field(item).trim().toLowerCase();
    if (a.isNotEmpty && a == field(candidate).trim().toLowerCase()) score += weight;
  }
  return score;
}

/// Up to [limit] siblings, best match first, pool order breaking ties. The
/// pool is itself a random draw, so a template with no real match still gets
/// plausible cards rather than an empty strip.
List<KluxTemplate> pickRelatedItems(KluxTemplate? item, List<KluxTemplate> pool, {int limit = relatedDisplayLimit}) {
  if (item == null || pool.isEmpty) return const [];
  final ranked = [
    for (var i = 0; i < pool.length; i++)
      if (!pool[i].isSameAs(item)) (row: pool[i], index: i, score: relatednessScore(item, pool[i])),
  ]..sort((a, b) => b.score != a.score ? b.score - a.score : a.index - b.index);
  return [for (final e in ranked.take(limit)) e.row];
}

// ── Requests ────────────────────────────────────────────────────────────────

/// Never-throws result, like the web module's `{status, items, message}`.
typedef TemplatesResult = ({bool ok, List<KluxTemplate> items, String? message});
typedef TemplateResult = ({String status, KluxTemplate? item, String? message});

class TemplatesApi {
  TemplatesApi(this._api);

  final ApiClient _api;

  /// Load one random draw of the public pool, newest first.
  /// No token: the endpoint is public, and `auth: false` keeps a stray 401
  /// from a third-party host from logging the user out.
  Future<TemplatesResult> fetchPublicTemplates() async {
    debugPrint('📡 [templates] fetching public templates → $publicTemplatesEndpoint');
    final res = await _api.post(publicTemplatesEndpoint, body: const {'type': 'image'}, auth: false);
    if (!res.ok) {
      debugPrint('❌ [templates] request failed: ${res.messageForDevs ?? res.message}');
      return (
        ok: false,
        items: const <KluxTemplate>[],
        message: res.status == null
            ? 'Connection problem. Please check your network and try again.'
            : "We couldn't load templates. Please try again.",
      );
    }
    final rows = _extractRows(res.raw);
    final items = <KluxTemplate>[for (var i = 0; i < rows.length; i++) ?normalizeTemplate(rows[i], i)]..sort(byNewest);
    debugPrint('✅ [templates] loaded ${items.length} template(s) (${rows.length - items.length} skipped)');
    return (ok: true, items: items, message: null);
  }

  /// Resolve ONE shared template by slug, exactly, from its CDN object —
  /// searching the random 20-row pool would find it about 1 time in 10.
  /// status: "ok" | "not-found" | "error".
  Future<TemplateResult> fetchTemplateBySlug(
    String slug, {
    String? title,
    String? formatKey,
    String? designTypeKey,
    String? pricing,
  }) async {
    final key = slug.trim();
    if (key.isEmpty) return (status: 'error', item: null, message: 'That template link is incomplete.');
    final url = templateLayoutUrl(key);
    try {
      debugPrint('📡 [templates] resolving shared template "$key" → $url');
      final res = await Dio().get<String>(
        url,
        options: Options(responseType: ResponseType.plain, validateStatus: (_) => true),
      );
      final status = res.statusCode ?? 0;
      // The bucket answers 403 for a missing key, since it doesn't allow listing.
      if (status == 403 || status == 404) {
        return (status: 'not-found', item: null, message: "That template isn't available any more.");
      }
      if (status < 200 || status >= 300) {
        return (status: 'error', item: null, message: "We couldn't open that template. Please try again.");
      }
      final body = jsonDecode(res.data ?? '');
      final layout = body is Map ? readLayout(body) : null;
      if (layout == null) return (status: 'error', item: null, message: "That template can't be opened.");
      final item = buildTemplateFromLayout(
        slug: key,
        canvas: layout.canvas,
        elements: layout.elements,
        title: title,
        formatKey: formatKey,
        designTypeKey: designTypeKey,
        pricing: pricing,
      );
      return (status: 'ok', item: item, message: null);
    } on FormatException {
      return (status: 'error', item: null, message: "We couldn't open that template. Please try again.");
    } catch (err) {
      debugPrint('❌ [templates] shared template request threw: $err');
      return (status: 'error', item: null, message: 'Connection problem. Please check your network and try again.');
    }
  }
}
