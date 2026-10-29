import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'ads_api.dart';
import 'ads_widgets.dart';

/// Port of `ads-content/publishing/page.jsx` — the brand's campaigns on each
/// connected ad network, with their last-30-days numbers, pause / resume and
/// delete.
///
/// Nothing is kept on the device: what's on screen is always the backend's
/// answer. Phone layout: the web's 11-column table becomes one card per
/// campaign (title, platform, status, created, the six stat cells, actions).
class AdsPublishingScreen extends StatefulWidget {
  const AdsPublishingScreen({super.key});

  static const path = '/ads-content/publishing';

  @override
  State<AdsPublishingScreen> createState() => _AdsPublishingScreenState();
}

class _AdsPublishingScreenState extends State<AdsPublishingScreen> {
  static const _pageSize = 10;

  late final AdsApi _api;
  final _search = TextEditingController();

  List<Map<String, dynamic>> _integrations = const [];
  List<AdCampaign> _rows = [];

  /// First load only — the "no ads yet" empty state must never flash at
  /// someone who does have campaigns.
  bool _loading = true;
  bool _fetchingLive = false;
  String? _refreshing;
  String? _toggling;

  String _status = 'all';
  String _platform = 'all';
  int _page = 1;

  int? _brandId;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _api = AdsApi(context.read<AuthController>().api);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A brand switch clears the previous brand's campaigns and holds the
    // skeleton until the backend answers for the new one. The integrations are
    // re-read too: the endpoint scopes them to the brand the backend has active.
    final brandId = context.watch<AuthController>().activeBrand?.id;
    if (brandId != _brandId) {
      _brandId = brandId;
      _init();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final run = ++_run;
    setState(() {
      _rows = [];
      _loading = true;
    });
    // 1. Integrations first. A failed lookup still has to unblock step 2 —
    //    otherwise the skeleton would never resolve.
    try {
      final list = await _api.integrations();
      if (!mounted || run != _run) return;
      _integrations = list;
    } on AdsException catch (e) {
      if (!mounted || run != _run) return;
      Toast.error(e.message);
      _integrations = const [];
    }
    // 2. The campaigns, exactly as the backend lists them.
    await _loadCampaigns(silent: true, run: run);
  }

  Future<void> _loadCampaigns({bool silent = false, int? run}) async {
    run ??= _run;
    setState(() => _fetchingLive = true);
    List<AdCampaign> rows = [];
    try {
      final res = await _api.liveCampaigns(_integrations);
      if (!mounted || run != _run) return;
      rows = res.rows;
      // carryStats: a refetch of the list shouldn't blank the numbers this
      // session already pulled for the same rows.
      final prev = {for (final r in _rows) r.id: r.stats};
      for (final r in rows) {
        r.stats ??= prev[r.id];
      }
      setState(() => _rows = rows);
      // A platform the backend couldn't read: show its own error, always.
      if (res.errors.isNotEmpty) Toast.error(res.errors.join(' · '));
      if (!silent) Toast.success('Loaded ${rows.length} campaign${rows.length == 1 ? '' : 's'}');
    } catch (e) {
      Toast.error(e is AdsException ? e.message : "Couldn't load campaigns");
    } finally {
      if (mounted && run == _run) {
        setState(() {
          _fetchingLive = false;
          _loading = false;
        });
      }
    }
    // After the list is up — the numbers fill in as they arrive.
    if (rows.isNotEmpty && mounted && run == _run) _loadAllStats(rows, run);
  }

  Future<void> _loadAllStats(List<AdCampaign> rows, int run) async {
    final targets = rows.where((p) => p.postId.isNotEmpty).toList();
    if (targets.isEmpty) return;
    final res = await _api.statsForRows(targets);
    if (!mounted || run != _run) return;
    setState(() {
      for (final p in _rows) {
        final s = res.stats[p.id];
        if (s != null) p.stats = s;
      }
    });
    res.errors.forEach((platform, message) => Toast.error('${platformMetaOf(platform).label} stats: $message'));
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Campaign spend / impressions / clicks over the last 30 days, held only
  /// for this page's lifetime.
  Future<void> _refreshStats(AdCampaign post) async {
    setState(() => _refreshing = post.id);
    try {
      final stats = await _api.campaignStats(post.platform, post.postId);
      if (!mounted) return;
      setState(() => post.stats = stats);
      Toast.success('Stats loaded');
    } catch (e) {
      Toast.error("Couldn't load stats: ${e is AdsException ? e.message : e}");
    } finally {
      if (mounted) setState(() => _refreshing = null);
    }
  }

  /// Pause or resume a campaign on its network, then re-read the list so the
  /// status shown is the one the backend now reports.
  Future<void> _setStatus(AdCampaign post, String status) async {
    setState(() => _toggling = post.id);
    try {
      await _api.setStatus(post.platform, post.postId, status);
      await _loadCampaigns(silent: true);
      Toast.success(status == 'ACTIVE' ? 'Campaign resumed' : 'Campaign paused');
    } catch (e) {
      Toast.error(e is AdsException ? e.message : "Couldn't update the campaign");
    } finally {
      if (mounted) setState(() => _toggling = null);
    }
  }

  /// Resuming a campaign starts spending, so it waits on a confirm; pausing doesn't.
  void _confirmResume(AdCampaign post) {
    showConfirmDialog(
      context,
      title: 'Resume this campaign?',
      message:
          '“${post.title.isEmpty ? 'Untitled' : post.title}” will go live on '
          '${platformMetaOf(post.platform).label} and start spending its budget.',
      confirmLabel: 'Resume',
      onConfirm: () => _setStatus(post, 'ACTIVE'),
    );
  }

  /// Delete a campaign on its network, then re-read the list. A refusal keeps
  /// the row — the campaign is still there.
  void _confirmDelete(AdCampaign post) {
    showConfirmDialog(
      context,
      title: 'Delete this campaign?',
      message:
          '“${post.title.isEmpty ? 'Untitled' : post.title}” and its ads will be deleted from '
          "${platformMetaOf(post.platform).label}. This can't be undone.",
      confirmLabel: 'Delete',
      danger: true,
      onConfirm: () async {
        try {
          await _api.deleteCampaign(post.platform, post.postId);
          await _loadCampaigns(silent: true);
          Toast.success('Campaign deleted');
        } catch (e) {
          Toast.error(e is AdsException ? e.message : "Couldn't delete the campaign");
        }
      },
    );
  }

  void _setFilter(VoidCallback change) => setState(() {
    change();
    _page = 1;
  });

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AdsSectionScaffold(location: AdsPublishingScreen.path, child: _loading ? _skeleton() : _body(context));
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    final posts = _rows;
    // Newest → oldest by creation date.
    final filtered = filterCampaigns(posts, status: _status, platform: _platform, search: _search.text)
      ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    final totalPages = max(1, (filtered.length / _pageSize).ceil());
    final page = _page.clamp(1, totalPages);
    final paged = filtered.skip((page - 1) * _pageSize).take(_pageSize).toList();
    final hasConnections = _integrations.isNotEmpty;
    final counts = {
      'all': posts.length,
      'ACTIVE': posts.where((p) => p.status == 'ACTIVE').length,
      'PAUSED': posts.where((p) => p.status == 'PAUSED').length,
    };

    return RefreshIndicator(
      onRefresh: () => _loadCampaigns(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          AdsPageHeader(
            title: 'Ads Publishing',
            subtitle: 'Your campaigns on each connected ad network.',
            action: hasConnections
                ? AdsButton(
                    label: _fetchingLive ? 'Refreshing…' : 'Refresh',
                    icon: LucideIcons.refreshCw,
                    spinning: _fetchingLive,
                    onTap: _fetchingLive ? null : () => _loadCampaigns(),
                  )
                : AdsButton(label: 'Connect Platforms →', filled: true, onTap: () => context.push('/integrations')),
          ),
          const SizedBox(height: 20),
          if (posts.isNotEmpty) ...[
            _summary(posts, counts),
            const SizedBox(height: 20),
            AdsFilterPanel(
              status: _status,
              counts: counts,
              onStatus: (s) => _setFilter(() => _status = s),
              platform: _platform,
              platformGroupLabel: '── Advertising',
              platformOptions: [
                for (final e in adPlatformMeta.entries)
                  if (e.value.ads) (e.key, '${e.value.emoji} ${e.value.label}'),
              ],
              onPlatform: (p) => _setFilter(() => _platform = p),
              search: _search,
              onSearch: (_) => _setFilter(() {}),
              resultCount: filtered.length,
            ),
            const SizedBox(height: 14),
          ],
          if (posts.isNotEmpty && filtered.isEmpty)
            AdsEmptyState(
              icon: LucideIcons.search,
              title: 'No ads match your filters',
              message: const Text('Try adjusting the platform, status, or search query.'),
              action: AdsButton(
                label: 'Clear Filters',
                onTap: () => _setFilter(() {
                  _status = 'all';
                  _platform = 'all';
                  _search.clear();
                }),
              ),
            ),
          if (posts.isEmpty)
            AdsEmptyState(
              accent: true,
              icon: LucideIcons.calendar,
              title: 'No campaigns yet',
              message: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Go to your Creatives, open a design, and tap '),
                    TextSpan(
                      text: 'Publish',
                      style: TextStyle(fontWeight: FontWeight.w600, color: c.gray600),
                    ),
                    const TextSpan(text: ' to get started.'),
                  ],
                ),
              ),
              action: AdsButton(label: 'Go to Creatives', filled: true, onTap: () => context.go('/creatives')),
            ),
          for (final post in paged) ...[_CampaignCard(post: post, state: this), const SizedBox(height: 10)],
          if (paged.isNotEmpty) _pager(context, page, totalPages, filtered.length),
        ],
      ),
    );
  }

  Widget _summary(List<AdCampaign> posts, Map<String, int> counts) {
    // A dash until some row's stats are loaded — a 0 would claim no
    // impressions when they simply haven't been asked for.
    final anyImpr = posts.any((p) => p.stats?.impressions != null);
    final impr = posts.fold<num>(0, (s, p) => s + (p.stats?.impressions ?? 0));
    final cards = [
      _SummaryCard(label: 'Total Ads', value: '${posts.length}', icon: LucideIcons.chartColumn),
      _SummaryCard(label: 'Active', value: '${counts['ACTIVE']}', icon: LucideIcons.circleCheck),
      _SummaryCard(label: 'Paused', value: '${counts['PAUSED']}', icon: LucideIcons.circlePause),
      _SummaryCard(label: 'Impressions (loaded rows)', value: anyImpr ? groupDigits(impr) : '—', icon: LucideIcons.eye),
    ];
    return Column(
      children: [
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: cards[i]),
              const SizedBox(width: 10),
              Expanded(child: cards[i + 1]),
            ],
          ),
        ],
      ],
    );
  }

  Widget _pager(BuildContext context, int page, int totalPages, int total) {
    final c = context.colors;
    final from = total == 0 ? 0 : (page - 1) * _pageSize + 1;
    final to = min(page * _pageSize, total);
    Widget box({required Widget child, VoidCallback? onTap, bool active = false}) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: active ? AppColors.blue600 : null, borderRadius: BorderRadius.circular(6)),
        child: child,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          Text('Showing $from–$to of $total ads', style: TextStyle(fontSize: 12, color: c.gray400)),
          if (totalPages > 1) ...[
            const SizedBox(height: 8),
            // Every page gets its own number, so a long list wraps instead of
            // running off the screen (as on the web).
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                Opacity(
                  opacity: page == 1 ? 0.3 : 1,
                  child: box(
                    onTap: page == 1 ? null : () => setState(() => _page = page - 1),
                    child: Icon(LucideIcons.chevronLeft, size: 16, color: c.gray500),
                  ),
                ),
                for (var n = 1; n <= totalPages; n++)
                  box(
                    active: n == page,
                    onTap: () => setState(() => _page = n),
                    child: Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: n == page ? Colors.white : c.gray500,
                      ),
                    ),
                  ),
                Opacity(
                  opacity: page == totalPages ? 0.3 : 1,
                  child: box(
                    onTap: page == totalPages ? null : () => setState(() => _page = page + 1),
                    child: Icon(LucideIcons.chevronRight, size: 16, color: c.gray500),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// `PublishingSkeleton`: header, four summary tiles, the filter bar, rows.
  Widget _skeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const SkeletonBox(width: 170, height: 20),
        const SizedBox(height: 8),
        const SkeletonBox(width: 240, height: 12),
        const SizedBox(height: 22),
        for (var i = 0; i < 2; i++) ...[
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: 62, radius: 12)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 62, radius: 12)),
            ],
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        const SkeletonBox(height: 110, radius: 12),
        const SizedBox(height: 14),
        for (var i = 0; i < 3; i++) ...[const SkeletonBox(height: 170, radius: 12), const SizedBox(height: 10)],
      ],
    );
  }
}

/// Port of `SummaryCard`.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AdsCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.blue600.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppColors.blue600),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.gray900),
                ),
                Text(label, maxLines: 2, style: TextStyle(fontSize: 11, color: c.gray500, height: 1.2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One table row of the web, as a card.
class _CampaignCard extends StatelessWidget {
  const _CampaignCard({required this.post, required this.state});

  final AdCampaign post;
  final _AdsPublishingScreenState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stats = post.stats ?? const AdStats();
    final toggling = state._toggling == post.id;
    final refreshing = state._refreshing == post.id;
    // Only the two states the backend can switch between.
    final canToggle = post.status == 'ACTIVE' || post.status == 'PAUSED';
    final hasId = post.postId.isNotEmpty;

    return AdsCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdThumb(url: post.imageUrl, size: 42),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray800),
                      ),
                      if (post.caption.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            post.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: c.gray400),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(post.status),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PlatformPill(post.platform),
              Text(formatCreated(post.createdAt), style: TextStyle(fontSize: 11.5, color: c.gray500)),
              if (post.dailyBudget != null)
                Text('· ${post.dailyBudget}/day budget', style: TextStyle(fontSize: 11.5, color: c.gray500)),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: c.gray50, borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  Row(
                    children: [
                      _StatCell(LucideIcons.eye, 'Impr.', metric(stats.impressions)),
                      _StatCell(LucideIcons.users, 'Reach', metric(stats.reach)),
                      _StatCell(LucideIcons.mousePointer, 'Clicks', metric(stats.clicks)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _StatCell(LucideIcons.heart, 'Likes', metric(stats.likes)),
                      _StatCell(LucideIcons.share2, 'Shares', metric(stats.shares)),
                      _StatCell(LucideIcons.trendingUp, 'CTR', ctrText(stats.ctr)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (canToggle)
                _ActionButton(
                  tooltip: post.status == 'ACTIVE' ? 'Pause campaign' : 'Resume campaign',
                  color: AppColors.blue500,
                  busy: toggling,
                  icon: post.status == 'ACTIVE' ? LucideIcons.pause : LucideIcons.play,
                  onTap: toggling
                      ? null
                      : () => post.status == 'ACTIVE' ? state._setStatus(post, 'PAUSED') : state._confirmResume(post),
                ),
              if (hasId)
                _ActionButton(
                  tooltip: 'Load stats',
                  color: c.gray400,
                  busy: refreshing,
                  icon: LucideIcons.refreshCw,
                  onTap: refreshing ? null : () => state._refreshStats(post),
                ),
              if (hasId)
                _ActionButton(
                  tooltip: 'Delete campaign',
                  color: AppColors.red500,
                  icon: LucideIcons.trash2,
                  onTap: () => state._confirmDelete(post),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final empty = value == '—';
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: c.gray400),
              const SizedBox(width: 3),
              Text(
                label.toUpperCase(),
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: c.gray400, letterSpacing: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: empty ? FontWeight.w400 : FontWeight.w600,
              color: empty ? c.gray300 : c.gray800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.tooltip,
    required this.color,
    required this.icon,
    required this.onTap,
    this.busy = false,
  });

  final String tooltip;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: busy
          ? SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 1.6, color: color))
          : Icon(icon, size: 16, color: color),
    );
  }
}
