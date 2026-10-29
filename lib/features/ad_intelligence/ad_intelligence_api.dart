import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';
import '../editor/magic_panel/magic_history_api.dart';
import '../magic_studio/magic_studio_types.dart';

/// The Ad Intelligence endpoints — the slice of the web's AuthContext these
/// five pages call (`creativeInsights`, `getCompetitorInsights`,
/// `checkCompliance`, `creativeScoring`, `runComparison`), plus
/// `useMagicImageResults.js` for Creative Comparison's Magic Studio tab.
///
/// Every endpoint is real on the web too (nothing here is mocked). Each answer
/// is an AI-written JSON object that the pages read field by field, so results
/// stay loose maps and the screens read them with [str] / [numOf] / [listOf].
class AdIntelligenceApi {
  AdIntelligenceApi(this._api);

  final ApiClient _api;

  // The AI calls run well past the client's 60s default (a comparison scores
  // two images on several measures in one request).
  static const _aiTimeout = Duration(minutes: 4);

  /// Ad Performance — `POST /creative-insights {brand}`.
  Future<AiResult> creativeInsights(String brand) async => _finish(
    await _api.post('/creative-insights', body: {'brand': brand}, timeout: _aiTimeout),
    'Creative insights failed',
  );

  /// A website address as typed, minus stray spaces. Some phone keyboards add
  /// a space after every "." ("canva. com"), which no URL contains.
  static String cleanUrl(String url) => url.replaceAll(RegExp(r'\s+'), '');

  /// Market Spy — `POST /competitor-insights {url}`. The web strips the scheme
  /// and any path first, so only the bare domain is sent.
  Future<AiResult> competitorInsights(String url) async {
    final domain = cleanUrl(url).replaceFirst(RegExp(r'^https?://'), '').split('/').first;
    return _finish(
      await _api.post('/competitor-insights', body: {'url': domain}, timeout: _aiTimeout),
      'Failed to fetch competitor insights',
    );
  }

  /// Ad Guard AI — `POST /compliance-checker`: multipart `image` +
  /// `platforms[]` for an upload, or JSON `{canvas, platforms}` for a design.
  Future<AiResult> checkCompliance({PickedCreative? image, String? canvas, required List<String> platforms}) async {
    final Object body;
    if (image != null) {
      final form = FormData()..files.add(MapEntry('image', image.multipart()));
      for (final p in platforms) {
        form.fields.add(MapEntry('platforms[]', p));
      }
      body = form;
    } else {
      body = {'canvas': canvas, 'platforms': platforms};
    }
    return _finish(await _api.post('/compliance-checker', body: body, timeout: _aiTimeout), 'Compliance check failed');
  }

  /// Ad Scorer AI — `POST /creative-scoring`: multipart `image`, or JSON
  /// `{canvas}` for a design.
  Future<AiResult> creativeScoring({PickedCreative? image, String? canvas}) async {
    final Object body = image != null
        ? (FormData()..files.add(MapEntry('image', image.multipart())))
        : {'canvas': canvas};
    return _finish(await _api.post('/creative-scoring', body: body, timeout: _aiTimeout), 'Creative scoring failed');
  }

  /// Creative Comparison, creatives mode — multipart `mode`, `label_a/b`,
  /// `image_a/b`. ⚠️ FILES ONLY: the backend rejects `image_url_a/b` ("Both
  /// image_a and image_b are required"), so a hosted pick is downloaded first
  /// ([fetchForUpload]), exactly as the web's `withFile` does.
  Future<AiResult> compareCreatives({
    required String labelA,
    required String labelB,
    required PickedCreative a,
    required PickedCreative b,
  }) async {
    final form = FormData()
      ..fields.addAll([
        const MapEntry('mode', 'creatives'),
        MapEntry('label_a', labelA.isEmpty ? 'Creative A' : labelA),
        MapEntry('label_b', labelB.isEmpty ? 'Creative B' : labelB),
      ])
      ..files.addAll([MapEntry('image_a', a.multipart()), MapEntry('image_b', b.multipart())]);
    return _finish(await _api.post('/creative-comparison', body: form, timeout: _aiTimeout), 'Comparison failed');
  }

  /// Creative Comparison, websites mode — JSON `{mode, url_a, url_b}`.
  Future<AiResult> compareWebsites(String urlA, String urlB) async => _finish(
    await _api.post(
      '/creative-comparison',
      body: {'mode': 'websites', 'url_a': cleanUrl(urlA), 'url_b': cleanUrl(urlB)},
      timeout: _aiTimeout,
    ),
    'Comparison failed',
  );

  /// The user's recent Magic Studio pictures, newest first — port of
  /// `useMagicImageResults.js`. A tool whose history fails is skipped rather
  /// than failing the tab; the rest are still worth comparing.
  Future<List<MagicPick>> magicImageResults() async {
    final history = MagicHistoryApi(_api);
    final lists = await Future.wait([
      for (final tool in _magicImageTools)
        history.list(tool).then((items) => [for (final i in items ?? const <MagicHistoryItem>[]) (tool, i)]),
    ]);
    final all = [
      for (final (tool, item) in lists.expand((l) => l))
        if (!item.pending && item.type == 'image' && item.url != null) (tool, item),
    ];
    DateTime at((String, MagicHistoryItem) e) => DateTime.tryParse(e.$2.createdAt ?? '') ?? DateTime(0);
    all.sort((a, b) => at(b).compareTo(at(a)));
    return [
      for (final (tool, item) in all.take(_magicLimit))
        MagicPick(id: item.id, url: item.url!, label: magicToolById(tool)?.label ?? 'Magic Studio'),
    ];
  }

  /// Backend history enums of the tools whose results can be pictures. The
  /// persona generator also writes text and video, which the filter drops.
  static const _magicImageTools = [
    'image-design',
    'social-design',
    'ad-design',
    'text_to_image',
    'image_to_variations',
    'persona_generator',
  ];

  /// A picker, not an archive.
  static const _magicLimit = 40;

  /// The web reads `res.text()` → JSON, and on a non-2xx shows the body's
  /// `message` or the call's own fallback. Network/infra/quota failures keep
  /// the app's friendlier classified message.
  AiResult _finish(ApiResult res, String fallback) {
    if (res.ok) {
      final raw = res.raw;
      return raw is Map ? AiResult(Map<String, dynamic>.from(raw)) : const AiResult.error('Invalid server response');
    }
    switch (res.source) {
      case ApiSource.network || ApiSource.infra || ApiSource.rateLimit:
        return AiResult.error(res.message);
      default:
        final m = res.body['message']?.toString();
        return AiResult.error(
          m != null && m.isNotEmpty ? m : (res.source == ApiSource.validation ? res.message : fallback),
        );
    }
  }
}

/// One AI answer: the decoded body, or the message to show.
class AiResult {
  const AiResult(this.data) : error = null;
  const AiResult.error(String this.error) : data = null;

  final Map<String, dynamic>? data;
  final String? error;
}

/// A Magic Studio picture offered in Creative Comparison.
class MagicPick {
  const MagicPick({required this.id, required this.url, required this.label});

  final String id;
  final String url;
  final String label;
}

/// An image the user picked (or a design rendered to PNG), ready to send as a
/// multipart file.
class PickedCreative {
  const PickedCreative({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;

  double get megabytes => bytes.length / 1024 / 1024;

  MultipartFile multipart() => MultipartFile.fromBytes(bytes, filename: name, contentType: _mediaType(name));

  static DioMediaType _mediaType(String name) {
    final ext = name.split('.').last.toLowerCase();
    return DioMediaType('image', switch (ext) {
      'jpg' || 'jpeg' => 'jpeg',
      'webp' => 'webp',
      'gif' => 'gif',
      _ => 'png',
    });
  }
}

/// Pick an image from the phone — the web's hidden `<input type="file"
/// accept="image/*">`. Capped at 2048px, plenty for scoring a creative.
Future<PickedCreative?> pickCreativeImage() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048);
  if (file == null) return null;
  return PickedCreative(bytes: await file.readAsBytes(), name: file.name);
}

// ── Creative Comparison upload limit ─────────────────────────────────────────

/// The comparison endpoint rejects images over 2MB ("The uploaded image
/// exceeds 2MB"). Aim just under it to leave room for headers (page.jsx).
const _uploadLimit = 2 * 1024 * 1024;
const _uploadTarget = _uploadLimit * 0.95;

/// A file the comparison endpoint will accept: unchanged when already under
/// the limit, otherwise scaled down until it fits.
///
/// ⚠️ PNG, NOT JPEG. The web re-encodes as JPEG at falling quality; dart:ui can
/// only encode PNG and the app has no JPEG encoder, so this steps the SIZE down
/// instead (2048 → 512 on the long side). Throws the web's message when even
/// the smallest step is too big.
Future<PickedCreative> fitUploadLimit(PickedCreative file) async {
  if (file.bytes.length <= _uploadTarget) return file;
  final base = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final probe = await ui.instantiateImageCodec(file.bytes);
  final first = (await probe.getNextFrame()).image;
  final longSide = math.max(first.width, first.height);
  final landscape = first.width >= first.height;
  first.dispose();
  probe.dispose();

  for (final side in const [2048, 1600, 1280, 1024, 768, 512]) {
    if (side >= longSide && side != 512) continue;
    final codec = await ui.instantiateImageCodec(
      file.bytes,
      targetWidth: landscape ? side : null,
      targetHeight: landscape ? null : side,
    );
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    codec.dispose();
    if (data != null && data.lengthInBytes <= _uploadTarget) {
      debugPrint(
        '🗜️ [comparison] $base: ${(file.megabytes).toStringAsFixed(1)}MB → '
        '${(data.lengthInBytes / 1048576).toStringAsFixed(1)}MB',
      );
      return PickedCreative(bytes: data.buffer.asUint8List(), name: '$base.png');
    }
  }
  throw Exception('That image is too large to compare, even after compressing it.');
}

/// Download a hosted creative (a Magic Studio result, or a design's stored
/// preview) so it can go up as a file. A plain Dio: the CDN wants no bearer.
Future<PickedCreative> fetchForUpload(String url, String label) async {
  final res = await Dio().get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
  final bytes = Uint8List.fromList(res.data ?? const []);
  if (bytes.isEmpty) throw Exception("Couldn't load one of the images.");
  final type = res.headers.value('content-type') ?? 'image/png';
  final ext = (type.split('/').last.split(';').first).replaceFirst('jpeg', 'jpg');
  return PickedCreative(bytes: bytes, name: '${label.replaceAll(RegExp(r'\W+'), '-')}.$ext');
}

// ── Loose JSON readers ───────────────────────────────────────────────────────

/// A display string for an AI field, or null when it's missing/empty.
String? str(dynamic v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

/// A field as shown on the web: the value, or an em dash.
String show(dynamic v) => str(v) ?? '—';

/// A number out of a field the AI may send as `72`, `"72"` or `"3.2x"`.
num? numOf(dynamic v) {
  if (v is num) return v;
  if (v == null) return null;
  final m = RegExp(r'-?\d+(\.\d+)?').firstMatch('$v');
  return m == null ? null : num.tryParse(m.group(0)!);
}

List<dynamic> listOf(dynamic v) => v is List ? v : const [];

Map<String, dynamic> mapOf(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};

/// The design's canvas JSON as the endpoints take it — the raw `canvas`
/// column as a string (page.jsx sends `selectedDesign.raw.canvas`).
String canvasPayload(Map<String, dynamic> raw) {
  final c = raw['canvas'];
  return c is String ? c : jsonEncode(c);
}
