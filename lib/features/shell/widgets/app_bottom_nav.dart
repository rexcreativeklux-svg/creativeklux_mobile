import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/skins.dart';
import '../nav_items.dart';

/// Phone bottom bar, Pixury-style: a short accent bar above the active slot,
/// outlined icons, labels underneath.
///
/// Same destinations as the web's mobile bottom bar — the four most-used
/// pages plus "More", which opens the full navigation drawer.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.location, required this.onMore});

  final String location;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final activePath = activePathIn(bottomNavItems, location);

    return Container(
      decoration: BoxDecoration(
        color: context.chromeColor,
        border: Border(top: BorderSide(color: c.gray200)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (final item in bottomNavItems)
                _Slot(
                  icon: item.icon,
                  label: item.short ?? item.label,
                  semanticLabel: item.label,
                  active: item.path == activePath,
                  onTap: () => context.go(item.path),
                ),
              _Slot(
                icon: LucideIcons.ellipsis,
                label: 'More',
                semanticLabel: 'Open navigation menu',
                active: false,
                onTap: onMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = active ? AppColors.blue600 : c.gray400;

    return Expanded(
      child: Semantics(
        label: semanticLabel,
        button: true,
        selected: active,
        child: InkResponse(
          onTap: onTap,
          highlightShape: BoxShape.rectangle,
          child: Column(
            children: [
              // Active indicator — the short bar on top of the slot.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                height: 3,
                width: active ? 32 : 0,
                decoration: BoxDecoration(
                  color: AppColors.blue600,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
                ),
              ),
              const Spacer(),
              Icon(icon, size: 21, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: color),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
