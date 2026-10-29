import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'social_content_api.dart';
import 'social_widgets.dart';

/// Port of `(pages)/social-content/publishing/page.jsx` — "Social
/// Publishing": every post on each connected account, with its metrics.
///
/// Loads in three hops like the web: connected accounts, then each
/// platform's post list, then (after the list is up) per-post metrics that
/// fill in as they arrive. Nothing is kept on the device.
///
/// Phone layout: the web's 11-column table becomes one card per post (title,
/// pills, a 3×2 metric grid, actions).
class SocialPublishingScreen extends StatefulWidget {
  const SocialPublishingScreen({super.key, this.location = path});

  static const path = '/social-content/publishing';

  /// The current route, for the section tabs.
  final String location;

  @override
  State<SocialPublishingScreen> createState() => _SocialPublishingScreenState();
}

class _SocialPublishingScreenState extends State<SocialPublishingScreen> {
  static const _pageSize = 10;

  late final SocialContentApi _api;
  final _searchCtl = TextEditingController();

  int? _brandId;
  bool _brandSeen = false;

  /// Bumped on every brand switch, so an answer for the previous brand is
  /// dropped instead of landing on the new one's page.
  int _run = 0;

  List<Map<String, dynamic>> _integrations = [];
  List<SocialPost> _allPosts = [];

  /// First load only — held until the backend's first answer, so the "no
  /// posts yet" empty state never flashes at someone who does have posts.
  bool _loading = true;
  bool _fetchingLive = false;
  String? _refreshing;

  String _status = 'all';
  String _platform = 'all';
  String _search = '';
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _api = SocialContentApi(context.read<AuthController>().api);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A brand switch clears the previous brand's posts and holds the skeleton
    // until the backend answers for the new one. Integrations are scoped to
    // the active brand too, so they're refetched.
    final brandId = context.watch<AuthController>().activeBrand?.id;
    if (!_brandSeen || brandId != _brandId) {
      _brandSeen = true;
      _brandId = brandId;
      _start();
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> _start() async {
    final run = ++_run;
    setState(() {
      _allPosts = [];
      _loading = true;
    });
    // 1. Integrations. A failed lookup still has to unblock step 2 —
    //    otherwise the page would wait forever on the skeleton.
    try {
      final data = await _api.integrations();
      if (!mounted || run != _run) return;
      _integrations = data;
    } on SocialApiException catch (e) {
      if (!mounted || run != _run) return;
      Toast.error(e.message);
      _integrations = [];
    }
    // 2. The posts, exactly as the backend lists them.
    await _loadPosts(silent: true, run: run);
  }

  Future<void> _loadPosts({bool silent = false, int? run}) async {
    run ??= _run;
    setState(() => _fetchingLive = true);
    var rows = <SocialPost>[];
    try {
      final live = await _api.livePosts(_integrations, _brandId);
      if (!mounted || run != _run) return;
      rows = live.rows;
      setState(() => _allPosts = SocialContentApi.carryStats(_allPosts, rows));
      // A platform the backend couldn't read: show its own error, always.
      if (live.errors.isNotEmpty) Toast.error(live.errors.join(' · '));
      if (!silent) {
        final count = rows.where((p) => p.type == 'social').length;
        Toast.success('Loaded $count post${count == 1 ? '' : 's'}');
      }
    } catch (e) {
      if (!mounted || run != _run) return;
      Toast.error(e is SocialApiException ? e.message : "Couldn't load posts");
    } finally {
      if (mounted && run == _run) {
        setState(() {
          _fetchingLive = false;
          _loading = false;
        });
      }
    }
    // After the list is up — the numbers fill in as they arrive.
    if (rows.isNotEmpty) _loadAllStats(rows, run);
  }

  /// Every row's metrics, fetched after the list so the cards render first.
  /// Each platform's refusal is reported once, in the server's words.
  Future<void> _loadAllStats(List<SocialPost> rows, int run) async {
    final targets = rows
        .where((p) => p.type == 'social' && p.postId != null && SocialContentApi.statsPlatforms.contains(p.platform))
        .toList();
    if (targets.isEmpty) return;
    final result = await _api.statsForRows(targets, _brandId);
    if (!mounted || run != _run) return;
    setState(() {
      for (final p in _allPosts) {
        final s = result.stats[p.id];
        if (s != null) p.stats = s;
      }
    });
    result.errors.forEach((platform, message) => Toast.error('${platformMeta(platform).label} stats: $message'));
  }

  /// One post's metrics, held only for this page's lifetime.
  Future<void> _refreshStats(SocialPost post) async {
    setState(() => _refreshing = post.id);
    try {
      final stats = await _api.postStats(post, _brandId);
      if (!mounted) return;
      setState(() => post.stats = stats);
      Toast.success('Stats loaded');
    } on SocialApiException catch (e) {
      Toast.error("Couldn't load stats: ${e.message}");
    } finally {
      if (mounted) setState(() => _refreshing = null);
    }
  }

  /// Deleting is irreversible, so it waits on a confirm. The dialog stays
  /// busy while the backend works and closes either way, like the web's.
  Future<void> _confirmDelete(SocialPost post) async {
    await showConfirmDialog(
      context,
      title: 'Delete this post?',
      message: deleteMessage(post),
      confirmLabel: 'Delete',
      danger: true,
      onConfirm: () async {
        try {
          await _api.deletePost(post, _brandId);
          await _loadPosts(silent: true);
          Toast.success('Post deleted');
        } on SocialApiException catch (e) {
          Toast.error(e.message);
        }
      },
    );
  }

  void _clearFilters() {
    _searchCtl.clear();
    setState(() {
      _status = 'all';
      _platform = 'all';
      _search = '';
      _page = 1;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SocialSectionScaffold(
      location: widget.location,
      child: _loading ? const _PublishingSkeleton() : _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final c = context.colors;
    final posts = _allPosts.where((p) => p.type == 'social').toList();
    final counts = statusCounts(posts);

    // Newest → oldest by the relevant date (scheduled uses scheduled_at, else
    // published_at).
    final filtered = filterPosts(posts, status: _status, platform: _platform, search: _search)
      ..sort((a, b) {
        int t(SocialPost p) =>
            (p.status == 'scheduled' ? p.scheduledAt : p.publishedAt ?? p.scheduledAt)?.millisecondsSinceEpoch ?? 0;
        return t(b).compareTo(t(a));
      });
    final totalPages = max(1, (filtered.length / _pageSize).ceil());
    final page = _page.clamp(1, totalPages);
    final paged = filtered.skip((page - 1) * _pageSize).take(_pageSize).toList();
    final hasConnections = _integrations.isNotEmpty;

    // A dash until some row's stats are loaded — a 0 would claim no
    // impressions when they simply haven't been asked for.
    final anyImpressions = posts.any((p) => p.stats?.impressions != null);
    final impressions = posts.fold<num>(0, (s, p) => s + (p.stats?.impressions ?? 0));

    return RefreshIndicator(
      onRefresh: () => hasConnections ? _loadPosts() : _start(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          SocialPageHeader(
            title: 'Social Publishing',
            subtitle: 'Your posts on each connected account.',
            action: hasConnections
                ? SocialButton(
                    label: _fetchingLive ? 'Refreshing…' : 'Refresh',
                    icon: LucideIcons.refreshCw,
                    spinning: _fetchingLive,
                    onTap: _fetchingLive ? null : () => _loadPosts(),
                  )
                : SocialButton(label: 'Connect Platforms →', filled: true, onTap: () => context.push('/integrations')),
          ),
          const SizedBox(height: 20),

          if (posts.isNotEmpty) ...[
            _SummaryGrid(
              cards: [
                ('Total Posts', fmtNum(posts.length), LucideIcons.chartColumn),
                ('Published', fmtNum(counts['published']!), LucideIcons.circleCheck),
                ('Scheduled', fmtNum(counts['scheduled']!), LucideIcons.calendar),
                ('Impressions (loaded rows)', anyImpressions ? fmtNum(impressions) : '—', LucideIcons.eye),
              ],
            ),
            const SizedBox(height: 20),
            PostFilterCard(
              counts: counts,
              status: _status,
              onStatus: (s) => setState(() {
                _status = s;
                _page = 1;
              }),
              platformOptions: [for (final id in socialPlatformIds) (id, platformMeta(id).label)],
              platform: _platform,
              onPlatform: (p) => setState(() {
                _platform = p;
                _page = 1;
              }),
              searchController: _searchCtl,
              onSearch: (v) => setState(() {
                _search = v;
                _page = 1;
              }),
              resultCount: filtered.length,
            ),
            const SizedBox(height: 16),
          ],

          if (posts.isEmpty)
            SocialEmptyState(
              icon: LucideIcons.calendar,
              accentIcon: true,
              title: 'No published or scheduled social posts yet',
              body: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Go to your Creatives, open a card, and tap '),
                    TextSpan(
                      text: 'Publish',
                      style: TextStyle(fontWeight: FontWeight.w700, color: c.gray600),
                    ),
                    const TextSpan(text: ' to get started.'),
                  ],
                ),
              ),
              action: SocialButton(label: 'Go to Creatives', filled: true, onTap: () => context.go('/creatives')),
            )
          else if (filtered.isEmpty)
            SocialEmptyState(
              icon: LucideIcons.search,
              title: 'No posts match your filters',
              body: const Text('Try adjusting the platform, status, or search query.'),
              action: SocialButton(label: 'Clear Filters', onTap: _clearFilters),
            )
          else ...[
            for (final post in paged) ...[
              _PostCard(
                post: post,
                refreshing: _refreshing == post.id,
                onRefresh: post.postId != null && SocialContentApi.statsPlatforms.contains(post.platform)
                    ? () => _refreshStats(post)
                    : null,
                onDelete: canDelete(post) ? () => _confirmDelete(post) : null,
              ),
              const SizedBox(height: 10),
            ],
            _Pagination(
              page: page,
              totalPages: totalPages,
              total: filtered.length,
              pageSize: _pageSize,
              onPage: (n) => setState(() => _page = n),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.cards});

  final List<(String, String, IconData)> cards;

  @override
  Widget build(BuildContext context) {
    Widget card((String, String, IconData) d) => Expanded(
      child: _SummaryCard(label: d.$1, value: d.$2, icon: d.$3),
    );
    return Column(
      children: [
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [card(cards[i]), const SizedBox(width: 10), card(cards[i + 1])],
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray200),
      ),
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.gray900),
                ),
                Text(label, style: TextStyle(fontSize: 11, color: c.gray500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the web's table, as a card.
class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.refreshing, this.onRefresh, this.onDelete});

  final SocialPost post;
  final bool refreshing;
  final VoidCallback? onRefresh;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = post.stats;
    final date = post.status == 'scheduled' && post.scheduledAt != null ? post.scheduledAt : post.publishedAt;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PostThumb(url: post.imageUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.projectTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray800),
                    ),
                    if (post.caption.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        post.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: c.gray400),
                      ),
                    ],
                  ],
                ),
              ),
              if (onRefresh != null)
                IconButton(
                  tooltip: 'Load stats',
                  visualDensity: VisualDensity.compact,
                  onPressed: refreshing ? null : onRefresh,
                  icon: refreshing
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.6, color: c.gray400),
                        )
                      : Icon(LucideIcons.refreshCw, size: 15, color: c.gray400),
                ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(LucideIcons.trash2, size: 15, color: AppColors.red500),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PlatformPill(platform: post.platform),
                StatusBadge(status: post.status),
                Text(fmtShortDateTime(date), style: TextStyle(fontSize: 11.5, color: c.gray500)),
              ],
            ),
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
                      _Metric(icon: LucideIcons.eye, label: 'Impr.', value: s?.impressions),
                      _Metric(icon: LucideIcons.users, label: 'Reach', value: s?.reach),
                      _Metric(icon: LucideIcons.mousePointer, label: 'Clicks', value: s?.clicks),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Metric(icon: LucideIcons.heart, label: 'Likes', value: s?.likes),
                      _Metric(icon: LucideIcons.share2, label: 'Shares', value: s?.shares),
                      _Metric(
                        icon: LucideIcons.trendingUp,
                        label: 'CTR',
                        text: s?.ctr != null && s!.ctr != 0 ? '${s.ctr!.toStringAsFixed(2)}%' : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, this.value, this.text});

  final IconData icon;
  final String label;
  final num? value;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = text ?? (value == null ? null : fmtNum(value!));
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 11, color: c.gray400),
              const SizedBox(width: 3),
              Text(
                label.toUpperCase(),
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: c.gray400, letterSpacing: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            shown ?? '—',
            style: shown == null
                ? TextStyle(fontSize: 12, color: c.gray300)
                : TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.gray800),
          ),
        ],
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.totalPages,
    required this.total,
    required this.pageSize,
    required this.onPage,
  });

  final int page;
  final int totalPages;
  final int total;
  final int pageSize;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final from = total == 0 ? 0 : (page - 1) * pageSize + 1;
    final to = min(page * pageSize, total);

    Widget square({required Widget child, VoidCallback? onTap, bool active = false}) => Material(
      color: active ? AppColors.blue600 : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(width: 32, height: 32, child: Center(child: child)),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          Text('Showing $from–$to of $total posts', style: TextStyle(fontSize: 12, color: c.gray400)),
          if (totalPages > 1) ...[
            const SizedBox(height: 8),
            // Every page gets its own number, so a long list wraps onto a
            // second line rather than running off the screen.
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 2,
              runSpacing: 2,
              children: [
                square(
                  onTap: page == 1 ? null : () => onPage(page - 1),
                  child: Icon(LucideIcons.chevronLeft, size: 16, color: page == 1 ? c.gray300 : c.gray500),
                ),
                for (var n = 1; n <= totalPages; n++)
                  square(
                    active: n == page,
                    onTap: () => onPage(n),
                    child: Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: n == page ? Colors.white : c.gray500,
                      ),
                    ),
                  ),
                square(
                  onTap: page == totalPages ? null : () => onPage(page + 1),
                  child: Icon(LucideIcons.chevronRight, size: 16, color: page == totalPages ? c.gray300 : c.gray500),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The web's `PublishingSkeleton`, laid out like the phone page.
class _PublishingSkeleton extends StatelessWidget {
  const _PublishingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const SkeletonBox(width: 180, height: 20),
        const SizedBox(height: 8),
        const SkeletonBox(width: 240, height: 12),
        const SizedBox(height: 20),
        for (var r = 0; r < 2; r++) ...[
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: 60, radius: 12)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 60, radius: 12)),
            ],
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        const SkeletonBox(height: 128, radius: 12),
        const SizedBox(height: 16),
        for (var i = 0; i < 3; i++) ...[const SkeletonBox(height: 150, radius: 12), const SizedBox(height: 10)],
      ],
    );
  }
}
