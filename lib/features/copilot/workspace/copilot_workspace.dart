import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../copilot_store.dart';
import '../data/copilot_data.dart';
import '../settings/copilot_settings_sheet.dart';
import '../widgets/copilot_widgets.dart';
import 'footer_sheets.dart';

/// Which workspace screen is showing — lights its row in the menu.
enum WorkspaceSection { conversation, workflows, plugins }

/// /copilot/:id/* — a single copilot's workspace (port of [id]/layout.jsx +
/// CopilotWorkspaceLayout.jsx).
///
/// ⚠️ THREE STATES, NOT TWO: "no copilot with this id" has to wait for the
/// catalog request — rendering "not found" while it is in flight accuses the
/// user of a broken link on every open — and a failed request is its own case.
///
/// The web's secondary sidebar (identity, Conversation / Workflows / Plugins /
/// Customize, Channels, footer) is the phone's "Copilot menu" sheet behind the
/// header button — the same thing the web's below-`lg` drawer holds.
class CopilotWorkspace extends StatelessWidget {
  const CopilotWorkspace({super.key, required this.id, required this.section, required this.builder});

  final String id;
  final WorkspaceSection section;
  final Widget Function(BuildContext context, Copilot copilot) builder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final store = CopilotStore.of(context);
    return Scaffold(
      backgroundColor: c.page,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final copilot = store.byId(id);
            return Column(
              children: [
                _Header(copilot: copilot, section: section),
                Expanded(
                  child: copilot != null
                      ? builder(context, copilot)
                      : store.loading
                      ? _Centred(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: c.gray400),
                            ),
                            Text('Loading this copilot…', style: TextStyle(fontSize: 12, color: c.gray500)),
                          ],
                        )
                      : store.error != null
                      // The server's own words — right now that sentence is
                      // what gets the backend fixed.
                      ? _Centred(
                          children: [
                            _Tile(icon: LucideIcons.triangleAlert, color: AppColors.red600, bg: c.redTint),
                            Text(
                              "Couldn't load your copilots",
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.gray900),
                            ),
                            Text(
                              store.error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Tw.red700),
                            ),
                            InkButton(label: 'Back to all copilots', onTap: () => context.go('/copilot/all')),
                          ],
                        )
                      // Loaded, and genuinely not there — a stale link or a deleted copilot.
                      : _Centred(
                          children: [
                            _Tile(icon: LucideIcons.bot, color: c.gray500, bg: c.gray100),
                            Text(
                              'Copilot not found',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.gray900),
                            ),
                            Text(
                              "This copilot doesn't exist, or it has been deleted.",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: c.gray500),
                            ),
                            InkButton(label: 'Back to all copilots', onTap: () => context.go('/copilot/all')),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Centred extends StatelessWidget {
  const _Centred({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, w) in children.indexed) ...[if (i > 0) const SizedBox(height: 12), w],
        ],
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.color, required this.bg});
  final IconData icon;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
    child: Icon(icon, size: 22, color: color),
  );
}

/// The web's below-`lg` bar: menu button, avatar, name — plus Back.
class _Header extends StatelessWidget {
  const _Header({required this.copilot, required this.section});
  final Copilot? copilot;
  final WorkspaceSection section;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cp = copilot;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.gray200)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => context.canPop() ? context.pop() : context.go('/copilot/all'),
            icon: Icon(LucideIcons.arrowLeft, size: 18, color: c.gray700),
          ),
          if (cp != null) ...[
            CopilotAvatar(copilot: cp, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                cp.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
              ),
            ),
            IconButton(
              tooltip: 'Open copilot menu',
              onPressed: () => showWorkspaceMenu(context, cp, section),
              icon: Icon(LucideIcons.panelLeft, size: 19, color: c.gray500),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}

/// The workspace panel as a sheet: identity, the copilot's pages, Customize,
/// Channels and the footer. ⚠️ No conversation list — opening a copilot loads
/// its whole history, so there is one ongoing thread per copilot.
Future<void> showWorkspaceMenu(BuildContext context, Copilot copilot, WorkspaceSection section) async {
  final router = GoRouter.of(context);
  final base = '/copilot/${copilot.id}';

  // Each row says what to do once the sheet has closed — a sheet opened from a
  // sheet would otherwise sit behind the menu that launched it.
  final action = await showModalBottomSheet<VoidCallback>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: context.colors.surface.withValues(alpha: 1),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final c = ctx.colors;
      Widget row(IconData icon, String label, VoidCallback then, {bool active = false, Widget? leading}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: active ? c.blueTint : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.pop(ctx, then),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  leading ?? Icon(icon, size: 18, color: active ? AppColors.blue600 : c.gray500),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: active ? AppColors.blue600 : c.gray700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Switching between the copilot's own pages swaps the screen, like the
      // web rail; the current one just closes the menu.
      VoidCallback go(WorkspaceSection target, String path) =>
          () => target == section ? null : router.pushReplacement(path);

      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandle(),
                // Identity — which copilot this is, and a way to another one.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(ctx, () => router.go('/copilot/all')),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          CopilotAvatar(copilot: copilot),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              copilot.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
                            ),
                          ),
                          Text('Switch', style: TextStyle(fontSize: 12, color: c.gray500)),
                          Icon(LucideIcons.chevronDown, size: 16, color: c.gray500),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // ⚠️ Conversation goes to the copilot's root with NO `?c=` —
                // that is what loads its stored history.
                row(
                  LucideIcons.messageSquare,
                  'Conversation',
                  go(WorkspaceSection.conversation, base),
                  active: section == WorkspaceSection.conversation,
                ),
                row(
                  LucideIcons.workflow,
                  'Workflows',
                  go(WorkspaceSection.workflows, '$base/workflows'),
                  active: section == WorkspaceSection.workflows,
                ),
                row(
                  LucideIcons.blocks,
                  'Plugins',
                  go(WorkspaceSection.plugins, '$base/plugins'),
                  active: section == WorkspaceSection.plugins,
                ),
                // Customize is not a page: it opens the settings sheet on General.
                row(
                  LucideIcons.slidersHorizontal,
                  'Customize',
                  () => showCopilotSettings(context, copilot, panel: 'general'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Text(
                    'Channels',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
                  ),
                ),
                // Straight to that channel's instructions in the settings sheet.
                for (final ch in copilotChannels)
                  row(
                    ch.icon,
                    ch.label,
                    () => showCopilotSettings(context, copilot, panel: 'channels', channel: ch.id),
                    leading: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(color: ch.tint, shape: BoxShape.circle),
                      child: Icon(ch.icon, size: 11, color: Colors.white),
                    ),
                  ),
                Divider(height: 20, color: c.gray200),
                row(LucideIcons.gift, 'Earn bonus credits', () => showInviteCredits(context)),
                row(LucideIcons.sparkles, "What's new", () => showWhatsNew(context)),
                row(LucideIcons.messageCircleMore, 'Leave feedback', () => showFeedback(context)),
              ],
            ),
          ),
        ),
      );
    },
  );
  action?.call();
}
