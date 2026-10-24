import 'dart:async';

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
import '../widgets/code_input.dart';

const _codeLength = 6;
const _minPasswordLength = 8;

/// Port of `(auth)/change-password/page.jsx` — steps 2 and 3 of the reset,
/// on one screen: verify the emailed code, then set a new password.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.email});

  final String email;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

enum _Step { code, password }

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  _Step _step = _Step.code;

  final _codeKey = GlobalKey<CodeInputState>();
  String _code = '';
  bool _verifying = false;
  bool _resending = false;
  int _countdown = 0;
  Timer? _timer;

  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _resetting = false;

  /// The code confirmed in step 1, sent alongside the new password in step 2.
  String _verifiedCode = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.email.isEmpty) Toast.warning('No email found. Please start the reset again.');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    if (_code.length != _codeLength) {
      Toast.error('Please enter all 6 digits.');
      return;
    }
    setState(() => _verifying = true);
    try {
      await context.read<AuthController>().verifyResetCode(widget.email, _code);
      _verifiedCode = _code;
      Toast.success('Code verified.', description: 'Now choose a new password.');
      setState(() => _step = _Step.password);
    } catch (err) {
      debugPrint('❌ verifyResetCode failed: $err');
      Toast.error(toUserMessage(err, 'The code is incorrect or expired.'));
      _codeKey.currentState?.clear();
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    if (widget.email.isEmpty || _countdown > 0 || _resending) return;
    setState(() => _resending = true);
    try {
      await context.read<AuthController>().sendResetCode(widget.email);
      Toast.success(
        'Code sent!',
        description: 'A new code is on its way. Check spam/promotions if it’s not in your inbox.',
      );
      setState(() => _countdown = 60);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _countdown--);
        if (_countdown <= 0) t.cancel();
      });
    } catch (err) {
      Toast.error(toUserMessage(err, 'Couldn’t send a new code. Please try again.'));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_password.text.length < _minPasswordLength) {
      Toast.error('Password must be at least $_minPasswordLength characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      Toast.error('Passwords do not match.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _resetting = true);
    try {
      final msg = await context.read<AuthController>().resetPassword(
        email: widget.email,
        code: _verifiedCode,
        password: _password.text,
        passwordConfirmation: _confirm.text,
      );
      Toast.success(msg);
      if (mounted) context.go('/login');
    } catch (err) {
      debugPrint('❌ resetPassword failed: $err');
      Toast.error(toUserMessage(err, 'Couldn’t reset your password. Please try again.'));
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final emailSpan = TextSpan(
      text: widget.email.isEmpty ? 'your email' : widget.email,
      style: TextStyle(color: c.gray600, fontWeight: FontWeight.w500),
    );
    final isCode = _step == _Step.code;

    return AuthShell(
      title: isCode ? 'Enter your reset code' : 'Set a new password',
      showBack: true,
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: isCode ? 'Enter the 6-digit code we sent to ' : 'Choose a new password for '),
            emailSpan,
            const TextSpan(text: '.'),
          ],
        ),
      ),
      children: [
        if (isCode) ...[
          CodeInput(
            key: _codeKey,
            enabled: !_verifying && widget.email.isNotEmpty,
            onChanged: (v) => setState(() => _code = v),
            onCompleted: (_) => _verifyCode(),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Verify code',
            loadingLabel: 'Verifying…',
            loading: _verifying,
            onPressed: _code.length == _codeLength && widget.email.isNotEmpty ? _verifyCode : null,
          ),
          ResendCodeRow(onResend: widget.email.isEmpty ? null : _resend, sending: _resending, countdown: _countdown),
        ] else ...[
          AppInput(
            label: 'New password',
            controller: _password,
            placeholder: '••••••••',
            password: true,
            hint: 'At least $_minPasswordLength characters.',
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
          ),
          const SizedBox(height: 14),
          AppInput(
            label: 'Confirm new password',
            controller: _confirm,
            placeholder: '••••••••',
            password: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _resetPassword(),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Update password',
            loadingLabel: 'Updating…',
            loading: _resetting,
            onPressed: _resetPassword,
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Center(
            child: GestureDetector(
              onTap: () => context.go('/login'),
              child: const Text(
                'Back to sign in',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
