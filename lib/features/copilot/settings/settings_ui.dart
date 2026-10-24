import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../data/copilot_data.dart';
import '../widgets/copilot_widgets.dart';

// The pieces every settings panel is built from (settings/settingsUi.jsx) —
// seven panels behind one nav have to read as seven views of one screen.

/// A titled block of settings. [action] sits under the text on a phone — the
/// web's below-`sm` layout ("a heading, a sentence and a button do not share 320px").
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    this.description,
    this.action,
    this.children = const [],
    this.last = false,
  });

  final String title;
  final String? description;
  final Widget? action;
  final List<Widget> children;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.only(bottom: last ? 0 : 20),
      margin: EdgeInsets.only(bottom: last ? 0 : 20),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.gray100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, style: TextStyle(fontSize: 13, height: 1.5, color: c.gray500)),
          ],
          if (action != null) ...[const SizedBox(height: 12), action!],
          if (children.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final (i, w) in children.indexed) ...[if (i > 0) const SizedBox(height: 14), w],
          ],
        ],
      ),
    );
  }
}

/// A setting with its control on the right.
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.title, this.description, required this.child});

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray900),
              ),
              if (description != null) ...[
                const SizedBox(height: 2),
                Text(description!, style: TextStyle(fontSize: 12, height: 1.5, color: c.gray500)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 14),
        child,
      ],
    );
  }
}

/// An on/off switch — ink, not the app blue: these sit next to permission copy.
class SettingsToggle extends StatelessWidget {
  const SettingsToggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: c.surface,
      activeTrackColor: c.gray900,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: c.gray200,
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    );
  }
}

class ChoiceOption {
  const ChoiceOption(this.value, this.label, this.description, this.icon);
  final String value;
  final String label;
  final String description;
  final IconData icon;
}

/// Radio cards (Sharing's visibility).
class ChoiceList extends StatelessWidget {
  const ChoiceList({super.key, required this.value, required this.onChanged, required this.options});
  final String value;
  final ValueChanged<String> onChanged;
  final List<ChoiceOption> options;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => onChanged(o.value),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: o.value == value ? c.blueTint : c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: o.value == value ? AppColors.blue500 : c.gray200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(o.icon, size: 16, color: o.value == value ? AppColors.blue600 : c.gray500),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.label,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray900),
                          ),
                          const SizedBox(height: 2),
                          Text(o.description, style: TextStyle(fontSize: 12, height: 1.5, color: c.gray500)),
                        ],
                      ),
                    ),
                    if (o.value == value) Icon(LucideIcons.check, size: 16, color: AppColors.blue600),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A read-only value with a Copy button (the copilot link, the link message).
class CopyField extends StatelessWidget {
  const CopyField({super.key, required this.label, required this.value, this.hint, this.what});
  final String label;
  final String value;
  final String? hint;

  /// What the toast calls it ("Copilot link copied").
  final String? what;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: MonoBox(value)),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Copy',
              style: IconButton.styleFrom(
                side: BorderSide(color: c.gray200),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                Toast.success('${what ?? label} copied');
              },
              icon: Icon(LucideIcons.copy, size: 16, color: c.gray500),
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint!, style: TextStyle(fontSize: 11, height: 1.4, color: c.gray400)),
        ],
      ],
    );
  }
}

/// A one-line mono value on the muted field background.
class MonoBox extends StatelessWidget {
  const MonoBox(this.text, {super.key, this.muted = false});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: c.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray200),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: muted ? c.gray400 : c.gray700),
      ),
    );
  }
}

/// A dashed-bordered empty note ("Only you, for now.").
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray200),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, height: 1.5, color: c.gray400),
      ),
    );
  }
}

/// The trigger a picker opens from (SettingsSelect.jsx's button).
class SelectTrigger extends StatelessWidget {
  const SelectTrigger({super.key, required this.label, required this.onTap, this.expand = false});
  final String label;
  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.gray200),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Flexible(
              fit: expand ? FlexFit.tight : FlexFit.loose,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray900),
              ),
            ),
            const SizedBox(width: 6),
            Icon(LucideIcons.chevronDown, size: 15, color: c.gray500),
          ],
        ),
      ),
    );
  }
}

/// The settings pickers (SettingsSelect.jsx) as a sheet: a description under
/// each option, group headings, optional search, and an optional footer (the
/// model menu's "View plans").
///
/// [onChanged] receives the CLICKED id even when [multiple] — the caller owns
/// what clicking means to its list (Cross-app access treats All / None
/// specially). [selected] is re-read after each pick so a multiple sheet stays
/// open and live.
Future<void> showPickSheet(
  BuildContext context, {
  required String title,
  required List<PickOption> options,
  required List<String> Function() selected,
  required ValueChanged<String> onChanged,
  List<PickGroup> groups = const [],
  bool multiple = false,
  bool searchable = false,
  Widget? footer,
}) {
  return showCopilotSheet<void>(
    context,
    title: title,
    fullHeight: options.length > 8,
    builder: (ctx) => _PickBody(
      options: options,
      groups: groups,
      selected: selected,
      onChanged: onChanged,
      multiple: multiple,
      searchable: searchable,
      footer: footer,
    ),
  );
}

class _PickBody extends StatefulWidget {
  const _PickBody({
    required this.options,
    required this.groups,
    required this.selected,
    required this.onChanged,
    required this.multiple,
    required this.searchable,
    this.footer,
  });

  final List<PickOption> options;
  final List<PickGroup> groups;
  final List<String> Function() selected;
  final ValueChanged<String> onChanged;
  final bool multiple;
  final bool searchable;
  final Widget? footer;

  @override
  State<_PickBody> createState() => _PickBodyState();
}

class _PickBodyState extends State<_PickBody> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final term = _query.text.trim().toLowerCase();
    final matches = [
      for (final o in widget.options)
        if (term.isEmpty || o.label.toLowerCase().contains(term) || (o.description ?? '').toLowerCase().contains(term))
          o,
    ];
    final groupIds = {for (final g in widget.groups) g.id};
    final loose = [
      for (final o in matches)
        if (!groupIds.contains(o.group)) o,
    ];
    final selected = widget.selected();

    Widget tile(PickOption o) {
      final on = selected.contains(o.id);
      return ListTile(
        dense: true,
        minLeadingWidth: 18,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: o.svg != null
            ? SvgPicture.string(
                o.svg!,
                width: 16,
                height: 16,
                colorFilter: ColorFilter.mode(c.gray700, BlendMode.srcIn),
              )
            : (o.icon != null ? Icon(o.icon, size: 16, color: c.gray500) : null),
        title: Text(
          o.label,
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.gray900),
        ),
        subtitle: o.description == null ? null : Text(o.description!, style: TextStyle(fontSize: 12, color: c.gray500)),
        trailing: on ? Icon(LucideIcons.check, size: 16, color: AppColors.blue600) : null,
        onTap: () {
          widget.onChanged(o.id);
          widget.multiple ? setState(() {}) : Navigator.pop(context);
        },
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: CopilotSearchField(controller: _query, hint: 'Search', onChanged: (_) => setState(() {})),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: [
                for (final o in loose) tile(o),
                for (final g in widget.groups)
                  if (matches.any((o) => o.group == g.id)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Row(
                        children: [
                          if (g.svg != null) ...[
                            SvgPicture.string(
                              g.svg!,
                              width: 12,
                              height: 12,
                              colorFilter: ColorFilter.mode(c.gray400, BlendMode.srcIn),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            g.label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: c.gray400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final o in matches)
                      if (o.group == g.id) tile(o),
                  ],
                if (matches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No matches',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: c.gray400),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.footer != null) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: widget.footer),
        ],
      ),
    );
  }
}
