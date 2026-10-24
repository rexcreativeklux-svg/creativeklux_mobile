import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../studio_form_kit.dart';
import 'social_sizes.dart';

// Port of `studio/forms/social/KindFields.jsx`: the fields that belong to ONE
// kind of social image. Everything the four kinds share — brand, description,
// colour, logo, size, goal, audience, format, images — lives in the form itself;
// only what actually differed is here.
//
// ⚠️ SHORT ON PURPOSE. Banner Type, Headline, Tagline, Video Title, Content
// Category, Emotion / Hook, Preferred Font and Additional Notes were all
// commented out in the old web forms before the merge, and were not carried over.

/// Post Tone — posts and memes. How the copy should sound.
class ToneField extends StatelessWidget {
  const ToneField({super.key, required this.value, required this.onChanged, required this.accent});

  final String? value;
  final ValueChanged<String> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) => FormFieldBlock(
    label: 'Post Tone',
    child: ChipWrap(
      children: [
        for (final t in socialTones)
          OptionChip(label: t.label, accent: accent, active: value == t.value, onTap: () => onChanged(t.value)),
      ],
    ),
  );
}

/// Call to Action — banners. Presets plus a free-text box, because a banner's
/// CTA is frequently none of the common seven.
///
/// The box shows a value only when it ISN'T one of the presets: tapping
/// "Shop Now" leaves it empty rather than mirroring the chip, so the two
/// controls read as one choice instead of two that happen to agree.
class CtaField extends StatefulWidget {
  const CtaField({super.key, required this.value, required this.onChanged, required this.accent});

  final String? value;
  final ValueChanged<String> onChanged;
  final Color accent;

  @override
  State<CtaField> createState() => _CtaFieldState();
}

class _CtaFieldState extends State<CtaField> {
  late final _custom = TextEditingController(text: _customText(widget.value));

  static String _customText(String? v) => v == null || ctaOptions.contains(v) ? '' : v;

  @override
  void didUpdateWidget(CtaField old) {
    super.didUpdateWidget(old);
    final want = _customText(widget.value);
    if (_custom.text != want) _custom.text = want;
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormFieldBlock(
    label: 'Call to Action (CTA)',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChipWrap(
          children: [
            for (final cta in ctaOptions)
              OptionChip(
                label: cta,
                accent: widget.accent,
                active: widget.value == cta,
                onTap: () => widget.onChanged(cta),
              ),
          ],
        ),
        const SizedBox(height: 8),
        StudioTextField(controller: _custom, accent: widget.accent, hint: 'Custom CTA…', onChanged: widget.onChanged),
      ],
    ),
  );
}

/// Visual Style — banners and thumbnails, with DIFFERENT option lists (a
/// thumbnail's "Bold & High Contrast" is not a banner's "Bold"). The list comes
/// from the kind, so nothing here needs to know which kind it draws for.
class StyleField extends StatelessWidget {
  const StyleField({
    super.key,
    required this.value,
    required this.styles,
    required this.onChanged,
    required this.accent,
  });

  final String? value;
  final List<SocialOption> styles;
  final ValueChanged<String> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) => FormFieldBlock(
    label: 'Visual Style',
    child: ChipWrap(
      children: [
        for (final s in styles)
          OptionChip(label: s.label, accent: accent, active: value == s.value, onTap: () => onChanged(s.value)),
      ],
    ),
  );
}

/// Lays [children] out [columns] across with equal widths — for the pickers
/// with many two-line tiles (sizes, audiences, durations), which as a loose
/// wrap on a 360dp phone leave ragged half-empty rows.
class SocialChoiceGrid extends StatelessWidget {
  const SocialChoiceGrid({super.key, required this.children, this.columns = 2});

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const gap = 8.0;
      final w = (box.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final c in children) SizedBox(width: w, child: c)],
      );
    },
  );
}

/// The Social Creative kind tag row — filled when active, unlike the tinted
/// [OptionChip], because it decides what the rest of the form IS.
class SocialKindTag extends StatelessWidget {
  const SocialKindTag({
    super.key,
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: active ? accent : c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: active ? accent : accent.withValues(alpha: 0.25), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : Color.lerp(accent, Colors.black, 0.2),
            ),
          ),
        ),
      ),
    );
  }
}
