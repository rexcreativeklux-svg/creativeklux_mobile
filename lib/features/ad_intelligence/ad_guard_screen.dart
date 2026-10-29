import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/auth_controller.dart';
import '../creatives/design.dart';
import 'ad_intel_kit.dart';
import 'ad_intelligence_api.dart';
import 'creative_source_card.dart';

/// Port of `ad-intelligence/ad-guard-ai/page.jsx` — checks an uploaded image
/// or a saved design against platform, brand and legal rules
/// (`POST /compliance-checker`).
///
/// The web's two columns (input | results) stack on a phone: input card, the
/// Run button, then the results.
class AdGuardScreen extends StatefulWidget {
  const AdGuardScreen({super.key});

  @override
  State<AdGuardScreen> createState() => _AdGuardScreenState();
}

const _platforms = ['Meta', 'Google', 'LinkedIn', 'TikTok', 'Twitter/X'];

const _gradeColors = {
  'A': Color(0xFF10B981),
  'B': Color(0xFF2563EB),
  'C': Color(0xFFF97316),
  'D': Color(0xFFEF4444),
  'F': Color(0xFF7F1D1D),
};

const _severityColors = {'Critical': AiHue.red, 'Major': AiHue.orange, 'Minor': AiHue.amber};

class _AdGuardScreenState extends State<AdGuardScreen> {
  late final _api = AdIntelligenceApi(context.read<AuthController>().api);

  PickedCreative? _file;
  Design? _design;
  final _selected = <String>['Meta', 'Google', 'LinkedIn'];
  bool _loading = false;
  Map<String, dynamic>? _data;
  String? _error;

  static const _accent = AiHue.emerald;
  static const _gradient = [AiHue.emerald, AiHue.teal];

  void _reset() {
    _data = null;
    _error = null;
  }

  Future<void> _analyze() async {
    if (_selected.isEmpty) {
      setState(() => _error = 'Please select at least one platform.');
      return;
    }
    if (_file == null && _design == null) {
      setState(() => _error = 'Please upload an image or select a design first.');
      return;
    }
    setState(() {
      _loading = true;
      _reset();
    });
    // Platforms go in the web's list order, not the order they were toggled.
    final platforms = [
      for (final p in _platforms)
        if (_selected.contains(p)) p,
    ];
    final res = _file != null
        ? await _api.checkCompliance(image: _file, platforms: platforms)
        : await _api.checkCompliance(canvas: canvasPayload(_design!.raw), platforms: platforms);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res.data;
      _error = res.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasInput = _file != null || _design != null;
    return AdIntelPage(
      children: [
        const ToolHeader(
          icon: LucideIcons.shieldCheck,
          colors: _gradient,
          title: 'Ad Guard AI',
          subtitle: 'Verify ad compliance for platform, brand, and legal standards.',
        ),
        CreativeSourceCard(
          accent: _accent,
          file: _file,
          design: _design,
          showFileMeta: true,
          header: _platformToggles(context),
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
        ),
        if (_error != null) ErrorBanner(_error!),
        if (hasInput)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: GradientButton(
              label: 'Run Compliance Check',
              icon: LucideIcons.shieldCheck,
              colors: _gradient,
              loading: _loading,
              loadingLabel: 'Checking compliance…',
              onPressed: _selected.isEmpty ? null : _analyze,
            ),
          ),
        if (_loading)
          const StatePanel(
            icon: Spinner(color: _accent),
            subtitle: 'AI is checking compliance…',
          )
        else if (_data != null)
          ..._results(context, _data!)
        else
          StatePanel(
            icon: Icon(LucideIcons.shieldCheck, size: 38, color: context.colors.gray200),
            subtitle: 'Upload an image or pick a saved design to check compliance',
          ),
      ],
    );
  }

  Widget _platformToggles(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Check Against Platforms',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray900),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _platforms)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _selected.contains(p) ? _selected.remove(p) : _selected.add(p)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: _selected.contains(p) ? _accent.withValues(alpha: 0.1) : c.surface,
                    border: Border.all(color: _selected.contains(p) ? _accent : c.gray200),
                  ),
                  child: Text(
                    p,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _selected.contains(p) ? AiHue.emeraldDeep : c.gray400,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _results(BuildContext context, Map<String, dynamic> d) {
    final c = context.colors;
    final platforms = listOf(d['platformCompliance']);
    final brand = mapOf(d['brandCompliance']);
    final legal = mapOf(d['legalCompliance']);
    final safety = d['contentSafety'] is Map ? mapOf(d['contentSafety']) : null;
    final access = d['accessibility'] is Map ? mapOf(d['accessibility']) : null;
    final plan = listOf(d['actionPlan']);
    final grade = str(d['complianceGrade']);

    return [
      // Overall
      AiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Overall Compliance', style: TextStyle(fontSize: 12, color: c.gray400)),
                ),
                StatusBadge(str(d['overallStatus'])),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              show(d['summary']),
              style: TextStyle(fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600, color: c.gray800),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Grade: ', style: TextStyle(fontSize: 12, color: c.gray400)),
                Text(
                  grade ?? '',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _gradeColors[grade] ?? const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(width: 12),
                Text('Risk: ', style: TextStyle(fontSize: 12, color: c.gray400)),
                Text(
                  '${show(d['overallRiskScore'])}/100',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.gray700),
                ),
              ],
            ),
          ],
        ),
      ),

      if (platforms.isNotEmpty)
        AiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardTitle('Platform Compliance'),
              for (final raw in platforms)
                Builder(
                  builder: (context) {
                    final p = mapOf(raw);
                    return InsetBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  show(p['platform']),
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray800),
                                ),
                              ),
                              StatusBadge(str(p['status'])),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(str(p['reason']) ?? '', style: TextStyle(fontSize: 12, height: 1.45, color: c.gray500)),
                          if (str(p['fix']) != null) _fix(p['fix']),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),

      _issueCard(
        'Brand Compliance',
        brand,
        titleKey: 'issue',
        titleColor: AiHue.orange,
        empty: 'No brand compliance issues detected.',
      ),
      _issueCard('Legal Compliance', legal, titleKey: 'check', empty: 'No legal compliance issues detected.'),

      if (safety != null || access != null)
        PairRow(
          children: [
            if (safety != null)
              AiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CardTitle('Content Safety', trailing: StatusBadge(str(safety['status']))),
                    if (listOf(safety['issues']).isNotEmpty)
                      for (final i in listOf(safety['issues']))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• ${show(mapOf(i)['detail'])}',
                            style: TextStyle(fontSize: 12, height: 1.4, color: c.gray500),
                          ),
                        )
                    else
                      Text('No content safety issues detected.', style: TextStyle(fontSize: 12, color: c.gray400)),
                  ],
                ),
              ),
            if (access != null)
              AiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CardTitle('Accessibility', trailing: StatusBadge(str(access['status']))),
                    Text(
                      'Contrast: ${str(access['contrastEstimate']) ?? ''}',
                      style: TextStyle(fontSize: 12, color: c.gray500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      str(access['readabilityNote']) ?? '',
                      style: TextStyle(fontSize: 12, height: 1.4, color: c.gray500),
                    ),
                  ],
                ),
              ),
          ],
        ),

      if (plan.isNotEmpty)
        AiCard(
          tint: _accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardTitle('Action Plan'),
              for (var i = 0; i < plan.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StepDot(i + 1, color: AiHue.emeraldDeep),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('${plan[i]}', style: TextStyle(fontSize: 12.5, height: 1.45, color: c.gray600)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  Widget _fix(dynamic fix) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      '↳ Fix: $fix',
      style: const TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w500, color: AiHue.teal),
    ),
  );

  /// Brand / Legal Compliance: a status badge and the issues (or "none").
  Widget _issueCard(
    String title,
    Map<String, dynamic> section, {
    required String titleKey,
    required String empty,
    Color? titleColor,
  }) {
    final c = context.colors;
    final issues = listOf(section['issues']);
    return AiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardTitle(title, trailing: section['status'] == null ? null : StatusBadge(str(section['status']))),
          if (issues.isEmpty)
            Text(empty, style: TextStyle(fontSize: 12, color: c.gray400))
          else
            for (final raw in issues)
              Builder(
                builder: (context) {
                  final i = mapOf(raw);
                  final severity = str(i['severity']);
                  return InsetBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              str(i[titleKey]) ?? '',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: titleColor ?? c.gray800,
                              ),
                            ),
                            if (severity != null)
                              Text(
                                severity.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: _severityColors[severity] ?? c.gray500,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(str(i['detail']) ?? '', style: TextStyle(fontSize: 12, height: 1.45, color: c.gray500)),
                        if (str(i['fix']) != null) _fix(i['fix']),
                      ],
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}
