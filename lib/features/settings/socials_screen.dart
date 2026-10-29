import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/auth_controller.dart';
import '../copilot/copilot_api.dart';
import '../copilot/plugins/brand_integrations.dart';
import 'settings_widgets.dart';

/// One card of the web's `socialPlatforms` list. [id] is the app's platform
/// id (`twitter` for X — see `toApiPlatform`).
class _Social {
  const _Social(this.id, this.name, this.description, this.color, this.icon);

  final String id;
  final String name;
  final String description;
  final Color color;
  final IconData icon;
}

// Lucide has no brand logos, so each card is a neutral glyph on the platform's
// colour (the web uses /logos/*.png).
const _platforms = [
  _Social(
    'facebook',
    'Facebook',
    'Connect your Facebook account to share updates',
    Color(0xFF1877F2),
    LucideIcons.thumbsUp,
  ),
  _Social('instagram', 'Instagram', 'Sync your Instagram for media sharing', Color(0xFFE1306C), LucideIcons.camera),
  _Social('linkedin', 'LinkedIn', 'Post updates directly from the platform', Color(0xFF0A66C2), LucideIcons.briefcase),
  _Social('tiktok', 'TikTok', 'Sync your TikTok for media sharing', Color(0xFF010101), LucideIcons.music),
  _Social('youtube', 'YouTube', 'Post updates directly from the platform', Color(0xFFFF0000), LucideIcons.play),
  _Social('pinterest', 'Pinterest', 'Sync your Pinterest for media sharing', Color(0xFFE60023), LucideIcons.pin),
  _Social('reddit', 'Reddit', 'Post updates directly from the platform', Color(0xFFFF4500), LucideIcons.messageSquare),
  _Social('twitter', 'X (Twitter)', 'Post updates directly from the platform', Color(0xFF14171A), LucideIcons.atSign),
];

/// Port of `(settings)/socials/page.jsx` — "Social Integrations": the eight
/// platform cards with Connect / Disconnect.
///
/// ⚠️ Deliberately NOT the web's data path. The web page reads the legacy
/// `GET /social-accounts`, and its Connect is retired (AuthContext's
/// `connectSocialAccount` just toasts "Accounts are now connected on the
/// Integrations page"). So the cards here run on the brand's integrations
/// catalogue instead (`BrandIntegrations`, the same one set of connections
/// /integrations and Copilot plugins use): Connect opens the API's OAuth
/// consent page in the browser, and the card updates when the app returns.
class SocialsScreen extends StatefulWidget {
  const SocialsScreen({super.key});

  @override
  State<SocialsScreen> createState() => _SocialsScreenState();
}

class _SocialsScreenState extends State<SocialsScreen> {
  BrandIntegrations? _integrations;
  int? _brandId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthController>();
    final brandId = auth.activeBrand?.id;
    // Connections belong to a brand — switching brands re-reads them.
    if (_integrations == null || brandId != _brandId) {
      _integrations?.dispose();
      _brandId = brandId;
      _integrations = BrandIntegrations(
        CopilotApi(auth.api),
        brandId,
        onNeedsChooser: (id) {
          if (mounted) showAccountChooser(context, _integrations!, id);
        },
      );
    }
  }

  @override
  void dispose() {
    _integrations?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final integrations = _integrations!;
    return SettingsScaffold(
      onRefresh: () => integrations.refresh(),
      children: [
        const SettingsHeader('Social Integrations'),
        ListenableBuilder(
          listenable: integrations,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (integrations.error != null && !integrations.loading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(integrations.error!, style: const TextStyle(fontSize: 12.5, color: AppColors.red500)),
                ),
              for (final p in _platforms)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: _card(context, integrations, p)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, BrandIntegrations integrations, _Social p) {
    final c = context.colors;
    final row = integrations.connectedBy[p.id];
    final connected = row != null;
    final awaiting = integrations.awaiting(p.id);
    final connecting = integrations.connectingId == p.id;
    final disconnecting = integrations.disconnectingId == p.id;
    final label = row?.accountLabel;

    Widget action;
    if (integrations.loading) {
      // Until the catalogue lands we can't say Connect or Disconnect, and a
      // guessed "Connect" invites re-connecting a connected platform — so only
      // the button waits (the web's skeleton).
      action = Container(
        width: 104,
        height: 34,
        decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(8)),
      );
    } else {
      final (text, color, onTap) = connected
          ? ('DISCONNECT', AppColors.red500, () => integrations.disconnect(p.id))
          : awaiting
          ? ('FINISH', AppColors.amber500, () => showAccountChooser(context, integrations, p.id))
          : ('CONNECT', AppColors.blue600, () => integrations.connect(p.id));
      final busy = connecting || disconnecting;
      action = SizedBox(
        height: 34,
        child: FilledButton(
          onPressed: busy || integrations.connectingId != null ? null : onTap,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: color.withValues(alpha: busy ? 0.6 : 0.35),
            disabledForegroundColor: Colors.white,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4),
          ),
          child: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(text),
        ),
      );
    }

    return SettingsCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: p.color, shape: BoxShape.circle),
            child: Icon(p.icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: c.gray900),
                ),
                const SizedBox(height: 2),
                Text(
                  connected && label != null && label.isNotEmpty ? 'Connected as $label' : p.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.gray500, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          action,
        ],
      ),
    );
  }
}
