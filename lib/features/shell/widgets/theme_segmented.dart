import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_controller.dart';

/// Sun / System / Moon pills (`appearance/ThemeSegmented.jsx`).
class ThemeSegmented extends StatelessWidget {
  const ThemeSegmented({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    const options = [
      (ThemeMode.light, LucideIcons.sun, 'Light'),
      (ThemeMode.system, LucideIcons.monitor, 'System'),
      (ThemeMode.dark, LucideIcons.moon, 'Dark'),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.gray100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.gray200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (mode, icon, label) in options)
            Tooltip(
              message: label,
              child: GestureDetector(
                onTap: () => theme.setMode(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 30,
                  height: 26,
                  decoration: BoxDecoration(
                    color: theme.mode == mode ? c.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    boxShadow: theme.mode == mode
                        ? const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))]
                        : null,
                  ),
                  child: Icon(icon, size: 14, color: theme.mode == mode ? AppColors.blue600 : c.gray500),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
