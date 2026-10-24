import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import '../widgets/copilot_widgets.dart';

// The workspace menu's footer: Earn bonus credits (InviteCreditsModal.jsx),
// What's new (WhatsNewPanel.jsx) and Leave feedback (FeedbackModal.jsx).
// All three open OVER the workspace — you are asking about the app, not
// leaving the copilot you were talking to.

// ── What's new ──────────────────────────────────────────────────────────────

/// ⚠️ EMPTY, AND THAT IS THE HONEST STATE: there is no changelog feed yet, and
/// invented release notes would put words in the product's mouth. A popover on
/// the web; a short sheet here.
Future<void> showWhatsNew(BuildContext context) => showCopilotSheet<void>(
  context,
  title: "What's New in Copilot",
  builder: (ctx) => SizedBox(
    height: 260,
    child: Center(
      child: Text('No Copilot updates yet.', style: TextStyle(fontSize: 13.5, color: ctx.colors.gray400)),
    ),
  ),
);

// ── Feedback ────────────────────────────────────────────────────────────────

/// Worst to best — the order is the scale. `value` is what the backend will store.
const _ratings = [
  ('bad', 'Bad', LucideIcons.thumbsDown),
  ('poor', 'Poor', LucideIcons.frown),
  ('okay', 'Okay', LucideIcons.meh),
  ('good', 'Good', LucideIcons.smilePlus),
  ('love', 'Love it', LucideIcons.heart),
];

/// A rating and an optional note. ⚠️ THE RATING IS REQUIRED, THE NOTE IS NOT —
/// a one-tap answer is the reason this is five faces. UI only, like the web.
Future<void> showFeedback(BuildContext context) =>
    showCopilotSheet<void>(context, builder: (ctx) => const _FeedbackBody());

class _FeedbackBody extends StatefulWidget {
  const _FeedbackBody();

  @override
  State<_FeedbackBody> createState() => _FeedbackBodyState();
}

class _FeedbackBodyState extends State<_FeedbackBody> {
  String? _rating;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "How's your experience?",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.gray900),
            ),
            const SizedBox(height: 4),
            Text('Your feedback shapes what we build next.', style: TextStyle(fontSize: 13, color: c.gray500)),
            const SizedBox(height: 20),
            Row(
              children: [
                for (final (value, label, icon) in _ratings)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _rating = value),
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _rating == value ? AppColors.blue600 : c.gray100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, size: 20, color: _rating == value ? Colors.white : c.gray500),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: _rating == value ? FontWeight.w600 : FontWeight.w400,
                              color: _rating == value ? c.gray900 : c.gray500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _note,
              minLines: 4,
              maxLines: 6,
              style: TextStyle(fontSize: 14, color: c.gray900),
              decoration: copilotFieldDecoration(
                context,
                "Tell us what's on your mind...",
              ).copyWith(fillColor: c.gray100),
            ),
            const SizedBox(height: 14),
            InkButton(
              label: 'Send feedback',
              icon: LucideIcons.send,
              expand: true,
              onTap: _rating == null
                  ? null
                  : () {
                      notifyPending('Your feedback');
                      Navigator.pop(context);
                    },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Invite friends & earn credits ───────────────────────────────────────────

/// The programme's numbers, in ONE place — the offer, the steps and the terms
/// all read them, so the promise cannot contradict itself.
const _friendSignup = 30, _copilotCreated = 30, _upgrade = 100;

/// ⚠️ UI ONLY: the referral code is derived from the user so the link is
/// stable for them, but nothing here creates a referral, and "Your Referrals
/// (0)" is a placeholder, not a fetched count.
Future<void> showInviteCredits(BuildContext context) {
  final auth = context.read<AuthController>();
  final raw = '${auth.user?['id'] ?? auth.user?['username'] ?? 'guest'}'.replaceAll(RegExp(r'\W'), '');
  final code = raw.isEmpty ? 'GUEST' : raw.substring(0, raw.length.clamp(0, 6)).toUpperCase();
  return showCopilotSheet<void>(
    context,
    fullHeight: true,
    builder: (ctx) => _InviteBody(link: '${AppConfig.webAppUrl}/register?ref=$code'),
  );
}

class _InviteBody extends StatefulWidget {
  const _InviteBody({required this.link});
  final String link;

  @override
  State<_InviteBody> createState() => _InviteBodyState();
}

class _InviteBodyState extends State<_InviteBody> {
  bool _terms = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = TextStyle(fontSize: 13, height: 1.5, color: c.gray500);
    final h3 = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900);

    Widget bullets(List<String> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in items)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: body),
                Expanded(child: Text(t, style: body)),
              ],
            ),
          ),
      ],
    );

    // ── Terms — a digression from the offer, with a Back to it. ──
    if (_terms) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(
            'Terms & Conditions',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.gray900),
          ),
          const SizedBox(height: 16),
          Text('Eligibility', style: h3),
          bullets([
            'Bonus credits apply only to brand-new users who sign up with your link.',
            'Share your link only with people you know. Spam or public posting may disqualify you.',
          ]),
          const SizedBox(height: 18),
          Text('Credits', style: h3),
          bullets([
            'You earn $_upgrade credits when an invited friend upgrades to a paid plan.',
            'Your friend gets $_friendSignup bonus credits when they sign up with your link.',
            "You can earn rewards for every friend you invite — there's no limit.",
            'Credits have no cash value and cannot be transferred or redeemed for money.',
          ]),
          const SizedBox(height: 18),
          Text('Restrictions', style: h3),
          bullets([
            'Rewards are void if obtained through fraud, fake accounts, or abuse.',
            "Credits are tied to your account and expire per the programme's credit-expiry policy.",
          ]),
          const SizedBox(height: 18),
          Text(
            'By participating, you agree to these terms. Creative Klux may modify or end the programme at any time.',
            style: body,
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _terms = false),
              icon: Icon(LucideIcons.arrowLeft, size: 16, color: c.gray900),
              label: Text(
                'Back',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.gray900),
              ),
            ),
          ),
        ],
      );
    }

    // ── The offer ── (the web's blue gift panel is dropped below `md`, as here)
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Text(
          'Invite Friends & Earn Credits',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: c.gray900),
        ),
        const SizedBox(height: 6),
        Text('Share your link and earn $_upgrade credits when a friend upgrades to a paid plan', style: body),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 40,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.gray100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.gray300),
                ),
                child: SelectableText(widget.link, maxLines: 1, style: TextStyle(fontSize: 13, color: c.gray900)),
              ),
            ),
            const SizedBox(width: 8),
            InkButton(
              label: _copied ? 'Copied' : 'Copy',
              icon: _copied ? LucideIcons.check : LucideIcons.copy,
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.link));
                setState(() => _copied = true);
                Toast.success('Invite link copied');
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('How it Works', style: h3),
        const SizedBox(height: 8),
        for (final (icon, text) in [
          (LucideIcons.share2, 'Share your unique invite link with friends'),
          (LucideIcons.gift, 'They get $_friendSignup free credits when they sign up'),
          (LucideIcons.gift, 'You earn $_copilotCreated credits when they create a copilot'),
          (LucideIcons.gift, 'You earn $_upgrade credits when they upgrade to a paid plan'),
        ])
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: c.gray500),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: body)),
              ],
            ),
          ),
        const SizedBox(height: 20),
        Text('Your Referrals (0)', style: TextStyle(fontSize: 13.5, color: c.gray500)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => setState(() => _terms = true),
            child: Text(
              'Terms & Conditions',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.gray900),
            ),
          ),
        ),
      ],
    );
  }
}
