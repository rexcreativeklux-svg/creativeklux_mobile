import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../editor/magic_panel/magic_option_body.dart';
import '../editor/magic_panel/magic_tools.dart' show MagicOption, MagicPanelKind;
import 'magic_configs.dart';

/// The chooser inside an option chip's sheet — port of magicPanelUI.jsx
/// `OptionPanelBody`, every panel kind the composer's tools declare.
///
/// list / cards / colors / ratios are drawn by the editor's `MagicOptionBody`
/// (the same shared body, as on the web, so a style card looks the same in
/// the editor's Magic tab and here). flags / voices / pills / slider /
/// templates are the kinds only the /magic-studio tools use, built below.
///
/// [onSelect]'s `keepOpen` comes from controls that fire continuously (a
/// slider drag, a hex being typed) — the sheet must not close mid-gesture.
class MagicOptionPanelBody extends StatelessWidget {
  const MagicOptionPanelBody({super.key, required this.option, required this.value, required this.onSelect});

  final MagicOptionSpec option;
  final String? value;
  final void Function(String value, {bool keepOpen}) onSelect;

  @override
  Widget build(BuildContext context) {
    MagicOption shared(MagicPanelKind kind) => MagicOption(
      key: option.key,
      label: option.label,
      panel: kind,
      defaultValue: option.defaultValue,
      items: option.items,
    );
    return switch (option.panel) {
      MagicPanel.list => MagicOptionBody(option: shared(MagicPanelKind.list), value: value, onSelect: onSelect),
      MagicPanel.cards => MagicOptionBody(option: shared(MagicPanelKind.cards), value: value, onSelect: onSelect),
      MagicPanel.colors => MagicOptionBody(option: shared(MagicPanelKind.colors), value: value, onSelect: onSelect),
      MagicPanel.ratios => MagicOptionBody(option: shared(MagicPanelKind.ratios), value: value, onSelect: onSelect),
      MagicPanel.flags => _FlagsBody(option: option, value: value, onSelect: onSelect),
      MagicPanel.voices => _VoicesBody(option: option, value: value, onSelect: onSelect),
      MagicPanel.pills => _PillsBody(option: option, value: value, onSelect: onSelect),
      MagicPanel.slider => _SliderBody(option: option, value: value, onSelect: onSelect),
      MagicPanel.templates => _TemplatesBody(option: option, value: value, onSelect: onSelect),
    };
  }
}

BoxDecoration _box(BuildContext context, bool active, {double radius = 12}) => BoxDecoration(
  color: active ? context.colors.blueTint : context.colors.surface,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: active ? AppColors.blue500 : context.colors.gray200, width: 2),
);

/// Two-up grid, like the editor body's compact layout.
Widget _twoUp(List<Widget> children, {double gap = 8}) => LayoutBuilder(
  builder: (context, box) {
    final w = (box.maxWidth - gap) / 2;
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [for (final c in children) SizedBox(width: w, child: c)],
    );
  },
);

/// Flag + label grid (Language).
class _FlagsBody extends StatelessWidget {
  const _FlagsBody({required this.option, required this.value, required this.onSelect});
  final MagicOptionSpec option;
  final String? value;
  final void Function(String value, {bool keepOpen}) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: _twoUp([
        for (final it in option.items)
          GestureDetector(
            onTap: () => onSelect(it.value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: _box(context, it.value == value),
              child: Row(
                children: [
                  Text(it.flag ?? '', style: const TextStyle(fontSize: 17)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      it.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: it.value == value ? AppColors.blue600 : c.gray700,
                      ),
                    ),
                  ),
                  if (it.value == value) Icon(LucideIcons.check, size: 14, color: AppColors.blue600),
                ],
              ),
            ),
          ),
      ]),
    );
  }
}

/// Portrait rows grouped by accent + gender (Voice).
///
/// ⚠️ NO ▶ PREVIEW. The web auditions a hosted voice from a pre-generated clip
/// under /voice-samples/aura/ — none exist yet — or, failing that, by ASKING
/// THE BACKEND TO SPEAK IT, which bills a generation and files a history record
/// per tap (PREVIEW_BY_GENERATING). Neither belongs on a phone where browsing
/// the grid is a few idle thumb-flicks; the cards are pick-only until the clips
/// land.
///
/// The portrait sits on the gender glyph, so a dead Pexels link lands on the
/// same designed state as a voice with no photo.
class _VoicesBody extends StatelessWidget {
  const _VoicesBody({required this.option, required this.value, required this.onSelect});
  final MagicOptionSpec option;
  final String? value;
  final void Function(String value, {bool keepOpen}) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groups = <(String, List<MagicChoice>)>[];
    for (final it in option.items) {
      if (groups.isNotEmpty && groups.last.$1 == it.group) {
        groups.last.$2.add(it);
      } else {
        groups.add((it.group ?? '', [it]));
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (name, items) in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text(
                name.toUpperCase(),
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.gray400),
              ),
            ),
            _twoUp(gap: 6, [
              for (final it in items)
                GestureDetector(
                  onTap: () => onSelect(it.value),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
                    decoration: _box(context, it.value == value),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ColoredBox(
                                  color: it.gender == 'female'
                                      ? const Color(0xFFFCE7F3) // pink-100
                                      : const Color(0xFFE0F2FE), // sky-100
                                  child: Icon(
                                    it.icon,
                                    size: 14,
                                    color: it.gender == 'female' ? const Color(0xFFDB2777) : const Color(0xFF0284C7),
                                  ),
                                ),
                                if (it.img != null) MediaImage(it.img!, cacheWidth: 100),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            it.label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: it.value == value ? AppColors.blue600 : c.gray900,
                            ),
                          ),
                        ),
                        if (it.top) ...[
                          const SizedBox(width: 3),
                          const Icon(LucideIcons.star, size: 12, color: AppColors.amber500),
                        ],
                      ],
                    ),
                  ),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Compact chips (Export format).
class _PillsBody extends StatelessWidget {
  const _PillsBody({required this.option, required this.value, required this.onSelect});
  final MagicOptionSpec option;
  final String? value;
  final void Function(String value, {bool keepOpen}) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final it in option.items)
            GestureDetector(
              onTap: () => onSelect(it.value),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: _box(context, it.value == value),
                child: Text(
                  it.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: it.value == value ? AppColors.blue600 : c.gray700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A number off a continuous range (Duration, Speaking speed / pace).
///
/// ⚠️ IT COMMITS WITH `keepOpen` — onChanged fires on every step of a drag —
/// and writes the value back as a STRING, rounded to the step's own precision
/// (0.75 + 0.05 is 0.8000000000000002 in binary floating point otherwise).
class _SliderBody extends StatelessWidget {
  const _SliderBody({required this.option, required this.value, required this.onSelect});
  final MagicOptionSpec option;
  final String? value;
  final void Function(String value, {bool keepOpen}) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final min = option.min, max = option.max, step = option.step;
    final raw = double.tryParse(value ?? option.defaultValue) ?? min;
    final current = raw.clamp(min, max).toDouble();
    final decimals = '$step'.contains('.') && !'$step'.endsWith('.0') ? '$step'.split('.')[1].length : 0;
    double round(double n) => double.parse(n.toStringAsFixed(decimals));
    String show(double n) => decimals == 0 ? '${n.round()}' : '${round(n)}';
    final hint = option.hint?.call(current);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${show(current)}${option.unit}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
              ),
              const Spacer(),
              if (hint != null)
                Flexible(
                  child: Text(
                    hint,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.gray400),
                  ),
                ),
            ],
          ),
          Slider(
            value: current,
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            activeColor: AppColors.blue600,
            label: '${show(current)}${option.unit}',
            onChanged: (v) => onSelect(show(round(v)), keepOpen: true),
          ),
          Row(
            children: [
              Text('${show(min)}${option.unit}', style: TextStyle(fontSize: 11, color: c.gray400)),
              const Spacer(),
              Text('${show(max)}${option.unit}', style: TextStyle(fontSize: 11, color: c.gray400)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Template cards under their category headings (Video Effects).
///
/// ⚠️ NO POSTER OR CLIP — the web's showcase media isn't ours and isn't in
/// this app (see the note in magic_configs.dart). Each card is its icon ground,
/// which is the web's own designed state for a card with no picture.
class _TemplatesBody extends StatelessWidget {
  const _TemplatesBody({required this.option, required this.value, required this.onSelect});
  final MagicOptionSpec option;
  final String? value;
  final void Function(String value, {bool keepOpen}) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final loose = option.items.where((i) => i.category == null).toList();
    final groups = [
      for (final cat in option.categoryOrder) (cat, option.items.where((i) => i.category == cat).toList()),
    ].where((g) => g.$2.isNotEmpty);

    Widget card(MagicChoice it) {
      final active = it.value == value;
      return GestureDetector(
        onTap: () => onSelect(it.value),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: _box(context, active, radius: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: c.gray100,
                      child: Icon(it.icon, size: 24, color: active ? AppColors.blue500 : c.gray400),
                    ),
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
                    Text(
                      it.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? AppColors.blue600 : c.gray900,
                      ),
                    ),
                    if (it.desc != null)
                      Text(
                        it.desc!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, height: 1.3, color: c.gray500),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loose.isNotEmpty) ...[
            const SizedBox(height: 8),
            _twoUp([for (final it in loose) card(it)]),
          ],
          for (final (cat, items) in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
              child: Text(
                cat.toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: c.gray400),
              ),
            ),
            _twoUp([for (final it in items) card(it)]),
          ],
        ],
      ),
    );
  }
}
