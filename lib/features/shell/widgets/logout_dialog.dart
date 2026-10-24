import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';

/// Port of `(components)/LogoutModal.jsx` — confirm, then a locked
/// "Logging out…" state until the sign-out finishes.
Future<void> showLogoutDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _LogoutDialog());

class _LogoutDialog extends StatefulWidget {
  const _LogoutDialog();

  @override
  State<_LogoutDialog> createState() => _LogoutDialogState();
}

class _LogoutDialogState extends State<_LogoutDialog> {
  bool _busy = false;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    final auth = context.read<AuthController>();
    final navigator = Navigator.of(context);
    try {
      await auth.logout();
      Toast.success('Logged out successfully');
      // The router redirects to /login; just make sure the dialog goes too.
      if (navigator.mounted) navigator.pop();
    } catch (err) {
      Toast.error('Something went wrong while logging out. Please try again.');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 384),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Log out?',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.gray900),
                      ),
                    ),
                    IconButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: Icon(LucideIcons.x, size: 20, color: c.gray400),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 12, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: c.redTint, shape: BoxShape.circle),
                        child: const Icon(LucideIcons.logOut, size: 20, color: AppColors.red600),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Are you sure you want to log out of your account?',
                          style: TextStyle(fontSize: 14, color: c.gray600),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        backgroundColor: c.gray100,
                        foregroundColor: c.gray700,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _busy ? null : _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue600,
                        disabledBackgroundColor: AppColors.blue600.withValues(alpha: 0.7),
                        disabledForegroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _busy
                            ? const [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                ),
                                SizedBox(width: 8),
                                Text('Logging out…'),
                              ]
                            : const [Text('Log Out'), SizedBox(width: 8), Icon(LucideIcons.logOut, size: 16)],
                      ),
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
