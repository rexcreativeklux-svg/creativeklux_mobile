import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/skins.dart';
import '../../auth/auth_controller.dart';
import '../../brand/brand_avatar.dart';
import '../../brand/brand_switcher_sheet.dart';
import 'account_sheet.dart';

/// The app's top bar: wordmark on the left, two avatars on the right.
///
///   brand logo → brand switcher (the web header's dropdown)
///   user avatar → account menu (the web sidebar's user popup)
///
/// The web header also has a calendar button and a brand-name pill; a 360dp
/// phone can't fit them next to the wordmark, so the calendar moved to the
/// More drawer and the brand shows as its logo with a small switch badge.
///
/// [title] replaces the wordmark on inner screens.
class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key, this.title, this.showBack = false});

  final String? title;
  final bool showBack;

  static const height = 56.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = context.watch<AuthController>();

    return Container(
      height: height,
      color: context.chromeColor,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (showBack) ...[
            _CircleButton(
              tooltip: 'Back',
              onTap: () => context.canPop() ? context.pop() : context.go('/'),
              child: Icon(LucideIcons.chevronLeft, size: 18, color: c.gray900),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: title != null
                ? Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.gray900),
                  )
                : const _Wordmark(),
          ),
          const SizedBox(width: 12),
          _BrandButton(auth: auth),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Account',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => showAccountSheet(context),
              child: UserAvatar(name: auth.username, size: 32),
            ),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/logo.png', height: 26),
        const SizedBox(width: 6),
        // Scales down rather than truncating when the action buttons leave
        // little room (narrow phones).
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Creative Klux',
              maxLines: 1,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: c.gray900),
            ),
          ),
        ),
      ],
    );
  }
}

/// The active brand's logo with a small chevron badge, so it reads as
/// "tap to switch".
class _BrandButton extends StatelessWidget {
  const _BrandButton({required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final brand = auth.activeBrand;
    return Tooltip(
      message: 'Switch brand',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: auth.brandsLoading ? null : () => showBrandSwitcher(context),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  padding: const EdgeInsets.all(1.5),
                  // gray100 shows while the logo loads, instead of an empty ring.
                  decoration: BoxDecoration(
                    color: c.gray100,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.gray200),
                  ),
                  child: brand != null
                      ? BrandAvatar(brand: brand, size: 31)
                      : Container(
                          decoration: BoxDecoration(color: c.gray100, shape: BoxShape.circle),
                          child: Icon(LucideIcons.building2, size: 15, color: c.gray500),
                        ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: c.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.gray200),
                  ),
                  child: Icon(LucideIcons.chevronDown, size: 11, color: c.gray600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 36px round, bordered icon button (the back button on inner screens).
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.child, required this.onTap, required this.tooltip});

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.gray100,
        shape: CircleBorder(side: BorderSide(color: c.gray200)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 36, height: 36, child: Center(child: child)),
        ),
      ),
    );
  }
}
