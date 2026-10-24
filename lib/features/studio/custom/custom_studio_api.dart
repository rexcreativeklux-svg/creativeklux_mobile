import '../../../core/api/api_client.dart';
import '../../brand/brand_api.dart';
import '../studio_api.dart';

/// What `/brands/import` pulled off a website (the web's `sendUrl`), in the
/// shape the studio forms read: `r.data?.data || r.data`.
class ImportedBrand {
  const ImportedBrand({
    this.name,
    this.description,
    this.primaryColor,
    this.secondaryColor,
    this.logo,
    this.images = const [],
  });

  final String? name;
  final String? description;
  final String? primaryColor;
  final String? secondaryColor;
  final String? logo;
  final List<String> images;
}

/// The Custom Creation studio's calls: brand import, image upload, and the
/// create-design engine + save shared with the AI chat ([StudioApi]).
class CustomStudioApi {
  CustomStudioApi(ApiClient api) : _brand = BrandApi(api), studio = StudioApi(api);

  final BrandApi _brand;
  final StudioApi studio;

  /// Returns the import, or throws with the server's message.
  Future<ImportedBrand> importBrand(String url) async {
    final res = await _brand.importFromUrl(url.trim());
    if (!res.ok) throw Exception(res.message.isNotEmpty ? res.message : 'Import failed');
    final d = res.body['data'] is Map ? Map<String, dynamic>.from(res.body['data'] as Map) : res.body;
    String? s(Object? v) => v == null || '$v'.trim().isEmpty ? null : '$v'.trim();
    final images = d['images'];
    return ImportedBrand(
      name: s(d['name']),
      description: s(d['description']),
      primaryColor: s(d['primary_color']),
      secondaryColor: s(d['secondary_color']),
      // The web reads logo, then logo_url, then logo.url.
      logo: s(d['logo'] is Map ? (d['logo'] as Map)['url'] : d['logo']) ?? s(d['logo_url']),
      images: [
        if (images is List)
          for (final i in images)
            if (i is Map && s(i['url']) != null) s(i['url'])! else if (i is String && i.isNotEmpty) i,
      ],
    );
  }

  /// Upload a picked image to the gallery (`POST /gallery`) → hosted URL.
  /// The web sends logos as data URLs and product images as gallery uploads;
  /// here both go through the gallery so payloads stay small on mobile data.
  Future<String?> uploadImage(List<int> bytes, String filename) => _brand.uploadImage(bytes, filename);
}
