import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import '../copilot/copilot_api.dart';
import '../copilot/data/copilot_catalog.dart';
import '../copilot/plugins/brand_integrations.dart';
import '../copilot/widgets/copilot_widgets.dart';
import '../shell/widgets/app_top_bar.dart';
import 'productivity_platforms.dart';

/// [BrandIntegrations], plus the catalogue's own labels and order.
///
/// The Integrations page names every row the way the catalogue does and lists
/// Productivity as "whatever the catalogue has outside Social/Ads", which
/// needs each row's `label` — and [IntegrationEntry] keeps only the state. So
/// this reads the same single request and keeps the labels too, rather than
/// asking for the catalogue twice.
class _CatalogueIntegrations extends BrandIntegrations {
  _CatalogueIntegrations(this._copilotApi, this._brand, {required super.onNeedsChooser}) : super(_copilotApi, _brand);

  final CopilotApi _copilotApi;
  final int? _brand;

  /// Catalogue order of platform ids → label.
  Map<String, String> labels = {};
  bool _gone = false;

  @override
  Future<List<IntegrationEntry>?> refresh() async {
    try {
      final rows = [
        for (final r in await _copilotApi.integrationCatalogue(_brand))
          if (r['provider'] != null) r,
      ];
      labels = {for (final r in rows) fromApiPlatform('${r['provider']}'): '${r['label'] ?? r['provider']}'};
      entries = [for (final r in rows) IntegrationEntry(r)];
      error = null;
      notifyListeners();
      return entries;
    } catch (e) {
      error = CopilotFailure.of(e).detail;
      notifyListeners();
      return null;
    }
  }

  /// A brand switch disposes this mid-request; the base class's first-load
  /// callback would then notify a disposed notifier (an assert in debug).
  @override
  void notifyListeners() {
    if (!_gone) super.notifyListeners();
  }

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }
}

/// One row on the page: its id, name and description, and how to draw its mark.
class _Row {
  const _Row({required this.id, required this.name, required this.description, this.productivity});
  final String id;
  final String name;
  final String description;

  /// Set for a Productivity row (its own mark); null = a Social/Ads platform,
  /// drawn by the copilot catalogue's [PlatformChip].
  final ProductivityPlatform? productivity;
}

/// /integrations — port of `(dashboard)/(pages)/integrations/page.jsx`.
///
/// ⚠️ ONE SET OF INTEGRATIONS: the same `useIntegrationCatalogue` flow as the
/// copilot's Plugins screen, through the same [BrandIntegrations] — connect
/// opens the API's consent page in the browser, and the catalogue is re-read
/// when the app comes back to the foreground. Every state comes from
/// `GET integrations/catalogue`; nothing here handles a token.
///
/// Integrations belong to the ACTIVE brand, so switching brand reloads them.
class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  _CatalogueIntegrations? _integrations;
  int? _brandId;
  bool _reportedError = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthController>();
    final brandId = auth.activeBrand?.id;
    if (_integrations != null && brandId == _brandId) return;
    _integrations?.removeListener(_onChange);
    _integrations?.dispose();
    _brandId = brandId;
    _reportedError = false;
    _integrations = _CatalogueIntegrations(
      CopilotApi(auth.api),
      brandId,
      onNeedsChooser: (platformId) {
        if (mounted) showAccountChooser(context, _integrations!, platformId);
      },
    )..addListener(_onChange);
  }

  /// The catalogue couldn't be read — say why, once, in the server's words.
  /// The rows still render (as not connected) so the page isn't blank.
  void _onChange() {
    final i = _integrations;
    if (i == null || i.loading || i.error == null || _reportedError) return;
    _reportedError = true;
    Toast.error(i.error!);
  }

  @override
  void dispose() {
    _integrations?.removeListener(_onChange);
    _integrations?.dispose();
    super.dispose();
  }

  List<_Row> _rowsFor(String category, Map<String, String> labels) => [
    for (final p in copilotPlatforms)
      if (p.category == category) _Row(id: p.id, name: labels[p.id] ?? p.name, description: p.description),
  ];

  /// Whatever the catalogue lists outside Social/Ads, in its order and under
  /// its labels; the local list stands in when the catalogue couldn't be read.
  List<_Row> _productivity(Map<String, String> labels) {
    final sectioned = {for (final p in copilotPlatforms) p.id};
    final ids = labels.keys.where((id) => !sectioned.contains(id)).toList();
    if (ids.isEmpty) {
      return [
        for (final p in productivityPlatforms)
          _Row(id: p.id, name: p.name, description: p.description, productivity: p),
      ];
    }
    return [
      for (final id in ids)
        () {
          final known = productivityPlatforms.where((p) => p.id == id).firstOrNull;
          return _Row(
            id: id,
            name: labels[id]!,
            description: known?.description ?? '',
            productivity:
                known ??
                ProductivityPlatform(
                  id: id,
                  name: labels[id]!,
                  description: '',
                  colors: genericPlatformColors,
                  svg: '',
                ),
          );
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final integrations = _integrations!;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Integrations', showBack: true),
          Expanded(
            child: ColoredBox(
              color: c.page,
              child: ListenableBuilder(
                listenable: integrations,
                builder: (context, _) {
                  final labels = integrations.labels;
                  final sections = [
                    ('Social Media', _rowsFor('Social', labels)),
                    ('Advertising Platforms', _rowsFor('Advertising', labels)),
                    ('Productivity', _productivity(labels)),
                  ];
                  return RefreshIndicator(
                    onRefresh: () async => integrations.refresh(),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(16, 18, 16, 28 + MediaQuery.paddingOf(context).bottom),
                      children: [
                        Text(
                          'Integrations',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.gray900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Connect your accounts with one click — CreativeKlux opens the platform login, you approve, and it's done.",
                          style: TextStyle(fontSize: 13, height: 1.45, color: c.gray500),
                        ),
                        const SizedBox(height: 16),
                        const _Banner(
                          icon: LucideIcons.info,
                          lead: 'How it works: ',
                          // "A new tab opens" on the web; here it's the browser.
                          text: 'Tap Connect on any platform. Your browser opens, where you log in and approve permissions. Some platforms then ask which Page or account to use. The connection is saved to your active brand.',
                          bg: Color(0xFFEFF4FF),
                          border: Color(0xFFC7D9FD),
                          iconColor: Color(0xFF155DFC),
                          fg: Color(0xFF1E40AF),
                        ),
                        const SizedBox(height: 24),
                        for (final (title, rows) in sections) ...[
                          Text(
                            title,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.gray900),
                          ),
                          const SizedBox(height: 12),
                          for (final r in rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _PlatformCard(row: r, integrations: integrations),
                            ),
                          const SizedBox(height: 18),
                        ],
                        Text(
                          "Disconnecting removes access from Creative Klux only — to remove the app from your account entirely, revoke it in that platform's own security settings.",
                          style: TextStyle(fontSize: 12, height: 1.45, color: c.gray500),
                        ),
                        const SizedBox(height: 20),
                        const _Banner(
                          icon: LucideIcons.circleAlert,
                          lead: 'Note: ',
                          text: 'Connected integrations are linked to your active brand. Switch your active brand to manage integrations for other brands.',
                          bg: Color(0xFFFFFBEB),
                          border: Color(0xFFFDE68A),
                          iconColor: Color(0xFFF59E0B),
                          fg: Color(0xFF92400E),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tinted info / note boxes. Fixed colours, as on the web (they're
/// hard-coded hexes there too, not theme tokens).
class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.lead,
    required this.text,
    required this.bg,
    required this.border,
    required this.iconColor,
    required this.fg,
  });

  final IconData icon;
  final String lead;
  final String text;
  final Color bg;
  final Color border;
  final Color iconColor;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        // In dark mode the pale fill would glare; tint it instead.
        color: dark ? iconColor.withValues(alpha: 0.12) : bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dark ? iconColor.withValues(alpha: 0.3) : border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 13, height: 1.5, color: dark ? context.colors.gray700 : fg),
                children: [
                  TextSpan(
                    text: lead,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// PlatformCard. Three states, straight from the catalogue:
///   connected          → green chip (the account it posts as) + Disconnect
///   awaiting selection → consent done, account not chosen: "Finish connecting"
///   neither            → Connect
///
/// Phone layout: the mark, name and blurb on top, and the status chip with
/// the action under them — "Finish connecting" beside the text would leave
/// the description a few characters wide at 360dp.
class _PlatformCard extends StatelessWidget {
  const _PlatformCard({required this.row, required this.integrations});
  final _Row row;
  final _CatalogueIntegrations integrations;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entry = integrations.entries.where((e) => e.id == row.id).firstOrNull;
    final connected = entry?.connected ?? false;
    final awaiting = !connected && (entry?.awaitingSelection ?? false);
    final connecting = integrations.connectingId == row.id;
    final disconnecting = integrations.disconnectingId == row.id;
    final busy = connecting || disconnecting;
    // The rows themselves, greyed out, while the catalogue loads: the list is
    // known before the request returns; only each row's state is pending.
    final loading = integrations.loading;

    final (chipLabel, chipFg, chipBg) = connected
        ? (entry?.accountLabel ?? 'Connected', const Color(0xFF15803D), const Color(0xFF22C55E))
        : awaiting
        ? ('Choose an account to finish', const Color(0xFFB45309), const Color(0xFFF59E0B))
        : ('Not connected', c.gray500, c.gray400);

    return Opacity(
      opacity: loading ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.gray200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Mark(row: row),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                      ),
                      if (row.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          row.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, height: 1.35, color: c.gray500),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                // Takes all the width the button leaves, hugging the left.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: chipBg.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: chipBg.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (connected) ...[
                            Icon(LucideIcons.check, size: 11, color: chipFg),
                            const SizedBox(width: 3),
                          ],
                          Flexible(
                            child: Text(
                              loading ? 'Checking…' : chipLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: chipFg),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (connected)
                  OutlinedButton(
                    onPressed: busy || loading ? null : () => integrations.disconnect(row.id),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      foregroundColor: AppColors.red600,
                      side: BorderSide(color: AppColors.red600.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                    ),
                    child: Text(disconnecting ? 'Disconnecting…' : 'Disconnect'),
                  )
                else
                  FilledButton.icon(
                    onPressed: busy || loading
                        ? null
                        : () => awaiting
                              ? showAccountChooser(context, integrations, row.id)
                              : integrations.connect(row.id),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      backgroundColor: AppColors.blue600,
                      disabledBackgroundColor: AppColors.blue600.withValues(alpha: 0.6),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    icon: connecting
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const SizedBox.shrink(),
                    label: Text(
                      connecting
                          ? 'Connecting…'
                          : awaiting
                          ? 'Finish connecting'
                          : 'Connect',
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

/// The platform's mark on its gradient tile.
class _Mark extends StatelessWidget {
  const _Mark({required this.row});
  final _Row row;

  static const size = 42.0;

  @override
  Widget build(BuildContext context) {
    final p = row.productivity;
    if (p == null) return PlatformChip(row.id, size: size);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(size * 0.24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.26),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: p.colors),
      ),
      child: p.svg.isEmpty ? const Icon(LucideIcons.plug, size: 18, color: Colors.white) : SvgPicture.string(p.svg),
    );
  }
}
