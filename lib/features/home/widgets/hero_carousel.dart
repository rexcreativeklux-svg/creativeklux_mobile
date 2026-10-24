import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/ui/media.dart';
import '../home_catalog.dart';

/// The rounded, auto-advancing banner at the top of home: full-bleed image,
/// big white title, an outlined "Try ▶" pill, and page dots bottom-right.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key, required this.slides});

  final List<HeroSlide> slides;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  // A large initial page lets the user swipe backwards from the first slide.
  static const _loopBase = 1000;
  late final _controller = PageController(initialPage: _loopBase * widget.slides.length);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _startAutoplay();
  }

  void _startAutoplay() {
    _timer?.cancel();
    // Long enough to watch a bit of each slide's clip.
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!_controller.hasClients) return;
      _controller.nextPage(duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Pause autoplay while the user is dragging; resume after.
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) _timer?.cancel();
              if (n is ScrollEndNotification) _startAutoplay();
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _index = i % slides.length),
              // Only the slide in view plays its video.
              itemBuilder: (context, i) =>
                  _Slide(slide: slides[i % slides.length], active: i % slides.length == _index),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 22,
            child: Row(
              children: [
                for (var i = 0; i < slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(left: 6),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: i == _index ? 1 : 0.45),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.slide, required this.active});

  final HeroSlide slide;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(slide.path),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (slide.video != null)
            AutoplayVideo(url: slide.video!, poster: slide.image, enabled: active)
          else
            MediaImage(slide.image),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.45, 1],
                colors: [Colors.transparent, Color(0xB3000000)],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Column(
              children: [
                Text(
                  slide.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    shadows: [Shadow(color: Color(0x66000000), blurRadius: 12)],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.push(slide.path),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    side: const BorderSide(color: Colors.white, width: 1.4),
                    shape: const StadiumBorder(),
                    minimumSize: const Size(168, 38),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text(slide.cta), const SizedBox(width: 4), const Icon(LucideIcons.play, size: 14)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
