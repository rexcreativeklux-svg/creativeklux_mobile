import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/ui/toast.dart';
import '../studio_form_kit.dart';
import 'designer_shared.dart';

/// Port of `studio/forms/BannersPrintDigitalForm.jsx`: Brand & Content →
/// Size & Purpose → Reference Images.
class BannersForm extends StatefulWidget {
  const BannersForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  State<BannersForm> createState() => _BannersFormState();
}

/// The web's THEME — the import falls back to it when a site has no colour.
const _theme = '#7c3aed';

const _mediums = [
  ('digital', 'Digital', LucideIcons.monitor, 'Web, social, display'),
  ('print', 'Print', LucideIcons.printer, 'Vinyl, fabric, paper'),
  ('both', 'Both', LucideIcons.layers, 'Multi-use assets'),
];

// Dimensions mirror the backend's SIZES['banners_print_digital'] map — it is
// the source of truth for every size both sides carry. The print sizes have no
// backend counterpart and are left as they are.
const _digitalSizes = [
  ('2560x1440', 'YouTube Banner', '2560 × 1440 px'),
  ('851x315', 'Facebook Banner', '851 × 315 px'),
  ('1584x396', 'LinkedIn Banner', '1584 × 396 px'),
  ('1500x500', 'Twitter Banner', '1500 × 500 px'),
  ('1200x628', 'Display Ad Landscape', '1200 × 628 px'),
  ('300x250', 'Display Ad Rectangle', '300 × 250 px'),
  ('728x90', 'Leaderboard Ad', '728 × 90 px'),
  ('160x600', 'Wide Skyscraper', '160 × 600 px'),
];

const _printSizes = [
  ('2x6ft', 'Step & Repeat', '2 × 6 ft'),
  ('3x6ft', 'Retractable', '3 × 6 ft'),
  ('4x8ft', 'Trade Show', '4 × 8 ft'),
  ('8x2ft', 'Outdoor Horizontal', '8 × 2 ft'),
  ('24x36in', 'Poster / Yard Sign', '24 × 36 in'),
  ('18x24in', 'Medium Poster', '18 × 24 in'),
  ('custom', 'Custom Size', 'Enter dimensions'),
];

const _visualStyles = [
  ('minimal', 'Minimal'),
  ('bold', 'Bold'),
  ('corporate', 'Corporate'),
  ('vibrant', 'Vibrant'),
  ('elegant', 'Elegant'),
  ('modern', 'Modern'),
  ('retro', 'Retro'),
  ('dark', 'Dark'),
];

const _purposes = [
  ('event', 'Event / Conference'),
  ('sale', 'Sale / Promotion'),
  ('product', 'Product Launch'),
  ('brand', 'Brand Awareness'),
  ('social', 'Social Media'),
  ('trade_show', 'Trade Show'),
  ('announcement', 'Announcement'),
  ('seasonal', 'Seasonal / Holiday'),
];

const _audiences = [
  ('B2B', 'B2B', 'Business professionals'),
  ('B2C', 'B2C', 'End consumers'),
  ('Casual', 'Casual', 'Broad social audience'),
  ('Inspirational', 'Inspirational', 'Creators & entrepreneurs'),
  ('Sales', 'Direct Sales', 'Hot leads, ad audiences'),
];

const _digitalFormats = ['PNG', 'JPEG', 'WEBP', 'SVG'];
const _printFormats = ['PDF', 'TIFF', 'EPS', 'PNG'];

// The web's two print-spec <select>s, shown as chips on a phone.
const _bleeds = [('0.125in', '0.125 in', 'Standard'), ('0.25in', '0.25 in', 'Large format'), ('none', 'None', null)];
const _dpis = [
  ('300dpi', '300 DPI', 'Standard print'),
  ('150dpi', '150 DPI', 'Large format'),
  ('72dpi', '72 DPI', 'Digital only'),
];

const _brandColors = ['#7c3aed', '#2563eb', '#059669', '#db2777', '#ef4444', '#f59e0b'];

const _steps = [
  ('Brand & Content', LucideIcons.layers),
  ('Size & Purpose', LucideIcons.layoutTemplate),
  ('Reference Images', LucideIcons.images),
];

class _BannersFormState extends State<BannersForm> {
  StudioFormHost get host => widget.host;

  int _step = 1;
  String? _error;
  bool _generating = false;

  // Brand & content — seeded like the studio page's shared formData.
  late final _name = TextEditingController(text: host.brandName);
  final _headline = TextEditingController();
  final _subheadline = TextEditingController();
  final _cta = TextEditingController();
  final _ctaUrl = TextEditingController();
  late final _description = TextEditingController(text: host.brandDescription);
  late final _url = TextEditingController(text: host.brandUrl);
  late String _brandColor = host.brand?.primaryColor ?? '#2563eb';
  late String? _logo = host.brandLogo;
  String _font = 'Montserrat';
  bool _importing = false;

  // Size & purpose. The medium starts unpicked (the lists show Digital until
  // one is chosen), and picking one resets the size and the format.
  String? _medium;
  String? _size;
  final _customWidth = TextEditingController();
  final _customHeight = TextEditingController();
  String? _purpose;
  String _visualStyle = 'modern';
  String _audience = 'B2C';
  String _fileFormat = 'PNG';

  // Like the web, these stay unset (→ null) until the user picks one, even
  // though the first option shows as selected.
  String? _bleed;
  String? _dpi;

  // Reference images (hosted URLs).
  List<String> _images = [];

  String get _shownMedium => _medium ?? 'digital';
  bool get _isPrint => _shownMedium == 'print';
  String get _defaultFormat => _isPrint ? 'PDF' : 'PNG';

  @override
  void dispose() {
    for (final c in [_name, _headline, _subheadline, _cta, _ctaUrl, _description, _url, _customWidth, _customHeight]) {
      c.dispose();
    }
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

  void _pickMedium(String m) => setState(() {
    final changed = _shownMedium != m;
    _medium = m;
    // The web's `useEffect([medium])`: a new medium means a new size list and
    // format list, so both reset.
    if (changed) {
      _size = null;
      _fileFormat = _defaultFormat;
    }
    _error = null;
  });

  void _continue() {
    String? err;
    if (_step == 1 && _name.text.trim().isEmpty) {
      err = 'Brand name is required.';
    } else if (_step == 1 && _headline.text.trim().isEmpty) {
      err = 'Banner headline is required.';
    } else if (_step == 2 && _medium == null) {
      err = 'Please select a banner medium.';
    } else if (_step == 2 && _size == null) {
      err = 'Please select a banner size.';
    } else if (_step == 2 && _purpose == null) {
      err = 'Please select a banner purpose.';
    }
    if (err != null) return setState(() => _error = err);
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
    String? nn(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final error = await host.generate({
      'creativeType': host.creative.id,
      'categoryType': host.category.id,
      'brandName': nn(_name),
      'bannerHeadline': nn(_headline),
      'bannerSubheadline': nn(_subheadline),
      'bannerCta': nn(_cta),
      'bannerCtaUrl': nn(_ctaUrl),
      'description': nn(_description),
      'brandColor': _brandColor,
      'logo': _logo,
      'font': _font,
      'visualStyle': _visualStyle,
      'bannerMedium': _medium,
      'bannerSize': _size,
      'bannerPurpose': _purpose,
      'audience': _audience,
      'fileFormat': _fileFormat,
      // The chips show 0.125in / 300 DPI as picked before any tap; the web
      // then sent null for them. Send what the user sees, for print banners.
      'bleedMargin': _shownMedium == 'print' || _shownMedium == 'both' ? _bleed ?? '0.125in' : _bleed,
      'printDpi': _shownMedium == 'print' || _shownMedium == 'both' ? _dpi ?? '300dpi' : _dpi,
      'customWidth': nn(_customWidth),
      'customHeight': nn(_customHeight),
      'bannerNotes': null,
      'sourceUrl': nn(_url),
      'images': _images,
      'generatedAt': nowIso(),
    });
    if (!mounted) return;
    setState(() {
      _generating = false;
      _error = error;
    });
  }

  Widget _text(String label, TextEditingController c, String hint, {bool required = false, TextInputType? type}) =>
      FormFieldBlock(
        label: label,
        required: required,
        child: StudioTextField(
          controller: c,
          accent: host.color,
          hint: hint,
          keyboardType: type,
          onChanged: (_) => setState(() => _error = null),
        ),
      );

  Widget _chips<T>(List<(T, String, String?)> options, T? value, ValueChanged<T> onPick) => ChipWrap(
    children: [
      for (final (v, label, desc) in options)
        OptionChip(label: label, desc: desc, accent: host.color, active: value == v, onTap: () => onPick(v)),
    ],
  );

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
              const FormSectionTitle('Brand & Banner Content'),
              UrlImportBox(controller: _url, accent: accent, loading: _importing, onImport: _import),
              _text('Brand / Company Name', _name, 'Acme Corp', required: true),
              _text(
                'Banner Headline',
                _headline,
                "The big, bold text on your banner (e.g., 'Summer Sale — Up to 50% Off')",
                required: true,
              ),
              _text('Subheadline / Supporting Text', _subheadline, 'A shorter supporting line below the headline'),
              FieldPair(
                left: _text('Call to Action (CTA)', _cta, 'e.g., Shop Now, Learn More, Register Free'),
                right: _text(
                  'CTA URL / QR Destination',
                  _ctaUrl,
                  'https://yourdomain.com/offer',
                  type: TextInputType.url,
                ),
              ),
              FormFieldBlock(
                label: 'Additional Context',
                child: StudioTextField(
                  controller: _description,
                  accent: accent,
                  hint: 'Any extra context, key messages, or design direction for the AI…',
                  maxLines: 2,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              FormFieldBlock(
                label: 'Brand Color',
                child: BrandColorField(
                  value: _brandColor,
                  presets: _brandColors,
                  onChanged: (v) => setState(() {
                    _brandColor = v;
                    _error = null;
                  }),
                ),
              ),
              FormFieldBlock(
                label: 'Logo (optional)',
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
          _sizeStep(context, accent)
        else
          DesignerImagesStep(
            host: host,
            title: 'Reference Images',
            zoneTitle: 'Upload or Search Reference Images',
            zoneSubtitle: 'Brand photos, textures, or design inspiration',
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
          generateLabel: 'Generate Banners',
          generateIcon: LucideIcons.sparkles,
        ),
      ],
    );
  }

  Widget _sizeStep(BuildContext context, Color accent) {
    final c = context.colors;
    final sizes = _isPrint ? _printSizes : _digitalSizes;
    final formats = _isPrint ? _printFormats : _digitalFormats;
    return FormColumn(
      children: [
        const FormSectionTitle('Size, Medium & Purpose'),
        FormFieldBlock(
          label: 'Banner Medium',
          required: true,
          child: ChipWrap(
            children: [
              for (final (v, label, icon, desc) in _mediums)
                OptionChip(
                  label: label,
                  desc: desc,
                  icon: icon,
                  accent: accent,
                  active: _medium == v,
                  onTap: () => _pickMedium(v),
                ),
            ],
          ),
        ),
        FormFieldBlock(
          label: _isPrint ? 'Print Size' : 'Digital Size',
          required: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _chips(
                sizes,
                _size,
                (v) => setState(() {
                  _size = v;
                  _error = null;
                }),
              ),
              if (_isPrint && _size == 'custom') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: StudioTextField(controller: _customWidth, accent: accent, hint: 'Width (e.g., 48)'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('×', style: TextStyle(fontSize: 14, color: c.gray400)),
                    ),
                    Expanded(
                      child: StudioTextField(controller: _customHeight, accent: accent, hint: 'Height (e.g., 96")'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        FormFieldBlock(
          label: 'Banner Purpose',
          required: true,
          child: _chips(
            [for (final (v, l) in _purposes) (v, l, null)],
            _purpose,
            (v) => setState(() {
              _purpose = v;
              _error = null;
            }),
          ),
        ),
        FormFieldBlock(
          label: 'Visual Style',
          child: _chips(
            [for (final (v, l) in _visualStyles) (v, l, null)],
            _visualStyle,
            (v) => setState(() => _visualStyle = v),
          ),
        ),
        FormFieldBlock(
          label: 'Target Audience',
          child: _chips(_audiences, _audience, (v) => setState(() => _audience = v)),
        ),
        FormFieldBlock(
          label: 'Output Format',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _chips(
                [for (final f in formats) (f, f == _defaultFormat ? '$f ✓' : f, null)],
                _fileFormat,
                (v) => setState(() => _fileFormat = v),
              ),
              if (_isPrint) ...[
                const SizedBox(height: 6),
                Text(
                  'PDF is recommended for print-ready files with bleed marks.',
                  style: TextStyle(fontSize: 11, color: c.gray400),
                ),
              ],
            ],
          ),
        ),
        if (_shownMedium == 'print' || _shownMedium == 'both')
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.15)),
            ),
            child: FormColumn(
              gap: 12,
              children: [
                Text(
                  'Print Specifications',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color.lerp(accent, Colors.black, 0.25),
                  ),
                ),
                FormFieldBlock(
                  label: 'Bleed Margin',
                  child: _chips(_bleeds, _bleed ?? '0.125in', (v) => setState(() => _bleed = v)),
                ),
                FormFieldBlock(
                  label: 'Print Resolution',
                  child: _chips(_dpis, _dpi ?? '300dpi', (v) => setState(() => _dpi = v)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
