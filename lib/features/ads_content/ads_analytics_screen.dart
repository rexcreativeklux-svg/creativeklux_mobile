import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'ads_api.dart';
import 'ads_widgets.dart';

/// Port of `ads-content/analytics/page.jsx` — last 30 days, per campaign, as
/// each ad network reports it: eight KPI tiles, impressions / clicks by
/// platform (Recharts bars → fl_chart), and the Ad Performance table, which
/// on a phone is the stacked label:value card the web's `ResponsiveTable`
/// draws below `md`.
class AdsAnalyticsScreen extends StatefulWidget {
  const AdsAnalyticsScreen({super.key});

  static const path = '/ads-content/analytics';

  @override
  State<AdsAnalyticsScreen> createState() => _AdsAnalyticsScreenState();
}

/// analytics/page.jsx's own `PLATFORM_META` (bar colours + its short labels).
const _chartMeta = {
  'facebook': ('Facebook', Color(0xFF3B82F6)),
  'instagram': ('Instagram', Color(0xFFEC4899)),
  'meta_ads': ('Meta Ads', Color(0xFF6366F1)),
  'google_ads': ('Google Ads', Color(0xFF22C55E)),
  'tiktok': ('TikTok', Color(0xFF94A3B8)),
  'tiktok_ads': ('TT Ads', Color(0xFF0891B2)),
  'linkedin': ('LinkedIn', Color(0xFF2563EB)),
  'twitter': ('X/Twitter', Color(0xFF475569)),
};

class _PlatformTotals {
  _PlatformTotals(this.label, this.color);

  final String label;
  final Color color;
  num impressions = 0;
  num clicks = 0;
  int posts = 0;
}

class _AdsAnalyticsScreenState extends State<AdsAnalyticsScreen> {
  late final AdsApi _api;

  List<AdCampaign> _rows = [];
  bool _fetchingLive = false;
  List<Map<String, dynamic>> _integrations = const [];

  // This page loads in two hops — integrations, then campaigns and their
  // metrics — and only the second one produces numbers. Both are tracked so
  // the KPI tiles never render a page of zeroes on the way there.
  bool _integrationsReady = false;
  bool _statsLoaded = false;

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
    // A brand switch means a different set of campaigns. Clear them and put
    // the KPI tiles back into their loading state until the backend answers.
    final brandId = context.watch<AuthController>().activeBrand?.id;
    if (brandId != _brandId) {
      _brandId = brandId;
      _init();
    }
  }

  Future<void> _init() async {
    final run = ++_run;
    setState(() {
      _rows = [];
      _statsLoaded = false;
      _integrationsReady = false;
    });
    try {
      final list = await _api.integrations();
      if (!mounted || run != _run) return;
      _integrations = list;
    } on AdsException catch (e) {
      if (!mounted || run != _run) return;
      Toast.error(e.message);
      _integrations = const [];
    }
    setState(() => _integrationsReady = true);
    // With nothing connected the page is already in its final state.
    if (_integrations.isNotEmpty) await _loadCampaigns(silent: true);
  }

  /// Every campaign the backend lists, each with its last-30-days metrics.
  /// Paused campaigns are included — they may well have run this month.
  Future<void> _loadCampaigns({bool silent = false}) async {
    final run = _run;
    setState(() => _fetchingLive = true);
    try {
      final res = await _api.liveCampaigns(_integrations);
      if (res.errors.isNotEmpty) Toast.error(res.errors.join(' · '));

      final failed = <String>[];
      final campaigns = res.rows;
      await Future.wait(
        campaigns.map((p) async {
          try {
            p.stats = await _api.campaignStats(p.platform, p.postId);
          } catch (e) {
            failed.add('${p.title}: ${e is AdsException ? e.message : e}');
          }
        }),
      );
      if (!mounted || run != _run) return;
      setState(() => _rows = campaigns);

      // A campaign whose metrics the backend refused: say so, with its words.
      if (failed.isNotEmpty) {
        debugPrint('Campaign metrics failed: $failed');
        Toast.error(
          "Couldn't load stats for ${failed.length} campaign${failed.length == 1 ? '' : 's'} — ${failed.first}",
        );
      }
      if (!silent) Toast.success('Loaded ${campaigns.length} campaign${campaigns.length == 1 ? '' : 's'}');
    } catch (e) {
      Toast.error(e is AdsException ? e.message : "Couldn't load campaigns");
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
    // Held until the stats pass finishes, not just the list: with ads but no
    // stats yet the page is charts full of zeroes, a worse lie than a placeholder.
    final initializing = !_integrationsReady || (_integrations.isNotEmpty && !_statsLoaded);
    return AdsSectionScaffold(location: AdsAnalyticsScreen.path, child: initializing ? _skeleton() : _body(context));
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    final campaigns = _rows;

    // Only the numbers campaign metrics actually carry. Spend isn't totalled —
    // each ad account reports it in its own currency.
    num impressions = 0, reach = 0, clicks = 0, conversions = 0;
    for (final p in campaigns) {
      impressions += p.stats?.impressions ?? 0;
      reach += p.stats?.reach ?? 0;
      clicks += p.stats?.clicks ?? 0;
      conversions += p.stats?.conversions ?? 0;
    }
    // Clicks over impressions across every campaign, not an average of averages.
    final overallCtr = impressions != 0 ? (clicks / impressions * 100).toStringAsFixed(2) : '0.00';

    final byPlatform = <String, _PlatformTotals>{};
    for (final p in campaigns) {
      final meta = _chartMeta[p.platform];
      final t = byPlatform.putIfAbsent(
        p.platform,
        () => _PlatformTotals(meta?.$1 ?? p.platform, meta?.$2 ?? const Color(0xFF888888)),
      );
      t.impressions += p.stats?.impressions ?? 0;
      t.clicks += p.stats?.clicks ?? 0;
      t.posts += 1;
    }
    final platformData = byPlatform.values.toList();

    final tiles = [
      _StatCard(icon: LucideIcons.eye, label: 'Total Impressions', value: groupDigits(impressions), accent: true),
      _StatCard(icon: LucideIcons.users, label: 'Total Reach', value: groupDigits(reach)),
      _StatCard(icon: LucideIcons.mousePointer, label: 'Total Clicks', value: groupDigits(clicks)),
      _StatCard(icon: LucideIcons.trendingUp, label: 'CTR', value: '$overallCtr%', accent: true),
      _StatCard(icon: LucideIcons.target, label: 'Conversions', value: groupDigits(conversions)),
      _StatCard(icon: LucideIcons.chartColumn, label: 'Campaigns', value: '${campaigns.length}'),
      _StatCard(
        icon: LucideIcons.circleCheck,
        label: 'Active',
        value: '${campaigns.where((p) => p.status == 'ACTIVE').length}',
        accent: true,
      ),
      _StatCard(
        icon: LucideIcons.circlePause,
        label: 'Paused',
        value: '${campaigns.where((p) => p.status == 'PAUSED').length}',
      ),
    ];

    return RefreshIndicator(
      onRefresh: () => _loadCampaigns(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          AdsPageHeader(
            title: 'Ads Analytics',
            subtitle: 'Last 30 days, per campaign, as each ad network reports it',
            action: AdsButton(
              label: _fetchingLive ? 'Refreshing...' : 'Refresh',
              icon: LucideIcons.refreshCw,
              filled: true,
              spinning: _fetchingLive,
              onTap: _fetchingLive ? null : () => _loadCampaigns(),
            ),
          ),
          const SizedBox(height: 20),
          if (campaigns.isEmpty)
            const AdsEmptyState(
              icon: LucideIcons.chartColumn,
              title: 'No campaigns yet',
              message: Text('Create an ad from Creatives to start seeing analytics.'),
            )
          else ...[
            for (var i = 0; i < tiles.length; i += 2) ...[
              if (i > 0) const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: tiles[i]),
                  const SizedBox(width: 10),
                  Expanded(child: tiles[i + 1]),
                ],
              ),
            ],
            const SizedBox(height: 20),
            _chartCard(context, 'Impressions by Platform', platformData, (t) => t.impressions),
            const SizedBox(height: 12),
            _chartCard(context, 'Clicks by Platform', platformData, (t) => t.clicks),
            const SizedBox(height: 20),
            AdsCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: c.gray100)),
                    ),
                    child: Text(
                      'Ad Performance',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray800),
                    ),
                  ),
                  for (var i = 0; i < campaigns.length; i++)
                    _PerformanceRow(post: campaigns[i], last: i == campaigns.length - 1),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chartCard(
    BuildContext context,
    String title,
    List<_PlatformTotals> data,
    num Function(_PlatformTotals) pick,
  ) {
    final c = context.colors;
    return AdsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray800),
          ),
          const SizedBox(height: 14),
          if (data.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                'No data',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.gray400),
              ),
            )
          else
            SizedBox(
              height: 190,
              child: _PlatformBarChart(data: data, pick: pick),
            ),
        ],
      ),
    );
  }

  /// `AnalyticsSkeleton`: header, the eight tiles, two charts, the table.
  Widget _skeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const SkeletonBox(width: 150, height: 20),
        const SizedBox(height: 8),
        const SkeletonBox(width: 250, height: 12),
        const SizedBox(height: 22),
        for (var i = 0; i < 4; i++) ...[
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: 84, radius: 12)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 84, radius: 12)),
            ],
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        const SkeletonBox(height: 240, radius: 12),
        const SizedBox(height: 12),
        const SkeletonBox(height: 240, radius: 12),
      ],
    );
  }
}

/// Port of `StatCard`.
class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value, this.accent = false});

  final IconData icon;
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AdsCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: c.gray500,
                    letterSpacing: 0.3,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent ? AppColors.blue600.withValues(alpha: 0.1) : c.gray100,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 14, color: accent ? AppColors.blue600 : c.gray500),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: c.gray900),
          ),
        ],
      ),
    );
  }
}

/// The Recharts `BarChart`: one bar per platform in its own colour, a dashed
/// horizontal grid, muted axis ticks and a themed tooltip.
class _PlatformBarChart extends StatelessWidget {
  const _PlatformBarChart({required this.data, required this.pick});

  final List<_PlatformTotals> data;
  final num Function(_PlatformTotals) pick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxY = data.map(pick).fold<num>(0, (a, b) => b > a ? b : a).toDouble();
    final tick = TextStyle(fontSize: 10, color: c.gray400);
    // Narrow bars when many platforms share the width; Recharts sizes them
    // from the band the same way.
    final barWidth = (220 / data.length).clamp(10, 36).toDouble();
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY * 1.1,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: c.gray100, strokeWidth: 1, dashArray: const [3, 3]),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, meta) => v == meta.max && maxY != 0
                  ? const SizedBox.shrink()
                  : SideTitleWidget(
                      meta: meta,
                      space: 4,
                      child: Text(_compact(v), style: tick),
                    ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: Text(data[i].label, style: tick, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => c.surface,
            tooltipBorder: BorderSide(color: c.gray200),
            tooltipBorderRadius: BorderRadius.circular(8),
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${data[group.x].label}\n',
              TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.gray900),
              children: [
                TextSpan(
                  text: groupDigits(rod.toY),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: c.gray700),
                ),
              ],
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: pick(data[i]).toDouble(),
                  color: data[i].color,
                  width: barWidth,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Axis ticks: 1.2k / 3.4M so they fit the narrow left gutter.
  static String _compact(double v) {
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(v % 1e6 == 0 ? 0 : 1)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(v % 1e3 == 0 ? 0 : 1)}k';
    return v.toStringAsFixed(v % 1 == 0 ? 0 : 1);
  }
}

/// One `AD_COLUMNS` row as the stacked card: the ad as the title, the other
/// seven columns as label:value pairs.
class _PerformanceRow extends StatelessWidget {
  const _PerformanceRow({required this.post, required this.last});

  final AdCampaign post;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = post.stats;
    final m = platformMetaOf(post.platform);
    final cells = [
      ('Platform', '${m.emoji} ${_chartMeta[post.platform]?.$1 ?? post.platform}'),
      ('Impressions', metric(s?.impressions)),
      ('Reach', metric(s?.reach)),
      ('Clicks', metric(s?.clicks)),
      ('Conversions', metric(s?.conversions)),
      ('CTR', ctrText(s?.ctr)),
      ('Updated', formatUpdated(s?.lastUpdated)),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.gray100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (post.imageUrl != null) ...[AdThumb(url: post.imageUrl, size: 32), const SizedBox(width: 10)],
              Expanded(
                child: Text(
                  post.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final (label, value) in cells)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: c.gray500)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray800),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
