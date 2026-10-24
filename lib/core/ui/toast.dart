import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';

/// App-wide toasts — stands in for sonner's `toast.success/error/warning`.
///
/// Mounted on the root ScaffoldMessenger (see `app.dart`), so a toast survives
/// a route change exactly like sonner's root-level `<Toaster>` does on the web.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

enum _Kind { success, error, warning, info }

class Toast {
  Toast._();

  static void success(String message, {String? description}) => _show(_Kind.success, message, description);
  static void error(String message, {String? description}) => _show(_Kind.error, message, description);
  static void warning(String message, {String? description}) => _show(_Kind.warning, message, description);
  static void info(String message, {String? description}) => _show(_Kind.info, message, description);

  static void _show(_Kind kind, String message, String? description) {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    final (icon, accent) = switch (kind) {
      _Kind.success => (LucideIcons.circleCheck, AppColors.green600),
      _Kind.error => (LucideIcons.circleAlert, AppColors.red600),
      _Kind.warning => (LucideIcons.triangleAlert, AppColors.amber500),
      _Kind.info => (LucideIcons.info, AppColors.blue600),
    };

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 6,
          duration: Duration(milliseconds: kind == _Kind.error ? 5000 : 3500),
          backgroundColor: Colors.transparent,
          padding: EdgeInsets.zero,
          content: Builder(
            builder: (context) {
              final c = context.colors;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.gray200),
                  boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 6))],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            message,
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray900),
                          ),
                          if (description != null) ...[
                            const SizedBox(height: 2),
                            Text(description, style: TextStyle(fontSize: 12.5, color: c.gray500)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
  }
}
