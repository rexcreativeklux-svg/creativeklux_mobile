import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart' show AppColorsContext;
import '../copilot_store.dart';
import '../data/copilot_data.dart';
import '../widgets/copilot_widgets.dart';
import 'settings_panels.dart';

/// The settings sheet's nav, in order (settings/settingsNav.js) — ONE list that
/// is both the nav and the router, so a panel cannot be listed and unreachable.
/// `id` is what the workspace menu passes in, so it stays stable.
const _nav = [
  ('general', 'General', LucideIcons.slidersHorizontal),
  ('sharing', 'Sharing & access', LucideIcons.share2),
  ('credits', 'Credit usage', LucideIcons.coins),
  ('personalization', 'Personalization', LucideIcons.sparkles),
  ('channels', 'Channels', LucideIcons.messageCircleMore),
  ('security', 'Security', LucideIcons.shieldCheck),
  ('developer', 'Developer', LucideIcons.code),
];

/// One sheet for everything about a copilot that is not a conversation
/// (CopilotSettingsModal.jsx). Settings you dip into and come back from, so a
/// sheet over the workspace rather than routes.
///
/// The web's below-`md` layout: the rail becomes a horizontal strip of pills,
/// then the pane's own title bar (with a back arrow inside a channel), then
/// the panel scrolling under it.
Future<void> showCopilotSettings(BuildContext context, Copilot copilot, {String panel = 'general', String? channel}) {
  final store = CopilotStore.of(context);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: context.colors.surface.withValues(alpha: 1),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => _SettingsSheet(store: store, copilotId: copilot.id, panel: panel, channel: channel),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.store, required this.copilotId, required this.panel, this.channel});
  final CopilotStore store;
  final String copilotId;
  final String panel;
  final String? channel;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late String _panel = widget.panel;
  late String? _channel = widget.channel;

  void _open(String id) => setState(() {
    _panel = id;
    _channel = null; // never land on Channels with a stale channel pushed
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final media = MediaQuery.of(context);
    return SizedBox(
      height: media.size.height * 0.92,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) {
            final copilot = widget.store.byId(widget.copilotId);
            // Deleted from inside the sheet (General → Delete closes it first,
            // but a delete elsewhere could land while it's open).
            if (copilot == null) return const SizedBox.shrink();
            final item = _nav.firstWhere((n) => n.$1 == _panel, orElse: () => _nav.first);
            final channel = item.$1 == 'channels' ? channelById(_channel) : null;
            void close() => Navigator.pop(context);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                const SheetHandle(),
                // ── Rail, as a strip of pills ──
                Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.gray100)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Row(
                      children: [
                        for (final (id, label, icon) in _nav)
                          Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: Material(
                              color: id == item.$1 ? c.gray200.withValues(alpha: 0.7) : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(9),
                                onTap: () => _open(id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  child: Row(
                                    children: [
                                      Icon(icon, size: 15, color: id == item.$1 ? c.gray900 : c.gray500),
                                      const SizedBox(width: 8),
                                      Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: id == item.$1 ? FontWeight.w600 : FontWeight.w500,
                                          color: id == item.$1 ? c.gray900 : c.gray500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // ── Pane title bar ──
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.gray100)),
                  ),
                  child: Row(
                    children: [
                      if (channel != null)
                        IconButton(
                          tooltip: 'Back to channels',
                          onPressed: () => setState(() => _channel = null),
                          icon: Icon(LucideIcons.chevronLeft, size: 20, color: c.gray400),
                        )
                      else
                        const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          channel != null ? 'Connect to ${channel.short}' : item.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.gray900),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: close,
                        icon: Icon(LucideIcons.x, size: 20, color: c.gray400),
                      ),
                    ],
                  ),
                ),
                // Keyed by panel and channel so switching resets scroll and any
                // half-typed draft instead of carrying it into the next panel.
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey('${item.$1}:${_channel ?? ''}'),
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + media.padding.bottom),
                    child: switch (item.$1) {
                      'sharing' => SharingPanel(copilot: copilot),
                      'credits' => CreditUsagePanel(copilot: copilot, onClose: close),
                      'personalization' => PersonalizationPanel(copilot: copilot, store: widget.store),
                      'channels' =>
                        channel != null
                            ? ChannelConnectView(channel: channel, copilot: copilot, store: widget.store)
                            : ChannelsPanel(onSelect: (id) => setState(() => _channel = id)),
                      'security' => SecurityPanel(copilot: copilot),
                      'developer' => DeveloperPanel(copilot: copilot),
                      _ => GeneralPanel(copilot: copilot, store: widget.store, onClose: close),
                    },
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

/// Ink-on-surface link button that closes the sheet first (View plans,
/// Plans & Billing) — the accent stays reserved for actions.
class SheetLinkBlock extends StatelessWidget {
  const SheetLinkBlock({super.key, required this.title, required this.subtitle, required this.onTap});
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.gray200),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray900),
                  ),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: c.gray500)),
                ],
              ),
            ),
            Icon(LucideIcons.arrowUpRight, size: 16, color: c.gray400),
          ],
        ),
      ),
    );
  }
}
