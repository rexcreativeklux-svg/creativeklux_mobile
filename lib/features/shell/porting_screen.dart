import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import 'widgets/app_top_bar.dart';

/// Stand-in for a web page that hasn't been ported yet. Every route the web
/// sidebar links to exists in the router from day one, so navigation works
/// end to end; each one is swapped for its real screen as it's ported.
class PortingScreen extends StatelessWidget {
  const PortingScreen({super.key, required this.title, required this.webPath, this.icon});

  final String title;

  /// The page's source under `src/app/` in the web codebase.
  final String webPath;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          AppTopBar(title: title, showBack: true),
          Expanded(
            child: Container(
              color: c.page,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: c.blueTint, borderRadius: BorderRadius.circular(16)),
                    child: Icon(icon ?? LucideIcons.hammer, size: 28, color: AppColors.blue600),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.gray900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This screen is being brought over from the web app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: c.gray500),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
