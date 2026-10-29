import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/design/design_renderer.dart';
import '../../core/theme/app_colors.dart';
import '../auth/auth_controller.dart';
import '../creatives/creatives_api.dart';
import '../creatives/design.dart';
import 'ad_intel_kit.dart';
import 'ad_intelligence_api.dart';
import 'comparison_widgets.dart';

/// Port of `ad-intelligence/creative-comparison/page.jsx` — two creatives (or
/// two competitor websites) scored side by side (`POST /creative-comparison`).
///
/// Phone layout: the web's `A | VS | B` grid stacks (A, the VS badge, B), and
/// the results' paired cards stack too; the two overall scores stay side by
/// side, since two numbers fit a 360dp row.
///
/// [initialImage] / [initialLabel] are the web's `?image=&label=` hand-off
/// from Magic Studio's "Compare": they seed Creative A and open its panel on
/// the Magic Studio tab.
class CreativeComparisonScreen extends StatefulWidget {
  const CreativeComparisonScreen({super.key, this.initialImage, this.initialLabel});

  final String? initialImage;
  final String? initialLabel;

  @override
  State<CreativeComparisonScreen> createState() => _CreativeComparisonScreenState();
}

class _CreativeComparisonScreenState extends State<CreativeComparisonScreen> {
  late final AuthController _auth = context.read<AuthController>();
  late final _api = AdIntelligenceApi(_auth.api);

  String _mode = 'creatives';
  bool _loading = false;
  Map<String, dynamic>? _result;
  String? _error;

  final _a = ComparisonSlot('Creative A');
  final _b = ComparisonSlot('Creative B');
  final _urlA = TextEditingController();
  final _urlB = TextEditingController();

  // Your creatives — fetched once here for BOTH panels (the web moved it up
  // for the same reason: two identical requests otherwise).
  List<Design> _designs = const [];
  bool _loadingDesigns = true;
  int? _designsBrand;

  List<MagicPick> _magic = const [];
  bool _loadingMagic = true;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialImage;
    if (seed != null && seed.isNotEmpty) {
      debugPrint('🆚 [comparison] opened with a Magic Studio image as Creative A');
      _a
        ..url = seed
        ..tab = 'magic';
      _a.label.text = (widget.initialLabel?.isNotEmpty ?? false) ? widget.initialLabel! : 'Creative A';
    }
    for (final c in [_a.label, _b.label, _urlA, _urlB]) {
      c.addListener(_onEdit);
    }
    _api.magicImageResults().then((items) {
      if (mounted) {
        setState(() {
          _magic = items;
          _loadingMagic = false;
        });
      }
    });
  }

  void _onEdit() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ⚠️ Waits for the active brand (fetchDesigns needs it), and reloads when
    // it changes — until then the panels' spinner stays up, like the web.
    final brandId = context.watch<AuthController>().activeBrand?.id;
    if (brandId != null && brandId != _designsBrand) {
      _designsBrand = brandId;
      _loadDesigns(brandId);
    }
  }

  Future<void> _loadDesigns(int brandId) async {
    final res = await CreativesApi(_auth.api).page(brandId, perPage: 20);
    if (!mounted || brandId != _designsBrand) return;
    setState(() {
      _designs = res?.designs ?? const [];
      _loadingDesigns = false;
    });
  }

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    _urlA.dispose();
    _urlB.dispose();
    super.dispose();
  }

  bool get _canCompare =>
      _mode == 'creatives' ? _a.hasImage && _b.hasImage : _urlA.text.trim().isNotEmpty && _urlB.text.trim().isNotEmpty;

  /// Render a picked design to PNG with the shared renderer, so the compared
  /// image matches what the editor shows (the web's renderDesignToBlob).
  Future<void> _selectDesign(ComparisonSlot slot, Design d) async {
    setState(() {
      slot
        ..designId = d.id
        ..file = null
        ..url = null
        ..rendering = true;
      slot.label.text = d.name;
    });
    PickedCreative? file;
    String? url;
    if (d.elements.isNotEmpty) {
      try {
        final long = math.max(d.canvasWidth, d.canvasHeight).toDouble();
        final png = await renderDesignPng(d.canvasSpec, d.elements, pixelRatio: math.min(1, 2048 / long));
        file = PickedCreative(bytes: png, name: '${d.name.isEmpty ? 'design' : d.name}.png');
      } catch (_) {
        file = null;
      }
    } else {
      // Nothing to paint — an image-only design is compared by its stored picture.
      url = d.previewUrl;
    }
    if (!mounted || slot.designId != d.id) return;
    // A failed render leaves the label without a picture, so Compare stays
    // off — the web's fallback does the same.
    setState(() {
      slot
        ..file = file
        ..url = url
        ..rendering = false;
    });
  }

  Future<void> _run() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    final AiResult res;
    if (_mode == 'creatives') {
      final List<PickedCreative> files;
      try {
        files = await Future.wait([_withFile(_a), _withFile(_b)]);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = _message(e) ?? "Couldn't load one of the images.";
          _loading = false;
        });
        return;
      }
      res = await _api.compareCreatives(labelA: _a.label.text, labelB: _b.label.text, a: files[0], b: files[1]);
    } else {
      res = await _api.compareWebsites(_urlA.text, _urlB.text);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = res.error;
      _result = res.data == null ? null : {'mode': _mode, ...res.data!};
    });
  }

  /// The web's `withFile`: a hosted pick is downloaded, and anything over the
  /// endpoint's 2MB limit is scaled down.
  Future<PickedCreative> _withFile(ComparisonSlot s) async {
    final file = s.file ?? await fetchForUpload(s.url!, s.label.text.isEmpty ? 'creative' : s.label.text);
    return fitUploadLimit(file);
  }

  static String? _message(Object e) {
    final s = '$e'.replaceFirst('Exception: ', '');
    return s.isEmpty ? null : s;
  }

  void _switchMode(String id) => setState(() {
    _mode = id;
    _result = null;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    return AdIntelPage(
      children: [
        const ToolHeader(
          icon: LucideIcons.gitCompareArrows,
          colors: [AiHue.indigo, AiHue.violetDeep],
          title: 'Creative Comparison',
          subtitle: 'Compare two creatives or competitor websites with AI-powered scoring.',
        ),

        // Mode selector — stacked on a phone, as the web does until sm.
        PairRow(
          children: [
            _modeCard(context, 'creatives', LucideIcons.upload, 'Compare Creatives', 'Upload two ad creatives'),
            _modeCard(context, 'websites', LucideIcons.globe, 'Compare Websites', 'Enter two competitor URLs'),
          ],
        ),
        const SizedBox(height: 8),

        // Hidden while the run is in flight: the loader shows the same pair,
        // and the request has already been sent with these inputs.
        if (_result == null && !_loading) ...[
          if (_mode == 'creatives') ...[
            CreativeSlotCard(
              title: 'Creative A',
              slot: _a,
              designs: _designs,
              loadingDesigns: _loadingDesigns,
              magic: _magic,
              loadingMagic: _loadingMagic,
              onChanged: () => setState(() {}),
              onSelectDesign: (d) => _selectDesign(_a, d),
            ),
            const VsBadge(),
            CreativeSlotCard(
              title: 'Creative B',
              slot: _b,
              designs: _designs,
              loadingDesigns: _loadingDesigns,
              magic: _magic,
              loadingMagic: _loadingMagic,
              onChanged: () => setState(() {}),
              onSelectDesign: (d) => _selectDesign(_b, d),
            ),
          ] else ...[
            WebsiteInputCard(label: 'Website A', controller: _urlA),
            const VsBadge(),
            WebsiteInputCard(label: 'Website B', controller: _urlB),
          ],
          const SizedBox(height: 12),
        ],

        if (_error != null) ErrorBanner(_error!),

        if (!_loading && _result == null)
          Center(
            child: GradientButton(
              label: 'Run AI Comparison',
              icon: LucideIcons.gitCompareArrows,
              colors: const [AiHue.indigo, AiHue.violetDeep],
              expand: false,
              height: 46,
              onPressed: _canCompare ? _run : null,
            ),
          ),

        if (_loading) ComparisonLoader(mode: _mode, a: _a, b: _b, urlA: _urlA.text, urlB: _urlB.text),

        if (_result != null && !_loading)
          ComparisonResults(
            result: _result!,
            onReset: () => setState(() {
              _result = null;
              _error = null;
            }),
          ),
      ],
    );
  }

  Widget _modeCard(BuildContext context, String id, IconData icon, String label, String description) {
    final c = context.colors;
    final active = _mode == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _switchMode(id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: active ? Color.alphaBlend(AiHue.indigo.withValues(alpha: 0.08), c.surface) : c.surface,
            border: Border.all(color: active ? AiHue.indigo.withValues(alpha: 0.5) : c.gray200),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: active ? AiHue.indigoDeep : c.gray400),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: active ? AiHue.indigoDeep : c.gray700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(description, style: TextStyle(fontSize: 12, color: c.gray400)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
