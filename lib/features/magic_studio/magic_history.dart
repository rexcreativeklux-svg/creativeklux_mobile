import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/ui/toast.dart';
import '../editor/magic_panel/magic_history_api.dart';
import 'magic_studio_types.dart';

/// Loads (and lets you refresh / delete from) the generation history for one
/// Magic Studio tool. Port of `magic-studio/useMagicHistory.js`.
///
/// ⚠️ IT ALSO OWNS RUNS THAT ARE STILL GOING. History contains records the
/// backend hasn't finished — a generation row is written when the request
/// arrives and filled in when the provider answers, and the backend finishes the
/// work whether or not anyone is still watching. Those come back as [pending],
/// which is what lets the tool show a wait it never started: open the screen
/// after wandering off mid-generation and the loading tile is there again — and
/// turns into the result when it lands.
///
/// So there are two lists, and mixing them would put a tile with no picture in
/// a grid of pictures:
///
///   [items]    finished results, one per generated asset — what the lattice renders
///   [pending]  runs still in flight — what the loading tiles are drawn from
///
/// While [pending] is non-empty this polls itself on the shared escalating
/// schedule ([magicNextPollDelay]) and stops as soon as it empties.
///
/// A null tool (signed out, or a tool with nothing on the server) keeps this
/// empty and offline.
class MagicHistoryController extends ChangeNotifier {
  MagicHistoryController(ApiClient api, this.toolId) : _api = MagicHistoryApi(api), _loading = toolId != null {
    refresh();
  }

  final MagicHistoryApi _api;

  /// Backend tool enum (e.g. "text_to_image"), or null for "no history".
  final String? toolId;

  // Everything the server returned, finished and unfinished alike. The two
  // public lists are derived from this so a delete only has to touch one place.
  List<MagicHistoryItem> _records = const [];
  List<MagicItem> _items = const [];
  List<MagicHistoryItem> _pending = const [];
  bool _loading;
  String? _removingId;
  bool _disposed = false;

  // Stale-guard: only the latest fetch may commit its result.
  int _fetchToken = 0;

  Timer? _pollTimer;
  String _pollKey = '';

  /// Finished results, newest first, as lattice tiles.
  List<MagicItem> get items => _items;

  /// Runs still in flight — and recent enough to still be believed.
  List<MagicHistoryItem> get pending => _pending;

  /// The initial (or a user-asked) fetch is in flight. Never raised by the poll.
  bool get loading => _loading;

  /// The item whose delete is in flight.
  String? get removingId => _removingId;

  /// Re-fetch.
  ///
  /// [quiet] doesn't raise [loading]. ⚠️ USED BY THE POLL, and not an
  /// optimisation: this re-fetches every few seconds while a run is in flight,
  /// and flagging each one as "loading" would blink the History button's
  /// spinner and the empty state for the whole wait.
  Future<void> refresh({bool quiet = false}) async {
    final tool = toolId;
    if (tool == null) {
      _setRecords(const []);
      _loading = false;
      _notify();
      return;
    }
    final token = ++_fetchToken;
    if (!quiet && !_loading) {
      _loading = true;
      _notify();
    }
    // A failed load is treated as "no history" for display, like the web.
    final list = await _api.list(tool);
    if (_disposed || token != _fetchToken) return;
    _setRecords(list ?? const []);
    if (!quiet) _loading = false;
    _notify();
  }

  /// Delete one generation. Optimistically drops it; on failure the error is
  /// toasted and the true state is re-fetched.
  ///
  /// ⚠️ TAKES AN ITEM AND DELETES A RECORD — the two are not the same thing when
  /// one generation made four images. All four tiles go at once, because there
  /// is one record behind them and the backend can't remove a single asset.
  Future<void> remove(MagicItem item) async {
    if (_removingId != null) return;
    final generationId = item.generationId ?? item.id.split(':').first;
    _removingId = item.id;
    final prev = _records;
    _setRecords([
      for (final r in _records)
        if (r.generationId != generationId) r,
    ]);
    _notify();
    final error = await _api.delete(generationId);
    if (_disposed) return;
    if (error == null) {
      Toast.success('Deleted');
    } else {
      Toast.error(error);
      _setRecords(prev);
      unawaited(refresh());
    }
    _removingId = null;
    _notify();
  }

  void _setRecords(List<MagicHistoryItem> records) {
    _records = records;
    _items = [
      for (final r in records)
        if (!r.pending) _toItem(r),
    ];
    // ⚠️ THE AGE CHECK IS WHAT STOPS A DEAD JOB HAUNTING THE TOOL. A backend that
    // crashes mid-run leaves a row stuck on "processing" forever; without a
    // cutoff every visit would open on a loading tile for a generation that is
    // never coming, and the poll would never stop.
    _pending = [
      for (final r in records)
        if (r.pending && magicElapsedSince(r.startedAt ?? r.createdAt) < magicStaleAfter) r,
    ];
    _syncPoll();
  }

  MagicItem _toItem(MagicHistoryItem r) => MagicItem(
    id: r.id,
    generationId: r.generationId,
    type: r.type ?? 'image',
    url: r.url,
    thumbnail: r.thumbnail,
    content: r.content,
    prompt: r.prompt,
    createdAt: r.createdAt,
    tool: toolId,
  );

  // ── Polling, while anything is still running ───────────────────────────────
  // Keyed on WHICH runs are pending rather than on the list, so an unchanged
  // set doesn't tear down and restart the timer on every refresh.
  void _syncPoll() {
    final key = _pending.map((r) => r.generationId).join(',');
    if (key == _pollKey && (_pollTimer != null || key.isEmpty)) return;
    _pollKey = key;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (key.isEmpty || _disposed) return;
    debugPrint('⏳ [magic-studio] $toolId: watching $key');
    _beat();
  }

  void _beat() {
    // Paced off how long the OLDEST run has been going, not off when this
    // screen opened — coming back to a job that started four minutes ago should
    // resume at its unhurried cadence, not hammer it as if it were new.
    var elapsed = Duration.zero;
    for (final r in _pending) {
      final e = magicElapsedSince(r.startedAt ?? r.createdAt);
      if (e > elapsed) elapsed = e;
    }
    final key = _pollKey;
    _pollTimer = Timer(magicNextPollDelay(elapsed), () async {
      if (_disposed || key != _pollKey) return;
      await refresh(quiet: true);
      // A refresh that changed the set has already restarted the timer.
      if (!_disposed && key == _pollKey && _pollKey.isNotEmpty) _beat();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }
}
