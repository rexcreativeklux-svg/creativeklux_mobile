import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/api/app_exception.dart';
import '../../../core/ui/app_input.dart';
import '../../../core/ui/primary_button.dart';
import '../../../core/ui/toast.dart';
import '../auth_controller.dart';
import '../widgets/auth_shell.dart';
import '../widgets/social_auth_buttons.dart';

/// Port of `(auth)/register/page.jsx`.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _license = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _license, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) {
      Toast.error('Please enter your name and email.');
      return;
    }
    if (_password.text.length < 8) {
      Toast.error('Password must be at least 8 characters long.');
      return;
    }
    if (_password.text != _confirm.text) {
      Toast.error('Passwords do not match.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final email = _email.text.trim();
    try {
      final msg = await context.read<AuthController>().register(
        _name.text.trim(),
        email,
        _password.text,
        _license.text.trim(),
      );
      Toast.success(msg);
      if (mounted) context.go(Uri(path: '/verify-email', queryParameters: {'email': email}).toString());
    } catch (err) {
      debugPrint('❌ register failed: $err');
      Toast.error(toUserMessage(err, 'Registration failed. Please try again.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: AuthShell(
        title: 'Create your account',
        subtitle: const Text('Start creating with Creative Klux — free for 7 days.'),
        children: [
          AppInput(
            label: 'Full name',
            controller: _name,
            placeholder: 'Jane Doe',
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
          ),
          const SizedBox(height: 14),
          AppInput(
            label: 'Email address',
            controller: _email,
            placeholder: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
          ),
          const SizedBox(height: 14),
          AppInput(
            label: 'License code',
            controller: _license,
            placeholder: 'Enter your license code',
            optional: true,
            hint: 'Leave empty for a free trial account (7 days).',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          AppInput(
            label: 'Password',
            controller: _password,
            placeholder: '••••••••',
            password: true,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
          ),
          const SizedBox(height: 14),
          AppInput(
            label: 'Confirm password',
            controller: _confirm,
            placeholder: '••••••••',
            password: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Create account',
            loadingLabel: 'Creating account…',
            loading: _loading,
            onPressed: _submit,
          ),
          const SocialAuthButtons(label: 'or sign up with'),
          AuthLinkLine(text: 'Already have an account? ', link: 'Sign in', onTap: () => context.go('/login')),
          const SizedBox(height: 32),
          const LegalConsentLine(prefix: 'By creating an account you agree to our'),
        ],
      ),
    );
  }
}
