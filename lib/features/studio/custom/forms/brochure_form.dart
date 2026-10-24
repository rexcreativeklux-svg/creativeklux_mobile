import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/ui/toast.dart';
import '../studio_form_kit.dart';
import 'designer_shared.dart';

/// Port of `studio/forms/BrochureForm.jsx`: Brand Details → Goals &
/// Formatting → Background Image.
class BrochureForm extends StatefulWidget {
  const BrochureForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  State<BrochureForm> createState() => _BrochureFormState();
}

/// (value, label, desc, fold x positions on a 22-wide panel, dashed = accordion).
const _foldTypes = [
  ('bi_fold', 'Bi-fold', '2 panels, 1 fold', [11.0], false),
  ('tri_fold', 'Tri-fold', '3 panels, 2 folds', [7.7, 14.3], false),
  ('z_fold', 'Z-fold', 'Accordion style', [7.7, 14.3], true),
  ('gate_fold', 'Gate Fold', 'Opens like gates', [5.5, 16.5], false),
];

// Dimensions mirror the backend's SIZES['brochures'] map — it is the source of
// truth (the digital A-series render at 96 DPI there).
const _sizes = [
  ('816x1056', 'Digital Letter', '8.5×11in, 96 DPI', 'Digital'),
  ('794x1123', 'Digital A4', '210×297mm, 96 DPI', 'Digital'),
  ('559x794', 'Digital A5', '148×210mm, 96 DPI', 'Digital'),
  ('2550x3300', 'Print Letter', '8.5×11in, 300 DPI', 'Print'),
  ('2480x3508', 'Print A4', '210×297mm, 300 DPI', 'Print'),
];

const _orientations = [
  ('portrait', 'Portrait', LucideIcons.rectangleVertical),
  ('landscape', 'Landscape', LucideIcons.rectangleHorizontal),
];

const _goals = ['Brand Awareness', 'Engagement', 'Sales', 'Lead Generation', 'Website Traffic'];

const _audiences = [
  ('B2B', 'B2B', 'Business owners, startups, agencies'),
  ('B2C', 'B2C', 'End consumers, everyday users'),
  ('Casual', 'Casual', 'Broad social media audience'),
  ('Inspirational', 'Inspirational', 'Entrepreneurs & creators'),
  ('Sales', 'Sales', 'Hot leads, ad audiences'),
];

const _fileFormats = ['PDF', 'PNG', 'JPEG'];

const _brandColors = ['#7c3aed', '#2563eb', '#059669', '#f59e0b', '#ec4899', '#ef4444'];

const _inspire = [
  'A professional bi-fold brochure for a corporate consulting firm',
  'A vibrant tri-fold brochure for a travel and tourism agency',
  'An elegant digital brochure for a luxury real estate brand',
  'A colorful brochure for a community health and wellness event',
  'A modern tech startup brochure showcasing SaaS products',
  'A restaurant menu brochure with warm tones and food photography',
];

const _steps = [
  ('Brand Details', LucideIcons.bookOpen),
  ('Goals & Formatting', LucideIcons.scan),
  ('Background Image', LucideIcons.images),
];

class _BrochureFormState extends State<BrochureForm> {
  StudioFormHost get host => widget.host;

  int _step = 1;
  String? _error;
  bool _generating = false;

  // Brand details — seeded like the studio page's shared formData.
  late final _name = TextEditingController(text: host.brandName);
  late final _description = TextEditingController(text: host.brandDescription);
  late final _url = TextEditingController(text: host.brandUrl);
  late String _brandColor = host.brand?.primaryColor ?? '#2563eb';
  late String? _logo = host.brandLogo;
  String _font = 'Montserrat';
  String? _foldType;
  bool _importing = false;

  // Goals & formatting — size, orientation start unset; goal / audience /
  // format carry the shared formData defaults.
  String? _size;
  String? _orientation;
  String _goal = 'Engagement';
  String _audience = 'B2C';
  String _fileFormat = 'PNG';

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
        _brandColor = d.primaryColor ?? '#7c3aed';
        _font = 'Arial';
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
    // Goal, audience and format always hold a value (the defaults), so this
    // only fires if that ever changes — kept for parity with the web.
    if (_step == 2 && (_goal.isEmpty || _audience.isEmpty || _fileFormat.isEmpty)) {
      return setState(() => _error = 'Please complete all fields before continuing.');
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
      // Project Name is commented out on the web, so it's always empty.
      'projectName': null,
      'description': nn(_description.text),
      'brandColor': _brandColor,
      'logo': _logo,
      'font': _font,
      'sourceUrl': nn(_url.text),
      'size': _size,
      'orientation': _orientation,
      'campaignGoal': _goal,
      'audience': _audience,
      'fileFormat': _fileFormat,
      // brochure-specific
      'foldType': _foldType,
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
          _brandStep(context, accent)
        else if (_step == 2)
          _goalsStep(context, accent)
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
          generateLabel: 'Generate Brochures',
          generateIcon: LucideIcons.sparkles,
        ),
      ],
    );
  }

  Widget _brandStep(BuildContext context, Color accent) {
    final c = context.colors;
    final selectedFold = _foldTypes.where((f) => f.$1 == _foldType).firstOrNull;
    return FormColumn(
      children: [
        const FormSectionTitle('Brand Details'),
        UrlImportBox(controller: _url, accent: accent, loading: _importing, onImport: _import),
        FormFieldBlock(
          label: 'Brand / Project Name',
          required: true,
          child: StudioTextField(
            controller: _name,
            accent: accent,
            hint: 'Your Brand',
            onChanged: (_) => setState(() => _error = null),
          ),
        ),
        FormFieldBlock(
          label: 'Description',
          child: StudioTextField(
            controller: _description,
            accent: accent,
            hint: 'Describe what this brochure is for — include tone, purpose, key messages, and target readers.',
            maxLines: 4,
            onInspire: () => setState(() {
              _description.text = pickPrompt(_inspire);
              _error = null;
            }),
            onChanged: (_) => setState(() => _error = null),
          ),
        ),
        // The selected fold's description sits on the label row, so the chips
        // stay compact.
        FormFieldBlock(
          label: 'Fold Type',
          trailing: Text(
            selectedFold?.$3 ?? 'How the brochure folds',
            style: TextStyle(fontSize: 10.5, color: c.gray400),
          ),
          child: ChipWrap(
            children: [
              for (final (v, label, _, folds, dashed) in _foldTypes)
                _FoldChip(
                  label: label,
                  folds: folds,
                  dashed: dashed,
                  accent: accent,
                  active: _foldType == v,
                  onTap: () => setState(() {
                    _foldType = v;
                    _error = null;
                  }),
                ),
            ],
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
          label: 'Logo',
          child: LogoField(api: host.api, value: _logo, accent: accent, onChanged: (v) => setState(() => _logo = v)),
        ),
      ],
    );
  }

  Widget _goalsStep(BuildContext context, Color accent) {
    final c = context.colors;
    return FormColumn(
      children: [
        const FormSectionTitle('Goals & Formatting'),
        FormFieldBlock(
          label: 'Brochure Size',
          child: FormColumn(
            gap: 12,
            children: [
              for (final group in const ['Digital', 'Print'])
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: c.gray400),
                    ),
                    const SizedBox(height: 6),
                    ChipWrap(
                      children: [
                        for (final (v, label, desc, type) in _sizes)
                          if (type == group)
                            OptionChip(
                              label: label,
                              desc: desc,
                              accent: accent,
                              active: _size == v,
                              onTap: () => setState(() => _size = v),
                            ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
        FormFieldBlock(
          label: 'Orientation',
          child: ChipWrap(
            children: [
              for (final (v, label, icon) in _orientations)
                OptionChip(
                  label: label,
                  icon: icon,
                  accent: accent,
                  active: _orientation == v,
                  onTap: () => setState(() => _orientation = v),
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
              for (final f in _fileFormats)
                OptionChip(
                  label: f == 'PDF' ? '$f ✓' : f,
                  accent: accent,
                  active: _fileFormat == f,
                  onTap: () => setState(() => _fileFormat = f),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The web's fold-type `<OptionChip glyph>`: a chip led by a panel outline
/// whose inner lines show where the folds sit (dashed for an accordion fold).
/// [OptionChip] only takes an icon or emoji, hence this small sibling.
class _FoldChip extends StatelessWidget {
  const _FoldChip({
    required this.label,
    required this.folds,
    required this.dashed,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final List<double> folds;
  final bool dashed;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = active ? Color.lerp(accent, Colors.black, 0.25)! : c.gray500;
    return Material(
      color: active ? accent.withValues(alpha: 0.07) : c.gray50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: active ? accent : c.gray100, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size(22, 14),
                painter: _FoldGlyphPainter(folds: folds, dashed: dashed, color: ink),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? ink : c.gray600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Port of the web's `FoldGlyph` SVG (22×14 viewBox).
class _FoldGlyphPainter extends CustomPainter {
  const _FoldGlyphPainter({required this.folds, required this.dashed, required this.color});

  final List<double> folds;
  final bool dashed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0.75, 0.75, 20.5, 12.5), const Radius.circular(1.5)),
      outline,
    );
    final line = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (final x in folds) {
      if (!dashed) {
        canvas.drawLine(Offset(x, 1.5), Offset(x, 12.5), line);
        continue;
      }
      // strokeDasharray="2 1.5"
      for (var y = 1.5; y < 12.5; y += 3.5) {
        canvas.drawLine(Offset(x, y), Offset(x, (y + 2).clamp(0, 12.5)), line);
      }
    }
  }

  @override
  bool shouldRepaint(_FoldGlyphPainter old) => old.color != color || old.dashed != dashed || old.folds != folds;
}
