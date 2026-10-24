import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../theme/app_colors.dart';

/// An image from either the bundle (`assets/…`) or the network (cached), with
/// a neutral placeholder while it loads and if it fails.
class MediaImage extends StatelessWidget {
  const MediaImage(this.src, {super.key, this.fit = BoxFit.cover, this.cacheWidth});

  final String src;
  final BoxFit fit;

  /// Decode width in physical pixels — keeps memory down for thumbnails.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: context.colors.gray100);
    if (!src.startsWith('http')) {
      return Image.asset(src, fit: fit, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => placeholder);
    }
    return CachedNetworkImage(
      imageUrl: src,
      fit: fit,
      memCacheWidth: cacheWidth,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

/// A muted, looping video that only exists while it's on screen.
///
/// Shows [poster] immediately; once the widget is at least 60% visible (and
/// [enabled]) it spins up a player and fades the video in over the poster.
/// When it scrolls away the player is disposed, so a home screen with dozens
/// of video cards only ever has the handful you can see playing.
class AutoplayVideo extends StatefulWidget {
  const AutoplayVideo({super.key, required this.url, required this.poster, this.enabled = true, this.posterWidth});

  final String url;
  final String poster;

  /// Lets a parent (e.g. the hero carousel) play only its current page.
  final bool enabled;
  final int? posterWidth;

  @override
  State<AutoplayVideo> createState() => _AutoplayVideoState();
}

class _AutoplayVideoState extends State<AutoplayVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _visible = false;

  @override
  void didUpdateWidget(AutoplayVideo old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _release();
    _sync();
  }

  void _onVisibility(VisibilityInfo info) {
    if (!mounted) return;
    final visible = info.visibleFraction >= 0.6;
    final gone = info.visibleFraction < 0.05;
    if (visible) {
      _visible = true;
    } else if (gone) {
      _visible = false;
    }
    _sync(dispose: gone);
  }

  /// Start, pause or release the player to match visibility + [enabled].
  Future<void> _sync({bool dispose = false}) async {
    final shouldPlay = _visible && widget.enabled;
    if (dispose) {
      _release();
      return;
    }
    if (!shouldPlay) {
      _controller?.pause();
      return;
    }
    if (_controller != null) {
      if (_ready) _controller!.play();
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      if (!mounted || _controller != controller) {
        controller.dispose();
        return;
      }
      setState(() => _ready = true);
      if (_visible && widget.enabled) controller.play();
    } catch (err) {
      // Network hiccup or unsupported codec — the poster stays up.
      debugPrint('video failed (${widget.url}): $err');
      if (_controller == controller) _controller = null;
      controller.dispose();
    }
  }

  void _release() {
    final c = _controller;
    _controller = null;
    if (_ready && mounted) setState(() => _ready = false);
    _ready = false;
    c?.dispose();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return VisibilityDetector(
      key: ObjectKey(this),
      onVisibilityChanged: _onVisibility,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MediaImage(widget.poster, cacheWidth: widget.posterWidth),
          AnimatedOpacity(
            opacity: _ready ? 1 : 0,
            duration: const Duration(milliseconds: 350),
            child: _ready && controller != null
                ? ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller.value.size.width,
                        height: controller.value.size.height,
                        child: VideoPlayer(controller),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
