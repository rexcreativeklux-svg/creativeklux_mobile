import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../../core/config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/ui/media.dart';
import '../../../../core/ui/toast.dart';
import '../../../auth/auth_controller.dart';
import '../../../editor/editor_api.dart';
import '../studio_form_kit.dart';

/// Port of `studio/forms/ImageAdsForm.jsx`: Brand Details → Size, Goals &
/// Audience → Background Image.
class ImageAdsForm extends StatefulWidget {
  const ImageAdsForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  State<ImageAdsForm> createState() => _ImageAdsFormState();
}

// Dimensions mirror the backend's SIZES['image'] map exactly. The backend is the
// source of truth for every size both sides carry — where these drifted apart the
// generator rendered at one size and the form promised another.
const _sizes = [
  ('LinkedIn Horizontal', '1200x627'),
  ('LinkedIn Square', '1080x1080'),
  ('Google Landscape', '1200x628'),
  ('Google Square', '1200x1200'),
  ('TikTok Vertical', '1080x1920'),
  ('Meta Square', '1080x1080'),
  ('Meta Vertical', '1080x1350'),
  ('Meta Stories/Reels', '1080x1920'),
];

const adsCampaignGoals = ['Brand Awareness', 'Engagement', 'Sales', 'Lead Generation', 'Website Traffic'];

const adsAudiences = [
  ('B2B', 'Business owners, startups, agencies'),
  ('B2C', 'End consumers, everyday users'),
  ('Casual', 'Broad social media audience'),
  ('Inspirational', 'Entrepreneurs & creators'),
  ('Sales', 'Hot leads, ad audiences'),
];

const _fileFormats = ['PNG', 'JPEG', 'WEBP', 'AVIF'];

const _visualStyles = [
  ('minimal', 'Minimal'),
  ('bold', 'Bold'),
  ('elegant', 'Elegant'),
  ('playful', 'Playful'),
  ('corporate', 'Corporate'),
  ('modern', 'Modern'),
  ('neon', 'Neon'),
  ('pastel', 'Pastel'),
];

/// The five swatches both ad forms offer (BRAND_COLORS).
const adsBrandColors = ['#2563eb', '#0ea5e9', '#8b5cf6', '#ec4899', '#ef4444'];

const _steps = [
  ('Brand Details', LucideIcons.image),
  ('Size, Goals & Audience', LucideIcons.scan),
  ('Background Image', LucideIcons.images),
];

class _ImageAdsFormState extends State<ImageAdsForm> {
  StudioFormHost get host => widget.host;

  int _step = 1;
  String? _error;
  bool _generating = false;

  // Brand details — seeded the way studio/page.jsx seeds `formData`.
  late final _name = TextEditingController(text: host.brandName);
  late final _description = TextEditingController(text: host.brandDescription);
  late final _url = TextEditingController(text: host.brandUrl);
  late String _brandColor = host.brand?.primaryColor ?? '#2563eb';
  late String? _logo = host.brandLogo;
  late String _caption = host.brand != null ? 'Discover ${host.brandName.isEmpty ? 'our brand' : host.brandName}!' : '';
  String _visualStyle = 'modern';
  final String _font = 'Montserrat';
  List<String> _importedImages = const [];
  bool _importing = false;

  // Size, goals & audience. No size is preselected, as on the web.
  (String, String)? _size;
  String _goal = 'Engagement';
  String _audience = 'B2C';
  String _format = 'PNG';

  // Background images
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
    if (_step == 2 && _size == null) return _fail('Please complete all fields before continuing.');
    setState(() {
      _error = null;
      _step++;
    });
  }

  Future<void> _generate() async {
    final size = _size;
    if (size == null) return _fail('Please select an ad size.');
    // Gate: generation needs at least adsMinImages images selected.
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
      // The web lets you pick a style here but leaves it out of its live
      // payload; we send it so the choice isn't silently lost.
      'visualStyle': _visualStyle,
      'font': _font,
      'sourceUrl': nn(_url.text),
      'campaignGoal': _goal,
      'audience': _audience,
      'fileFormat': _format,
      'caption': nn(_caption),
      'category': size.$1.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
      'type_size': size.$2,
      // Every item is already a hosted URL (uploaded or picked from the web).
      'images': [for (final m in _media) m.url],
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
              const FormSectionTitle('Brand Details'),
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
                label: 'Description',
                child: StudioTextField(
                  controller: _description,
                  accent: accent,
                  hint: 'Brief description of your brand or campaign…',
                  maxLines: 3,
                  onChanged: (_) => setState(() => _error = null),
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
              // Keyed on the name, NOT the dimensions: several presets share
              // dimensions (LinkedIn Square and Meta Square are both 1080x1080),
              // so matching on the size would light up two chips at once.
              FormFieldBlock(
                label: 'Ad Size',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChipWrap(
                      children: [
                        for (final s in _sizes)
                          OptionChip(
                            label: s.$1,
                            desc: s.$2,
                            accent: accent,
                            active: _size?.$1 == s.$1,
                            onTap: () => setState(() {
                              _size = s;
                              _error = null;
                            }),
                          ),
                      ],
                    ),
                    if (_size != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Selected: ${_size!.$1} (${_size!.$2})',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: accent),
                        ),
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
                label: 'File Format',
                child: ChipWrap(
                  children: [
                    for (final f in _fileFormats)
                      OptionChip(
                        label: f == 'PNG' ? '$f ✓' : f,
                        accent: accent,
                        active: _format == f,
                        onTap: () => setState(() => _format = f),
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
              AdsMediaStep(
                host: host,
                items: _media,
                importedImages: _importedImages,
                searchSeed: _name.text,
                onChanged: (m) => setState(() {
                  _media = m;
                  _error = null;
                }),
                zoneTitle: 'Upload or Search More Images',
                zoneHint: 'Search the web or upload from your phone',
                zoneIcon: LucideIcons.fileUp,
                buttonIcon: LucideIcons.images,
              ),
              // Image-gate hint — only while below the minimum.
              if (_media.length < adsMinImages)
                Text(
                  'Select at least $adsMinImages images (max $adsMaxImages) to generate.',
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
          generateLabel: 'Generate Ads',
          generateIcon: LucideIcons.sparkles,
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared by ImageAdsForm and VideoAdsForm: the "Background Image / Media" step.
// ═════════════════════════════════════════════════════════════════════════════

/// Port of `(lib)/creative/imageGate.js`: the ad forms need between
/// [adsMinImages] and [adsMaxImages] images before Generate unlocks.
const adsMinImages = 3;
const adsMaxImages = 5;

String adsImageGateMessage(int count) => 'Select at least $adsMinImages images to generate — you have $count.';

/// One picked background image or video. [url] is always a hosted URL, which
/// is what ends up in the payload's `images`.
class AdsMediaItem {
  const AdsMediaItem({required this.url, this.thumb, this.isVideo = false});

  final String url;

  /// A still to show for it; a gallery/uploaded video has none.
  final String? thumb;
  final bool isVideo;
}

/// The step-3 body of both ad forms: the brand images strip
/// (`BrandImagesStrip.jsx`), the selected grid, and the "Choose Media" zone
/// that opens [_MediaPickerSheet] (the phone stand-in for `MediaPickerModal`).
class AdsMediaStep extends StatefulWidget {
  const AdsMediaStep({
    super.key,
    required this.host,
    required this.items,
    required this.onChanged,
    required this.importedImages,
    required this.searchSeed,
    required this.zoneTitle,
    required this.zoneHint,
    required this.zoneIcon,
    required this.buttonIcon,
    this.allowVideo = false,
  });

  final StudioFormHost host;
  final List<AdsMediaItem> items;
  final ValueChanged<List<AdsMediaItem>> onChanged;

  /// Images the URL import scraped; when empty the strip shows the user's
  /// own gallery instead, as the web does.
  final List<String> importedImages;

  /// What an empty stock search looks for (the brand name).
  final String searchSeed;
  final String zoneTitle;
  final String zoneHint;
  final IconData zoneIcon;
  final IconData buttonIcon;

  /// Video ads take background videos too (from the gallery / phone).
  final bool allowVideo;

  @override
  State<AdsMediaStep> createState() => _AdsMediaStepState();
}

class _AdsMediaStepState extends State<AdsMediaStep> {
  List<String>? _library; // the gallery fallback for the strip
  final _localSelected = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.importedImages.isEmpty) _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    final (items, _) = await EditorApi(context.read<AuthController>().api).gallery(type: 'image');
    if (mounted) setState(() => _library = [for (final i in items) i.src]);
  }

  int get _remaining => adsMaxImages - widget.items.length;

  void _add(List<AdsMediaItem> picked) {
    final have = {for (final m in widget.items) m.url};
    final fresh = picked.where((p) => !have.contains(p.url)).toList();
    final toAdd = fresh.take(_remaining.clamp(0, adsMaxImages)).toList();
    if (toAdd.isEmpty) {
      if (fresh.isNotEmpty) Toast.error('Max $adsMaxImages items reached.');
      return;
    }
    widget.onChanged([...widget.items, ...toAdd]);
    if (toAdd.length < fresh.length) {
      Toast.warning('Max $adsMaxImages items reached — some skipped.');
    } else {
      Toast.success('${toAdd.length} item${toAdd.length > 1 ? 's' : ''} added ✓');
    }
  }

  Future<void> _openPicker() async {
    if (_remaining <= 0) return Toast.error('Max $adsMaxImages items reached.');
    final picked = await showModalBottomSheet<List<AdsMediaItem>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MediaPickerSheet(
        host: widget.host,
        api: EditorApi(context.read<AuthController>().api),
        maxSelectable: _remaining,
        searchSeed: widget.searchSeed.trim().isNotEmpty
            ? widget.searchSeed.trim()
            : (widget.host.brandName.trim().isNotEmpty ? widget.host.brandName.trim() : 'premium marketing lifestyle'),
        allowVideo: widget.allowVideo,
      ),
    );
    if (picked != null && picked.isNotEmpty && mounted) _add(picked);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.host.color;
    return FormColumn(
      gap: 14,
      children: [
        _brandStrip(context, accent),
        if (widget.items.isNotEmpty) _selectedGrid(context),
        _chooseZone(context, accent),
      ],
    );
  }

  // ── BrandImagesStrip.jsx ───────────────────────────────────────────────────

  Widget _brandStrip(BuildContext context, Color accent) {
    final c = context.colors;
    final source = widget.importedImages.isNotEmpty ? widget.importedImages : _library;
    if (source == null) {
      return Row(
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text('Loading your images…', style: TextStyle(fontSize: 12, color: c.gray400)),
        ],
      );
    }
    final images = source.toSet().take(8).toList(); // dedupe — the backend sometimes repeats
    if (images.isEmpty) return const SizedBox.shrink();

    final selectedUrls = {for (final m in widget.items) m.url};
    final total = selectedUrls.length + _localSelected.length;
    final atCap = total >= adsMaxImages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(LucideIcons.image, size: 14, color: c.gray400),
            const SizedBox(width: 6),
            Text(
              'Your brand images',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: atCap ? AppColors.amber500.withValues(alpha: 0.15) : c.gray100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$total / $adsMaxImages selected',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: atCap ? Color.lerp(AppColors.amber500, c.gray900, 0.3) : c.gray400,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_localSelected.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_localSelected.length} image${_localSelected.length > 1 ? 's' : ''} selected',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(_localSelected.clear),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(LucideIcons.x, size: 15, color: c.gray400),
                  tooltip: 'Clear selection',
                ),
                FilledButton.icon(
                  onPressed: () {
                    final urls = [
                      for (final u in images)
                        if (_localSelected.contains(u)) u,
                    ];
                    setState(_localSelected.clear);
                    _add([for (final u in urls) AdsMediaItem(url: u, thumb: u)]);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  icon: const Icon(LucideIcons.mousePointerClick, size: 13),
                  label: Text(_localSelected.length > 1 ? 'Use ${_localSelected.length}' : 'Use'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (atCap && _localSelected.isEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.amber500.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.amber500.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Maximum of $adsMaxImages images reached. Remove an image to add more.',
              style: TextStyle(fontSize: 11, color: Color.lerp(AppColors.amber500, c.gray900, 0.25)),
            ),
          ),
          const SizedBox(height: 8),
        ],
        GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final url in images)
              _StripTile(
                url: url,
                accent: accent,
                external: selectedUrls.contains(url),
                local: _localSelected.contains(url),
                disabled: atCap && !_localSelected.contains(url) && !selectedUrls.contains(url),
                onTap: () => setState(() {
                  if (_localSelected.remove(url)) return;
                  if (selectedUrls.length + _localSelected.length < adsMaxImages) _localSelected.add(url);
                }),
              ),
          ],
        ),
        if (_localSelected.isEmpty && !atCap)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Tap images to select one or more',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: c.gray400),
            ),
          ),
      ],
    );
  }

  // ── Selected (n) ───────────────────────────────────────────────────────────

  Widget _selectedGrid(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Selected (${widget.items.length})',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 5,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          clipBehavior: Clip.none,
          children: [
            for (final m in widget.items)
              Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: m.thumb != null
                        ? MediaImage(m.thumb!, cacheWidth: 160)
                        : ColoredBox(
                            color: c.gray100,
                            child: Icon(LucideIcons.video, size: 18, color: c.gray400),
                          ),
                  ),
                  if (m.isVideo && m.thumb != null)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                        child: const Icon(LucideIcons.clapperboard, size: 11, color: Colors.white),
                      ),
                    ),
                  // Always visible — there's no hover on a phone.
                  Positioned(
                    top: -5,
                    right: -5,
                    child: GestureDetector(
                      onTap: () => widget.onChanged([...widget.items]..remove(m)),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(color: AppColors.red500, shape: BoxShape.circle),
                        child: const Icon(LucideIcons.x, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  // ── Upload / picker zone ───────────────────────────────────────────────────

  Widget _chooseZone(BuildContext context, Color accent) {
    final c = context.colors;
    return Material(
      color: c.gray50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.gray200, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openPicker,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.gray200),
                ),
                child: Icon(widget.zoneIcon, size: 19, color: c.gray400),
              ),
              const SizedBox(height: 10),
              Text(
                widget.zoneTitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray700),
              ),
              const SizedBox(height: 3),
              Text(
                widget.zoneHint,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: c.gray400),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _openPicker,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                icon: Icon(widget.buttonIcon, size: 15),
                label: const Text('Choose Media'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One square in the brand images strip, with its check circle.
class _StripTile extends StatelessWidget {
  const _StripTile({
    required this.url,
    required this.accent,
    required this.external,
    required this.local,
    required this.disabled,
    required this.onTap,
  });

  final String url;
  final Color accent;
  final bool external;
  final bool local;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final picked = external || local;
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: GestureDetector(
        // Already in the form: the selected grid's × removes it.
        onTap: external || disabled ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: picked ? accent.withValues(alpha: local ? 1 : 0.6) : c.gray100,
              width: picked ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MediaImage(url, cacheWidth: 200),
              Positioned(
                top: 5,
                left: 5,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: picked ? accent : c.surface.withValues(alpha: 0.85),
                    border: Border.all(color: picked ? accent : c.gray300, width: 1.5),
                  ),
                  child: picked ? const Icon(LucideIcons.check, size: 11, color: Colors.white) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── MediaPickerModal.jsx (Search Media · My Library) ────────────────────────

class _MediaPickerSheet extends StatefulWidget {
  const _MediaPickerSheet({
    required this.host,
    required this.api,
    required this.maxSelectable,
    required this.searchSeed,
    required this.allowVideo,
  });

  final StudioFormHost host;
  final EditorApi api;
  final int maxSelectable;
  final String searchSeed;
  final bool allowVideo;

  @override
  State<_MediaPickerSheet> createState() => _MediaPickerSheetState();
}

class _MediaPickerSheetState extends State<_MediaPickerSheet> {
  String _tab = 'search'; // 'search' | 'library'
  final _selected = <AdsMediaItem>[];

  // Search (Pexels through the web app's /api/pexels — the key stays server-side)
  final _query = TextEditingController();
  Timer? _debounce;
  List<AdsMediaItem>? _results;
  bool _searchFailed = false;
  int _searchRun = 0;

  // Library
  String _libType = 'image';
  final _library = <AdsMediaItem>[];
  int _page = 1;
  bool _hasMore = true;
  bool _libLoading = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim().isNotEmpty ? _query.text.trim() : widget.searchSeed;
    final run = ++_searchRun;
    setState(() {
      _results = null;
      _searchFailed = false;
    });
    try {
      final res = await Dio().get<Map<String, dynamic>>(
        '${AppConfig.webAppUrl}/api/pexels',
        queryParameters: {'query': q, 'per_page': 60},
      );
      if (!mounted || run != _searchRun) return;
      final photos = res.data?['photos'];
      setState(
        () => _results = [
          for (final p in (photos is List ? photos : const []).whereType<Map>())
            if (p['src'] is Map)
              AdsMediaItem(
                url: '${(p['src'] as Map)['large2x'] ?? (p['src'] as Map)['large'] ?? (p['src'] as Map)['original']}',
                thumb: '${(p['src'] as Map)['medium'] ?? (p['src'] as Map)['small']}',
              ),
        ],
      );
    } catch (_) {
      if (!mounted || run != _searchRun) return;
      setState(() {
        _results = const [];
        _searchFailed = true;
      });
      Toast.error('Failed to load images.');
    }
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _search);
  }

  Future<void> _loadLibrary() async {
    if (_libLoading || !_hasMore) return;
    setState(() => _libLoading = true);
    final type = _libType;
    final (items, more) = await widget.api.gallery(type: type, page: _page);
    if (!mounted || type != _libType) return;
    setState(() {
      _library.addAll([
        for (final i in items)
          type == 'video' ? AdsMediaItem(url: i.src, isVideo: true) : AdsMediaItem(url: i.src, thumb: i.src),
      ]);
      _hasMore = more;
      _page++;
      _libLoading = false;
    });
  }

  void _setTab(String t) {
    setState(() => _tab = t);
    if (t == 'library' && _library.isEmpty) _loadLibrary();
  }

  void _setLibType(String t) {
    if (t == _libType) return;
    setState(() {
      _libType = t;
      _library.clear();
      _page = 1;
      _hasMore = true;
      _libLoading = false;
    });
    _loadLibrary();
  }

  bool _isSelected(AdsMediaItem m) => _selected.any((s) => s.url == m.url);

  void _toggle(AdsMediaItem m) {
    if (_isSelected(m)) return setState(() => _selected.removeWhere((s) => s.url == m.url));
    if (_selected.length >= widget.maxSelectable) {
      return Toast.error(
        'You can only select ${widget.maxSelectable} more item${widget.maxSelectable == 1 ? '' : 's'}.',
      );
    }
    setState(() => _selected.add(m));
  }

  Future<void> _upload() async {
    final room = widget.maxSelectable - _selected.length;
    if (room <= 0) return Toast.error('You can only select ${widget.maxSelectable} more items.');
    final picker = ImagePicker();
    final video = _libType == 'video';
    final files = video
        ? [?await picker.pickVideo(source: ImageSource.gallery)]
        : room == 1
        ? [?await picker.pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048)]
        : await picker.pickMultiImage(limit: room, maxWidth: 2048, maxHeight: 2048);
    if (files.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    var failed = 0;
    for (final f in files.take(room)) {
      try {
        final url = await widget.host.api.uploadImage(await f.readAsBytes(), f.name);
        if (url == null) {
          failed++;
          continue;
        }
        final item = video ? AdsMediaItem(url: url, isVideo: true) : AdsMediaItem(url: url, thumb: url);
        if (!mounted) return;
        setState(() {
          _library.insert(0, item);
          _selected.add(item);
        });
      } catch (_) {
        failed++;
      }
    }
    if (mounted) setState(() => _uploading = false);
    if (failed > 0) Toast.error('Upload failed. Please try again.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = widget.host.color;
    final height = MediaQuery.sizeOf(context).height * 0.85;

    Widget tabChip(String id, String label, IconData icon) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OptionChip(label: label, icon: icon, accent: accent, active: _tab == id, onTap: () => _setTab(id)),
    );

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose Media',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.gray900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(LucideIcons.x, size: 18, color: c.gray500),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  tabChip('search', 'Search Media', LucideIcons.fileSearch),
                  tabChip('library', 'My Library', LucideIcons.folderOpen),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _tab == 'search' ? _searchBody(context, accent) : _libraryBody(context, accent)),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.gray100)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_selected.length} / ${widget.maxSelectable} selected',
                      style: TextStyle(fontSize: 12.5, color: c.gray500),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.gray600,
                      side: BorderSide(color: c.gray200),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selected.isEmpty || _uploading ? null : () => Navigator.pop(context, [..._selected]),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(_selected.isEmpty ? 'Add' : 'Add (${_selected.length})'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<AdsMediaItem> items, Color accent, {Widget? footer}) => GridView.builder(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
    ),
    itemCount: items.length + (footer != null ? 1 : 0),
    itemBuilder: (context, i) {
      if (i == items.length) return footer!;
      final m = items[i];
      final on = _isSelected(m);
      final c = context.colors;
      return GestureDetector(
        onTap: () => _toggle(m),
        child: Container(
          decoration: BoxDecoration(
            color: c.gray100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? accent : Colors.transparent, width: 2.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (m.thumb != null) MediaImage(m.thumb!, cacheWidth: 240) else Icon(LucideIcons.video, color: c.gray400),
              if (on)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: const Icon(LucideIcons.check, size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _searchBody(BuildContext context, Color accent) {
    final c = context.colors;
    final results = _results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: StudioTextField(
            controller: _query,
            accent: accent,
            hint: 'Search images… (e.g. office, lifestyle, food)',
            onChanged: _onQuery,
          ),
        ),
        Expanded(
          child: results == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : results.isEmpty
              ? Center(
                  child: Text(
                    _searchFailed ? 'Failed to load images.' : 'No images found. Try another search.',
                    style: TextStyle(fontSize: 13, color: c.gray400),
                  ),
                )
              : _grid(results, accent),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Photos provided by Pexels',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: c.gray400),
          ),
        ),
      ],
    );
  }

  Widget _libraryBody(BuildContext context, Color accent) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              if (widget.allowVideo) ...[
                OptionChip(
                  label: 'Images',
                  accent: accent,
                  active: _libType == 'image',
                  onTap: () => _setLibType('image'),
                ),
                const SizedBox(width: 8),
                OptionChip(
                  label: 'Videos',
                  accent: accent,
                  active: _libType == 'video',
                  onTap: () => _setLibType('video'),
                ),
              ],
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _uploading ? null : _upload,
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.gray700,
                  side: BorderSide(color: c.gray200),
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                icon: _uploading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.upload, size: 15),
                label: Text(_uploading ? 'Uploading…' : 'Upload'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _library.isEmpty && _libLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _library.isEmpty
              ? Center(
                  child: Text(
                    _libType == 'video' ? 'No videos in your library yet.' : 'No images in your library yet.',
                    style: TextStyle(fontSize: 13, color: c.gray400),
                  ),
                )
              : _grid(
                  _library,
                  accent,
                  footer: _hasMore
                      ? Center(
                          child: _libLoading
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : TextButton(onPressed: _loadLibrary, child: const Text('Load more')),
                        )
                      : null,
                ),
        ),
      ],
    );
  }
}
