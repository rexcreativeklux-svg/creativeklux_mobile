import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';

/// The ad-campaign endpoints the Ads Content pages read — port of the ads half
/// of `(lib)/creativesApi.js` plus the helpers in `(lib)/integration.js` that
/// wrap them (`getAdCampaignStats`, `loadStatsForRows`, the ad branch of
/// `fetchLivePostsFromConnectedAccounts`) and AuthContext's `fetchIntegrations`.
///
///   GET    integrations                connected accounts
///   GET    creatives/campaigns         campaigns on one ad platform
///   GET    creatives/campaign-metrics  spend / impressions / clicks for one campaign
///   PATCH  creatives/campaign-status   pause or resume a campaign
///   DELETE creatives/campaign          delete a campaign
///
/// The brand is read server-side from the signed-in user's `active_brand_id`,
/// so these calls take no `brand_id` (same as the web).
///
/// Every failure throws an [AdsException] carrying the SERVER'S OWN WORDS —
/// while the contract settles, that text is the only thing worth showing.
class AdsApi {
  AdsApi(this._api);

  final ApiClient _api;

  /// Ad platforms the API knows (`SERVER_AD_PLATFORMS`; app ids match the API's).
  static const adPlatforms = ['meta_ads', 'google_ads', 'tiktok_ads', 'snapchat_ads', 'pinterest_ads'];

  /// Port of `serverMessage()` — the most specific thing the server said.
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

  /// Connected accounts (AuthContext `fetchIntegrations`). X arrives as `x`
  /// and is renamed `twitter`; a row at status 0 is still waiting for its
  /// account to be chosen, so it isn't connected.
  Future<List<Map<String, dynamic>>> integrations() async {
    final res = await _api.get('/integrations');
    if (!res.ok) throw AdsException(_serverMessage(res, "Couldn't load connected accounts"));
    final raw = res.raw;
    final rows = raw is List ? raw : (raw is Map && raw['data'] is List ? raw['data'] as List : null);
    if (rows == null) return const [];
    return [
      for (final r in rows)
        if (r is Map && '${r['status']}' != '0')
          {...Map<String, dynamic>.from(r), if (r['platform'] == 'x') 'platform': 'twitter'},
    ];
  }

  /// Campaigns on one ad platform, normalised by the API:
  /// `{ id, name, status, objective, daily_budget, created_time, thumbnail }`.
  Future<List<Map<String, dynamic>>> campaigns(String platform, {int limit = 25}) async {
    final res = await _api.get('/creatives/campaigns', query: {'platform': platform, 'limit': limit});
    if (!res.ok) throw AdsException(_serverMessage(res, "Couldn't load $platform campaigns"));
    final data = res.data;
    final list = data is List ? data : (data is Map ? data['campaigns'] : null);
    return [
      if (list is List)
        for (final c in list)
          if (c is Map) Map<String, dynamic>.from(c),
    ];
  }

  /// Port of `getAdCampaignStats`: `metrics` comes back as one object or as
  /// rows (per day / per breakdown), with only the numbers the network
  /// reports — rows are summed.
  Future<AdStats> campaignStats(String platform, String campaignId, {int days = 30}) async {
    final res = await _api.get(
      '/creatives/campaign-metrics',
      query: {'platform': platform, 'campaign_id': campaignId, 'days': days},
    );
    if (!res.ok) throw AdsException(_serverMessage(res, "Couldn't load $platform metrics"));
    final data = res.data;
    final raw = (data is Map ? data['metrics'] : null) ?? data ?? const {};
    final rows = raw is List ? raw : [raw];
    num sum(List<String> keys) {
      num total = 0;
      for (final row in rows) {
        if (row is! Map) continue;
        for (final k in keys) {
          final v = row[k];
          if (v == null || v == '') continue;
          final n = num.tryParse('$v');
          if (n != null) {
            total += n;
            break;
          }
        }
      }
      return total;
    }

    final impressions = sum(['impressions']);
    final clicks = sum(['clicks', 'link_clicks', 'swipes']);
    return AdStats(
      impressions: impressions,
      reach: sum(['reach']),
      clicks: clicks,
      ctr: impressions != 0 ? clicks / impressions * 100 : 0,
      spend: sum(['spend', 'cost']),
      conversions: sum(['conversions']),
      lastUpdated: DateTime.now(),
    );
  }

  /// Pause or resume a campaign. `status` is "ACTIVE" or "PAUSED" — resuming
  /// spends real money, so the caller confirms first.
  Future<void> setStatus(String platform, String campaignId, String status) async {
    final res = await _api.patch(
      '/creatives/campaign-status',
      body: {'platform': platform, 'campaign_id': campaignId, 'status': status},
    );
    if (!res.ok) throw AdsException(_serverMessage(res, "Couldn't update the campaign"));
  }

  /// Delete a campaign (and with it, on the network, its ad sets and ads).
  /// Irreversible — the caller confirms first.
  ///
  /// ⚠️ THE BODY IS PROVISIONAL on the web too: on 2026-10-28 the route
  /// answered 500 "campaignDestroy does not exist". `{ platform, campaign_id }`
  /// mirrors campaign-status, its closest sibling.
  Future<void> deleteCampaign(String platform, String campaignId) async {
    final res = await _api.delete('/creatives/campaign', body: {'platform': platform, 'campaign_id': campaignId});
    if (!res.ok) throw AdsException(_serverMessage(res, "Couldn't delete the campaign"));
  }

  /// The ad branch of `fetchLivePostsFromConnectedAccounts`: one call per
  /// connected ad platform, each campaign a row carrying the network's own
  /// status as it came back ("ACTIVE", "PAUSED", …) — nothing mapped or
  /// guessed. A platform that fails is skipped and its error collected, in the
  /// server's words, for the page to surface.
  ///
  /// The web also lists every connected SOCIAL platform's posts here, then
  /// drops them (these pages keep `type === "ad"` only). The phone skips those
  /// wasted calls — and with them, social-post errors on an ads page.
  Future<({List<AdCampaign> rows, List<String> errors})> liveCampaigns(List<Map<String, dynamic>> integrations) async {
    final errors = <String>[];
    final connected = adPlatforms.where((p) => integrations.any((i) => i['platform'] == p));
    final lists = await Future.wait(
      connected.map((platform) async {
        try {
          final list = await campaigns(platform);
          return [for (final c in list) AdCampaign.fromApi(platform, c)];
        } on AdsException catch (e) {
          errors.add('$platform: ${e.message}');
          return <AdCampaign>[];
        }
      }),
    );
    return (rows: [for (final l in lists) ...l], errors: errors);
  }

  /// Port of `loadStatsForRows`: each row's stats, a few at a time. A platform
  /// that has refused twice (e.g. missing permission) will refuse every row
  /// the same way, so it stops being asked; its first error is reported once.
  Future<({Map<String, AdStats> stats, Map<String, String> errors})> statsForRows(
    List<AdCampaign> rows, {
    int concurrency = 4,
  }) async {
    final stats = <String, AdStats>{};
    final errors = <String, String>{};
    final failures = <String, int>{};
    final queue = [...rows];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final row = queue.removeAt(0);
        if ((failures[row.platform] ?? 0) >= 2) continue;
        try {
          stats[row.id] = await campaignStats(row.platform, row.postId);
        } catch (e) {
          failures[row.platform] = (failures[row.platform] ?? 0) + 1;
          errors.putIfAbsent(row.platform, () => e is AdsException ? e.message : "Couldn't load stats");
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    return (stats: stats, errors: errors);
  }
}

/// One campaign row — the `type: "ad"` row `fetchLivePostsFromConnectedAccounts`
/// builds from a `creatives/campaigns` entry.
class AdCampaign {
  AdCampaign({
    required this.id,
    required this.title,
    required this.caption,
    required this.imageUrl,
    required this.platform,
    required this.status,
    required this.createdAt,
    required this.postId,
    this.dailyBudget,
    this.stats,
  });

  factory AdCampaign.fromApi(String platform, Map<String, dynamic> c) {
    final created = c['created_time'] == null ? null : DateTime.tryParse('${c['created_time']}')?.toLocal();
    final objective = c['objective']?.toString();
    final name = c['name']?.toString();
    final thumb = c['thumbnail']?.toString();
    final budget = c['daily_budget'];
    return AdCampaign(
      id: '${platform}_campaign_${c['id']}',
      title: name == null || name.isEmpty ? '$platform campaign' : name,
      caption: objective == null || objective.isEmpty ? '' : 'Objective: $objective',
      // The ad's own creative image, when the network gives one (Meta does;
      // Google sends null).
      imageUrl: thumb == null || thumb.isEmpty ? null : thumb,
      platform: platform,
      status: (c['status']?.toString().isNotEmpty ?? false) ? '${c['status']}' : 'UNKNOWN',
      createdAt: created,
      postId: '${c['id']}',
      dailyBudget: budget == null || budget == '' ? null : '$budget',
    );
  }

  final String id;
  final String title;
  final String caption;
  final String? imageUrl;
  final String platform;
  final String status;

  /// The only date the backend gives a campaign.
  final DateTime? createdAt;

  /// The network's own campaign id.
  final String postId;

  /// As the API sends it — whole units of the ad account's own currency.
  final String? dailyBudget;

  AdStats? stats;
}

/// A campaign's last-30-days numbers, held only for the page's lifetime.
class AdStats {
  const AdStats({
    this.impressions,
    this.reach,
    this.clicks,
    this.ctr,
    this.spend,
    this.conversions,
    this.likes,
    this.shares,
    this.lastUpdated,
  });

  final num? impressions;
  final num? reach;
  final num? clicks;
  final num? ctr;
  final num? spend;
  final num? conversions;

  /// Never filled by campaign metrics; the web's Publishing table still has
  /// the columns, so the cards keep them (they show "—").
  final num? likes;
  final num? shares;
  final DateTime? lastUpdated;
}

class AdsException implements Exception {
  AdsException(this.message);
  final String message;

  @override
  String toString() => message;
}
