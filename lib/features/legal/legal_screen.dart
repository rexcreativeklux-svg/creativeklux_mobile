import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'legal_content.dart';

/// The legal pages' link blue (`#1447e6`), fixed as on the web.
const _linkBlue = AppColors.primary;

/// /privacy and /terms — port of `(legal)/privacy`, `(legal)/terms` and
/// their shared `(components)/legal/LegalLayout.jsx`: a header, the hero
/// (title, last updated, summary), "On this page", the sections, and the
/// footer links. The text is identical to the web's (legal_content.dart).
///
/// ⚠️ PUBLIC: the sign-in and register screens link here, so these pages
/// must open signed out — they stand outside the dashboard shell and read
/// the session only to choose between "Get started" and nothing.
///
/// "On this page" scrolls to the section, like the web's `#anchor` links.
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, required this.document});

  const LegalScreen.privacy({super.key}) : document = privacyPolicy;
  const LegalScreen.terms({super.key}) : document = termsOfService;

  final LegalDocument document;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late final _keys = {for (final s in widget.document.sections) s.id: GlobalKey()};

  void _jump(String id) {
    final ctx = _keys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  void _back(bool signedIn) => context.canPop() ? context.pop() : context.go(signedIn ? '/' : '/login');

  /// Terms ↔ Privacy replaces this page rather than stacking another.
  void _open(String path) => context.pushReplacement(path);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final doc = widget.document;
    final signedIn = context.select<AuthController, bool>((a) => a.isLoggedIn);

    return Scaffold(
      backgroundColor: c.page,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(bottom: BorderSide(color: c.gray100)),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => _back(signedIn),
                    icon: Icon(LucideIcons.chevronLeft, size: 20, color: c.gray900),
                  ),
                  Image.asset('assets/images/logo.png', width: 26, height: 26),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Creative Klux',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
                    ),
                  ),
                  if (!signedIn)
                    FilledButton(
                      onPressed: () => context.go('/register'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _linkBlue,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Get started'),
                    ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 32 + MediaQuery.paddingOf(context).bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero
                    Text(
                      doc.title,
                      style: TextStyle(fontSize: 24, height: 1.2, fontWeight: FontWeight.w700, color: c.gray900),
                    ),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        text: 'Last updated: ',
                        style: TextStyle(fontSize: 12.5, color: c.gray400),
                        children: [
                          TextSpan(
                            text: doc.updated,
                            style: TextStyle(color: c.gray500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(doc.summary, style: TextStyle(fontSize: 14, height: 1.7, color: c.gray500)),
                    const SizedBox(height: 22),
                    Divider(height: 1, color: c.gray100),
                    const SizedBox(height: 22),

                    // Table of contents
                    Text(
                      'ON THIS PAGE',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: c.gray400),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: c.gray100, width: 1.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final s in doc.sections)
                            InkWell(
                              onTap: () => _jump(s.id),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                                child: Text(s.tocLabel, style: TextStyle(fontSize: 13, color: c.gray500)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Article
                    for (final s in doc.sections) _Section(key: _keys[s.id], section: s),

                    // Footer
                    const SizedBox(height: 16),
                    Divider(height: 1, color: c.gray100),
                    const SizedBox(height: 20),
                    Text(
                      '© ${DateTime.now().year} Creative Klux. All rights reserved.',
                      style: TextStyle(fontSize: 12.5, color: c.gray400),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 4,
                      children: [
                        _FooterLink('Terms', doc == termsOfService ? null : () => _open('/terms')),
                        _FooterLink('Privacy', doc == privacyPolicy ? null : () => _open('/privacy')),
                        if (!signedIn) _FooterLink('Sign in', () => context.go('/login')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink(this.label, this.onTap);
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
        foregroundColor: c.gray500,
        disabledForegroundColor: c.gray900,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({super.key, required this.section});
  final LegalSection section;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.gray900),
          ),
          const SizedBox(height: 10),
          for (final b in section.blocks)
            switch (b) {
              LegalP(:final text) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _Paragraph(text)),
              LegalSub(:final text) => Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  text,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray800),
                ),
              ),
              LegalBullets(:final items) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(top: 8, right: 10, left: 2),
                              decoration: const BoxDecoration(color: _linkBlue, shape: BoxShape.circle),
                            ),
                            Expanded(
                              child: Text(item, style: TextStyle(fontSize: 14, height: 1.6, color: c.gray500)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            },
        ],
      ),
    );
  }
}

/// A paragraph; `{email}` becomes the tappable support address (mailto).
class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);
  final String text;

  Future<void> _mail() async {
    final ok = await launchUrl(Uri(scheme: 'mailto', path: legalEmail));
    if (!ok) Toast.error("Couldn't open your email app.", description: legalEmail);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(fontSize: 14, height: 1.7, color: c.gray500);
    final parts = text.split('{email}');
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            TextSpan(text: parts[i]),
            if (i < parts.length - 1)
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  onTap: _mail,
                  child: Text(legalEmail, style: style.copyWith(color: _linkBlue)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
