import 'package:flutter/material.dart';

import 'account_sections.dart';
import 'settings_widgets.dart';

/// Port of `(settings)/sessions-and-password/page.jsx` — password reset,
/// active sessions, log out / delete account.
///
/// The web page is an older copy of the same three blocks that /profile now
/// carries: it calls the retired `creativeklux-frontend/user/...` backend and
/// shows a success modal. Here it shares /profile's newer blocks (userend
/// endpoints, toasts, the all-fields check) instead of porting the dead calls.
class SessionsPasswordScreen extends StatelessWidget {
  const SessionsPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsScaffold(
      children: [
        SettingsHeader(
          'Active sessions & passwords',
          subtitle: 'Manage your active sessions, update password, or delete your account.',
        ),
        PasswordCard(title: 'Password Reset'),
        SizedBox(height: 14),
        SessionsCard(title: 'Active Sessions'),
        SizedBox(height: 18),
        AccountActions(),
      ],
    );
  }
}
