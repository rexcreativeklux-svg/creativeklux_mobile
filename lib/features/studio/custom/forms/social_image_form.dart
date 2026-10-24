import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/ui/toast.dart';
import '../studio_form_kit.dart';
import 'social/kind_fields.dart';
import 'social/social_media_field.dart';
import 'social/social_sizes.dart';

/// Port of `studio/forms/SocialImageForm.jsx`: the Social Creative "Image" tab
/// — every social image, in one form. Details → Size, Goals & Audience →
/// Background Image.
///
/// ⚠️ THE KIND IS A TAG, NOT A ROUTE. Post / banner / thumbnail / meme is chosen
/// INSIDE this form and changes nothing structural. It still has to reach the
/// backend, via `kind.subType` → `categoryType` (create_sub_type); the studio's
/// own category ("image") is deliberately NOT what gets sent.
///
/// ⚠️ THERE IS NO TARGET PLATFORM FIELD. The size presets are platform-named, so
/// the platform comes off the selected size, and sizes that name no platform
/// send none rather than guessing.
class SocialImageForm extends StatefulWidget {
  const SocialImageForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  State<SocialImageForm> createState() => _SocialImageFormState();
}

const _brandColors = ['#2563eb', '#0ea5e9', '#8b5cf6', '#ec4899', '#ef4444'];

const _steps = [
  ('Details', LucideIcons.type),
  ('Size, Goals & Audience', LucideIcons.scan),
  ('Background Image', LucideIcons.images),
];

class _SocialImageFormState extends State<SocialImageForm> {
  StudioFormHost get host => widget.host;

  int _step = 1;
  String? _error;
  bool _generating = false;

  // Details — seeded like the studio page's `formData`.
  late final _name = TextEditingController(text: host.brandName);
  late final _description = TextEditingController(text: host.brandDescription);
  late final _url = TextEditingController(text: host.brandUrl);
  late String _brandColor = host.brand?.primaryColor ?? '#2563eb';
  late String? _logo = host.brandLogo;
  String _font = 'Montserrat';
  late String _caption = host.brand != null ? 'Discover ${host.brandName.isEmpty ? 'our brand' : host.brandName}!' : '';
  List<String> _hashtags = const [];
  List<String> _importedImages = const [];
  bool _importing = false;

  // Kind + its own fields
  SocialKind _kind = socialKindById('post');
  String _tone = 'casual';
  String _cta = 'Download Now';
  String _visualStyle = 'modern';

  // Size, goals & audience. `_sizeLabel` starts unset, as on the web, so the
  // default 1080x1080 resolves to the first preset with that value.
  String _size = '1080x1080';
  String? _sizeLabel;
  String _goal = 'Engagement';
  String _audience = 'B2C';
  String _format = 'PNG';

  // Background images (hosted URLs)
  List<String> _images = const [];

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _url.dispose();
    super.dispose();
  }

  /// The label of the selected size, resolved within the current kind.
  String get _activeSizeLabel =>
      _kind.sizes.where((s) => s.label == _sizeLabel).firstOrNull?.label ??
      _kind.sizes.where((s) => s.value == _size).firstOrNull?.label ??
      '';

  /// The full selected size — where the platform and template category come from.
  SocialSize get _activeSize => socialSizeByLabel(_kind.id, _activeSizeLabel);

  void _selectSize(SocialSize s) => setState(() {
    _size = s.value;
    _sizeLabel = s.label;
    _error = null;
  });

  /// Switch kind.
  ///
  /// ⚠️ EVERY KIND-SCOPED CHOICE IS RE-RESOLVED HERE, not just the size. The
  /// kinds offer different goals, formats and styles; carrying a stale value
  /// across meant nothing showed selected while the old answer was what got
  /// generated. Anything the new kind doesn't offer falls back to its first option.
  void _selectKind(SocialKind next) => setState(() {
    final size = next.sizes.first;
    _kind = next;
    _size = size.value;
    _sizeLabel = size.label;
    if (!next.goals.contains(_goal)) _goal = next.goals.first;
    if (!next.formats.contains(_format)) _format = next.formats.first;
    final styles = next.styles;
    if (styles != null && !styles.any((s) => s.value == _visualStyle)) _visualStyle = styles.first.value;
    _error = null;
  });

  Future<void> _import() async {
    if (_url.text.trim().isEmpty) return setState(() => _error = 'Please enter a valid brand URL.');
    setState(() => _importing = true);
    try {
      final d = await host.api.importBrand(_url.text);
      if (!mounted) return;
      setState(() {
        _name.text = d.name ?? '';
        _description.text = d.description ?? '';
        _brandColor = d.primaryColor ?? '#2563eb';
        _font = 'Montserrat';
        if (_caption.isEmpty) _caption = 'Discover ${d.name}!';
        if (_hashtags.isEmpty) _hashtags = const ['#SocialMedia', '#Brand'];
        _logo = d.logo;
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

  void _continue() {
    if (_step == 1 && _name.text.trim().isEmpty) return setState(() => _error = 'Brand name is required.');
    // Audience is only required where the kind actually asks for one.
    if (_step == 2 && (_size.isEmpty || _goal.isEmpty || (_kind.audience && _audience.isEmpty) || _format.isEmpty)) {
      return setState(() => _error = 'Please complete all fields before continuing.');
    }
    setState(() {
      _error = null;
      _step++;
    });
  }

  Future<void> _generate() async {
    if (_size.isEmpty) {
      final msg = 'Please select a ${_kind.sizeLabel.toLowerCase()}.';
      Toast.error(msg);
      return setState(() => _error = msg);
    }
    // Gate: generation needs at least minImages images selected.
    if (_images.length < minImages) {
      final msg = imageGateMessage(_images.length);
      Toast.error(msg);
      return setState(() => _error = msg);
    }
    setState(() {
      _error = null;
      _generating = true;
    });

    String? nn(String s) => s.trim().isEmpty ? null : s.trim();
    final activeSize = _activeSize;
    final sizeLabel = _activeSizeLabel;
    final templateCategory = activeSize.category;

    final error = await host.generate({
      'creativeType': host.creative.id,
      // ⚠️ THE KIND'S SUB-TYPE, NOT THE TAB — see the class comment.
      'categoryType': _kind.subType,
      'brand_id': host.brand?.id,
      'brandName': nn(_name.text),
      'description': nn(_description.text),
      'brandColor': _brandColor,
      'logo': _logo,
      'visualStyle': _visualStyle,
      'font': _font,
      'sourceUrl': nn(_url.text),
      'size': _size,
      // Which preset that size came from — "Facebook Cover" reads very
      // differently from a bare "851x315".
      'sizeLabel': sizeLabel.isEmpty ? null : sizeLabel,
      'campaignGoal': _goal,
      'audience': _kind.audience ? _audience : null,
      'fileFormat': _format,
      'caption': nn(_caption),
      'hashtags': _hashtags,
      // ⚠️ DERIVED FROM THE SIZE. A list of one (or none), because that is the
      // shape this field has always had and the publish flow reads it as a list.
      'platforms': [?activeSize.platform],
      // Only the fields the selected kind actually shows.
      if (_kind.tone) 'tone': _tone,
      if (_kind.cta) 'cta': nn(_cta),
      // The old thumbnails form sent its platform under this key too; kept so
      // the generator doesn't quietly lose a field it may key on.
      if (_kind.id == 'thumbnail') 'thumbnailPlatform': activeSize.platform,
      'category': templateCategory.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
      'type_size': _size,
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
    // Step 2's heading follows the kind — "& Audience" is a lie on thumbnails.
    final stepTwoTitle = _kind.audience ? 'Size, Goals & Audience' : 'Size, Goals & Format';
    final steps = [('${_kind.label} Details', _steps[0].$2), _steps[1], _steps[2]];

    return FormColumn(
      children: [
        StepIndicator(steps: steps, current: _step, accent: accent, onTap: (s) => setState(() => _step = s)),
        if (_error != null) FormErrorBanner(_error!),
        if (_step == 1)
          FormColumn(
            children: [
              // ── Kind tag ── above the fields because it decides what the rest
              // of the form IS: the sizes, the extra fields, and the sub-type.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormSectionTitle('${_kind.label} Details'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final k in socialKinds)
                        SocialKindTag(
                          label: k.label,
                          active: k.id == _kind.id,
                          accent: accent,
                          onTap: () => _selectKind(k),
                        ),
                    ],
                  ),
                ],
              ),
              UrlImportBox(controller: _url, accent: accent, loading: _importing, onImport: _import),
              FormFieldBlock(
                label: 'Brand Name / Project Name',
                required: true,
                child: StudioTextField(
                  controller: _name,
                  accent: accent,
                  hint: 'Your Brand',
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              FormFieldBlock(
                label: _kind.descLabel,
                child: StudioTextField(
                  controller: _description,
                  accent: accent,
                  hint: _kind.descPlaceholder,
                  maxLines: 3,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              // ⚠️ BRAND COLOUR SITS DIRECTLY UNDER THE DESCRIPTION, above the
              // kind's own fields: that block is a different height per kind, so
              // anything after it would jump around as the tag changes.
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
                child: LogoField(
                  api: host.api,
                  value: _logo,
                  accent: accent,
                  onChanged: (v) => setState(() => _logo = v),
                ),
              ),
              // ── The selected kind's own fields ──
              if (_kind.tone) ToneField(value: _tone, accent: accent, onChanged: (v) => setState(() => _tone = v)),
              if (_kind.cta) CtaField(value: _cta, accent: accent, onChanged: (v) => setState(() => _cta = v)),
              if (_kind.styles != null)
                StyleField(
                  value: _visualStyle,
                  styles: _kind.styles!,
                  accent: accent,
                  onChanged: (v) => setState(() => _visualStyle = v),
                ),
            ],
          )
        else if (_step == 2)
          FormColumn(
            children: [
              FormSectionTitle(stepTwoTitle),
              FormFieldBlock(
                label: _kind.sizeLabel,
                child: SocialChoiceGrid(
                  children: [
                    for (final s in _kind.sizes)
                      OptionChip(
                        label: s.label,
                        desc: s.value,
                        accent: accent,
                        active: _activeSizeLabel == s.label,
                        onTap: () => _selectSize(s),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Campaign Goal',
                child: ChipWrap(
                  children: [
                    for (final g in _kind.goals)
                      OptionChip(
                        label: g,
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
              if (_kind.audience)
                FormFieldBlock(
                  label: 'Audience',
                  child: SocialChoiceGrid(
                    children: [
                      for (final a in socialAudiences)
                        OptionChip(
                          label: a.label,
                          desc: a.desc,
                          accent: accent,
                          active: _audience == a.value,
                          onTap: () => setState(() {
                            _audience = a.value;
                            _error = null;
                          }),
                        ),
                    ],
                  ),
                ),
              FormFieldBlock(
                label: 'File Format',
                child: ChipWrap(
                  children: [
                    for (final f in _kind.formats)
                      OptionChip(
                        label: f == 'PNG' ? '$f ✓' : f,
                        accent: accent,
                        active: _format == f,
                        onTap: () => setState(() {
                          _format = f;
                          _error = null;
                        }),
                      ),
                  ],
                ),
              ),
            ],
          )
        else
          FormColumn(
            gap: 14,
            children: [
              const FormSectionTitle('Select Images'),
              SocialMediaField(
                api: host.api,
                images: _images,
                suggested: _importedImages,
                accent: accent,
                title: 'Upload More Images',
                subtitle: 'Upload from your phone, or pick from your images above',
                onChanged: (v) => setState(() {
                  _images = v;
                  _error = null;
                }),
              ),
              // Image-gate hint — only while below the minimum.
              if (_images.length < minImages)
                Text(
                  'Select at least $minImages images (max $maxImages) to generate.',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.amber500),
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
          generateLabel: _kind.generateLabel,
          generateIcon: LucideIcons.sparkles,
        ),
      ],
    );
  }
}
