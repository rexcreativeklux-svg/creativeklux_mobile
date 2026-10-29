import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';

/// App-wide toasts — stands in for sonner's `toast.success/error/warning`.
///
/// ⚠️ DRAWN ABOVE EVERYTHING, not as SnackBars. A SnackBar lives in the page's
/// Scaffold, and every sheet and dialog opens on the ROOT navigator above it —
/// so a toast raised from inside a sheet ("Couldn't load that URL", "Select a
/// brand first") was painted behind the sheet and never seen. [ToastHost] sits
/// in `MaterialApp.builder`, above the navigator, like sonner's root-level
/// `<Toaster>` sits above every modal on the web.
///
/// Kept for `MaterialApp.scaffoldMessengerKey`; nothing shows SnackBars now.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

enum ToastKind { success, error, warning, info }

/// A button on the toast (e.g. "Copy" on a Copilot failure report).
class ToastAction {
  const ToastAction(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;
}

class ToastData {
  const ToastData({
    required this.id,
    required this.kind,
    required this.message,
    this.description,
    this.action,
    this.maxLines,
  });

  final int id;
  final ToastKind kind;
  final String message;
  final String? description;
  final ToastAction? action;

  /// Clamp the headline (long server errors); null = no limit.
  final int? maxLines;
}

class Toast {
  Toast._();

  /// The toast on screen, or null. One at a time — a new one replaces it,
  /// as `hideCurrentSnackBar` did.
  static final current = ValueNotifier<ToastData?>(null);
  static Timer? _timer;
  static int _seq = 0;

  static void success(String message, {String? description}) =>
      show(ToastKind.success, message, description: description);
  static void error(String message, {String? description}) => show(ToastKind.error, message, description: description);
  static void warning(String message, {String? description}) =>
      show(ToastKind.warning, message, description: description);
  static void info(String message, {String? description}) => show(ToastKind.info, message, description: description);

  static void show(
    ToastKind kind,
    String message, {
    String? description,
    ToastAction? action,
    Duration? duration,
    int? maxLines,
  }) {
    _timer?.cancel();
    final data = ToastData(
      id: ++_seq,
      kind: kind,
      message: message,
      description: description,
      action: action,
      maxLines: maxLines,
    );
    current.value = data;
    _timer = Timer(duration ?? Duration(milliseconds: kind == ToastKind.error ? 5000 : 3500), () {
      if (current.value?.id == data.id) current.value = null;
    });
  }

  static void dismiss() {
    _timer?.cancel();
    current.value = null;
  }
}

/// Paints [Toast.current] above the whole app — put it last in the
/// `MaterialApp.builder` stack. Sits above the keyboard and the system bar.
class ToastHost extends StatelessWidget {
  const ToastHost({super.key});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = (mq.viewInsets.bottom > 0 ? mq.viewInsets.bottom : mq.padding.bottom) + 16;
    return ValueListenableBuilder<ToastData?>(
      valueListenable: Toast.current,
      builder: (context, toast, _) => Positioned(
        left: 16,
        right: 16,
        bottom: bottom,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(anim),
              child: child,
            ),
          ),
          child: toast == null ? const SizedBox.shrink() : _ToastCard(key: ValueKey(toast.id), toast: toast),
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({super.key, required this.toast});

  final ToastData toast;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, accent) = switch (toast.kind) {
      ToastKind.success => (LucideIcons.circleCheck, AppColors.green600),
      ToastKind.error => (LucideIcons.circleAlert, AppColors.red600),
      ToastKind.warning => (LucideIcons.triangleAlert, AppColors.amber500),
      ToastKind.info => (LucideIcons.info, AppColors.blue600),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          type: MaterialType.transparency,
          // Swipe or tap away, as with a SnackBar.
          child: Dismissible(
            key: ValueKey(toast.id),
            onDismissed: (_) => Toast.dismiss(),
            child: GestureDetector(
              onTap: toast.action == null ? Toast.dismiss : null,
              child: Container(
                padding: EdgeInsets.fromLTRB(14, 12, toast.action == null ? 14 : 6, 12),
                decoration: BoxDecoration(
                  // Solid even under a skin: a toast sits over arbitrary content.
                  color: c.surface.withValues(alpha: 1),
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
                            toast.message,
                            maxLines: toast.maxLines,
                            overflow: toast.maxLines == null ? null : TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray900),
                          ),
                          if (toast.description != null) ...[
                            const SizedBox(height: 2),
                            Text(toast.description!, style: TextStyle(fontSize: 12.5, color: c.gray500)),
                          ],
                        ],
                      ),
                    ),
                    if (toast.action != null)
                      TextButton(
                        onPressed: () {
                          Toast.dismiss();
                          toast.action!.onTap();
                        },
                        child: Text(toast.action!.label, style: TextStyle(fontSize: 12.5, color: c.gray900)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
