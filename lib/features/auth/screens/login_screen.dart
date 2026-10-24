import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/api/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/app_input.dart';
import '../../../core/ui/primary_button.dart';
import '../../../core/ui/toast.dart';
import '../auth_controller.dart';
import '../widgets/auth_shell.dart';
import '../widgets/social_auth_buttons.dart';

/// Port of `(auth)/login/page.jsx`.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      Toast.error('Please enter your email and password.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final msg = await context.read<AuthController>().login(_email.text.trim(), _password.text);
      Toast.success(msg);
      // The router's redirect takes it from here (verify gate or home).
    } catch (err) {
      debugPrint('❌ login failed: $err');
      Toast.error(toUserMessage(err, 'Couldn’t sign you in. Please check your email and password.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AutofillGroup(
      child: AuthShell(
        title: 'Welcome back',
        subtitle: const Text('Sign in to your Creative Klux account.'),
        children: [
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
            label: 'Password',
            controller: _password,
            placeholder: '••••••••',
            password: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            rightLabel: GestureDetector(
              onTap: () => context.push('/forgot-password'),
              child: const Text(
                'Forgot password?',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(label: 'Sign in', loadingLabel: 'Signing in…', loading: _loading, onPressed: _submit),
          const SocialAuthButtons(),
          AuthLinkLine(text: 'Don’t have an account? ', link: 'Create one free', onTap: () => context.go('/register')),
          const SizedBox(height: 32),
          Text(
            'By signing in you agree to our Terms & Privacy Policy',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: c.gray300),
          ),
        ],
      ),
    );
  }
}
