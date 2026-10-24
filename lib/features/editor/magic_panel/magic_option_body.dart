import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/media.dart';
import 'magic_tools.dart';

/// One option row ("Visual style · Photorealistic ▾") that expands IN PLACE to
/// its chooser — the web's compact layout (MagicToolTab's option rows below
/// `lg`). The desktop fly-out (MagicOptionDropdown.jsx) isn't ported: in a 300px
/// side panel or a bottom sheet there's no canvas beside the row to float over.
class MagicOptionRow extends StatelessWidget {
  const MagicOptionRow({
    super.key,
    required this.option,
    required this.value,
    required this.open,
    required this.onToggle,
    required this.onSelect,
  });

  final MagicOption option;
  final String? value;
  final bool open;
  final VoidCallback onToggle;

  /// [keepOpen] comes from controls that fire continuously (the hex box) and
  /// must not collapse the row being typed into.
  final void Function(String value, {bool keepOpen}) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: c.gray100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray900),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        summarizeOption(option, value),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.blue600),
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(LucideIcons.chevronDown, size: 14, color: c.gray400),
                    ),
                  ],
                ),
              ),
            ),
            if (open)
              Container(
                constraints: const BoxConstraints(maxHeight: 256),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(top: BorderSide(color: c.gray200)),
                ),
                child: SingleChildScrollView(
                  child: MagicOptionBody(option: option, value: value, onSelect: onSelect),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The chooser itself — port of magicPanelUI.jsx `OptionPanelBody` for the
/// four panel kinds the editor's tools use (list, cards, colors, ratios), laid
/// out two-up as the web's compact rows force with `[&>div]:grid-cols-2`.
class MagicOptionBody extends StatelessWidget {
  const MagicOptionBody({super.key, required this.option, required this.value, required this.onSelect});

  final MagicOption option;
  final String? value;
  final void Function(String value, {bool keepOpen}) onSelect;

  @override
  Widget build(BuildContext context) {
    return switch (option.panel) {
      MagicPanelKind.colors => _ColorsBody(option: option, value: value, onSelect: onSelect),
      MagicPanelKind.ratios => _grid(context, (it, active) => _RatioCard(item: it, active: active)),
      MagicPanelKind.cards => _grid(context, (it, active) => _StyleCard(item: it, active: active)),
      MagicPanelKind.list => _grid(context, (it, active) => _ListCard(item: it, active: active)),
    };
  }

  Widget _grid(BuildContext context, Widget Function(MagicOptionItem, bool) card) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = (box.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final it in option.items)
                SizedBox(
                  width: w,
                  child: GestureDetector(onTap: () => onSelect(it.value), child: card(it, it.value == value)),
                ),
            ],
          );
        },
      ),
    );
  }
}

BoxDecoration _cardBox(BuildContext context, bool active, {double radius = 12}) => BoxDecoration(
  color: active ? context.colors.blueTint : context.colors.surface,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: active ? AppColors.blue500 : context.colors.gray200, width: 2),
);

/// Icon + label + description (Purpose, Content type).
class _ListCard extends StatelessWidget {
  const _ListCard({required this.item, required this.active});
  final MagicOptionItem item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: _cardBox(context, active),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: active ? AppColors.blue500.withValues(alpha: 0.15) : c.gray100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon ?? LucideIcons.sparkles, size: 15, color: active ? AppColors.blue600 : c.gray500),
              ),
              const Spacer(),
              if (active) Icon(LucideIcons.check, size: 15, color: AppColors.blue600),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? AppColors.blue600 : c.gray900),
          ),
          if (item.desc != null) Text(item.desc!, style: TextStyle(fontSize: 10.5, height: 1.3, color: c.gray500)),
        ],
      ),
    );
  }
}

/// Thumbnail + label + description (Visual style). The photo is a third-party
/// Pexels URL that may stop resolving; MediaImage falls back to a plain gray
/// panel and the label row still carries the style's icon, so a dead link is
/// untidy rather than broken (the web uncovers an icon panel instead).
class _StyleCard extends StatelessWidget {
  const _StyleCard({required this.item, required this.active});
  final MagicOptionItem item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardBox(context, active, radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 72,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: c.gray100,
                  child: Icon(item.icon, size: 26, color: active ? AppColors.blue500 : c.gray400),
                ),
                if (item.img != null) MediaImage(item.img!, cacheWidth: 300),
                if (active)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: AppColors.blue600,
                      child: Icon(LucideIcons.check, size: 12, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (item.icon != null) ...[
                      Icon(item.icon, size: 13, color: active ? AppColors.blue600 : c.gray400),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        item.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: active ? AppColors.blue600 : c.gray900,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.desc != null)
                  Text(
                    item.desc!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, height: 1.3, color: c.gray500),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A scaled frame per aspect ratio.
class _RatioCard extends StatelessWidget {
  const _RatioCard({required this.item, required this.active});
  final MagicOptionItem item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const maxDim = 48.0;
    final bw = item.w >= item.h ? maxDim : maxDim * item.w / item.h;
    final bh = item.h >= item.w ? maxDim : maxDim * item.h / item.w;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _cardBox(context, active, radius: 14),
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: Center(
              child: Container(
                width: bw,
                height: bh,
                decoration: BoxDecoration(
                  color: active ? AppColors.blue500.withValues(alpha: 0.45) : c.gray200,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: active ? AppColors.blue600 : c.gray700,
            ),
          ),
          if (item.ratio != null) Text(item.ratio!, style: TextStyle(fontSize: 10, color: c.gray400)),
        ],
      ),
    );
  }
}

Color? _hex(String v) {
  final m = RegExp(r'^#([0-9a-f]{6})$', caseSensitive: false).firstMatch(v);
  return m == null ? null : Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}

/// Swatches + a free hex box. The first swatch is "no colour in particular" and
/// the default, drawn slashed so it can't be mistaken for a shade. The hex box
/// is the point (a brand's own colour); the web's native colour picker beside it
/// has no stand-in here.
class _ColorsBody extends StatefulWidget {
  const _ColorsBody({required this.option, required this.value, required this.onSelect});
  final MagicOption option;
  final String? value;
  final void Function(String value, {bool keepOpen}) onSelect;

  @override
  State<_ColorsBody> createState() => _ColorsBodyState();
}

class _ColorsBodyState extends State<_ColorsBody> {
  late final _hexCtrl = TextEditingController(text: _custom ? widget.value : '');

  bool get _custom {
    final v = widget.value;
    return v != null && v != autoColor && !widget.option.items.any((i) => i.value == v);
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final it in widget.option.items)
                Semantics(
                  label: it.label,
                  selected: it.value == widget.value,
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      _hexCtrl.clear();
                      widget.onSelect(it.value);
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _hex(it.value) ?? c.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: it.value == widget.value ? c.gray900 : c.gray200, width: 2),
                      ),
                      child: it.value == autoColor
                          // A diagonal through an empty swatch — the standard "no fill".
                          ? Center(
                              child: Transform.rotate(
                                angle: -0.785,
                                child: Container(width: 36, height: 1, color: c.gray300),
                              ),
                            )
                          : it.value == widget.value
                          ? const Icon(
                              LucideIcons.check,
                              size: 16,
                              color: Colors.white,
                              shadows: [Shadow(blurRadius: 2, color: Colors.black54)],
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Custom',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: c.gray500),
              ),
              const SizedBox(width: 8),
              if (_custom && _hex(widget.value!) != null) ...[
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _hex(widget.value!),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: c.gray200),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _hexCtrl,
                  maxLength: 7,
                  style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: c.gray700),
                  decoration: const InputDecoration(
                    hintText: '#2563EB',
                    counterText: '',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (raw) {
                    final next = raw.trim();
                    // Only commit a complete hex — half-typed "#2b" isn't a colour.
                    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(next)) {
                      widget.onSelect(next, keepOpen: true);
                    } else if (next.isEmpty || next == '#') {
                      widget.onSelect(autoColor, keepOpen: true);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
