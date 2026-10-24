import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';

// Port of the web's app/(dashboard)/(pages)/designs/DesignsLayout.jsx — the
// old static poster gallery.
//
// On the web each poster is a hand-built HTML/CSS page, shown as a PNG from
// public/thumbnails/ in the grid and as the live HTML in a modal. Those pages
// aren't editable designs (no layout JSON, nothing to save), so the app ships
// only the PNGs (assets/images/posters/) and opens them full-screen with pinch
// zoom, plus download and share — the HTML version has nothing more to show.

const _dir = 'assets/images/posters';

/// The web's `designComponents` list, same order. Only the thumbnail file is
/// kept; titles are derived from it, since the web's `name`s are raw ids
/// ("Silent-Factors-Poster", "ViralTrendsPoster").
const posterFiles = [
  'corporate-poster',
  'MarketValuePoster',
  'SilentFactorsPoster',
  'ViralTrendsPoster',
  'AssetsPeakPricePoster',
  'MarketValuePricePoster',
  'MarketValueReflectsPoster',
  'InvisibleFactorsPoster',
  'RealLifeExamplePoster',
  'FactorsAffectPoster',
  'RedefineValuePoster',
  'ThreeDriversPoster',
  'MarketValueEasyPoster',
  'BrandBoosterPoster',
  'StrugglingResultsPoster',
  'NoEngagementPoster',
  'WeHandleItAllPoster',
  'BenefitsCardPoster',
  'GrowBrandPoster',
  'TestimonialPoster',
  'ClientTestimonialPoster',
  'WhyCustomersStayPoster',
  'PurpleMarketValueMissingPoster',
  'PurpleMarketValueCompassPoster',
  'PurpleShowValuePoster',
  'PurpleMarketValuePoster',
  'UnlockTrueValuePoster',
  'StrategyValuationPoster',
  'MoreThanNumbersPoster',
  'ClientSuccessStoryPoster',
  'BoostMarketValuePoster',
  'BuildTrustValuePoster',
  'SitBackRelaxPoster',
  'RealizeDreamsPoster',
  'TestimonialWordPoster',
  'FamilyDreamsPoster',
  'HappyHomeGuidePoster',
  'LuxuryHouseSalePoster',
  'MarketCompassTimelinePoster',
  'SpeakerGuestStarPoster',
  'CustomersAttractionPoster',
  'MarketValuesMissingPoster',
  'HonestyTestimonialsPoster',
  'EmbedValuesPoster',
  'StoriesProveGrowthPoster',
  'TrustedTeamsTestimonialPoster',
  'BrandFeelsAlivePoster',
  'RealStoriesImpactPoster',
  'GrowthCampaignViralPoster',
];

String posterAsset(String file) => '$_dir/$file.png';

/// "MarketValueEasyPoster" → "Market Value Easy"; "corporate-poster" → "Corporate".
String posterTitle(String file) {
  final base = file.replaceAll(RegExp(r'[-_]?poster$', caseSensitive: false), '');
  final words = base
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .split(RegExp(r'[-_\s]+'))
      .where((w) => w.isNotEmpty);
  return words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
}

/// The Posters tab: a grid of the PNGs. Every poster is ~4:5, cropped from
/// the top like the web's `object-cover object-top`.
class PostersGrid extends StatelessWidget {
  const PostersGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1024 ? 4 : (width >= 640 ? 3 : 2);
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          sliver: SliverToBoxAdapter(
            child: Text(
              '${posterFiles.length} ready-made posters. Tap one to view it full size.',
              style: TextStyle(fontSize: 12.5, color: c.gray500),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 4 / 5,
            ),
            itemCount: posterFiles.length,
            itemBuilder: (context, i) {
              final file = posterFiles[i];
              return Material(
                color: c.gray200,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                elevation: 1,
                shadowColor: Colors.black26,
                child: InkWell(
                  onTap: () => openPosterViewer(context, i),
                  child: Image.asset(
                    posterAsset(file),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    // Decode at grid size — the full PNGs go up to 838px wide.
                    cacheWidth: (width / columns * dpr).round(),
                    semanticLabel: posterTitle(file),
                    errorBuilder: (_, _, _) => Center(child: Icon(LucideIcons.image, size: 20, color: c.gray400)),
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

/// Full-screen viewer, swipeable between posters, pinch to zoom. Pushed on the
/// ROOT navigator so it covers the shell's bottom nav. Always black, in both
/// themes, like any photo viewer.
void openPosterViewer(BuildContext context, int index) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, _, _) => _PosterViewer(initial: index),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _PosterViewer extends StatefulWidget {
  const _PosterViewer({required this.initial});

  final int initial;

  @override
  State<_PosterViewer> createState() => _PosterViewerState();
}

class _PosterViewerState extends State<_PosterViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  bool _busy = false;

  /// Zoomed in → swiping would fight the pan, so paging is locked until the
  /// poster is back at 1×.
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  String get _file => posterFiles[_index];

  Future<Uint8List> _bytes() async {
    final data = await rootBundle.load(posterAsset(_file));
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _bytes();
      if (!await Gal.hasAccess(toAlbum: false)) await Gal.requestAccess();
      await Gal.putImageBytes(bytes, name: 'creativeklux-${_file.toLowerCase()}');
      Toast.success('Poster saved to your gallery ✓');
    } catch (err) {
      debugPrint('poster download failed: $err');
      Toast.error('Download failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    try {
      final bytes = await _bytes();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/png')],
          fileNameOverrides: ['$_file.png'],
          subject: posterTitle(_file),
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      Toast.error("Couldn't share this poster.");
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget action(IconData icon, String tip, VoidCallback? onTap) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon, size: 20, color: Colors.white),
      style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.12)),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
            itemCount: posterFiles.length,
            onPageChanged: (i) => setState(() {
              _index = i;
              _zoomed = false;
            }),
            itemBuilder: (_, i) => _ZoomablePoster(
              file: posterFiles[i],
              onZoomChanged: (z) {
                if (z != _zoomed) setState(() => _zoomed = z);
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  action(LucideIcons.x, 'Close', () => Navigator.of(context).pop()),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          posterTitle(_file),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        Text(
                          '${_index + 1} of ${posterFiles.length}',
                          style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
                  Builder(builder: (bc) => action(LucideIcons.share2, 'Share', () => _share(bc))),
                  const SizedBox(width: 6),
                  _busy
                      ? const SizedBox(
                          width: 48,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                          ),
                        )
                      : action(LucideIcons.download, 'Download', _download),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomablePoster extends StatefulWidget {
  const _ZoomablePoster({required this.file, required this.onZoomChanged});

  final String file;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePoster> createState() => _ZoomablePosterState();
}

class _ZoomablePosterState extends State<_ZoomablePoster> {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _transform,
      minScale: 1,
      maxScale: 5,
      onInteractionEnd: (_) => widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.01),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 64),
          child: Image.asset(posterAsset(widget.file), fit: BoxFit.contain),
        ),
      ),
    );
  }
}
