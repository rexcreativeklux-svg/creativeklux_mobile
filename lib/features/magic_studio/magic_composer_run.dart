import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../editor/magic_panel/magic_history_api.dart';
import '../studio/magic_design.dart';
import 'magic_configs.dart';
import 'magic_studio_types.dart';

/// Runs one composer generation — the composer's slice of useMagicGenerate.js.
///
/// ⚠️ NOT A SECOND GENERATE PATH. Every JSON tool goes through `MagicApi.run`
/// (magic_design.dart) — fire, follow the run through the status endpoint,
/// recover a cut-off request from history. This adds only what that path
/// can't do on its own:
///
///   • TEXT RESULTS. `MagicDone` carries URLs, and a persona "Text" run or a
///     transcript has none — so the finished record is read back from history
///     (where `content` / `transcript` live; see expandMagicHistoryRecord).
///   • IDS. A media result is matched to its history tile by URL, so the
///     lattice gets the same `<generationId>:<i>` ids history will — the
///     session result and the history refresh then dedupe instead of doubling.
///   • AUDIO TO TEXT posts MULTIPART (`audio` file + `tool` + `language`),
///     which `MagicApi.run` (a JSON body) can't carry.

/// How a composer run ended.
sealed class MagicRunResult {
  const MagicRunResult();
}

class MagicRunDone extends MagicRunResult {
  const MagicRunDone(this.items);
  final List<MagicItem> items;
}

class MagicRunError extends MagicRunResult {
  const MagicRunError(this.message);
  final String message;
}

/// Still going past the poll ceiling — it lands in history when done.
class MagicRunTimedOut extends MagicRunResult {
  const MagicRunTimedOut();
}

class MagicRunCancelled extends MagicRunResult {
  const MagicRunCancelled();
}

/// The audio Audio to Text sends: a gallery file, downloaded and posted as bytes.
class MagicAudioSource {
  const MagicAudioSource({required this.url, required this.name});
  final String url;
  final String name;
}

/// Extension → MIME, for the formats the transcriber takes (AUDIO_MIME_BY_EXT).
/// ⚠️ LOAD-BEARING: a part sent as application/octet-stream comes back
/// "HTTP 415: Unsupported audio type" — which reads like a corrupt file.
const _audioMime = {
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'oga': 'audio/ogg',
  'm4a': 'audio/mp4',
  'mp4': 'audio/mp4',
  'aac': 'audio/aac',
  'flac': 'audio/flac',
  'webm': 'audio/webm',
};

/// Files above this are refused before anything is read (MAX_AUDIO_BYTES).
const magicMaxAudioBytes = 100 * 1024 * 1024;

class MagicComposerRunner {
  MagicComposerRunner(this._api) : _history = MagicHistoryApi(_api);

  final ApiClient _api;
  final MagicHistoryApi _history;

  static const _pollCeiling = Duration(minutes: 10);

  Future<MagicRunResult> run({
    required MagicToolConfig config,
    required MagicStudioTool tool,
    required Map<String, dynamic> payload,
    required String resultType,
    required String prompt,
    required bool Function() isActive,
    MagicAudioSource? audio,
    void Function()? onStillWorking,
  }) async {
    final startedAt = DateTime.now();
    if (config.multipartAudio) {
      return _runMultipartAudio(config, tool, payload, audio, startedAt, isActive, onStillWorking);
    }

    final outcome = await MagicApi(_api).run(payload, isActive: isActive, onStillWorking: onStillWorking);
    switch (outcome) {
      case MagicDone(:final urls):
        return MagicRunDone(await _itemsFor(config, tool, urls, resultType, prompt, startedAt));
      case MagicFailed(:final message) || MagicRefused(:final message):
        return MagicRunError(message);
      case MagicTimedOut():
        return const MagicRunTimedOut();
      case MagicCancelled():
        return const MagicRunCancelled();
    }
  }

  /// The finished run as lattice items — history's own tiles where they can be
  /// found, else plain session items built from the URLs.
  Future<List<MagicItem>> _itemsFor(
    MagicToolConfig config,
    MagicStudioTool tool,
    List<String> urls,
    String resultType,
    String prompt,
    DateTime startedAt,
  ) async {
    final records = await _history.list(config.historyTool) ?? const <MagicHistoryItem>[];
    if (urls.isEmpty) {
      // A text result: the newest finished record this run could have made.
      final since = startedAt.subtract(const Duration(seconds: 15));
      final fresh = records.where((r) {
        if (r.pending) return false;
        final at = DateTime.tryParse(r.startedAt ?? r.createdAt ?? '');
        return at != null && !at.isBefore(since);
      }).toList();
      if (fresh.isEmpty) return const [];
      final gid = fresh.first.generationId;
      return [for (final r in fresh.where((r) => r.generationId == gid)) _fromHistory(r, tool, prompt)];
    }
    final byUrl = {for (final r in records) ?r.url: r};
    var i = 0;
    return [
      for (final url in urls)
        if (byUrl[url] case final r?)
          _fromHistory(r, tool, prompt)
        else
          MagicItem(
            id: 'session-${startedAt.millisecondsSinceEpoch}-${i++}',
            type: resultType,
            url: url,
            videoUrl: resultType == 'video' ? url : null,
            prompt: prompt.isEmpty ? null : prompt,
            createdAt: DateTime.now().toUtc().toIso8601String(),
            tool: tool.id,
          ),
    ];
  }

  MagicItem _fromHistory(MagicHistoryItem r, MagicStudioTool tool, String prompt) => MagicItem(
    id: r.id,
    generationId: r.generationId,
    type: r.type ?? 'image',
    url: r.url,
    videoUrl: r.type == 'video' ? r.url : null,
    thumbnail: r.thumbnail,
    content: r.content,
    prompt: r.prompt ?? (prompt.isEmpty ? null : prompt),
    createdAt: r.createdAt,
    tool: tool.id,
  );

  // ── Audio to Text ──────────────────────────────────────────────────────────

  Future<MagicRunResult> _runMultipartAudio(
    MagicToolConfig config,
    MagicStudioTool tool,
    Map<String, dynamic> fields,
    MagicAudioSource? audio,
    DateTime startedAt,
    bool Function() isActive,
    void Function()? onStillWorking,
  ) async {
    if (audio == null) return const MagicRunError('Please upload or record some audio.');

    // The gallery hosts the file; the transcriber wants the BYTES. Fetched
    // straight off the CDN — no auth header belongs on a third-party host.
    List<int> bytes;
    try {
      final res = await Dio().get<List<int>>(audio.url, options: Options(responseType: ResponseType.bytes));
      bytes = res.data ?? const [];
    } catch (_) {
      return const MagicRunError("Couldn't read that audio file. Please try another one.");
    }
    if (bytes.isEmpty) return const MagicRunError("Couldn't read that audio file. Please try another one.");
    if (bytes.length > magicMaxAudioBytes) return const MagicRunError('File size must be under 100 MB.');
    if (!isActive()) return const MagicRunCancelled();

    final name = _fileName(audio);
    final ext = name.split('.').last.toLowerCase();
    final form = FormData.fromMap({
      ...fields,
      'audio': MultipartFile.fromBytes(
        bytes,
        filename: name,
        contentType: DioMediaType.parse(_audioMime[ext] ?? 'audio/mpeg'),
      ),
    });

    final res = await _api.post('/magic-studio/generate', body: form, timeout: const Duration(minutes: 5));
    if (!isActive()) return const MagicRunCancelled();

    if (res.ok) {
      final text = _textOf(res.raw);
      if (text != null) {
        return MagicRunDone([
          MagicItem(
            id: 'session-text-${startedAt.millisecondsSinceEpoch}',
            generationId: _idOf(res.raw),
            type: 'text',
            content: text,
            createdAt: DateTime.now().toUtc().toIso8601String(),
            tool: tool.id,
          ),
        ]);
      }
    } else if (res.status != null && res.status! >= 400 && res.status! < 500 && res.status != 408) {
      // A real refusal (validation, credits, 415) made no run.
      return MagicRunError(res.message.isNotEmpty ? res.message : 'Transcription failed. Please try again.');
    }

    // Queued, or the request was cut off while the backend carried on: follow
    // the record through history until it settles.
    onStillWorking?.call();
    return _followTextInHistory(config, tool, startedAt, isActive);
  }

  Future<MagicRunResult> _followTextInHistory(
    MagicToolConfig config,
    MagicStudioTool tool,
    DateTime startedAt,
    bool Function() isActive,
  ) async {
    final since = startedAt.subtract(const Duration(seconds: 15));
    while (isActive()) {
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed > _pollCeiling) return const MagicRunTimedOut();
      await Future<void>.delayed(magicNextPollDelay(elapsed));
      if (!isActive()) break;
      final records = await _history.list(config.historyTool);
      if (records == null) continue; // a failed CHECK is retried next beat
      final mine = records.where((r) {
        final at = DateTime.tryParse(r.startedAt ?? r.createdAt ?? '');
        return at != null && !at.isBefore(since);
      }).toList();
      if (mine.isEmpty) continue;
      final newest = mine.first;
      if (newest.pending) continue;
      return MagicRunDone([
        for (final r in mine.where((r) => r.generationId == newest.generationId)) _fromHistory(r, tool, ''),
      ]);
    }
    return const MagicRunCancelled();
  }

  static String _fileName(MagicAudioSource a) {
    final named = a.name.trim();
    if (named.contains('.')) return named;
    final path = Uri.tryParse(a.url)?.pathSegments.lastOrNull ?? '';
    return path.contains('.') ? path : 'audio.mp3';
  }

  static dynamic _unwrap(dynamic d) => d is Map && d['generation'] is Map ? d['generation'] : d;

  static String? _textOf(dynamic data) {
    final root = _unwrap(data);
    if (root is! Map) return null;
    for (final k in ['text', 'transcript', 'transcription', 'result', 'content']) {
      final v = root[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  static String? _idOf(dynamic data) {
    final root = _unwrap(data);
    final id = root is Map ? root['id'] : null;
    return id == null ? null : '$id';
  }
}
