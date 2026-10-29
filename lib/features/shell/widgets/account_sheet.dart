import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/auth_controller.dart';
import '../nav_items.dart';
import 'logout_dialog.dart';
import 'theme_segmented.dart';
import '../../appearance/appearance_button.dart';

/// The account menu — the popup above the sidebar's user button on the web,
/// as a bottom sheet. Opened from the top bar's profile button.
Future<void> showAccountSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (sheetContext) => const AccountMenu(closeOnNavigate: true),
);

/// User block + account links + theme + logout. Also embedded at the foot of
/// the More drawer, so there's one account menu rather than two.
class AccountMenu extends StatelessWidget {
  const AccountMenu({super.key, this.closeOnNavigate = false});

  /// Pop the enclosing sheet/drawer before navigating.
  final bool closeOnNavigate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = context.watch<AuthController>();
    // From the router, not GoRouterState.of: as a sheet this sits on the ROOT
    // navigator, above every route, where GoRouterState.of throws and the sheet
    // came up blank. (It still works embedded in the More drawer.)
    final location = GoRouter.of(context).routeInformationProvider.value.uri.path;

    void go(String path) {
      final router = GoRouter.of(context);
      if (closeOnNavigate) Navigator.pop(context);
      router.push(path);
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: UserBlock(auth: auth),
          ),
          Divider(color: c.gray200),
          for (final link in accountLinks)
            ListTile(
              dense: true,
              leading: Icon(link.icon, size: 18, color: c.gray500),
              title: Text(
                link.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isPathActive(location, link.path) ? FontWeight.w600 : FontWeight.w500,
                  color: isPathActive(location, link.path) ? AppColors.blue600 : c.gray900,
                ),
              ),
              onTap: () => go(link.path),
            ),
          Divider(color: c.gray200),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Text(
                  'THEME',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 1.6, color: c.gray400),
                ),
                const Spacer(),
                AppearanceButton(beforeOpen: closeOnNavigate ? () => Navigator.pop(context) : null),
                const SizedBox(width: 8),
                const ThemeSegmented(),
              ],
            ),
          ),
          Divider(color: c.gray200),
          ListTile(
            dense: true,
            leading: const Icon(LucideIcons.power, size: 18, color: AppColors.red500),
            title: const Text(
              'Logout',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.red500),
            ),
            onTap: () {
              // The dialog needs a context that outlives this sheet.
              final rootContext = Navigator.of(context, rootNavigator: true).context;
              if (closeOnNavigate) Navigator.pop(context);
              showLogoutDialog(rootContext);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Avatar initial + username + plan name.
class UserBlock extends StatelessWidget {
  const UserBlock({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = auth.username;
    return Row(
      children: [
        UserAvatar(name: name, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Account' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
              ),
              const SizedBox(height: 2),
              if (auth.packageLoading)
                Container(
                  width: 64,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(color: c.gray200, borderRadius: BorderRadius.circular(4)),
                )
              else
                Text(
                  auth.planName,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.blue500),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Blue gradient circle with the user's initial.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.size = 32});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blue500, AppColors.blue600],
        ),
      ),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.w700),
      ),
    );
  }
}
