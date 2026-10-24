import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/media.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import '../../editor/editor_api.dart';
import '../../shell/widgets/app_top_bar.dart';
import 'custom_studio_api.dart';
import 'design_results_view.dart';
import 'studio_form_kit.dart';

/// Port of `(pages)/studio/create-from-url/page.jsx` (`/studio/create-from-url`):
/// import a website's brand details, pick Ads or Content, fill in the details,
/// size / goal / audience, choose 3–5 background images, then generate designs
/// with the create-design engine and save the ones you like.
///
/// Phone changes: the step bar shows icons plus a "Step n of 5" caption instead
/// of five labels; images are added without the web's cropper (the web's own
/// "Skip" path); the media picker is a bottom sheet with Search + My Library +
/// Upload (no Magic Studio tab).
class CreateFromUrlScreen extends StatefulWidget {
  const CreateFromUrlScreen({super.key});

  @override
  State<CreateFromUrlScreen> createState() => _CreateFromUrlScreenState();
}

// ── Options (same lists and copy as the web page) ───────────────────────────

const _visualStyles = ['Minimal', 'Bold', 'Elegant', 'Playful', 'Corporate', 'Modern', 'Neon', 'Pastel'];

const _adSizes = [
  ('LinkedIn Horizontal', '1200×627'),
  ('LinkedIn Square', '627×627'),
  ('Google Landscape', '1200×628'),
  ('Google Square', '1200×1200'),
  ('TikTok Vertical', '1080×1920'),
  ('Meta Square', '1080×1080'),
  ('Meta Vertical', '1080×1350'),
  ('Meta Stories/Reels', '1080×1921'),
];

const _socialSizes = [
  ('LinkedIn Horizontal', '1200×627'),
  ('LinkedIn Square', '627×627'),
  ('Instagram Square', '1080×1080'),
  ('Instagram Portrait', '1080×1350'),
  ('Stories / Reels', '1080×1920'),
  ('Facebook Feed', '1200×630'),
  ('Twitter / X Post', '1600×900'),
  ('Pinterest Pin', '1000×1500'),
];

const _videoSizes = [
  ('TikTok / Reels', '1080×1920'),
  ('Meta Square', '1080×1080'),
  ('Meta Vertical', '1080×1350'),
  ('YouTube / Landscape', '1920×1080'),
  ('Google Display', '1200×628'),
  ('LinkedIn', '1200×627'),
  ('Stories', '720×1280'),
  ('Pre-roll', '1280×720'),
];

const _campaignGoals = ['Brand Awareness', 'Engagement', 'Sales', 'Lead Generation', 'Website Traffic'];

const _audiences = [
  ('B2B', 'Business owners, startups, agencies'),
  ('B2C', 'End consumers, everyday users'),
  ('Casual', 'Broad social media audience'),
  ('Inspirational', 'Entrepreneurs & creators'),
  ('Sales', 'Hot leads, ad audiences'),
];

const _postTones = ['Professional', 'Casual', 'Humorous', 'Inspirational', 'Urgent', 'Educational'];
const _socialPlatforms = ['Instagram', 'LinkedIn', 'Facebook', 'Twitter / X', 'TikTok', 'Pinterest'];
const _fileFormats = ['PNG', 'JPEG', 'WEBP', 'AVIF'];
const _videoFormats = ['MP4', 'MOV'];

/// (id, label, enabled) — Interactive / Playable are "Coming soon…" on the web too.
const _adSubTypes = [
  ('image', 'Image', true),
  ('video', 'Video', true),
  ('interactive', 'Interactive', false),
  ('playable', 'Playable', false),
];

const _defaultColors = ['#3b82f6', '#06b6d4', '#a855f7', '#ec4899', '#ef4444', '#1e3a8a'];

const _stepsAds = ['URL', 'Type', 'Brand Details', 'Size, Goals & Audience', 'Select Images'];
const _stepsSocial = ['URL', 'Type', 'Post Details', 'Size, Goals & Audience', 'Select Images'];
const _stepIcons = [
  LucideIcons.globe,
  LucideIcons.layoutGrid,
  LucideIcons.penLine,
  LucideIcons.slidersHorizontal,
  LucideIcons.images,
];

// `(lib)/creative/imageGate.js`: generation needs MIN..MAX images.
const _minImages = 3;
const _maxImages = 5;
String _imageGateMessage(int count) => 'Select at least $_minImages images to generate — you have $count.';

// `(lib)/design/creativeEngine.js`: create-design builds this many when the
// page has no count field.
const _defaultDesignCount = 5;

/// The web's blue-600 (Ads) and teal-600 (Content) selection accents.
Color get _adsAccent => AppColors.blue600;
const _socialAccent = Color(0xFF0D9488);

class _CreateFromUrlScreenState extends State<CreateFromUrlScreen> {
  late final CustomStudioApi _api = CustomStudioApi(context.read<AuthController>().api);

  int _step = 1;
  String? _creationType; // 'ads' | 'social'

  // Step 1
  final _urlCtrl = TextEditingController();
  bool _importing = false;
  bool _imported = false;
  String _importError = '';
  List<String> _scrapedImages = const []; // images pulled off the imported site (max 10)

  // Step 3
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _visualStyle = 'Modern';
  String _brandColor = '#1e3a8a';
  String? _logoUrl;
  bool _logoUploaded = false; // "Logo uploaded" vs "Logo imported"
  bool _logoBusy = false;
  String _postTone = 'Casual';
  String _targetPlatform = 'Instagram';

  // Step 4
  String _adSubType = 'image';
  String _adSize = 'Meta Square';
  String _socialSize = 'Instagram Square';
  String _videoSize = 'Meta Square';
  String _campaignGoal = 'Engagement';
  String _audience = 'B2C';
  String _fileFormat = 'PNG';
  String _videoFormat = 'MP4';

  // Step 5 — the web's `croppedImages`, as hosted URLs.
  final _images = <String>[];

  // Generation / results
  bool _generating = false;
  bool _showingResults = false;
  final _variations = <Map<String, dynamic>>[];
  int _expected = 0;
  bool _done = true;

  bool get _isAds => _creationType == 'ads';
  bool get _isVideo => _isAds && _adSubType == 'video';
  List<String> get _steps => _isAds ? _stepsAds : _stepsSocial;
  Color get _accent => _isAds ? _adsAccent : _socialAccent;

  @override
  void initState() {
    super.initState();
    // Step 3's Continue depends on both fields.
    _nameCtrl.addListener(_rebuild);
    _descCtrl.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String get _selectedSizeLabel => !_isAds ? _socialSize : (_isVideo ? _videoSize : _adSize);

  /// "1080x1080" — the web's getSelectedSize().
  String get _selectedSize {
    final list = !_isAds ? _socialSizes : (_isVideo ? _videoSizes : _adSizes);
    final fallback = _isVideo ? '1080x1920' : '1080x1080';
    for (final (label, size) in list) {
      if (label == _selectedSizeLabel) return size.replaceAll('×', 'x');
    }
    return fallback;
  }

  // ── URL import (the web's handleImport → sendUrl) ──────────────────────────

  Future<void> _import() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty || _importing) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _importing = true;
      _importError = '';
    });
    try {
      final d = await _api.importBrand(url);
      if (!mounted) return;
      setState(() {
        if (d.name != null) _nameCtrl.text = d.name!;
        if (d.description != null) _descCtrl.text = d.description!;
        if (d.primaryColor != null) _brandColor = d.primaryColor!;
        // Only take a usable link — some sites hand back an object here.
        final logo = d.logo;
        if (logo != null && (logo.startsWith('http') || logo.startsWith('data:'))) {
          _logoUrl = logo;
          _logoUploaded = false;
        }
        _scrapedImages = d.images.take(10).toList();
        _imported = true;
      });
    } catch (e) {
      final raw = '$e'.replaceFirst('Exception: ', '');
      final message = raw.trim().isEmpty ? 'Failed to import. Please fill in manually.' : raw;
      if (mounted) setState(() => _importError = message);
      Toast.error(message);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _pickLogo() async {
    setState(() => _logoBusy = true);
    final url = await pickAndUploadImage(_api, maxBytes: 5 * 1024 * 1024);
    if (!mounted) return;
    setState(() {
      _logoBusy = false;
      if (url != null) {
        _logoUrl = url;
        _logoUploaded = true;
      }
    });
  }

  // ── Images (the web's handleBrandImageUse / handleApplyFromPicker) ─────────

  void _useBrandImages(List<String> urls) {
    final remaining = _maxImages - _images.length;
    if (remaining <= 0) return Toast.info('Maximum of $_maxImages items reached.');
    final toAdd = urls.take(remaining).toList();
    setState(() => _images.addAll(toAdd));
    if (toAdd.length < urls.length) {
      Toast.info('Only added ${toAdd.length} — max $_maxImages reached.');
    } else {
      Toast.success('${toAdd.length} image${toAdd.length > 1 ? 's' : ''} added ✓');
    }
  }

  Future<void> _openPicker() async {
    final remaining = _maxImages - _images.length;
    if (remaining <= 0) return Toast.info('Maximum of $_maxImages items reached.');
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.colors.surface.withValues(alpha: 1),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _MediaPickerSheet(
        api: _api,
        editorApi: EditorApi(context.read<AuthController>().api),
        maxSelectable: remaining,
        searchFallback:
            '${_nameCtrl.text.trim().isEmpty ? 'premium marketing lifestyle' : _nameCtrl.text.trim()} marketing ad',
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final left = _maxImages - _images.length;
    final toAdd = picked.where((u) => !_images.contains(u)).take(left).toList();
    setState(() => _images.addAll(toAdd));
    Toast.success('Added ${toAdd.length} image(s)');
    if (toAdd.length < picked.length) Toast.info('Only added what fits — max $_maxImages.');
  }

  // ── Generate (the web's handleGenerate → generate) ─────────────────────────

  Future<void> _handleGenerate() async {
    if (_nameCtrl.text.trim().isEmpty) return Toast.error('Please enter a brand name');
    if (_images.length < _minImages) return Toast.error(_imageGateMessage(_images.length));
    await _generate();
  }

  Map<String, dynamic> _buildPayload() {
    final size = _selectedSize;
    final brandId = context.read<AuthController>().activeBrand?.id;
    return {
      'creativeType': _isAds ? 'ads_creative' : 'social_creative',
      'categoryType': _isAds ? _adSubType : 'posts',
      'brand_id': brandId,
      'brandName': _nameCtrl.text,
      'description': _descCtrl.text,
      'brandColor': _brandColor,
      'logo': _logoUrl,
      'visualStyle': _visualStyle,
      'font': 'Montserrat',
      'sourceUrl': _urlCtrl.text.isEmpty ? null : _urlCtrl.text,
      'size': size,
      'campaignGoal': _campaignGoal,
      'audience': _audience,
      if (_isVideo) 'videoFormat': _videoFormat else 'fileFormat': _fileFormat,
      // Every pick is already a hosted link (uploads go to the gallery on pick).
      'images': [
        for (final u in _images)
          if (u.startsWith('http')) u,
      ],
      'category': _selectedSizeLabel.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
      'type_size': size,
      if (!_isAds) ...{'tone': _postTone, 'platforms': _targetPlatform},
      'generatedAt': nowIso(),
    };
  }

  Future<void> _generate() async {
    final payload = _buildPayload();
    setState(() {
      _generating = true;
      _variations.clear();
      _expected = _defaultDesignCount;
      _done = false;
    });

    final failures = await _api.studio.createDesigns(
      payload,
      count: _defaultDesignCount,
      onBatch: (batch) {
        if (!mounted) return;
        setState(() {
          _variations.addAll(batch);
          // The results take over as soon as the first designs land.
          if (batch.isNotEmpty) {
            _generating = false;
            _showingResults = true;
          }
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _generating = false;
      _done = true;
    });

    if (_variations.isEmpty) {
      Toast.error(
        failures.isNotEmpty && failures.first.isNotEmpty ? failures.first : 'No results returned from generation',
      );
    } else if (failures.isNotEmpty) {
      Toast.warning('${failures.length} batch${failures.length == 1 ? '' : 'es'} failed — showing the rest.');
    }
  }

  Future<String?> _save(List<Map<String, dynamic>> designs) async {
    final brandId = context.read<AuthController>().activeBrand?.id;
    if (brandId == null) {
      Toast.error('Select a brand first.');
      return 'No brand';
    }
    final res = await _api.studio.save(brandId, designs, _isAds ? 'ads' : 'social');
    if (!res.ok) {
      Toast.error(res.message.isNotEmpty ? res.message : 'Failed to save designs');
      return res.message;
    }
    Toast.success('Design(s) saved successfully ✓', description: 'Find them in My Creations.');
    return null;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      // System back walks the steps (and leaves the results) before leaving.
      canPop: !_showingResults && _step == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _generating) return;
        setState(() => _showingResults ? _showingResults = false : _step--);
      },
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                const AppTopBar(title: 'Create from URL', showBack: true),
                Expanded(
                  child: Container(
                    color: c.page,
                    child: _showingResults
                        ? DesignResultsView(
                            variations: _variations,
                            expectedCount: _expected,
                            done: _done,
                            onBack: () => setState(() => _showingResults = false),
                            onSave: _save,
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            children: [
                              StepIndicator(
                                steps: [for (var i = 0; i < _steps.length; i++) (_steps[i], _stepIcons[i])],
                                current: _step,
                                accent: AppColors.blue600,
                                onTap: (n) => setState(() => _step = n),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Step $_step of ${_steps.length} · ${_steps[_step - 1]}',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: c.gray400),
                              ),
                              const SizedBox(height: 14),
                              _Card(child: _stepBody()),
                            ],
                          ),
                  ),
                ),
              ],
            ),
            if (_generating)
              const _GeneratingOverlay(
                title: 'Generating your ad creative',
                subtitle: 'Crafting copy, layout & visuals',
              ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody() => switch (_step) {
    1 => _stepUrl(),
    2 => _stepType(),
    3 => _stepDetails(),
    4 => _stepSizes(),
    _ => _stepImages(),
  };

  // ── Step 1: URL ────────────────────────────────────────────────────────────

  Widget _stepUrl() {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeading('Enter your website URL', "We'll automatically extract your brand details to get started."),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _imported ? AppColors.green500.withValues(alpha: 0.06) : c.gray50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _imported ? AppColors.green500.withValues(alpha: 0.4) : c.gray200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.globe, size: 15, color: _imported ? AppColors.green500 : AppColors.blue500),
                  const SizedBox(width: 6),
                  Text(
                    'URL',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray700),
                  ),
                  if (_imported) ...[
                    const SizedBox(width: 8),
                    const Icon(LucideIcons.check, size: 13, color: AppColors.green600),
                    const SizedBox(width: 3),
                    const Flexible(
                      child: Text(
                        'Brand data imported',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.green600),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (!_imported) Text('Auto-fills brand info', style: TextStyle(fontSize: 11, color: c.gray400)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlCtrl,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      textInputAction: TextInputAction.go,
                      onChanged: (_) => setState(() {
                        _imported = false;
                        _importError = '';
                      }),
                      onSubmitted: (_) => _import(),
                      style: TextStyle(fontSize: 13.5, color: c.gray900),
                      decoration: _inputDecoration(
                        context,
                        hint: 'https://yourwebsite.com',
                        border: _imported ? AppColors.green500.withValues(alpha: 0.5) : null,
                        suffix: _imported ? const Icon(LucideIcons.check, size: 16, color: AppColors.green500) : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _importing || _urlCtrl.text.trim().isEmpty ? null : _import,
                    style: FilledButton.styleFrom(
                      backgroundColor: _imported ? AppColors.green500 : AppColors.blue600,
                      disabledBackgroundColor: (_imported ? AppColors.green500 : AppColors.blue600).withValues(
                        alpha: 0.5,
                      ),
                      disabledForegroundColor: Colors.white,
                      minimumSize: const Size(80, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    child: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : _imported
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [Icon(LucideIcons.check, size: 14), SizedBox(width: 4), Text('Done')],
                          )
                        : const Text('Import'),
                  ),
                ],
              ),
              if (_importError.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_importError, style: const TextStyle(fontSize: 12, color: AppColors.red500)),
              ],
              if (_imported && _nameCtrl.text.isNotEmpty) ...[const SizedBox(height: 12), _importSummary()],
              if (!_imported && _importError.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Enter your website URL and tap Import to auto-fill your brand details.',
                  style: TextStyle(fontSize: 11.5, color: c.gray400),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        _NavRow(onNext: _imported ? () => setState(() => _step = 2) : null),
      ],
    );
  }

  Widget _importSummary() {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.green500.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.green500.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colorOf(_brandColor),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 3)],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nameCtrl.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.green600),
                ),
                if (_descCtrl.text.isNotEmpty)
                  Text(
                    _descCtrl.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.gray500),
                  ),
              ],
            ),
          ),
          if (_logoUrl != null) ...[const SizedBox(width: 8), _LogoThumb(_logoUrl!)],
        ],
      ),
    );
  }

  // ── Step 2: Type ───────────────────────────────────────────────────────────

  Widget _stepType() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _StepHeading('What would you like to create?', 'Choose your creative type to get started.'),
      const SizedBox(height: 16),
      _TypeCard(
        icon: LucideIcons.megaphone,
        label: 'Create Ads',
        description: 'Generate paid ad creatives for Meta, Google, TikTok, LinkedIn and more.',
        accent: _adsAccent,
        selected: _creationType == 'ads',
        onTap: () => setState(() => _creationType = 'ads'),
      ),
      const SizedBox(height: 10),
      _TypeCard(
        icon: LucideIcons.share2,
        label: 'Create Content',
        description: 'Design social media posts, stories, reels, banners and thumbnails.',
        accent: _socialAccent,
        selected: _creationType == 'social',
        onTap: () => setState(() => _creationType = 'social'),
      ),
      const SizedBox(height: 18),
      _NavRow(
        onBack: () => setState(() => _step = 1),
        onNext: _creationType == null ? null : () => setState(() => _step = 3),
      ),
    ],
  );

  // ── Step 3: Brand / Post Details ───────────────────────────────────────────

  Widget _stepDetails() {
    final c = context.colors;
    return FormColumn(
      children: [
        _StepHeading(_isAds ? 'Brand Details' : 'Post Details', null),
        FormFieldBlock(
          label: 'Brand Name / Project Name',
          required: true,
          child: StudioTextField(controller: _nameCtrl, accent: AppColors.blue600, hint: 'e.g. Acme Inc'),
        ),
        FormFieldBlock(
          label: _isAds ? 'Description' : 'Post Description',
          child: StudioTextField(
            controller: _descCtrl,
            accent: AppColors.blue600,
            maxLines: 3,
            hint: _isAds ? 'What does the brand do?' : 'What is this post about?',
          ),
        ),
        if (_isAds)
          FormFieldBlock(label: 'Visual Style', child: _chips(_visualStyles, _visualStyle, (v) => _visualStyle = v))
        else ...[
          FormFieldBlock(label: 'Post Tone', child: _chips(_postTones, _postTone, (v) => _postTone = v)),
          FormFieldBlock(
            label: 'Target Platform',
            child: _chips(_socialPlatforms, _targetPlatform, (v) => _targetPlatform = v),
          ),
        ],
        FormFieldBlock(
          label: 'Brand Color',
          child: BrandColorField(
            value: _brandColor,
            presets: _defaultColors,
            onChanged: (v) => setState(() => _brandColor = v),
          ),
        ),
        FormFieldBlock(
          label: 'Logo',
          child: Material(
            color: _logoUrl != null ? AppColors.green500.withValues(alpha: 0.06) : c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _logoUrl != null ? AppColors.green500.withValues(alpha: 0.6) : c.gray300),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _logoBusy ? null : _pickLogo,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    if (_logoBusy)
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    else if (_logoUrl != null)
                      const Icon(LucideIcons.check, size: 16, color: AppColors.green500)
                    else
                      Icon(LucideIcons.upload, size: 16, color: c.gray400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _logoBusy
                            ? 'Uploading…'
                            : _logoUrl == null
                            ? 'Upload logo'
                            : (_logoUploaded ? 'Logo uploaded' : 'Logo imported'),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: _logoUrl != null ? FontWeight.w500 : FontWeight.w400,
                          color: _logoUrl != null ? AppColors.green600 : c.gray500,
                        ),
                      ),
                    ),
                    if (_logoUrl != null) ...[
                      _LogoThumb(_logoUrl!),
                      IconButton(
                        onPressed: () => setState(() => _logoUrl = null),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(LucideIcons.x, size: 15, color: c.gray400),
                      ),
                    ] else
                      const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
        _NavRow(
          onBack: () => setState(() => _step = 2),
          onNext: _nameCtrl.text.trim().isEmpty || _descCtrl.text.trim().isEmpty
              ? null
              : () => setState(() => _step = 4),
        ),
      ],
    );
  }

  Widget _chips(List<String> options, String value, void Function(String) set) => ChipWrap(
    children: [
      for (final o in options)
        OptionChip(label: o, active: value == o, accent: _accent, onTap: () => setState(() => set(o))),
    ],
  );

  // ── Step 4: Size, Goals & Audience ─────────────────────────────────────────

  Widget _stepSizes() {
    final sizes = !_isAds ? _socialSizes : (_isVideo ? _videoSizes : _adSizes);
    final formats = _isVideo ? _videoFormats : _fileFormats;
    final format = _isVideo ? _videoFormat : _fileFormat;
    return FormColumn(
      children: [
        const _StepHeading('Size, Goals & Audience', null),
        if (_isAds)
          FormFieldBlock(
            label: 'Ad Format',
            child: ChipWrap(
              children: [
                for (final (id, label, enabled) in _adSubTypes)
                  Opacity(
                    opacity: enabled ? 1 : 0.5,
                    child: OptionChip(
                      label: label,
                      active: _adSubType == id,
                      accent: _adsAccent,
                      onTap: enabled ? () => setState(() => _adSubType = id) : () => Toast.info('Coming soon…'),
                    ),
                  ),
              ],
            ),
          ),
        FormFieldBlock(
          label: _isAds ? (_isVideo ? 'Video Size' : 'Ad Size') : 'Post Size',
          child: ChipWrap(
            children: [
              for (final (label, size) in sizes)
                OptionChip(
                  label: label,
                  desc: size,
                  active: _selectedSizeLabel == label,
                  accent: _accent,
                  onTap: () => setState(() {
                    if (!_isAds) {
                      _socialSize = label;
                    } else if (_isVideo) {
                      _videoSize = label;
                    } else {
                      _adSize = label;
                    }
                  }),
                ),
            ],
          ),
        ),
        FormFieldBlock(label: 'Campaign Goal', child: _chips(_campaignGoals, _campaignGoal, (v) => _campaignGoal = v)),
        FormFieldBlock(
          label: 'Audience',
          child: ChipWrap(
            children: [
              for (final (label, desc) in _audiences)
                OptionChip(
                  label: label,
                  desc: desc,
                  active: _audience == label,
                  accent: _accent,
                  onTap: () => setState(() => _audience = label),
                ),
            ],
          ),
        ),
        FormFieldBlock(
          label: _isVideo ? 'Video Format' : 'File Format',
          child: ChipWrap(
            children: [
              for (final f in formats)
                OptionChip(
                  label: f,
                  icon: format == f ? LucideIcons.check : null,
                  active: format == f,
                  accent: _accent,
                  onTap: () => setState(() => _isVideo ? _videoFormat = f : _fileFormat = f),
                ),
            ],
          ),
        ),
        _NavRow(onBack: () => setState(() => _step = 3), onNext: () => setState(() => _step = 5)),
      ],
    );
  }

  // ── Step 5: Select Images / Background Media ───────────────────────────────

  Widget _stepImages() {
    final c = context.colors;
    final canGenerate = _images.length >= _minImages;
    return FormColumn(
      gap: 16,
      children: [
        _StepHeading(
          _isVideo ? 'Select Background Media' : 'Select Images',
          _isVideo
              ? 'Add background media for your video ad. You can search, upload, or use brand assets.'
              : 'Add background images for your creative. You can search, upload, or use brand images.',
        ),
        if (_scrapedImages.isNotEmpty)
          _BrandImagesStrip(
            images: _scrapedImages,
            label: 'Images from imported site',
            selected: _images,
            maxSelect: _maxImages,
            onUse: _useBrandImages,
          ),
        if (_images.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Selected (${_images.length})',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final url in _images)
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: c.gray200),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: MediaImage(url, cacheWidth: 200),
                        ),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: GestureDetector(
                            onTap: () => setState(() => _images.remove(url)),
                            child: Container(
                              width: 22,
                              height: 22,
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
          ),
        // Upload / picker drop zone.
        Material(
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
                    child: Icon(_isVideo ? LucideIcons.film : LucideIcons.fileUp, size: 19, color: c.gray400),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isVideo ? 'Upload or Search Background Media' : 'Upload or Search Images',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _isVideo
                        ? 'Images from your library, web search, or your device'
                        : 'Search the web, your library, or upload from device',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: c.gray400),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _openPicker,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.blue600,
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    icon: Icon(_isVideo ? LucideIcons.film : LucideIcons.images, size: 16),
                    label: const Text('Choose Media'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Text(
          _isVideo
              ? 'Select at least $_minImages media items (max $_maxImages) to generate.'
              : 'Select at least $_minImages images (max $_maxImages) to generate.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: canGenerate ? c.gray400 : AppColors.amber500),
        ),
        _NavRow(
          onBack: () => setState(() => _step = 4),
          onNext: _generating ? null : _handleGenerate,
          nextLabel: _generating ? 'Generating...' : (_isVideo ? 'Generate Video Ads' : 'Generate Creative'),
          loading: _generating,
        ),
      ],
    );
  }
}

// ── Small pieces ────────────────────────────────────────────────────────────

InputDecoration _inputDecoration(BuildContext context, {String? hint, Color? border, Widget? suffix}) {
  final c = context.colors;
  OutlineInputBorder b(Color color, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: color, width: w),
  );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(fontSize: 13, color: c.gray400),
    filled: true,
    fillColor: c.surface,
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 34),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: b(border ?? c.gray200),
    focusedBorder: b(AppColors.blue500, 1.5),
    border: b(border ?? c.gray200),
  );
}

/// The white step card (`bg-surface rounded-2xl border p-7`).
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.colors.gray200),
    ),
    child: child,
  );
}

class _StepHeading extends StatelessWidget {
  const _StepHeading(this.title, this.subtitle);

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.gray900),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: TextStyle(fontSize: 13, height: 1.45, color: c.gray500)),
        ],
      ],
    );
  }
}

class _LogoThumb extends StatelessWidget {
  const _LogoThumb(this.url);

  final String url;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.green500.withValues(alpha: 0.3)),
    ),
    clipBehavior: Clip.antiAlias,
    child: MediaImage(url, fit: BoxFit.contain, cacheWidth: 120),
  );
}

/// ← Back · Continue → — each step's footer. [onNext] null = disabled, like
/// the web's `disabled:opacity-40`.
class _NavRow extends StatelessWidget {
  const _NavRow({this.onBack, required this.onNext, this.nextLabel = 'Continue', this.loading = false});

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextLabel;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        if (onBack != null) ...[
          OutlinedButton.icon(
            onPressed: onBack,
            style: OutlinedButton.styleFrom(
              foregroundColor: c.gray600,
              side: BorderSide(color: c.gray200),
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
            ),
            icon: const Icon(LucideIcons.arrowLeft, size: 16),
            label: const Text('Back'),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(child: Text(nextLabel, overflow: TextOverflow.ellipsis)),
                if (!loading) ...[const SizedBox(width: 6), const Icon(LucideIcons.arrowRight, size: 16)],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One of step 2's CREATION_TYPES cards.
class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? accent.withValues(alpha: 0.07) : c.gray50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? accent : c.gray100, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 21, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.gray900),
                    ),
                    const SizedBox(height: 3),
                    Text(description, style: TextStyle(fontSize: 12.5, height: 1.45, color: c.gray500)),
                  ],
                ),
              ),
              if (selected) ...[const SizedBox(width: 8), Icon(LucideIcons.circleCheck, size: 18, color: accent)],
            ],
          ),
        ),
      ),
    );
  }
}

/// Port of `(components)/BrandImagesStrip.jsx` as used here: the imported
/// site's images, tap to multi-select (capped with what's already picked),
/// then "Use". The web's Crop action is left out (no cropper on mobile yet).
class _BrandImagesStrip extends StatefulWidget {
  const _BrandImagesStrip({
    required this.images,
    required this.label,
    required this.selected,
    required this.maxSelect,
    required this.onUse,
  });

  final List<String> images;
  final String label;
  final List<String> selected;
  final int maxSelect;
  final ValueChanged<List<String>> onUse;

  @override
  State<_BrandImagesStrip> createState() => _BrandImagesStripState();
}

class _BrandImagesStripState extends State<_BrandImagesStrip> {
  final _local = <String>{};
  final _broken = <String>{};

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Dedupe — the backend sometimes returns the same image twice.
    final images = widget.images.toSet().where((u) => !_broken.contains(u)).toList();
    final external = widget.selected.length;
    // Trim if the outside selection grew (e.g. the picker added items).
    final allowed = (widget.maxSelect - external).clamp(0, widget.maxSelect);
    if (_local.length > allowed) {
      final keep = _local.take(allowed).toList();
      _local
        ..clear()
        ..addAll(keep);
    }
    final atCap = widget.maxSelect - external - _local.length <= 0;
    if (images.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(LucideIcons.image, size: 14, color: c.gray400),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: atCap ? AppColors.amber500.withValues(alpha: 0.15) : c.gray100,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${external + _local.length} / ${widget.maxSelect} selected',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: atCap ? AppColors.amber500 : c.gray400,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_local.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
            decoration: BoxDecoration(
              color: c.blueTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.blue500.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_local.length} image${_local.length > 1 ? 's' : ''} selected',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.blue600),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(_local.clear),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Clear selection',
                  icon: Icon(LucideIcons.x, size: 15, color: c.gray400),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final picked = _local.toList();
                    setState(_local.clear);
                    widget.onUse(picked);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue600,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  icon: const Icon(LucideIcons.mousePointerClick, size: 13),
                  label: Text(_local.length > 1 ? 'Use ${_local.length}' : 'Use'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (atCap && _local.isEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.amber500.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.amber500.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Maximum of ${widget.maxSelect} images reached. Remove an image to add more.',
              style: const TextStyle(fontSize: 11, color: AppColors.amber500),
            ),
          ),
          const SizedBox(height: 8),
        ],
        GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final url in images)
              Builder(
                builder: (context) {
                  final ext = widget.selected.contains(url);
                  final local = _local.contains(url);
                  final disabled = atCap && !local && !ext;
                  return Opacity(
                    opacity: disabled ? 0.4 : 1,
                    child: GestureDetector(
                      onTap: ext || disabled
                          ? null
                          : () => setState(() => local ? _local.remove(url) : _local.add(url)),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: local
                                ? AppColors.blue500
                                : ext
                                ? AppColors.blue500.withValues(alpha: 0.6)
                                : c.gray100,
                            width: local || ext ? 2 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              url,
                              fit: BoxFit.cover,
                              cacheWidth: 200,
                              // Broken scraped links are hidden, as on the web.
                              errorBuilder: (_, _, _) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted && !_broken.contains(url)) setState(() => _broken.add(url));
                                });
                                return const SizedBox.shrink();
                              },
                            ),
                            if (local || ext)
                              Positioned(
                                top: 4,
                                left: 4,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(color: AppColors.blue500, shape: BoxShape.circle),
                                  child: const Icon(LucideIcons.check, size: 11, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// A stock or library image in the picker.
class _PickItem {
  const _PickItem({required this.thumb, required this.full});
  final String thumb;
  final String full;
}

/// Phone version of `(components)/MediaPickerModal.jsx` as this page opens
/// it (image-only): Search Media (Pexels via the web app's `/api/pexels`, so
/// the key stays server-side), My Library (`GET /gallery`), and Upload from
/// the device. Pops with the chosen hosted URLs.
class _MediaPickerSheet extends StatefulWidget {
  const _MediaPickerSheet({
    required this.api,
    required this.editorApi,
    required this.maxSelectable,
    required this.searchFallback,
  });

  final CustomStudioApi api;
  final EditorApi editorApi;
  final int maxSelectable;

  /// What an empty search box searches for (`${brandName} marketing ad`).
  final String searchFallback;

  @override
  State<_MediaPickerSheet> createState() => _MediaPickerSheetState();
}

class _MediaPickerSheetState extends State<_MediaPickerSheet> {
  String _tab = 'search';
  final _selected = <String>[];

  // Search
  final _query = TextEditingController();
  Timer? _debounce;
  List<_PickItem>? _results;
  bool _searching = false;
  int _run = 0;

  // Library
  final _library = <_PickItem>[];
  int _page = 1;
  bool _hasMore = true;
  bool _libLoading = false;
  bool _libStarted = false;

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
    final q = _query.text.trim().isEmpty ? widget.searchFallback : _query.text.trim();
    final run = ++_run;
    setState(() => _searching = true);
    try {
      final res = await Dio().get<Map<String, dynamic>>(
        '${AppConfig.webAppUrl}/api/pexels',
        queryParameters: {'query': q, 'per_page': 60},
      );
      if (!mounted || run != _run) return;
      final photos = res.data?['photos'];
      setState(
        () => _results = [
          for (final p in (photos is List ? photos : const []).whereType<Map>())
            if (p['src'] is Map)
              _PickItem(
                thumb: '${(p['src'] as Map)['medium'] ?? (p['src'] as Map)['original']}',
                full: '${(p['src'] as Map)['large2x'] ?? (p['src'] as Map)['large'] ?? (p['src'] as Map)['original']}',
              ),
        ],
      );
    } catch (_) {
      if (!mounted || run != _run) return;
      Toast.error('Failed to load images.');
      setState(() => _results = const []);
    } finally {
      if (mounted && run == _run) setState(() => _searching = false);
    }
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _search);
  }

  Future<void> _loadLibrary() async {
    if (_libLoading || !_hasMore) return;
    setState(() {
      _libLoading = true;
      _libStarted = true;
    });
    final (items, more) = await widget.editorApi.gallery(type: 'image', page: _page);
    if (!mounted) return;
    setState(() {
      _library.addAll([for (final g in items) _PickItem(thumb: g.src, full: g.src)]);
      _hasMore = more;
      _page++;
      _libLoading = false;
    });
  }

  void _setTab(String t) {
    setState(() => _tab = t);
    if (t == 'library' && !_libStarted) _loadLibrary();
  }

  void _toggle(String url) {
    setState(() {
      if (_selected.contains(url)) {
        _selected.remove(url);
      } else if (widget.maxSelectable == 1) {
        // Single-select just swaps, like the web.
        _selected
          ..clear()
          ..add(url);
      } else if (_selected.length >= widget.maxSelectable) {
        final n = widget.maxSelectable;
        Toast.info('You can only select $n more item${n == 1 ? '' : 's'}.');
      } else {
        _selected.add(url);
      }
    });
  }

  Future<void> _upload() async {
    final left = widget.maxSelectable - _selected.length;
    if (left <= 0) {
      final n = widget.maxSelectable;
      return Toast.info('You can only select $n more item${n == 1 ? '' : 's'}.');
    }
    final picker = ImagePicker();
    final files = left >= 2
        ? await picker.pickMultiImage(limit: left, maxWidth: 2048, maxHeight: 2048)
        : [?await picker.pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048)];
    if (files.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    var failed = 0;
    for (final f in files.take(left)) {
      try {
        final url = await widget.api.uploadImage(await f.readAsBytes(), f.name);
        if (url == null) {
          failed++;
          continue;
        }
        if (!mounted) return;
        setState(() {
          _library.insert(0, _PickItem(thumb: url, full: url));
          _selected.add(url);
        });
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    if (failed > 0) Toast.error("Couldn't upload $failed image${failed == 1 ? '' : 's'}. Please try again.");
    // Show what was just uploaded.
    _setTab('library');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final height = MediaQuery.sizeOf(context).height * 0.88;
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: c.gray300, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose Media',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.gray900),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _uploading ? null : _upload,
                    icon: _uploading
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(LucideIcons.upload, size: 15),
                    label: Text(_uploading ? 'Uploading…' : 'Upload', style: const TextStyle(fontSize: 13)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(LucideIcons.x, size: 18, color: c.gray500),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _TabPill(
                    icon: LucideIcons.fileSearch,
                    label: 'Search Media',
                    active: _tab == 'search',
                    onTap: () => _setTab('search'),
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    icon: LucideIcons.folderOpen,
                    label: 'My Library',
                    active: _tab == 'library',
                    onTap: () => _setTab('library'),
                  ),
                ],
              ),
            ),
            if (_tab == 'search')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: TextField(
                  controller: _query,
                  onChanged: _onQuery,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    _debounce?.cancel();
                    _search();
                  },
                  style: TextStyle(fontSize: 13.5, color: c.gray900),
                  decoration: _inputDecoration(
                    context,
                    hint: 'Search photos…',
                  ).copyWith(prefixIcon: Icon(LucideIcons.search, size: 16, color: c.gray400)),
                ),
              ),
            const SizedBox(height: 10),
            Expanded(child: _tab == 'search' ? _searchGrid() : _libraryGrid()),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.gray200)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_selected.length} / ${widget.maxSelectable} selected',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.gray500),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.gray600,
                        side: BorderSide(color: c.gray200),
                        minimumSize: const Size(0, 42),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _selected.isEmpty || _uploading ? null : () => Navigator.pop(context, [..._selected]),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue600,
                        minimumSize: const Size(0, 42),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      child: Text(_selected.isEmpty ? 'Apply' : 'Apply (${_selected.length})'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchGrid() {
    final c = context.colors;
    final results = _results;
    if (results == null || (_searching && results.isEmpty)) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (results.isEmpty) {
      return Center(
        child: Text('No images found.', style: TextStyle(fontSize: 13, color: c.gray400)),
      );
    }
    return Stack(
      children: [
        _grid(results),
        if (_searching) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
      ],
    );
  }

  Widget _libraryGrid() {
    final c = context.colors;
    if (_library.isEmpty) {
      if (_libLoading || !_libStarted) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No images in your library yet. Tap Upload to add some.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.gray400),
          ),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) _loadLibrary();
        return false;
      },
      child: _grid(_library, footer: _libLoading),
    );
  }

  Widget _grid(List<_PickItem> items, {bool footer = false}) => GridView.builder(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
    ),
    itemCount: items.length + (footer ? 1 : 0),
    itemBuilder: (context, i) {
      if (i >= items.length) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      final item = items[i];
      final index = _selected.indexOf(item.full);
      final on = index >= 0;
      return GestureDetector(
        onTap: () => _toggle(item.full),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? AppColors.blue500 : Colors.transparent, width: 2.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MediaImage(item.thumb, cacheWidth: 240),
              if (on)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.blue500, shape: BoxShape.circle),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _TabPill extends StatelessWidget {
  const _TabPill({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: active ? AppColors.blue600 : c.gray100,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: active ? Colors.white : c.gray600),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: active ? Colors.white : c.gray600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen loader while the first designs are on the way — the web's
/// `FullOverlayLoader`. Same look as Custom Creation's overlay.
class _GeneratingOverlay extends StatelessWidget {
  const _GeneratingOverlay({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.blue600.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(LucideIcons.wandSparkles, color: AppColors.blue600, size: 26),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.gray500),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    color: AppColors.blue600,
                    backgroundColor: AppColors.blue600.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
