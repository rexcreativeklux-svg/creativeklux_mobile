import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../copilot_api.dart';
import '../copilot_store.dart';
import '../data/copilot_data.dart';

// The pieces every Copilot screen shares — ports of copilot/_components
// (CopilotAvatar, PlatformChip, SurfaceChip, CopilotComposer, DropdownMenu,
// CreateCopilotModal) plus the `notifyPending` / `reportFailure` helpers in
// _data/copilots.js.

/// Say out loud that a control is waiting on the backend — a control that
/// silently does nothing reads as broken.
void notifyPending(String label) => Toast.info('$label lands with the Copilot backend.');

/// Report a failed write in the SERVER'S OWN WORDS (copilots.js `reportFailure`).
///
/// ⚠️ The server's sentence is the headline and our context drops to the
/// description — the reverse of the usual toast, and deliberate while the
/// backend is being brought up. Long-lived, with a Copy action, because the
/// next thing that happens to this text is being pasted to whoever can fix it.
void reportFailure(Object error, String what) {
  final f = CopilotFailure.of(error);
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 12),
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        content: Builder(
          builder: (context) {
            final c = context.colors;
            return Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.gray200),
                boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 6))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.circleAlert, size: 18, color: AppColors.red600),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          f.detail,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          f.status != null ? '$what · HTTP ${f.status}' : what,
                          style: TextStyle(fontSize: 12.5, color: c.gray500),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: '$what — ${f.text}'));
                      messenger.hideCurrentSnackBar();
                      Toast.success('Error copied');
                    },
                    child: Text('Copy', style: TextStyle(fontSize: 12.5, color: c.gray900)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
}

/// The ink button the web draws as `bg-gray-900 text-surface` — inverts in
/// dark mode with the gray ramp, like the web.
class InkButton extends StatelessWidget {
  const InkButton({super.key, required this.label, this.icon, this.onTap, this.busy = false, this.expand = false});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null && !busy;
    return Material(
      color: enabled || busy ? c.gray900 : c.gray100,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.surface))
              else if (icon != null)
                Icon(icon, size: 16, color: enabled ? c.surface : c.gray400),
              if (busy || icon != null) const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: enabled || busy ? c.surface : c.gray400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bordered secondary button (settingsUi.jsx `GhostButton`); [danger] goes red.
class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, this.icon, this.onTap, this.danger = false, this.busy = false});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = danger ? AppColors.red600 : c.gray900;
    return Material(
      color: danger ? c.redTint : c.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: danger ? AppColors.red600.withValues(alpha: 0.3) : c.gray300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
              else if (icon != null)
                Icon(icon, size: 15, color: danger ? fg : c.gray500),
              if (busy || icon != null) const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tinted glyph tile that stands in for a copilot (CopilotAvatar.jsx).
/// White glyph on a saturated tint — readable in both themes.
class CopilotAvatar extends StatelessWidget {
  const CopilotAvatar({super.key, required this.copilot, this.size = 36});

  final Copilot copilot;

  /// 20 (sm) / 36 (md) / 48 (lg) / 56 (Identity panel).
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: copilot.tint,
        borderRadius: BorderRadius.circular(size <= 20 ? 6 : (size <= 36 ? 9 : 12)),
      ),
      child: Icon(copilot.icon, size: size * 0.5, color: Colors.white),
    );
  }
}

/// A platform's white-fill mark on its gradient (PlatformChip.jsx / the
/// ConnectorCard tile). An unknown id renders nothing rather than throwing.
class PlatformChip extends StatelessWidget {
  const PlatformChip(this.id, {super.key, this.size = 22});

  final String id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = platformsById[id];
    if (p == null) return const SizedBox.shrink();
    return Tooltip(
      message: p.name,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.26),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: p.colors.length > 1 ? p.colors : [p.colors.first, p.colors.first],
          ),
        ),
        child: SvgPicture.string(p.svg),
      ),
    );
  }
}

/// The badge for the part of the app a workflow runs in (SurfaceChip.jsx) —
/// the same tile as [PlatformChip], so a row mixing both reads as one set.
class SurfaceChip extends StatelessWidget {
  const SurfaceChip(this.category, {super.key, this.size = 22});

  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = categorySurfaces[category];
    if (s == null) return const SizedBox.shrink();
    return Tooltip(
      message: s.name,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(size * 0.26)),
        child: Icon(s.icon, size: size * 0.58, color: Colors.white),
      ),
    );
  }
}

/// The box you type a task into (CopilotComposer.jsx) — the SAME control on
/// the /copilot home and in a copilot's conversation, so they cannot drift.
///
/// The phone keyboard's return key opens a line; the send button sends (a
/// hardware Enter submits, as on the web).
class CopilotComposer extends StatelessWidget {
  const CopilotComposer({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.placeholder = 'Give your Copilot a task to do...',
    this.minLines = 2,
    this.busy = false,
    this.sendLabel = 'Send task',
    this.focusNode,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final String placeholder;
  final int minLines;
  final bool busy;
  final String sendLabel;
  final FocusNode? focusNode;

  /// Only ever called with a non-empty value — the guard lives here.
  void _submit() {
    if (busy || controller.text.trim().isEmpty) return;
    onSubmit();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 10, 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.gray200),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Column(
        children: [
          CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.enter): _submit},
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: minLines,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 14, color: c.gray900, height: 1.4),
              decoration: InputDecoration(
                hintText: placeholder,
                hintStyle: TextStyle(fontSize: 14, color: c.gray400),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          Row(
            children: [
              _IconTap(icon: LucideIcons.plus, label: 'Add attachment', onTap: () => notifyPending('Attachments')),
              const Spacer(),
              _IconTap(icon: LucideIcons.mic, label: 'Dictate task', onTap: () => notifyPending('Dictation')),
              const SizedBox(width: 6),
              // Dimmed rather than disabled while empty: it keeps its place and
              // pressing it simply does nothing.
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final ready = controller.text.trim().isNotEmpty && !busy;
                  return Semantics(
                    button: true,
                    label: sendLabel,
                    child: GestureDetector(
                      onTap: _submit,
                      child: Opacity(
                        opacity: ready || busy ? 1 : 0.5,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(color: c.blueTint, borderRadius: BorderRadius.circular(9)),
                          child: busy
                              ? Padding(
                                  padding: const EdgeInsets.all(9),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue600),
                                )
                              : Icon(LucideIcons.arrowUp, size: 17, color: AppColors.blue600),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IconButton(
      tooltip: label,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 17, color: c.gray500),
    );
  }
}

/// Underline tabs — the Plugins / Connectors / Skills / Personalization tab
/// strips. A level of navigation, not a filter, so not a segmented pill.
class UnderlineTabs extends StatelessWidget {
  const UnderlineTabs({super.key, required this.tabs, required this.value, required this.onChanged, this.counts});

  final List<String> tabs;
  final String value;
  final ValueChanged<String> onChanged;
  final Map<String, int>? counts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.gray200)),
      ),
      child: Row(
        children: [
          for (final t in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 22),
              child: InkWell(
                onTap: () => onChanged(t),
                child: Container(
                  padding: const EdgeInsets.only(bottom: 9, top: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: t == value ? AppColors.blue600 : Colors.transparent, width: 2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        t,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: t == value ? FontWeight.w600 : FontWeight.w500,
                          color: t == value ? c.gray900 : c.gray500,
                        ),
                      ),
                      if ((counts?[t] ?? 0) > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(99)),
                          child: Text(
                            '${counts![t]}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.gray500),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A search box (the catalog / connectors / skills toolbars).
class CopilotSearchField extends StatelessWidget {
  const CopilotSearchField({super.key, required this.controller, required this.hint, this.onChanged});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.gray300),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 16, color: c.gray400),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(fontSize: 14, color: c.gray900),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 14, color: c.gray400),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => controller.text.isEmpty
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: () {
                      controller.clear();
                      onChanged?.call('');
                    },
                    child: Icon(LucideIcons.x, size: 15, color: c.gray400),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A bordered trigger that opens [showChoiceSheet] (DropdownMenu.jsx's look).
class DropdownTrigger extends StatelessWidget {
  const DropdownTrigger({super.key, required this.label, this.icon, required this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.gray300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 15, color: c.gray400), const SizedBox(width: 6)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray900),
                ),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronDown, size: 15, color: c.gray500),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of a [showChoiceSheet]: a filter value (✓ on the current one) or an
/// action (with an icon) — DropdownMenu.jsx's two kinds of item.
class ChoiceItem {
  const ChoiceItem(this.label, {this.icon, this.selected = false, this.danger = false, this.onTap});
  final String label;
  final IconData? icon;
  final bool selected;
  final bool danger;
  final VoidCallback? onTap;
}

/// The phone's stand-in for the web's dropdowns and ⋯ menus: a short sheet.
/// A `null` entry draws a separator. The item's action runs after the sheet closes.
Future<void> showChoiceSheet(BuildContext context, {String? heading, required List<ChoiceItem?> items}) async {
  final picked = await showModalBottomSheet<ChoiceItem>(
    context: context,
    useRootNavigator: true,
    backgroundColor: context.colors.surface.withValues(alpha: 1),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final c = ctx.colors;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              if (heading != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: Text(
                    heading,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.gray500),
                  ),
                ),
              for (final it in items)
                if (it == null)
                  Divider(height: 9, color: c.gray200)
                else
                  ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    leading: it.icon == null
                        ? null
                        : Icon(it.icon, size: 17, color: it.danger ? AppColors.red600 : c.gray500),
                    minLeadingWidth: 20,
                    title: Text(
                      it.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: it.selected ? FontWeight.w600 : FontWeight.w500,
                        color: it.danger ? AppColors.red600 : c.gray900,
                      ),
                    ),
                    trailing: it.selected ? Icon(LucideIcons.check, size: 16, color: AppColors.blue600) : null,
                    onTap: () => Navigator.pop(ctx, it),
                  ),
            ],
          ),
        ),
      );
    },
  );
  picked?.onTap?.call();
}

/// Just spacing now: the app theme draws a drag handle on every bottom sheet
/// (`showDragHandle` in AppTheme), and this one stacked a second under it.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(height: 4);
}

/// A titled bottom sheet — the phone's ResponsiveModal. [fullHeight] is the
/// web's `fullHeightSheet` (the browse dialogs); short forms size to content.
Future<T?> showCopilotSheet<T>(
  BuildContext context, {
  String? title,
  bool fullHeight = false,
  bool dismissible = true,
  required Widget Function(BuildContext ctx) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: context.colors.surface.withValues(alpha: 1),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final c = ctx.colors;
      final media = MediaQuery.of(ctx);
      final body = Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Column(
          mainAxisSize: fullHeight ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const SheetHandle(),
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.gray900),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: dismissible ? () => Navigator.pop(ctx) : null,
                      icon: Icon(LucideIcons.x, size: 19, color: c.gray400),
                    ),
                  ],
                ),
              ),
            if (fullHeight) Expanded(child: builder(ctx)) else Flexible(child: builder(ctx)),
          ],
        ),
      );
      return fullHeight
          ? SizedBox(height: media.size.height * 0.92, child: body)
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
              child: body,
            );
    },
  );
}

/// Centred loading / error / empty block (the catalog's four states).
class StateBlock extends StatelessWidget {
  const StateBlock.loading(this.title, {super.key}) : kind = 0, detail = null, icon = null, action = null;
  const StateBlock.error(this.title, this.detail, {super.key, this.action}) : kind = 1, icon = null;
  const StateBlock.empty(this.title, this.detail, {super.key, this.icon, this.action}) : kind = 2;

  final int kind;
  final String title;
  final String? detail;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
      decoration: BoxDecoration(
        color: kind == 1 ? c.redTint : c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kind == 1 ? AppColors.red600.withValues(alpha: 0.25) : c.gray200),
      ),
      child: Column(
        children: [
          if (kind == 0)
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.gray400))
          else
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kind == 1 ? AppColors.red600.withValues(alpha: 0.12) : c.gray100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                kind == 1 ? LucideIcons.triangleAlert : (icon ?? LucideIcons.search),
                size: 17,
                color: kind == 1 ? AppColors.red600 : c.gray500,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: kind == 0 ? 12 : 14,
              fontWeight: kind == 0 ? FontWeight.w400 : FontWeight.w700,
              color: kind == 0 ? c.gray500 : c.gray900,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            // The server's exact words, in mono — the thing worth screenshotting.
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: kind == 1
                  ? const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5, color: Tw.red700)
                  : TextStyle(fontSize: 12, color: c.gray500),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// "Create copilot" — asks for a name, makes the copilot, hands it back
/// (CreateCopilotModal.jsx). Shared by the catalog's button and the home
/// screen's first-task composer.
///
/// ⚠️ NOT DISMISSIBLE WHILE CREATING: closing mid-request would leave a copilot
/// nobody is taken to, and a retry would make a duplicate.
Future<Copilot?> showCreateCopilotSheet(BuildContext context) {
  final store = CopilotStore.of(context);
  return showCopilotSheet<Copilot>(
    context,
    title: 'Create copilot',
    builder: (ctx) => _CreateCopilotBody(store: store),
  );
}

class _CreateCopilotBody extends StatefulWidget {
  const _CreateCopilotBody({required this.store});
  final CopilotStore store;

  @override
  State<_CreateCopilotBody> createState() => _CreateCopilotBodyState();
}

class _CreateCopilotBodyState extends State<_CreateCopilotBody> {
  final _name = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty || _creating) return;
    setState(() => _creating = true);
    try {
      final copilot = await widget.store.add({'name': name});
      if (mounted) Navigator.pop(context, copilot);
    } catch (e) {
      reportFailure(e, "Couldn't create a copilot");
      if (mounted) setState(() => _creating = false); // give the form back
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: !_creating,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Give it a name you'll recognise. You can rename it at anytime.",
                style: TextStyle(fontSize: 13.5, color: c.gray500, height: 1.4),
              ),
              const SizedBox(height: 16),
              Text(
                'Name',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _name,
                autofocus: true,
                enabled: !_creating,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                style: TextStyle(fontSize: 14, color: c.gray900),
                decoration: copilotFieldDecoration(context, 'For example, Brand assistant'),
              ),
              const SizedBox(height: 18),
              ListenableBuilder(
                listenable: _name,
                builder: (context, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _creating ? null : () => Navigator.pop(context),
                      child: Text('Cancel', style: TextStyle(color: c.gray500)),
                    ),
                    const SizedBox(width: 8),
                    InkButton(
                      label: _creating ? 'Creating…' : 'Create',
                      busy: _creating,
                      onTap: _name.text.trim().isEmpty ? null : _submit,
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

/// The house text-field look in the copilot sheets.
InputDecoration copilotFieldDecoration(BuildContext context, String hint) {
  final c = context.colors;
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: 13.5, color: c.gray400),
    isDense: true,
    filled: true,
    fillColor: c.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    enabledBorder: border(c.gray200),
    disabledBorder: border(c.gray200),
    focusedBorder: border(AppColors.primary),
  );
}
