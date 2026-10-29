import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import 'gallery_api.dart';
import 'media_actions.dart';

/// One entry of a card's actions menu (MenuItem in MediaCard.jsx).
class MediaAction {
  const MediaAction(this.label, this.icon, this.onTap, {this.danger = false});
  final String label;
  final IconData icon;
  final void Function(GalleryMedia item) onTap;
  final bool danger;
}

/// Port of components/gallery/MediaCard.jsx — one card for any gallery item
/// by its media type (image, video, audio, document), with the shared ⋮
/// actions menu (download / copy link / delete, plus any extras such as
/// "Save to gallery" on stock results).
///
/// Phone changes: the ⋮ button is always visible (there's no hover), and a
/// tap OPENS the item — images and videos full screen, documents in the
/// browser (the web's own behaviour for documents) — since a 2-column phone
/// tile is too small for the web's inline `<video controls>`.
class MediaCard extends StatelessWidget {
  const MediaCard({super.key, required this.item, this.index = 0, this.actions = const []});

  final GalleryMedia item;
  final int index;
  final List<MediaAction> actions;

  @override
  Widget build(BuildContext context) {
    final menu = actions.isEmpty ? null : MediaMenuButton(item: item, actions: actions);
    switch (item.type) {
      case 'audio':
        return AudioMediaCard(item: item, index: index, menu: menu);
      case 'video':
        return _Overlay(
          menu: menu,
          onTap: () => openVideoViewer(context, item, actions),
          child: _VideoTile(item: item),
        );
      case 'document':
        return _Overlay(
          menu: menu,
          onTap: () => openMediaExternally(item),
          child: _DocTile(item: item),
        );
      default:
        return _Overlay(
          menu: menu,
          onTap: () => openImageViewer(context, item, actions),
          child: _ImageTile(item: item),
        );
    }
  }
}

/// Rounded, bordered tile + the ⋮ menu in the corner.
class _Overlay extends StatelessWidget {
  const _Overlay({required this.child, required this.onTap, this.menu});
  final Widget child;
  final VoidCallback onTap;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.gray100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.gray100),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(onTap: onTap, child: child),
          ),
          if (menu != null) Positioned(top: 6, right: 6, child: menu!),
        ],
      ),
    );
  }
}

/// The dark round ⋮ button and its menu.
class MediaMenuButton extends StatelessWidget {
  const MediaMenuButton({super.key, required this.item, required this.actions, this.light = false});

  final GalleryMedia item;
  final List<MediaAction> actions;

  /// A plain grey icon (on a light card) instead of the dark disc (on media).
  final bool light;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<MediaAction>(
      tooltip: 'Actions',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      color: c.surface.withValues(alpha: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (a) => a.onTap(item),
      itemBuilder: (_) => [
        for (final a in actions)
          PopupMenuItem(
            value: a,
            height: 42,
            child: Row(
              children: [
                Icon(a.icon, size: 16, color: a.danger ? AppColors.red600 : c.gray700),
                const SizedBox(width: 10),
                Text(a.label, style: TextStyle(fontSize: 13.5, color: a.danger ? AppColors.red600 : c.gray700)),
              ],
            ),
          ),
      ],
      child: Container(
        width: 30,
        height: 30,
        decoration: light ? null : const BoxDecoration(color: Color(0x8C000000), shape: BoxShape.circle),
        child: Icon(LucideIcons.ellipsisVertical, size: 16, color: light ? c.gray500 : Colors.white),
      ),
    );
  }
}

/// An image at its own aspect ratio (it sits in a masonry column). A dead src
/// gets a square placeholder naming the file — a broken image at its tiny
/// intrinsic size read as an upload that was never fetched (MediaCard.jsx).
class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.item});
  final GalleryMedia item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CachedNetworkImage(
      imageUrl: item.src,
      width: double.infinity,
      fit: BoxFit.fitWidth,
      memCacheWidth: 500,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, _) => SizedBox(height: 170, child: ColoredBox(color: c.gray100)),
      errorWidget: (_, _, _) => AspectRatio(
        aspectRatio: 1,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.imageOff, size: 22, color: c.gray400),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                item.filename.isNotEmpty ? item.filename : 'Image unavailable',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, height: 1.2, color: c.gray400),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.item});
  final GalleryMedia item;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.poster != null)
              MediaImage(item.poster!, cacheWidth: 500)
            else
              const Center(child: Icon(LucideIcons.film, size: 26, color: Colors.white24)),
            Center(
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(color: Color(0xB3000000), shape: BoxShape.circle),
                child: const Icon(LucideIcons.play, size: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.item});
  final GalleryMedia item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AspectRatio(
      aspectRatio: 1,
      child: ColoredBox(
        color: c.gray50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.fileText, size: 34, color: AppColors.blue500),
              const SizedBox(height: 8),
              Text(
                item.filename.isNotEmpty ? item.filename : 'Document',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray700),
              ),
              const SizedBox(height: 3),
              Text(
                item.extBadge,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: c.gray400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Audio (port of components/gallery/AudioCard.jsx) ─────────────────────────

/// Placeholder amplitudes (FALLBACK_WAVE). The web decodes the real waveform
/// with Web Audio and falls back to these when it can't; the phone has no
/// decoder without a new package, so it always shows the placeholder.
const _fallbackWave = [
  8, 14, 20, 12, 24, 16, 10, 22, 18, 26, 14, 9, 20, 28, //
  16, 12, 22, 10, 18, 24, 14, 8, 20, 16, 26, 12, 18, 10,
];

String formatClock(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${s ~/ 60}:${'${s % 60}'.padLeft(2, '0')}';
}

/// Play/pause, ±10s skips, a waveform you tap or drag to scrub, elapsed /
/// total time, and mute + volume.
///
/// The player is created on the first Play, not on build: a page of 30
/// audio cards would otherwise open 30 network players. So the total time
/// reads 0:00 until the track is played once.
class AudioMediaCard extends StatefulWidget {
  const AudioMediaCard({super.key, required this.item, this.index = 0, this.menu});

  final GalleryMedia item;
  final int index;
  final Widget? menu;

  @override
  State<AudioMediaCard> createState() => _AudioMediaCardState();
}

class _AudioMediaCardState extends State<AudioMediaCard> {
  VideoPlayerController? _player;
  bool _starting = false;
  double _volume = 1;
  bool _muted = false;
  double? _drag;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Duration get _duration => _player?.value.duration ?? Duration.zero;
  Duration get _position => _player?.value.position ?? Duration.zero;
  bool get _playing => _player?.value.isPlaying ?? false;

  void _tick() {
    if (mounted) setState(() {});
  }

  Future<VideoPlayerController?> _ensure() async {
    if (_player != null) return _player;
    setState(() => _starting = true);
    final p = VideoPlayerController.networkUrl(Uri.parse(widget.item.src));
    try {
      await p.initialize();
      await p.setVolume(_muted ? 0 : _volume);
      p.addListener(_tick);
      if (!mounted) {
        p.dispose();
        return null;
      }
      setState(() {
        _player = p;
        _starting = false;
      });
      return p;
    } catch (err) {
      debugPrint('❌ [audio-card] audio playback failed: $err');
      p.dispose();
      if (mounted) setState(() => _starting = false);
      Toast.error("Couldn't play this audio — try downloading it instead.");
      return null;
    }
  }

  Future<void> _togglePlay() async {
    if (_starting) return;
    final p = await _ensure();
    if (p == null) return;
    if (p.value.isPlaying) {
      await p.pause();
      return;
    }
    // Replay from the top when sitting at the end.
    if (_duration > Duration.zero && _position >= _duration - const Duration(milliseconds: 50)) {
      await p.seekTo(Duration.zero);
    }
    await p.play();
  }

  void _seekBy(int seconds) {
    final p = _player;
    if (p == null || _duration == Duration.zero) return;
    final ms = (_position.inMilliseconds + seconds * 1000).clamp(0, _duration.inMilliseconds);
    p.seekTo(Duration(milliseconds: ms));
  }

  void _seekToFraction(double f) {
    final p = _player;
    if (p == null || _duration == Duration.zero) return;
    p.seekTo(Duration(milliseconds: (f.clamp(0.0, 1.0) * _duration.inMilliseconds).round()));
  }

  void _setVolume(double v) {
    setState(() {
      _volume = v;
      _muted = v == 0;
    });
    _player?.setVolume(v);
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _player?.setVolume(_muted ? 0 : _volume);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dur = _duration;
    final fraction =
        _drag ?? (dur.inMilliseconds > 0 ? (_position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0);
    final title = widget.item.filename.isNotEmpty ? widget.item.filename : 'Audio track ${widget.index + 1}';
    final volumeIcon = _muted || _volume == 0
        ? LucideIcons.volumeX
        : (_volume < 0.5 ? LucideIcons.volume1 : LucideIcons.volume2);

    Widget skip(IconData icon, String tip, VoidCallback onTap) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 17, color: c.gray500),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title (+ the ⋮ menu, in the row rather than over the title).
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.blue600.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(LucideIcons.audioLines, size: 15, color: AppColors.blue600),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray900),
                ),
              ),
              ?widget.menu,
            ],
          ),
          const SizedBox(height: 10),
          // Waveform — tap or drag to scrub.
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: LayoutBuilder(
              builder: (context, box) {
                double at(Offset p) => (p.dx / box.maxWidth).clamp(0.0, 1.0);
                final canSeek = dur > Duration.zero;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: canSeek ? (d) => _seekToFraction(at(d.localPosition)) : null,
                  onHorizontalDragStart: canSeek ? (d) => setState(() => _drag = at(d.localPosition)) : null,
                  onHorizontalDragUpdate: canSeek ? (d) => setState(() => _drag = at(d.localPosition)) : null,
                  onHorizontalDragEnd: canSeek
                      ? (_) {
                          _seekToFraction(_drag ?? 0);
                          setState(() => _drag = null);
                        }
                      : null,
                  child: SizedBox(
                    height: 48,
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            for (var i = 0; i < _fallbackWave.length; i++)
                              Expanded(
                                child: Center(
                                  child: Container(
                                    height: (_fallbackWave[i] / 28 * 40).clamp(2.0, 40.0),
                                    margin: const EdgeInsets.symmetric(horizontal: 1),
                                    decoration: BoxDecoration(
                                      color: (i + 0.5) / _fallbackWave.length <= fraction
                                          ? AppColors.blue500
                                          : AppColors.blue500.withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (canSeek)
                          Positioned(
                            left: (fraction * box.maxWidth - 1).clamp(0.0, box.maxWidth - 2),
                            top: 3,
                            bottom: 3,
                            child: Container(
                              width: 2,
                              decoration: BoxDecoration(
                                color: AppColors.blue600,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatClock(_drag != null ? dur * _drag! : _position),
                  style: TextStyle(fontSize: 11, color: c.gray400, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                Text(
                  formatClock(dur),
                  style: TextStyle(fontSize: 11, color: c.gray400, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Transport + volume.
          Row(
            children: [
              skip(LucideIcons.skipBack, 'Back 10 seconds', () => _seekBy(-10)),
              InkWell(
                onTap: _togglePlay,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.blue600, const Color(0xFF4F39F6)],
                    ),
                  ),
                  child: _starting
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(_playing ? LucideIcons.pause : LucideIcons.play, size: 19, color: Colors.white),
                ),
              ),
              skip(LucideIcons.skipForward, 'Forward 10 seconds', () => _seekBy(10)),
              const SizedBox(width: 4),
              skip(volumeIcon, _muted ? 'Unmute' : 'Mute', _toggleMute),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: AppColors.blue600,
                    thumbColor: AppColors.blue600,
                    inactiveTrackColor: c.gray200,
                  ),
                  child: Slider(value: _muted ? 0 : _volume, onChanged: _setVolume),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Masonry (port of components/gallery/MasonryGrid.jsx) ────────────────────

/// Column masonry: item i → column i % N, so a new page only extends the
/// columns and nothing already on screen jumps. While a page loads, a few
/// skeletons sit at the bottom of EVERY column.
///
/// Columns follow the grid's own width like the web (≥480 → 3, ≥700 → 4,
/// ≥950 → 5, else 2), so a 360dp phone gets two.
class MasonryColumns extends StatelessWidget {
  const MasonryColumns({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.loadingMore = false,
    this.skeletonPerColumn = 2,
    this.gap = 10,
  });

  final List<GalleryMedia> items;
  final Widget Function(GalleryMedia item, int index) itemBuilder;
  final bool loadingMore;
  final int skeletonPerColumn;
  final double gap;

  static const _skeletonHeights = [176.0, 224.0, 200.0, 256.0, 192.0, 240.0];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final cols = w >= 950 ? 5 : (w >= 700 ? 4 : (w >= 480 ? 3 : 2));
        final buckets = List.generate(cols, (_) => <int>[]);
        for (var i = 0; i < items.length; i++) {
          buckets[i % cols].add(i);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var col = 0; col < cols; col++) ...[
              if (col > 0) SizedBox(width: gap),
              Expanded(
                child: Column(
                  children: [
                    for (final i in buckets[col])
                      Padding(
                        key: ValueKey(items[i].id ?? i),
                        padding: EdgeInsets.only(bottom: gap),
                        child: itemBuilder(items[i], i),
                      ),
                    if (loadingMore)
                      for (var s = 0; s < skeletonPerColumn; s++)
                        Padding(
                          padding: EdgeInsets.only(bottom: gap),
                          child: Container(
                            height: _skeletonHeights[(col + s) % _skeletonHeights.length] * 0.8,
                            decoration: BoxDecoration(color: c.gray200, borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A greyed tile the shape of [type]'s card (GallerySkeleton.jsx).
class MediaSkeleton extends StatelessWidget {
  const MediaSkeleton({super.key, required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final box = Container(
      decoration: BoxDecoration(color: c.gray200, borderRadius: BorderRadius.circular(14)),
    );
    return switch (type) {
      'audio' => SizedBox(height: 150, child: box),
      'video' => AspectRatio(aspectRatio: 16 / 9, child: box),
      _ => AspectRatio(aspectRatio: 1, child: box),
    };
  }
}

// ── Full-screen viewers ──────────────────────────────────────────────────────
// Pushed on the ROOT navigator so they cover the bottom nav (see CLAUDE.md).

/// The card's actions, minus the ones that make no sense from inside the
/// viewer, shown in its top bar's ⋮ menu. Delete closes the viewer first.
List<MediaAction> _viewerActions(BuildContext context, List<MediaAction> actions) => [
  for (final a in actions)
    MediaAction(a.label, a.icon, (item) {
      if (a.danger) Navigator.of(context).pop();
      a.onTap(item);
    }, danger: a.danger),
];

void openImageViewer(BuildContext context, GalleryMedia item, List<MediaAction> actions) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (ctx, _, _) => _ViewerScaffold(
        item: item,
        actions: _viewerActions(ctx, actions),
        child: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: item.src,
              fit: BoxFit.contain,
              placeholder: (_, _) => const Center(child: CircularProgressIndicator(color: Colors.white54)),
              errorWidget: (_, _, _) => const Icon(LucideIcons.imageOff, color: Colors.white38, size: 32),
            ),
          ),
        ),
      ),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

void openVideoViewer(BuildContext context, GalleryMedia item, List<MediaAction> actions) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (ctx, _, _) => _ViewerScaffold(
        item: item,
        actions: _viewerActions(ctx, actions),
        child: _VideoPlayerView(url: item.src),
      ),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

class _ViewerScaffold extends StatelessWidget {
  const _ViewerScaffold({required this.item, required this.actions, required this.child});
  final GalleryMedia item;
  final List<MediaAction> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      item.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, color: Colors.white70),
                    ),
                  ),
                  if (actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: MediaMenuButton(item: item, actions: actions),
                    ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// A plain player with controls (the web's `<video controls>`).
class _VideoPlayerView extends StatefulWidget {
  const _VideoPlayerView({required this.url});
  final String url;

  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_tick);
    _c
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _ready = true);
          _c.play();
        })
        .catchError((Object err) {
          debugPrint('❌ [gallery] video failed: $err');
          if (mounted) setState(() => _failed = true);
        });
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Text("Couldn't play this video.", style: TextStyle(fontSize: 13.5, color: Colors.white70)),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator(color: Colors.white54));
    final v = _c.value;
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => v.isPlaying ? _c.pause() : _c.play(),
            child: Center(
              child: AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_c)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
          child: Row(
            children: [
              IconButton(
                onPressed: () => v.isPlaying ? _c.pause() : _c.play(),
                icon: Icon(v.isPlaying ? LucideIcons.pause : LucideIcons.play, color: Colors.white),
              ),
              Text(formatClock(v.position), style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
              const SizedBox(width: 10),
              Expanded(
                child: VideoProgressIndicator(
                  _c,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  colors: VideoProgressColors(
                    playedColor: AppColors.blue500,
                    bufferedColor: Colors.white30,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(formatClock(v.duration), style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
            ],
          ),
        ),
      ],
    );
  }
}
