import 'dart:async';

import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';

/// One post as the Publishing / Calendar / Analytics pages render it — the
/// row shape `normalizeLivePosts` builds in the web's `(lib)/integration.js`.
///
/// Nothing is cached on the device: every row is the backend's answer from
/// this screen's own load, exactly like the web (which keeps nothing in the
/// browser either).
class SocialPost {
  SocialPost({
    required this.id,
    required this.projectTitle,
    required this.caption,
    required this.imageUrl,
    required this.platform,
    required this.type,
    required this.status,
    required this.publishedAt,
    required this.scheduledAt,
    required this.postId,
    required this.permalinkUrl,
    this.stats,
  });

  /// `<prefix>_<platform id>`, e.g. `fb_123` — unique across platforms.
  final String id;
  final String projectTitle;
  final String caption;
  final String? imageUrl;
  final String platform;

  /// `social` (always, for the rows this section reads).
  final String type;

  /// `published` | `scheduled` — "scheduled" is a post the platform itself
  /// reports as scheduled (Facebook's `scheduled_publish_time`).
  final String status;
  final DateTime? publishedAt;
  final DateTime? scheduledAt;
  final String? postId;
  final String? permalinkUrl;

  /// The post's metrics, once loaded. Null = never asked for (shown as "—").
  PostStats? stats;

  /// The date that places the post: its schedule when scheduled, else when it
  /// went out.
  DateTime? get when => status == 'scheduled' ? scheduledAt : publishedAt;
}

/// Port of the object `normalizeMetrics` returns. A metric the platform did
/// not send stays null (shown as "—"), never 0: Facebook reports no
/// impressions for a post, and a 0 would claim it had none.
class PostStats {
  const PostStats({
    this.impressions,
    this.reach,
    this.clicks,
    this.likes,
    this.comments,
    this.shares,
    this.saves,
    this.ctr,
    this.lastUpdated,
  });

  final num? impressions;
  final num? reach;
  final num? clicks;
  final num? likes;
  final num? comments;
  final num? shares;
  final num? saves;

  /// Never sent by creatives/post-metrics today; kept because the web's table
  /// has a CTR column that reads it.
  final num? ctr;
  final DateTime? lastUpdated;

  PostStats stamped() => PostStats(
    impressions: impressions,
    reach: reach,
    clicks: clicks,
    likes: likes,
    comments: comments,
    shares: shares,
    saves: saves,
    ctr: ctr,
    lastUpdated: DateTime.now(),
  );
}

/// The live list plus the server's own words for each platform that failed
/// (the web rides them on the array as `rows.errors`).
class LivePosts {
  LivePosts(this.rows, this.errors);
  final List<SocialPost> rows;
  final List<String> errors;
}

class SocialApiException implements Exception {
  SocialApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The calls the Social Content section makes — a port of the slices of
/// `(lib)/integration.js` + `(lib)/creativesApi.js` it uses, plus
/// AuthContext's `fetchIntegrations`:
///
///   GET    /integrations            connected accounts
///   GET    creatives/posts          recent posts on one platform
///   GET    creatives/post-metrics   engagement for one post
///   DELETE creatives/post           remove a published post
///
/// The API holds the platform tokens; the app never touches a platform API.
/// Every failure is thrown as a [SocialApiException] carrying the SERVER'S OWN
/// WORDS — that text names the real problem, so the pages show it as-is.
class SocialContentApi {
  SocialContentApi(this._api);

  final ApiClient _api;

  /// Social platforms the publishing API covers (app-side ids) —
  /// `SERVER_PUBLISH_PLATFORMS`.
  static const publishPlatforms = ['facebook', 'instagram', 'twitter', 'linkedin', 'youtube', 'pinterest', 'tiktok'];

  /// Platforms whose posts get a delete button (`SERVER_DELETE_PLATFORMS`).
  /// Instagram and TikTok are asked too, even though their APIs don't allow
  /// it: the backend answers with its own reason, and that is shown as-is.
  static const deletePlatforms = publishPlatforms;

  /// Platforms creatives/post-metrics answers for (`POST_STATS_PLATFORMS`).
  static const statsPlatforms = ['facebook', 'instagram', 'youtube'];

  static bool supportsDelete(String platform) => deletePlatforms.contains(platform);

  /// The API's platform keys, where they differ from the app's.
  static String toApiPlatform(String p) => p == 'twitter' ? 'x' : p;

  static int _requireBrand(int? brandId) {
    if (brandId == null) throw SocialApiException('Select a brand first.');
    return brandId;
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

  // ── Integrations ──────────────────────────────────────────────────────────

  /// Connected accounts — port of AuthContext's `fetchIntegrations`.
  ///
  /// Throws with the server's own message when the lookup fails, so a broken
  /// endpoint is never mistaken for "no accounts connected" (why this doesn't
  /// reuse `PublishApi.integrations`, which folds a failure into null).
  /// X arrives as `x` and is renamed `twitter`; a row at status 0 is still
  /// waiting for its account to be chosen, so it isn't connected.
  Future<List<Map<String, dynamic>>> integrations() async {
    final res = await _api.get('/integrations');
    if (!res.ok) {
      if (res.status == null) throw SocialApiException(res.message);
      final b = res.body;
      final msg = b['message'] ?? b['error'];
      throw SocialApiException(
        msg is String && msg.isNotEmpty ? msg : "Couldn't load connected accounts (HTTP ${res.status})",
      );
    }
    final raw = res.raw;
    final rows = raw is List ? raw : (raw is Map && raw['data'] is List ? raw['data'] as List : null);
    if (rows == null) return [];
    return [
      for (final r in rows)
        if (r is Map && '${r['status']}' != '0')
          {...Map<String, dynamic>.from(r), if (r['platform'] == 'x') 'platform': 'twitter'},
    ];
  }

  // ── Posts ─────────────────────────────────────────────────────────────────

  /// Port of `fetchLivePostsFromConnectedAccounts`, social half: one
  /// `creatives/posts` call per connected platform, in parallel. LinkedIn has
  /// no post listing for third-party apps, so it isn't asked. A platform that
  /// fails is skipped and its error kept, in the server's words, for the page
  /// to surface.
  ///
  /// The web also lists ad campaigns here (`type: 'ad'` rows) — and every
  /// social page then filters them straight back out. They aren't fetched.
  Future<LivePosts> livePosts(List<Map<String, dynamic>> integrations, int? brandId) async {
    final connected = publishPlatforms
        .where((p) => p != 'linkedin')
        .where((p) => integrations.any((i) => i['platform'] == p))
        .toList();
    final errors = <String>[];
    final lists = await Future.wait(
      connected.map((platform) async {
        try {
          final data = await _platformPosts(platform, brandId);
          return _normalizeLivePosts(platform, data);
        } on SocialApiException catch (e) {
          errors.add('$platform: ${e.message}');
          return <SocialPost>[];
        }
      }),
    );
    return LivePosts([for (final l in lists) ...l], errors);
  }

  /// Recent posts on one platform — `data` is whatever that platform returns.
  Future<dynamic> _platformPosts(String platform, int? brandId) async {
    final res = await _api.get(
      '/creatives/posts',
      query: {'brand_id': _requireBrand(brandId), 'platform': toApiPlatform(platform), 'limit': 20},
    );
    if (!res.ok) throw SocialApiException(_serverMessage(res, "Couldn't load $platform posts"));
    return res.data;
  }

  /// A platform's own post list → rows (port of `normalizeLivePosts`). The
  /// shape differs per network, so every field is read defensively.
  static List<SocialPost> _normalizeLivePosts(String platform, dynamic data) {
    dynamic rows = data;
    if (rows is Map) {
      rows = rows['data'] ?? rows['posts'] ?? rows['items'] ?? rows['videos'] ?? rows['tweets'] ?? rows['pins'];
    }
    if (rows is! List) return [];

    const prefixes = {'facebook': 'fb', 'instagram': 'ig', 'twitter': 'x', 'youtube': 'yt'};
    final prefix = prefixes[platform] ?? platform;

    String? str(dynamic v) => v == null || '$v'.isEmpty ? null : '$v';
    String? first(Iterable<dynamic> vs) {
      for (final v in vs) {
        final s = str(v);
        if (s != null) return s;
      }
      return null;
    }

    final out = <SocialPost>[];
    for (final p in rows) {
      if (p is! Map) continue;
      final snippet = p['snippet'] is Map ? p['snippet'] as Map : const {};
      final rawId = p['id'];
      final id = first([rawId is Map ? rawId['videoId'] : rawId, p['video_id'], p['pin_id']]);
      if (id == null) continue;

      final text =
          first([
            p['message'],
            p['caption'],
            p['text'],
            p['description'],
            p['video_description'],
            snippet['description'],
          ]) ??
          '';
      final title =
          first([p['title'], snippet['title'], p['story']]) ?? (text.length > 60 ? text.substring(0, 60) : text);
      final scheduledAt = _toDate(p['scheduled_publish_time']);
      final thumbs = snippet['thumbnails'] is Map ? snippet['thumbnails'] as Map : const {};
      final media = p['media'] is Map ? p['media'] as Map : const {};
      final images = media['images'] is Map ? media['images'] as Map : const {};

      out.add(
        SocialPost(
          id: '${prefix}_$id',
          projectTitle: title.isNotEmpty ? title : '$platform post',
          caption: text,
          imageUrl: first([
            p['full_picture'],
            p['thumbnail_url'],
            p['media_url'],
            p['cover_image_url'],
            p['image_url'],
            thumbs['high'] is Map ? thumbs['high']['url'] : null,
            thumbs['default'] is Map ? thumbs['default']['url'] : null,
            images['600x'] is Map ? images['600x']['url'] : null,
          ]),
          platform: platform,
          type: 'social',
          status: scheduledAt != null ? 'scheduled' : 'published',
          publishedAt: scheduledAt != null
              ? null
              : _toDate(
                  p['created_time'] ?? p['timestamp'] ?? p['created_at'] ?? p['create_time'] ?? snippet['publishedAt'],
                ),
          scheduledAt: scheduledAt,
          postId: id,
          permalinkUrl: first([p['permalink_url'], p['permalink'], p['share_url'], p['url'], p['link']]),
        ),
      );
    }
    return out;
  }

  /// Unix seconds (TikTok `create_time`, Facebook `scheduled_publish_time`) or
  /// an ISO string → local time; null when it doesn't parse.
  static DateTime? _toDate(dynamic v) {
    if (v == null || v == '') return null;
    if (v is num) return DateTime.fromMillisecondsSinceEpoch((v * 1000).round()).toLocal();
    final s = '$v';
    if (RegExp(r'^\d+$').hasMatch(s)) return DateTime.fromMillisecondsSinceEpoch(int.parse(s) * 1000).toLocal();
    // Facebook sends `+0000` offsets, which DateTime.parse doesn't take.
    final fixed = s.replaceFirstMapped(RegExp(r'([+-]\d{2})(\d{2})$'), (m) => '${m[1]}:${m[2]}');
    return DateTime.tryParse(fixed)?.toLocal();
  }

  /// Carry the metrics this screen already pulled over to a fresh list (port
  /// of `carryStats`): metrics are a separate call per row, so a refetch of
  /// the list shouldn't blank them.
  static List<SocialPost> carryStats(List<SocialPost> prev, List<SocialPost> next) {
    final byId = {for (final r in prev) r.id: r.stats};
    for (final r in next) {
      final s = byId[r.id];
      if (s != null) r.stats = s;
    }
    return next;
  }

  // ── Metrics ───────────────────────────────────────────────────────────────

  /// One post's metrics (`getPostStats`), stamped with the time they landed.
  Future<PostStats> postStats(SocialPost post, int? brandId) async {
    final res = await _api.get(
      '/creatives/post-metrics',
      query: {'brand_id': _requireBrand(brandId), 'platform': toApiPlatform(post.platform), 'post_id': post.postId},
    );
    if (!res.ok) throw SocialApiException(_serverMessage(res, "Couldn't load ${post.platform} metrics"));
    return _normalizeMetrics(res.data).stamped();
  }

  /// Port of `loadStatsForRows`: metrics for many rows, four requests at a
  /// time. Each platform's failure is kept once, in the server's own words,
  /// so a page reports "Instagram: no permission" a single time rather than
  /// per row. A platform that refused twice will refuse every row the same
  /// way, so its remaining rows are skipped.
  Future<({Map<String, PostStats> stats, Map<String, String> errors})> statsForRows(
    List<SocialPost> rows,
    int? brandId, {
    int concurrency = 4,
  }) async {
    final stats = <String, PostStats>{};
    final errors = <String, String>{};
    final failures = <String, int>{};
    final queue = [...rows];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final row = queue.removeAt(0);
        if ((failures[row.platform] ?? 0) >= 2) continue;
        try {
          stats[row.id] = await postStats(row, brandId);
        } on SocialApiException catch (e) {
          failures[row.platform] = (failures[row.platform] ?? 0) + 1;
          errors.putIfAbsent(row.platform, () => e.message);
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    return (stats: stats, errors: errors);
  }

  /// creatives/post-metrics passes through whatever the platform returns, so
  /// the numbers are pulled from wherever they are (flat fields, or an
  /// `insights` / `metrics` / `public_metrics` object). Facebook sends
  /// `likes`/`shares`; YouTube sends camelCase strings (`viewCount`, …).
  static PostStats _normalizeMetrics(dynamic data) {
    final d = data is Map ? data : const {};
    final src = <dynamic, dynamic>{
      ...d,
      if (d['insights'] is Map) ...d['insights'] as Map,
      if (d['metrics'] is Map) ...d['metrics'] as Map,
      if (d['public_metrics'] is Map) ...d['public_metrics'] as Map,
    };
    num? pick(List<String> keys) {
      for (final k in keys) {
        final v = src[k];
        if (v is num) return v;
        if (v is String && v.isNotEmpty && num.tryParse(v) != null) return num.parse(v);
        if (v is Map) {
          final summary = v['summary'];
          if (summary is Map && summary['total_count'] != null) return num.tryParse('${summary['total_count']}');
          if (v['count'] is num) return v['count'] as num;
        }
      }
      return null;
    }

    return PostStats(
      impressions: pick(['impressions', 'impression_count', 'views', 'view_count', 'viewCount']),
      reach: pick(['reach']),
      clicks: pick(['clicks', 'link_clicks']),
      likes: pick(['likes', 'like_count', 'likeCount', 'reactions']),
      comments: pick(['comments', 'comment_count', 'commentCount', 'reply_count']),
      shares: pick(['shares', 'share_count', 'retweet_count']),
      saves: pick(['saves', 'saved', 'bookmark_count', 'favoriteCount']),
    );
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  /// Delete a post through the backend (`deletePostFromPlatform`). Throws with
  /// the backend's own words when it refuses — the post is still on the
  /// platform then, so the caller keeps the row. Irreversible: confirm first.
  Future<void> deletePost(SocialPost post, int? brandId) async {
    if (!supportsDelete(post.platform) || post.postId == null) {
      throw SocialApiException("${post.platform} posts can't be deleted from here.");
    }
    final res = await _api.delete(
      '/creatives/post',
      body: {'brand_id': _requireBrand(brandId), 'platform': toApiPlatform(post.platform), 'post_id': post.postId},
    );
    if (!res.ok) throw SocialApiException(_serverMessage(res, "Couldn't delete the ${post.platform} post"));
  }
}
