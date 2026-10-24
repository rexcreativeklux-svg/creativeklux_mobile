import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';

/// "Create something new": the two ways to start a design. On the web this is
/// a small dropdown under the + button; on a phone it's a bottom sheet with
/// big, thumb-sized choices.
Future<void> showCreateSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
  builder: (sheetContext) {
    final c = sheetContext.colors;
    void go(String path) {
      Navigator.pop(sheetContext);
      context.push(path);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create something new',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.gray900),
          ),
          const SizedBox(height: 2),
          Text('Pick how you’d like to start.', style: TextStyle(fontSize: 13, color: c.gray500)),
          const SizedBox(height: 16),
          _Option(
            icon: LucideIcons.globe,
            colors: const [Color(0xFF2563EB), Color(0xFF06B6D4)],
            title: 'Create from URL',
            subtitle: 'Paste a link. We pull the copy, colours and images from the page.',
            onTap: () => go('/studio/create-from-url'),
          ),
          const SizedBox(height: 10),
          _Option(
            icon: LucideIcons.wandSparkles,
            colors: const [Color(0xFF7C3AED), Color(0xFFEC4899)],
            title: 'Custom Creation',
            subtitle: 'Start from a template or a blank canvas.',
            onTap: () => go('/studio/select'),
          ),
        ],
      ),
    );
  },
);

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.colors,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final List<Color> colors;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.gray50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.gray100),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                  boxShadow: [
                    BoxShadow(color: colors.first.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Icon(icon, size: 22, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.gray900),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12.5, height: 1.35, color: c.gray500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(LucideIcons.chevronRight, size: 18, color: c.gray400),
            ],
          ),
        ),
      ),
    );
  }
}
