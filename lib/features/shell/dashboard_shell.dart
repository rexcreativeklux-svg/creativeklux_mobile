import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/skins.dart';
import '../auth/auth_controller.dart';
import '../brand/brand_select_gate.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/nav_drawer.dart';

/// Wraps every signed-in screen — the Flutter counterpart of
/// `(dashboard)/layout.js`.
///
///   Phone / tablet portrait (< 1024px): bottom bar + "More" drawer.
///   Wide (≥ 1024px): a permanent sidebar rail, no bottom bar.
///
/// It also owns the active-brand gate: a verified user with no active brand
/// gets the blocking brand picker on every route except /brand/create.
class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  /// Same switch point as the web (`lg`).
  static const wideBreakpoint = 1024.0;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = context.watch<AuthController>();
    final wide = MediaQuery.sizeOf(context).width >= DashboardShell.wideBreakpoint;

    final showBrandGate =
        !auth.brandsLoading &&
        auth.user != null &&
        auth.isVerified &&
        auth.activeBrand == null &&
        !widget.location.startsWith('/brand/create');

    return Stack(
      children: [
        Scaffold(
          key: _scaffoldKey,
          // Under a skin or a photo the wallpaper is painted behind the whole
          // app, and the shell lays the skin's translucent PAGE over it — the
          // web's `bg-page` main area. Without it a screen that paints no
          // background of its own (Home) sat straight on a busy photo.
          backgroundColor: context.watch<SkinController>().active ? c.page : c.surface,
          drawer: wide ? null : const NavDrawer(),
          body: wide
              ? Row(
                  children: [
                    const NavDrawer(asRail: true),
                    Expanded(child: widget.child),
                  ],
                )
              : widget.child,
          bottomNavigationBar: wide
              ? null
              : AppBottomNav(location: widget.location, onMore: () => _scaffoldKey.currentState?.openDrawer()),
        ),
        if (showBrandGate) const Positioned.fill(child: BrandSelectGate()),
      ],
    );
  }
}
