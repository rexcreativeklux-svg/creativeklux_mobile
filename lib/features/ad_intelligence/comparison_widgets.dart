import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/design/design_canvas.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../creatives/design.dart';
import 'ad_intel_kit.dart';
import 'ad_intelligence_api.dart';

/// The pieces of `creative-comparison/page.jsx` below the page itself:
/// CreativeUpload (+ CreativePickerCard), WebsiteInput, ComparisonLoader
/// (+ LoaderSide), ResultsPanel (+ ScoreBar, ProConList, WebsiteMetrics).

const _indigo = AiHue.indigo;
const _indigoDeep = AiHue.indigoDeep;

/// The dimensions each mode scores — the loader cycles through the same
/// list the results render.
const creativeScores = [
  ('conversionScore', 'Conversion'),
  ('engagementScore', 'Engagement'),
  ('visualScore', 'Visual'),
  ('brandScore', 'Brand'),
];
const websiteScores = [('seoScore', 'SEO'), ('contentScore', 'Content'), ('socialScore', 'Social')];

/// One side of a creatives comparison. Lives with the PAGE, not the panel —
/// the panels unmount while a run is in flight, and an error (or "New
/// Comparison") must bring them back with the pick and its tab intact (the
/// web's `tabFor` exists for the same reason).
class ComparisonSlot {
  ComparisonSlot(String defaultLabel) : label = TextEditingController(text: defaultLabel);

  final TextEditingController label;

  /// An upload or a rendered design.
  PickedCreative? file;

  /// A hosted picture (a Magic Studio pick, or an image-only design).
  String? url;

  /// The design the pick came from (lights its card).
  int? designId;

  /// A design is being painted to PNG.
  bool rendering = false;

  /// "projects" | "magic" | "upload". ⚠️ Opens on "From Creatives": comparing
  /// two of your own creatives is what this screen is for, so your work is
  /// offered first and a file upload is the alternative.
  String tab = 'projects';

  bool get hasImage => file != null || (url?.isNotEmpty ?? false);

  void clear() {
    file = null;
    url = null;
    designId = null;
    rendering = false;
  }

  void dispose() => label.dispose();
}

/// The picture a slot holds, from bytes or a URL.
Widget _slotImage(ComparisonSlot s, {BoxFit fit = BoxFit.contain}) {
  if (s.file != null) return Image.memory(s.file!.bytes, fit: fit, gaplessPlayback: true);
  if (s.url != null) return MediaImage(s.url!, fit: fit);
  return const SizedBox.shrink();
}

/// "VS" between the two inputs.
class VsBadge extends StatelessWidget {
  const VsBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.surface,
            border: Border.all(color: c.gray300, width: 1.5),
          ),
          child: Text(
            'VS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.gray400),
          ),
        ),
      ),
    );
  }
}

/// CreativeUpload — a name field and three sources: From Creatives / Magic
/// Studio / Upload image.
class CreativeSlotCard extends StatelessWidget {
  const CreativeSlotCard({
    super.key,
    required this.title,
    required this.slot,
    required this.designs,
    required this.loadingDesigns,
    required this.magic,
    required this.loadingMagic,
    required this.onChanged,
    required this.onSelectDesign,
  });

  final String title;
  final ComparisonSlot slot;
  final List<Design> designs;
  final bool loadingDesigns;
  final List<MagicPick> magic;
  final bool loadingMagic;

  /// The slot was changed in place — rebuild.
  final VoidCallback onChanged;
  final ValueChanged<Design> onSelectDesign;

  Future<void> _upload() async {
    final f = await pickCreativeImage();
    if (f == null) return;
    slot
      ..clear()
      ..file = f;
    onChanged();
  }

  void _clear() {
    slot.clear();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TinyLabel('$title Name', color: c.gray500, bottom: 6),
          SizedBox(
            height: 40,
            child: TextField(
              controller: slot.label,
              style: TextStyle(fontSize: 13.5, color: c.gray800),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.gray50,
                hintText: title,
                hintStyle: TextStyle(fontSize: 13.5, color: c.gray400),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.gray200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _indigo, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Segmented tabs — "From Creatives" leads and is the default.
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                _seg(context, 'projects', LucideIcons.layoutGrid, 'Creatives'),
                _seg(context, 'magic', LucideIcons.wandSparkles, 'Magic Studio'),
                _seg(context, 'upload', LucideIcons.upload, 'Upload'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          switch (slot.tab) {
            'upload' => _uploadTab(context),
            'magic' => _magicTab(context),
            _ => _projectsTab(context),
          },
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, String id, IconData icon, String label) {
    final c = context.colors;
    final active = slot.tab == id;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          slot.tab = id;
          onChanged();
        },
        child: Container(
          height: 32,
          decoration: BoxDecoration(color: active ? c.surface : null, borderRadius: BorderRadius.circular(9)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: active ? c.gray800 : c.gray500),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: active ? c.gray800 : c.gray500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _uploadTab(BuildContext context) {
    final c = context.colors;
    if (!slot.hasImage) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _upload,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 30),
          decoration: BoxDecoration(
            color: c.gray50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.gray200, width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(12)),
                child: Icon(LucideIcons.upload, size: 20, color: c.gray400),
              ),
              const SizedBox(height: 10),
              Text(
                'Upload $title',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray700),
              ),
              const SizedBox(height: 3),
              Text('PNG, JPG, WEBP', style: TextStyle(fontSize: 12, color: c.gray400)),
            ],
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: c.gray100,
        height: 200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _slotImage(slot),
            Positioned(top: 8, right: 8, child: _RoundX(onTap: _clear)),
          ],
        ),
      ),
    );
  }

  Widget _magicTab(BuildContext context) {
    final c = context.colors;
    final picked = slot.file == null && slot.url != null && magic.any((m) => m.url == slot.url);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loadingMagic)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Spinner(color: _indigo, size: 22, stroke: 2.5)),
          )
        else if (magic.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(
              children: [
                Icon(LucideIcons.wandSparkles, size: 30, color: c.gray200),
                const SizedBox(height: 8),
                Text('No Magic Studio images yet', style: TextStyle(fontSize: 12, color: c.gray400)),
              ],
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: magic.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemBuilder: (_, i) {
                final item = magic[i];
                final selected = slot.url == item.url && slot.file == null;
                return GestureDetector(
                  onTap: () {
                    slot
                      ..clear()
                      ..url = item.url;
                    slot.label.text = item.label;
                    onChanged();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: c.gray100,
                      border: Border.all(color: selected ? _indigo : Colors.transparent, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MediaImage(item.url, cacheWidth: 300),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Color(0x99000000), Color(0x00000000)],
                              ),
                            ),
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, color: Colors.white),
                            ),
                          ),
                        ),
                        if (selected) const Positioned(top: 5, right: 5, child: _CheckDot(size: 18)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        if (picked) _pickedStrip(context, slot.label.text),
      ],
    );
  }

  Widget _projectsTab(BuildContext context) {
    final c = context.colors;
    Design? selected;
    for (final d in designs) {
      if (d.id == slot.designId) selected = d;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loadingDesigns)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Spinner(color: _indigo, size: 22, stroke: 2.5)),
          )
        else if (designs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(
              children: [
                Icon(LucideIcons.wandSparkles, size: 30, color: c.gray200),
                const SizedBox(height: 8),
                Text('No designs found', style: TextStyle(fontSize: 12, color: c.gray400)),
              ],
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: designs.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 160,
              ),
              itemBuilder: (_, i) => _PickerCard(
                design: designs[i],
                selected: slot.designId == designs[i].id,
                rendering: slot.rendering && slot.designId == designs[i].id,
                onTap: () => onSelectDesign(designs[i]),
              ),
            ),
          ),
        if (selected != null) _pickedStrip(context, selected.name),
      ],
    );
  }

  Widget _pickedStrip(BuildContext context, String name) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.fromLTRB(12, 2, 2, 2),
    decoration: BoxDecoration(
      color: _indigo.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _indigo.withValues(alpha: 0.2)),
    ),
    child: Row(
      children: [
        const Icon(LucideIcons.check, size: 14, color: _indigo),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _indigoDeep),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _clear,
          icon: const Icon(LucideIcons.x, size: 15, color: _indigo),
        ),
      ],
    ),
  );
}

// Type → badge colours, mirroring the Creatives library (TYPE_COLOR).
const _typeColors = {
  'ads': Color(0xFF2563EB),
  'social': Color(0xFF4F46E5),
  'card': Color(0xFF7C3AED),
  'banner': Color(0xFF0D9488),
  'image': Color(0xFF2563EB),
  'video': Color(0xFF0891B2),
};

String _shortDate(DateTime? d) {
  if (d == null) return '—';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[d.month - 1]} ${d.day}';
}

/// CreativePickerCard — the /creatives library card (16:9 preview, type
/// badge, score, name, tagline, date) with a selected ring instead of the
/// favourite/delete actions.
class _PickerCard extends StatelessWidget {
  const _PickerCard({required this.design, required this.selected, required this.rendering, required this.onTap});

  final Design design;
  final bool selected;
  final bool rendering;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = design;
    final tc = _typeColors[d.type.toLowerCase()] ?? c.gray500;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _indigo : c.gray100, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: c.gray50,
                    child: d.elements.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(6),
                            child: DesignCanvas(canvas: d.canvasSpec, elements: d.elements),
                          )
                        : d.previewUrl != null
                        ? MediaImage(d.previewUrl!, fit: BoxFit.contain, cacheWidth: 400)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.wandSparkles, size: 20, color: c.gray300),
                              const SizedBox(height: 3),
                              Text('No preview', style: TextStyle(fontSize: 10, color: c.gray300)),
                            ],
                          ),
                  ),
                  Positioned(
                    top: 5,
                    left: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: tc.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(color: tc, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _cap(d.category),
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: tc),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (selected) const Positioned(top: 5, right: 5, child: _CheckDot(size: 20)),
                  if (d.score > 0)
                    Positioned(
                      bottom: 5,
                      right: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: c.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '★ ${d.score}',
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AiHue.greenDeep),
                        ),
                      ),
                    ),
                  if (rendering)
                    ColoredBox(
                      color: c.surface.withValues(alpha: 0.6),
                      child: const Center(child: Spinner(color: _indigo, size: 18, stroke: 2)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.gray900),
                  ),
                  Text(
                    d.tagline ?? _cap(d.category),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: d.tagline != null ? c.gray400 : c.gray300,
                      fontStyle: d.tagline != null ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(LucideIcons.clock, size: 11, color: c.gray300),
                      const SizedBox(width: 4),
                      Text(_shortDate(d.createdAt), style: TextStyle(fontSize: 10, color: c.gray400)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _CheckDot extends StatelessWidget {
  const _CheckDot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(color: _indigoDeep, shape: BoxShape.circle),
    child: Icon(LucideIcons.check, size: size * 0.6, color: Colors.white),
  );
}

class _RoundX extends StatelessWidget {
  const _RoundX({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: CircleBorder(side: BorderSide(color: c.gray200)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 30, height: 30, child: Icon(LucideIcons.x, size: 15, color: c.gray500)),
      ),
    );
  }
}

/// WebsiteInput — one URL field.
class WebsiteInputCard extends StatelessWidget {
  const WebsiteInputCard({super.key, required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TinyLabel(label, color: c.gray500, bottom: 10),
          SizedBox(
            height: 42,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              style: TextStyle(fontSize: 13.5, color: c.gray800),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.gray50,
                hintText: 'https://example.com',
                hintStyle: TextStyle(fontSize: 13.5, color: c.gray400),
                prefixIcon: Icon(LucideIcons.globe, size: 16, color: c.gray400),
                prefixIconConstraints: const BoxConstraints(minWidth: 38),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: controller.clear,
                        icon: Icon(LucideIcons.x, size: 15, color: c.gray300),
                      ),
                contentPadding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.gray200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _indigo, width: 1.5),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Column(
              children: [
                Icon(LucideIcons.globe, size: 34, color: c.gray100),
                const SizedBox(height: 6),
                Text('Enter a URL to compare', style: TextStyle(fontSize: 12, color: c.gray300)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The wait, with the two things being compared still on screen.
///
/// ⚠️ NO PROGRESS BAR, DELIBERATELY. The comparison is one request — nothing
/// here can see inside it, so a bar would advance on a guess. The elapsed time
/// is true, so that carries the wait. The dimension row is "what is being
/// assessed", cycling the real score keys; no ticks, since nothing knows a
/// stage finished.
class ComparisonLoader extends StatefulWidget {
  const ComparisonLoader({
    super.key,
    required this.mode,
    required this.a,
    required this.b,
    required this.urlA,
    required this.urlB,
  });

  final String mode;
  final ComparisonSlot a;
  final ComparisonSlot b;
  final String urlA;
  final String urlB;

  @override
  State<ComparisonLoader> createState() => _ComparisonLoaderState();
}

class _ComparisonLoaderState extends State<ComparisonLoader> {
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // One timer drives both the clock and the lit dimension, so they can't
    // drift apart. Mounted for exactly one run.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _seconds++));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final creatives = widget.mode == 'creatives';
    final dims = creatives ? creativeScores : websiteScores;
    final active = dims[(_seconds ~/ 2) % dims.length];
    final elapsed = _seconds < 60 ? '${_seconds}s' : '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}';

    return AiCard(
      padding: 18,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _side(context, widget.a, widget.urlA, 'Creative A')),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 34, 10, 0),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.surface,
                    border: Border.all(color: _indigo.withValues(alpha: 0.35), width: 1.5),
                  ),
                  child: const Text(
                    'VS',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _indigo),
                  ),
                ),
              ),
              Expanded(child: _side(context, widget.b, widget.urlB, 'Creative B')),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spinner(color: _indigo, size: 15, stroke: 2),
              const SizedBox(width: 8),
              Text(
                'Scoring ${active.$2.toLowerCase()}…',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in dims)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: d == active ? _indigo.withValues(alpha: 0.15) : c.gray100,
                  ),
                  child: Text(
                    d.$2,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: d == active ? _indigoDeep : c.gray400,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$elapsed elapsed · comparing both ${creatives ? 'creatives' : 'sites'} on ${dims.length} measures',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: c.gray400, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }

  Widget _side(BuildContext context, ComparisonSlot slot, String url, String fallback) {
    final c = context.colors;
    final creatives = widget.mode == 'creatives';
    final name = creatives ? slot.label.text : url;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: c.gray100,
                border: Border.all(color: c.gray200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: creatives && slot.hasImage
                  ? _slotImage(slot)
                  : Icon(LucideIcons.globe, size: 26, color: c.gray300),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name.isEmpty ? fallback : name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.gray700),
        ),
      ],
    );
  }
}

/// ResultsPanel — verdict, overall + per-dimension scores, website metrics
/// (websites mode) and each side's pros & cons.
class ComparisonResults extends StatelessWidget {
  const ComparisonResults({super.key, required this.result, required this.onReset});

  final Map<String, dynamic> result;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = mapOf(result['itemA']);
    final b = mapOf(result['itemB']);
    final winner = str(result['winner']);
    final margin = str(result['marginOfVictory']);
    final websites = result['mode'] == 'websites';
    final scores = websites ? websiteScores : creativeScores;
    final pair = [(a, 'A'), (b, 'B')];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Comparison Results',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.gray900),
                ),
              ),
              OutlinedButton(
                onPressed: onReset,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  foregroundColor: c.gray500,
                  side: BorderSide(color: c.gray200),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                child: const Text('New Comparison'),
              ),
            ],
          ),
        ),

        // Verdict banner
        AiCard(
          tint: _indigo,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: _indigoDeep, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(LucideIcons.gitCompareArrows, size: 15, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'AI Verdict',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.gray900),
                  ),
                  if (margin != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: TintPill(
                        '$margin victory',
                        border: false,
                        fontSize: 11,
                        color: switch (margin) {
                          'Narrow' => AiHue.blue,
                          'Clear' => AiHue.orangeDeep,
                          'Decisive' => AiHue.redDeep,
                          _ => c.gray600,
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(str(result['verdict']) ?? '', style: TextStyle(fontSize: 13, height: 1.5, color: c.gray700)),
            ],
          ),
        ),

        // Score breakdown
        AiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CardTitle('Score Breakdown', bottom: 14),
              Row(
                children: [
                  for (final (item, which) in pair) ...[
                    if (which == 'B') const SizedBox(width: 10),
                    Expanded(child: _overall(context, item, which == winner, which)),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              for (final (key, label) in scores)
                _ScoreBar(
                  label: label,
                  a: numOf(a[key]) ?? 0,
                  b: numOf(b[key]) ?? 0,
                  labelA: show(a['label']),
                  labelB: show(b['label']),
                ),
            ],
          ),
        ),

        if (websites)
          PairRow(
            children: [
              for (final (item, which) in pair)
                AiCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _itemHeader(context, item, which == winner),
                      _WebsiteMetrics(item: item),
                    ],
                  ),
                ),
            ],
          ),

        PairRow(
          children: [
            for (final (item, which) in pair)
              AiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _itemHeader(context, item, which == winner),
                    for (final p in listOf(item['pros'])) _proCon(context, '$p', true),
                    for (final p in listOf(item['cons'])) _proCon(context, '$p', false),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _overall(BuildContext context, Map<String, dynamic> item, bool won, String which) {
    final c = context.colors;
    final score = numOf(item['overallScore']) ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: won ? AiHue.emerald.withValues(alpha: 0.08) : c.gray50,
        border: Border.all(color: won ? AiHue.emerald.withValues(alpha: 0.35) : c.gray100, width: 2),
      ),
      child: Column(
        children: [
          Text(
            show(item['label']),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
          ),
          const SizedBox(height: 4),
          Text(
            show(item['overallScore']),
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: scoreColor(score)),
          ),
          const SizedBox(height: 6),
          _WinnerBadge(won: won),
        ],
      ),
    );
  }

  Widget _itemHeader(BuildContext context, Map<String, dynamic> item, bool won) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            show(item['label']),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.colors.gray900),
          ),
        ),
        const SizedBox(width: 8),
        _WinnerBadge(won: won),
      ],
    ),
  );

  Widget _proCon(BuildContext context, String text, bool pro) {
    final color = pro ? AiHue.emerald : AiHue.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(pro ? LucideIcons.trendingUp : LucideIcons.trendingDown, size: 13, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, height: 1.45, color: context.colors.gray700)),
          ),
        ],
      ),
    );
  }
}

class _WinnerBadge extends StatelessWidget {
  const _WinnerBadge({required this.won});

  final bool won;

  @override
  Widget build(BuildContext context) => won
      ? const TintPill('Winner', icon: LucideIcons.circleCheck, color: AiHue.emeraldDeep, fontSize: 11)
      : TintPill('Runner-up', icon: LucideIcons.circleX, color: context.colors.gray400, fontSize: 11);
}

/// One dimension: both scores, two bars, and who leads by how much.
class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.label, required this.a, required this.b, required this.labelA, required this.labelB});

  final String label;
  final num a;
  final num b;
  final String labelA;
  final String labelB;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final diff = a - b;
    Widget chip(num v) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: scoreColor(v).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(
        '$v',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scoreColor(v)),
      ),
    );
    Widget bar(num v, int delayMs) => ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: ColoredBox(
          color: c.gray100,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (v / 100).clamp(0, 1).toDouble()),
            duration: Duration(milliseconds: 700 + delayMs),
            curve: Curves.easeOut,
            builder: (_, f, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: f,
              child: ColoredBox(color: scoreColor(v)),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.gray600),
                ),
              ),
              chip(a),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('vs', style: TextStyle(fontSize: 11.5, color: c.gray300)),
              ),
              chip(b),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: bar(a, 0)),
              const SizedBox(width: 6),
              Expanded(child: bar(b, 100)),
            ],
          ),
          if (diff != 0)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                diff > 0
                    ? '$labelA leads by ${diff.toStringAsFixed(1)}'
                    : '$labelB leads by ${diff.abs().toStringAsFixed(1)}',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 10.5, color: c.gray400),
              ),
            ),
        ],
      ),
    );
  }
}

/// WebsiteMetrics — the traffic numbers present for one site, plus its
/// desktop/mobile split.
class _WebsiteMetrics extends StatelessWidget {
  const _WebsiteMetrics({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final metrics = [
      ('Monthly Visits', item['monthlyVisits']),
      ('Unique Visitors', item['uniqueVisitors']),
      ('Pages/Visit', item['pagesPerVisit']),
      ('Avg Duration', item['avgDuration']),
      ('Bounce Rate', item['bounceRate']),
      ('Top Age Group', item['topAgeGroup']),
    ].where((m) => str(m.$2) != null && m.$2 != 0).toList();

    Widget split(String label, dynamic v, Color color) {
      final pct = (numOf(v) ?? 0).clamp(0, 100) / 100;
      return Expanded(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label, style: TextStyle(fontSize: 10.5, color: c.gray500)),
                ),
                Text('${v ?? ''}%', style: TextStyle(fontSize: 10.5, color: c.gray500)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: ColoredBox(
                  color: c.gray200,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: pct.toDouble(),
                    child: ColoredBox(color: color),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowGrid(
          gap: 8,
          children: [
            for (final (label, v) in metrics)
              InsetBox(
                margin: 0,
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TinyLabel(label, bottom: 2),
                    Text(
                      '$v',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.gray800),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (item['desktopShare'] != null) ...[
          if (metrics.isNotEmpty) const SizedBox(height: 8),
          InsetBox(
            margin: 0,
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TinyLabel('Device Split', bottom: 6),
                Row(
                  children: [
                    split('Desktop', item['desktopShare'], AiHue.indigo),
                    const SizedBox(width: 12),
                    split('Mobile', item['mobileShare'], AiHue.violet),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
