import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/media.dart';
import '../brand.dart';

/// The fonts a brand can pick — the web's FONTS list.
const brandFonts = ['Inter', 'Roboto', 'Poppins', 'Open Sans', 'Lato', 'Montserrat'];

/// The web's INDUSTRIES list.
const brandIndustries = ['Technology', 'Healthcare', 'Retail', 'Finance', 'Education', 'Hospitality', 'Other'];

/// [font] as a TextStyle, falling back to the app font for anything unknown.
TextStyle brandFontStyle(String? font, TextStyle base) {
  if (font == null || font.isEmpty) return base;
  try {
    return GoogleFonts.getFont(font, textStyle: base);
  } catch (_) {
    return base;
  }
}

/// 10px uppercase, widely tracked gray label (`text-[10px] uppercase tracking-widest`).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: text.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: context.colors.gray400),
        children: [
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: AppColors.red500),
            ),
        ],
      ),
    );
  }
}

/// 135° primary → secondary gradient with the faint dot pattern the web
/// draws on brand cards and banners.
class BrandGradient extends StatelessWidget {
  const BrandGradient({super.key, required this.primary, required this.secondary, this.child, this.borderRadius});

  final Color primary;
  final Color secondary;
  final Widget? child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [primary, secondary]),
      ),
      child: CustomPaint(painter: _DotsPainter(), child: child),
    );
  }
}

class _DotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.07);
    const step = 16.0;
    for (var x = step / 2; x < size.width; x += step) {
      for (var y = step / 2; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => false;
}

/// White rounded tile holding the logo, or the brand initial in its colour.
class BrandLogoTile extends StatelessWidget {
  const BrandLogoTile({
    super.key,
    required this.name,
    required this.color,
    this.logoUrl,
    this.logoBytes,
    this.size = 48,
    this.circle = false,
  });

  final String name;
  final Color color;
  final String? logoUrl;
  final Uint8List? logoBytes;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final initial = Center(
      child: Text(
        name.trim().isEmpty ? 'B' : name.trim()[0].toUpperCase(),
        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w900, color: color),
      ),
    );
    final Widget content = logoBytes != null
        ? Image.memory(logoBytes!, fit: BoxFit.contain)
        : logoUrl != null
        ? MediaImage(logoUrl!, fit: BoxFit.contain)
        : initial;

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(logoBytes != null || logoUrl != null ? size * 0.12 : 0),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(size * 0.28),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

/// "Active" (green) / "Draft" (amber) pill — on the web this only means
/// "is this the brand currently switched to".
class BrandStatusPill extends StatelessWidget {
  const BrandStatusPill({super.key, required this.active, this.onDark = true});

  final bool active;

  /// Sitting on a brand gradient (translucent white) vs. on a card.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final dot = active ? const Color(0xFF34D399) : const Color(0xFFFCD34D);
    final bg = onDark
        ? Colors.white.withValues(alpha: 0.2)
        : (active ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB));
    final fg = onDark ? Colors.white : (active ? const Color(0xFF047857) : const Color(0xFFB45309));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            active ? 'Active' : 'Draft',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }
}

/// Small rounded chip (industry, font…).
class InfoChip extends StatelessWidget {
  const InfoChip(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.gray50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.gray100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: c.gray400), const SizedBox(width: 4)],
          Text(
            text,
            style: TextStyle(fontSize: 10.5, color: c.gray600, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// A colour swatch + hex field (the web's ColorPicker). Tapping the swatch
/// opens a palette sheet; the hex field accepts typing.
class ColorField extends StatefulWidget {
  const ColorField({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<ColorField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(ColorField old) {
    super.didUpdateWidget(old);
    if (widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _PaletteSheet(current: widget.value),
    );
    if (picked != null) widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = Brand.parseHex(widget.value) ?? c.gray200;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(widget.label),
        const SizedBox(height: 6),
        Row(
          children: [
            GestureDetector(
              onTap: _pick,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.gray200),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLength: 7,
                style: TextStyle(fontFamily: 'monospace', fontSize: 13.5, color: c.gray900),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]'))],
                onChanged: (v) {
                  if (RegExp(r'^#[0-9a-fA-F]{0,6}$').hasMatch(v)) widget.onChanged(v);
                },
                decoration: brandInputDecoration(context).copyWith(counterText: ''),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PaletteSheet extends StatelessWidget {
  const _PaletteSheet({required this.current});

  final String current;

  // Tailwind 600s/400s and neutrals — a broad, on-brand starting palette.
  static const _palette = [
    '#2563eb', '#155dfc', '#0ea5e9', '#06b6d4', '#14b8a6', '#10b981', '#22c55e', '#84cc16', //
    '#eab308', '#f59e0b', '#f97316', '#ef4444', '#e11d48', '#ec4899', '#d946ef', '#a855f7', //
    '#8b5cf6', '#6366f1', '#1e3a8a', '#0f172a', '#334155', '#64748b', '#94a3b8', '#ffffff', //
    '#7c2d12', '#78350f', '#365314', '#064e3b', '#164e63', '#1e1b4b', '#4a044e', '#000000', //
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick a colour',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final hex in _palette)
                  GestureDetector(
                    onTap: () => Navigator.pop(context, hex),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Brand.parseHex(hex),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: hex.toLowerCase() == current.toLowerCase() ? AppColors.blue600 : c.gray200,
                          width: hex.toLowerCase() == current.toLowerCase() ? 2.5 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Input style shared by the brand forms (`bg-gray-50 border-gray-200 rounded-xl`).
InputDecoration brandInputDecoration(BuildContext context, {String? hint}) {
  final c = context.colors;
  OutlineInputBorder border(Color color, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: w),
  );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(color: c.gray400, fontSize: 14),
    filled: true,
    fillColor: c.gray50,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    enabledBorder: border(c.gray200),
    focusedBorder: border(AppColors.blue500, 1.5),
    border: border(c.gray200),
  );
}

/// Live brand card preview (BrandPreview.jsx): gradient banner with the logo
/// tile, name in the chosen font, tagline, description, chips, palette and
/// typography cards.
class BrandPreviewCard extends StatelessWidget {
  const BrandPreviewCard({
    super.key,
    required this.name,
    required this.tagline,
    required this.description,
    required this.industry,
    required this.font,
    required this.primary,
    required this.secondary,
    this.logoUrl,
    this.logoBytes,
    this.emptyDescription = 'Your brand description will appear here once you fill in the details.',
  });

  final String name;
  final String tagline;
  final String description;
  final String industry;
  final String font;
  final String primary;
  final String secondary;
  final String? logoUrl;
  final Uint8List? logoBytes;
  final String emptyDescription;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = Brand.parseHex(primary) ?? AppColors.brandFallback;
    final s = Brand.parseHex(secondary) ?? const Color(0xFF10B981);

    Widget card({required Widget child}) => Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.gray100),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Live preview'),
        const SizedBox(height: 8),
        card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 112,
                child: BrandGradient(
                  primary: p,
                  secondary: s,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Row(
                          children: [
                            for (final col in [p, s])
                              Container(
                                width: 20,
                                height: 20,
                                margin: const EdgeInsets.only(left: 4),
                                decoration: BoxDecoration(
                                  color: col,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 14,
                        bottom: 12,
                        child: BrandLogoTile(name: name, color: p, logoUrl: logoUrl, logoBytes: logoBytes, size: 56),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.trim().isEmpty ? 'Your Brand' : name,
                      style: brandFontStyle(
                        font,
                        TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.gray900),
                      ),
                    ),
                    if (tagline.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        tagline,
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: c.gray400),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      description.trim().isEmpty ? emptyDescription : description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, height: 1.45, color: c.gray500),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [if (industry.isNotEmpty) InfoChip(industry), if (font.isNotEmpty) InfoChip(font)],
                    ),
                  ],
                ),
              ),
              Container(
                height: 4,
                decoration: BoxDecoration(gradient: LinearGradient(colors: [p, s])),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Palette'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final (col, hex) in [(p, primary), (s, secondary)])
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(8)),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              hex,
                              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: c.gray600),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Typography'),
                const SizedBox(height: 8),
                Text('Aa Bb Cc — $font', style: brandFontStyle(font, TextStyle(fontSize: 16, color: c.gray800))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
