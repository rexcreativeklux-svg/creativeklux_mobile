import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/section_tabs.dart';
import '../shell/widgets/app_top_bar.dart';

/// Pieces every Ad Intelligence page repeats — the phone versions of the
/// little components each web page declares for itself (Card, SectionLabel,
/// StatusBadge, the error strip, the empty/loading panels, the RadialBarChart
/// gauges).

/// The section's pages — `ad-intelligence/layout.jsx` NAV_ITEMS.
final adIntelTabs = [
  SectionTab('Ad Performance', '/ad-intelligence/ad-performance', LucideIcons.lightbulb),
  SectionTab('Market Spy', '/ad-intelligence/market-spy', LucideIcons.search),
  SectionTab('Ad Guard AI', '/ad-intelligence/ad-guard-ai', LucideIcons.shieldCheck),
  SectionTab('Ad Scorer AI', '/ad-intelligence/ad-scorer-ai', LucideIcons.star),
  SectionTab('Creative Comparison', '/ad-intelligence/creative-comparison', LucideIcons.gitCompareArrows),
];

// Tool hues, straight from the web pages' Tailwind classes. They're accents
// (headers, buttons, highlights) — every neutral still comes from the gray ramp.
class AiHue {
  AiHue._();
  static const emerald = Color(0xFF10B981);
  static const emeraldDeep = Color(0xFF059669);
  static const teal = Color(0xFF0D9488);
  static const amber = Color(0xFFF59E0B);
  static const orangeDeep = Color(0xFFEA580C);
  static const orange = Color(0xFFF97316);
  static const violet = Color(0xFF8B5CF6);
  static const purple = Color(0xFF9333EA);
  static const pink = Color(0xFFEC4899);
  static const rose = Color(0xFFF43F5E);
  static const indigo = Color(0xFF6366F1);
  static const indigoDeep = Color(0xFF4F46E5);
  static const violetDeep = Color(0xFF7C3AED);
  static const blue = Color(0xFF2563EB);
  static const navy = Color(0xFF1E3A8A);
  static const green = Color(0xFF22C55E);
  static const greenDeep = Color(0xFF16A34A);
  static const red = Color(0xFFEF4444);
  static const redDeep = Color(0xFFDC2626);
  static const yellow = Color(0xFFCA8A04);
}

/// The 80/60/40 score ramp most pages share (Ad Guard / Comparison use
/// emerald for the top band, Ad Scorer uses green — pass [top]).
Color scoreColor(num s, {Color top = AiHue.emerald}) =>
    s >= 80 ? top : (s >= 60 ? AiHue.blue : (s >= 40 ? AiHue.orange : AiHue.red));

/// `{High, Medium, Low}` priority pill colours (priorityClass in the pages).
Color? priorityColor(String? p) => switch (p) {
  'High' => AiHue.redDeep,
  'Medium' => AiHue.orangeDeep,
  'Low' => AiHue.greenDeep,
  _ => null,
};

/// One Ad Intelligence page: top bar, the section tabs (the web's secondary
/// sidebar), and a scrolling body with 16px gutters.
class AdIntelPage extends StatelessWidget {
  const AdIntelPage({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Ad Intelligence'),
          SectionTabs(tabs: adIntelTabs, location: GoRouterState.of(context).uri.path),
          Expanded(
            child: Container(
              color: c.page,
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The gradient icon tile + title + one-line pitch that opens every page.
class ToolHeader extends StatelessWidget {
  const ToolHeader({super.key, required this.icon, required this.colors, required this.title, required this.subtitle});

  final IconData icon;
  final List<Color> colors;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.gray900),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12.5, height: 1.35, color: c.gray500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `bg-surface border rounded-2xl` — the card every result sits in.
class AiCard extends StatelessWidget {
  const AiCard({super.key, required this.child, this.padding = 16, this.tint, this.margin = 12});

  final Widget child;
  final double padding;

  /// A soft accent wash (the web's `from-emerald-50 via-white to-teal-50`).
  final Color? tint;
  final double margin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: margin),
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: tint == null ? c.surface : Color.alphaBlend(tint!.withValues(alpha: 0.07), c.surface),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint == null ? c.gray200 : tint!.withValues(alpha: 0.25)),
      ),
      child: child,
    );
  }
}

/// `font-bold text-sm mb-4` card titles.
class CardTitle extends StatelessWidget {
  const CardTitle(this.text, {super.key, this.color, this.trailing, this.bottom = 12});

  final String text;
  final Color? color;
  final Widget? trailing;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      text,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color ?? context.colors.gray800),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: trailing == null
          ? title
          : Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 8),
                trailing!,
              ],
            ),
    );
  }
}

/// The grey inset row/box used inside cards (`bg-gray-50 border-gray-100 rounded-xl`).
class InsetBox extends StatelessWidget {
  const InsetBox({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.margin = 8});

  final Widget child;
  final EdgeInsets padding;
  final double margin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: margin),
      padding: padding,
      decoration: BoxDecoration(
        color: c.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray100),
      ),
      child: child,
    );
  }
}

/// The red `AlertCircle` strip under an input.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key, this.bottom = 12});

  final String message;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: bottom),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.redTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red500.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(LucideIcons.circleAlert, size: 16, color: AppColors.red500),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.red600)),
          ),
        ],
      ),
    );
  }
}

/// The big centred empty / loading panels (`py-24` / `h-64` boxes).
class StatePanel extends StatelessWidget {
  const StatePanel({super.key, required this.icon, this.title, this.subtitle, this.action, this.minHeight = 240});

  /// A loading spinner, or a tinted icon tile.
  final Widget icon;
  final String? title;
  final String? subtitle;
  final Widget? action;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          if (title != null) ...[
            const SizedBox(height: 14),
            Text(
              title!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray600),
            ),
          ],
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.4, color: c.gray400),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// A rounded tinted tile holding an icon — the empty states' `w-16 h-16 bg-x-50`.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, required this.color, this.size = 56});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
    child: Icon(icon, size: size * 0.44, color: color.withValues(alpha: 0.55)),
  );
}

/// A spinner in a tool's colour.
class Spinner extends StatelessWidget {
  const Spinner({super.key, required this.color, this.size = 36, this.stroke = 3});

  final Color color;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CircularProgressIndicator(strokeWidth: stroke, color: color),
  );
}

/// A small tinted pill (`text-[10px] font-bold px-2 py-0.5 rounded-full`).
class TintPill extends StatelessWidget {
  const TintPill(this.text, {super.key, required this.color, this.icon, this.fontSize = 10.5, this.border = true});

  final String text;
  final Color color;
  final IconData? icon;
  final double fontSize;
  final bool border;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(99),
      border: border ? Border.all(color: color.withValues(alpha: 0.25)) : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: fontSize + 1, color: color), const SizedBox(width: 4)],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    ),
  );
}

/// Passed / Failed / Warning (Ad Guard's StatusBadge). Unknown → Warning.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      'Passed' => (LucideIcons.circleCheck, AiHue.emeraldDeep),
      'Failed' => (LucideIcons.circleX, AiHue.redDeep),
      _ => (LucideIcons.triangleAlert, AiHue.amber),
    };
    return TintPill(status ?? 'Warning', color: color, icon: icon, fontSize: 11);
  }
}

/// The gradient call-to-action buttons (`bg-linear-to-r from-x to-y`).
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.colors,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.loadingLabel,
    this.expand = true,
    this.height = 44,
  });

  final String label;
  final List<Color> colors;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  /// Shown next to the spinner; null = spinner only (the web's input-row buttons).
  final String? loadingLabel;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        else if (icon != null)
          Icon(icon, size: 16, color: Colors.white),
        if (!loading || loadingLabel != null) ...[
          if (loading || icon != null) const SizedBox(width: 8),
          Text(
            loading ? loadingLabel! : label,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ],
      ],
    );
    return Opacity(
      // Loading keeps full strength like the web; only a disabled button fades.
      opacity: onPressed == null && !loading ? 0.45 : 1,
      child: Material(
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          height: height,
          decoration: BoxDecoration(gradient: LinearGradient(colors: colors)),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: content),
          ),
        ),
      ),
    );
  }
}

/// Recharts' RadialBarChart gauges (start at 12 o'clock, clockwise, rounded
/// ends, a grey track) as one painter, with [child] centred inside.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.value,
    required this.color,
    required this.size,
    required this.stroke,
    this.child,
  });

  /// 0–100.
  final num value;
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _RingPainter(value.clamp(0, 100).toDouble(), color, context.colors.gray200, stroke),
      child: Center(child: child),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track, this.stroke);

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: (size.shortestSide - stroke) / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value / 100, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.stroke != stroke;
}

/// An N-column grid that sizes its cells from the width it gets — for the
/// web's `grid-cols-2 md:grid-cols-4` stat rows inside a scrolling page.
class FlowGrid extends StatelessWidget {
  const FlowGrid({super.key, required this.children, this.columns = 2, this.wideColumns, this.gap = 10});

  final List<Widget> children;
  final int columns;

  /// Columns from 600px up (tablet / landscape); defaults to [columns].
  final int? wideColumns;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cols = box.maxWidth >= 600 ? (wideColumns ?? columns) : columns;
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    },
  );
}

/// Two cards the web puts side by side (`md:grid-cols-2`): stacked on a
/// phone, a row from 700px.
class PairRow extends StatelessWidget {
  const PairRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < 700 || children.length < 2) return Column(children: children);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: children[i]),
          ],
        ],
      );
    },
  );
}

/// A bullet line (`• text`, `→ text`) used by the list cards.
class BulletLine extends StatelessWidget {
  const BulletLine(this.text, {super.key, required this.bullet, required this.color});

  final String text;
  final String bullet;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 16,
          child: Text(bullet, style: TextStyle(fontSize: 12.5, color: color)),
        ),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12.5, height: 1.45, color: context.colors.gray500)),
        ),
      ],
    ),
  );
}

/// A small uppercase field label (`text-[10px] font-bold uppercase tracking-wider`).
class TinyLabel extends StatelessWidget {
  const TinyLabel(this.text, {super.key, this.color, this.bottom = 4});

  final String text;
  final Color? color;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottom),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: color ?? context.colors.gray400,
      ),
    ),
  );
}

/// The numbered circle in Action Plan / Recommendations.
class StepDot extends StatelessWidget {
  const StepDot(this.n, {super.key, required this.color, this.filled = false});

  final int n;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    alignment: Alignment.center,
    decoration: BoxDecoration(shape: BoxShape.circle, color: filled ? color : color.withValues(alpha: 0.15)),
    child: Text(
      '$n',
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: filled ? Colors.white : color),
    ),
  );
}

/// The single-field input row on Ad Performance and Market Spy.
class InputRow extends StatelessWidget {
  const InputRow({
    super.key,
    required this.controller,
    required this.hint,
    required this.button,
    required this.onSubmit,
    required this.focusColor,
    this.icon,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final Widget button;
  final VoidCallback onSubmit;
  final Color focusColor;
  final IconData? icon;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    OutlineInputBorder border(Color color, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: w),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => onSubmit(),
                style: TextStyle(fontSize: 13.5, color: c.gray800),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: c.surface,
                  hintText: hint,
                  hintMaxLines: 1,
                  hintStyle: TextStyle(fontSize: 13, color: c.gray400, overflow: TextOverflow.ellipsis),
                  prefixIcon: icon == null ? null : Icon(icon, size: 16, color: c.gray400),
                  prefixIconConstraints: const BoxConstraints(minWidth: 38),
                  contentPadding: EdgeInsets.fromLTRB(icon == null ? 14 : 0, 12, 12, 12),
                  enabledBorder: border(c.gray200),
                  focusedBorder: border(focusColor, 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          button,
        ],
      ),
    );
  }
}
