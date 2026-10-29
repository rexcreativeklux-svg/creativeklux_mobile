import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../shell/widgets/app_top_bar.dart';

/// /help — port of `(dashboard)/(pages)/help/page.jsx`: the Help panel's two
/// links, Tutorial Videos and Support.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget link(String label, String sub, IconData icon, String path) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push(path),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.gray200),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: c.blueTint, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 18, color: AppColors.blue600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                      ),
                      const SizedBox(height: 2),
                      Text(sub, style: TextStyle(fontSize: 12, color: c.gray500)),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 18, color: c.gray400),
              ],
            ),
          ),
        ),
      ),
    );

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Help', showBack: true),
          Expanded(
            child: ColoredBox(
              color: c.page,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                children: [
                  link('Tutorial Videos', 'Step-by-step video guides', LucideIcons.squarePlay, '/help/tutorial-videos'),
                  link('Support', 'FAQs and ways to reach us', LucideIcons.lifeBuoy, '/help/support'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
