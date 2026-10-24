import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/auth_controller.dart';

/// Holds the router on `/splash` until the opening animation has played.
/// The router redirects away once BOTH this is done and the stored session
/// has been confirmed (see app_router.dart).
class IntroGate extends ChangeNotifier {
  bool _done = false;
  bool get done => _done;

  void finish() {
    if (_done) return;
    _done = true;
    notifyListeners();
  }
}

/// Launch-screen navy — the same colour as the native splash
/// (`android/app/src/main/res/values/colors.xml`, iOS LaunchScreen), so the
/// hand-over from the OS splash to this screen is invisible.
const _navy = Color(0xFF0A1A55);
const _glow = Color(0xFF1E4FE0);

/// The opening animation. It starts on the native splash's exact frame — the
/// logo in a white circle on navy — then the design posters fly in and fan
/// out around it, the name rises underneath, and everything clears outward
/// into the app.
///
/// Also covers the time the stored session takes to confirm (it used to be a
/// plain spinner): if the animation finishes first, a small spinner appears
/// under the name until it's ready.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.gate});

  final IntroGate gate;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  static const _posters = [
    'BoostMarketValuePoster',
    'ClientSuccessStoryPoster',
    'HappyHomeGuidePoster',
    'MoreThanNumbersPoster',
    'TestimonialWordPoster',
    'UnlockTrueValuePoster',
    'WhyCustomersStayPoster',
    'corporate-poster',
  ];

  /// Where each poster settles, in degrees around the logo (0° = right, 90° =
  /// down). The band just below the logo is left clear for the name: the side
  /// pair sits a little above centre, the bottom pair well below the text.
  static const _angles = [-142.0, -113.0, -67.0, -38.0, -12.0, -168.0, 58.0, 122.0];

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final AnimationController _float = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  late final AnimationController _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((s) {
      if (s == AnimationStatus.completed) _maybeExit();
    });
    _float.repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Reduced motion: no show, straight to the app once the session is in.
      if (MediaQuery.of(context).disableAnimations) {
        _intro.value = 1;
        _maybeExit();
      } else {
        _intro.forward();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final p in _posters) {
      precacheImage(AssetImage('assets/images/posters/$p.png'), context);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _float.dispose();
    _exit.dispose();
    super.dispose();
  }

  Future<void> _maybeExit() async {
    if (_exiting || !mounted || !_intro.isCompleted) return;
    if (context.read<AuthController>().loading) return; // build() retries when it flips
    _exiting = true;
    if (MediaQuery.of(context).disableAnimations) {
      widget.gate.finish();
      return;
    }
    await _exit.forward();
    widget.gate.finish();
  }

  /// `t` mapped onto [begin, end] of the timeline, eased.
  double _seg(double t, double begin, double end, [Curve curve = Curves.linear]) =>
      curve.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<AuthController>().loading;
    if (!loading) WidgetsBinding.instance.addPostFrameCallback((_) => _maybeExit());

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: _navy,
        body: AnimatedBuilder(
          animation: Listenable.merge([_intro, _float, _exit]),
          builder: (context, _) => LayoutBuilder(builder: (context, box) => _frame(context, box.biggest, loading)),
        ),
      ),
    );
  }

  Widget _frame(BuildContext context, Size size, bool loading) {
    final t = _intro.value;
    final e = Curves.easeInCubic.transform(_exit.value);
    // Starts dead centre (where the native splash drew the logo), then lifts a
    // little to make room for the name.
    final settle = _seg(t, 0.12, 0.42, Curves.easeOutBack);
    final center = Offset(size.width / 2, size.height / 2 - 24 * settle);

    // The poster ring: an ellipse sized to the screen, capped on tablets.
    final rx = math.min(size.width * 0.38, 300.0);
    final ry = math.min(size.height * 0.3, 320.0);
    final cardW = (size.width * 0.2).clamp(64.0, 120.0);
    final cardH = cardW * 1.25;

    // Logo: the native splash's 160 circle, a squeeze, then a bounce down to 112.
    final squeeze = _seg(t, 0, 0.12, Curves.easeOut);
    final circle = (160 - 24 * squeeze) + (112 - 136) * settle;
    final logoScale = 1 + 0.25 * e;

    // A ring bursts out of the logo as it lands.
    final burst = _seg(t, 0.14, 0.62, Curves.easeOut);
    final text = _seg(t, 0.55, 0.8, Curves.easeOutCubic);
    final glow = _seg(t, 0, 0.35);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Brand glow fades in over the flat launch navy.
        Positioned.fill(
          child: Opacity(
            opacity: glow,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, (center.dy / size.height) * 2 - 1),
                  radius: 0.9,
                  colors: const [_glow, _navy],
                ),
              ),
            ),
          ),
        ),

        // Posters fly in, then drift; on exit they scatter outward.
        for (final (i, name) in _posters.indexed) _poster(i, name, t, e, center, rx, ry, cardW, cardH),

        // Burst ring.
        if (burst > 0 && burst < 1)
          Positioned(
            left: center.dx - (60 + 160 * burst),
            top: center.dy - (60 + 160 * burst),
            child: Container(
              width: 2 * (60 + 160 * burst),
              height: 2 * (60 + 160 * burst),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.5 * (1 - burst)), width: 2),
              ),
            ),
          ),

        // Logo.
        Positioned(
          left: center.dx - circle / 2,
          top: center.dy - circle / 2,
          child: Opacity(
            opacity: 1 - e,
            child: Transform.scale(
              scale: logoScale,
              child: Container(
                width: circle,
                height: circle,
                padding: EdgeInsets.all(circle * 0.125),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: _glow.withValues(alpha: 0.55 * settle), blurRadius: 40, spreadRadius: 6),
                  ],
                ),
                child: Image.asset('assets/images/logo.png'),
              ),
            ),
          ),
        ),

        // Name + line, under the logo.
        Positioned(
          left: 0,
          right: 0,
          top: center.dy + 56 + 20 + 16 * (1 - text),
          child: Opacity(
            opacity: text * (1 - e),
            child: Column(
              children: [
                const Text(
                  'Creative Klux',
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                ),
                const SizedBox(height: 4),
                Text(
                  'On-brand designs, made with AI',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 13.5),
                ),
                const SizedBox(height: 18),
                // Only once the show is over and the session still isn't in.
                AnimatedOpacity(
                  opacity: _intro.isCompleted && loading && !_exiting ? 1 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Fades into the app's own background so the route change is seamless.
        if (e > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: context.colors.surface.withValues(alpha: _seg(e, 0.45, 1))),
            ),
          ),
      ],
    );
  }

  Widget _poster(int i, String name, double t, double e, Offset center, double rx, double ry, double w, double h) {
    final rad = _angles[i] * math.pi / 180;
    final dir = Offset(math.cos(rad), math.sin(rad));

    // Staggered arrival from well off-screen, with a spin that unwinds.
    final start = 0.1 + i * 0.045;
    final p = _seg(t, start, start + 0.42, Curves.easeOutCubic);
    final spinSign = i.isEven ? 1 : -1;
    final restTilt = dir.dx * 10; // lean outward, like a fanned hand
    final reach = 1 + 2.2 * (1 - p) + 1.4 * e; // ring multiplier: far → 1 → scatter

    // Gentle idle drift once landed.
    final phase = _float.value * 2 * math.pi + i * 0.8;
    final bob = Offset(math.cos(phase) * 3, math.sin(phase) * 6) * p;

    final pos = center + Offset(dir.dx * rx, dir.dy * ry) * reach + bob;
    final tilt = (restTilt + spinSign * 50 * (1 - p) + math.sin(phase) * 1.5) * math.pi / 180;
    final opacity = (p * (1 - e)).clamp(0.0, 1.0);

    return Positioned(
      left: pos.dx - w / 2,
      top: pos.dy - h / 2,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: tilt,
          child: Transform.scale(
            scale: 0.7 + 0.3 * p,
            child: Container(
              width: w,
              height: h,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8))],
              ),
              child: Image.asset('assets/images/posters/$name.png', fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );
  }
}
