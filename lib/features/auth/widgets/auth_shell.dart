import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';

/// The frame shared by every auth screen — the mobile layout of the web's
/// `(auth)/layout.jsx` (brand header row) wrapped around `AuthShell.jsx`
/// (width-capped card with a title and subtitle).
///
/// The desktop showcase panel is left out: on a phone the web hides it too.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.showBack = false,
  });

  final String title;
  final Widget subtitle;
  final List<Widget> children;

  /// Show a back chevron in the header (sub-screens like forgot password).
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Brand header — the web's mobile-only header row.
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.gray100)),
              ),
              child: Row(
                children: [
                  if (showBack && context.canPop())
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: IconButton(
                        onPressed: () => context.pop(),
                        icon: Icon(LucideIcons.chevronLeft, size: 18, color: c.gray500),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  Image.asset('assets/images/logo.png', width: 24, height: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Creative Klux',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                  height: 1.15,
                                  color: c.gray900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DefaultTextStyle.merge(
                                style: TextStyle(fontSize: 13, color: c.gray400, height: 1.4),
                                child: subtitle,
                              ),
                              const SizedBox(height: 24),
                              ...children,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Didn’t receive the code? Resend code" + the spam-folder hint, shared by
/// the verify-email and reset-code screens.
class ResendCodeRow extends StatelessWidget {
  const ResendCodeRow({super.key, required this.onResend, required this.sending, required this.countdown});

  final VoidCallback? onResend;
  final bool sending;
  final int countdown;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final disabled = onResend == null || sending || countdown > 0;
    return Column(
      children: [
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Didn’t receive the code? ', style: TextStyle(fontSize: 13, color: c.gray400)),
            GestureDetector(
              onTap: disabled ? null : onResend,
              child: Text(
                sending
                    ? 'Sending…'
                    : countdown > 0
                    ? 'Resend in ${countdown}s'
                    : 'Resend code',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: disabled ? c.gray300 : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 11, color: c.gray400, height: 1.5),
            children: const [
              TextSpan(text: 'Check your '),
              TextSpan(
                text: 'Spam',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: ', '),
              TextSpan(
                text: 'Promotions',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: ', or '),
              TextSpan(
                text: 'Junk',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: ' folder — emails may take up to 2 minutes.'),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// A centred "text + link" line, e.g. "Don't have an account? Create one free".
class AuthLinkLine extends StatelessWidget {
  const AuthLinkLine({super.key, required this.text, required this.link, required this.onTap});

  final String text;
  final String link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          Text(text, style: TextStyle(fontSize: 13, color: context.colors.gray400)),
          GestureDetector(
            onTap: onTap,
            child: Text(
              link,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// "By signing in you agree to our Terms & Privacy Policy" — with both
/// names tappable, opening the public `/terms` and `/privacy` pages (pushed,
/// so Back returns to the form with what was typed still there).
class LegalConsentLine extends StatelessWidget {
  const LegalConsentLine({super.key, required this.prefix});

  /// e.g. "By signing in you agree to our".
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final link = TextStyle(fontSize: 11, color: c.gray500, decoration: TextDecoration.underline);
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        Text('$prefix ', style: TextStyle(fontSize: 11, color: c.gray300)),
        GestureDetector(
          onTap: () => context.push('/terms'),
          child: Text('Terms', style: link),
        ),
        Text(' & ', style: TextStyle(fontSize: 11, color: c.gray300)),
        GestureDetector(
          onTap: () => context.push('/privacy'),
          child: Text('Privacy Policy', style: link),
        ),
      ],
    );
  }
}
