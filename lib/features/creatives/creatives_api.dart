import 'dart:convert';

import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';
import 'design.dart';

/// Saved-design endpoints — the design functions from the web's AuthContext
/// (`fetchDesigns`, `deleteDesignById`, `bulkDeleteDesigns`,
/// `updateDesignById`, `toggleDesignFavorite`).
class CreativesApi {
  CreativesApi(this._api);

  final ApiClient _api;

  /// One page of a brand's designs. Only `brand_id`, `per_page` and `page`
  /// do anything server-side — filtering/search happen on the client.
  Future<({List<Design> designs, int lastPage})?> page(int brandId, {int perPage = 24, int page = 1}) async {
    final res = await _api.get('/creative-designs', query: {'brand_id': brandId, 'per_page': perPage, 'page': page});
    if (!res.ok) return null;
    // A Laravel paginator — at the top level or nested under `data` — or a bare array.
    final body = res.raw;
    final pager = body is Map && body['data'] is Map ? body['data'] as Map : body;
    final list = pager is List ? pager : (pager is Map ? pager['data'] : null);
    final lastPage = pager is Map ? int.tryParse('${pager['last_page'] ?? 1}') ?? 1 : 1;
    return (designs: [if (list is List) ...list.map(Design.tryParse).whereType<Design>()], lastPage: lastPage);
  }

  /// Every design for the brand, fetched like the web does it: page 1 first
  /// (shown straight away through [onProgress]), then the rest six at a time.
  /// Small pages in parallel are much faster on this backend than one big one.
  Future<List<Design>?> all(int brandId, {void Function(List<Design>)? onProgress}) async {
    const pageSize = 24, concurrency = 6, maxPages = 400;
    final first = await page(brandId, perPage: pageSize);
    if (first == null) return null;

    final byId = {for (final d in first.designs) d.id: d};
    List<Design> sorted() => byId.values.toList()
      ..sort((a, b) {
        final c = (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
        return c != 0 ? c : b.id.compareTo(a.id);
      });
    onProgress?.call(sorted());

    final last = first.lastPage.clamp(1, maxPages);
    for (var start = 2; start <= last; start += concurrency) {
      final batch = await Future.wait([
        for (var p = start; p < start + concurrency && p <= last; p++) page(brandId, perPage: pageSize, page: p),
      ]);
      for (final r in batch) {
        for (final d in r?.designs ?? const <Design>[]) {
          byId[d.id] = d;
        }
      }
      onProgress?.call(sorted());
    }
    return sorted();
  }

  Future<ApiResult> delete(int id) => _api.delete('/creative-designs/$id');

  Future<ApiResult> bulkDelete(List<int> ids) => _api.delete('/creative-designs/bulk-delete', body: {'ids': ids});

  /// Rename + edit copy. `copy` goes as a JSON string, keeping extra keys.
  Future<ApiResult> updateCopy(int id, {required String name, required Map<String, dynamic> copy}) =>
      _api.put('/creative-designs/$id', body: {'name': name, 'copy': jsonEncode(copy)});

  Future<ApiResult> setFavorite(int id, bool favorite) =>
      _api.patch('/creative-designs/$id/favorite', body: {'fav': favorite ? 1 : 0});
}
