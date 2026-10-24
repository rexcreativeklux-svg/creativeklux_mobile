import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_result.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import '../brand.dart';
import 'manage_ui.dart';
import 'members_tab.dart' show BlankFallback;

/// Port of `brand/manage/components/AiKeysTab.jsx` + `AddAiKeyModal.jsx` +
/// `lib/aiCredentials.js` — bring-your-own provider keys per capability.

const _capabilities = [
  ('chat', 'Chat', 'Copilot conversations, captions and every text generation.'),
  ('image', 'Image', 'Magic Studio and creative image generation.'),
  ('video', 'Video', 'Video generation jobs.'),
];

const _systemProvider = {'chat': 'Ariziy', 'image': 'Ariziy', 'video': 'fal'};

const _providerMeta = <String, (String, String, String?)>{
  'openai': ('OpenAI', 'sk-…', null),
  'anthropic': ('Anthropic', 'sk-ant-…', null),
  'gemini': ('Google Gemini', 'AIza…', null),
  'ariziy_byok': ('Ariziy', 'Your Ariziy API key', null),
  'fal_byok': (
    'fal',
    'key_id:key_secret',
    'Paste the full key including the colon — key_id:key_secret. The first half alone will be rejected.',
  ),
  'veo': ('Google Veo', 'AIza…', null),
  'runway': ('Runway', 'key_…', "Runway is image-to-video only — text-only prompts will fail while it's active."),
};

const _fallbackProviders = {
  'chat': ['openai', 'anthropic', 'gemini', 'ariziy_byok'],
  'image': ['openai', 'gemini', 'fal_byok', 'ariziy_byok'],
  'video': ['veo', 'runway', 'fal_byok'],
};

String _providerLabel(String id, [String? fallback]) => fallback ?? _providerMeta[id]?.$1 ?? id;

bool _truthy(dynamic v) => v == true || v == 1 || v == '1';

class _Provider {
  _Provider(this.id, this.label, this.models, this.freeModel);
  final String id;
  final String label;
  final List<(String, String)> models;
  final bool freeModel;
}

class _Credential {
  _Credential(Map m)
    : id = m['id'],
      capability = '${m['capability']}',
      provider = '${m['provider']}',
      model = '${m['model'] ?? ''}',
      active = _truthy(m['is_active'] ?? m['active']),
      keyPreview =
          (m['key_preview'] ??
                  m['masked_key'] ??
                  m['key_hint'] ??
                  (m['last_four'] != null ? '••••${m['last_four']}' : ''))
              .toString(),
      status = '${m['status'] ?? (m['verified_at'] != null ? 'verified' : '')}',
      error = '${m['last_error'] ?? m['error'] ?? ''}';

  final Object? id;
  final String capability;
  final String provider;
  final String model;
  bool active;
  final String keyPreview;
  final String status;
  final String error;

  bool get failed => status == 'failed' || status == 'invalid' || error.isNotEmpty;
}

class _Capability {
  _Capability(this.id, this.label, this.description, this.providers, this.credentials, this.activeId);
  final String id;
  final String label;
  final String description;
  final List<_Provider> providers;
  final List<_Credential> credentials;
  final Object? activeId;
}

List<(String, String)> _models(dynamic models) {
  if (models == null) return [];
  final list = models is List
      ? models
      : (models as Map).entries
            .map((e) => e.value is String ? {'id': e.key, 'label': e.value} : {'id': e.key, ...?(e.value as Map?)})
            .toList();
  return [
    for (final m in list)
      if (m is String)
        (m, m)
      else if (m is Map && (m['id'] ?? m['model'] ?? m['value']) != null)
        ('${m['id'] ?? m['model'] ?? m['value']}', '${m['label'] ?? m['name'] ?? m['id'] ?? m['model']}'),
  ];
}

_Provider _provider(dynamic raw, String id, String capability) {
  final r = raw is Map ? raw : const {};
  final models = r['models'];
  final pid = '${r['id'] ?? r['key'] ?? r['provider'] ?? id}';
  return _Provider(
    pid,
    _providerLabel(pid, (r['label'] ?? r['name'])?.toString()),
    _models(models is Map && models[capability] != null ? models[capability] : models),
    _truthy(r['free_model']),
  );
}

List<_Provider> _providersFor(Map payload, String capability) {
  final src = payload['providers'] ?? payload['available'] ?? payload['capabilities'];
  final perCap = src is Map ? src[capability] : null;
  if (perCap != null) {
    final inner = perCap is Map && perCap['providers'] != null ? perCap['providers'] : perCap;
    if (inner is List) return [for (final p in inner) _provider(p, '${(p as Map?)?['id']}', capability)];
    if (inner is Map) return [for (final e in inner.entries) _provider(e.value, '${e.key}', capability)];
  }
  if (src is Map) {
    final flat = [
      for (final e in src.entries)
        if (e.value is Map && (e.value['capabilities'] as List?)?.contains(capability) == true)
          _provider(e.value, '${e.key}', capability),
    ];
    if (flat.isNotEmpty) return flat;
  }
  return [for (final id in _fallbackProviders[capability]!) _provider(null, id, capability)];
}

/// Port of `normalizeAiCredentials` — accepts the response shapes the web does.
List<_Capability> _normalize(dynamic raw) {
  final rawMap = raw is Map ? raw : const {};
  final payload = rawMap['data'] is Map ? rawMap['data'] as Map : rawMap;
  final savedRaw = payload['credentials'] ?? payload['saved'] ?? (rawMap['data'] is List ? rawMap['data'] : []);
  final saved = [
    for (final c in (savedRaw is Map ? savedRaw.values : savedRaw as List).expand((v) => v is List ? v : [v]))
      if (c is Map) _Credential(c),
  ];
  final activeMap = payload['active'] is Map ? payload['active'] as Map : const {};

  return [
    for (final (id, label, description) in _capabilities)
      () {
        final creds = saved.where((c) => c.capability == id).toList();
        final entry = activeMap[id];
        final activeVal = entry is Map ? (entry['id'] ?? entry['credential_id'] ?? entry['provider']) : entry;
        Object? activeId = creds.where((c) => c.active).firstOrNull?.id;
        if (activeVal != null) {
          activeId = creds
              .where((c) => '${c.id}' == '$activeVal' || c.provider == '$activeVal')
              .firstOrNull
              ?.id; // "system" or unknown → our key
        }
        for (final c in creds) {
          c.active = c.id == activeId;
        }
        return _Capability(id, label, description, _providersFor(payload, id), creds, activeId);
      }(),
  ];
}

class AiKeysTab extends StatefulWidget {
  const AiKeysTab({super.key, required this.brand});

  final Brand brand;

  @override
  State<AiKeysTab> createState() => _AiKeysTabState();
}

class _AiKeysTabState extends State<AiKeysTab> {
  List<_Capability>? _caps;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await context.read<AuthController>().brandApi.aiCredentials(widget.brand.id);
    if (!mounted) return;
    setState(() {
      _error = res.ok ? null : res.message;
      _caps = res.ok ? _normalize(res.raw) : _caps;
    });
  }

  /// Run an action, toast, then reload the list either way.
  Future<void> _run(Future<ApiResult> Function() call, String success) async {
    setState(() => _busy = true);
    final res = await call();
    if (!mounted) return;
    res.ok ? Toast.success(success) : Toast.error(res.message);
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _addKey(_Capability cap) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddKeySheet(brandId: widget.brand.id, capability: cap),
    );
    if (saved == true) _load();
  }

  Future<void> _remove(_Capability cap, _Credential cred) async {
    final api = context.read<AuthController>().brandApi;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ConfirmCard(
        title: 'Remove this key?',
        body: Text(
          cred.active
              ? "This key is active. Removing it switches ${cap.id} back to Creativeklux's key, which is paid in tokens."
              : 'The key will be deleted from this brand.',
          style: TextStyle(fontSize: 13.5, height: 1.45, color: ctx.colors.gray600),
        ),
        confirmLabel: 'Remove',
        onConfirm: () => Navigator.pop(ctx, true),
      ),
    );
    if (ok == true) await _run(() => api.deleteAiCredential(widget.brand.id, cred.id!), 'Key removed');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final api = context.read<AuthController>().brandApi;
    final caps = _caps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InfoBanner(
          children: [
            TextSpan(
              text: 'Bring your own API key: ',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text:
                  "by default this brand runs on Creativeklux's AI and pays in tokens. Add your own provider key "
                  'and that provider bills you directly — no tokens are charged for that capability.',
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_error != null && caps == null)
          ManageCard(
            child: Column(
              children: [
                const Icon(LucideIcons.triangleAlert, color: AppColors.amber500),
                const SizedBox(height: 8),
                Text(
                  "Couldn't load AI keys: $_error",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.gray600),
                ),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: _load, child: const Text('Try again')),
              ],
            ),
          )
        else if (caps == null)
          for (var i = 0; i < 3; i++)
            Container(
              height: 120,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(14)),
            )
        else
          for (final cap in caps) ...[
            ManageCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cap.label,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.gray900),
                              ),
                              Text(cap.description, style: TextStyle(fontSize: 12.5, color: c.gray500)),
                            ],
                          ),
                        ),
                        GradientButton(
                          label: 'Add key',
                          icon: LucideIcons.plus,
                          onPressed: _busy ? null : () => _addKey(cap),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: c.gray100),
                  _row(
                    context,
                    icon: LucideIcons.coins,
                    title: 'Creativeklux key',
                    active: cap.activeId == null,
                    subtitle: '${_systemProvider[cap.id]} · paid in tokens',
                    actions: [
                      if (cap.activeId != null)
                        _miniButton(
                          'Use',
                          () => _run(
                            () => api.revertToSystemKey(widget.brand.id, cap.id),
                            "${cap.label} is back on Creativeklux's key",
                          ),
                        ),
                    ],
                  ),
                  for (final cred in cap.credentials) ...[
                    Divider(height: 1, color: c.gray100),
                    _row(
                      context,
                      icon: LucideIcons.keyRound,
                      title: _providerLabel(cred.provider),
                      active: cred.active,
                      failed: cred.failed,
                      subtitle: [
                        if (cred.model.isNotEmpty) cred.model,
                        if (cred.keyPreview.isNotEmpty) cred.keyPreview,
                        'billed by provider',
                      ].join(' · '),
                      error: cred.error,
                      actions: [
                        if (!cred.active)
                          _miniButton(
                            'Use',
                            () => _run(
                              () => api.activateAiCredential(widget.brand.id, cred.id!),
                              '${cap.label} now uses your ${_providerLabel(cred.provider)} key',
                            ),
                          ),
                        _miniButton(
                          'Re-check',
                          () => _run(
                            () => api.verifyAiCredential(widget.brand.id, cred.id!),
                            '${_providerLabel(cred.provider)} key is working',
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove key',
                          onPressed: _busy ? null : () => _remove(cap, cred),
                          icon: const Icon(LucideIcons.trash2, size: 16, color: AppColors.red500),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _miniButton(String label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: OutlinedButton(
      onPressed: _busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        side: BorderSide(color: context.colors.gray200),
        foregroundColor: context.colors.gray700,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    ),
  );

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool active,
    required String subtitle,
    required List<Widget> actions,
    bool failed = false,
    String error = '',
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 16, color: c.gray600),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                        ),
                        if (active) const StatusChip('✓ Active', fg: Color(0xFF047857), bg: Color(0xFFECFDF5)),
                        if (failed) const StatusChip('⚠ Check failed', fg: Color(0xFFB45309), bg: Color(0xFFFFFBEB)),
                      ],
                    ),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: c.gray500)),
                    if (error.isNotEmpty) Text(error, style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ),
        ],
      ),
    );
  }
}

class _AddKeySheet extends StatefulWidget {
  const _AddKeySheet({required this.brandId, required this.capability});

  final int brandId;
  final _Capability capability;

  @override
  State<_AddKeySheet> createState() => _AddKeySheetState();
}

class _AddKeySheetState extends State<_AddKeySheet> {
  late _Provider _provider = widget.capability.providers.first;
  final _key = TextEditingController();
  final _model = TextEditingController();
  bool _activate = true;
  bool _show = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _key.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Paste your API key.');
      return;
    }
    if (_provider.id == 'fal_byok' && !key.contains(':')) {
      setState(() => _error = 'fal keys look like key_id:key_secret — paste the whole thing, colon included.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await context.read<AuthController>().brandApi.saveAiCredential(
      brandId: widget.brandId,
      capability: widget.capability.id,
      provider: _provider.id,
      apiKey: key,
      model: _model.text.trim(),
      activate: _activate,
    );
    if (!mounted) return;
    if (res.ok) {
      Toast.success('${_provider.label} key verified and saved');
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = res.message.ifBlank('Something went wrong.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = _providerMeta[_provider.id];
    final hint = meta?.$3 ?? "Tested against the provider before it's stored. Encrypted at rest.";
    final useFreeText = _provider.freeModel || _provider.models.isEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(LucideIcons.keyRound, size: 18, color: AppColors.blue600),
                const SizedBox(width: 8),
                Text(
                  'Add ${widget.capability.id} key',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.gray900),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ManageField(
              label: 'Provider',
              child: DropdownButtonFormField<String>(
                initialValue: _provider.id,
                isExpanded: true,
                dropdownColor: c.surface,
                decoration: manageInput(context, ''),
                items: [
                  for (final p in widget.capability.providers) DropdownMenuItem(value: p.id, child: Text(p.label)),
                ],
                onChanged: (v) => setState(() {
                  _provider = widget.capability.providers.firstWhere((p) => p.id == v);
                  _model.clear();
                  _error = null;
                }),
              ),
            ),
            const SizedBox(height: 12),
            ManageField(
              label: 'API key',
              child: TextField(
                controller: _key,
                obscureText: !_show,
                autocorrect: false,
                enableSuggestions: false,
                decoration: manageInput(context, meta?.$2 ?? 'API key').copyWith(
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _show = !_show),
                    icon: Icon(_show ? LucideIcons.eyeOff : LucideIcons.eye, size: 16, color: c.gray400),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(hint, style: TextStyle(fontSize: 11.5, color: c.gray500)),
            const SizedBox(height: 12),
            ManageField(
              label: 'Model',
              child: useFreeText
                  ? TextField(
                      controller: _model,
                      decoration: manageInput(context, 'Pick a suggestion or paste any model id'),
                    )
                  : DropdownButtonFormField<String>(
                      isExpanded: true,
                      dropdownColor: c.surface,
                      decoration: manageInput(context, ''),
                      hint: const Text('Default model'),
                      items: [
                        for (final (id, label) in _provider.models) DropdownMenuItem(value: id, child: Text(label)),
                      ],
                      onChanged: (v) => _model.text = v ?? '',
                    ),
            ),
            if (useFreeText && _provider.models.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Any model id from ${_provider.label} works — the list is only suggestions.',
                style: TextStyle(fontSize: 11.5, color: c.gray500),
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final (id, _) in _provider.models)
                    ActionChip(
                      label: Text(id, style: const TextStyle(fontSize: 12)),
                      onPressed: () => _model.text = id,
                    ),
                ],
              ),
            ],
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _activate,
              onChanged: (v) => setState(() => _activate = v ?? true),
              title: Text(
                'Use this key for ${widget.capability.id} right away',
                style: TextStyle(fontSize: 13.5, color: c.gray700),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(fontSize: 12.5, color: AppColors.red500)),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: c.gray600)),
                ),
                const SizedBox(width: 8),
                PrimaryAction(label: _saving ? 'Verifying…' : 'Verify & save', loading: _saving, onPressed: _save),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
