import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'social_content_api.dart';
import 'social_widgets.dart';

/// Port of `(pages)/social-content/analytics/page.jsx` — "Social Analytics":
/// totals, a 14-day timeline, impressions by platform, the engagement split
/// and per-post performance, all from the backend's per-post metrics.
///
/// The Recharts charts are fl_chart here, sized to the phone's width; the
/// pie's hover tooltip becomes a legend with the values in it. The Post
/// Performance table is the stacked label:value card the web's
/// ResponsiveTable already shows below `md`.
class SocialAnalyticsScreen extends StatefulWidget {
  const SocialAnalyticsScreen({super.key, this.location = path});

  static const path = '/social-content/analytics';

  /// The current route, for the section tabs.
  final String location;

  @override
  State<SocialAnalyticsScreen> createState() => _SocialAnalyticsScreenState();
}

/// Per-post metrics the analytics page asks for (the web's STATS_FETCHERS:
/// Facebook and Instagram — the amber notice below says so).
const _statsPlatforms = ['facebook', 'instagram'];

const _clicksColor = Color(0xFF22C55E);
const _likesColor = Color(0xFFEC4899);
const _sharesColor = Color(0xFF8B5CF6);
const _commentsColor = Color(0xFFF59E0B);

class _SocialAnalyticsScreenState extends State<SocialAnalyticsScreen> {
  late final SocialContentApi _api;

  int? _brandId;
  bool _brandSeen = false;
  int _run = 0;

  List<SocialPost> _allPosts = [];
  bool _fetchingLive = false;
  List<Map<String, dynamic>> _integrations = [];

  // This page loads in two hops — integrations, then live posts and per-post
  // stats — and only the second one produces numbers. Both are tracked so the
  // KPI tiles never render a page of zeroes on the way there.
  bool _integrationsReady = false;
  bool _statsLoaded = false;

  @override
  void initState() {
    super.initState();
    _api = SocialContentApi(context.read<AuthController>().api);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A brand switch means a different set of posts: clear them and put the
    // KPI tiles back into their loading state until the backend answers.
    final brandId = context.watch<AuthController>().activeBrand?.id;
    if (!_brandSeen || brandId != _brandId) {
      _brandSeen = true;
      _brandId = brandId;
      _start();
    }
  }

  Future<void> _start() async {
    final run = ++_run;
    setState(() {
      _allPosts = [];
      _statsLoaded = false;
      _integrationsReady = false;
    });
    try {
      final data = await _api.integrations();
      if (!mounted || run != _run) return;
      _integrations = data;
    } on SocialApiException catch (e) {
      if (!mounted || run != _run) return;
      Toast.error(e.message);
      _integrations = [];
    }
    setState(() => _integrationsReady = true);
    if (_integrations.isNotEmpty) await _loadPosts(silent: true);
  }

  /// Every post the backend lists, and — for the platforms the backend serves
  /// per-post metrics for — those metrics. Nothing kept beyond this screen.
  Future<void> _loadPosts({bool silent = false}) async {
    final run = _run;
    setState(() => _fetchingLive = true);
    try {
      final live = await _api.livePosts(_integrations, _brandId);
      if (!mounted || run != _run) return;
      if (live.errors.isNotEmpty) Toast.error(live.errors.join(' · '));

      final failed = <String>[];
      final social = await Future.wait(
        live.rows.where((p) => p.type == 'social').map((p) async {
          if (p.status != 'published' || p.postId == null || !_statsPlatforms.contains(p.platform)) return p;
          try {
            p.stats = await _api.postStats(p, _brandId);
          } on SocialApiException catch (e) {
            failed.add('${p.platform}: ${e.message}');
          }
          return p;
        }),
      );
      if (!mounted || run != _run) return;
      setState(() => _allPosts = social);

      // A post whose metrics the backend refused: say so, with its words.
      if (failed.isNotEmpty) {
        Toast.error("Couldn't load stats for ${failed.length} post${failed.length == 1 ? '' : 's'} — ${failed.first}");
      }
      if (!silent) Toast.success('Loaded ${social.length} post${social.length == 1 ? '' : 's'}');
    } catch (e) {
      if (!mounted || run != _run) return;
      Toast.error(e is SocialApiException ? e.message : "Couldn't load posts");
    } finally {
      if (mounted && run == _run) {
        setState(() {
          _fetchingLive = false;
          _statsLoaded = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Held until the stats pass finishes, not just the post sync: with posts
    // but no stats yet the page is real charts full of zeroes, which is a
    // worse lie than a placeholder.
    final initializing = !_integrationsReady || (_integrations.isNotEmpty && !_statsLoaded);
    return SocialSectionScaffold(
      location: widget.location,
      child: initializing ? const _AnalyticsSkeleton() : _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final posts = _allPosts.where((p) => p.type == 'social').toList();
    final published = posts.where((p) => p.status == 'published').toList();

    num sum(num? Function(PostStats s) f) =>
        published.fold<num>(0, (a, p) => a + (p.stats == null ? 0 : f(p.stats!) ?? 0));
    final impressions = sum((s) => s.impressions);
    final reach = sum((s) => s.reach);
    final clicks = sum((s) => s.clicks);
    final likes = sum((s) => s.likes);
    final shares = sum((s) => s.shares);
    final comments = sum((s) => s.comments);

    // Clicks over impressions across every post, not an average of averages.
    final ctr = impressions > 0 ? (clicks / impressions * 100).toStringAsFixed(2) : '0.00';

    final hasAnyStats = published.any((p) => p.stats != null);

    return RefreshIndicator(
      onRefresh: () => _loadPosts(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          SocialPageHeader(
            title: 'Social Analytics',
            subtitle: 'Aggregated social performance across platforms',
            action: SocialButton(
              label: _fetchingLive ? 'Refreshing...' : 'Refresh',
              icon: LucideIcons.refreshCw,
              filled: true,
              spinning: _fetchingLive,
              onTap: _fetchingLive ? null : () => _loadPosts(),
            ),
          ),
          const SizedBox(height: 20),
          if (published.isEmpty)
            const SocialEmptyState(
              icon: LucideIcons.chartColumn,
              title: 'No published posts yet',
              body: Text('Publish content from Creatives to start seeing analytics.'),
            )
          else ...[
            _KpiGrid(
              cards: [
                _Kpi(LucideIcons.eye, 'Total Impressions', fmtNum(impressions), accent: true),
                _Kpi(LucideIcons.users, 'Total Reach', fmtNum(reach)),
                _Kpi(LucideIcons.mousePointer, 'Total Clicks', fmtNum(clicks)),
                _Kpi(LucideIcons.trendingUp, 'CTR', '$ctr%', accent: true),
                _Kpi(LucideIcons.heart, 'Total Likes', fmtNum(likes)),
                _Kpi(LucideIcons.share2, 'Total Shares', fmtNum(shares)),
                _Kpi(LucideIcons.circleCheck, 'Published Posts', fmtNum(published.length), accent: true),
                _Kpi(LucideIcons.clock, 'Scheduled', fmtNum(posts.where((p) => p.status == 'scheduled').length)),
              ],
            ),
            if (!hasAnyStats) ...[const SizedBox(height: 16), const _NoMetricsNotice()],
            const SizedBox(height: 16),
            _ChartCard(
              title: 'Posts published in the last 14 days — their totals, by publish day',
              child: _TimelineChart(published: published),
            ),
            const SizedBox(height: 16),
            _ChartCard(
              title: 'Impressions by Platform',
              child: _PlatformChart(published: published),
            ),
            const SizedBox(height: 16),
            _ChartCard(
              title: 'Engagement Breakdown',
              child: _EngagementChart(
                slices: [
                  ('Likes', likes, _likesColor),
                  ('Shares', shares, _sharesColor),
                  ('Comments', comments, _commentsColor),
                  ('Clicks', clicks, _clicksColor),
                ].where((e) => e.$2 > 0).toList(),
              ),
            ),
            const SizedBox(height: 16),
            _PerformanceList(posts: published),
          ],
        ],
      ),
    );
  }
}

// ── KPI tiles ───────────────────────────────────────────────────────────────

class _Kpi {
  const _Kpi(this.icon, this.label, this.value, {this.accent = false});
  final IconData icon;
  final String label;
  final String value;
  final bool accent;
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.cards});

  final List<_Kpi> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _StatCard(kpi: cards[i])),
              const SizedBox(width: 10),
              Expanded(child: _StatCard(kpi: cards[i + 1])),
            ],
          ),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.kpi});

  final _Kpi kpi;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  kpi.label.toUpperCase(),
                  maxLines: 2,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.gray500, letterSpacing: 0.3),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: kpi.accent ? AppColors.blue600.withValues(alpha: 0.1) : c.gray100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(kpi.icon, size: 14, color: kpi.accent ? AppColors.blue600 : c.gray500),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              kpi.value,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.gray900),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoMetricsNotice extends StatelessWidget {
  const _NoMetricsNotice();

  @override
  Widget build(BuildContext context) {
    const amber = AppColors.amber500;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.circleAlert, size: 16, color: amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'The backend returned no metrics for these posts. Per-post metrics are served for Facebook and '
              'Instagram only.',
              style: TextStyle(fontSize: 12, color: Color.lerp(amber, context.colors.gray900, 0.35)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Charts ──────────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray800),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// A round axis maximum + tick step for [value] (≈4 gridlines).
(double max, double step) _niceScale(num value) {
  if (value <= 0) return (4, 1);
  final raw = value / 4;
  final exp = pow(10, (log(raw) / ln10).floor()).toDouble();
  final f = raw / exp;
  final nice = f <= 1
      ? 1
      : f <= 2
      ? 2
      : f <= 2.5
      ? 2.5
      : f <= 5
      ? 5
      : 10;
  final step = nice * exp;
  return (step * (value / step).ceil(), step);
}

/// Axis numbers kept short enough for a narrow Y axis: 950, 1.2k, 3.4M.
String _compact(double v) {
  if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(v % 1e6 == 0 ? 0 : 1)}M';
  if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(v % 1e3 == 0 ? 0 : 1)}k';
  return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

FlGridData _grid(BuildContext context, double step) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: step,
  getDrawingHorizontalLine: (_) => FlLine(color: context.colors.gray100, strokeWidth: 1, dashArray: const [3, 3]),
);

TextStyle _tick(BuildContext context) => TextStyle(fontSize: 10, color: context.colors.gray400);

AxisTitles _leftAxis(BuildContext context, double step) => AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    reservedSize: 34,
    interval: step,
    getTitlesWidget: (v, meta) => Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(_compact(v), textAlign: TextAlign.right, style: _tick(context)),
    ),
  ),
);

const _noTitles = AxisTitles();

class _TimelineChart extends StatelessWidget {
  const _TimelineChart({required this.published});

  final List<SocialPost> published;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    // Each post's totals on the day it was published, for the last 14 days.
    final days = [for (var i = 13; i >= 0; i--) DateTime(now.year, now.month, now.day - i)];
    final series = [
      for (final d in days)
        () {
          final dayPosts = published.where((p) => p.publishedAt != null && sameDay(p.publishedAt!, d));
          num total(num? Function(PostStats) f) =>
              dayPosts.fold<num>(0, (a, p) => a + (p.stats == null ? 0 : f(p.stats!) ?? 0));
          return (total((s) => s.impressions), total((s) => s.clicks), total((s) => s.likes));
        }(),
    ];
    final peak = series.fold<num>(0, (m, s) => max(m, max(s.$1, max(s.$2, s.$3))));
    final (maxY, step) = _niceScale(peak);

    final lines = [
      ('impressions', AppColors.blue600, [for (var i = 0; i < 14; i++) FlSpot(i.toDouble(), series[i].$1.toDouble())]),
      ('clicks', _clicksColor, [for (var i = 0; i < 14; i++) FlSpot(i.toDouble(), series[i].$2.toDouble())]),
      ('likes', _likesColor, [for (var i = 0; i < 14; i++) FlSpot(i.toDouble(), series[i].$3.toDouble())]),
    ];

    // Fourteen date labels overlap on a phone, so only some are drawn — but
    // always the first and last, which are what make the range readable
    // (the web's `interval: "preserveStartEnd"`).
    const shown = {0, 4, 8, 13};

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: 13,
              minY: 0,
              maxY: maxY,
              gridData: _grid(context, step),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: _noTitles,
                rightTitles: _noTitles,
                leftTitles: _leftAxis(context, step),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 1,
                    getTitlesWidget: (v, meta) {
                      final i = v.round();
                      if (v != i || !shown.contains(i)) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(fmtMonthDay(days[i]), style: _tick(context)),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => c.surface,
                  tooltipBorder: BorderSide(color: c.gray200),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${s.barIndex == 0 ? '${fmtMonthDay(days[s.x.round()])}\n' : ''}'
                        '${lines[s.barIndex].$1} : ${fmtNum(s.y)}',
                        TextStyle(fontSize: 11.5, color: lines[s.barIndex].$2, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                for (final (_, color, spots) in lines)
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: color,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _Legend(items: [for (final (name, color, _) in lines) (name, color)]),
      ],
    );
  }
}

class _PlatformChart extends StatelessWidget {
  const _PlatformChart({required this.published});

  final List<SocialPost> published;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // platform → impressions, in first-seen order like the web's object keys.
    final totals = <String, num>{};
    for (final p in published) {
      totals[p.platform] = (totals[p.platform] ?? 0) + (p.stats?.impressions ?? 0);
    }
    if (totals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Text(
          'No data',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: c.gray400),
        ),
      );
    }
    final entries = totals.entries.toList();
    final (maxY, step) = _niceScale(totals.values.fold<num>(0, max));

    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: _grid(context, step),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: _noTitles,
            rightTitles: _noTitles,
            leftTitles: _leftAxis(context, step),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (i < 0 || i >= entries.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(platformMeta(entries[i].key).short, style: _tick(context)),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => c.surface,
              tooltipBorder: BorderSide(color: c.gray200),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${platformMeta(entries[group.x].key).label}\n',
                TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.gray900),
                children: [
                  TextSpan(
                    text: 'impressions : ${fmtNum(rod.toY)}',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400, color: c.gray700),
                  ),
                ],
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < entries.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: entries[i].value.toDouble(),
                    width: entries.length > 4 ? 18 : 28,
                    color: platformMeta(entries[i].key).color,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EngagementChart extends StatelessWidget {
  const _EngagementChart({required this.slices});

  final List<(String, num, Color)> slices;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (slices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Text(
          'No engagement data yet',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: c.gray400),
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 170,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 46,
              sectionsSpace: 3,
              startDegreeOffset: -90,
              sections: [
                for (final (_, value, color) in slices)
                  PieChartSectionData(value: value.toDouble(), color: color, radius: 32, showTitle: false),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // The values ride in the legend — a phone has no hover for the web's
        // tooltip.
        _Legend(items: [for (final (name, value, color) in slices) ('$name · ${fmtNum(value)}', color)]),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});

  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final (label, color) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 11, color: c.gray500)),
            ],
          ),
      ],
    );
  }
}

// ── Post performance ────────────────────────────────────────────────────────

/// The Post Performance table as the web's ResponsiveTable shows it below
/// `md`: one card per post, the post as its title and every other column a
/// labelled row.
class _PerformanceList extends StatelessWidget {
  const _PerformanceList({required this.posts});

  final List<SocialPost> posts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Text(
              'Post Performance',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray800),
            ),
          ),
          for (final p in posts) ...[Divider(height: 1, color: c.gray100), _PerformanceCard(post: p)],
        ],
      ),
    );
  }
}

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({required this.post});

  final SocialPost post;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = post.stats;
    final m = platformMeta(post.platform);
    final rows = [
      ('Platform', '${m.emoji} ${m.label}'),
      ('Impressions', fmtStat(s?.impressions)),
      ('Reach', fmtStat(s?.reach)),
      ('Clicks', fmtStat(s?.clicks)),
      ('Likes', fmtStat(s?.likes)),
      ('CTR', s?.ctr != null && s!.ctr != 0 ? '${s.ctr!.toStringAsFixed(2)}%' : '—'),
      ('Updated', s?.lastUpdated != null ? fmtMonthDayTime(s!.lastUpdated!) : '—'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (post.imageUrl != null) ...[
                PostThumb(url: post.imageUrl, size: 32, radius: 4),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  post.projectTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: c.gray500)),
                  const Spacer(),
                  Text(value, style: TextStyle(fontSize: 12, color: c.gray800)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The web's `AnalyticsSkeleton`, laid out like the phone page.
class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const SkeletonBox(width: 170, height: 20),
        const SizedBox(height: 8),
        const SkeletonBox(width: 250, height: 12),
        const SizedBox(height: 20),
        for (var r = 0; r < 4; r++) ...[
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: 78, radius: 12)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 78, radius: 12)),
            ],
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        const SkeletonBox(height: 260, radius: 12),
      ],
    );
  }
}
