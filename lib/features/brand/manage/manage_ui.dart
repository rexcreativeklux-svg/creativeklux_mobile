import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';

/// Small building blocks shared by the Brand Settings tabs, so each tab file
/// reads like the web component it ports.

/// White rounded card (`rounded-xl border p-4 sm:p-6`).
class ManageCard extends StatelessWidget {
  const ManageCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.gray200),
      ),
      child: child,
    );
  }
}

class ManageField extends StatelessWidget {
  const ManageField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.gray800),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

InputDecoration manageInput(BuildContext context, String hint, {Widget? prefixIcon}) {
  final c = context.colors;
  OutlineInputBorder border(Color color, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: color, width: w),
  );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(color: c.gray400, fontSize: 14),
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: c.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: border(c.gray200),
    focusedBorder: border(AppColors.blue600, 1.5),
    border: border(c.gray200),
  );
}

/// `#155dfc` filled button with an optional spinner.
class PrimaryAction extends StatelessWidget {
  const PrimaryAction({super.key, required this.label, required this.onPressed, this.loading = false, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.blue600,
        disabledBackgroundColor: context.colors.gray200,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          else if (icon != null)
            Icon(icon, size: 16),
          if (loading || icon != null) const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// `linear-gradient(135deg, #155dfc, #3b82f6)` button.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(colors: [AppColors.blue600, Color(0xFF3B82F6)]),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 15, color: Colors.white), const SizedBox(width: 6)],
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Amber plan / coming-soon badge (`bg-amber-50 border-amber-200 text-amber-600`).
class AmberBadge extends StatelessWidget {
  const AmberBadge(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFFEE685)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFE17100)),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.text, {super.key, required this.fg, required this.bg});

  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

/// Blue info banner (`border #c7d9fd, bg #eff4ff, text #1e40af`).
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.children});

  final List<InlineSpan> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC7D9FD)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(LucideIcons.info, size: 16, color: Color(0xFF1E40AF)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13, height: 1.45, color: Color(0xFF1E40AF)),
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Destructive confirm dialog body: title, message, Cancel + red action.
class ConfirmCard extends StatelessWidget {
  const ConfirmCard({
    super.key,
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.onConfirm,
    this.busy = false,
    this.icon,
  });

  final String title;
  final Widget body;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: !busy,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: c.redTint, borderRadius: BorderRadius.circular(10)),
                        child: Icon(icon, size: 18, color: AppColors.red500),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.gray900),
                      ),
                    ),
                    IconButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      icon: Icon(LucideIcons.x, size: 18, color: c.gray400),
                    ),
                  ],
                ),
                Padding(padding: const EdgeInsets.fromLTRB(0, 6, 8, 18), child: body),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom(foregroundColor: c.gray600),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: busy ? null : onConfirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.red600,
                        disabledBackgroundColor: AppColors.red600.withValues(alpha: 0.6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: busy
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(confirmLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pull a list out of a response body: the array itself, `data`, or [key].
List<Map<String, dynamic>> listFrom(dynamic raw, [String? key]) {
  dynamic list = raw;
  if (list is Map) {
    list = list['data'] is List
        ? list['data']
        : (key != null ? list[key] : null) ?? (list['data'] is Map ? (list['data'] as Map)[key] : null);
  }
  return list is List ? list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : [];
}
