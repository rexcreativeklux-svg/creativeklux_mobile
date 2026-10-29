import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/auth_controller.dart';
import 'ad_intel_kit.dart';
import 'ad_intelligence_api.dart';

/// Port of `ad-intelligence/ad-performance/page.jsx` (the web component is
/// still called CreativeInsights) — a brand/account name in, an AI
/// performance report out (`POST /creative-insights`).
class AdPerformanceScreen extends StatefulWidget {
  const AdPerformanceScreen({super.key});

  @override
  State<AdPerformanceScreen> createState() => _AdPerformanceScreenState();
}

const _levels = ['VERY POOR', 'POOR', 'NORMAL', 'GOOD', 'EXCELLENT'];
const _levelColors = [Color(0xFFEF4444), Color(0xFFF97316), Color(0xFF2563EB), Color(0xFF22C55E), Color(0xFF10B981)];

Color _levelColor(String? level) {
  final i = _levels.indexOf(level ?? '');
  return i >= 0 ? _levelColors[i] : AiHue.blue;
}

class _AdPerformanceScreenState extends State<AdPerformanceScreen> {
  late final _api = AdIntelligenceApi(context.read<AuthController>().api);
  final _brand = TextEditingController();

  bool _loading = false;
  Map<String, dynamic>? _data;
  String? _error;

  static const _gradient = [AiHue.violet, AiHue.purple];

  @override
  void initState() {
    super.initState();
    // The buttons enable as soon as there's a name, like the web's `disabled`.
    _brand.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _brand.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final brand = _brand.text.trim();
    if (brand.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });
    final res = await _api.creativeInsights(_brand.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res.data;
      _error = res.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final has = _brand.text.trim().isNotEmpty;
    return AdIntelPage(
      children: [
        const ToolHeader(
          icon: LucideIcons.lightbulb,
          colors: _gradient,
          title: 'Ad Performance',
          subtitle: 'The ultimate ad performance dashboard, built for performance-driven brands.',
        ),
        InputRow(
          controller: _brand,
          // The web's placeholder adds "(e.g. Nike, Shopify)", which a 360dp
          // field cuts off mid-word — the examples are dropped on the phone.
          hint: 'Enter your brand or account name',
          focusColor: AiHue.violet,
          onSubmit: _analyze,
          button: GradientButton(
            label: 'Generate',
            icon: LucideIcons.refreshCw,
            colors: _gradient,
            expand: false,
            loading: _loading,
            onPressed: has ? _analyze : null,
          ),
        ),
        if (_error != null) ErrorBanner(_error!),
        if (_data == null && !_loading && _error == null)
          StatePanel(
            minHeight: 300,
            icon: const IconTile(icon: LucideIcons.trendingUp, color: AiHue.violet),
            title: 'No insight data yet',
            subtitle: 'Click Generate Insights to create your Ad Performance report.',
            action: GradientButton(
              label: 'Generate Insights',
              icon: LucideIcons.refreshCw,
              colors: _gradient,
              expand: false,
              height: 40,
              onPressed: has ? _analyze : null,
            ),
          ),
        if (_loading)
          const StatePanel(
            minHeight: 300,
            icon: Spinner(color: AiHue.violet),
            subtitle: 'Generating ad performance insights…',
          ),
        if (_data != null && !_loading) ..._results(context, _data!),
      ],
    );
  }

  List<Widget> _results(BuildContext context, Map<String, dynamic> d) {
    final c = context.colors;
    final level = str(d['ciLevel']);
    final color = _levelColor(level);
    final ci = numOf(d['ciScore']);
    final trend = listOf(d['trendData']);
    final types = listOf(d['topCreativeTypes']);
    final channels = listOf(d['channelBreakdown']);
    final recs = listOf(d['recommendations']);
    final audience = [
      ('Top Age Group', d['topAgeGroup']),
      ('Top Gender', d['topGender']),
      ('Top Device', d['topDevice']),
      ('Top Country', d['topCountry']),
    ];
    final fatigue = str(d['fatigueLevel']);

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text.rich(
          TextSpan(
            text: '${show(d['brand'])} — ',
            children: [
              TextSpan(
                text: 'Account Performance Report',
                style: TextStyle(fontWeight: FontWeight.w600, color: c.gray700),
              ),
            ],
          ),
          style: TextStyle(fontSize: 13, color: c.gray400),
        ),
      ),

      // Top KPIs — 2 across on a phone, 4 from 600px.
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FlowGrid(
          wideColumns: 4,
          children: [
            for (final (label, value) in [
              ('CI Score', d['ciScore'] != null ? '${d['ciScore']}%' : null),
              ('Avg CTR', d['avgCTR']),
              ('Avg CPC', d['avgCPC']),
              ('Avg ROAS', d['avgROAS']),
              ('Impressions', d['impressions']),
              ('Conversions', d['conversions']),
              ('Active Creatives', d['activeCreatives']),
              ('Fatigued', d['fatiguedCreatives']),
            ])
              _kpi(context, label, value),
          ],
        ),
      ),

      PairRow(
        children: [
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardTitle('CI Score', bottom: 2),
                Text('Compared to others in your market.', style: TextStyle(fontSize: 12, color: c.gray400)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    RingGauge(
                      value: ci ?? 0,
                      color: color,
                      size: 116,
                      stroke: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${d['ciScore'] ?? ''}%',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color),
                          ),
                          Text(level ?? '', style: TextStyle(fontSize: 9.5, color: c.gray400)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (level != null) TintPill(level, color: color, border: false, fontSize: 11),
                          const SizedBox(height: 6),
                          Text(
                            str(d['ciSummary']) ?? '',
                            style: TextStyle(fontSize: 12, height: 1.45, color: c.gray500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Scale bar — the level reached is lit, the rest faded.
                Row(
                  children: [
                    for (var i = 0; i < _levels.length; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: _levelColors[i].withValues(alpha: level == _levels[i] ? 1 : 0.2),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    for (final l in _levels)
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            l,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: level == l ? FontWeight.w700 : FontWeight.w400,
                              color: level == l ? c.gray900 : c.gray400,
                            ),
                          ),
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
                const CardTitle('Creative Fatigue Analysis'),
                _metric(
                  context,
                  'Fatigue Level',
                  d['fatigueLevel'],
                  fatigue == 'High'
                      ? AiHue.red
                      : fatigue == 'Medium'
                      ? AiHue.orange
                      : AiHue.green,
                ),
                _metric(context, 'Avg Frequency', d['avgFrequency']),
                _metric(context, 'Suggested Refresh', d['suggestedRefreshIn']),
                _metric(context, 'Active Creatives', d['activeCreatives'], AiHue.green),
                _metric(context, 'Fatigued Creatives', d['fatiguedCreatives'], AiHue.orange),
              ],
            ),
          ),
        ],
      ),

      if (trend.isNotEmpty)
        AiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardTitle('Performance Trend (8 Weeks)'),
              SizedBox(height: 200, child: _TrendChart(trend: trend)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _legend(context, 'CI Score', AiHue.violet),
                  const SizedBox(width: 18),
                  _legend(context, 'ROAS', AiHue.blue, dashed: true),
                ],
              ),
            ],
          ),
        ),

      if (types.isNotEmpty || channels.isNotEmpty)
        PairRow(
          children: [
            if (types.isNotEmpty)
              AiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CardTitle('Top Creative Types'),
                    for (final raw in types)
                      Builder(
                        builder: (context) {
                          final t = mapOf(raw);
                          return _breakdownRow(
                            context,
                            title: show(t['type']),
                            parts: [
                              _labelled(context, 'CTR: ', t['ctr']),
                              _labelled(context, 'Spend: ', t['spend']),
                              Text(
                                '${show(t['score'])}%',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AiHue.violetDeep,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            if (channels.isNotEmpty)
              AiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CardTitle('Channel Breakdown'),
                    for (final raw in channels)
                      Builder(
                        builder: (context) {
                          final ch = mapOf(raw);
                          return _breakdownRow(
                            context,
                            title: show(ch['channel']),
                            parts: [
                              Text(show(ch['impressions']), style: TextStyle(fontSize: 12, color: c.gray400)),
                              _labelled(context, 'CTR: ', ch['ctr']),
                              _labelled(context, 'ROAS: ', ch['roas'], valueColor: AiHue.greenDeep),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),

      if (audience.any((a) => a.$2 != null))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FlowGrid(
            wideColumns: 4,
            children: [
              for (final (label, value) in audience)
                AiCard(
                  margin: 0,
                  padding: 14,
                  child: Column(
                    children: [
                      Text(label, style: TextStyle(fontSize: 11.5, color: c.gray400)),
                      const SizedBox(height: 4),
                      Text(
                        show(value),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.gray900),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

      if (recs.isNotEmpty)
        AiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardTitle('AI Recommendations', trailing: null),
              for (var i = 0; i < recs.length; i++) _recommendation(context, i, recs[i]),
            ],
          ),
        ),
    ];
  }

  Widget _kpi(BuildContext context, String label, dynamic value) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray100),
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: c.gray400),
          ),
          const SizedBox(height: 4),
          Text(
            show(value),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.gray900),
          ),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String label, dynamic value, [Color? color]) {
    final c = context.colors;
    return InsetBox(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: c.gray500)),
          ),
          Flexible(
            child: Text(
              show(value),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color ?? c.gray900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, String label, Color color, {bool dashed = false}) => Row(
    children: [
      SizedBox(
        width: 20,
        height: 2,
        child: dashed
            ? Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    Container(width: 4, height: 2, color: color),
                    const SizedBox(width: 2),
                  ],
                ],
              )
            : ColoredBox(color: color),
      ),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 11, color: context.colors.gray400)),
    ],
  );

  /// The web's one-line rows (`type ··· CTR · Spend · score`) — the stats drop
  /// under the title on a phone so neither gets squeezed.
  Widget _breakdownRow(BuildContext context, {required String title, required List<Widget> parts}) {
    final c = context.colors;
    return InsetBox(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.gray700),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 12, runSpacing: 2, children: parts),
        ],
      ),
    );
  }

  Widget _labelled(BuildContext context, String label, dynamic value, {Color? valueColor}) {
    final c = context.colors;
    return Text.rich(
      TextSpan(
        text: label,
        children: [
          TextSpan(
            text: show(value),
            style: TextStyle(fontWeight: FontWeight.w700, color: valueColor ?? c.gray700),
          ),
        ],
      ),
      style: TextStyle(fontSize: 12, color: c.gray400),
    );
  }

  /// A recommendation is either a string (the old page) or
  /// `{title, detail, priority, scoreImpact}` — both are shown.
  Widget _recommendation(BuildContext context, int i, dynamic r) {
    final c = context.colors;
    final isMap = r is Map;
    final m = mapOf(r);
    final title = isMap ? (str(m['title']) ?? '') : 'Recommendation ${i + 1}';
    final detail = isMap ? (str(m['detail']) ?? '') : '$r';
    final priority = isMap ? str(m['priority']) : null;
    final impact = isMap ? str(m['scoreImpact']) : null;
    return InsetBox(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StepDot(i + 1, color: AiHue.violet, filled: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray800),
                ),
              ),
              if (priority != null) ...[
                const SizedBox(width: 6),
                TintPill(priority, color: priorityColor(priority) ?? c.gray500),
              ],
              if (impact != null) ...[
                const SizedBox(width: 6),
                Text(
                  impact,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AiHue.greenDeep),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(detail, style: TextStyle(fontSize: 12, height: 1.45, color: c.gray500)),
          ),
        ],
      ),
    );
  }
}

/// The 8-week line chart: CI Score (solid violet) and ROAS (dashed blue) on
/// one hidden Y axis, week labels underneath — the web's Recharts LineChart.
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.trend});

  final List<dynamic> trend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = trend.map(mapOf).toList();
    List<FlSpot> spots(String key) => [
      for (var i = 0; i < rows.length; i++)
        if (numOf(rows[i][key]) case final v?) FlSpot(i.toDouble(), v.toDouble()),
    ];
    LineChartBarData line(String key, Color color, {List<int>? dash}) => LineChartBarData(
      spots: spots(key),
      isCurved: true,
      preventCurveOverShooting: true,
      color: color,
      barWidth: 2,
      dashArray: dash,
      dotData: const FlDotData(show: false),
    );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (rows.length - 1).clamp(1, 1 << 20).toDouble(),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          line('score', AiHue.violet),
          line('roas', AiHue.blue, dash: const [4, 2]),
        ],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i != value || i < 0 || i >= rows.length) return const SizedBox.shrink();
                // Every label fits from 6 weeks down; at 8 on a phone, every other.
                if (rows.length > 6 && meta.parentAxisSize < 360 && i.isOdd) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(show(rows[i]['week']), style: TextStyle(fontSize: 10.5, color: c.gray400)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => c.surface,
            tooltipBorder: BorderSide(color: c.gray200),
            tooltipBorderRadius: BorderRadius.circular(8),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${s.barIndex == 0 ? 'CI Score' : 'ROAS'}: ${show(rows[s.x.round()][s.barIndex == 0 ? 'score' : 'roas'])}',
                  TextStyle(fontSize: 12, color: s.barIndex == 0 ? AiHue.violet : AiHue.blue),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
