import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import '../studio/studio_api.dart';
import 'template_card.dart';
import 'templates_api.dart';

// Port of the web's app/(components)/studio/TemplateDetailsModal.jsx (the
// template half — saved designs open Creative Studio's own sheet instead) plus
// TemplatesSection.jsx's saveTemplate().
//
// Layout on a phone, top to bottom in one scroller: big preview → title and
// badges → "Save to Designs" → summary + tags → Specs → Share → "More like
// this". Tapping a sibling swaps the sheet over to it and jumps back to the
// top, so the strip is a browse loop rather than a dead end.
//
// ⚠️ NEITHER SOURCE SENDS PROSE. A row carries only structured fields, so the
// summary is WRITTEN HERE from those fields and the layer mix in `elements`
// (describeItem). If the backend ever adds a real `description`, show it instead.

/// Open the details sheet for [item]. [pool] feeds "More like this".
Future<void> showTemplateDetailsSheet(
  BuildContext context, {
  required KluxTemplate item,
  required List<KluxTemplate> pool,
  required TemplatePreviewCache cache,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.colors.surface.withValues(alpha: 1),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.94,
      child: _TemplateDetailsSheet(initial: item, pool: pool, cache: cache, hostContext: context),
    ),
  );
}

/// Plural-aware label per element type, e.g. 3 → "3 text blocks".
const _elementLabels = {
  'text': ('text block', 'text blocks'),
  'image': ('image', 'images'),
  'shape': ('shape', 'shapes'),
  'icon': ('icon', 'icons'),
  'line': ('line', 'lines'),
  'group': ('group', 'groups'),
  'table': ('table', 'tables'),
  'chart': ('chart', 'charts'),
};

/// "1080x1350" → "1080 × 1350 px". Falls back to the canvas when absent.
String? formatSize(KluxTemplate t) {
  final raw = t.typeSize?.trim();
  final m = raw == null ? null : RegExp(r'^(\d+)\s*[x×]\s*(\d+)$', caseSensitive: false).firstMatch(raw);
  if (m != null) return '${m[1]} × ${m[2]} px';
  final w = num.tryParse('${t.canvas['width']}');
  final h = num.tryParse('${t.canvas['height']}');
  if (w != null && h != null && w > 0 && h > 0) return '${w.round()} × ${h.round()} px';
  return (raw ?? '').isEmpty ? null : raw;
}

/// "8 text blocks, 4 shapes and 1 image" — biggest group first, since it
/// defines the design. Unknown types fall back to their own name.
String? describeLayers(List<dynamic> elements) {
  if (elements.isEmpty) return null;
  final counts = <String, int>{};
  for (final el in elements) {
    final type = (el is Map ? '${el['type'] ?? 'layer'}' : 'layer').toLowerCase();
    counts[type] = (counts[type] ?? 0) + 1;
  }
  final parts = (counts.entries.toList()..sort((a, b) => b.value - a.value)).map((e) {
    final (one, many) = _elementLabels[e.key] ?? (e.key, '${e.key}s');
    return '${e.value} ${e.value == 1 ? one : many}';
  }).toList();
  if (parts.length == 1) return parts.first;
  return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
}

/// The summary paragraph, written from the row's real fields.
String describeItem(KluxTemplate t) {
  final shape = (t.format ?? t.designType ?? t.category ?? 'design').toLowerCase();
  final size = formatSize(t);
  final orientation = (t.orientation ?? '').toLowerCase();
  var opening = 'A ${t.premium ? 'premium' : 'free'} $shape template';
  if (size != null) opening += ', sized $size';
  // Only add the orientation when the format hasn't already said it.
  if (orientation.isNotEmpty && !shape.contains(orientation)) opening += ' in $orientation';
  opening += '.';
  final layers = describeLayers(t.elements);
  final build = layers != null ? " It's built from ${t.elements.length} editable layers — $layers." : '';
  return '$opening$build Save it to your designs and every layer is yours to edit — copy, colours and images.';
}

/// Labelled spec rows; rows with no value are dropped. The web has Media,
/// Layers, Access and the dates commented out, so they stay out here too.
List<(String, String)> buildSpecs(KluxTemplate t) => [
  for (final (label, value) in [
    ('Format', t.format),
    ('Dimensions', formatSize(t)),
    ('Orientation', t.orientation),
    ('Category', t.category),
    ('Design type', t.designType),
  ])
    if (value != null && value.isNotEmpty) (label, value),
];

/// The chips under the summary — the same facts, scannable at a glance.
List<String> buildTags(KluxTemplate t) {
  final tags = <String>[];
  for (final tag in [
    t.designType,
    t.format,
    t.orientation,
    t.mediaType,
    t.pricing != null ? (t.premium ? 'Premium' : 'Free') : null,
  ]) {
    if (tag != null && tag.isNotEmpty && !tags.contains(tag)) tags.add(tag);
  }
  return tags;
}

class _TemplateDetailsSheet extends StatefulWidget {
  const _TemplateDetailsSheet({
    required this.initial,
    required this.pool,
    required this.cache,
    required this.hostContext,
  });

  final KluxTemplate initial;
  final List<KluxTemplate> pool;
  final TemplatePreviewCache cache;

  /// The screen's context — still mounted after the sheet pops, so the
  /// post-save navigation can run from it.
  final BuildContext hostContext;

  @override
  State<_TemplateDetailsSheet> createState() => _TemplateDetailsSheetState();
}

class _TemplateDetailsSheetState extends State<_TemplateDetailsSheet> {
  late KluxTemplate _item = widget.initial;
  final _scroll = ScrollController();
  bool _saving = false;
  bool _copied = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// A "More like this" tap re-points the sheet; jump (not animate) to the
  /// top to match the instant content swap.
  void _select(KluxTemplate next) {
    setState(() {
      _item = next;
      _copied = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// Copy the template into the brand's own designs (TemplatesSection's
  /// saveTemplate). It does NOT open the editor: the copy is written, a toast
  /// says so, and the user is moved to /creatives where the copy is waiting
  /// (the web home page's handleTemplateSaved).
  ///
  /// `type` / `sub_type` come from the template's own taxonomy so the copy
  /// lands in the right filter tab on /creatives instead of defaulting to
  /// "ads" — both the raw lowercased keys, not the display strings.
  Future<void> _save() async {
    if (_saving) return;
    final auth = context.read<AuthController>();
    final brandId = auth.activeBrand?.id;
    if (brandId == null) {
      Toast.error('Select a brand before saving a template.');
      return;
    }
    final item = _item;
    setState(() => _saving = true);
    debugPrint('💾 [templates] saving "${item.title}" to designs (brand $brandId)');
    try {
      final result = await StudioApi(auth.api).save(brandId, [
        {
          'name': item.title,
          'canvas': item.canvas,
          'elements': item.elements,
          'category': item.formatKey ?? 'image', // → sub_type
          // A library template is a Scraive layout: save converts it to ours,
          // so the editor opens it the way the card painted it.
          'source': 'scraive',
        },
      ], (item.designType ?? 'design').toLowerCase());
      if (!mounted) return;
      if (!result.ok) {
        Toast.error(result.message.isNotEmpty ? result.message : "Couldn't save this template. Please try again.");
        setState(() => _saving = false);
        return;
      }
      Toast.success('"${item.title}" saved to your designs');
      final host = widget.hostContext;
      Navigator.of(context).pop();
      if (host.mounted) host.go('/creatives');
    } catch (err) {
      debugPrint('❌ [templates] save threw: $err');
      Toast.error("Couldn't save this template. Please try again.");
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: templateShareUrl(_item)));
    if (!mounted) return;
    setState(() => _copied = true);
    Toast.success('Template link copied');
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// The web offers email, Facebook and LinkedIn buttons; the system share
  /// sheet covers all three (and every other app) in one tap.
  Future<void> _share(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: "Thought you'd like this template on Creative Klux:\n\n${_item.title}\n${templateShareUrl(_item)}",
          subject: 'Template: ${_item.title}',
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      Toast.error("Couldn't open the share sheet.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final item = _item;
    final size = formatSize(item);
    final tags = buildTags(item);
    final specs = buildSpecs(item);
    final related = pickRelatedItems(item, widget.pool);
    final screenH = MediaQuery.sizeOf(context).height;

    Widget heading(String text) => Row(
      children: [
        Container(width: 7, height: 7, color: AppColors.blue600),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray900),
        ),
      ],
    );

    return Stack(
      children: [
        ListView(
          controller: _scroll,
          padding: EdgeInsets.zero,
          children: [
            // ── Preview — repainted large; the card's paint holds the space.
            Container(
              height: (screenH * 0.42).clamp(260.0, 520.0),
              color: c.page,
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: TemplateArtwork(key: ValueKey(item.cacheKey), item: item, cache: widget.cache, hiRes: true),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3, color: c.gray900),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: item.premium ? c.gray900 : AppColors.blue500.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.premium ? 'PREMIUM' : 'FREE',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: item.premium ? c.surface : AppColors.blue600,
                          ),
                        ),
                      ),
                      if (item.format != null) Text(item.format!, style: TextStyle(fontSize: 12.5, color: c.gray500)),
                      if (size != null) ...[
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(color: c.gray300, shape: BoxShape.circle),
                        ),
                        Text(size, style: TextStyle(fontSize: 12.5, color: c.gray500)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Primary action — copies the template into the brand's designs.
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: c.gray900,
                        foregroundColor: c.surface,
                        disabledBackgroundColor: c.gray900.withValues(alpha: 0.6),
                        disabledForegroundColor: c.surface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      icon: _saving
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: c.surface),
                            )
                          : const Icon(LucideIcons.save, size: 16),
                      label: Text(_saving ? 'Saving…' : 'Save to Designs'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(describeItem(item), style: TextStyle(fontSize: 13.5, height: 1.55, color: c.gray600)),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in tags)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: c.gray200),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: c.gray600),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (specs.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    heading('Specs'),
                    const SizedBox(height: 10),
                    Divider(height: 1, color: c.gray200),
                    for (final (label, value) in specs) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Text(label, style: TextStyle(fontSize: 13, color: c.gray500)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                value,
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray900),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: c.gray200),
                    ],
                  ],
                  const SizedBox(height: 22),
                  heading('Share'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _ShareButton(
                        icon: _copied ? LucideIcons.check : LucideIcons.link2,
                        label: _copied ? 'Link copied' : 'Copy link',
                        onTap: _copyLink,
                      ),
                      const SizedBox(width: 8),
                      Builder(
                        builder: (bc) =>
                            _ShareButton(icon: LucideIcons.share2, label: 'Share', onTap: () => _share(bc)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            // ── More like this — the same TemplateCard the grid uses.
            if (related.isNotEmpty) ...[
              Divider(height: 1, color: c.gray200),
              Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 12), child: heading('More like this')),
              SizedBox(
                height: TemplateCard.cellExtent(156),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: related.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => SizedBox(
                    width: 156,
                    child: TemplateCard(item: related[i], cache: widget.cache, onOpen: () => _select(related[i])),
                  ),
                ),
              ),
              SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
            ],
          ],
        ),
        // Close — over the sheet's top-right corner.
        Positioned(
          right: 10,
          top: 10,
          child: Material(
            color: c.surface.withValues(alpha: 0.85),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).pop(),
              child: SizedBox(width: 34, height: 34, child: Icon(LucideIcons.x, size: 17, color: c.gray600)),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.gray200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: c.gray600),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.gray700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
