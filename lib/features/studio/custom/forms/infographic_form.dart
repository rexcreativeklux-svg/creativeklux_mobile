import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/ui/toast.dart';
import '../studio_form_kit.dart';

/// Port of `studio/forms/InfographicForm.jsx`: Brand Details → Goals & Style.
class InfographicForm extends StatefulWidget {
  const InfographicForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  State<InfographicForm> createState() => _InfographicFormState();
}

const _goals = [
  ('Brand Awareness', '📣'),
  ('Engagement', '💬'),
  ('Sales', '🛒'),
  ('Lead Generation', '🎯'),
  ('Website Traffic', '🌐'),
];

const _audiences = [
  ('B2B', 'Business owners, startups, agencies'),
  ('B2C', 'End consumers, everyday users'),
  ('Casual', 'Broad social media audience'),
  ('Educational', 'Students, researchers, learners'),
  ('Professional', 'Industry experts, professionals'),
];

const _formats = [('PNG', 'Transparent BG'), ('PDF', 'Print-ready'), ('JPEG', 'Compressed')];

const _orientations = [('Portrait', LucideIcons.rectangleVertical), ('Landscape', LucideIcons.rectangleHorizontal)];

const _chartStyles = [
  ('bar', 'Bar Chart', 'Comparisons & rankings'),
  ('pie', 'Pie / Donut', 'Part-to-whole ratios'),
  ('timeline', 'Timeline', 'Sequential events'),
  ('flowchart', 'Flowchart', 'Processes & decisions'),
  ('stats', 'Stat Callouts', 'Key numbers & facts'),
  ('mixed', 'Mixed', 'Combination layout'),
];

const _inspire = [
  'An engaging infographic on global climate change statistics and their impact',
  'A professional business growth metrics infographic for Q4 performance',
  'A colorful health and wellness tips infographic with actionable data',
  'An educational historical timeline infographic of the space race',
  'A tech-focused infographic on AI adoption trends across industries',
  'A step-by-step process infographic for onboarding new team members',
];

const _steps = [('Brand Details', LucideIcons.chartColumn), ('Goals & Style', LucideIcons.target)];

class _InfographicFormState extends State<InfographicForm> {
  StudioFormHost get host => widget.host;

  int _step = 1;
  String? _error;
  bool _generating = false;

  // Brand details
  late final _name = TextEditingController(text: host.brandName);
  late final _description = TextEditingController(text: host.brandDescription);
  late final _url = TextEditingController(text: host.brandUrl);
  late String _brandColor = host.brand?.primaryColor ?? '#f59e0b';
  late String? _logo = host.brandLogo;
  bool _importing = false;

  // Goals & style
  String _goal = 'Brand Awareness';
  String _audience = 'B2C';
  String _format = 'PNG';
  String _orientation = 'Portrait';
  String _chartStyle = 'mixed';

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_url.text.trim().isEmpty) return setState(() => _error = 'Please enter a valid brand URL.');
    setState(() => _importing = true);
    try {
      final d = await host.api.importBrand(_url.text);
      if (!mounted) return;
      setState(() {
        _name.text = d.name ?? '';
        _description.text = d.description ?? '';
        _brandColor = d.primaryColor ?? '#f59e0b';
        _logo = d.logo;
        _error = null;
      });
      Toast.success('Brand imported!');
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to import brand. Check the URL.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _continue() {
    if (_step == 1 && _name.text.trim().isEmpty) return setState(() => _error = 'Please enter a brand name.');
    if (_step == 1 && _description.text.trim().isEmpty) {
      return setState(() => _error = 'Please enter an infographic description.');
    }
    setState(() {
      _error = null;
      _step++;
    });
  }

  Future<void> _generate() async {
    if (_name.text.trim().isEmpty || _description.text.trim().isEmpty) {
      return setState(() => _error = 'Brand name and description are required.');
    }
    setState(() {
      _error = null;
      _generating = true;
    });
    String? nn(String s) => s.trim().isEmpty ? null : s.trim();
    final error = await host.generate({
      'creativeType': host.creative.id,
      'categoryType': host.category.id,
      'brandName': nn(_name.text),
      'description': nn(_description.text),
      'brandColor': _brandColor,
      'primaryColor': _brandColor,
      'logo': _logo,
      'campaignGoal': _goal,
      'audience': _audience,
      'fileFormat': _format,
      'orientation': _orientation,
      'chartStyle': _chartStyle,
      'count': 4,
      'sourceUrl': nn(_url.text),
      'generatedAt': nowIso(),
    });
    if (!mounted) return;
    setState(() {
      _generating = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = host.color;
    return FormColumn(
      children: [
        StepIndicator(steps: _steps, current: _step, accent: accent, onTap: (s) => setState(() => _step = s)),
        if (_error != null) FormErrorBanner(_error!),
        if (_step == 1)
          FormColumn(
            children: [
              const FormSectionTitle('Brand Details'),
              UrlImportBox(controller: _url, accent: accent, loading: _importing, onImport: _import),
              FormFieldBlock(
                label: 'Brand / Project Name',
                required: true,
                child: StudioTextField(
                  controller: _name,
                  accent: accent,
                  hint: 'e.g. Acme Corp',
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              FormFieldBlock(
                label: 'Infographic Description',
                required: true,
                child: StudioTextField(
                  controller: _description,
                  accent: accent,
                  hint: 'Describe your infographic… topic, key data points, story you want to tell.',
                  maxLines: 4,
                  maxLength: 500,
                  onInspire: () => setState(() {
                    _description.text = pickPrompt(_inspire);
                    _error = null;
                  }),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              FormFieldBlock(
                label: 'Brand Color',
                child: BrandColorField(value: _brandColor, onChanged: (v) => setState(() => _brandColor = v)),
              ),
              FormFieldBlock(
                label: 'Logo',
                child: LogoField(
                  api: host.api,
                  value: _logo,
                  accent: accent,
                  onChanged: (v) => setState(() => _logo = v),
                ),
              ),
            ],
          )
        else
          FormColumn(
            children: [
              const FormSectionTitle('Goals & Style'),
              FormFieldBlock(
                label: 'Campaign Goal',
                child: ChipWrap(
                  children: [
                    for (final (g, emoji) in _goals)
                      OptionChip(
                        label: g,
                        emoji: emoji,
                        accent: accent,
                        active: _goal == g,
                        onTap: () => setState(() => _goal = g),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Target Audience',
                child: ChipWrap(
                  children: [
                    for (final (a, desc) in _audiences)
                      OptionChip(
                        label: a,
                        desc: desc,
                        accent: accent,
                        active: _audience == a,
                        onTap: () => setState(() => _audience = a),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Chart Style',
                child: ChipWrap(
                  children: [
                    for (final (v, label, desc) in _chartStyles)
                      OptionChip(
                        label: label,
                        desc: desc,
                        accent: accent,
                        active: _chartStyle == v,
                        onTap: () => setState(() => _chartStyle = v),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Export Format',
                child: ChipWrap(
                  children: [
                    for (final (f, desc) in _formats)
                      OptionChip(
                        label: f,
                        desc: desc,
                        accent: accent,
                        active: _format == f,
                        onTap: () => setState(() => _format = f),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Orientation',
                child: ChipWrap(
                  children: [
                    for (final (o, icon) in _orientations)
                      OptionChip(
                        label: o,
                        icon: icon,
                        accent: accent,
                        active: _orientation == o,
                        onTap: () => setState(() => _orientation = o),
                      ),
                  ],
                ),
              ),
            ],
          ),
        FormNavBar(
          step: _step,
          totalSteps: _steps.length,
          accent: accent,
          generating: _generating,
          onBack: () => setState(() => _step--),
          onContinue: _continue,
          onGenerate: _generate,
          generateLabel: 'Generate Infographic',
        ),
      ],
    );
  }
}
