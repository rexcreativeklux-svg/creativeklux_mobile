import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/ui/toast.dart';
import '../studio_form_kit.dart';
import 'image_ads_form.dart'
    show
        AdsMediaItem,
        AdsMediaStep,
        adsAudiences,
        adsBrandColors,
        adsCampaignGoals,
        adsImageGateMessage,
        adsMaxImages,
        adsMinImages;

/// Port of `studio/forms/VideoAdsForm.jsx`: Brand & Script → Size, Goals &
/// Audience → Background Media.
class VideoAdsForm extends StatefulWidget {
  const VideoAdsForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  State<VideoAdsForm> createState() => _VideoAdsFormState();
}

// Dimensions mirror the backend's SIZES['video'] map exactly — it is the source
// of truth for every size both sides carry.
//
// ⚠️ TWO PRESETS SHARE 1080x1920 (TikTok / Reels and Stories), exactly as they do
// on the backend. The LABEL is therefore this list's identity, not the value.
const _sizes = [
  ('1080x1920', 'TikTok / Reels'),
  ('1080x1080', 'Meta Square'),
  ('1080x1350', 'Meta Vertical'),
  ('1920x1080', 'YouTube / Landscape'),
  ('1200x628', 'Google Display'),
  ('1200x627', 'LinkedIn'),
  ('1080x1920', 'Stories'),
  ('1280x720', 'Pre-roll'),
];

const _videoTypes = [
  ('Reels', '15–90s looping'),
  ('Shorts', 'Up to 60s'),
  ('Pre-roll', '5–15s skippable'),
  ('Story', 'Up to 15s'),
  ('Long-form', '60s+'),
];

const _videoFormats = ['MP4', 'MOV'];

const _visualStyles = [
  ('minimal', 'Minimal'),
  ('bold', 'Bold'),
  ('elegant', 'Elegant'),
  ('playful', 'Playful'),
  ('corporate', 'Corporate'),
  ('modern', 'Modern'),
  ('luxury', 'Luxury'),
  ('cinematic', 'Cinematic'),
];

const _steps = [
  ('Brand & Script', LucideIcons.video),
  ('Size, Goals & Audience', LucideIcons.scan),
  ('Background Media', LucideIcons.film),
];

class _VideoAdsFormState extends State<VideoAdsForm> {
  StudioFormHost get host => widget.host;

  int _step = 1;
  String? _error;
  bool _generating = false;

  // Brand & script — seeded the way studio/page.jsx seeds `formData`.
  late final _name = TextEditingController(text: host.brandName);
  late final _description = TextEditingController(text: host.brandDescription);
  late final _url = TextEditingController(text: host.brandUrl);
  late String _brandColor = host.brand?.primaryColor ?? '#2563eb';
  late String? _logo = host.brandLogo;
  late String _caption = host.brand != null ? 'Discover ${host.brandName.isEmpty ? 'our brand' : host.brandName}!' : '';
  String _videoType = 'Reels';
  String _visualStyle = 'modern';
  final String _font = 'Montserrat';
  List<String> _importedImages = const [];
  bool _importing = false;

  // Size, goals & audience. The web defaults `size` to 1080x1080 without
  // lighting a chip; we light the matching one (Meta Square) — same payload.
  String _size = '1080x1080';
  String _sizeLabel = 'Meta Square';
  String _goal = 'Engagement';
  String _audience = 'B2C';
  String _videoFormat = 'MP4';

  // Background media
  List<AdsMediaItem> _media = const [];

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

  /// "Inspire Me" — a script written for the chosen goal, not a random pick.
  void _inspire() {
    final brand = _name.text.trim().isNotEmpty ? _name.text.trim() : 'your brand';
    final type = _videoType;
    final audience = _audience;
    final scripts = {
      'Sales':
          "Open with a bold close-up of $brand's hero product. Quick cuts showing key features. Flash \"Limited Offer\" in bold text. Countdown timer overlay. End with strong CTA \"Shop Now\" with a swipe-up link. $type format, high energy, direct tone.",
      'Brand Awareness':
          'Cinematic slow-motion shots of $brand in premium lifestyle settings. Soft music, elegant text overlays. Subtle logo reveal at the end. $type style, aspirational and polished, perfect for $audience audience.',
      'Engagement':
          'Trending audio hook in first 2 seconds. Show $brand in a relatable, fun situation. Text overlay asks a question to prompt comments. End with branded hashtag challenge. $type format, casual and shareable.',
      'Lead Generation':
          'Problem-solution format: show a pain point in 3 seconds, reveal $brand as the fix. Overlay "Get Your Free Guide" with arrow animation pointing to link. $type style, clear and persuasive.',
      'Website Traffic':
          'Fast-paced product tour of $brand with benefit callouts. Final screen: animated "Learn More" button. $type format, 15–30s, direct and clickable.',
    };
    setState(() {
      _description.text = scripts[_goal] ?? scripts['Engagement']!;
      _error = null;
    });
  }

  Future<void> _import() async {
    if (_url.text.trim().isEmpty) return _fail('Please enter a valid brand URL.');
    setState(() => _importing = true);
    try {
      final d = await host.api.importBrand(_url.text);
      if (!mounted) return;
      // Use the scraped value if present, else keep what the user already had.
      setState(() {
        if (d.name != null) _name.text = d.name!;
        if (d.description != null) _description.text = d.description!;
        if (d.primaryColor != null) _brandColor = d.primaryColor!;
        if (d.logo != null) _logo = d.logo;
        if (d.name != null) _caption = 'Discover ${d.name}!';
        if (d.images.isNotEmpty) _importedImages = d.images.where((u) => u.startsWith('http')).toList();
        _error = null;
      });
      Toast.success('Brand imported!');
    } catch (e) {
      final msg = '$e'.replaceFirst('Exception: ', '');
      if (mounted) _fail(msg.isEmpty ? 'Failed to import brand. Check the URL.' : msg);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _continue() {
    if (_step == 1 && (_name.text.trim().isEmpty || _description.text.trim().isEmpty)) {
      return _fail('Brand name and description are required.');
    }
    setState(() {
      _error = null;
      _step++;
    });
  }

  Future<void> _generate() async {
    // Gate: generation needs at least adsMinImages media items selected.
    if (_media.length < adsMinImages) return _fail(adsImageGateMessage(_media.length));
    setState(() {
      _error = null;
      _generating = true;
    });
    String? nn(String s) => s.trim().isEmpty ? null : s.trim();
    final error = await host.generate({
      'creativeType': host.creative.id,
      'categoryType': host.category.id,
      'brand_id': host.brand?.id,
      'brandName': nn(_name.text),
      'description': nn(_description.text),
      'brandColor': _brandColor,
      'logo': _logo,
      'visualStyle': _visualStyle,
      'font': _font,
      'sourceUrl': nn(_url.text),
      'size': _size,
      'campaignGoal': _goal,
      'audience': _audience,
      'videoFormat': _videoFormat,
      'videoType': _videoType,
      'caption': nn(_caption),
      // Hosted URLs of every picked image AND video, as the web sends them.
      'images': [for (final m in _media) m.url],
      // The label, not the value, names the category: Stories and TikTok /
      // Reels share 1080x1920.
      'category': _sizeLabel.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
      'type_size': _size,
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
              const FormSectionTitle('Brand & Script'),
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
                  hint: "Describe your video (e.g., 'Open with close-up of product, bold text overlay, end with CTA…')",
                  maxLines: 4,
                  onInspire: _inspire,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              FormFieldBlock(
                label: 'Video Type',
                child: ChipWrap(
                  children: [
                    for (final (t, desc) in _videoTypes)
                      OptionChip(
                        label: t,
                        desc: desc,
                        accent: accent,
                        active: _videoType == t,
                        onTap: () => setState(() => _videoType = t),
                      ),
                  ],
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
                label: 'Brand Color',
                child: BrandColorField(
                  value: _brandColor,
                  presets: adsBrandColors,
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
              const FormSectionTitle('Size, Goals & Audience'),
              FormFieldBlock(
                label: 'Video Size',
                child: ChipWrap(
                  children: [
                    for (final (value, label) in _sizes)
                      OptionChip(
                        label: label,
                        desc: value,
                        accent: accent,
                        // Matched on label, not value: TikTok / Reels and
                        // Stories are both 1080x1920.
                        active: _sizeLabel == label,
                        onTap: () => setState(() {
                          _size = value;
                          _sizeLabel = label;
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
                    for (final g in adsCampaignGoals)
                      OptionChip(label: g, accent: accent, active: _goal == g, onTap: () => setState(() => _goal = g)),
                  ],
                ),
              ),
              FormFieldBlock(
                label: 'Audience',
                child: ChipWrap(
                  children: [
                    for (final (a, desc) in adsAudiences)
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
              FormFieldBlock(
                label: 'Video Format',
                child: ChipWrap(
                  children: [
                    for (final f in _videoFormats)
                      OptionChip(
                        label: f == 'MP4' ? '$f ✓' : f,
                        accent: accent,
                        active: _videoFormat == f,
                        onTap: () => setState(() => _videoFormat = f),
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
              const FormSectionTitle('Select Background Media'),
              AdsMediaStep(
                host: host,
                items: _media,
                importedImages: _importedImages,
                searchSeed: _name.text,
                allowVideo: true,
                onChanged: (m) => setState(() {
                  _media = m;
                  _error = null;
                }),
                zoneTitle: 'Upload or Search Background Media',
                zoneHint: 'Images or videos — from your library, web search, or your phone',
                zoneIcon: LucideIcons.film,
                buttonIcon: LucideIcons.film,
              ),
              // Image-gate hint — only while below the minimum.
              if (_media.length < adsMinImages)
                Text(
                  'Select at least $adsMinImages media items (max $adsMaxImages) to generate.',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: Color.lerp(AppColors.amber500, c.gray900, 0.2)),
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
          generateLabel: 'Generate Video Ads',
          generateIcon: LucideIcons.film,
        ),
      ],
    );
  }
}
