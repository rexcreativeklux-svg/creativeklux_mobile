import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/media.dart';
import '../../../core/ui/toast.dart';
import '../../brand/brand.dart';
import 'creatives_config.dart';
import 'custom_studio_api.dart';

/// Building blocks shared by every Custom Creation form — the pieces the web's
/// `studio/forms/*.jsx` each re-declare (Field, SectionTitle, the step bar,
/// the URL import box, OptionChip, the nav buttons…), built once here.
///
/// A form is a [StatefulWidget] that takes a [StudioFormHost], keeps its own
/// field state, and calls [StudioFormHost.generate] with the web's payload.

// ── Host ────────────────────────────────────────────────────────────────────

/// What every form receives — the web's `commonProps`.
class StudioFormHost {
  const StudioFormHost({
    required this.creative,
    required this.category,
    required this.brand,
    required this.api,
    required this.generate,
  });

  final StudioCreative creative;
  final StudioCategory category;
  final Brand? brand;
  final CustomStudioApi api;

  /// Run create-design with the form's payload (the web's
  /// `generateCustomCreative`). Put `creativeType` and `categoryType` in it, as
  /// the web does. The screen shows the loading overlay, streams batches into
  /// the results view, and switches to it on the first batch.
  ///
  /// Resolves with an error message when every batch failed, else null.
  final Future<String?> Function(Map<String, dynamic> payload) generate;

  Color get color => creative.color;

  /// `activeBrand?.<field>` defaults, as the web forms seed their state.
  String get brandName => brand?.name ?? '';
  String get brandDescription => brand?.description ?? '';
  String? get brandLogo => brand?.logoUrl;
  String get brandUrl => brand?.url ?? '${brand?.raw['source_url'] ?? ''}';
  String get brandPrimary => brand?.primaryColor ?? hexOf(color);
  String? get brandSecondary => brand?.secondaryColor;
}

/// `#rrggbb` for a colour.
String hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// A colour from `#rgb` / `#rrggbb`, or [fallback].
Color colorOf(String? hex, [Color? fallback]) => Brand.parseHex(hex) ?? fallback ?? AppColors.blue600;

/// ISO timestamp the web puts on every payload as `generatedAt`.
String nowIso() => DateTime.now().toUtc().toIso8601String();

/// Random pick for the "✨ Inspire Me" buttons.
String pickPrompt(List<String> prompts) => prompts[Random().nextInt(prompts.length)];

// ── Layout ──────────────────────────────────────────────────────────────────

/// The web's `<SectionTitle>`.
class FormSectionTitle extends StatelessWidget {
  const FormSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.colors.gray900),
  );
}

/// The web's `<Field label required>`: a small grey label over its input.
class FormFieldBlock extends StatelessWidget {
  const FormFieldBlock({super.key, required this.label, required this.child, this.required = false, this.trailing});

  final String label;
  final bool required;
  final Widget child;

  /// Right-aligned extra on the label row (a counter, a hint).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text.rich(
                TextSpan(
                  text: label,
                  children: [
                    if (required)
                      const TextSpan(
                        text: ' *',
                        style: TextStyle(color: AppColors.red500),
                      ),
                  ],
                ),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
              ),
            ),
            if (trailing != null) ...[const Spacer(), trailing!],
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// Vertical stack with the web's `gap-5` between fields.
class FormColumn extends StatelessWidget {
  const FormColumn({super.key, required this.children, this.gap = 18});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
    ],
  );
}

// ── Inputs ──────────────────────────────────────────────────────────────────

InputDecoration _decoration(BuildContext context, Color accent, String? hint) {
  final c = context.colors;
  OutlineInputBorder border(Color color, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: color, width: w),
  );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(fontSize: 13, color: c.gray400),
    filled: true,
    fillColor: c.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    enabledBorder: border(c.gray200),
    focusedBorder: border(accent, 1.5),
    border: border(c.gray200),
  );
}

/// The web's `inputCls` text input / textarea. With [onInspire] it gets the
/// "✨ Inspire Me" button bottom-left; with [maxLength] a counter bottom-right.
class StudioTextField extends StatelessWidget {
  const StudioTextField({
    super.key,
    required this.controller,
    required this.accent,
    this.hint,
    this.maxLines = 1,
    this.maxLength,
    this.onInspire,
    this.onChanged,
    this.keyboardType,
  });

  final TextEditingController controller;
  final Color accent;
  final String? hint;
  final int maxLines;
  final int? maxLength;
  final VoidCallback? onInspire;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final field = TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: maxLines > 1 ? maxLines : null,
      keyboardType: keyboardType ?? (maxLines > 1 ? TextInputType.multiline : null),
      inputFormatters: [if (maxLength != null) LengthLimitingTextInputFormatter(maxLength)],
      onChanged: onChanged,
      style: TextStyle(fontSize: 13.5, color: c.gray900, height: 1.4),
      decoration: _decoration(
        context,
        accent,
        hint,
      ).copyWith(contentPadding: EdgeInsets.fromLTRB(12, 11, 12, onInspire != null || maxLength != null ? 40 : 11)),
    );
    if (onInspire == null && maxLength == null) return field;
    return Stack(
      children: [
        field,
        if (onInspire != null)
          Positioned(
            left: 8,
            bottom: 8,
            child: OutlinedButton(
              onPressed: onInspire,
              style: OutlinedButton.styleFrom(
                foregroundColor: c.gray600,
                side: BorderSide(color: c.gray200),
                backgroundColor: c.surface,
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
              child: const Text('✨ Inspire Me'),
            ),
          ),
        if (maxLength != null)
          Positioned(
            right: 12,
            bottom: 14,
            child: ListenableBuilder(
              listenable: controller,
              builder: (_, _) =>
                  Text('${controller.text.length}/$maxLength', style: TextStyle(fontSize: 10, color: c.gray400)),
            ),
          ),
      ],
    );
  }
}

/// "Import from URL — auto-fills brand info": the tinted box at the top of
/// every form's first step.
class UrlImportBox extends StatelessWidget {
  const UrlImportBox({
    super.key,
    required this.controller,
    required this.accent,
    required this.loading,
    required this.onImport,
    this.title = 'Import from URL',
    this.hint = 'Auto-fills brand info',
  });

  final TextEditingController controller;
  final Color accent;
  final bool loading;
  final VoidCallback onImport;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.globe, size: 15, color: accent),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray700),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: c.gray400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => TextField(
                    controller: controller,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => onImport(),
                    style: TextStyle(fontSize: 13.5, color: c.gray900),
                    decoration: _decoration(context, accent, 'https://yourdomain.com/'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => FilledButton(
                  onPressed: loading || controller.text.trim().isEmpty ? null : onImport,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    minimumSize: const Size(76, 42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Import'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Preset swatches + the current colour + its hex — the web's "Brand Color"
/// field. Tapping the big swatch opens a fuller palette.
class BrandColorField extends StatelessWidget {
  const BrandColorField({super.key, required this.value, required this.onChanged, this.presets = defaultPresets});

  final String value;
  final ValueChanged<String> onChanged;
  final List<String> presets;

  static const defaultPresets = [
    '#7c3aed',
    '#2563eb',
    '#059669',
    '#db2777',
    '#ef4444',
    '#f59e0b',
    '#0ea5e9',
    '#111827',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final current = colorOf(value);
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final hex in presets)
                GestureDetector(
                  onTap: () => onChanged(hex),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: colorOf(hex),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: value.toLowerCase() == hex ? c.gray900 : Colors.transparent, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () async {
            final picked = await showColorPalette(context, value);
            if (picked != null) onChanged(picked);
          },
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: current,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: c.gray200),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value.toUpperCase(),
          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: c.gray600),
        ),
      ],
    );
  }
}

/// A grid of colours plus a hex field — the phone stand-in for the web's
/// native `<input type="color">`.
Future<String?> showColorPalette(BuildContext context, String current) {
  const hues = [0.0, 20, 38, 50, 90, 145, 175, 200, 220, 245, 270, 300, 330];
  const levels = [(0.95, 0.35), (0.85, 0.5), (0.8, 0.62), (0.7, 0.75)];
  final hexCtrl = TextEditingController(text: current);
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) {
      final c = sheet.colors;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pick a colour',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
            ),
            const SizedBox(height: 12),
            for (final (s, l) in levels)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    for (final h in hues)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(sheet, hexOf(HSLColor.fromAHSL(1, h.toDouble(), s, l).toColor())),
                          child: Container(
                            height: 26,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: HSLColor.fromAHSL(1, h.toDouble(), s, l).toColor(),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                for (final g in const [0.0, 0.2, 0.4, 0.6, 0.8, 0.95, 1.0])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(sheet, hexOf(HSLColor.fromAHSL(1, 0, 0, g).toColor())),
                      child: Container(
                        height: 26,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: HSLColor.fromAHSL(1, 0, 0, g).toColor(),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.gray200),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: hexCtrl,
                    autocorrect: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
                      LengthLimitingTextInputFormatter(7),
                    ],
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                    decoration: _decoration(sheet, AppColors.blue600, '#2563eb'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final v = hexCtrl.text.startsWith('#') ? hexCtrl.text : '#${hexCtrl.text}';
                    if (Brand.parseHex(v) == null) return Toast.error('Enter a hex colour like #2563eb');
                    Navigator.pop(sheet, v.toLowerCase());
                  },
                  style: FilledButton.styleFrom(minimumSize: const Size(72, 42)),
                  child: const Text('Use'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// Pick an image from the phone and upload it to the gallery → hosted URL.
/// Shows its own error toast; returns null on cancel or failure.
Future<String?> pickAndUploadImage(CustomStudioApi api, {int maxBytes = 10 * 1024 * 1024}) async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.length > maxBytes) {
    Toast.error('That image is too large. Please choose one under ${maxBytes ~/ (1024 * 1024)} MB.');
    return null;
  }
  try {
    final url = await api.uploadImage(bytes, file.name);
    if (url == null) Toast.error("Couldn't upload that image. Please try again.");
    return url;
  } catch (e) {
    Toast.error("Couldn't upload that image. Please try again.");
    return null;
  }
}

/// The web's "Logo" field: Upload / Replace + a thumbnail with a remove ×.
class LogoField extends StatefulWidget {
  const LogoField({super.key, required this.api, required this.value, required this.onChanged, required this.accent});

  final CustomStudioApi api;
  final String? value;
  final ValueChanged<String?> onChanged;
  final Color accent;

  @override
  State<LogoField> createState() => _LogoFieldState();
}

class _LogoFieldState extends State<LogoField> {
  bool _uploading = false;

  Future<void> _pick() async {
    setState(() => _uploading = true);
    final url = await pickAndUploadImage(widget.api, maxBytes: 5 * 1024 * 1024);
    if (!mounted) return;
    setState(() => _uploading = false);
    if (url != null) widget.onChanged(url);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final logo = widget.value;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _uploading ? null : _pick,
            style: OutlinedButton.styleFrom(
              foregroundColor: c.gray600,
              side: BorderSide(color: c.gray300),
              minimumSize: const Size(0, 42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: _uploading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(LucideIcons.fileUp, size: 16),
            label: Text(_uploading ? 'Uploading…' : (logo != null ? 'Replace' : 'Upload')),
          ),
        ),
        if (logo != null) ...[
          const SizedBox(width: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.gray200),
                ),
                clipBehavior: Clip.antiAlias,
                child: MediaImage(logo, fit: BoxFit.contain, cacheWidth: 120),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => widget.onChanged(null),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(color: AppColors.red500, shape: BoxShape.circle),
                    child: const Icon(LucideIcons.x, size: 11, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A row of uploaded image thumbnails with an "add" tile — for product /
/// reference images. Holds hosted URLs.
class ImageListField extends StatefulWidget {
  const ImageListField({
    super.key,
    required this.api,
    required this.images,
    required this.onChanged,
    required this.accent,
    this.max = 5,
  });

  final CustomStudioApi api;
  final List<String> images;
  final ValueChanged<List<String>> onChanged;
  final Color accent;
  final int max;

  @override
  State<ImageListField> createState() => _ImageListFieldState();
}

class _ImageListFieldState extends State<ImageListField> {
  bool _uploading = false;

  Future<void> _add() async {
    setState(() => _uploading = true);
    final url = await pickAndUploadImage(widget.api);
    if (!mounted) return;
    setState(() => _uploading = false);
    if (url != null) widget.onChanged([...widget.images, url]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final url in widget.images)
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(width: 64, height: 64, child: MediaImage(url, cacheWidth: 160)),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => widget.onChanged([...widget.images]..remove(url)),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(color: AppColors.red500, shape: BoxShape.circle),
                    child: const Icon(LucideIcons.x, size: 11, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        if (widget.images.length < widget.max)
          InkWell(
            onTap: _uploading ? null : _add,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: widget.accent.withValues(alpha: 0.35)),
              ),
              child: Center(
                child: _uploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(LucideIcons.imagePlus, size: 20, color: widget.accent),
              ),
            ),
          ),
        if (widget.images.isEmpty)
          SizedBox(
            height: 64,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Add up to ${widget.max} images', style: TextStyle(fontSize: 12, color: c.gray400)),
            ),
          ),
      ],
    );
  }
}

// ── Choices ─────────────────────────────────────────────────────────────────

/// Port of `forms/OptionChip.jsx`: a content-width, single-select chip with an
/// optional leading icon/emoji badge and a description line.
class OptionChip extends StatelessWidget {
  const OptionChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    required this.accent,
    this.desc,
    this.icon,
    this.emoji,
  });

  final String label;
  final String? desc;
  final IconData? icon;

  /// Shown instead of [icon] (the goal pills use emoji).
  final String? emoji;
  final bool active;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasBadge = icon != null || emoji != null;
    return Material(
      color: active ? accent.withValues(alpha: 0.07) : c.gray50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: active ? accent : c.gray100, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(hasBadge ? 7 : 12, 7, 12, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null)
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: active ? accent : c.surface,
                    borderRadius: BorderRadius.circular(7),
                    border: active ? null : Border.all(color: c.gray200),
                  ),
                  child: Icon(icon, size: 13, color: active ? Colors.white : c.gray400),
                )
              else if (emoji != null)
                Padding(
                  padding: const EdgeInsets.only(left: 3, right: 6),
                  child: Text(emoji!, style: const TextStyle(fontSize: 13)),
                ),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: active ? Color.lerp(accent, Colors.black, 0.25) : c.gray600,
                      ),
                    ),
                    if (desc != null)
                      Text(
                        desc!,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: active ? Color.lerp(accent, Colors.black, 0.25)!.withValues(alpha: 0.7) : c.gray400,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A wrap of [OptionChip]s — the usual `flex flex-wrap gap-2` row.
class ChipWrap extends StatelessWidget {
  const ChipWrap({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: children);
}

// ── Steps & navigation ──────────────────────────────────────────────────────

/// The numbered step bar at the top of each form: done steps get a check and
/// can be tapped to go back; connectors fill as you progress.
///
/// It also scrolls the page back to the top whenever the step changes: on a
/// phone you tap Continue at the bottom of a long step, and the next one
/// should start at its title, not halfway down. Living here, every form that
/// shows the bar gets it.
class StepIndicator extends StatefulWidget {
  const StepIndicator({super.key, required this.steps, required this.current, required this.accent, this.onTap});

  /// (label, icon) per step, 1-based [current].
  final List<(String, IconData)> steps;
  final int current;
  final Color accent;
  final ValueChanged<int>? onTap;

  @override
  State<StepIndicator> createState() => _StepIndicatorState();
}

class _StepIndicatorState extends State<StepIndicator> {
  @override
  void didUpdateWidget(StepIndicator old) {
    super.didUpdateWidget(old);
    if (old.current == widget.current) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final position = Scrollable.maybeOf(context)?.position;
      if (position != null && position.pixels > position.minScrollExtent) {
        position.animateTo(
          position.minScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      _StepBar(steps: widget.steps, current: widget.current, accent: widget.accent, onTap: widget.onTap);
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.steps, required this.current, required this.accent, this.onTap});

  final List<(String, IconData)> steps;
  final int current;
  final Color accent;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final showLabels = steps.length <= 3;
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          GestureDetector(
            onTap: current > i + 1 ? () => onTap?.call(i + 1) : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: current > i + 1 ? accent : c.surface,
                    border: Border.all(color: current >= i + 1 ? accent : c.gray200, width: 2),
                  ),
                  child: Icon(
                    current > i + 1 ? LucideIcons.check : steps[i].$2,
                    size: 14,
                    color: current > i + 1
                        ? Colors.white
                        : current == i + 1
                        ? accent
                        : c.gray300,
                  ),
                ),
                if (showLabels && current == i + 1) ...[
                  const SizedBox(width: 6),
                  Text(
                    steps[i].$1,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.gray700),
                  ),
                ],
              ],
            ),
          ),
          if (i < steps.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: current > i + 1 ? accent : c.gray200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// The red "X message" box above a form.
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: context.colors.redTint,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.red500.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(LucideIcons.x, size: 15, color: AppColors.red600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: const TextStyle(fontSize: 13, color: AppColors.red600)),
        ),
      ],
    ),
  );
}

/// ← Back · Continue → / Generate — the bottom of every form.
class FormNavBar extends StatelessWidget {
  const FormNavBar({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.accent,
    required this.onBack,
    required this.onContinue,
    required this.onGenerate,
    required this.generateLabel,
    this.generating = false,
    this.generateIcon = LucideIcons.wandSparkles,
  });

  final int step;
  final int totalSteps;
  final Color accent;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final VoidCallback onGenerate;
  final String generateLabel;
  final IconData generateIcon;
  final bool generating;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final last = step >= totalSteps;
    return Row(
      children: [
        if (step > 1)
          OutlinedButton(
            onPressed: onBack,
            style: OutlinedButton.styleFrom(
              foregroundColor: c.gray600,
              side: BorderSide(color: c.gray200),
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('← Back'),
          ),
        if (step > 1) const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: generating ? null : (last ? onGenerate : onContinue),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              disabledBackgroundColor: accent.withValues(alpha: 0.6),
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: generating
                  ? const [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                    ]
                  : last
                  ? [Icon(generateIcon, size: 16), const SizedBox(width: 8), Flexible(child: Text(generateLabel))]
                  : const [Text('Continue'), SizedBox(width: 6), Icon(LucideIcons.chevronRight, size: 16)],
            ),
          ),
        ),
      ],
    );
  }
}
