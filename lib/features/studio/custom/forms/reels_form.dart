import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/ui/toast.dart';
import '../studio_form_kit.dart';
import 'social/kind_fields.dart';
import 'social/social_media_field.dart';
import 'social/social_sizes.dart';

/// Port of `studio/forms/ReelsForm.jsx`: the Social Creative "Video" tab.
/// Video Details → Format, Goals & Audience → Media & Assets.
class ReelsForm extends StatefulWidget {
  const ReelsForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  State<ReelsForm> createState() => _ReelsFormState();
}

const _uniqueSizes = [
  ('1080x1920', '9:16 — Reels / TikTok / Shorts / Stories'),
  ('1080x1350', '4:5 — Portrait Feed'),
  ('1080x1080', '1:1 — Square'),
];

const _platforms = [
  ('instagram_reels', 'Instagram Reels'),
  ('tiktok', 'TikTok'),
  ('youtube', 'YouTube Shorts'),
  ('instagram', 'Instagram Stories'),
  ('facebook_reels', 'Facebook Reels'),
  ('snapchat', 'Snapchat'),
];

const _durations = [
  ('15', '15s', 'Stories / quick hook'),
  ('30', '30s', 'Reels / TikTok sweet spot'),
  ('60', '60s', 'Full story arc'),
  ('90', '90s', 'YouTube Shorts max'),
];

const _goals = ['Brand Awareness', 'Engagement', 'Followers', 'Sales', 'Website Traffic'];

const _audiences = [
  ('Gen Z', 'Gen Z', '13–26, TikTok-native'),
  ('Millennials', 'Millennials', '27–42, Instagram-first'),
  ('B2C', 'B2C', 'End consumers'),
  ('B2B', 'B2B', 'Professionals & teams'),
  ('Inspirational', 'Creators', 'Entrepreneurs & influencers'),
];

const _videoStyles = [
  ('trending', 'Trending'),
  ('cinematic', 'Cinematic'),
  ('raw', 'Raw / UGC'),
  ('animated', 'Animated'),
  ('talking_head', 'Talking Head'),
  ('slideshow', 'Slideshow'),
];

const _brandColors = ['#059669', '#0ea5e9', '#8b5cf6', '#ec4899', '#f59e0b'];

const _videoFormats = ['MP4', 'MOV', 'WEBM'];

const _steps = [
  ('Video Details', LucideIcons.film),
  ('Format, Goals & Audience', LucideIcons.scan),
  ('Media & Assets', LucideIcons.images),
];

class _ReelsFormState extends State<ReelsForm> {
  StudioFormHost get host => widget.host;

  int _step = 1;
  String? _error;
  bool _generating = false;

  // Video details — seeded like the studio page's `formData`.
  late final _name = TextEditingController(text: host.brandName);
  late final _description = TextEditingController(text: host.brandDescription);
  late final _url = TextEditingController(text: host.brandUrl);
  late String _brandColor = host.brand?.primaryColor ?? '#2563eb';
  late String? _logo = host.brandLogo;
  String _font = 'Montserrat';
  late String _caption = host.brand != null ? 'Discover ${host.brandName.isEmpty ? 'our brand' : host.brandName}!' : '';
  List<String> _hashtags = const [];
  List<String> _importedImages = const [];
  String _videoStyle = 'cinematic';

  // ⚠️ A LIST, AND IT HAS TO BE. The web once seeded this as the string
  // "instagram", which crashed the multi-select toggle.
  List<String> _platformsSel = const [];
  bool _importing = false;

  // Format, goals & audience. Duration starts unpicked, as on the web.
  String _duration = '';
  String _size = '1080x1080';
  String _goal = 'Engagement';
  String _audience = 'B2C';
  String _videoFormat = 'MP4';

  // Media (hosted URLs)
  List<String> _images = const [];

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _url.dispose();
    super.dispose();
  }

  void _fail(String msg) {
    setState(() => _error = msg);
    Toast.error(msg);
  }

  void _togglePlatform(String v) => setState(() {
    final next = [..._platformsSel];
    if (!next.remove(v)) next.add(v);
    _platformsSel = next;
    _error = null;
  });

  Future<void> _import() async {
    if (_url.text.trim().isEmpty) return _fail('Please enter a valid brand URL.');
    setState(() => _importing = true);
    try {
      final d = await host.api.importBrand(_url.text);
      if (!mounted) return;
      setState(() {
        _name.text = d.name ?? '';
        _description.text = d.description ?? '';
        _brandColor = d.primaryColor ?? '#059669';
        _font = 'Montserrat';
        if (_caption.isEmpty) _caption = 'Watch ${d.name}!';
        if (_hashtags.isEmpty) _hashtags = const ['#Reels', '#Shorts', '#TikTok'];
        _logo = d.logo;
        _importedImages = d.images;
        _error = null;
      });
      Toast.success('Brand imported!');
    } catch (_) {
      if (mounted) _fail('Failed to import brand. Check the URL.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _continue() {
    if (_step == 1 && _name.text.trim().isEmpty) return _fail('Brand name is required.');
    if (_step == 2 && (_size.isEmpty || _goal.isEmpty || _audience.isEmpty)) {
      return _fail('Please complete all fields before continuing.');
    }
    setState(() {
      _error = null;
      _step++;
    });
  }

  Future<void> _generate() async {
    // Gate: generation needs between minImages and maxImages media items.
    final bounds = imageBoundsMessage(_images.length);
    if (bounds != null) return _fail(bounds);
    setState(() {
      _error = null;
      _generating = true;
    });

    String? nn(String s) => s.trim().isEmpty ? null : s.trim();
    // Size label → Scraive category, as the web derives it.
    final sizeLabel = _uniqueSizes.where((s) => s.$1 == _size).firstOrNull?.$2 ?? _size;

    final error = await host.generate({
      'creativeType': host.creative.id,
      'categoryType': host.category.id,
      'brand_id': host.brand?.id,
      'brandName': nn(_name.text),
      'description': nn(_description.text),
      'brandColor': _brandColor,
      'logo': _logo,
      'videoStyle': _videoStyle,
      // The Opening Hook field is commented out on the web, so this is always empty.
      'hook': null,
      'font': _font,
      'sourceUrl': nn(_url.text),
      'size': nn(_size),
      'duration': nn(_duration),
      'campaignGoal': _goal,
      'audience': _audience,
      'videoFormat': _videoFormat,
      'caption': nn(_caption),
      'hashtags': _hashtags,
      // ⚠️ A LIST — the backend and the publish flow read it as one.
      'platforms': _platformsSel,
      'musicVibe': null,
      'subtitles': null,
      'category': sizeLabel.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
      'type_size': nn(_size),
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
    final c = context.colors;
    return FormColumn(
      children: [
        StepIndicator(steps: _steps, current: _step, accent: accent, onTap: (s) => setState(() => _step = s)),
        if (_error != null) FormErrorBanner(_error!),
        if (_step == 1)
          FormColumn(
            children: [
              const FormSectionTitle('Video Details'),
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
                label: 'Video Script / Description',
                child: StudioTextField(
                  controller: _description,
                  accent: accent,
                  hint:
                      'Describe your reel or paste a script. What story do you want to tell? '
                      'What should happen scene by scene?',
                  maxLines: 4,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              FormFieldBlock(
                label: 'Video Style',
                child: ChipWrap(
                  children: [
                    for (final (v, label) in _videoStyles)
                      OptionChip(
                        label: label,
                        accent: accent,
                        active: _videoStyle == v,
                        onTap: () => setState(() => _videoStyle = v),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Target Platforms',
                child: ChipWrap(
                  children: [
                    for (final (v, label) in _platforms)
                      OptionChip(
                        label: label,
                        accent: accent,
                        active: _platformsSel.contains(v),
                        onTap: () => _togglePlatform(v),
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
                label: 'Logo / Watermark',
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
              const FormSectionTitle('Format, Goals & Audience'),
              FormFieldBlock(
                label: 'Video Duration',
                child: SocialChoiceGrid(
                  children: [
                    for (final (v, label, desc) in _durations)
                      OptionChip(
                        label: label,
                        desc: desc,
                        accent: accent,
                        active: _duration == v,
                        onTap: () => setState(() {
                          _duration = v;
                          _error = null;
                        }),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Aspect Ratio / Size',
                // One per row: the labels are long ("9:16 — Reels / TikTok / …").
                child: SocialChoiceGrid(
                  columns: 1,
                  children: [
                    for (final (v, label) in _uniqueSizes)
                      OptionChip(
                        label: label,
                        desc: v,
                        accent: accent,
                        active: _size == v,
                        onTap: () => setState(() {
                          _size = v;
                          _error = null;
                        }),
                      ),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Campaign Goal',
                child: ChipWrap(
                  children: [
                    for (final g in _goals)
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
              FormFieldBlock(
                label: 'Audience',
                child: SocialChoiceGrid(
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
                label: 'Export Format',
                child: ChipWrap(
                  children: [
                    for (final f in _videoFormats)
                      OptionChip(
                        label: f == 'MP4' ? '$f ✓' : f,
                        accent: accent,
                        active: _videoFormat == f,
                        onTap: () => setState(() {
                          _videoFormat = f;
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
            gap: 12,
            children: [
              const FormSectionTitle('Media & Assets'),
              Text(
                'Add images to compose your reel. Images will be used as slides.',
                style: TextStyle(fontSize: 12, color: c.gray400),
              ),
              SocialMediaField(
                api: host.api,
                images: _images,
                suggested: _importedImages,
                accent: accent,
                icon: LucideIcons.film,
                title: 'Upload Images',
                subtitle: 'Images will become slides · Max $maxImages assets',
                onChanged: (v) => setState(() {
                  _images = v;
                  _error = null;
                }),
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
          generateLabel: 'Generate Reels',
          generateIcon: LucideIcons.sparkles,
        ),
      ],
    );
  }
}
