import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/auth_controller.dart';
import 'copilot_api.dart';
import 'data/copilot_data.dart';

/// One copilot, in the shape the cards, avatar and settings render — port of
/// `adaptCopilot` in copilot/_data/copilots.js.
///
/// ⚠️ THE SERVER MODEL IS NARROWER THAN THE UI'S: a row is
/// `{ id, name, description, instructions, greeting, channels, allowed_tools }`
/// with no category, icon or tint. Those are derived here, in one place.
///
/// ⚠️ `channels: null` means EVERY channel and `allowed_tools: null` every
/// tool — null and [] are opposites, so [raw] keeps them as they came.
class Copilot {
  Copilot._(this.raw)
    : id = '${raw['id']}',
      name = (raw['name'] ?? 'Untitled copilot').toString(),
      description = (raw['description'] ?? '').toString(),
      // ⚠️ Not from the server — every copilot suggests the Brand starters
      // until the API carries a category (same default as the web).
      category = (raw['category'] ?? 'Brand').toString(),
      favorite = raw['favorite'] == true || raw['favorite'] == 1 || raw['favorite'] == '1';

  factory Copilot.fromRow(Map<String, dynamic> row) => Copilot._(Map<String, dynamic>.from(row));

  final Map<String, dynamic> raw;
  final String id;
  final String name;
  final String description;
  final String category;
  final bool favorite;

  DateTime? get createdAt => DateTime.tryParse('${raw['created_at'] ?? ''}');
  DateTime? get updatedAt => DateTime.tryParse('${raw['updated_at'] ?? ''}');

  /// "3 days ago" from the server's timestamp, or "recently" when none came back.
  String get editedAgo {
    final at = updatedAt ?? createdAt;
    return at == null ? 'recently' : distanceToNow(at);
  }

  /// Stable per id, so a copilot keeps its face between screens.
  int get _seed {
    final key = '${raw['id'] ?? raw['name'] ?? ''}';
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit).toSigned(32); // JS `| 0`
    }
    return hash.abs();
  }

  static const _glyphs = [
    LucideIcons.palette,
    LucideIcons.calendarDays,
    LucideIcons.megaphone,
    LucideIcons.camera,
    LucideIcons.radar,
    LucideIcons.mic,
  ];

  IconData get icon => _glyphs[_seed % _glyphs.length];

  /// blue-600 / emerald-600 / orange-500 / violet-600 / rose-500 / cyan-600.
  Color get tint => [AppColors.blue600, Tw.emerald600, Tw.orange500, Tw.violet600, Tw.rose500, Tw.cyan600][_seed % 6];

  Copilot patched(Map<String, dynamic> patch) => Copilot._({...raw, ...patch});
}

/// date-fns `formatDistanceToNow(at, { addSuffix: true })`, which the web uses
/// for "Last edited …".
String distanceToNow(DateTime at, [DateTime? now]) {
  final diff = (now ?? DateTime.now()).difference(at);
  final future = diff.isNegative;
  final secs = diff.inSeconds.abs();
  final mins = (secs / 60).round();
  String d;
  if (secs < 30) {
    d = 'less than a minute';
  } else if (mins <= 1) {
    d = '1 minute';
  } else if (mins < 45) {
    d = '$mins minutes';
  } else if (mins < 90) {
    d = 'about 1 hour';
  } else if (mins < 1440) {
    d = 'about ${(mins / 60).round()} hours';
  } else if (mins < 2520) {
    d = '1 day';
  } else if (mins < 43200) {
    d = '${(mins / 1440).round()} days';
  } else if (mins < 86400) {
    d = 'about ${(mins / 43200).round()} month${(mins / 43200).round() == 1 ? '' : 's'}';
  } else {
    final months = (mins / 43200).floor();
    if (months < 12) {
      d = '$months months';
    } else {
      final years = months ~/ 12, rem = months % 12;
      d = rem < 3
          ? 'about $years year${years == 1 ? '' : 's'}'
          : rem < 9
          ? 'over $years year${years == 1 ? '' : 's'}'
          : 'almost ${years + 1} years';
    }
  }
  return future ? 'in $d' : '$d ago';
}

/// The Copilot catalog — ONE list behind every Copilot screen. Port of the
/// module store in copilot/_data/copilots.js (and the "added skills" store at
/// the foot of _data/skills.js).
///
/// One store rather than state per screen is the point: starring on
/// /copilot/all has to show in the workspace the same instant, and deleting
/// has to drop it everywhere.
///
/// ⚠️ IT LOADS ONCE, ON FIRST USE, and [loading] starts true so nothing renders
/// "no copilots yet" during the round trip — an empty catalog and an unfinished
/// request look identical and mean opposite things.
class CopilotStore extends ChangeNotifier {
  CopilotStore._(this.api, this._owner);

  final CopilotApi api;
  final String _owner;

  static CopilotStore? _instance;

  /// The store for the signed-in account. A different user (sign-out, then
  /// someone else in) gets a fresh store rather than the last one's copilots.
  static CopilotStore of(BuildContext context) {
    final auth = context.read<AuthController>();
    final owner = '${auth.user?['id'] ?? auth.email}';
    final current = _instance;
    if (current != null && current._owner == owner) return current;
    final store = CopilotStore._(CopilotApi(auth.api), owner);
    _instance = store;
    store.refresh();
    return store;
  }

  List<Copilot> _items = const [];
  bool _loading = true;
  String? _error;

  List<Copilot> get items => _items;
  bool get loading => _loading;

  /// The server's own words (`describeApiError(...).text`), or null.
  String? get error => _error;

  Copilot? byId(String id) => _items.where((c) => c.id == id).firstOrNull;

  /// Re-read the catalog. Public so a failed load can be retried.
  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = _rowsFrom(await api.listCopilots());
    } catch (e) {
      _error = CopilotFailure.of(e).text;
    }
    _loading = false;
    notifyListeners();
  }

  /// The list out of a response, whichever envelope it arrives in.
  static List<Copilot> _rowsFrom(dynamic data) {
    final list = data is List ? data : (data is Map ? (data['data'] ?? data['copilots'] ?? data['items']) : null);
    return [
      if (list is List)
        for (final r in list)
          if (r is Map) Copilot.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  /// Optimistic write: change the list now, put the SNAPSHOT back if the
  /// server refuses (an inverse is only right if nothing moved in between).
  Future<void> _optimistic(List<Copilot> next, Future<dynamic> Function() request) async {
    final before = _items;
    _items = next;
    notifyListeners();
    try {
      await request();
    } catch (e) {
      _items = before;
      notifyListeners();
      rethrow;
    }
  }

  /// ⚠️ `favorite` is not a documented server field. Sent anyway rather than
  /// kept locally — a favourite on one phone only is not a favourite.
  Future<void> toggleFavorite(String id) {
    final favorite = !(byId(id)?.favorite ?? false);
    return _optimistic([
      for (final c in _items) c.id == id ? c.patched({'favorite': favorite}) : c,
    ], () => api.patchCopilot(id, {'favorite': favorite}));
  }

  /// Patch one copilot — a rename, or the Identity panel saving its brief.
  Future<void> update(String id, Map<String, dynamic> patch) =>
      _optimistic([for (final c in _items) c.id == id ? c.patched(patch) : c], () => api.patchCopilot(id, patch));

  Future<void> remove(String id) => _optimistic([
    for (final c in _items)
      if (c.id != id) c,
  ], () => api.destroyCopilot(id));

  /// Create one and put it first. ⚠️ Not optimistic — the id comes from the
  /// server, and a card with an invented id breaks when tapped. A create that
  /// answers with no record refetches and takes the newest.
  Future<Copilot> add(Map<String, dynamic> payload) async {
    final name = '${payload['name'] ?? ''}'.trim();
    if (name.isEmpty) throw const CopilotFailure(detail: 'Give the copilot a name.');
    final res = await api.createCopilot({...payload, 'name': name});
    Map<String, dynamic>? record;
    for (final c in [
      res is Map ? res['copilot'] : null,
      res is Map && res['data'] is Map ? (res['data'] as Map)['copilot'] : null,
      res is Map ? res['data'] : null,
      res,
    ]) {
      if (c is Map && c['id'] != null) {
        record = Map<String, dynamic>.from(c);
        break;
      }
    }
    if (record == null) {
      await refresh();
      final newest = _items.firstOrNull;
      if (newest == null) throw const CopilotFailure(detail: 'The copilot was created but could not be loaded.');
      return newest;
    }
    final created = Copilot.fromRow(record);
    _items = [created, ..._items];
    _loading = false;
    _error = null;
    notifyListeners();
    return created;
  }

  /// Duplicate a copilot — a real create, so the copy survives a reload.
  Future<Copilot?> clone(String id) async {
    final source = byId(id);
    if (source == null) return null;
    return add({
      'name': '${source.name} copy',
      'description': source.description,
      'instructions': source.raw['instructions'],
      'greeting': source.raw['greeting'],
      'channels': source.raw['channels'],
      'allowed_tools': source.raw['allowed_tools'],
    });
  }

  // ── Conversations minted this visit (copilots.js sessionConversations) ───
  //
  // ⚠️ OPENING A COPILOT LOADS ITS HISTORY. A minted `?c=` is the one thing that
  // says "a blank thread this time" — and it stops meaning that once the app
  // restarts, when what was said is in the server's history. Static: the
  // lifetime is the app process, the mobile counterpart of one page load.
  static final _sessionConversations = <String>{};

  static String newConversationId() {
    final id = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    _sessionConversations.add(id);
    return id;
  }

  static bool isSessionConversation(String? id) => id != null && _sessionConversations.contains(id);

  // ── Skills this workspace has added (skills.js store) ────────────────────
  // ⚠️ Local, like the web: the browse sheet's two tabs are two views of one fact.
  final List<String> addedSkills = [];

  void toggleSkill(String slug) {
    addedSkills.contains(slug) ? addedSkills.remove(slug) : addedSkills.add(slug);
    notifyListeners();
  }
}
