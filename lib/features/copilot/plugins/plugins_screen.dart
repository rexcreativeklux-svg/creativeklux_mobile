import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/auth_controller.dart';
import '../copilot_store.dart';
import '../data/copilot_catalog.dart';
import '../data/copilot_data.dart';
import '../data/copilot_types.dart';
import '../widgets/copilot_widgets.dart';
import '../workspace/copilot_workspace.dart';
import 'brand_integrations.dart';
import 'plugin_sheets.dart';
import 'skills_tab.dart';

/// /copilot/:id/plugins — the apps and skills a copilot can work with (port
/// of [id]/plugins/page.jsx): Connectors / Skills tabs, the banner, "Most
/// popular" with Browse all, and "Apps connected".
///
/// ⚠️ THE SAME SET OF INTEGRATIONS AS /integrations — one row, one table.
/// Still UI only, as on the web: MCP servers, connector requests, skill upload.
class CopilotPluginsScreen extends StatelessWidget {
  const CopilotPluginsScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) => CopilotWorkspace(
    id: id,
    section: WorkspaceSection.plugins,
    builder: (context, copilot) => _Plugins(copilot: copilot),
  );
}

class _Plugins extends StatefulWidget {
  const _Plugins({required this.copilot});
  final Copilot copilot;

  @override
  State<_Plugins> createState() => _PluginsState();
}

class _PluginsState extends State<_Plugins> {
  /// Cards under "Most popular"; the rest behind "Browse all".
  static const _popular = 8;
  String _tab = 'Connectors';
  late final BrandIntegrations _integrations = BrandIntegrations(
    CopilotStore.of(context).api,
    context.read<AuthController>().activeBrand?.id,
    onNeedsChooser: (platformId) {
      if (mounted) showAccountChooser(context, _integrations, platformId);
    },
  );

  @override
  void dispose() {
    _integrations.dispose();
    super.dispose();
  }

  /// Every skill action lands in the SAME place: a new conversation with the
  /// prompt DRAFTED (`?task=`) — activating differs from creating only in what
  /// it drafts.
  void _openInChat(String prompt) => context.push(
    Uri(
      path: '/copilot/${widget.copilot.id}',
      queryParameters: {'c': CopilotStore.newConversationId(), 'task': prompt},
    ).toString(),
  );

  void _browseConnectors() =>
      showConnectorsSheet(context, _integrations, onRequest: () => showRequestConnectorSheet(context));

  /// The header action belongs to the TAB: the catalog on Connectors, the
  /// Add Skill menu on Skills.
  Widget _headerAction() => _tab == 'Connectors'
      ? InkButton(label: 'Add Connector', icon: LucideIcons.plus, onTap: _browseConnectors)
      : InkButton(
          label: 'Add Skill',
          icon: LucideIcons.plus,
          onTap: () => showChoiceSheet(
            context,
            items: [
              ChoiceItem(
                'Create skill in chat',
                icon: LucideIcons.messageSquarePlus,
                onTap: () => _openInChat(createSkillPrompt),
              ),
              ChoiceItem(
                'Browse skills',
                icon: LucideIcons.layoutGrid,
                onTap: () => showSkillsSheet(context, CopilotStore.of(context)),
              ),
              ChoiceItem(
                'Upload skill file',
                icon: LucideIcons.upload,
                onTap: () => showUploadSkillSheet(context, onAskChat: () => _openInChat(createSkillPrompt)),
              ),
            ],
          ),
        );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: _integrations,
      builder: (context, _) {
        final connectedBy = _integrations.connectedBy;
        final connectedApps = [
          for (final p in copilotPlatforms)
            if (connectedBy.containsKey(p.id)) p,
        ];
        return RefreshIndicator(
          onRefresh: () async => _integrations.refresh(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 28 + MediaQuery.paddingOf(context).bottom),
            children: [
              Text(
                'Plugins',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.gray900),
              ),
              const SizedBox(height: 4),
              Text(
                'Enhance your Copilot experience by integrating with your favorite apps and custom connectors.',
                style: TextStyle(fontSize: 13.5, height: 1.45, color: c.gray500),
              ),
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft, child: _headerAction()),
              const SizedBox(height: 18),
              UnderlineTabs(
                tabs: const ['Connectors', 'Skills'],
                value: _tab,
                onChanged: (t) => setState(() => _tab = t),
              ),
              if (_tab == 'Connectors') ...[
                const SizedBox(height: 18),
                // ── Banner ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 36),
                  decoration: BoxDecoration(color: AppColors.blue600, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text.rich(
                          TextSpan(
                            style: TextStyle(fontSize: 14, color: Colors.white),
                            children: [
                              TextSpan(text: 'Connect your copilot to '),
                              TextSpan(
                                text: 'social, ads, and more',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Publishes your designs and reports back on how they did',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Color(0xFFDBEAFE)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Most popular',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.gray900),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _browseConnectors,
                      iconAlignment: IconAlignment.end,
                      icon: Icon(LucideIcons.arrowRight, size: 15, color: c.gray500),
                      label: Text('Browse all', style: TextStyle(fontSize: 13, color: c.gray500)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final p in copilotPlatforms.take(_popular))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ConnectorCard(platform: p, integrations: _integrations),
                  ),
                // ── Apps connected — the brand's real integrations. ──
                const SizedBox(height: 16),
                Text(
                  'Apps connected',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.gray900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Connected for your whole brand — every copilot can use these, and they are the same apps your Integrations page lists.',
                  style: TextStyle(fontSize: 13, height: 1.45, color: c.gray500),
                ),
                const SizedBox(height: 12),
                if (_integrations.loading)
                  Text('Loading…', style: TextStyle(fontSize: 13.5, color: c.gray400))
                else if (connectedApps.isEmpty)
                  Text(
                    _integrations.error ?? 'No apps connected yet.',
                    style: TextStyle(fontSize: 13.5, color: c.gray500),
                  )
                else
                  for (final p in connectedApps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ConnectorCard(platform: p, integrations: _integrations),
                    ),
              ] else
                SkillsTab(
                  copilot: widget.copilot,
                  onOpenInChat: _openInChat,
                  onBrowseAll: () => showSkillsSheet(context, CopilotStore.of(context)),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One connectable app (ConnectorCard.jsx). ⚠️ CONNECTED STATE IS THE BRAND'S,
/// not the copilot's — hence Disconnect, not "remove from this copilot". Once
/// connected, the account it posts AS replaces the platform blurb.
class ConnectorCard extends StatelessWidget {
  const ConnectorCard({super.key, required this.platform, required this.integrations, this.stacked = false});

  final CopilotPlatform platform;
  final BrandIntegrations integrations;

  /// Wrap the description instead of clamping it to two lines.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final connected = integrations.connectedBy[platform.id];
    final busy = integrations.connectingId == platform.id || integrations.disconnectingId == platform.id;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.gray200),
      ),
      child: Row(
        children: [
          PlatformChip(platform.id, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  platform.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                ),
                const SizedBox(height: 2),
                Text(
                  connected != null ? (connected.accountLabel ?? 'Connected') : platform.description,
                  maxLines: connected != null ? 1 : (stacked ? null : 2),
                  overflow: connected != null || !stacked ? TextOverflow.ellipsis : null,
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: connected != null ? c.gray600 : c.gray500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (connected != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Tw.emerald600.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.check, size: 11, color: Tw.emerald600),
                      SizedBox(width: 3),
                      Text(
                        'Connected',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Tw.emerald600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _SmallButton(label: 'Disconnect', busy: busy, onTap: () => integrations.disconnect(platform.id)),
              ],
            )
          else if (integrations.awaiting(platform.id))
            // Consent went through but no account was picked yet — e.g. the app
            // was closed on the way back from the consent page. The web's
            // "Finish connecting" (integrations/page.jsx).
            _SmallButton(
              label: 'Finish connecting',
              busy: busy,
              onTap: () => showAccountChooser(context, integrations, platform.id),
            )
          else
            // Always visible — there is no hover on a phone.
            _SmallButton(label: 'Connect', busy: busy, onTap: () => integrations.connect(platform.id)),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.busy, required this.onTap});
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return OutlinedButton(
      onPressed: busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        side: BorderSide(color: c.gray300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        foregroundColor: c.gray900,
      ),
      child: busy
          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.gray500))
          : Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }
}
