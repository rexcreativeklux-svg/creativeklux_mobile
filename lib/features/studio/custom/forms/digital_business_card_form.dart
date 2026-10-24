import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../studio_form_kit.dart';

/// Port of `studio/forms/DigitalBusinessCardForm.jsx`:
/// Personal Details → Card Format → Style & Output.
///
/// The web's generate is a placeholder (a Pexels search dressed up as
/// results); here the same fields go to create-design like every other form.
class DigitalBusinessCardForm extends StatefulWidget {
  const DigitalBusinessCardForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  State<DigitalBusinessCardForm> createState() => _DigitalBusinessCardFormState();
}

const _formats = [('PNG', 'Recommended'), ('JPEG', 'Compressed'), ('PDF', 'Print-ready')];

// Dimensions mirror the backend's SIZES['digital_business_cards'] map — it is
// the source of truth.
const _sizes = [
  ('700x400', 'Digital Horizontal', '3.5×2 in · 200 DPI'),
  ('400x700', 'Digital Vertical', '2×3.5 in · 200 DPI'),
  ('1050x600', 'Print Horizontal', '3.5×2 in · 300 DPI'),
  ('600x1050', 'Print Vertical', '2×3.5 in · 300 DPI'),
];

const _orientations = [('Horizontal', LucideIcons.rectangleHorizontal), ('Vertical', LucideIcons.rectangleVertical)];

const _fonts = ['Arial', 'Helvetica', 'Times New Roman', 'Roboto', 'Poppins'];

const _cardStyles = [
  ('minimalist', 'Minimalist', 'Clean, white-space focused'),
  ('bold', 'Bold', 'Strong colors, big type'),
  ('elegant', 'Elegant', 'Refined and luxury feel'),
  ('modern', 'Modern', 'Flat design, sans-serif'),
  ('creative', 'Creative', 'Unique layouts, gradients'),
  ('corporate', 'Corporate', 'Professional and formal'),
];

const _inspire = [
  'A minimalist digital business card for a senior tech consultant',
  'A vibrant business card for a creative agency director with bold typography',
  'A professional business card for a corporate lawyer at a top-tier firm',
  'A modern business card for a startup founder with a clean, fresh design',
  'An elegant business card for a luxury brand manager with gold accents',
  'A sleek card for a product designer at a well-known tech company',
];

const _steps = [
  ('Personal Details', LucideIcons.user),
  ('Card Format', LucideIcons.settings2),
  ('Style & Output', LucideIcons.creditCard),
];

class _DigitalBusinessCardFormState extends State<DigitalBusinessCardForm> {
  StudioFormHost get host => widget.host;

  int _step = 1;
  String? _error;
  bool _generating = false;

  // Personal details
  late final _brandName = TextEditingController(text: host.brandName);
  late final _description = TextEditingController(text: host.brandDescription);
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  late final _company = TextEditingController(text: host.brandName);
  final _website = TextEditingController();
  late String _primary = host.brand?.primaryColor ?? '#000000';
  late String _secondary = host.brand?.secondaryColor ?? '#e11d48';
  late String _font = _brandFont ?? 'Poppins';
  late String? _logo = host.brandLogo;

  String? get _brandFont {
    final f = host.brand?.raw['font'];
    return f is String && f.trim().isNotEmpty ? f : null;
  }

  // Card format
  String _format = 'PNG';
  String _size = '1050x600';
  String _orientation = 'Horizontal';

  // Style & output
  String _cardStyle = 'minimalist';
  int _count = 3;

  @override
  void dispose() {
    for (final c in [_brandName, _description, _name, _title, _email, _phone, _company, _website]) {
      c.dispose();
    }
    super.dispose();
  }

  void _continue() {
    if (_step == 1 && _name.text.trim().isEmpty) return setState(() => _error = 'Please enter a name.');
    if (_step == 1 && _email.text.trim().isEmpty) return setState(() => _error = 'Please enter an email address.');
    if (_step == 1 && _description.text.trim().isEmpty) {
      return setState(() => _error = 'Please enter a card description.');
    }
    if (_step == 2 && _format.isEmpty) return setState(() => _error = 'Please select a file format.');
    if (_step == 2 && _orientation.isEmpty) return setState(() => _error = 'Please select an orientation.');
    setState(() {
      _error = null;
      _step++;
    });
  }

  Future<void> _generate() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) {
      return setState(() => _error = 'Name and email are required.');
    }
    setState(() {
      _error = null;
      _generating = true;
    });
    String? nn(String s) => s.trim().isEmpty ? null : s.trim();
    final error = await host.generate({
      'creativeType': host.creative.id,
      'categoryType': host.category.id,
      'brandName': nn(_brandName.text) ?? nn(_company.text),
      'description': nn(_description.text),
      'name': nn(_name.text),
      'title': nn(_title.text),
      'email': nn(_email.text),
      'phone': nn(_phone.text),
      'company': nn(_company.text),
      'website': nn(_website.text),
      'brandColor': _primary,
      'primaryColor': _primary,
      'secondaryColor': _secondary,
      'font': _font,
      'logo': _logo,
      'fileFormat': _format,
      'size': _size,
      'orientation': _orientation,
      'cardStyle': _cardStyle,
      // The user picks how many cards, so the engine is told too.
      'count': _count,
      'variations': _count,
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
        if (_step == 1) _personalStep(accent) else if (_step == 2) _formatStep(accent) else _styleStep(accent),
        FormNavBar(
          step: _step,
          totalSteps: _steps.length,
          accent: accent,
          generating: _generating,
          onBack: () => setState(() => _step--),
          onContinue: _continue,
          onGenerate: _generate,
          generateLabel: 'Generate Cards',
        ),
      ],
    );
  }

  Widget _text(
    String label,
    TextEditingController ctrl,
    Color accent,
    String hint, {
    bool required = false,
    TextInputType? keyboard,
  }) => FormFieldBlock(
    label: label,
    required: required,
    child: StudioTextField(
      controller: ctrl,
      accent: accent,
      hint: hint,
      keyboardType: keyboard,
      onChanged: required ? (_) => setState(() => _error = null) : null,
    ),
  );

  Widget _personalStep(Color accent) => FormColumn(
    children: [
      const FormSectionTitle('Personal Details'),
      _text('Brand Name', _brandName, accent, 'e.g. Acme Corp'),
      FormFieldBlock(
        label: 'Card Description',
        required: true,
        child: StudioTextField(
          controller: _description,
          accent: accent,
          hint: 'Describe your business card style, industry, and intended use.',
          maxLines: 4,
          maxLength: 300,
          onInspire: () => setState(() {
            _description.text = pickPrompt(_inspire);
            _error = null;
          }),
          onChanged: (_) => setState(() => _error = null),
        ),
      ),
      _Pair(
        _text('Full Name', _name, accent, 'e.g. Jane Smith', required: true),
        _text('Job Title', _title, accent, 'e.g. Senior Product Designer'),
      ),
      _Pair(
        _text('Email', _email, accent, 'e.g. jane@acme.com', required: true, keyboard: TextInputType.emailAddress),
        _text('Phone', _phone, accent, 'e.g. +1 555 000 1234', keyboard: TextInputType.phone),
      ),
      _Pair(
        _text('Company', _company, accent, 'e.g. Acme Corp'),
        _text('Website', _website, accent, 'e.g. https://acme.com', keyboard: TextInputType.url),
      ),
      FormFieldBlock(
        label: 'Primary Color',
        child: BrandColorField(value: _primary, presets: const [], onChanged: (v) => setState(() => _primary = v)),
      ),
      FormFieldBlock(
        label: 'Secondary Color',
        child: BrandColorField(value: _secondary, presets: const [], onChanged: (v) => setState(() => _secondary = v)),
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
    ],
  );

  Widget _formatStep(Color accent) {
    final c = context.colors;
    final small = TextStyle(fontSize: 11.5, color: c.gray500);
    return FormColumn(
      children: [
        const FormSectionTitle('Card Format'),
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
          label: 'Card Size',
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
        _SummaryBox(
          accent: accent,
          title: 'Your Card',
          children: [
            Text(
              [_name.text, if (_title.text.isNotEmpty) '· ${_title.text}'].join(' '),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray700),
            ),
            Text([_email.text, if (_phone.text.isNotEmpty) _phone.text].join(' · '), style: small),
            if (_company.text.isNotEmpty)
              Text([_company.text, if (_website.text.isNotEmpty) _website.text].join(' · '), style: small),
            const SizedBox(height: 6),
            Row(
              children: [
                _Dot(colorOf(_primary)),
                const SizedBox(width: 6),
                _Dot(colorOf(_secondary)),
                const SizedBox(width: 8),
                Text(_font, style: TextStyle(fontSize: 11.5, color: accent)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _styleStep(Color accent) {
    final c = context.colors;
    final style = _cardStyles.firstWhere((s) => s.$1 == _cardStyle).$2;
    final sizeLabel = _sizes.where((s) => s.$1 == _size).firstOrNull?.$2 ?? _size;
    return FormColumn(
      children: [
        const FormSectionTitle('Style & Output'),
        FormFieldBlock(
          label: 'Card Style',
          child: ChipWrap(
            children: [
              for (final (v, label, desc) in _cardStyles)
                OptionChip(
                  label: label,
                  desc: desc,
                  accent: accent,
                  active: _cardStyle == v,
                  onTap: () => setState(() => _cardStyle = v),
                ),
            ],
          ),
        ),
        FormFieldBlock(
          label: 'Card Variations: $_count',
          child: Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: accent,
                  thumbColor: accent,
                  inactiveTrackColor: c.gray200,
                  overlayColor: accent.withValues(alpha: 0.12),
                  showValueIndicator: ShowValueIndicator.never,
                ),
                child: Slider(
                  value: _count.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  onChanged: (v) => setState(() => _count = v.round()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var n = 1; n <= 5; n++)
                      Text(
                        '$n',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: _count == n ? FontWeight.w700 : FontWeight.w400,
                          color: _count == n ? accent : c.gray400,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _SummaryBox(
          accent: accent,
          title: 'Summary',
          children: [
            Text(
              '${_name.text} — ${_title.text.isEmpty ? 'No title' : _title.text}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray700),
            ),
            Text(
              [_email.text, if (_company.text.isNotEmpty) _company.text].join(' · '),
              style: TextStyle(fontSize: 11.5, color: c.gray500),
            ),
            const SizedBox(height: 4),
            Text(
              'Style: $style · $_format · $sizeLabel · $_orientation · $_count variation${_count > 1 ? 's' : ''}',
              style: TextStyle(fontSize: 11.5, color: accent),
            ),
          ],
        ),
      ],
    );
  }
}

/// Two fields side by side when there's room (the web's `grid-cols-2`),
/// stacked on a narrow phone so inputs like email aren't squeezed.
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

/// The tinted "Your Card" / "Summary" recap box.
class _SummaryBox extends StatelessWidget {
  const _SummaryBox({required this.accent, required this.title, required this.children});

  final Color accent;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: accent.withValues(alpha: 0.15)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: accent),
        ),
        const SizedBox(height: 4),
        ...children,
      ],
    ),
  );
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: context.colors.gray200),
    ),
  );
}
