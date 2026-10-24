import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';
import '../brand/brand_api.dart';

/// Server-side publishing — port of `(lib)/creativesApi.js` + the publish
/// helpers in `(lib)/integration.js`. The API posts to the platforms itself
/// with tokens it holds; the app only sends the creative and where it goes.
///
/// Every failure is thrown as a [PublishException] carrying the SERVER'S OWN
/// WORDS — that text names the actual problem, so it is shown as-is.
class PublishApi {
  PublishApi(this._api);

  final ApiClient _api;

  /// The API's platform keys, where they differ from the app's.
  static String toApiPlatform(String p) => p == 'twitter' ? 'x' : p;

  /// Connected accounts (`GET /integrations`). X arrives as `x` and is renamed
  /// `twitter`; a row at status 0 is still waiting for its account to be
  /// chosen, so it isn't a publish target. Null when the list couldn't load.
  Future<List<Map<String, dynamic>>?> integrations() async {
    final res = await _api.get('/integrations');
    if (!res.ok) return null;
    final raw = res.raw;
    final rows = raw is List ? raw : (raw is Map && raw['data'] is List ? raw['data'] as List : null);
    if (rows == null) return null;
    return [
      for (final r in rows)
        if (r is Map && '${r['status']}' != '0')
          {...Map<String, dynamic>.from(r), if (r['platform'] == 'x') 'platform': 'twitter'},
    ];
  }

  /// The most specific thing the server said (port of `serverMessage`).
  static String _serverMessage(ApiResult res, String fallback) {
    final b = res.body;
    final errors = b['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      final msg = first is List && first.isNotEmpty ? '${first.first}' : '$first';
      if (msg.isNotEmpty) return msg;
    }
    final msg = b['message'] ?? b['error'];
    if (msg is String && msg.isNotEmpty) return msg;
    return res.status != null ? '$fallback (HTTP ${res.status})' : res.message;
  }

  /// Publish to ONE social platform (`POST creatives/publish`), throwing the
  /// platform's own error when it didn't go out.
  ///
  /// Partial success is the normal case for this endpoint, so the answer is
  /// per platform and is read the same for a 200 and a 422 that carries
  /// `results` ("every platform failed").
  Future<({String? postId, bool draftOnly})> publish(String platform, int brandId, Map<String, dynamic> fields) async {
    final key = toApiPlatform(platform);
    final body = {
      'brand_id': brandId,
      'platforms': [key],
      for (final e in fields.entries)
        if (e.value != null) e.key: e.value,
    };
    final res = await _api.post('/creatives/publish', body: body);
    final results = res.body['results'];
    if (results is! Map) throw PublishException(_serverMessage(res, 'Publish failed'));
    final r = results[key];
    if (r is! Map || r['ok'] != true) {
      throw PublishException(r is Map && r['error'] != null ? '${r['error']}' : 'Publishing to $platform failed.');
    }
    return (postId: r['id']?.toString(), draftOnly: r['draft_only'] == true);
  }

  /// Create an ad (`POST creatives/ads`) — campaign → ad set → creative → ad
  /// in one call, PAUSED. Empty optionals are dropped (the API validates a
  /// present-but-blank field). Returns `{status, currency, …}`.
  Future<Map<String, dynamic>> createAd(Map<String, dynamic> ad) async {
    final body = {
      for (final e in ad.entries)
        if (e.value != null && e.value != '') e.key: e.value,
    };
    final res = await _api.post('/creatives/ads', body: body);
    if (!res.ok) throw PublishException(_serverMessage(res, "Couldn't create the ad"));
    final data = res.body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : res.body;
  }

  /// Host a file through the gallery upload and return its URL.
  Future<String> upload(Uint8List bytes, String filename) async {
    final res = await _api.post(
      '/gallery',
      body: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)}),
    );
    if (!res.ok) throw PublishException(_serverMessage(res, "Couldn't upload the image"));
    final url = BrandApi.extractImageUrl(res.body);
    if (url == null) throw PublishException('The upload returned no file URL.');
    return url;
  }

  /// A 1200×1200 copy of the image, the whole design fitted on white (nothing
  /// cropped), hosted through the gallery — Google's responsive display ad
  /// needs a 1:1 image beside the landscape one. Null if it can't be made; the
  /// API then answers with Google's own refusal.
  Future<String?> squareImageFor(String url) async {
    try {
      final res = await Dio().get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(res.data!));
      final img = (await codec.getNextFrame()).image;
      const size = 1200.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawRect(const Rect.fromLTWH(0, 0, size, size), Paint()..color = const Color(0xFFFFFFFF));
      final scale = [size / img.width, size / img.height].reduce((a, b) => a < b ? a : b);
      final w = img.width * scale, h = img.height * scale;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH((size - w) / 2, (size - h) / 2, w, h),
        Paint()..filterQuality = FilterQuality.high,
      );
      final out = await recorder.endRecording().toImage(size.toInt(), size.toInt());
      final png = await out.toByteData(format: ui.ImageByteFormat.png);
      return await upload(png!.buffer.asUint8List(), 'square.png');
    } catch (_) {
      return null;
    }
  }
}

class PublishException implements Exception {
  PublishException(this.message);
  final String message;

  @override
  String toString() => message;
}
