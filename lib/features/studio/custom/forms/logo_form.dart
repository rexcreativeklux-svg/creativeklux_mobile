import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/ui/toast.dart';
import '../studio_form_kit.dart';
import 'designer_shared.dart';

/// Port of `studio/forms/LogoForm.jsx`: Brand Identity → Style & Layout →
/// Reference Images.
class LogoForm extends StatefulWidget {
  const LogoForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  State<LogoForm> createState() => _LogoFormState();
}

/// The web's THEME — the import falls back to it when a site has no colour.
const _theme = '#7c3aed';

const _logoStyles = [
  ('wordmark', 'Wordmark', 'Text-only logo'),
  ('lettermark', 'Lettermark', 'Initials-based'),
  ('pictorial', 'Pictorial', 'Icon/symbol'),
  ('combination', 'Combination', 'Icon + text'),
  ('emblem', 'Emblem', 'Badge / seal'),
  ('mascot', 'Mascot', 'Character-based'),
];

const _visualStyles = [
  ('minimal', 'Minimal'),
  ('bold', 'Bold'),
  ('elegant', 'Elegant'),
  ('playful', 'Playful'),
  ('corporate', 'Corporate'),
  ('modern', 'Modern'),
  ('retro', 'Retro'),
  ('luxury', 'Luxury'),
];

const _fileFormats = ['PNG', 'SVG', 'PDF', 'WEBP'];

const _layouts = [
  ('stacked', 'Stacked', 'Icon above text'),
  ('horizontal', 'Horizontal', 'Icon beside text'),
  ('icon_only', 'Icon Only', 'Symbol standalone'),
  ('text_only', 'Text Only', 'No icon'),
];

const _brandColors = ['#7c3aed', '#2563eb', '#059669', '#db2777', '#ef4444', '#f59e0b'];

const _steps = [
  ('Brand Identity', LucideIcons.layers),
  ('Style & Layout', LucideIcons.palette),
  ('Reference Images', LucideIcons.images),
];

class _LogoFormState extends State<LogoForm> {
  StudioFormHost get host => widget.host;

  int _step = 1;
  String? _error;
  bool _generating = false;

  // Brand identity — seeded like the studio page's shared formData.
  late final _name = TextEditingController(text: host.brandName);
  late final _description = TextEditingController(text: host.brandDescription);
  late final _url = TextEditingController(text: host.brandUrl);
  late String _brandColor = host.brand?.primaryColor ?? '#2563eb';
  late String? _logo = host.brandLogo;
  String _font = 'Montserrat';
  bool _importing = false;

  // Style & layout — logo type and layout start unpicked, as on the web.
  String? _logoStyle;
  String _visualStyle = 'modern';
  String? _layout;
  String _fileFormat = 'PNG';

  // Reference images (hosted URLs).
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
        _brandColor = d.primaryColor ?? _theme;
        _font = 'Montserrat';
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
    if (_step == 1 && _name.text.trim().isEmpty) return setState(() => _error = 'Brand name is required.');
    if (_step == 2 && (_logoStyle == null || _layout == null)) {
      return setState(() => _error = 'Please select a logo style, visual style, and layout.');
    }
    setState(() {
      _error = null;
      _step++;
    });
  }

  Future<void> _generate() async {
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
      'logo': _logo,
      'visualStyle': _visualStyle,
      'font': _font,
      'sourceUrl': nn(_url.text),
      'fileFormat': _fileFormat,
      // logo-specific (tagline / industry / notes are commented out on the web)
      'tagline': null,
      'industry': null,
      'logoStyle': _logoStyle,
      'layout': _layout,
      'logoNotes': null,
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
    void clear() => _error = null;
    return FormColumn(
      children: [
        StepIndicator(steps: _steps, current: _step, accent: accent, onTap: (s) => setState(() => _step = s)),
        if (_error != null) FormErrorBanner(_error!),
        if (_step == 1)
          FormColumn(
            children: [
              const FormSectionTitle('Brand Identity'),
              UrlImportBox(controller: _url, accent: accent, loading: _importing, onImport: _import),
              FormFieldBlock(
                label: 'Brand Name',
                required: true,
                child: StudioTextField(
                  controller: _name,
                  accent: accent,
                  hint: 'Your Brand Name',
                  onChanged: (_) => setState(clear),
                ),
              ),
              FormFieldBlock(
                label: 'Brand Description',
                child: StudioTextField(
                  controller: _description,
                  accent: accent,
                  hint: 'Describe your brand, its values, and what makes it unique…',
                  maxLines: 3,
                  onChanged: (_) => setState(clear),
                ),
              ),
              FormFieldBlock(
                label: 'Brand Color',
                child: BrandColorField(
                  value: _brandColor,
                  presets: _brandColors,
                  onChanged: (v) => setState(() {
                    _brandColor = v;
                    clear();
                  }),
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
              const FormSectionTitle('Style & Layout'),
              FormFieldBlock(
                label: 'Logo Type',
                required: true,
                child: ChipWrap(
                  children: [
                    for (final (v, label, desc) in _logoStyles)
                      OptionChip(
                        label: label,
                        desc: desc,
                        accent: accent,
                        active: _logoStyle == v,
                        onTap: () => setState(() {
                          _logoStyle = v;
                          clear();
                        }),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Visual Aesthetic',
                required: true,
                child: ChipWrap(
                  children: [
                    for (final (v, label) in _visualStyles)
                      OptionChip(
                        label: label,
                        accent: accent,
                        active: _visualStyle == v,
                        onTap: () => setState(() {
                          _visualStyle = v;
                          clear();
                        }),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Layout Orientation',
                required: true,
                child: ChipWrap(
                  children: [
                    for (final (v, label, desc) in _layouts)
                      OptionChip(
                        label: label,
                        desc: desc,
                        accent: accent,
                        active: _layout == v,
                        onTap: () => setState(() {
                          _layout = v;
                          clear();
                        }),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Output Format',
                child: ChipWrap(
                  children: [
                    for (final f in _fileFormats)
                      OptionChip(
                        label: f == 'PNG' ? '$f ✓' : f,
                        accent: accent,
                        active: _fileFormat == f,
                        onTap: () => setState(() => _fileFormat = f),
                      ),
                  ],
                ),
              ),
            ],
          )
        else
          DesignerImagesStep(
            host: host,
            title: 'Reference Images',
            intro:
                "Upload or select images that inspire your logo's look and feel. These help guide the AI generation.",
            selectedLabel: 'Selected references',
            zoneTitle: 'Add Reference Images',
            zoneSubtitle: 'Logos, brand assets, or style inspiration',
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
          generateLabel: 'Generate Logos',
          generateIcon: LucideIcons.sparkles,
        ),
      ],
    );
  }
}
