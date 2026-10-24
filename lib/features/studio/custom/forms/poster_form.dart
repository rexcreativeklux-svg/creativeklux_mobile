import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/ui/media.dart';
import '../../../../core/ui/toast.dart';
import '../../../auth/auth_controller.dart';
import '../../../editor/editor_api.dart';
import '../studio_form_kit.dart';

/// Port of `studio/forms/PosterForm.jsx`: Brand Details → Goals & Format → Images.
class PosterForm extends StatefulWidget {
  const PosterForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  State<PosterForm> createState() => _PosterFormState();
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

const _formats = [('PNG', 'Transparent BG'), ('PDF', 'Print-ready'), ('JPEG', 'Compressed')];

// Dimensions mirror the backend's SIZES['posters'] map — it is the source of
// truth (the web once labelled an A4 page "Digital A3").
const _sizes = [
  ('816x1056', 'Digital Letter', '8.5×11 in · 96 DPI'),
  ('1123x1587', 'Digital A3', '297×420 mm · 96 DPI'),
  ('5400x7200', 'Print Poster', '18×24 in · 300 DPI'),
  ('3508x4961', 'Print A3', '297×420 mm · 300 DPI'),
  ('1056x1632', 'Digital Tabloid', '11×17 in · 96 DPI'),
];

const _orientations = [('Portrait', LucideIcons.rectangleVertical), ('Landscape', LucideIcons.rectangleHorizontal)];

const _inspire = [
  'A vibrant concert poster for a summer music festival with bold neon typography',
  'A minimalist poster for a modern tech conference with clean geometric shapes',
  'An elegant art exhibition poster featuring abstract watercolor elements',
  'A bold sports event poster with dynamic motion blur and strong colors',
  'A professional corporate seminar poster with a premium and refined feel',
  'A retro-style film festival poster inspired by vintage movie art',
];

const _steps = [
  ('Brand Details', LucideIcons.image),
  ('Goals & Format', LucideIcons.target),
  ('Images', LucideIcons.layoutTemplate),
];

/// BrandImagesStrip's hard cap on selected images.
const _maxImages = 5;

class _PosterFormState extends State<PosterForm> {
  StudioFormHost get host => widget.host;

  int _step = 1;
  String? _error;
  bool _generating = false;

  // Brand details
  late final _name = TextEditingController(text: host.brandName);
  late final _description = TextEditingController(text: host.brandDescription);
  late final _url = TextEditingController(text: host.brandUrl);
  late String _brandColor = host.brand?.primaryColor ?? '#7c3aed';
  late String? _logo = host.brandLogo;
  bool _importing = false;

  // Not shown on the form, but the web sends them: projectName starts as the
  // brand name, font comes from the brand, caption/hashtags are fixed seeds.
  late final String _projectName = host.brandName;
  late String _font = _brandFont ?? 'Inter';
  late final String _caption = 'Check out ${host.brandName.isEmpty ? 'our brand' : host.brandName}!';
  static const _hashtags = '#Poster #Design #Brand';

  String? get _brandFont {
    final f = host.brand?.raw['font'];
    return f is String && f.trim().isNotEmpty ? f : null;
  }

  // Goals & format
  String _goal = 'Brand Awareness';
  String _audience = 'B2C';
  String _format = 'PNG';
  String _size = '816x1056';
  String _orientation = 'Portrait';

  // Images — hosted URLs (uploads go to the gallery first).
  List<String> _images = [];

  // "Your brand images": the first 8 images of the user's gallery, as the web's
  // BrandImagesStrip shows. Loaded the first time step 3 opens.
  List<GalleryItem>? _gallery;
  bool _galleryLoading = false;

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
        _brandColor = d.primaryColor ?? '#7c3aed';
        // The import never returns a font, so this is the web's fallback.
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

  Future<void> _loadGallery() async {
    if (_gallery != null || _galleryLoading) return;
    setState(() => _galleryLoading = true);
    final (items, _) = await EditorApi(context.read<AuthController>().api).gallery();
    if (!mounted) return;
    setState(() {
      _gallery = items.take(8).toList();
      _galleryLoading = false;
    });
  }

  void _toggleImage(String url) {
    if (_images.contains(url)) return setState(() => _images = [..._images]..remove(url));
    if (_images.length >= _maxImages) {
      return Toast.error('Maximum of $_maxImages images reached. Remove an image to add more.');
    }
    setState(() => _images = [..._images, url]);
  }

  void _goTo(int step) {
    setState(() => _step = step);
    if (step == 3) _loadGallery();
  }

  void _continue() {
    if (_step == 1 && _name.text.trim().isEmpty) return setState(() => _error = 'Please enter a brand name.');
    if (_step == 1 && _description.text.trim().isEmpty) {
      return setState(() => _error = 'Please enter a poster description.');
    }
    setState(() => _error = null);
    _goTo(_step + 1);
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
      'projectName': nn(_projectName),
      'description': nn(_description.text),
      'brandColor': _brandColor,
      'primaryColor': _brandColor,
      'font': _font,
      'logo': _logo,
      'caption': _caption,
      'hashtags': _hashtags,
      'campaignGoal': _goal,
      'audience': _audience,
      'fileFormat': _format,
      'size': _size,
      'orientation': _orientation,
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
        if (_step == 1) _brandStep(accent) else if (_step == 2) _goalsStep(accent) else _imagesStep(accent),
        FormNavBar(
          step: _step,
          totalSteps: _steps.length,
          accent: accent,
          generating: _generating,
          onBack: () => _goTo(_step - 1),
          onContinue: _continue,
          onGenerate: _generate,
          generateLabel: 'Generate Posters',
        ),
      ],
    );
  }

  Widget _brandStep(Color accent) => FormColumn(
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
        label: 'Poster Description',
        required: true,
        child: StudioTextField(
          controller: _description,
          accent: accent,
          hint: 'Describe your poster… event name, headline message, mood, key details.',
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
        child: LogoField(api: host.api, value: _logo, accent: accent, onChanged: (v) => setState(() => _logo = v)),
      ),
    ],
  );

  Widget _goalsStep(Color accent) => FormColumn(
    children: [
      const FormSectionTitle('Goals & Format'),
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
        label: 'Poster Size',
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
    ],
  );

  Widget _imagesStep(Color accent) {
    final c = context.colors;
    return FormColumn(
      children: [
        const FormSectionTitle('Images'),
        _PickStrip(
          label: 'Your brand images',
          loading: _galleryLoading,
          loadingText: 'Loading your images…',
          items: [for (final g in _gallery ?? const <GalleryItem>[]) (g.src, g.src)],
          selected: _images,
          accent: accent,
          onToggle: _toggleImage,
        ),
        FormFieldBlock(
          label: _images.isEmpty ? 'Upload Images' : 'Selected (${_images.length})',
          child: ImageListField(
            api: host.api,
            images: _images,
            max: _maxImages,
            accent: accent,
            onChanged: (v) => setState(() => _images = v),
          ),
        ),
        Text(
          'Upload from your phone, or tap your brand images above to add them.',
          style: TextStyle(fontSize: 11.5, color: c.gray400),
        ),
      ],
    );
  }
}

/// A horizontal row of tappable image tiles (thumb, full URL). Tapping toggles
/// the full URL in [selected] — the phone stand-in for the web's
/// BrandImagesStrip (select / quick-crop on hover).
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
