import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/auth_controller.dart';
import '../nav_items.dart';
import 'account_sheet.dart';
import 'theme_segmented.dart';
import '../../appearance/appearance_button.dart';

/// The sidebar — rendered as the "More" drawer on phones, and as a permanent
/// rail on wide screens (`asRail: true`). One widget, two places, like the
/// web's `<Sidebar variant="drawer">`.
class NavDrawer extends StatefulWidget {
  const NavDrawer({super.key, this.asRail = false});

  final bool asRail;

  @override
  State<NavDrawer> createState() => _NavDrawerState();
}

enum _Tab { apps, copilot }

class _NavDrawerState extends State<NavDrawer> {
  _Tab? _manualTab;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final location = GoRouterState.of(context).matchedLocation;
    // Follow the route (any /copilot page → Copilot tab), but let the user
    // flip tabs to browse until the next navigation.
    final routeTab = location.startsWith('/copilot') ? _Tab.copilot : _Tab.apps;
    final tab = _manualTab ?? routeTab;
    final items = tab == _Tab.apps ? appsItems : copilotItems;
    final activePath = activePathIn(items, location);

    void navigate(String path) {
      final router = GoRouter.of(context);
      if (!widget.asRail) Navigator.pop(context);
      setState(() => _manualTab = null);
      router.go(path);
    }

    final content = SafeArea(
      right: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo row (+ close on the drawer).
          Container(
            height: 56,
            padding: const EdgeInsets.only(left: 16, right: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.gray200)),
            ),
            child: Row(
              children: [
                Image.asset('assets/images/logo.png', height: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Creative Klux',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: c.gray900),
                  ),
                ),
                if (!widget.asRail)
                  IconButton(
                    tooltip: 'Close navigation menu',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(LucideIcons.x, size: 18, color: c.gray500),
                  ),
              ],
            ),
          ),

          // Designs / Copilot tabs — each is also a link to that tab's home.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: c.gray100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.gray200),
              ),
              child: Row(
                children: [
                  for (final (t, label, icon, home) in [
                    (_Tab.apps, 'Designs', LucideIcons.layoutGrid, appsItems.first.path),
                    (_Tab.copilot, 'Copilot', LucideIcons.bot, copilotItems.first.path),
                  ])
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _manualTab = t);
                          navigate(home);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          decoration: BoxDecoration(
                            color: tab == t ? c.surface : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: tab == t
                                ? const [BoxShadow(color: Color(0x0F000000), blurRadius: 2, offset: Offset(0, 1))]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(icon, size: 16, color: tab == t ? AppColors.blue600 : c.gray500),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: tab == t ? FontWeight.w600 : FontWeight.w500,
                                  color: tab == t ? c.gray900 : c.gray500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Nav list.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _NavTile(item: item, active: item.path == activePath, onTap: () => navigate(item.path)),
                  ),
              ],
            ),
          ),

          // Theme row.
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.gray200)),
            ),
            child: Row(
              children: [
                Text(
                  'THEME',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 1.6, color: c.gray400),
                ),
                const Spacer(),
                AppearanceButton(beforeOpen: widget.asRail ? null : () => Navigator.pop(context)),
                const SizedBox(width: 8),
                const ThemeSegmented(),
              ],
            ),
          ),

          // Account block — opens the account menu.
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.gray200)),
            ),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    // Open the sheet from the shell's context, not the drawer's,
                    // which is about to be disposed.
                    final shellContext = Scaffold.of(context).context;
                    if (!widget.asRail) Navigator.pop(context);
                    showAccountSheet(shellContext);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(child: UserBlock(auth: context.watch<AuthController>())),
                        Icon(LucideIcons.chevronUp, size: 16, color: c.gray500),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.asRail) {
      return Container(
        width: 224,
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(right: BorderSide(color: c.gray200)),
        ),
        child: content,
      );
    }
    return Drawer(
      width: 280,
      backgroundColor: c.surface.withValues(alpha: 1),
      shape: const RoundedRectangleBorder(),
      child: content,
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.active, required this.onTap});

  final NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: active ? c.blueTint : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(item.icon, size: 18, color: active ? AppColors.blue600 : c.gray500),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: active ? AppColors.blue600 : c.gray500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
