import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/ui/toast.dart';
import '../studio_form_kit.dart';
import 'designer_shared.dart';

/// Port of `studio/forms/BusinessCardForm.jsx`: Brand & Contact → Style &
/// Layout → Reference Images.
class BusinessCardForm extends StatefulWidget {
  const BusinessCardForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  State<BusinessCardForm> createState() => _BusinessCardFormState();
}

/// The web's THEME — the import falls back to it when a site has no colour.
const _theme = '#7c3aed';

// Dimensions mirror the backend's SIZES['business_cards'] map — it is the
// source of truth. The physical size stays in `desc`, since inches and
// millimetres are what people think in for a card.
//
// ⚠️ Mini reads oddly on purpose: 825×330 is the backend's value (2.75 × 1.1 in
// at 300 DPI).
const _cardSizes = [
  ('1050x600', 'Standard US', '3.5 × 2 in · 1050 × 600 px'),
  ('1004x650', 'Standard EU', '85 × 55 mm · 1004 × 650 px'),
  ('825x330', 'Mini', '2.75 × 1.1 in · 825 × 330 px'),
  ('750x750', 'Square', '2.5 × 2.5 in · 750 × 750 px'),
];

const _cardLayouts = [
  ('horizontal', 'Horizontal', 'Classic landscape'),
  ('vertical', 'Vertical', 'Portrait orientation'),
  ('folded', 'Folded', 'Double-sided fold'),
  ('square', 'Square', 'Equal dimensions'),
];

const _visualStyles = [
  ('minimal', 'Minimal'),
  ('bold', 'Bold'),
  ('elegant', 'Elegant'),
  ('corporate', 'Corporate'),
  ('creative', 'Creative'),
  ('luxury', 'Luxury'),
  ('modern', 'Modern'),
  ('retro', 'Retro'),
];

const _finishes = [
  ('matte', 'Matte', 'Smooth, non-reflective'),
  ('glossy', 'Glossy', 'Shiny finish'),
  ('soft_touch', 'Soft Touch', 'Velvet-like texture'),
  ('spot_uv', 'Spot UV', 'Selective gloss coating'),
];

const _fileFormats = ['PDF', 'PNG', 'JPEG', 'WEBP'];

const _brandColors = ['#7c3aed', '#2563eb', '#059669', '#db2777', '#ef4444', '#f59e0b'];

const _steps = [
  ('Brand & Contact', LucideIcons.creditCard),
  ('Style & Layout', LucideIcons.palette),
  ('Reference Images', LucideIcons.images),
];

class _BusinessCardFormState extends State<BusinessCardForm> {
  StudioFormHost get host => widget.host;

  int _step = 1;
  String? _error;
  bool _generating = false;

  // Brand & contact — seeded like the studio page's shared formData.
  late final _name = TextEditingController(text: host.brandName);
  final _contactName = TextEditingController();
  final _jobTitle = TextEditingController();
  final _department = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _website = TextEditingController();
  final _address = TextEditingController();
  late final _description = TextEditingController(text: host.brandDescription);
  late final _url = TextEditingController(text: host.brandUrl);
  late String _brandColor = host.brand?.primaryColor ?? '#2563eb';
  late String? _logo = host.brandLogo;
  String _font = 'Montserrat';
  bool _importing = false;

  // Style & layout — size and orientation start unpicked, as on the web.
  String? _cardSize;
  String? _cardLayout;
  String _visualStyle = 'modern';
  String? _finish;
  String _fileFormat = 'PNG';

  // Reference images (hosted URLs).
  List<String> _images = [];

  @override
  void dispose() {
    for (final c in [
      _name,
      _contactName,
      _jobTitle,
      _department,
      _email,
      _phone,
      _website,
      _address,
      _description,
      _url,
    ]) {
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
        // The web fills Website from the import's `url`; the import here doesn't
        // carry it (nor email / phone), so the address that was imported stands in.
        _website.text = _url.text.trim();
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
    if (_step == 1 && _contactName.text.trim().isEmpty) {
      return setState(() => _error = 'Contact name is required.');
    }
    if (_step == 2 && (_cardSize == null || _cardLayout == null)) {
      return setState(() => _error = 'Please select a card size, layout, and visual style.');
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
    String? nn(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final error = await host.generate({
      'creativeType': host.creative.id,
      'categoryType': host.category.id,
      'brandName': nn(_name),
      'contactName': nn(_contactName),
      'jobTitle': nn(_jobTitle),
      'department': nn(_department),
      'email': nn(_email),
      'phone': nn(_phone),
      'website': nn(_website),
      'address': nn(_address),
      'tagline': null,
      'description': nn(_description),
      'brandColor': _brandColor,
      'logo': _logo,
      'visualStyle': _visualStyle,
      'font': _font,
      'cardSize': _cardSize,
      'cardLayout': _cardLayout,
      'finish': _finish,
      'fileFormat': _fileFormat,
      'cardNotes': null,
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
              const FormSectionTitle('Brand & Contact Details'),
              UrlImportBox(controller: _url, accent: accent, loading: _importing, onImport: _import),
              FieldPair(
                left: _text('Brand / Company Name', _name, 'Acme Corp', required: true),
                right: _text('Contact Name', _contactName, 'Jane Doe', required: true),
              ),
              FieldPair(
                left: _text('Job Title', _jobTitle, 'Creative Director'),
                right: _text('Department', _department, 'Marketing'),
              ),
              FieldPair(
                left: _text('Email', _email, 'hello@acme.com', type: TextInputType.emailAddress),
                right: _text('Phone', _phone, '+1 (555) 000-0000', type: TextInputType.phone),
              ),
              FieldPair(
                left: _text('Website', _website, 'www.acme.com', type: TextInputType.url),
                right: _text('Address', _address, '123 Main St, City', type: TextInputType.streetAddress),
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
          FormColumn(
            children: [
              const FormSectionTitle('Style & Layout'),
              FormFieldBlock(
                label: 'Card Size',
                required: true,
                child: ChipWrap(
                  children: [
                    for (final (v, label, desc) in _cardSizes)
                      OptionChip(
                        label: label,
                        desc: desc,
                        accent: accent,
                        active: _cardSize == v,
                        onTap: () => setState(() {
                          _cardSize = v;
                          _error = null;
                        }),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Card Orientation',
                required: true,
                child: ChipWrap(
                  children: [
                    for (final (v, label, desc) in _cardLayouts)
                      OptionChip(
                        label: label,
                        desc: desc,
                        accent: accent,
                        active: _cardLayout == v,
                        onTap: () => setState(() {
                          _cardLayout = v;
                          _error = null;
                        }),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Visual Style',
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
                          _error = null;
                        }),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Print Finish',
                child: ChipWrap(
                  children: [
                    for (final (v, label, desc) in _finishes)
                      OptionChip(
                        label: label,
                        desc: desc,
                        accent: accent,
                        active: _finish == v,
                        onTap: () => setState(() => _finish = v),
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
                        label: f == 'PDF' ? '$f ✓' : f,
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
            zoneTitle: 'Upload or Search Reference Images',
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
          generateLabel: 'Generate Cards',
          generateIcon: LucideIcons.sparkles,
        ),
      ],
    );
  }
}
