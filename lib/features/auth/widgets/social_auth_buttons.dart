import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';

/// Port of `auth/AuthProviders.jsx` — "or continue with" divider and the
/// Google / Facebook / TikTok buttons.
///
/// ⚠️ NOT WIRED YET. The web flow opens a popup and receives the result via
/// `window.postMessage` from the backend's callback page, which has no mobile
/// equivalent. It needs the backend to redirect to an app deep link instead
/// (e.g. `creativeklux://auth?token=…`). Until then the buttons say so.
class SocialAuthButtons extends StatelessWidget {
  const SocialAuthButtons({super.key, this.label = 'or continue with'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    void comingSoon() => Toast.info(
      'Coming soon to the app',
      description: 'Social sign-in is on its way. Use your email and password for now.',
    );

    Widget button(String text, Widget icon) => Expanded(
      child: OutlinedButton(
        onPressed: comingSoon,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          side: BorderSide(color: c.gray200),
          backgroundColor: c.surface,
          foregroundColor: c.gray700,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        child: FittedBox(child: Row(children: [icon, const SizedBox(width: 6), Text(text)])),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Divider(color: c.gray100)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: c.gray400),
                ),
              ),
              Expanded(child: Divider(color: c.gray100)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              button('Google', const _BrandMark('G', Color(0xFF4285F4))),
              const SizedBox(width: 10),
              button('Facebook', const _BrandMark('f', Color(0xFF1877F2), filled: true)),
              const SizedBox(width: 10),
              button('TikTok', _BrandMark('♪', c.gray900, filled: true)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small letter-mark standing in for the provider logos.
class _BrandMark extends StatelessWidget {
  const _BrandMark(this.glyph, this.color, {this.filled = false});

  final String glyph;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: filled ? null : Border.all(color: color, width: 1.6),
      ),
      child: Text(
        glyph,
        style: TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w800,
          // TikTok's mark is gray-900, which flips to near-white in dark mode.
          color: filled ? (color.computeLuminance() > 0.5 ? Colors.black : Colors.white) : color,
        ),
      ),
    );
  }
}
