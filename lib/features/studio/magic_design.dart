import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/painting.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';
import '../brand/brand.dart';

/// Magic Designs in the chat — port of `studio/ai-chat-page/magicDesign.js`
/// plus the slice of Magic Studio it calls (`(lib)/magic-studio-api.js`,
/// `magicStudioConfigs.jsx`, `useMagicGenerate`, `pollSchedule.js`).
///
/// THE BACKEND DECIDES THE MODE (`design_mode: "Magic-Designs"`); this only
/// maps it onto a Magic Studio tool:
///
///   medium "video"                       → Text to Video
///   brand_details.creative_type "ads"    → Ads Design
///   brand_details.creative_type "social" → Social Design
///   anything else                        → Stock Image

/// CDN base for turning an S3 object key into a hosted URL (magic-studio-api.js).
const _cdnBase = 'https://d3r8chxzp8ea06.cloudfront.net';

bool isMagicDesign(Map<String, dynamic> data) {
  final bd = data['brand_details'] is Map ? data['brand_details'] as Map : const {};
  return '${data['design_mode'] ?? ''}'.toLowerCase().startsWith('magic') ||
      '${bd['designMode'] ?? ''}'.toLowerCase() == 'magic';
}

Map<String, dynamic> _details(Map<String, dynamic> data) =>
    data['brand_details'] is Map ? Map<String, dynamic>.from(data['brand_details'] as Map) : {};

bool isMagicVideo(Map<String, dynamic> data) =>
    '${data['medium'] ?? _details(data)['medium'] ?? ''}'.toLowerCase() == 'video';

String _purposeFor(Map<String, dynamic> data) =>
    const {
      'ads': 'ad-design',
      'social': 'social-design',
      'designer': 'image-design',
    }['${_details(data)['creative_type'] ?? ''}'.toLowerCase()] ??
    'image-design';

/// Which Magic Studio tool builds this reply.
String magicToolFor(Map<String, dynamic> data) => isMagicVideo(data) ? 'text_to_video' : _purposeFor(data);

const magicToolTitles = {
  'ad-design': 'Ads Design',
  'social-design': 'Social Design',
  'image-design': 'Stock Image',
  'text_to_video': 'Text to Video',
};

// ── Ratio ──────────────────────────────────────────────────────────────────────

const _ratios = [
  ('square', 1, 1, false),
  ('landscape', 16, 9, false),
  ('portrait', 9, 16, false),
  ('wide', 21, 9, true),
];
const _ratioStrings = {'square': '1:1', 'landscape': '16:9', 'portrait': '9:16', 'wide': '21:9'};
const _ratioSizes = {
  'square': Size(1024, 1024),
  'landscape': Size(1920, 1080),
  'portrait': Size(1080, 1920),
  'wide': Size(2520, 1080),
};

/// The offered ratio closest to a "1200x630" size (compared on the log
/// scale). Text to Video offers no Ultra Wide.
String _nearestRatio(String? size, bool video) {
  final m = RegExp(r'(\d+)\s*[x×]\s*(\d+)', caseSensitive: false).firstMatch(size ?? '');
  final w = int.tryParse(m?.group(1) ?? '') ?? 0, h = int.tryParse(m?.group(2) ?? '') ?? 0;
  if (w <= 0 || h <= 0) return video ? 'portrait' : 'square';
  final target = log(w / h);
  final options = _ratios.where((r) => !(video && r.$4));
  return options.reduce((a, b) => (log(b.$2 / b.$3) - target).abs() < (log(a.$2 / a.$3) - target).abs() ? b : a).$1;
}

// ── Prompts ────────────────────────────────────────────────────────────────────

/// Every Magic prompt is kept within 500 characters: Text to Video rejects
/// anything longer (422), and the backend's prompts run 630–1,200.
const _promptMax = 500;

/// Cut to `limit` at the last full sentence, else the last whole word.
String _fitPrompt(String text, int limit) {
  if (text.length <= limit) return text;
  final head = text.substring(0, limit);
  final sentence = head.lastIndexOf(RegExp(r'[.!?]'));
  final cut = sentence > limit * 0.5
      ? head.substring(0, sentence + 1).trim()
      : head.substring(0, max(0, head.lastIndexOf(' '))).trim();
  // A cut inside a quoted headline leaves the quote open — close it.
  final open = '“'.allMatches(cut).length > '”'.allMatches(cut).length;
  return open ? '${cut.substring(0, min(cut.length, limit - 1))}”' : cut;
}

/// The prompts the backend wrote — one per version — else the brief as one.
List<String> magicPromptsFrom(Map<String, dynamic> data) {
  final details = _details(data);
  final written = [
    data['generation_prompts'],
    details['generation_prompts'],
  ].firstWhere((v) => v is List, orElse: () => const []);
  final prompts = [
    for (final p in written as List)
      if (p is String && p.trim().isNotEmpty) p.trim(),
  ];
  final description = '${details['description'] ?? ''}'.trim();
  if (prompts.isEmpty && description.isNotEmpty) prompts.add(description);
  if (prompts.isEmpty) {
    final brief = _briefFrom(details);
    if (brief.isNotEmpty) prompts.add(brief);
  }
  return [for (final p in prompts) _fitPrompt(p, _promptMax)];
}

/// A prompt pieced together from the brief's own fields, for a reply that
/// reaches Magic without prompts or a description.
String _briefFrom(Map<String, dynamic> d) {
  String t(dynamic v) => v is String ? v.trim() : '';
  final platform = d['platforms'] is List
      ? (d['platforms'] as List).where((p) => p != null && '$p'.isNotEmpty).join(' / ')
      : t(d['platforms']);
  final kind = t(d['create_sub_type']).replaceAll('_', ' ');
  final brand = t(d['brandName']);
  final parts = [
    'A ${platform.isNotEmpty ? '$platform ' : ''}${kind.isNotEmpty ? kind : 'design'}${brand.isNotEmpty ? ' for $brand' : ''}.',
    if (t(d['headline']).isNotEmpty) 'Headline: "${t(d['headline'])}".',
    if (t(d['tagline']).isNotEmpty) 'Tagline: "${t(d['tagline'])}".',
    if (t(d['campaignGoal']).isNotEmpty) 'Goal: ${t(d['campaignGoal'])}.',
    if (t(d['audience']).isNotEmpty) 'Audience: ${t(d['audience'])}.',
    if (t(d['visualStyle']).isNotEmpty) 'Style: ${t(d['visualStyle'])}.',
  ];
  // The opening sentence alone says nothing about WHAT to show.
  return parts.length > 1 ? parts.join(' ') : '';
}

/// The values a run is made with — the same keys the /magic-studio composer
/// fills in, already shaped into the request body each tool sends.
class MagicRunValues {
  MagicRunValues._(
    this.tool,
    this._purpose,
    this.ratio,
    this.variations,
    this._duration,
    this._color,
    this._brandName,
    this._brandLogo,
  );

  factory MagicRunValues.from(Map<String, dynamic> data, Brand? brand) {
    final d = _details(data);
    final video = isMagicVideo(data);
    final count = int.tryParse('${data['variations'] ?? d['variations'] ?? ''}');
    final seconds = int.tryParse('${data['duration'] ?? d['duration'] ?? ''}');
    final color = '${d['brandColor'] ?? ''}';
    return MagicRunValues._(
      magicToolFor(data),
      _purposeFor(data),
      _nearestRatio('${data['size'] ?? d['size'] ?? d['type_size'] ?? ''}', video),
      count != null && count > 0 ? count : 1,
      // fal.ai kling-video takes "5" or "10" and nothing else.
      seconds != null && seconds > 7 ? '10' : '5',
      RegExp(r'^#[0-9a-f]{3,8}$', caseSensitive: false).hasMatch(color) ? color : null,
      '${d['brandName'] ?? brand?.name ?? ''}'.trim(),
      '${d['logo'] ?? brand?.logo ?? ''}'.trim(),
    );
  }

  final String tool;
  final String _purpose;
  final String ratio;
  int variations;
  final String _duration;
  final String? _color;
  final String _brandName;
  final String _brandLogo;

  bool get isVideo => tool == 'text_to_video';

  /// Request body — `text_to_video` or the design tools (Text to Image with the
  /// purpose fixed: `tool` IS the purpose there).
  Map<String, dynamic> payload(String prompt) => isVideo
      ? {
          'tool': 'text_to_video',
          // The reply's visualStyle isn't one of Magic Studio's styles.
          'visual_style': 'photorealistic',
          'ratio': _ratioStrings[ratio],
          'duration': _duration,
          'purpose': _purpose,
          'variations': variations,
          'prompt': prompt,
        }
      : {
          'tool': tool,
          'visual_style': 'photorealistic',
          'ratio': _ratioStrings[ratio],
          'purpose': tool,
          'variations': variations,
          'color': ?_color,
          if (_brandName.isNotEmpty) 'brand_name': _brandName,
          if (_brandLogo.isNotEmpty) 'logo_url': _brandLogo,
          'prompt': prompt,
        };
}

// ── Responses ──────────────────────────────────────────────────────────────────

String? _resolveMediaUrl(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(v)) return v;
  return '$_cdnBase/${v.replaceFirst(RegExp(r'^/+'), '')}';
}

dynamic _unwrap(dynamic data) => data is Map && data['generation'] is Map ? data['generation'] : data;

/// Raw result items, whole batch first (`meta.outputs`, then `urls`).
List<dynamic> _extractItems(dynamic data) {
  if (data == null) return const [];
  final root = _unwrap(data);
  if (root is List) return root;
  if (root is! Map) return const [];
  final outputs = root['meta'] is Map ? (root['meta'] as Map)['outputs'] : null;
  if (outputs is List && outputs.isNotEmpty) return outputs;
  final urls = (data is Map ? data['urls'] : null) ?? root['urls'];
  if (urls is List && urls.isNotEmpty) return urls;
  for (final k in ['assets', 'results', 'data', 'items', 'urls', 'images', 'videos']) {
    if (root[k] is List) return root[k] as List;
  }
  for (final k in ['url', 'src', 'video_url', 'audio_url', 'image_url', 's3_key']) {
    if (root[k] != null && '${root[k]}'.isNotEmpty) return [root];
  }
  return const [];
}

List<String> _assetUrls(dynamic data) => [
  for (final item in _extractItems(data))
    ?(item is String
        ? _resolveMediaUrl(item)
        : item is Map
        ? [
            'src',
            'url',
            'video_url',
            'videoSrc',
            'audio_url',
            'image_url',
            's3_key',
            'key',
            'preview',
          ].map((k) => _resolveMediaUrl(item[k])).firstWhere((u) => u != null, orElse: () => null)
        : null),
];

const _doneStates = ['completed', 'complete', 'done', 'success', 'succeeded', 'ready', 'finished'];
const _failedStates = ['failed', 'error', 'errored', 'cancelled', 'canceled'];

/// "completed" | "processing" | "failed".
String _status(dynamic data) {
  final root = _unwrap(data);
  var s = root is Map ? '${root['status'] ?? ''}' : '';
  if (s.isEmpty && data is Map && data['data'] is Map) s = '${(data['data'] as Map)['status'] ?? ''}';
  s = s.toLowerCase().trim();
  if (s.isNotEmpty) {
    if (_doneStates.contains(s)) return 'completed';
    if (_failedStates.contains(s)) return 'failed';
    return 'processing';
  }
  return _extractItems(data).isNotEmpty ? 'completed' : 'processing';
}

dynamic _generationId(dynamic data) {
  final root = _unwrap(data);
  if (root is Map) {
    for (final k in ['id', 'job_id', 'jobId', 'video_id', 'videoId', 'generation_id']) {
      if (root[k] != null) return root[k];
    }
  }
  if (data is Map && data['data'] is Map) return (data['data'] as Map)['id'] ?? (data['data'] as Map)['job_id'];
  return null;
}

/// Provider failures about OUR account (an exhausted fal.ai balance…) — never
/// shown verbatim: they name our vendor and tell a customer to top up.
final _accountError = RegExp(
  r'exhausted balance|top up|user is locked|insufficient (?:funds|balance|credits?)|quota exceeded|out of credits?|billing',
  caseSensitive: false,
);

/// A provider error, in words a user can act on: the vendor prefix goes, and a
/// validation `detail` becomes "Duration: Input should be '5' or '10'".
String _readableError(dynamic data) {
  final root = _unwrap(data);
  dynamic raw = root is Map ? (root['error'] ?? root['error_message'] ?? root['message']) : null;
  if (raw == null && data is Map && data['data'] is Map) raw = (data['data'] as Map)['error'];
  final text = raw is String ? raw.trim() : '';
  if (text.isEmpty) return '';
  if (_accountError.hasMatch(text)) return 'This tool is temporarily unavailable. Please try again shortly.';
  if (RegExp('timed out|timeout', caseSensitive: false).hasMatch(text)) {
    return 'The generator took too long and gave up. Please try again.';
  }
  final start = text.indexOf('{');
  if (start >= 0) {
    try {
      final detail = (jsonDecode(text.substring(start)) as Map)['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail.trim();
      if (detail is List && detail.isNotEmpty) {
        return detail
            .map((d) {
              final loc = d is Map && d['loc'] is List ? (d['loc'] as List) : const [];
              final field = loc.isNotEmpty ? '${loc.last}' : '';
              final label = field.isNotEmpty ? '${field[0].toUpperCase()}${field.substring(1)}: ' : '';
              return '$label${d is Map ? (d['msg'] ?? 'invalid value') : 'invalid value'}';
            })
            .join('; ');
      }
    } catch (_) {}
  }
  return text.replaceFirst(RegExp(r'^[^:]*\([^)]*\):\s*'), '');
}

// ── Running ────────────────────────────────────────────────────────────────────

/// How one run ended.
sealed class MagicOutcome {
  const MagicOutcome();
}

class MagicDone extends MagicOutcome {
  const MagicDone(this.urls);
  final List<String> urls;
}

class MagicFailed extends MagicOutcome {
  const MagicFailed(this.message);
  final String message;
}

/// The request itself was refused (no run was recorded); [message] is the
/// server's own words.
class MagicRefused extends MagicOutcome {
  const MagicRefused(this.message);
  final String message;
}

/// Still going after the poll ceiling — it lands in Magic Studio history.
class MagicTimedOut extends MagicOutcome {
  const MagicTimedOut();
}

class MagicCancelled extends MagicOutcome {
  const MagicCancelled();
}

class MagicApi {
  MagicApi(this._api);

  final ApiClient _api;

  /// Stop following a run after this; the result still lands in history.
  static const _pollCeiling = Duration(minutes: 10);

  /// Tight at first (a 1x image can be done in ~46s), slack later (a 4x batch
  /// runs ~4 minutes). Measured on the web (pollSchedule.js).
  static Duration _nextDelay(Duration elapsed) => elapsed < const Duration(seconds: 30)
      ? const Duration(seconds: 3)
      : elapsed < const Duration(minutes: 2)
      ? const Duration(seconds: 5)
      : const Duration(seconds: 10);

  /// Start one run and see it through.
  ///
  /// ⚠️ /magic-studio/generate holds its connection for the whole job, and the
  /// edge cuts it (Cloudflare 524 at 120s; our client gives up sooner) while
  /// the backend carries on. So a failed request isn't a failed run: history is
  /// read for the record this run made, and a run still in flight is followed
  /// to its end through the status endpoint ([onStillWorking] fires first).
  Future<MagicOutcome> run(
    Map<String, dynamic> payload, {
    required bool Function() isActive,
    void Function()? onStillWorking,
  }) async {
    final startedAt = DateTime.now();
    // Generation runs 46–240s (measured on the web), far past the client's
    // 60s default — wait for it rather than lean on the history recovery,
    // which can't always find a run (design tools are filed under another tool).
    final res = await _api.post('/magic-studio/generate', body: payload, timeout: const Duration(minutes: 5));

    if (res.ok) {
      final status = _status(res.raw);
      if (status == 'failed') {
        final msg = _readableError(res.raw);
        return MagicFailed(msg.isNotEmpty ? msg : 'Generation failed. Please try again.');
      }
      final urls = _assetUrls(res.raw);
      if (status == 'completed' && urls.isNotEmpty) return MagicDone(urls);
      final id = _generationId(res.raw);
      if (id != null) return _follow(id, startedAt, isActive);
    }

    // A real refusal (validation, credits…) made no run — say what the server said.
    if (!res.ok && res.status != null && res.status! >= 400 && res.status! < 500 && res.status != 408) {
      final text = '${res.body['message'] ?? res.body['error'] ?? ''}';
      if (res.status == 402 || RegExp(r'limit|credits?', caseSensitive: false).hasMatch(text)) {
        return const MagicRefused('Monthly AI credits limit reached. Please upgrade your plan to continue.');
      }
      return MagicRefused(res.message.isNotEmpty ? res.message : 'AI generation failed. Please try again.');
    }

    final outcome = await _findRun(payload['tool'] as String, startedAt);
    if (outcome == null) {
      return const MagicRefused('Magic Studio didn\'t accept this request. Please try again.');
    }
    if (outcome is MagicOutcome) return outcome;
    onStillWorking?.call();
    return _follow(outcome, startedAt, isActive);
  }

  /// The newest record this run could have made (with slack for clock skew):
  /// a [MagicFailed] for a failed one, its id for one still going, null when
  /// there's none.
  Future<Object?> _findRun(String tool, DateTime startedAt) async {
    final ApiResult res = await _api.post('/magic-studio/history', body: {'tool': tool});
    if (!res.ok) return null;
    final raw = res.raw;
    final list = raw is List ? raw : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
    final since = startedAt.subtract(const Duration(seconds: 15));
    final runs = list.whereType<Map>().where((r) {
      final at = DateTime.tryParse('${r['created_at']}');
      return at != null && !at.isBefore(since);
    }).toList()..sort((a, b) => (num.tryParse('${b['id']}') ?? 0).compareTo(num.tryParse('${a['id']}') ?? 0));
    if (runs.isEmpty) return null;
    final run = runs.first;
    if ('${run['status']}'.toLowerCase() == 'failed') {
      final msg = _readableError(run);
      return MagicFailed(msg.isNotEmpty ? msg : 'The generator reported a failure.');
    }
    return run['id'];
  }

  Future<MagicOutcome> _follow(dynamic id, DateTime startedAt, bool Function() isActive) async {
    while (isActive()) {
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed > _pollCeiling) return const MagicTimedOut();
      await Future<void>.delayed(_nextDelay(elapsed));
      if (!isActive()) break;
      final res = await _api.get('/magic-studio/generations/$id/status');
      // A failed CHECK is retried on the next beat; only the record saying
      // "failed" ends the run.
      if (!res.ok) continue;
      final status = _status(res.raw);
      if (status == 'completed') return MagicDone(_assetUrls(res.raw));
      if (status == 'failed') {
        final msg = _readableError(res.raw);
        return MagicFailed(msg.isNotEmpty ? msg : 'The generator reported a failure.');
      }
    }
    return const MagicCancelled();
  }
}

// ── Results as designs ────────────────────────────────────────────────────────

/// Natural size of an image URL, or null.
Future<Size?> _imageSize(String url) {
  final done = Completer<Size?>();
  final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!done.isCompleted) done.complete(Size(info.image.width.toDouble(), info.image.height.toDouble()));
      stream.removeListener(listener);
    },
    onError: (_, _) {
      if (!done.isCompleted) done.complete(null);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future.timeout(const Duration(seconds: 15), onTimeout: () => null);
}

/// One Magic result as a design, shown exactly as returned — a canvas the
/// media's own size, so it previews, saves and opens in the editor like any
/// other design.
///
///   image → the picture as the only element.
///   video → the video as the only element (the web also lays a still frame
///           under it for the thumbnail; the app can't grab one yet).
///
/// ⚠️ `run` (the run's start time) keeps ids unique across runs — one run per
/// version means every run's first asset would otherwise share an id.
Future<Map<String, dynamic>> magicResultToVariation(
  String url, {
  required String name,
  required String ratio,
  required String tool,
  required int run,
  required int index,
  required bool video,
}) async {
  final id = 'magic-$run-$index';
  final size = (video ? null : await _imageSize(url)) ?? _ratioSizes[ratio] ?? _ratioSizes['square']!;
  final type = video ? 'video' : 'image';
  return {
    'id': id,
    'name': name,
    'source': 'magic',
    'magicTool': tool,
    if (video) ...{'kind': 'video', 'src': url},
    'canvas': {'width': size.width, 'height': size.height, 'background': video ? '#000000' : '#ffffff'},
    'elements': [
      {
        'id': '$id-$type',
        'type': type,
        'src': url,
        'x': 0,
        'y': 0,
        'width': size.width,
        'height': size.height,
        'rotation': 0,
        'opacity': 1,
      },
    ],
  };
}

/// A Magic Design's hosted file URL, or null for a creative (designActions.js).
String? hostedUrlOf(Map<String, dynamic> v) {
  if (v['source'] != 'magic') return null;
  if (v['kind'] == 'video') return v['src'] as String?;
  final els = v['elements'] is List ? v['elements'] as List : const [];
  return els.whereType<Map>().where((e) => e['type'] == 'image').map((e) => e['src'] as String?).firstOrNull;
}
