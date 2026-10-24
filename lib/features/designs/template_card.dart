import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/design/design_renderer.dart';
import '../../core/theme/app_colors.dart';
import 'templates_api.dart';

// Port of the web's app/(components)/studio/TemplateCard.jsx — THE card for a
// Klux template, used by the Templates grid AND the details sheet's "More like
// this" strip, so the two can't drift apart.
//
// ⚠️ WHAT THE CARD CAN SHOW IS CAPPED BY THE DATA. The pool sends no author,
// rating or install count — only format, size, tier and dates — so the card
// shows the tier badge, the title, its subtitle and a date. Nothing invented.

/// Longest edge, in px, of a card preview. Same as the web's PREVIEW_MAX_DIM:
/// a 2-up phone grid never draws a card wider than this, and a full-size paint
/// per card (what DesignCanvas holds) would cost ~8 MB of bitmap each.
const _cardMaxDim = 480.0;

/// Longest edge of the details sheet's own repaint. The web uses 1400 too.
const detailMaxDim = 1400.0;

/// Paint a template's layout to a bitmap no larger than [maxDim] on its long side.
Future<ui.Image> paintTemplate(KluxTemplate t, double maxDim) {
  final w = (num.tryParse('${t.canvas['width']}') ?? 1080).toDouble();
  final h = (num.tryParse('${t.canvas['height']}') ?? 1080).toDouble();
  final ratio = math.min(1.0, maxDim / math.max(w, h));
  // Library templates are Scraive layouts — see scraive_compat.dart.
  return renderDesign(t.canvas, t.elements, scraive: true, pixelRatio: ratio);
}

/// Card previews, painted once per template and shared by every card that
/// shows it (the grid, the sheet's strip, the sheet's placeholder). Owned by
/// the screen and disposed with it. Callers get CLONES, so a card can dispose
/// its handle without pulling the bitmap out from under another one.
class TemplatePreviewCache {
  final _images = <String, ui.Image>{};
  final _pending = <String, Future<ui.Image?>>{};
  bool _disposed = false;

  /// A clone of the cached preview, or null if it isn't painted yet.
  ui.Image? peek(KluxTemplate t) => _images[t.cacheKey]?.clone();

  /// Paint (or join the paint already running) and return a clone; null on failure.
  Future<ui.Image?> load(KluxTemplate t) async {
    final key = t.cacheKey;
    final hit = _images[key];
    if (hit != null) return hit.clone();
    final image = await (_pending[key] ??= _paint(t));
    return image?.clone();
  }

  Future<ui.Image?> _paint(KluxTemplate t) async {
    try {
      final image = await paintTemplate(t, _cardMaxDim);
      if (_disposed) {
        image.dispose();
        return null;
      }
      _images[t.cacheKey] = image;
      return image;
    } catch (err) {
      debugPrint('❌ [templates] preview failed for "${t.title}": $err');
      return null;
    } finally {
      _pending.remove(t.cacheKey);
    }
  }

  void dispose() {
    _disposed = true;
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
  }
}

/// A template's artwork: the painted layout, letterboxed over a blurred copy of
/// itself so a portrait template reads as artwork rather than a crop (the web
/// card's backdrop trick). [hiRes] repaints at [detailMaxDim] for the sheet,
/// showing the cached card paint meanwhile so it never opens empty.
class TemplateArtwork extends StatefulWidget {
  const TemplateArtwork({super.key, required this.item, required this.cache, this.hiRes = false});

  final KluxTemplate item;
  final TemplatePreviewCache cache;
  final bool hiRes;

  @override
  State<TemplateArtwork> createState() => _TemplateArtworkState();
}

class _TemplateArtworkState extends State<TemplateArtwork> {
  ui.Image? _image;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(TemplateArtwork old) {
    super.didUpdateWidget(old);
    if (old.item.cacheKey != widget.item.cacheKey || old.hiRes != widget.hiRes) _resolve();
  }

  void _set(ui.Image? image) {
    _image?.dispose();
    _image = image;
  }

  Future<void> _resolve() async {
    final gen = ++_generation;
    _failed = false;
    _set(widget.cache.peek(widget.item));
    if (_image != null && !widget.hiRes) return;

    ui.Image? next;
    try {
      next = widget.hiRes ? await paintTemplate(widget.item, detailMaxDim) : await widget.cache.load(widget.item);
    } catch (err) {
      debugPrint('⚠️ [template-details] couldn\'t paint "${widget.item.title}" large: $err');
    }
    if (!mounted || gen != _generation) {
      next?.dispose();
      return;
    }
    setState(() {
      if (next != null) {
        _set(next);
      } else if (_image == null) {
        _failed = true;
      }
    });
  }

  @override
  void dispose() {
    _generation++;
    _set(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final image = _image;
    if (image == null) {
      if (_failed) {
        // Painting failed — the row's photo is the last resort, then an icon.
        final thumb = widget.item.thumbnail;
        if (thumb != null && thumb.startsWith('http')) {
          return CachedNetworkImage(
            imageUrl: thumb,
            fit: BoxFit.contain,
            errorWidget: (_, _, _) => _FailedTile(color: c.gray400),
          );
        }
        return _FailedTile(color: c.gray400);
      }
      return ColoredBox(color: c.gray200.withValues(alpha: 0.6));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // The SAME bitmap, zoomed and blurred, fills the letterbox with the
        // design's own colours instead of a flat plate. The 1.25 overshoot is
        // more than the blur radius, so no soft rim shows along the edges.
        ClipRect(
          child: Transform.scale(
            scale: 1.25,
            child: Opacity(
              opacity: 0.6,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: RawImage(image: image, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(widget.hiRes ? 16 : 0),
          child: RawImage(image: image, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
        ),
      ],
    );
  }
}

class _FailedTile extends StatelessWidget {
  const _FailedTile({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Center(child: Icon(LucideIcons.image, size: 20, color: color));
}

/// Relative-ish date label for a card's footer (the web's formatMeta).
String? formatMeta(String? value) {
  if (value == null || value.isEmpty) return null;
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  final days = DateTime.now().difference(date).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 30) return '$days days ago';
  if (days < 365) return '${days ~/ 30} months ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[date.month - 1]} ${date.year}';
}

/// One template card — artwork, title, format, then date + the arrow chip.
/// A card does NOT open the template: tapping opens its details sheet.
class TemplateCard extends StatelessWidget {
  const TemplateCard({super.key, required this.item, required this.cache, required this.onOpen});

  final KluxTemplate item;
  final TemplatePreviewCache cache;
  final VoidCallback onOpen;

  /// Artwork aspect (width / height). The web's 16:10 tile suits a wide
  /// desktop grid; on a 2-up phone grid it would shrink the (mostly portrait)
  /// templates to stamps.
  static const artAspect = 4 / 5;

  /// Grid cell height for a card [width] wide: the artwork at [artAspect]
  /// plus the padding, title, subtitle and footer rows.
  static double cellExtent(double width) => (width - 16) / artAspect + 100;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = formatMeta(item.meta);

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.gray200),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Expanded rather than a fixed ratio: the grid sizes the cell from
              // [cellExtent], and a larger system font then shrinks the artwork
              // instead of overflowing the text below it.
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ColoredBox(
                    color: c.blueTint,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        TemplateArtwork(item: item, cache: cache),
                        // surface-on-gray900 rather than white-on-black, so
                        // the chip inverts with dark mode and stays legible.
                        if (item.premium)
                          Positioned(
                            left: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: c.gray900.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'PREMIUM',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                  color: c.surface,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray900),
                ),
              ),
              if (item.subtitle != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 1, 2, 0),
                  child: Text(
                    item.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: c.gray500),
                  ),
                ),
              const SizedBox(height: 8),
              // Footer: date + the "View details" chip. There is no hover on a
              // phone, so the chip is just the arrow — the whole card is the target.
              Row(
                children: [
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      meta ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: c.gray500),
                    ),
                  ),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(color: c.gray900, borderRadius: BorderRadius.circular(7)),
                    child: Icon(LucideIcons.arrowRight, size: 14, color: c.surface),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A placeholder card with the real card's rhythm, so nothing shifts on load.
class TemplateCardSkeleton extends StatefulWidget {
  const TemplateCardSkeleton({super.key});

  @override
  State<TemplateCardSkeleton> createState() => _TemplateCardSkeletonState();
}

class _TemplateCardSkeletonState extends State<TemplateCardSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(4)),
      ),
    );

    return FadeTransition(
      opacity: Tween<double>(begin: 0.55, end: 1).animate(_pulse),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.gray200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 10),
            bar(0.7, 12),
            const SizedBox(height: 6),
            bar(0.5, 10),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}
