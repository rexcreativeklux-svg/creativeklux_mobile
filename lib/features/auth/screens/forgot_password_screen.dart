import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/api/app_exception.dart';
import '../../../core/ui/app_input.dart';
import '../../../core/ui/primary_button.dart';
import '../../../core/ui/toast.dart';
import '../auth_controller.dart';
import '../widgets/auth_shell.dart';

/// Port of `(auth)/forgot-password/page.jsx` — step 1 of the code-based reset.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      Toast.error('Please enter your email address.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final msg = await context.read<AuthController>().sendResetCode(email);
      Toast.success(msg);
      if (mounted) {
        context.push(Uri(path: '/change-password', queryParameters: {'email': email}).toString());
      }
    } catch (err) {
      debugPrint('❌ sendResetCode failed: $err');
      Toast.error(toUserMessage(err, 'Couldn’t send the reset code. Please try again.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Forgot password?',
      subtitle: const Text('Enter your email and we’ll send you a 6-digit code to reset your password.'),
      showBack: true,
      children: [
        AppInput(
          label: 'Email address',
          controller: _email,
          placeholder: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 18),
        PrimaryButton(label: 'Send reset code', loadingLabel: 'Sending…', loading: _loading, onPressed: _submit),
        AuthLinkLine(text: 'Remembered your password? ', link: 'Back to sign in', onTap: () => context.go('/login')),
      ],
    );
  }
}
