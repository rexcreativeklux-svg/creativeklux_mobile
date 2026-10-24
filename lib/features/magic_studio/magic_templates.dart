import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import 'magic_studio_types.dart';

/// The Templates canvas — examples to start from, and the viewer a card opens
/// into. Port of `magic-studio/TemplateGallery.jsx`, `TemplateDesign.jsx` and
/// the catalog loading of `mediaTemplates.js` / `textToImageTemplates.js`.
///
/// ⚠️ THE CATALOGS ARE GENERATED. `assets/magic_templates/<toolId>.json` is
/// written by `node tool/magic_templates/gen.mjs`, which imports the web's own
/// modules and runs their own shaping — don't hand-edit the JSON; change the
/// web catalog and regenerate.
///
/// ⚠️ THE MEDIA IS PEXELS, NOT OUR OUTPUT — free-licence photos and clips
/// standing in for our own renders, each with copy written to describe it. The
/// viewer credits the photographer, as Pexels asks.

// ── Catalogs ─────────────────────────────────────────────────────────────────

/// Which asset each tool reads. Text to Image and Stock Image share the photo
/// catalog (textToImageTemplates.js TEMPLATES_BY_TOOL), so it's written once.
const _catalogFiles = <String, String>{
  'text_to_image': 'text_to_image',
  'image-design': 'text_to_image',
  'social-design': 'social-design',
  'ad-design': 'ad-design',
  'image_to_variations': 'image_to_variations',
  'persona_generator': 'persona_generator',
  'text_to_video': 'text_to_video',
  'image_to_video': 'image_to_video',
  'script_to_voiceover': 'script_to_voiceover',
  'digital_human': 'digital_human',
  'video_effects': 'video_effects',
  'video_background_remover': 'video_background_remover',
  'video_enhancer': 'video_enhancer',
};

/// Whether a tool has a Templates canvas at all — known at once, without
/// loading anything, because the screen has to decide which canvas to open on
/// before the catalog can possibly have arrived (mediaTemplates.js `hasTemplates`).
bool magicToolHasTemplates(String toolId) => _catalogFiles.containsKey(toolId);

/// Parsed catalogs, kept so coming back to a tool doesn't re-read the asset.
final _loaded = <String, List<MagicTemplateEntry>>{};

/// A tool's templates, in a fresh random order on every call — so coming back
/// to a tool shows a different first screen rather than the same dozen cards
/// (the web shuffles once per mount; the screen calls this once per mount).
/// Empty for a tool with none, or if the asset fails to load.
Future<List<MagicTemplate>> loadMagicTemplates(String toolId) async {
  final file = _catalogFiles[toolId];
  if (file == null) return const [];
  var list = _loaded[file];
  if (list == null) {
    try {
      final raw = jsonDecode(await rootBundle.loadString('assets/magic_templates/$file.json')) as List;
      list = [for (final e in raw.whereType<Map>()) MagicTemplateEntry.fromJson(e.cast<String, dynamic>())];
      _loaded[file] = list;
    } catch (err) {
      debugPrint('❌ [magic-studio] templates for $toolId failed: $err');
      // An empty canvas rather than a skeleton that never resolves.
      return const [];
    }
  }
  return [...list]..shuffle(math.Random());
}

/// A Social / Ads template's `design` block (designTemplates.js):
/// the copy laid over the photo, and how.
class MagicTemplateDesign {
  const MagicTemplateDesign({
    required this.format,
    required this.layout,
    required this.theme,
    required this.font,
    required this.accent,
    required this.headline,
    this.eyebrow,
    this.body,
    this.cta,
    this.badge,
    this.handle,
  });

  factory MagicTemplateDesign.fromJson(Map<String, dynamic> j) => MagicTemplateDesign(
    format: '${j['format'] ?? 'square'}',
    layout: '${j['layout'] ?? 'bottom'}',
    theme: '${j['theme'] ?? 'dark'}',
    font: '${j['font'] ?? 'sans'}',
    accent: _hex(j['accent']) ?? AppColors.blue600,
    headline: '${j['headline'] ?? ''}',
    eyebrow: j['eyebrow'] as String?,
    body: j['body'] as String?,
    cta: j['cta'] as String?,
    badge: j['badge'] as String?,
    handle: j['handle'] as String?,
  );

  /// "square" | "portrait" — a Text to Image `ratio` value.
  final String format;

  /// "top" | "bottom" | "center".
  final String layout;

  /// "dark" (white copy on a dark scrim) | "light".
  final String theme;

  /// "sans" | "serif".
  final String font;
  final Color accent;
  final String headline;
  final String? eyebrow, body, cta, badge, handle;

  bool get dark => theme != 'light';
  bool get portrait => format == 'portrait';
}

Color? _hex(Object? v) {
  final s = '${v ?? ''}'.replaceFirst('#', '');
  final n = int.tryParse(s.length == 3 ? s.split('').map((c) => '$c$c').join() : s, radix: 16);
  return n == null || (s.length != 6 && s.length != 3) ? null : Color(0xFF000000 | n);
}

/// A [MagicTemplate] plus what only the gallery's cards read: the card-sized
/// still, the photographer credit, and the design block a Social / Ads card is
/// drawn from. [MagicTemplate.title] carries the web's `formatLabel`.
class MagicTemplateEntry extends MagicTemplate {
  const MagicTemplateEntry({
    required super.id,
    required super.prompt,
    super.title,
    super.image,
    super.video,
    super.aspectRatio,
    super.values,
    super.sourceImage,
    super.sourceVideo,
    super.designFormat,
    super.category,
    this.thumb,
    this.credit,
    this.link,
    this.design,
  });

  factory MagicTemplateEntry.fromJson(Map<String, dynamic> j) => MagicTemplateEntry(
    id: '${j['id']}',
    prompt: '${j['prompt'] ?? ''}',
    title: j['title'] as String?,
    image: j['image'] as String?,
    video: j['video'] as String?,
    aspectRatio: (j['aspectRatio'] as num?)?.toDouble(),
    values: (j['values'] as Map?)?.cast<String, dynamic>(),
    sourceImage: j['sourceImage'] as String?,
    sourceVideo: j['sourceVideo'] as String?,
    designFormat: j['designFormat'] as String?,
    category: j['category'] as String?,
    thumb: j['thumb'] as String?,
    credit: j['credit'] as String?,
    link: j['link'] as String?,
    design: j['design'] is Map ? MagicTemplateDesign.fromJson((j['design'] as Map).cast<String, dynamic>()) : null,
  );

  /// Card-sized still (600px; 900 for a design). [image] is the viewer's 1600px.
  final String? thumb;
  final String? credit;

  /// The photo / clip's pexels.com page.
  final String? link;
  final MagicTemplateDesign? design;
}

String? _thumbOf(MagicTemplate t) => (t is MagicTemplateEntry ? t.thumb : null) ?? t.image;
MagicTemplateDesign? _designOf(MagicTemplate t) => t is MagicTemplateEntry ? t.design : null;

// ── Gallery ──────────────────────────────────────────────────────────────────

int _columnsFor(double width) => width >= 1024
    ? 4
    : width >= 600
    ? 3
    : 2;

const _gap = 10.0;
const _gutter = 16.0;

/// The masonry of examples. ⚠️ A SLIVER, like MagicLattice, so the screen can
/// swap one for the other in the same CustomScrollView.
///
/// ⚠️ MASONRY, NOT THE HISTORY LATTICE. The lattice crops every cell to one
/// wide shape; templates are there to be LOOKED AT before you pick one, and a
/// portrait cropped to 3:2 loses the face — so each card keeps its own shape,
/// reserved up front from the catalog so the columns don't jump as images
/// arrive. Columns are filled shortest-first.
///
/// TWO TARGETS PER CARD: the picture opens the viewer, Use hands the template
/// to the composer. Use is always shown — there is no hover on a phone.
class MagicTemplateGallery extends StatelessWidget {
  const MagicTemplateGallery({super.key, required this.templates, required this.onUse, this.bottomPadding = 0});

  final List<MagicTemplate> templates;

  /// Put it in the composer (the web's `applyTemplate`; see [MagicTemplate.toRefill]).
  final ValueChanged<MagicTemplate> onUse;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(_gutter, 12, _gutter, 12 + bottomPadding),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final columns = _columnsFor(constraints.crossAxisExtent + _gutter * 2);
          final colWidth = (constraints.crossAxisExtent - _gap * (columns - 1)) / columns;
          final cols = List.generate(columns, (_) => <int>[]);
          final heights = List.filled(columns, 0.0);
          for (var i = 0; i < templates.length; i++) {
            var shortest = 0;
            for (var c = 1; c < columns; c++) {
              if (heights[c] < heights[shortest] - 0.5) shortest = c;
            }
            cols[shortest].add(i);
            heights[shortest] += colWidth / (templates[i].aspectRatio ?? 1) + _gap;
          }
          return SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) const SizedBox(width: _gap),
                  Expanded(
                    child: Column(
                      children: [
                        for (final i in cols[c])
                          Padding(
                            padding: const EdgeInsets.only(bottom: _gap),
                            child: _TemplateCard(
                              template: templates[i],
                              onOpen: () => _openViewer(context, templates, i, onUse),
                              onUse: () => onUse(templates[i]),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The canvas while a catalog is still loading — same columns as the real
/// thing, so the cards arrive into the places these were holding.
class MagicTemplateGallerySkeleton extends StatelessWidget {
  const MagicTemplateGallerySkeleton({super.key, this.bottomPadding = 0});

  final double bottomPadding;

  static const _aspects = [3 / 4, 16 / 9, 1.0, 9 / 16, 4 / 3, 16 / 9, 3 / 4, 1.0, 16 / 9, 9 / 16, 4 / 3, 3 / 4];

  @override
  Widget build(BuildContext context) {
    return MagicTemplateGallery(
      templates: [
        for (var i = 0; i < _aspects.length; i++)
          MagicTemplate(id: 'skeleton-$i', prompt: '', aspectRatio: _aspects[i]),
      ],
      onUse: (_) {},
      bottomPadding: bottomPadding,
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onOpen, required this.onUse});

  final MagicTemplate template;
  final VoidCallback onOpen;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final t = template;
    final c = context.colors;
    final skeleton = t.prompt.isEmpty && t.image == null;
    final design = _designOf(t);
    final thumb = _thumbOf(t);

    return AspectRatio(
      aspectRatio: t.aspectRatio ?? 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: c.gray100,
          child: skeleton
              ? const SizedBox.expand()
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      onTap: onOpen,
                      child: _Lazy(
                        id: t.id,
                        child: design != null
                            ? MagicTemplateDesignView(template: t, design: design, src: thumb)
                            : t.video != null
                            // Plays only while on screen — a canvas is a hundred
                            // clips, and the ones you scrolled past go back to
                            // being a poster.
                            ? AutoplayVideo(url: t.video!, poster: thumb ?? '', posterWidth: 600)
                            : thumb == null
                            ? const SizedBox.expand()
                            : MediaImage(thumb, cacheWidth: 600),
                      ),
                    ),
                    // ⚠️ NOT ON A DESIGN. Its copy is the point of the card, and
                    // a scrim would sit right on the headline and CTA — so a
                    // design gets a bare Use in the corner instead.
                    if (design == null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(9, 28, 7, 8),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xBF000000), Color(0x59000000), Color(0x00000000)],
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: IgnorePointer(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if ((t.title ?? '').isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 2),
                                          child: Text(
                                            t.title!.toUpperCase(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        t.prompt,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11, height: 1.3, color: Color(0xE6FFFFFF)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _UseButton(onTap: onUse),
                            ],
                          ),
                        ),
                      )
                    else
                      Positioned(right: 7, bottom: 7, child: _UseButton(onTap: onUse)),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Builds [child] only once the card has come near the screen, and keeps it
/// after — so opening a hundred-card canvas doesn't start a hundred downloads
/// for cards nobody has scrolled to (the web's `loading="lazy"`).
class _Lazy extends StatefulWidget {
  const _Lazy({required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  State<_Lazy> createState() => _LazyState();
}

class _LazyState extends State<_Lazy> {
  bool _seen = false;

  @override
  Widget build(BuildContext context) {
    if (_seen) return widget.child;
    return VisibilityDetector(
      key: ValueKey('lazy-${widget.id}'),
      onVisibilityChanged: (info) {
        if (!_seen && info.visibleFraction > 0 && mounted) setState(() => _seen = true);
      },
      child: const SizedBox.expand(),
    );
  }
}

class _UseButton extends StatelessWidget {
  const _UseButton({required this.onTap, this.large = false});

  final VoidCallback onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.blue600,
      shape: const StadiumBorder(),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        // On the card it's a small round ✨: a "Use" pill sat on top of the
        // design's own headline on a 2-column phone grid. Tapping the card
        // opens the viewer, whose big "Use this" says it in words.
        child: Padding(
          padding: large ? const EdgeInsets.symmetric(horizontal: 18, vertical: 11) : const EdgeInsets.all(7),
          child: !large
              ? const Tooltip(
                  message: 'Use this template',
                  child: Icon(LucideIcons.sparkles, size: 15, color: Colors.white),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.sparkles, size: large ? 15 : 12.5, color: Colors.white),
                    SizedBox(width: large ? 6 : 4),
                    Text(
                      large ? 'Use this' : 'Use',
                      style: TextStyle(fontSize: large ? 13.5 : 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── TemplateDesign.jsx ───────────────────────────────────────────────────────

/// A Social or Ads template drawn as the design it stands for: its photo,
/// cropped to its format, with the copy from its `design` block over a scrim.
///
/// ⚠️ TYPE IS SIZED AS A SHARE OF THE WIDTH (the web's `cqw`), not in px. The
/// same design is a ~170px card on a phone and a full-width panel in the viewer,
/// and it has to look like the same design in both.
class MagicTemplateDesignView extends StatelessWidget {
  const MagicTemplateDesignView({super.key, required this.template, required this.design, this.src});

  final MagicTemplate template;
  final MagicTemplateDesign design;

  /// Which size of the photo to draw.
  final String? src;

  @override
  Widget build(BuildContext context) {
    final d = design;
    return AspectRatio(
      aspectRatio: template.aspectRatio ?? (d.portrait ? 9 / 16 : 1),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          double q(double pct) => w * pct / 100;
          final ink = d.dark ? Colors.white : const Color(0xFF111827);
          final serif = d.font == 'serif';
          // A center layout gets a panel behind the copy on light photos — a pale
          // scrim alone over a busy pattern doesn't hold dark type.
          final panel = d.layout == 'center' && !d.dark;
          final center = d.layout == 'center';
          final image = src ?? _thumbOf(template);

          final copy = Container(
            padding: panel ? EdgeInsets.symmetric(horizontal: q(6), vertical: q(7)) : EdgeInsets.zero,
            constraints: BoxConstraints(maxWidth: d.badge != null ? q(70) : double.infinity),
            decoration: panel
                ? BoxDecoration(
                    color: const Color(0xD9FFFFFF),
                    borderRadius: BorderRadius.circular(q(3)),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 10))],
                  )
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                if (d.eyebrow != null) ...[
                  Text(
                    d.eyebrow!.toUpperCase(),
                    textAlign: center ? TextAlign.center : TextAlign.start,
                    style: TextStyle(
                      color: d.accent,
                      fontSize: q(3.3),
                      fontWeight: FontWeight.w700,
                      letterSpacing: q(3.3) * 0.14,
                    ),
                  ),
                  SizedBox(height: q(2.4)),
                ],
                Text(
                  d.headline,
                  textAlign: center ? TextAlign.center : TextAlign.start,
                  style: TextStyle(
                    color: ink,
                    fontSize: q(d.portrait ? 10.5 : 8.6),
                    height: 1.04,
                    fontWeight: serif ? FontWeight.w600 : FontWeight.w800,
                    fontFamily: serif ? 'serif' : null,
                    fontFamilyFallback: serif ? const ['Georgia', 'Times New Roman'] : null,
                    letterSpacing: q(d.portrait ? 10.5 : 8.6) * (serif ? -0.01 : -0.03),
                  ),
                ),
                if (d.body != null) ...[
                  SizedBox(height: q(2.4)),
                  Text(
                    d.body!,
                    textAlign: center ? TextAlign.center : TextAlign.start,
                    style: TextStyle(color: ink.withValues(alpha: 0.88), fontSize: q(3.9), height: 1.35),
                  ),
                ],
                if (d.cta != null) ...[
                  SizedBox(height: q(2.4) + q(1.5)),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: q(5), vertical: q(2.2)),
                    decoration: BoxDecoration(
                      color: d.accent,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [BoxShadow(color: Color(0x29000000), blurRadius: 6, offset: Offset(0, 3))],
                    ),
                    // The accent is chosen to read on the photo, so the button's
                    // own text takes whichever of black or white the copy isn't.
                    child: Text(
                      d.cta!,
                      style: TextStyle(
                        color: d.dark ? const Color(0xFF111827) : Colors.white,
                        fontSize: q(3.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );

          final pad = d.portrait ? EdgeInsets.symmetric(horizontal: q(8), vertical: q(9)) : EdgeInsets.all(q(7));

          return Stack(
            fit: StackFit.expand,
            children: [
              if (image != null) MediaImage(image, cacheWidth: 900),
              DecoratedBox(decoration: _scrim(d)),
              if (d.badge != null)
                Positioned(
                  right: q(6),
                  top: q(6),
                  child: Container(
                    width: q(19),
                    height: q(19),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: d.accent,
                      shape: BoxShape.circle,
                      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 6))],
                    ),
                    child: Text(
                      d.badge!,
                      style: TextStyle(fontSize: q(5.4), fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                ),
              Padding(
                // Room for the handle under copy that sits at the bottom.
                padding: pad.copyWith(bottom: d.handle != null ? q(13) : null),
                child: Align(
                  alignment: switch (d.layout) {
                    'top' => Alignment.topLeft,
                    'center' => Alignment.center,
                    _ => Alignment.bottomLeft,
                  },
                  child: copy,
                ),
              ),
              if (d.handle != null)
                Positioned(
                  bottom: q(d.portrait ? 6 : 5),
                  left: center ? 0 : q(d.portrait ? 8 : 7),
                  right: center ? 0 : null,
                  child: Text(
                    d.handle!,
                    textAlign: center ? TextAlign.center : TextAlign.start,
                    style: TextStyle(color: ink.withValues(alpha: 0.85), fontSize: q(3.1), fontWeight: FontWeight.w500),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static BoxDecoration _scrim(MagicTemplateDesign d) {
    final base = d.dark ? Colors.black : Colors.white;
    Color a(double v) => base.withValues(alpha: v);
    return switch (d.layout) {
      'center' => BoxDecoration(color: a(d.dark ? 0.35 : 0.25)),
      'top' => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: d.dark ? [a(0.7), a(0.3), a(0)] : [a(0.85), a(0.4), a(0)],
        ),
      ),
      _ => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: d.dark ? [a(0.75), a(0.35), a(0)] : [a(0.9), a(0.45), a(0)],
        ),
      ),
    };
  }
}

// ── Viewer ───────────────────────────────────────────────────────────────────

void _openViewer(BuildContext context, List<MagicTemplate> templates, int index, ValueChanged<MagicTemplate> onUse) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _TemplateViewer(
        templates: templates,
        initial: index,
        onUse: (t) {
          Navigator.of(context).pop();
          onUse(t);
        },
      ),
    ),
  );
}

/// One template, full screen: the picture, contained rather than cropped (the
/// one place the whole frame is shown), and under it the whole prompt with Use
/// this and Download. Swipe for the rest; it wraps at both ends.
class _TemplateViewer extends StatefulWidget {
  const _TemplateViewer({required this.templates, required this.initial, required this.onUse});

  final List<MagicTemplate> templates;
  final int initial;
  final ValueChanged<MagicTemplate> onUse;

  @override
  State<_TemplateViewer> createState() => _TemplateViewerState();
}

class _TemplateViewerState extends State<_TemplateViewer> {
  // A large virtual page count, started in the middle, so swiping wraps at
  // both ends — the web's arrows never dead-end either.
  static const _loops = 1000;
  late final int _count = widget.templates.length;
  late final PageController _pages = PageController(initialPage: _count * (_loops ~/ 2) + widget.initial);
  late int _index = widget.initial;
  bool _downloading = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _download(MagicTemplate t) async {
    final url = t.image;
    if (url == null || _downloading) return;
    setState(() => _downloading = true);
    Toast.info('Downloading…');
    try {
      final res = await Dio().get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImageBytes(Uint8List.fromList(res.data ?? const []), name: 'template-${t.id}');
      Toast.success('Saved to your photo gallery');
    } catch (err) {
      debugPrint('❌ [magic-studio] template download failed: $err');
      Toast.error("Couldn't download that image");
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = widget.templates[_index];
    final design = _designOf(t);
    final entry = t is MagicTemplateEntry ? t : null;

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Close',
          icon: Icon(LucideIcons.x, size: 20, color: c.gray600),
        ),
        centerTitle: true,
        title: Text(
          '${_index + 1} of $_count',
          style: TextStyle(fontSize: 12.5, color: c.gray400, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _count * _loops,
                onPageChanged: (p) => setState(() => _index = p % _count),
                itemBuilder: (_, p) {
                  final it = widget.templates[p % _count];
                  final d = _designOf(it);
                  final aspect = it.aspectRatio ?? 1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _gutter, vertical: 8),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: aspect,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ColoredBox(
                            color: c.gray100,
                            child: d != null
                                ? MagicTemplateDesignView(template: it, design: d, src: it.image)
                                : it.video != null
                                // The clip itself, playing — the one place you
                                // watch it rather than glimpse it.
                                ? AutoplayVideo(url: it.video!, poster: it.image ?? _thumbOf(it) ?? '')
                                : InteractiveViewer(
                                    maxScale: 4,
                                    child: MediaImage(it.image ?? _thumbOf(it) ?? '', fit: BoxFit.contain),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.36),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(_gutter, 8, _gutter, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((t.title ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          t.title!.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: AppColors.blue600,
                          ),
                        ),
                      ),
                    Text(t.prompt, style: TextStyle(fontSize: 13.5, height: 1.55, color: c.gray800)),
                    // Pexels asks for the photographer to be credited. Quiet, but there.
                    if (entry?.credit != null)
                      GestureDetector(
                        onTap: entry!.link == null
                            ? null
                            : () => launchUrl(Uri.parse(entry.link!), mode: LaunchMode.externalApplication),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '${t.video != null ? 'Video' : 'Photo'} by ${entry.credit} on Pexels',
                            style: TextStyle(fontSize: 11, color: c.gray400),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(_gutter, 4, _gutter, 12),
              child: Row(
                children: [
                  _UseButton(onTap: () => widget.onUse(t), large: true),
                  const SizedBox(width: 8),
                  // Not on a design: its copy is laid over the photo, so the
                  // file would be the bare photo — not what the card shows. Nor
                  // on a clip: it would save the still.
                  if (design == null && t.video == null)
                    OutlinedButton.icon(
                      onPressed: _downloading ? null : () => _download(t),
                      style: OutlinedButton.styleFrom(
                        shape: const StadiumBorder(),
                        side: BorderSide(color: c.gray200),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      ),
                      icon: Icon(LucideIcons.download, size: 15, color: c.gray700),
                      label: Text(
                        'Download',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray700),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
