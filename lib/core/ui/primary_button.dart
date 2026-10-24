import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';

/// The full-width blue submit button every auth screen uses
/// (`h-11 rounded-xl bg-[#1447e6]` + the soft blue shadow).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.loadingLabel,
    this.trailingArrow = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final String? loadingLabel;
  final bool trailingArrow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final disabled = loading || onPressed == null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: disabled
            ? const []
            : [BoxShadow(color: AppColors.primary.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: FilledButton(
        onPressed: disabled ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: c.gray100,
          disabledForegroundColor: c.gray400,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: loading
              ? [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.gray400)),
                  const SizedBox(width: 8),
                  Text(loadingLabel ?? label),
                ]
              : [
                  Text(label),
                  if (trailingArrow) ...[const SizedBox(width: 8), const Icon(LucideIcons.arrowRight, size: 15)],
                ],
        ),
      ),
    );
  }
}
