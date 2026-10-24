import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import 'appearance_sheet.dart';

/// Port of `appearance/AppearanceButton.jsx`: the palette button beside the
/// theme control that opens the Appearance panel.
///
/// [beforeOpen] closes whatever it sits in (the drawer, the account sheet) —
/// the panel previews on the live app, so nothing should be left over it.
class AppearanceButton extends StatelessWidget {
  const AppearanceButton({super.key, this.beforeOpen});

  final VoidCallback? beforeOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: 'Appearance',
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () {
          // A context that outlives the drawer / sheet being closed.
          final root = Navigator.of(context, rootNavigator: true).context;
          beforeOpen?.call();
          showAppearanceSheet(root);
        },
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: c.gray100,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: c.gray200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.palette, size: 14, color: AppColors.blue600),
              const SizedBox(width: 5),
              Text(
                'Appearance',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: c.gray700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
