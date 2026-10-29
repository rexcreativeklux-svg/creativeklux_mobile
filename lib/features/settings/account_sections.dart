import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/api/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/app_input.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'settings_api.dart';
import 'settings_widgets.dart';

// The password, sessions and account-action blocks. On the web they appear
// twice — in profile/page.jsx and again in sessions-and-password/page.jsx —
// with the profile copy being the newer one (userend endpoints, toasts, the
// "fill in all fields" check). Both screens use this one version.

/// The "Password" card (profile/page.jsx).
class PasswordCard extends StatefulWidget {
  const PasswordCard({super.key, this.title = 'Password'});

  final String title;

  @override
  State<PasswordCard> createState() => _PasswordCardState();
}

class _PasswordCardState extends State<PasswordCard> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _updating = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    if (_current.text.isEmpty || _next.text.isEmpty || _confirm.text.isEmpty) {
      Toast.error('Please fill in all password fields.');
      return;
    }
    if (_next.text != _confirm.text) {
      Toast.error('Passwords do not match.');
      return;
    }
    final auth = context.read<AuthController>();
    final userId = auth.user?['id'];
    if (userId == null) return;

    FocusScope.of(context).unfocus();
    setState(() => _updating = true);
    try {
      await SettingsApi(auth.api).changePassword(userId, _current.text, _next.text);
      Toast.success('Password updated.');
      _current.clear();
      _next.clear();
      _confirm.clear();
    } catch (_) {
      // The web shows one fixed line whatever the server said.
      Toast.error("Couldn't update your password. Please try again.");
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(widget.title),
          AppInput(
            label: 'Current password',
            controller: _current,
            placeholder: 'Enter current password',
            password: true,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          AppInput(
            label: 'New password',
            controller: _next,
            placeholder: 'Min. 8 characters',
            password: true,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          AppInput(
            label: 'Confirm password',
            controller: _confirm,
            placeholder: 'Repeat new password',
            password: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _update(),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: SettingsButton(
              label: 'Update password',
              loading: _updating,
              color: context.colors.gray900,
              foreground: context.colors.surface,
              onPressed: _update,
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Active sessions" card. Loads on open; an unreachable endpoint reads as
/// "No active sessions found." exactly like the web (it only logs the error).
class SessionsCard extends StatefulWidget {
  const SessionsCard({super.key, this.title = 'Active sessions'});

  final String title;

  @override
  State<SessionsCard> createState() => _SessionsCardState();
}

class _SessionsCardState extends State<SessionsCard> {
  late final SettingsApi _api = SettingsApi(context.read<AuthController>().api);
  List<Map<String, dynamic>> _sessions = const [];
  bool _loading = true;
  final Set<Object?> _ending = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _api.sessions();
      if (mounted) setState(() => _sessions = list);
    } catch (e) {
      debugPrint('❌ Failed to load sessions: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _end(Map<String, dynamic> s) async {
    final id = s['id'];
    setState(() => _ending.add(id));
    try {
      await _api.terminateSession(id as Object);
      if (!mounted) return;
      setState(() => _sessions = _sessions.where((x) => x['id'] != id).toList());
      Toast.success('Session ended.');
    } catch (_) {
      Toast.error('Failed to terminate session.');
    } finally {
      if (mounted) setState(() => _ending.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(widget.title),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue600),
                ),
              ),
            )
          else if (_sessions.isEmpty)
            Text('No active sessions found.', style: TextStyle(fontSize: 13, color: c.gray400))
          else
            for (final s in _sessions) _sessionRow(context, s),
        ],
      ),
    );
  }

  Widget _sessionRow(BuildContext context, Map<String, dynamic> s) {
    final c = context.colors;
    final device = '${s['device'] ?? 'Unknown device'}';
    final current = s['current'] == true || s['current'] == 1;
    final phone = RegExp('iphone|android|mobile', caseSensitive: false).hasMatch(device);
    final meta = [s['browser'], s['location'], s['date']].where((v) => v != null && '$v'.isNotEmpty).join(' · ');
    final ending = _ending.contains(s['id']);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: c.gray50, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.surface,
              shape: BoxShape.circle,
              border: Border.all(color: c.gray200),
            ),
            child: Icon(phone ? LucideIcons.smartphone : LucideIcons.monitor, size: 14, color: c.gray500),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        device,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.gray900),
                      ),
                    ),
                    if (current) ...[const SizedBox(width: 6), const StatusPill('Current', PillColors.green)],
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.gray500),
                  ),
              ],
            ),
          ),
          if (!current) ...[
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: OutlinedButton(
                onPressed: ending ? null : () => _end(s),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red500,
                  side: BorderSide(color: AppColors.red500.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: Text(ending ? 'Ending…' : 'End'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Log out" + "Delete account", with the delete confirmation.
class AccountActions extends StatelessWidget {
  const AccountActions({super.key});

  Future<void> _delete(BuildContext context) async {
    final auth = context.read<AuthController>();
    final userId = auth.user?['id'];
    if (userId == null) return;
    var deleted = false;
    await showConfirmDialog(
      context,
      title: 'Delete your account?',
      message:
          'This will permanently remove your account and all associated data. '
          'This action cannot be undone.',
      confirmLabel: 'Delete account',
      danger: true,
      onConfirm: () async {
        try {
          await SettingsApi(auth.api).deleteAccount(userId);
          deleted = true;
        } on AppException catch (e) {
          debugPrint('❌ Delete account failed: ${e.messageForDevs ?? e.message}');
          Toast.error("Couldn't delete your account. Please try again.");
        }
      },
    );
    if (!deleted) return;
    Toast.success('Account deleted.');
    // Same 1.5s beat as the web, so the toast is read before the sign-out.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SettingsButton(
          label: 'Log out',
          icon: LucideIcons.logOut,
          outlined: true,
          color: c.gray700,
          onPressed: () => context.read<AuthController>().logout(),
        ),
        SettingsButton(
          label: 'Delete account',
          icon: LucideIcons.trash,
          outlined: true,
          color: AppColors.red500,
          onPressed: () => _delete(context),
        ),
      ],
    );
  }
}
