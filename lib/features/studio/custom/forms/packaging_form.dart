import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/ui/media.dart';
import '../../../../core/ui/toast.dart';
import '../studio_form_kit.dart';

/// Port of `studio/forms/PackagingMockupForm.jsx`:
/// Brand & Product → Format & Goals → Background Image.
///
/// The web's generate is a placeholder (it echoes the picked backgrounds back
/// as "results"); here the form's fields go to create-design like every other
/// form, with the backgrounds as `images`.
class PackagingForm extends StatefulWidget {
  const PackagingForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  State<PackagingForm> createState() => _PackagingFormState();
}

const _mockupTypes = [
  ('box', 'Box', 'Folding carton, gift box', LucideIcons.package),
  ('bottle', 'Bottle', 'Glass, plastic, cosmetic', LucideIcons.milk),
  ('bag', 'Bag', 'Paper, kraft, shopping', LucideIcons.shoppingBag),
  ('can', 'Can', 'Beverage, food, spray', LucideIcons.cupSoda),
  ('pouch', 'Pouch', 'Stand-up, flat, ziplock', LucideIcons.package2),
  ('tube', 'Tube', 'Cosmetic, squeeze, lip', LucideIcons.cylinder),
  ('jar', 'Jar', 'Glass, cream, candle', LucideIcons.glassWater),
  ('label', 'Label', 'Sticker, wrap-around', LucideIcons.tag),
];

/// (value, label, desc, group)
const _resolutions = [
  ('1000x1000', 'Digital Square', '1000×1000 px', 'Digital'),
  ('1200x800', 'Digital Rectangular', '1200×800 px', 'Digital'),
  ('3000x3000', 'Print Square', '10×10 in, 300 DPI', 'Print'),
  ('3600x2400', 'Print Rectangular', '12×8 in, 300 DPI', 'Print'),
];

const _formats = [('PNG', 'Recommended'), ('JPEG', 'Compressed'), ('PDF', 'Print-ready')];

const _goals = ['Brand Awareness', 'Engagement', 'Sales', 'Lead Generation', 'Website Traffic'];

const _audiences = [
  ('B2B', 'Business owners, startups, agencies'),
  ('B2C', 'End consumers, everyday users'),
  ('Casual', 'Broad social media audience'),
  ('Educational', 'Students, researchers, learners'),
  ('Professional', 'Industry experts, professionals'),
];

const _visualStyles = [
  ('minimal', 'Minimal'),
  ('luxury', 'Luxury'),
  ('playful', 'Playful'),
  ('eco', 'Eco / Natural'),
  ('bold', 'Bold'),
  ('corporate', 'Corporate'),
];

const _brandColors = ['#7c3aed', '#2563eb', '#059669', '#f59e0b', '#ec4899'];

const _fonts = ['Arial', 'Helvetica', 'Times New Roman', 'Roboto', 'Poppins'];

const _inspire = [
  'A sleek box packaging for a luxury skincare product',
  'A vibrant bottle label for an artisan energy drink',
  'A minimalist bag design for premium organic coffee',
  'A modern can design for a craft beer series',
  'An eco-friendly pouch for sustainable wellness snacks',
];

const _steps = [
  ('Brand & Product', LucideIcons.package),
  ('Format & Goals', LucideIcons.scan),
  ('Background Image', LucideIcons.images),
];

const _maxImages = 5;

class _PackagingFormState extends State<PackagingForm> {
  StudioFormHost get host => widget.host;

  int _step = 1;
  String? _error;
  bool _generating = false;

  late final _url = TextEditingController(text: host.brandUrl);
  bool _importing = false;

  // Brand & product — seeded from the studio page's shared formData, which
  // starts from the active brand.
  late final _brandName = TextEditingController(text: host.brandName);
  final _projectName = TextEditingController();
  final _tagline = TextEditingController();
  late final _description = TextEditingController(text: host.brandDescription);
  late final _caption = TextEditingController(text: host.brand == null ? '' : 'Discover ${host.brandName}!');
  final _hashtags = TextEditingController();
  String? _mockupType;
  // The shared default is "modern", which isn't one of this form's chips, so
  // nothing shows selected until the user picks — as on the web.
  String _visualStyle = 'modern';
  late String _primary = host.brand?.primaryColor ?? '#2563eb';
  late String _secondary = host.brand?.secondaryColor ?? '#0ea5e9';
  // The shared default ("Montserrat") isn't in the web's <select>, which then
  // shows Arial, so start on what the user would see.
  String _font = 'Arial';
  late String? _logo = host.brandLogo;

  // Format & goals
  String? _resolution;
  String _format = 'PNG';
  String _goal = 'Engagement';
  String _audience = 'B2C';

  // Background images — hosted URLs.
  List<String> _images = [];
  List<String> _importedImages = [];

  // RecommendedImagesSection: Pexels photos for "<brand> <mockup> product
  // packaging design", through the web app's /api/pexels (key stays server-side).
  List<(String, String)> _recommended = [];
  bool _loadingRecommended = false;
  String? _recommendedFor;

  @override
  void dispose() {
    for (final c in [_url, _brandName, _projectName, _tagline, _description, _caption, _hashtags]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() => _error = null);

  Future<void> _import() async {
    if (_url.text.trim().isEmpty) return setState(() => _error = 'Please enter a valid brand URL.');
    setState(() => _importing = true);
    try {
      final d = await host.api.importBrand(_url.text);
      if (!mounted) return;
      final cleanName = (d.name ?? '').replaceAll(RegExp(r'\s+'), '');
      setState(() {
        _brandName.text = d.name ?? '';
        _description.text = d.description ?? '';
        // The import doesn't return a tagline or font; these are the web's fallbacks.
        _tagline.text = '';
        _font = 'Arial';
        _primary = d.primaryColor ?? '#7c3aed';
        _secondary = d.secondaryColor ?? '#2563eb';
        _logo = d.logo;
        if (_caption.text.isEmpty) _caption.text = 'Beautiful packaging by ${d.name ?? ''} – ready to launch!';
        if (_hashtags.text.trim().isEmpty) {
          _hashtags.text = ['#PackagingDesign', '#Mockup', '#Branding', '#$cleanName'].join(' ');
        }
        _importedImages = d.images;
        _error = null;
      });
      Toast.success('Brand imported!');
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to import brand. Check the URL.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _loadRecommended() async {
    final brand = _brandName.text.trim();
    if (brand.isEmpty) return;
    final query = '$brand ${_mockupType ?? 'packaging'} product packaging design';
    if (query == _recommendedFor) return;
    _recommendedFor = query;
    setState(() => _loadingRecommended = true);
    try {
      final res = await Dio().get<Map<String, dynamic>>(
        '${AppConfig.webAppUrl}/api/pexels',
        queryParameters: {'query': query, 'per_page': 8},
      );
      final photos = res.data?['photos'];
      if (!mounted || query != _recommendedFor) return;
      setState(
        () => _recommended = [
          for (final p in (photos is List ? photos : const []).whereType<Map>())
            if (p['src'] is Map) ('${(p['src'] as Map)['medium']}', '${(p['src'] as Map)['large2x']}'),
        ],
      );
    } catch (_) {
      if (mounted) setState(() => _recommended = []);
    } finally {
      if (mounted) setState(() => _loadingRecommended = false);
    }
  }

  void _toggleImage(String url) {
    if (_images.contains(url)) return setState(() => _images = [..._images]..remove(url));
    if (_images.length >= _maxImages) {
      return Toast.error('Maximum of $_maxImages images reached. Remove an image to add more.');
    }
    setState(() {
      _images = [..._images, url];
      _error = null;
    });
  }

  void _goTo(int step) {
    setState(() => _step = step);
    if (step == 3) _loadRecommended();
  }

  bool _validate(int step) {
    String? e;
    if (step == 1 && _brandName.text.trim().isEmpty) {
      e = 'Brand name is required.';
    } else if (step == 1 && _mockupType == null) {
      e = 'Please select a mockup type.';
    } else if (step == 2 && _resolution == null) {
      e = 'Please complete all fields before continuing.';
    } else if (step == 3 && _images.isEmpty) {
      e = 'Select at least one background image.';
    }
    setState(() => _error = e);
    return e == null;
  }

  void _continue() {
    if (_validate(_step)) _goTo(_step + 1);
  }

  Future<void> _generate() async {
    // The web only checks this step on "Continue", which the last step never
    // shows; run it before generating so the background step means something.
    if (!_validate(3)) return;
    setState(() => _generating = true);
    String? nn(String s) => s.trim().isEmpty ? null : s.trim();
    final error = await host.generate({
      'creativeType': host.creative.id,
      'categoryType': host.category.id,
      'brandName': nn(_brandName.text),
      'projectName': nn(_projectName.text),
      'tagline': nn(_tagline.text),
      'mockupType': _mockupType,
      'description': nn(_description.text),
      'visualStyle': _visualStyle,
      'brandColor': _primary,
      'primaryColor': _primary,
      'secondaryColor': _secondary,
      'font': _font,
      'logo': _logo,
      'caption': nn(_caption.text),
      'hashtags': _hashtags.text.split(' ').where((h) => h.isNotEmpty).toList(),
      'resolution': _resolution,
      'size': _resolution,
      'fileFormat': _format,
      'campaignGoal': _goal,
      'audience': _audience,
      'count': 4,
      'sourceUrl': nn(_url.text),
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
        StepIndicator(steps: _steps, current: _step, accent: accent, onTap: _goTo),
        if (_error != null) FormErrorBanner(_error!),
        if (_step == 1) _productStep(accent) else if (_step == 2) _formatStep(accent) else _backgroundStep(accent),
        FormNavBar(
          step: _step,
          totalSteps: _steps.length,
          accent: accent,
          generating: _generating,
          onBack: () => _goTo(_step - 1),
          onContinue: _continue,
          onGenerate: _generate,
          generateLabel: 'Generate Mockups',
          generateIcon: LucideIcons.sparkles,
        ),
      ],
    );
  }

  Widget _text(String label, TextEditingController ctrl, Color accent, String hint, {bool required = false}) =>
      FormFieldBlock(
        label: label,
        required: required,
        child: StudioTextField(controller: ctrl, accent: accent, hint: hint, onChanged: (_) => _changed()),
      );

  Widget _productStep(Color accent) {
    final selected = _mockupTypes.where((m) => m.$1 == _mockupType).firstOrNull;
    return FormColumn(
      children: [
        _IconSectionTitle(
          icon: LucideIcons.package,
          accent: accent,
          title: 'Brand & Product',
          subtitle: "Who the brand is and what's going on the packaging.",
        ),
        UrlImportBox(controller: _url, accent: accent, loading: _importing, onImport: _import),
        _Pair(
          _text('Brand Name', _brandName, accent, 'Your Brand', required: true),
          _text('Project Name', _projectName, accent, 'e.g. Summer Skincare Line'),
        ),
        _text('Product Tagline', _tagline, accent, 'e.g. Pure. Natural. Powerful.'),
        // Required in step 1 so it informs the rest; the selected type's
        // description shows on the label row instead of under every chip.
        FormFieldBlock(
          label: 'Packaging / Mockup Type',
          required: true,
          trailing: _Hint(selected?.$3 ?? 'Pick the surface you want mocked up'),
          child: ChipWrap(
            children: [
              for (final (v, label, _, icon) in _mockupTypes)
                OptionChip(
                  label: label,
                  icon: icon,
                  accent: accent,
                  active: _mockupType == v,
                  onTap: () => setState(() {
                    _mockupType = v;
                    _error = null;
                  }),
                ),
            ],
          ),
        ),
        FormFieldBlock(
          label: 'Product / Design Brief',
          child: StudioTextField(
            controller: _description,
            accent: accent,
            hint: 'Describe the product, key design elements, target feel, and any special requirements…',
            maxLines: 4,
            maxLength: 500,
            onInspire: () => setState(() {
              _description.text = pickPrompt(_inspire);
              _error = null;
            }),
            onChanged: (_) => _changed(),
          ),
        ),
        FormFieldBlock(
          label: 'Visual Style',
          child: ChipWrap(
            children: [
              for (final (v, label) in _visualStyles)
                OptionChip(
                  label: label,
                  accent: accent,
                  active: _visualStyle == v,
                  onTap: () => setState(() => _visualStyle = v),
                ),
            ],
          ),
        ),
        FormFieldBlock(
          label: 'Primary Color',
          child: BrandColorField(
            value: _primary,
            presets: _brandColors,
            onChanged: (v) => setState(() => _primary = v),
          ),
        ),
        FormFieldBlock(
          label: 'Secondary Color',
          child: BrandColorField(
            value: _secondary,
            presets: const [],
            onChanged: (v) => setState(() => _secondary = v),
          ),
        ),
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
          label: 'Logo',
          child: LogoField(api: host.api, value: _logo, accent: accent, onChanged: (v) => setState(() => _logo = v)),
        ),
        FormFieldBlock(
          label: 'Caption',
          child: StudioTextField(
            controller: _caption,
            accent: accent,
            hint: 'e.g. New packaging alert! Fresh, bold, and ready to stand out',
            maxLines: 2,
            maxLength: 280,
            onChanged: (_) => _changed(),
          ),
        ),
        _text('Hashtags', _hashtags, accent, '#PackagingDesign #Mockup #Branding'),
      ],
    );
  }

  Widget _formatStep(Color accent) {
    final c = context.colors;
    final selected = _mockupTypes.where((m) => m.$1 == _mockupType).firstOrNull;
    return FormColumn(
      children: [
        _IconSectionTitle(
          icon: LucideIcons.scan,
          accent: accent,
          title: 'Format & Goals',
          subtitle: 'Output size, file type, and who this mockup is aimed at.',
        ),
        FormFieldBlock(
          label: 'Resolution',
          required: true,
          trailing: const _Hint('Digital for social, Print for 300 DPI output'),
          child: FormColumn(
            gap: 12,
            children: [
              for (final group in const ['Digital', 'Print'])
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: c.gray400,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ChipWrap(
                      children: [
                        for (final (v, label, desc, g) in _resolutions)
                          if (g == group)
                            OptionChip(
                              label: label,
                              desc: desc,
                              // Stand-in for the web's AspectGlyph: square vs. landscape.
                              icon: _isSquare(v) ? LucideIcons.square : LucideIcons.rectangleHorizontal,
                              accent: accent,
                              active: _resolution == v,
                              onTap: () => setState(() {
                                _resolution = v;
                                _error = null;
                              }),
                            ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
        FormFieldBlock(
          label: 'File Format',
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
          label: 'Campaign Goal',
          child: ChipWrap(
            children: [
              for (final g in _goals)
                OptionChip(label: g, accent: accent, active: _goal == g, onTap: () => setState(() => _goal = g)),
            ],
          ),
        ),
        FormFieldBlock(
          label: 'Audience',
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
        if (selected != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(10)),
                  child: Icon(selected.$4, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SELECTED MOCKUP',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text('${selected.$2} — ${selected.$3}', style: TextStyle(fontSize: 12.5, color: c.gray700)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _goTo(1),
                  style: TextButton.styleFrom(
                    foregroundColor: accent,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static bool _isSquare(String res) {
    final p = res.split('x');
    return p.length == 2 && p[0] == p[1];
  }

  Widget _backgroundStep(Color accent) {
    final c = context.colors;
    return FormColumn(
      children: [
        _IconSectionTitle(
          icon: LucideIcons.images,
          accent: accent,
          title: 'Background Image',
          subtitle: _resolution != null
              ? 'Optimal: ${_resolution}px'
              : 'Select a resolution in Step 2 for best crop results',
        ),
        if (_importedImages.isNotEmpty)
          _PickStrip(
            label: 'Imported brand images',
            items: [for (final u in _importedImages) (u, u)],
            selected: _images,
            accent: accent,
            onToggle: _toggleImage,
          ),
        _PickStrip(
          label: 'Recommended images',
          loading: _loadingRecommended,
          loadingText: 'Finding images…',
          items: _recommended,
          selected: _images,
          accent: accent,
          onToggle: _toggleImage,
        ),
        FormFieldBlock(
          label: _images.isEmpty ? 'Upload Background' : 'Selected media (${_images.length})',
          child: ImageListField(
            api: host.api,
            images: _images,
            max: _maxImages,
            accent: accent,
            onChanged: (v) => setState(() {
              _images = v;
              _error = null;
            }),
          ),
        ),
        Text(
          'Upload from your phone, or tap an image above to use it.',
          style: TextStyle(fontSize: 11.5, color: c.gray400),
        ),
      ],
    );
  }
}

/// The form's SectionTitle: a tinted icon chip, the heading and a one-line
/// explainer.
class _IconSectionTitle extends StatelessWidget {
  const _IconSectionTitle({required this.icon, required this.accent, required this.title, required this.subtitle});

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 16, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FormSectionTitle(title),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: c.gray400)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Secondary copy on the right of a field's label row (the web's `hint`).
class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.45),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: TextStyle(fontSize: 10.5, color: context.colors.gray400),
    ),
  );
}

/// Two fields side by side when there's room (the web's `sm:grid-cols-2`),
/// stacked on a phone.
class _Pair extends StatelessWidget {
  const _Pair(this.a, this.b);

  final Widget a;
  final Widget b;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) => box.maxWidth >= 480
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          )
        : FormColumn(children: [a, b]),
  );
}

/// A horizontal row of tappable image tiles (thumb, full URL); tapping toggles
/// the full URL in [selected]. Stands in for the web's Imported / Recommended
/// image sections (select, then Apply, then crop).
class _PickStrip extends StatelessWidget {
  const _PickStrip({
    required this.label,
    required this.items,
    required this.selected,
    required this.onToggle,
    required this.accent,
    this.loading = false,
    this.loadingText = 'Loading…',
  });

  final String label;
  final List<(String, String)> items;
  final List<String> selected;
  final ValueChanged<String> onToggle;
  final Color accent;
  final bool loading;
  final String loadingText;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (loading) {
      return Row(
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text(loadingText, style: TextStyle(fontSize: 12, color: c.gray400)),
        ],
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final (thumb, full) = items[i];
              final on = selected.contains(full);
              return GestureDetector(
                onTap: () => onToggle(full),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: on ? accent : c.gray200, width: on ? 2 : 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MediaImage(thumb, cacheWidth: 200),
                      if (on)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                            child: const Icon(LucideIcons.check, size: 11, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
