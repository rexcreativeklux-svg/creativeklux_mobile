import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/ui/toast.dart';
import '../studio_form_kit.dart';
import 'designer_shared.dart';

/// Port of `studio/forms/FlyerForm.jsx`: Brand Details → Goals & Layout →
/// Background Image.
class FlyerForm extends StatefulWidget {
  const FlyerForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  State<FlyerForm> createState() => _FlyerFormState();
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

const _formats = [('PDF', 'Print-ready'), ('PNG', 'Transparent BG'), ('JPEG', 'Compressed')];

// Dimensions mirror the backend's SIZES['flyers'] map — it is the source of
// truth (the digital A-series render at 96 DPI there).
const _sizes = [
  ('816x1056', 'Digital Letter', '8.5×11 in · 96 DPI'),
  ('794x1123', 'Digital A4', '210×297 mm · 96 DPI'),
  ('2550x3300', 'Print Letter', '8.5×11 in · 300 DPI'),
  ('2480x3508', 'Print A4', '210×297 mm · 300 DPI'),
  ('559x794', 'Digital A5', '148×210 mm · 96 DPI'),
];

const _orientations = [('Portrait', LucideIcons.rectangleVertical), ('Landscape', LucideIcons.rectangleHorizontal)];

const _fonts = ['Arial', 'Helvetica', 'Times New Roman', 'Inter', 'Roboto', 'Playfair Display', 'Poppins'];

const _brandColors = ['#059669', '#2563eb', '#7c3aed', '#db2777', '#ef4444', '#f59e0b'];

const _inspire = [
  'A vibrant digital flyer for a summer music festival with bold typography',
  'A professional print flyer for a business leadership seminar',
  'A colorful community event flyer with a warm, welcoming feel',
  'An elegant wedding announcement flyer with gold accents',
  'A bold promotional flyer for a limited-time product sale',
  'A minimalist startup launch flyer with clean lines and modern fonts',
];

const _steps = [
  ('Brand Details', LucideIcons.image),
  ('Goals & Layout', LucideIcons.target),
  ('Background Image', LucideIcons.images),
];

class _FlyerFormState extends State<FlyerForm> {
  StudioFormHost get host => widget.host;

  int _step = 1;
  String? _error;
  bool _generating = false;

  // Brand details — the flyer keeps its own state (not the shared formData),
  // with its own green colour default.
  late final _name = TextEditingController(text: host.brandName);
  late final _description = TextEditingController(text: host.brandDescription);
  late final _url = TextEditingController(text: host.brandUrl);
  late String _brandColor = host.brand?.primaryColor ?? '#059669';
  late String _font = _fonts.contains(host.brand?.fonts) ? host.brand!.fonts! : 'Inter';
  late String? _logo = host.brandLogo;
  bool _importing = false;

  // Goals & format — goal and audience start unpicked, as on the web.
  String? _goal;
  String? _audience;
  String _format = 'PDF';
  String _size = '816x1056';
  String _orientation = 'Portrait';

  // Background images (hosted URLs).
  List<String> _images = [];

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
        _brandColor = d.primaryColor ?? '#059669';
        _font = 'Inter';
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
    String? err;
    if (_step == 1 && _name.text.trim().isEmpty) {
      err = 'Please enter a brand name.';
    } else if (_step == 1 && _description.text.trim().isEmpty) {
      err = 'Please enter a flyer description.';
    } else if (_step == 2 && _goal == null) {
      err = 'Please select a campaign goal.';
    } else if (_step == 2 && _audience == null) {
      err = 'Please select a target audience.';
    }
    if (err != null) return setState(() => _error = err);
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
      // Project Name is commented out on the web, so it's always empty.
      'projectName': null,
      'description': nn(_description.text),
      'brandColor': _brandColor,
      'primaryColor': _brandColor,
      'logo': _logo,
      'font': _font,
      'sourceUrl': nn(_url.text),
      'size': _size,
      'orientation': _orientation,
      'campaignGoal': _goal,
      'audience': _audience,
      'fileFormat': _format,
      'images': _images,
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
                label: 'Flyer Description',
                required: true,
                child: StudioTextField(
                  controller: _description,
                  accent: accent,
                  hint: 'Describe your flyer… event name, key message, tone, and any special details.',
                  maxLines: 4,
                  maxLength: 500,
                  onInspire: () => setState(() {
                    _description.text = pickPrompt(_inspire);
                    _error = null;
                  }),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              // The web previews each chip in its own typeface (CSS font-family
              // from the browser); on a phone those faces aren't installed, so
              // the chips show plain labels.
              FormFieldBlock(
                label: 'Font',
                child: ChipWrap(
                  children: [
                    for (final f in _fonts)
                      OptionChip(label: f, accent: accent, active: _font == f, onTap: () => setState(() => _font = f)),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Brand Color',
                child: BrandColorField(
                  value: _brandColor,
                  presets: _brandColors,
                  onChanged: (v) => setState(() => _brandColor = v),
                ),
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
        else if (_step == 2)
          FormColumn(
            children: [
              const FormSectionTitle('Goals & Layout'),
              FormFieldBlock(
                label: 'Campaign Goal',
                required: true,
                child: ChipWrap(
                  children: [
                    for (final (g, emoji) in _goals)
                      OptionChip(
                        label: g,
                        emoji: emoji,
                        accent: accent,
                        active: _goal == g,
                        onTap: () => setState(() {
                          _goal = g;
                          _error = null;
                        }),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Target Audience',
                required: true,
                child: ChipWrap(
                  children: [
                    for (final (v, label, desc) in _audiences)
                      OptionChip(
                        label: label,
                        desc: desc,
                        accent: accent,
                        active: _audience == v,
                        onTap: () => setState(() {
                          _audience = v;
                          _error = null;
                        }),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Flyer Size',
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
          )
        else
          DesignerImagesStep(
            host: host,
            title: 'Background Image',
            zoneTitle: 'Upload or Search More Images',
            zoneSubtitle: 'Pick from your phone or tap a brand image above',
            images: _images,
            onChanged: (v) => setState(() => _images = v),
          ),
        FormNavBar(
          step: _step,
          totalSteps: _steps.length,
          accent: accent,
          generating: _generating,
          onBack: () => setState(() => _step--),
          onContinue: _continue,
          onGenerate: _generate,
          generateLabel: 'Generate Flyers',
        ),
      ],
    );
  }
}
