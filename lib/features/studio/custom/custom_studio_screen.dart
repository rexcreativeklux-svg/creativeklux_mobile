import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import '../../shell/widgets/app_top_bar.dart';
import 'creatives_config.dart';
import 'custom_studio_api.dart';
import 'design_results_view.dart';
import 'forms/studio_forms.dart';
import 'studio_form_kit.dart';

/// Port of `(pages)/studio/page.jsx` (`/studio?creative=…`): the category
/// pills for one creative type, the matching form, and the generated designs.
class CustomStudioScreen extends StatefulWidget {
  const CustomStudioScreen({super.key, this.creative});

  final String? creative;

  @override
  State<CustomStudioScreen> createState() => _CustomStudioScreenState();
}

class _CustomStudioScreenState extends State<CustomStudioScreen> {
  late final StudioCreative _creative = creativeById(widget.creative);
  late StudioCategory _category = _creative.categories.first;
  late final CustomStudioApi _api = CustomStudioApi(context.read<AuthController>().api);

  /// "form" or "result", like the web's `step`.
  bool _showingResults = false;
  bool _generating = false;
  String _generatingLabel = '';

  final _variations = <Map<String, dynamic>>[];
  int _expected = 0;
  bool _done = true;
  String _savedType = '';

  /// Runs create-design for a form. Batches stream into [_variations]; the
  /// results view takes over as soon as the first one lands.
  Future<String?> _generate(Map<String, dynamic> payload) async {
    final count = (int.tryParse('${payload['variations'] ?? ''}') ?? 5).clamp(1, 20);
    setState(() {
      _generating = true;
      _generatingLabel = 'Designing your ${_category.label.toLowerCase()}…';
      _variations.clear();
      _expected = count;
      _done = false;
      _savedType = '${payload['creativeType'] ?? _creative.id}';
    });

    final failures = await _api.studio.createDesigns(
      Map<String, dynamic>.from(payload),
      count: count,
      onBatch: (batch) {
        if (!mounted) return;
        setState(() {
          _variations.addAll(batch);
          if (batch.isNotEmpty) {
            _generating = false;
            _showingResults = true;
          }
        });
      },
    );
    if (!mounted) return null;
    setState(() {
      _generating = false;
      _done = true;
    });

    if (_variations.isEmpty) {
      return failures.isNotEmpty ? failures.first : 'No designs came back. Please try again.';
    }
    if (failures.isNotEmpty) {
      Toast.warning('${failures.length} batch${failures.length == 1 ? '' : 'es'} failed — showing the rest.');
    }
    return null;
  }

  Future<String?> _save(List<Map<String, dynamic>> designs) async {
    final brandId = context.read<AuthController>().activeBrand?.id;
    if (brandId == null) {
      Toast.error('Select a brand first.');
      return 'No brand';
    }
    final res = await _api.studio.save(brandId, designs, _savedType);
    if (!res.ok) {
      Toast.error(res.message);
      return res.message;
    }
    Toast.success('Design(s) saved successfully ✓', description: 'Find them in My Creations.');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final brand = context.watch<AuthController>().activeBrand;
    final host = StudioFormHost(creative: _creative, category: _category, brand: brand, api: _api, generate: _generate);

    return PopScope(
      // Back from the results returns to the form, like the web's "Back to form".
      canPop: !_showingResults,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showingResults) setState(() => _showingResults = false);
      },
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                AppTopBar(title: _creative.label, showBack: true),
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
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            children: [
                              _CategoryPills(
                                creative: _creative,
                                selected: _category,
                                onChanged: (cat) => setState(() => _category = cat),
                              ),
                              const SizedBox(height: 18),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: c.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: c.gray100),
                                ),
                                // Keyed so switching category starts that form fresh.
                                child: KeyedSubtree(
                                  key: ValueKey('${_creative.id}/${_category.id}'),
                                  child: buildStudioForm(host),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
            if (_generating) _GeneratingOverlay(label: _generatingLabel, accent: _creative.color),
          ],
        ),
      ),
    );
  }
}

/// The web's `CategorySelector`: the creative's label, then a pill per
/// category. Horizontal scroll on a phone instead of wrapping into a block.
class _CategoryPills extends StatelessWidget {
  const _CategoryPills({required this.creative, required this.selected, required this.onChanged});

  final StudioCreative creative;
  final StudioCategory selected;
  final ValueChanged<StudioCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = creative.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          creative.label.toUpperCase(),
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.6, color: color),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: creative.categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final cat = creative.categories[i];
              final active = cat.id == selected.id;
              return Opacity(
                opacity: cat.disabled ? 0.4 : 1,
                child: Material(
                  color: active ? color : c.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                    side: BorderSide(color: active ? color : color.withValues(alpha: 0.2)),
                  ),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: cat.disabled ? () => Toast.info('${cat.label} is coming soon…') : () => onChanged(cat),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Center(
                        child: Text(
                          cat.label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: active ? Colors.white : color,
                          ),
                        ),
                      ),
                    ),
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

/// Full-screen "designing…" overlay while the first batch is on its way —
/// the web's FloatingAnimation modal.
class _GeneratingOverlay extends StatelessWidget {
  const _GeneratingOverlay({required this.label, required this.accent});

  final String label;
  final Color accent;

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
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(LucideIcons.wandSparkles, color: accent, size: 26),
                ),
                const SizedBox(height: 16),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.gray900),
                ),
                const SizedBox(height: 4),
                Text(
                  'This can take a minute. Designs appear as soon as they are ready.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: c.gray500),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    color: accent,
                    backgroundColor: accent.withValues(alpha: 0.12),
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

/// Port of `(pages)/studio/select/page.jsx`: "What would you like to Create
/// today?" and a card per creative type.
class StudioSelectScreen extends StatelessWidget {
  const StudioSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Custom Creation', showBack: true),
          Expanded(
            child: Container(
              // The web's soft drifting orbs, as a still wash.
              decoration: BoxDecoration(
                color: c.page,
                gradient: RadialGradient(
                  center: const Alignment(-0.8, -0.9),
                  radius: 1.4,
                  colors: [AppColors.blue600.withValues(alpha: 0.07), c.page.withValues(alpha: 0)],
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'What would you like to '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: ShaderMask(
                            shaderCallback: (r) =>
                                const LinearGradient(colors: [Color(0xFF003DDA), Color(0xFF60A5FA), Color(0xFF2563EB)])
                                    .createShader(r),
                            child: const Text(
                              'Create',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(text: ' today?'),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.2,
                      color: c.gray900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose a creative type to get started',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: c.gray500),
                  ),
                  const SizedBox(height: 24),
                  for (final cr in studioCreatives) ...[
                    _CreativeCard(creative: cr, onTap: () => context.push('/studio?creative=${cr.id}')),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreativeCard extends StatelessWidget {
  const _CreativeCard({required this.creative, required this.onTap});

  final StudioCreative creative;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = creative.color;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 1))],
      ),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: 0.18), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: color.withValues(alpha: 0.08),
          highlightColor: color.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.15)),
                  ),
                  child: Icon(creative.icon, size: 20, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        creative.label,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.gray900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        creative.tagline.toUpperCase(),
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: color),
                      ),
                      const SizedBox(height: 6),
                      Text(creative.description, style: TextStyle(fontSize: 12.5, height: 1.5, color: c.gray500)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final tag in creative.tags)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: color.withValues(alpha: 0.18)),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: color),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 18, color: color.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
