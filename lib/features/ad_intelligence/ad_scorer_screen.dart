import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/auth_controller.dart';
import '../creatives/design.dart';
import 'ad_intel_kit.dart';
import 'ad_intelligence_api.dart';
import 'creative_source_card.dart';

/// Port of `ad-intelligence/ad-scorer-ai/page.jsx` — scores an uploaded image
/// or a saved design for conversion, brand, engagement, clarity and targeting
/// (`POST /creative-scoring`).
///
/// Phone order: input card (with its Score button inside, like the web),
/// Detected Elements, then the results that sit in the web's right column.
class AdScorerScreen extends StatefulWidget {
  const AdScorerScreen({super.key});

  @override
  State<AdScorerScreen> createState() => _AdScorerScreenState();
}

class _AdScorerScreenState extends State<AdScorerScreen> {
  late final _api = AdIntelligenceApi(context.read<AuthController>().api);

  PickedCreative? _file;
  Design? _design;
  bool _loading = false;
  Map<String, dynamic>? _data;
  String? _error;

  static const _accent = AiHue.amber;
  static const _gradient = [AiHue.amber, AiHue.orangeDeep];

  // Ad Scorer's ramp tops out in green-500, not emerald.
  static Color _score(num v) => scoreColor(v, top: AiHue.green);

  void _reset() {
    _data = null;
    _error = null;
  }

  Future<void> _runScore() async {
    if (_file == null && _design == null) {
      setState(() => _error = 'Please upload an image or select a design first.');
      return;
    }
    setState(() {
      _loading = true;
      _reset();
    });
    final res = _file != null
        ? await _api.creativeScoring(image: _file)
        : await _api.creativeScoring(canvas: canvasPayload(_design!.raw));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res.data;
      _error = res.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasInput = _file != null || _design != null;
    final data = _data;
    final elements = listOf(data?['elements']);

    return AdIntelPage(
      children: [
        const ToolHeader(
          icon: LucideIcons.star,
          colors: _gradient,
          title: 'Ad Scorer AI',
          subtitle: 'Score your creatives for performance, brand awareness, or engagement.',
        ),
        CreativeSourceCard(
          accent: _accent,
          badgeTop: AiHue.green,
          file: _file,
          design: _design,
          onFile: (f) => setState(() {
            _file = f;
            _design = null;
            _reset();
          }),
          onDesign: (d) => setState(() {
            _design = d;
            _file = null;
            _reset();
          }),
          onClear: () => setState(() {
            _file = null;
            _design = null;
            _reset();
          }),
          footer: hasInput
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: GradientButton(
                    label: '✦ Score This Creative',
                    colors: _gradient,
                    loading: _loading,
                    loadingLabel: 'Scoring…',
                    onPressed: _runScore,
                  ),
                )
              : null,
        ),

        if (elements.isNotEmpty)
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardTitle('Detected Elements'),
                FlowGrid(
                  gap: 6,
                  children: [
                    for (final raw in elements)
                      Builder(
                        builder: (context) {
                          final el = mapOf(raw);
                          final detected = el['detected'] == true || '${el['detected']}' == '1';
                          return InsetBox(
                            margin: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Row(
                              children: [
                                Icon(
                                  detected ? LucideIcons.circleCheck : LucideIcons.circleAlert,
                                  size: 14,
                                  color: detected ? AiHue.green : AiHue.orange,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    show(el['name']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray700),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),

        if (_error != null) ErrorBanner(_error!),

        if (_loading)
          const StatePanel(
            icon: Spinner(color: _accent),
            subtitle: 'AI is scoring your creative…',
          )
        else if (data != null)
          ..._results(context, data)
        else
          const StatePanel(
            minHeight: 220,
            icon: IconTile(icon: LucideIcons.star, color: _accent),
            subtitle: 'Score results will appear here',
          ),
      ],
    );
  }

  List<Widget> _results(BuildContext context, Map<String, dynamic> d) {
    final c = context.colors;
    final best = listOf(d['bestPlatforms']);
    final worst = listOf(d['worstPlatforms']);
    final recs = listOf(d['recommendations']);
    final notes = [
      ('Strength', d['creativeStrength'], AiHue.greenDeep),
      ('Key Weakness', d['creativeWeakness'], AiHue.red),
      ('Audience Signal', d['audienceSignal'], AiHue.blue),
    ].where((n) => str(n.$2) != null).toList();

    return [
      if (str(d['headline']) != null)
        AiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                str(d['headline'])!,
                style: TextStyle(fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w700, color: c.gray900),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  if (str(d['estimatedCTR']) != null)
                    Text.rich(
                      TextSpan(
                        text: 'Est. CTR: ',
                        children: [
                          TextSpan(
                            text: str(d['estimatedCTR']),
                            style: TextStyle(fontWeight: FontWeight.w700, color: c.gray800),
                          ),
                        ],
                      ),
                      style: TextStyle(fontSize: 12, color: c.gray400),
                    ),
                  if (str(d['estimatedConversionLift']) != null)
                    Text(
                      str(d['estimatedConversionLift'])!,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AiHue.greenDeep),
                    ),
                ],
              ),
              if (best.isNotEmpty || worst.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in best) TintPill('$p', color: AiHue.greenDeep),
                    for (final p in worst) TintPill('✗ $p', color: AiHue.redDeep),
                  ],
                ),
              ],
              if (notes.isNotEmpty) ...[
                Divider(height: 24, color: c.gray100),
                for (final (label, text, color) in notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TinyLabel(label, color: color),
                        Text('$text', style: TextStyle(fontSize: 12, height: 1.45, color: c.gray500)),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),

      AiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CardTitle('Scores'),
            // Two gauges a row on a phone, three from 600px — as the web
            // does at its sm breakpoint.
            FlowGrid(
              wideColumns: 3,
              children: [
                for (final (label, key) in const [
                  ('Conversion', 'conversionScore'),
                  ('Brand', 'brandScore'),
                  ('Engagement', 'engagementScore'),
                  ('Clarity', 'clarityScore'),
                  ('Targeting', 'targetingScore'),
                  ('Overall', 'overallScore'),
                ])
                  _gauge(context, label, d[key]),
              ],
            ),
          ],
        ),
      ),

      if (recs.isNotEmpty)
        AiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardTitle('AI Recommendations'),
              for (final raw in recs)
                Builder(
                  builder: (context) {
                    final r = mapOf(raw);
                    final priority = str(r['priority']);
                    final pColor = priorityColor(priority);
                    return InsetBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      str(r['title']) ?? '',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray800),
                                    ),
                                    if (str(r['category']) != null)
                                      Text(
                                        str(r['category'])!,
                                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: c.gray400),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (priority != null) TintPill(priority, color: pColor ?? c.gray500),
                              if (str(r['scoreImpact']) != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  str(r['scoreImpact'])!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AiHue.greenDeep,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(str(r['detail']) ?? '', style: TextStyle(fontSize: 12, height: 1.45, color: c.gray500)),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
    ];
  }

  Widget _gauge(BuildContext context, String label, dynamic raw) {
    final c = context.colors;
    final v = numOf(raw) ?? 0;
    final color = _score(v);
    return InsetBox(
      margin: 0,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          RingGauge(
            value: v,
            color: color,
            size: 84,
            stroke: 10,
            child: Text(
              '${raw ?? 0}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: c.gray400),
          ),
        ],
      ),
    );
  }
}
