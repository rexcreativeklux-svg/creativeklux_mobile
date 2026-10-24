import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/api/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/primary_button.dart';
import '../../../core/ui/toast.dart';
import '../auth_controller.dart';
import '../widgets/auth_shell.dart';
import '../widgets/code_input.dart';

/// Port of `(auth)/verify-email/page.jsx`.
///
/// Reached after registering (`?email=`) or bounced here by the router when a
/// signed-in user isn't verified yet. Once verified, the router's redirect
/// moves a signed-in user on to home by itself.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, this.email});

  final String? email;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeKey = GlobalKey<CodeInputState>();
  String _code = '';
  bool _loading = false;
  bool _resending = false;
  int _countdown = 0;
  Timer? _timer;

  String get _email => (widget.email?.isNotEmpty ?? false) ? widget.email! : context.read<AuthController>().email;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_email.isEmpty) Toast.warning('No email address found. Please register again.');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!RegExp(r'^[A-Z0-9]{6}$', caseSensitive: false).hasMatch(_code)) {
      Toast.error('Please enter the full 6-character code.');
      return;
    }
    setState(() => _loading = true);
    final auth = context.read<AuthController>();
    try {
      await auth.verifyEmail(_code);
      Toast.success(
        'Email verified!',
        description: auth.isLoggedIn ? 'Welcome! Redirecting…' : 'Welcome! Please sign in.',
      );
      // Signed in → the router sends us home. Fresh registration → sign in.
      if (!auth.isLoggedIn && mounted) context.go('/login');
    } catch (err) {
      debugPrint('❌ verifyEmail failed: $err');
      Toast.error(toUserMessage(err, 'The code is incorrect or expired.'));
      _codeKey.currentState?.clear();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_email.isEmpty || _countdown > 0) return;
    setState(() => _resending = true);
    try {
      await context.read<AuthController>().resendVerificationEmail(_email);
      Toast.success(
        'Code sent!',
        description: 'A new code has been sent to your email. Check spam/promotions if it’s not in your inbox.',
      );
      _startCooldown();
    } catch (err) {
      Toast.error(toUserMessage(err, 'Couldn’t send a new code. Please try again later.'));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _startCooldown() {
    setState(() => _countdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _countdown--);
      if (_countdown <= 0) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = context.watch<AuthController>();
    final email = _email;

    return AuthShell(
      title: 'Verify your email',
      subtitle: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Enter the 6-character code we sent to '),
            TextSpan(
              text: email.isEmpty ? 'your email' : email,
              style: TextStyle(color: c.gray600, fontWeight: FontWeight.w500),
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
      children: [
        CodeInput(
          key: _codeKey,
          enabled: !_loading && !_resending,
          onChanged: (v) => setState(() => _code = v),
          onCompleted: (_) => _verify(),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Verify email',
          loadingLabel: 'Verifying…',
          trailingArrow: false,
          loading: _loading,
          onPressed: _code.length == 6 ? _verify : null,
        ),
        ResendCodeRow(onResend: email.isEmpty ? null : _resend, sending: _resending, countdown: _countdown),
        // A signed-in but unverified user has no other way out of this gate.
        if (auth.isLoggedIn)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Center(
              child: TextButton(
                onPressed: auth.logout,
                child: Text('Sign out', style: TextStyle(fontSize: 13, color: c.gray500)),
              ),
            ),
          )
        else
          AuthLinkLine(text: '', link: 'Back to sign in', onTap: () => context.go('/login')),
      ],
    );
  }
}
