import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/skins.dart';
import 'core/theme/theme_controller.dart';
import 'core/ui/toast.dart';
import 'features/auth/auth_controller.dart';
import 'features/shell/splash_screen.dart';

class CreativeKluxApp extends StatefulWidget {
  const CreativeKluxApp({super.key});

  @override
  State<CreativeKluxApp> createState() => _CreativeKluxAppState();
}

class _CreativeKluxAppState extends State<CreativeKluxApp> with WidgetsBindingObserver {
  final _intro = IntroGate();
  late final GoRouter _router = buildRouter(context.read<AuthController>(), _intro);

  /// What the accent was last set to, so a change can rebuild the whole tree.
  Color? _appliedAccent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    _intro.dispose();
    super.dispose();
  }

  /// "System" theme follows the phone — and a skin has a light and a dark
  /// treatment, so the palette has to follow it too.
  @override
  void didChangePlatformBrightness() => setState(() {});

  /// [AppColors.blue600] is read straight from a static by ~200 widgets, so a
  /// skin change has to rebuild every one of them, not just the ones that
  /// depend on the Theme. State (route, scroll, typed text) is kept: this marks
  /// elements dirty, it doesn't replace them.
  void _rebuildEverything() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeController>().mode;
    final skins = context.watch<SkinController>();
    final platformDark = View.of(context).platformDispatcher.platformBrightness == Brightness.dark;
    final dark = themeMode == ThemeMode.dark || (themeMode == ThemeMode.system && platformDark);

    // The skin's accent replaces the app blue (skins.css re-points blue-600).
    final palette = skins.skin.palette(dark);
    AppColors.applyAccent(accent: palette?.accent, soft: palette?.accentSoft);
    if (_appliedAccent != AppColors.blue600) {
      final first = _appliedAccent == null;
      _appliedAccent = AppColors.blue600;
      if (!first) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _rebuildEverything() : null);
    }

    return MaterialApp.router(
      title: 'Creative Klux',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: AppTheme.light(skins.colorsFor(dark: false)),
      darkTheme: AppTheme.dark(skins.colorsFor(dark: true)),
      themeMode: themeMode,
      routerConfig: _router,
      // Status-bar icons follow the theme (they were white on the light app),
      // and both system bars are see-through so a skin's art reaches the edges.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
        child: Stack(
          children: [
            // The wallpaper behind every screen — a skin's art and/or a photo
            // (`:root[data-skin]` / `:root[data-wallpaper]` on the web). Screens
            // paint the skin's translucent page/surface over it.
            if (skins.active)
              Positioned.fill(
                child: SkinBackdrop(palette: palette, wallpaper: skins.wallpaper, fallback: context.colors.surface),
              ),
            // The phone's own font-size setting multiplies every size in the
            // app. Honour it, but cap it so a large setting can't break layouts
            // that were sized for a phone screen.
            MediaQuery.withClampedTextScaling(maxScaleFactor: 1.1, child: child!),
            // Above the navigator, so toasts show over sheets and dialogs too.
            const ToastHost(),
          ],
        ),
      ),
    );
  }
}
