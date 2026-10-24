import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/ui/toast.dart';
import '../studio_form_kit.dart';

/// Port of `studio/forms/PresentationDeckForm.jsx`: Brand Details → Style & Format.
class PresentationDeckForm extends StatefulWidget {
  const PresentationDeckForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  State<PresentationDeckForm> createState() => _PresentationDeckFormState();
}

const _goals = [
  ('Brand Awareness', '📣'),
  ('Engagement', '💬'),
  ('Sales', '🛒'),
  ('Lead Generation', '🎯'),
  ('Website Traffic', '🌐'),
];

const _audiences = [
  ('B2B', 'B2B', 'Business owners, startups, agencies'),
  ('B2C', 'B2C', 'End consumers, everyday users'),
  ('Casual', 'Casual', 'Broad social media audience'),
  ('Inspirational', 'Inspirational', 'Entrepreneurs, creators, startups'),
  ('Sales', 'Direct / Sales', 'Hot leads, ad audiences'),
];

const _formats = [('PDF', 'Recommended'), ('PNG', 'Slide images'), ('PPTX', 'Editable deck')];

const _sizes = [
  ('1280x720', 'Standard', '1280×720 · Digital'),
  ('1920x1080', 'Widescreen', '1920×1080 · Full HD'),
  ('3600x2025', 'Print', '3600×2025 · 300 DPI'),
];

const _slideStyles = [
  ('minimal', 'Minimal', 'Clean white, bold type'),
  ('bold', 'Bold', 'Strong colors, big visuals'),
  ('corporate', 'Corporate', 'Professional and polished'),
  ('creative', 'Creative', 'Dynamic layouts, gradients'),
];

const _slideCounts = [
  ('5', '5 slides', 'Quick overview'),
  ('10', '10 slides', 'Standard deck'),
  ('15', '15 slides', 'Detailed pitch'),
  ('20', '20 slides', 'Full presentation'),
];

const _inspire = [
  'A professional pitch deck for a B2B SaaS startup targeting enterprise clients',
  'An educational presentation on the future of renewable energy and climate tech',
  'A sleek corporate overview deck showcasing Q4 performance and 2025 goals',
  'A compelling investor deck for a health-tech startup raising a Series A',
  'A product launch presentation introducing a new AI-powered mobile application',
  'A bold sales deck designed to close mid-market deals in financial services',
];

const _steps = [('Brand Details', LucideIcons.monitorPlay), ('Style & Format', LucideIcons.layoutTemplate)];

class _PresentationDeckFormState extends State<PresentationDeckForm> {
  StudioFormHost get host => widget.host;

  int _step = 1;
  String? _error;
  bool _generating = false;

  // Brand details
  late final _name = TextEditingController(text: host.brandName);
  late final _description = TextEditingController(text: host.brandDescription);
  late final _url = TextEditingController(text: host.brandUrl);
  late String _brandColor = host.brand?.primaryColor ?? '#4f46e5';
  late String? _logo = host.brandLogo;
  bool _importing = false;

  // Deck style
  String _slideStyle = 'minimal';
  String _slideCount = '10';

  // Goals & format
  String _goal = 'Brand Awareness';
  String _audience = 'B2B';
  String _format = 'PDF';
  String _size = '1920x1080';

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
        _brandColor = d.primaryColor ?? '#4f46e5';
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
      return setState(() => _error = 'Please enter a deck description.');
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
      'presentationGoal': _goal,
      'audience': _audience,
      'fileFormat': _format,
      'size': _size,
      'slideStyle': _slideStyle,
      'slideCount': _slideCount,
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
                label: 'Deck Description',
                required: true,
                child: StudioTextField(
                  controller: _description,
                  accent: accent,
                  hint: "Describe your presentation… topic, key message, who it's for, and what you want to achieve.",
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
              const FormSectionTitle('Style & Format'),
              FormFieldBlock(
                label: 'Visual Style',
                child: ChipWrap(
                  children: [
                    for (final (v, label, desc) in _slideStyles)
                      OptionChip(
                        label: label,
                        desc: desc,
                        accent: accent,
                        active: _slideStyle == v,
                        onTap: () => setState(() => _slideStyle = v),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Number of Slides',
                child: ChipWrap(
                  children: [
                    for (final (v, label, desc) in _slideCounts)
                      OptionChip(
                        label: label,
                        desc: desc,
                        accent: accent,
                        active: _slideCount == v,
                        onTap: () => setState(() => _slideCount = v),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Presentation Goal',
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
                    for (final (v, label, desc) in _audiences)
                      OptionChip(
                        label: label,
                        desc: desc,
                        accent: accent,
                        active: _audience == v,
                        onTap: () => setState(() => _audience = v),
                      ),
                  ],
                ),
              ),
              // Side by side on the web from `sm`; stacked on a phone.
              FormFieldBlock(
                label: 'Slide Size',
                child: ChipWrap(
                  children: [
                    for (final (v, label, desc) in _sizes)
                      OptionChip(
                        label: label,
                        desc: desc,
                        accent: accent,
                        active: _size == v,
                        onTap: () => setState(() => _size = v),
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
          generateLabel: 'Generate Deck',
        ),
      ],
    );
  }
}
