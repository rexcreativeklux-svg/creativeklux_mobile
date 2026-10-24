import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/media.dart';
import '../../../core/ui/toast.dart';
import '../copilot_api.dart';
import '../widgets/copilot_widgets.dart';

/// The API's platform keys where they differ from the app's (creativesApi.js).
String toApiPlatform(String id) => id == 'twitter' ? 'x' : id;
String fromApiPlatform(String provider) => provider == 'x' ? 'twitter' : provider;

/// One row of `GET integrations/catalogue`.
class IntegrationEntry {
  IntegrationEntry(Map<String, dynamic> e)
    : id = fromApiPlatform('${e['provider']}'),
      connected = e['connected'] == true,
      awaitingSelection = e['awaiting_selection'] == true,
      accountLabel = e['account_label']?.toString();

  final String id;
  final bool connected;

  /// ⚠️ NOT connected — a tool firing with no account id is the bug this state
  /// exists to prevent, so it surfaces as "Finish connecting", never as connected.
  final bool awaitingSelection;
  final String? accountLabel;
}

/// The brand's connected apps, for the Plugins screen — port of
/// useBrandIntegrations.js over useIntegrationCatalogue.js.
///
/// ⚠️ THERE IS ONE SET OF INTEGRATIONS: connecting here and on /integrations is
/// the same act, writing the same row. The API runs each platform's OAuth and
/// holds every token — nothing here sees one.
///
/// The web opens the consent page in a tab and waits for a postMessage from
/// the API's callback page. A phone has no opener to post to, so the consent
/// page opens in the browser and, when the app comes back to the foreground,
/// the catalogue is re-read — the catalogue is what says what was stored,
/// whatever the tab reported (the web treats a dropped message the same way).
class BrandIntegrations extends ChangeNotifier with WidgetsBindingObserver {
  BrandIntegrations(this._api, this._brandId, {required this.onNeedsChooser}) {
    WidgetsBinding.instance.addObserver(this);
    refresh().whenComplete(() {
      loading = false;
      notifyListeners();
    });
  }

  final CopilotApi _api;
  final int? _brandId;

  /// A connection that needs its account chosen (a Facebook Page, an ad account).
  final void Function(String platformId) onNeedsChooser;

  List<IntegrationEntry> entries = const [];
  bool loading = true;
  String? error;
  String? connectingId;
  String? disconnectingId;
  bool _disposed = false;

  /// A platform whose consent went through but whose account (Page, ad
  /// account…) is still to be chosen — "Finish connecting" on the web.
  bool awaiting(String platformId) => entries.any((e) => e.id == platformId && e.awaitingSelection && !e.connected);

  /// platform id → the connected row.
  Map<String, IntegrationEntry> get connectedBy => {
    for (final e in entries)
      if (e.connected) e.id: e,
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<List<IntegrationEntry>?> refresh() async {
    try {
      final rows = await _api.integrationCatalogue(_brandId);
      entries = [
        for (final r in rows)
          if (r['provider'] != null) IntegrationEntry(r),
      ];
      error = null;
      _notify();
      return entries;
    } catch (e) {
      error = CopilotFailure.of(e).detail;
      _notify();
      return null;
    }
  }

  /// Back from the consent page: what did the server store?
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || connectingId == null) return;
    final platformId = connectingId!;
    refresh().then((rows) {
      connectingId = null;
      _notify();
      final row = rows?.where((e) => e.id == platformId).firstOrNull;
      if (row == null) return;
      if (row.awaitingSelection) {
        onNeedsChooser(platformId);
      } else if (row.connected) {
        Toast.success('Connected');
      }
    });
  }

  Future<void> connect(String platformId) async {
    if (_brandId == null) {
      Toast.error('Select a brand first.');
      return;
    }
    connectingId = platformId;
    _notify();
    try {
      final url = await _api.connectIntegration(toApiPlatform(platformId), _brandId);
      // Single-use, signed URL — opened exactly as given.
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) throw const CopilotFailure(detail: "Couldn't open the consent page.");
    } catch (e) {
      connectingId = null;
      _notify();
      Toast.error(CopilotFailure.of(e).detail);
    }
  }

  Future<bool> disconnect(String platformId) async {
    disconnectingId = platformId;
    _notify();
    try {
      await _api.disconnectIntegration(toApiPlatform(platformId), _brandId);
      Toast.success('Integration disconnected.');
      await refresh();
      return true;
    } catch (e) {
      Toast.error(CopilotFailure.of(e).detail);
      return false;
    } finally {
      disconnectingId = null;
      _notify();
    }
  }

  Future<(List<Map<String, dynamic>>, String?)> accounts(String platformId) =>
      _api.integrationAccounts(toApiPlatform(platformId), _brandId);

  Future<String?> select(String platformId, Object accountId) =>
      _api.selectIntegrationAccount(toApiPlatform(platformId), accountId, _brandId);
}

/// "Choose an account" (PlatformPageModal.jsx) — which Facebook Page /
/// Instagram account / ad account to connect. An account's `warning` shows,
/// muted, and it stays selectable. Disconnect is the way out when the approved
/// login has nothing to pick.
Future<void> showAccountChooser(BuildContext context, BrandIntegrations integrations, String platformId) async {
  List<Map<String, dynamic>> accounts;
  String? message;
  try {
    (accounts, message) = await integrations.accounts(platformId);
  } catch (e) {
    Toast.error(CopilotFailure.of(e).detail);
    return;
  }
  if (!context.mounted) return;
  await showCopilotSheet<void>(
    context,
    title: 'Choose an account',
    builder: (ctx) =>
        _ChooserBody(integrations: integrations, platformId: platformId, accounts: accounts, message: message),
  );
}

class _ChooserBody extends StatefulWidget {
  const _ChooserBody({required this.integrations, required this.platformId, required this.accounts, this.message});
  final BrandIntegrations integrations;
  final String platformId;
  final List<Map<String, dynamic>> accounts;
  final String? message;

  @override
  State<_ChooserBody> createState() => _ChooserBodyState();
}

class _ChooserBodyState extends State<_ChooserBody> {
  late List<Map<String, dynamic>> _accounts = widget.accounts;
  late String? _message = widget.message;
  Object? _loadingId;
  bool _disconnecting = false;

  bool get _busy => _loadingId != null || _disconnecting;

  Future<void> _pick(Map<String, dynamic> account) async {
    setState(() => _loadingId = account['id']);
    try {
      final msg = await widget.integrations.select(widget.platformId, account['id'] as Object);
      Toast.success(msg ?? '${account['name'] ?? 'Account'} connected');
      await widget.integrations.refresh();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      Toast.error(CopilotFailure.of(e).detail);
      // A refused choice usually means a stale list — fetch it again.
      try {
        final (a, m) = await widget.integrations.accounts(widget.platformId);
        if (mounted) {
          setState(() {
            _accounts = a;
            _message = m;
          });
        }
      } catch (_) {}
      if (mounted) setState(() => _loadingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text('Pick which one to connect to this brand.', style: TextStyle(fontSize: 12.5, color: c.gray500)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (_accounts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      _message ?? 'No accounts are available to connect.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: c.gray500),
                    ),
                  ),
                for (final a in _accounts) _accountTile(context, a),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _disconnecting = true);
                            final ok = await widget.integrations.disconnect(widget.platformId);
                            if (!mounted) return;
                            ok ? Navigator.pop(this.context) : setState(() => _disconnecting = false);
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red600,
                      side: BorderSide(color: AppColors.red600.withValues(alpha: 0.3)),
                    ),
                    child: Text(_disconnecting ? 'Disconnecting…' : 'Disconnect'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: c.gray500)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountTile(BuildContext context, Map<String, dynamic> a) {
    final c = context.colors;
    final name = '${a['name'] ?? a['id']}';
    final picture = a['picture'];
    final avatar =
        a['avatar']?.toString() ??
        (picture is Map && picture['data'] is Map ? picture['data']['url']?.toString() : null);
    final loading = _loadingId != null && _loadingId == a['id'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: _busy ? null : () => _pick(a),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.gray200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: avatar != null
                      ? MediaImage(avatar, fit: BoxFit.cover)
                      : Container(
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(colors: [Color(0xFF1877F2), Color(0xFF0C5FCA)]),
                          ),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'A',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.gray800),
                    ),
                    Text('ID: ${a['id']}', style: TextStyle(fontSize: 11, color: c.gray400)),
                    if (a['warning'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(LucideIcons.triangleAlert, size: 12, color: AppColors.amber500),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${a['warning']}',
                                style: const TextStyle(fontSize: 11, color: AppColors.amber500),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue500),
                )
              else
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.gray200, width: 2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
