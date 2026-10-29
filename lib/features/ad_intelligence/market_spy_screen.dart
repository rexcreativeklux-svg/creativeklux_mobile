import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/auth_controller.dart';
import 'ad_intel_kit.dart';
import 'ad_intelligence_api.dart';

/// Port of `ad-intelligence/market-spy/page.jsx` (CompetitorInsights) — a
/// competitor's site in, traffic / audience / ad-spend estimates out
/// (`POST /competitor-insights`).
class MarketSpyScreen extends StatefulWidget {
  const MarketSpyScreen({super.key});

  @override
  State<MarketSpyScreen> createState() => _MarketSpyScreenState();
}

// The page's COLORS.
const _primary = AiHue.navy;
const _accent = AiHue.blue;
const _green = AiHue.greenDeep;

class _MarketSpyScreenState extends State<MarketSpyScreen> {
  late final _api = AdIntelligenceApi(context.read<AuthController>().api);
  final _url = TextEditingController();

  bool _loading = false;
  Map<String, dynamic>? _data;
  String? _error;

  static const _gradient = [AiHue.pink, AiHue.rose];

  @override
  void initState() {
    super.initState();
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    if (_url.text.trim().isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });
    final res = await _api.competitorInsights(_url.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res.data;
      _error = res.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdIntelPage(
      children: [
        const ToolHeader(
          icon: LucideIcons.search,
          colors: _gradient,
          title: 'Market Spy',
          subtitle: "See insights from your competitors' websites.",
        ),
        InputRow(
          controller: _url,
          icon: LucideIcons.globe,
          keyboardType: TextInputType.url,
          // The web's "Enter competitor website URL, e.g. https://competitor.com"
          // doesn't fit a phone field; the example alone says what to type.
          hint: 'https://competitor.com',
          focusColor: _accent,
          onSubmit: _analyze,
          button: GradientButton(
            label: 'Analyze',
            icon: LucideIcons.search,
            colors: _gradient,
            expand: false,
            loading: _loading,
            onPressed: _url.text.trim().isEmpty ? null : _analyze,
          ),
        ),
        if (_error != null) ErrorBanner(_error!),
        if (_data == null && !_loading && _error == null)
          const StatePanel(
            minHeight: 300,
            icon: IconTile(icon: LucideIcons.users, color: AiHue.pink),
            title: 'Enter a competitor URL to get started',
            subtitle: "We'll analyze traffic, audience, ad spend, and more.",
          ),
        if (_loading)
          const StatePanel(
            minHeight: 300,
            icon: Spinner(color: AiHue.pink),
            subtitle: 'Analyzing competitor data…',
          ),
        if (_data != null && !_loading) ..._results(context, _data!),
      ],
    );
  }

  List<Widget> _results(BuildContext context, Map<String, dynamic> d) {
    final c = context.colors;

    final devices = [
      ('Desktop', numOf(d['desktopShare']) ?? 0, _primary),
      ('Mobile', numOf(d['mobileShare']) ?? 0, _accent),
      ('Tablet', numOf(d['tabletShare']) ?? 0, _green),
    ].where((e) => e.$2 > 0).toList();

    final sources = mapOf(d['trafficSources']);
    final sourceRows = d['trafficSources'] is Map
        ? [
            for (final (name, key) in const [
              ('Direct', 'direct'),
              ('Organic', 'organic'),
              ('Paid', 'paid'),
              ('Social', 'social'),
              ('Referral', 'referral'),
              ('Email', 'email'),
            ])
              (name, numOf(sources[key]) ?? 0),
          ]
        : const <(String, num)>[];

    final male = numOf(d['malePercent']) ?? 0;
    final female = numOf(d['femalePercent']) ?? 0;
    final strengths = listOf(d['strengths']);
    final weaknesses = listOf(d['weaknesses']);
    final gaps = listOf(d['opportunityGaps']);
    final interests = listOf(d['interests']);
    final affinities = listOf(d['contentAffinities']);
    final purchase = str(d['purchaseBehavior']);
    final threat = str(d['threatLevel']);

    return [
      // Domain + summary
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                text: 'Insights for: ',
                children: [
                  TextSpan(
                    text: str(d['domain']) ?? _url.text,
                    style: TextStyle(fontWeight: FontWeight.w700, color: c.gray800),
                  ),
                ],
              ),
              style: TextStyle(fontSize: 13, color: c.gray400),
            ),
            if (str(d['marketPositionSummary']) != null) ...[
              const SizedBox(height: 6),
              Text(
                str(d['marketPositionSummary'])!,
                style: TextStyle(fontSize: 12, height: 1.45, fontStyle: FontStyle.italic, color: c.gray400),
              ),
            ],
          ],
        ),
      ),

      // Core metrics
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FlowGrid(
          wideColumns: 3,
          children: [
            _stat(context, 'Visit Count', d['visitCount'], d['visitCountChange'], LucideIcons.trendingUp),
            _stat(context, 'Unique Visitors', d['uniqueVisitors'], d['uniqueVisitorsChange'], LucideIcons.users),
            _stat(context, 'Pages / Visit', d['pagesPerVisit'], d['pagesPerVisitChange'], LucideIcons.globe),
            _stat(context, 'Avg. Duration', d['avgVisitDuration'], d['avgVisitDurationChange'], LucideIcons.clock),
            _stat(context, 'Bounce Rate', d['bounceRate'], d['bounceRateChange'], LucideIcons.arrowUpRight),
          ],
        ),
      ),

      // Ad spend / SEO
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FlowGrid(
          wideColumns: 4,
          children: [
            for (final (label, value) in [
              ('Est. Monthly Ad Spend', d['estimatedAdSpend']),
              ('Est. Revenue Range', d['estimatedRevenue']),
              ('SEO Score', d['seoScore'] != null ? '${d['seoScore']}/100' : null),
              ('Domain Authority', d['domainAuthority'] != null ? '${d['domainAuthority']}/100' : null),
            ])
              AiCard(
                margin: 0,
                padding: 12,
                child: Column(
                  children: [
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: c.gray400),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      show(value),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.gray900),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),

      PairRow(
        children: [
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardTitle('Device Traffic Share'),
                Row(
                  children: [
                    SizedBox(
                      width: 124,
                      height: 124,
                      child: devices.isEmpty
                          ? null
                          : PieChart(
                              PieChartData(
                                centerSpaceRadius: 40,
                                sectionsSpace: 0,
                                startDegreeOffset: -90,
                                sections: [
                                  for (final (_, v, color) in devices)
                                    PieChartSectionData(
                                      value: v.toDouble(),
                                      color: color,
                                      radius: 20,
                                      showTitle: false,
                                    ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: [
                          for (final (name, v, color) in devices)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(name, style: TextStyle(fontSize: 13, color: c.gray500)),
                                  ),
                                  Text(
                                    '$v%',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.gray800),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardTitle('Traffic Sources'),
                // The web's horizontal Recharts bars, drawn as rows so the
                // labels and values stay legible at phone width (the web
                // shows the value in a tooltip; here it sits at the bar's end).
                ..._hBars(context, sourceRows),
              ],
            ),
          ),
        ],
      ),

      PairRow(
        children: [
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardTitle('Gender', bottom: 2),
                Text('Gender distribution of their audience.', style: TextStyle(fontSize: 12, color: c.gray400)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${d['malePercent'] ?? ''}% Male',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.gray700),
                      ),
                    ),
                    Text(
                      '${d['femalePercent'] ?? ''}% Female',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.gray700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    height: 34,
                    child: Row(
                      children: [
                        if (male > 0) _genderSeg('♂ MALE', male, _primary),
                        if (female > 0) _genderSeg('FEMALE ♀', female, _accent),
                        // A split that doesn't add up to 100 leaves the rest empty, as on the web.
                        if (male + female < 100) Spacer(flex: ((100 - male - female) * 10).round()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _dot(context, 'Male', _primary),
                    const SizedBox(width: 16),
                    _dot(context, 'Female', _accent),
                  ],
                ),
              ],
            ),
          ),
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardTitle('Age Distribution'),
                SizedBox(height: 170, child: _AgeChart(groups: listOf(d['ageGroups']))),
              ],
            ),
          ),
        ],
      ),

      PairRow(
        children: [
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardTitle('Top Countries'),
                for (final raw in listOf(d['topCountries']))
                  Builder(
                    builder: (context) {
                      final m = mapOf(raw);
                      final share = numOf(m['share']) ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: Text(
                                show(m['country']),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: c.gray700),
                              ),
                            ),
                            Expanded(child: _bar(context, share / 100, _accent, 6)),
                            SizedBox(
                              width: 42,
                              child: Text(
                                '${m['share'] ?? ''}%',
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.gray700),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardTitle('Social Following'),
                for (final e in mapOf(d['socialFollowing']).entries) _kvRow(context, _capitalize(e.key), show(e.value)),
              ],
            ),
          ),
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardTitle('Top Keywords'),
                for (final (i, kw) in listOf(d['topKeywords']).indexed)
                  InsetBox(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          '#${i + 1}',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: AiHue.blue),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('$kw', style: TextStyle(fontSize: 12, color: c.gray700)),
                        ),
                      ],
                    ),
                  ),
                Divider(height: 20, color: c.gray200),
                for (final (k, v) in [
                  ('Backlinks', d['backlinksCount']),
                  ('Household', d['householdSize']),
                  ('Income', d['incomeLevel']),
                  ('Education', d['educationLevel']),
                ])
                  if (str(v) != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(k, style: TextStyle(fontSize: 12, color: c.gray400)),
                          ),
                          Flexible(
                            child: Text(
                              '$v',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.gray700),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),

      if (strengths.isNotEmpty || weaknesses.isNotEmpty)
        PairRow(
          children: [
            AiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CardTitle('✦ Strengths', color: AiHue.greenDeep),
                  for (final s in strengths) BulletLine('$s', bullet: '•', color: AiHue.green),
                ],
              ),
            ),
            AiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CardTitle('✦ Weaknesses', color: AiHue.red),
                  for (final w in weaknesses) BulletLine('$w', bullet: '•', color: AiHue.red),
                ],
              ),
            ),
          ],
        ),

      if (gaps.isNotEmpty || purchase != null || affinities.isNotEmpty)
        PairRow(
          children: [
            if (gaps.isNotEmpty)
              AiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CardTitle(
                      '✦ Opportunity Gaps',
                      color: const Color(0xFF1D4ED8),
                      trailing: threat == null ? null : _threatBadge(threat.split(' ').first),
                    ),
                    for (final g in gaps) BulletLine('$g', bullet: '→', color: AiHue.blue),
                  ],
                ),
              ),
            if (purchase != null || affinities.isNotEmpty || interests.isNotEmpty)
              AiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CardTitle('✦ Audience Psychographics'),
                    if (purchase != null) ...[
                      const TinyLabel('Purchase Behavior'),
                      Text(purchase, style: TextStyle(fontSize: 12, height: 1.45, color: c.gray500)),
                      const SizedBox(height: 14),
                    ],
                    if (interests.isNotEmpty) ...[
                      const TinyLabel('Interests', bottom: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final i in interests) TintPill('$i', color: AiHue.blue)],
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (affinities.isNotEmpty) ...[
                      const TinyLabel('Content Affinities', bottom: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final a in affinities) TintPill('$a', color: AiHue.pink)],
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
    ];
  }

  Widget _stat(BuildContext context, String label, dynamic value, dynamic change, IconData icon) {
    final c = context.colors;
    final ch = str(change);
    final up = ch == null ? null : !ch.startsWith('-');
    return AiCard(
      margin: 0,
      padding: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: c.gray400),
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AiHue.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 13, color: AiHue.blue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // The AI often answers in words ("approximately 500 million"), which
          // cut to one line hid the number itself. Short values stay big;
          // long ones drop a size and wrap to three lines.
          Builder(
            builder: (context) {
              final text = show(value);
              final long = text.length > 12;
              return Text(
                text,
                maxLines: long ? 3 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: long ? 14 : 18, height: 1.25, fontWeight: FontWeight.w700, color: c.gray900),
              );
            },
          ),
          if (ch != null) ...[
            const SizedBox(height: 4),
            Text(
              '${up! ? '▲' : '▼'} $ch',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: up ? AiHue.green : AiHue.red),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _hBars(BuildContext context, List<(String, num)> rows) {
    final c = context.colors;
    final max = rows.fold<num>(0, (m, r) => math.max(m, r.$2));
    return [
      for (final (name, v) in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(name, style: TextStyle(fontSize: 11.5, color: c.gray400)),
              ),
              Expanded(child: _bar(context, max == 0 ? 0 : v / max, _accent, 14, square: true)),
              SizedBox(
                width: 40,
                child: Text(
                  '$v',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.gray700),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  /// A fill bar over a grey track. [square] keeps the left end flat, as the
  /// web's horizontal bars (`radius={[0, 4, 4, 0]}`) do.
  Widget _bar(BuildContext context, num fraction, Color color, double height, {bool square = false}) {
    final radius = square
        ? BorderRadius.horizontal(right: Radius.circular(height / 3.5))
        : BorderRadius.circular(height / 2);
    return LayoutBuilder(
      builder: (context, box) => Container(
        height: height,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: square ? null : context.colors.gray200,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Container(
          width: box.maxWidth * fraction.clamp(0, 1).toDouble(),
          decoration: BoxDecoration(color: color, borderRadius: radius),
        ),
      ),
    );
  }

  Widget _genderSeg(String label, num pct, Color color) => Expanded(
    flex: math.max(1, (pct * 10).round()),
    child: Container(
      color: color,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
    ),
  );

  Widget _dot(BuildContext context, String label, Color color) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 12, color: context.colors.gray400)),
    ],
  );

  Widget _kvRow(BuildContext context, String k, String v) {
    final c = context.colors;
    return InsetBox(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: TextStyle(fontSize: 12, color: c.gray500)),
          ),
          Text(
            v,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.gray800),
          ),
        ],
      ),
    );
  }

  Widget _threatBadge(String level) {
    final color = switch (level) {
      'Critical' => AiHue.redDeep,
      'High' => AiHue.orangeDeep,
      'Medium' => AiHue.yellow,
      _ => AiHue.greenDeep,
    };
    return TintPill('Threat: $level', color: color);
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Age Distribution — vertical bars of `ageGroups[].percent` by `age`.
class _AgeChart extends StatelessWidget {
  const _AgeChart({required this.groups});

  final List<dynamic> groups;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = groups.map(mapOf).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final width = math.min(28.0, box.maxWidth / rows.length * 0.6);
        return BarChart(
          BarChartData(
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            alignment: BarChartAlignment.spaceAround,
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) {
                    final i = value.round();
                    if (i < 0 || i >= rows.length) return const SizedBox.shrink();
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(show(rows[i]['age']), style: TextStyle(fontSize: 10, color: c.gray400)),
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
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                  '${show(rows[group.x]['age'])}\npercent: ${show(rows[group.x]['percent'])}',
                  TextStyle(fontSize: 12, color: c.gray700),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < rows.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: (numOf(rows[i]['percent']) ?? 0).toDouble(),
                      color: _accent,
                      width: width,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
