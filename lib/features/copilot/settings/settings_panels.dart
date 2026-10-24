import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import '../copilot_api.dart';
import '../copilot_store.dart';
import '../data/copilot_data.dart';
import '../widgets/copilot_widgets.dart';
import 'copilot_settings_sheet.dart' show SheetLinkBlock;
import 'settings_ui.dart';

// The seven panels of the copilot settings sheet (settings/*.jsx). Each says
// which of its controls are real and which wait on the Copilot backend.

// ── General ─────────────────────────────────────────────────────────────────

/// The surfaces a copilot can work in, as picker options.
final _surfaceOptions = [
  for (final e in categorySurfaces.entries)
    PickOption(e.key, e.value.name, description: e.value.blurb, icon: e.value.icon),
];
const _allAreas = PickOption('__all', 'All app areas', description: 'Everything this copilot could reach');
const _noAreas = PickOption('__none', 'No app areas', description: 'Chat only — it touches nothing');

/// General — what this copilot runs on, what it may reach, its voice, and
/// clone / delete (GeneralPanel.jsx).
///
/// ⚠️ The model, app-access and voice choices are runtime settings the Copilot
/// backend owns — held locally here, as on the web, rather than pretending to
/// save. The model is deliberately NOT the studio composer's device choice.
class GeneralPanel extends StatefulWidget {
  const GeneralPanel({super.key, required this.copilot, required this.store, required this.onClose});
  final Copilot copilot;
  final CopilotStore store;
  final VoidCallback onClose;

  @override
  State<GeneralPanel> createState() => _GeneralPanelState();
}

class _GeneralPanelState extends State<GeneralPanel> {
  bool _confirming = false;
  String _chatModel = automaticModel.id;
  String _autoModel = automaticModel.id;
  late List<String> _areas = [for (final o in _surfaceOptions) o.id];
  String _voice = defaultVoice;

  VideoPlayerController? _audio;
  bool _playing = false;

  @override
  void dispose() {
    _audio?.dispose();
    super.dispose();
  }

  /// Plays the pre-generated clip the web serves from /voice-samples —
  /// deliberately not an on-device synth behind a settings dropdown.
  Future<void> _toggleVoice() async {
    if (_playing) {
      await _audio?.pause();
      setState(() => _playing = false);
      return;
    }
    await _audio?.dispose();
    final audio = VideoPlayerController.networkUrl(Uri.parse('${AppConfig.webAppUrl}/voice-samples/$_voice.mp3'));
    _audio = audio;
    try {
      await audio.initialize();
      audio.addListener(() {
        final v = audio.value;
        if (mounted && _playing && !v.isPlaying && v.position >= v.duration) setState(() => _playing = false);
      });
      await audio.play();
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
      Toast.error('No sample for that voice yet');
    }
  }

  String _modelLabel(String id) => modelChoices.where((m) => m.id == id).firstOrNull?.label ?? automaticModel.label;

  /// The two specials replace the list; the rest toggle.
  void _toggleArea(String id) => setState(() {
    if (id == _allAreas.id) {
      _areas = [for (final o in _surfaceOptions) o.id];
    } else if (id == _noAreas.id) {
      _areas = [];
    } else {
      _areas.contains(id) ? _areas.remove(id) : _areas.add(id);
    }
  });

  List<String> get _areaValue => _areas.length == _surfaceOptions.length
      ? [_allAreas.id, ..._areas]
      : _areas.isEmpty
      ? [_noAreas.id]
      : _areas;

  String get _areaLabel => _areas.length == _surfaceOptions.length
      ? _allAreas.label
      : _areas.isEmpty
      ? _noAreas.label
      : _areas.length == 1
      ? (_surfaceOptions.where((o) => o.id == _areas.first).firstOrNull?.label ?? '1 app area')
      : '${_areas.length} app areas';

  Widget _viewPlans(BuildContext sheetContext) {
    final router = GoRouter.of(context);
    return InkButton(
      label: 'View plans',
      expand: true,
      onTap: () {
        Navigator.pop(sheetContext);
        widget.onClose();
        router.go('/billing');
      },
    );
  }

  Future<void> _pickModel(String title, String value, ValueChanged<String> set) => showPickSheet(
    context,
    title: title,
    options: modelChoices,
    groups: modelGroups,
    selected: () => [value],
    onChanged: set,
    footer: Builder(builder: _viewPlans),
  );

  @override
  Widget build(BuildContext context) {
    final cp = widget.copilot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'AI models',
          description:
              'Choose models for chat and automations, or keep them on Automatic to pick the best one for each task.',
          children: [
            SettingsRow(
              title: 'Chat',
              description: 'Used for conversations and tools in chat.',
              child: SelectTrigger(
                label: _modelLabel(_chatModel),
                onTap: () => _pickModel('Chat model', _chatModel, (id) => setState(() => _chatModel = id)),
              ),
            ),
            SettingsRow(
              title: 'Automations',
              description: 'Used for scheduled and background tasks.',
              child: SelectTrigger(
                label: _modelLabel(_autoModel),
                onTap: () => _pickModel('Automations model', _autoModel, (id) => setState(() => _autoModel = id)),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Cross-app data access',
          description: 'Which parts of Creative Klux this copilot may work in — read your kits and library, and (where you allow it) change them. Anything it publishes still runs under your connected accounts.',
          children: [
            SelectTrigger(
              label: _areaLabel,
              expand: true,
              onTap: () => showPickSheet(
                context,
                title: 'App areas',
                multiple: true,
                searchable: true,
                options: [_allAreas, _noAreas, ..._surfaceOptions],
                selected: () => _areaValue,
                onChanged: _toggleArea,
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Voice',
          description: 'Pick the voice ${cp.name} speaks in.',
          action: Row(
            children: [
              SelectTrigger(
                label: voiceOptions.firstWhere((v) => v.id == _voice).label,
                onTap: () => showPickSheet(
                  context,
                  title: 'Voice',
                  searchable: true,
                  options: voiceOptions,
                  groups: voiceGroups,
                  selected: () => [_voice],
                  onChanged: (id) {
                    _audio?.pause();
                    setState(() {
                      _voice = id;
                      _playing = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: _playing ? 'Stop preview' : 'Play voice preview',
                style: IconButton.styleFrom(
                  side: BorderSide(color: context.colors.gray200),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _toggleVoice,
                icon: Icon(_playing ? LucideIcons.square : LucideIcons.play, size: 16, color: context.colors.gray500),
              ),
            ],
          ),
        ),
        SettingsSection(
          title: 'Clone copilot',
          description: 'Create a copy of this copilot with its brief, workflows and settings.',
          action: GhostButton(
            label: 'Clone copilot',
            icon: LucideIcons.copy,
            onTap: () {
              // Closes straight away: the toast lands over the page either way.
              widget.onClose();
              widget.store
                  .clone(cp.id)
                  .then((_) => Toast.success('${cp.name} cloned'))
                  .catchError((Object e) => reportFailure(e, "Couldn't clone this copilot"));
            },
          ),
        ),
        // No "Move to folder" — folders have no endpoint.
        SettingsSection(
          title: 'Delete this copilot',
          description: 'Removes it from your catalog along with its conversations. Any connected channel stops working immediately, and this cannot be undone.',
          last: true,
          action: _confirming
              ? Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.colors.redTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.red600.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Delete ${cp.name}? This cannot be undone.',
                        style: const TextStyle(fontSize: 13, color: Tw.red700),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          GhostButton(label: 'Cancel', onTap: () => setState(() => _confirming = false)),
                          const SizedBox(width: 8),
                          GhostButton(
                            label: 'Delete',
                            icon: LucideIcons.trash2,
                            danger: true,
                            // The workspace behind falls to its "Copilot not
                            // found" state, with the way back to the catalog.
                            onTap: () {
                              widget.onClose();
                              widget.store
                                  .remove(cp.id)
                                  .then((_) => Toast.success('${cp.name} deleted'))
                                  .catchError((Object e) => reportFailure(e, "Couldn't delete this copilot"));
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: GhostButton(
                    label: 'Delete this copilot',
                    icon: LucideIcons.trash2,
                    danger: true,
                    onTap: () => setState(() => _confirming = true),
                  ),
                ),
        ),
      ],
    );
  }
}

// ── Sharing & access ────────────────────────────────────────────────────────

/// The link is REAL (copyable); the visibility choice is a server-side
/// permission, so it is held here and the panel says so.
class SharingPanel extends StatefulWidget {
  const SharingPanel({super.key, required this.copilot});
  final Copilot copilot;

  @override
  State<SharingPanel> createState() => _SharingPanelState();
}

class _SharingPanelState extends State<SharingPanel> {
  String _visibility = 'private';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Who can access this copilot',
          description: 'Access is enforced by the Copilot backend, so this choice takes effect once it lands.',
          children: [
            ChoiceList(
              value: _visibility,
              onChanged: (v) => setState(() => _visibility = v),
              options: const [
                ChoiceOption(
                  'private',
                  'Private',
                  'Only you can open this copilot or see its conversations.',
                  LucideIcons.lock,
                ),
                ChoiceOption(
                  'workspace',
                  'Everyone in your workspace',
                  'Teammates can chat with it and run its workflows.',
                  LucideIcons.users,
                ),
                ChoiceOption(
                  'link',
                  'Anyone with the link',
                  'Anyone holding the link can chat with it. It still runs on your credits.',
                  LucideIcons.globe,
                ),
              ],
            ),
          ],
        ),
        SettingsSection(
          title: 'Link',
          description: 'Where this copilot lives. Sharing the link does not grant access on its own.',
          children: [CopyField(label: 'Copilot link', value: '${AppConfig.webAppUrl}/copilot/${widget.copilot.id}')],
        ),
        SettingsSection(
          title: 'People with access',
          description: 'Everyone who has been given this copilot directly.',
          last: true,
          children: [
            // No seeded members — inventing colleagues puts names on screen that don't exist.
            const EmptyNote('Only you, for now.\nInvited teammates appear here.'),
            Align(
              alignment: Alignment.centerRight,
              child: GhostButton(
                label: 'Invite people',
                icon: LucideIcons.userPlus,
                onTap: () => notifyPending('Inviting teammates'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Credit usage ────────────────────────────────────────────────────────────

/// ⚠️ THE NUMBERS ARE NOT INVENTED: a credit balance is account fact, and
/// per-copilot metering doesn't exist yet — so the meter renders empty and the
/// panel points at Plans & Billing.
class CreditUsagePanel extends StatelessWidget {
  const CreditUsagePanel({super.key, required this.copilot, required this.onClose});
  final Copilot copilot;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final router = GoRouter.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'This billing period',
          description: 'Credits ${copilot.name} has used since your plan last renewed.',
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.gray200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '—',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.gray900),
                            ),
                            Text('credits used by this copilot', style: TextStyle(fontSize: 12, color: c.gray500)),
                          ],
                        ),
                      ),
                      Icon(LucideIcons.coins, size: 19, color: c.gray400),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // The meter, empty — here so the panel doesn't re-lay-out
                  // when the first real number arrives.
                  Container(
                    height: 8,
                    decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(99)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Per-copilot metering arrives with the Copilot backend. Your plan balance is live on Plans & Billing.',
                    style: TextStyle(fontSize: 11, height: 1.4, color: c.gray400),
                  ),
                ],
              ),
            ),
            SheetLinkBlock(
              title: 'Plans & Billing',
              subtitle: 'Your plan, quotas and license codes',
              onTap: () {
                onClose();
                router.go('/billing');
              },
            ),
          ],
        ),
        SettingsSection(
          title: 'Where the credits go',
          description: 'Broken down by the kind of work this copilot does.',
          last: true,
          children: [
            for (final (label, hint) in const [
              ('Conversations', 'Messages you exchange with it'),
              ('Workflow runs', 'Its standing jobs, on schedule'),
              ('Generations', 'Designs, copy and images it makes'),
            ])
              SettingsRow(
                title: label,
                description: hint,
                child: Text(
                  '—',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray400),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Personalization ─────────────────────────────────────────────────────────

/// Who the COPILOT is (Identity) and what it knows about YOU (Memory).
///
/// Identity writes through on blur — a rename shows up behind the sheet
/// without a Save button. Memory needs a server, so it holds for the session.
class PersonalizationPanel extends StatefulWidget {
  const PersonalizationPanel({super.key, required this.copilot, required this.store});
  final Copilot copilot;
  final CopilotStore store;

  @override
  State<PersonalizationPanel> createState() => _PersonalizationPanelState();
}

class _PersonalizationPanelState extends State<PersonalizationPanel> {
  String _tab = 'Identity';
  late final _name = TextEditingController(text: widget.copilot.name);
  late final _about = TextEditingController(text: widget.copilot.description);
  final _nameFocus = FocusNode();
  final _aboutFocus = FocusNode();
  late final _yourName = TextEditingController(
    text: (() {
      final u = context.read<AuthController>().user;
      return '${u?['name'] ?? u?['username'] ?? ''}';
    })(),
  );
  final _aboutYou = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Commit on blur, not per keystroke — the name is on screen behind the
    // sheet, and watching it change letter by letter reads as a bug.
    for (final f in [_nameFocus, _aboutFocus]) {
      f.addListener(() {
        if (!f.hasFocus) _commit();
      });
    }
  }

  @override
  void dispose() {
    for (final t in [_name, _about, _yourName, _aboutYou]) {
      t.dispose();
    }
    _nameFocus.dispose();
    _aboutFocus.dispose();
    super.dispose();
  }

  void _commit() {
    final cp = widget.store.byId(widget.copilot.id) ?? widget.copilot;
    final name = _name.text.trim();
    if (name.isEmpty) {
      _name.text = cp.name; // a copilot cannot be nameless — put it back
      Toast.error('A copilot needs a name');
      return;
    }
    final about = _about.text.trim();
    if (name == cp.name && about == cp.description) return;
    widget.store.update(cp.id, {'name': name, 'description': about}).catchError((Object e) {
      if (mounted) _name.text = cp.name; // the store rolled back; the field must agree
      reportFailure(e, "Couldn't save");
    });
  }

  Widget _label(String text, {bool optional = false}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray900),
          children: [
            if (optional)
              TextSpan(
                text: ' (optional)',
                style: TextStyle(fontWeight: FontWeight.w400, color: c.gray400),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cp = widget.copilot;
    final field = TextStyle(fontSize: 13.5, color: c.gray900);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UnderlineTabs(tabs: const ['Identity', 'Memory'], value: _tab, onChanged: (t) => setState(() => _tab = t)),
        const SizedBox(height: 18),
        if (_tab == 'Identity') ...[
          // Not a picker: the tint and glyph are derived, and there's nowhere
          // to store an uploaded avatar yet.
          Align(
            alignment: Alignment.centerLeft,
            child: CopilotAvatar(copilot: cp, size: 56),
          ),
          const SizedBox(height: 16),
          _label('Copilot name'),
          TextField(
            controller: _name,
            focusNode: _nameFocus,
            style: field,
            onSubmitted: (_) => _commit(),
            decoration: copilotFieldDecoration(context, 'Brand Warden'),
          ),
          const SizedBox(height: 16),
          _label('About the copilot', optional: true),
          TextField(
            controller: _about,
            focusNode: _aboutFocus,
            minLines: 8,
            maxLines: 14,
            style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.5, color: c.gray900),
            decoration: copilotFieldDecoration(
              context,
              '# Who you are\n\nWhat this copilot is for, how it should behave, and anything it must never do.',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Written first-person, in Markdown. It is what the copilot shows on its card and what it works from in every conversation.',
            style: TextStyle(fontSize: 11, height: 1.4, color: c.gray400),
          ),
        ] else ...[
          _label('Your name'),
          TextField(
            controller: _yourName,
            style: field,
            decoration: copilotFieldDecoration(context, 'What should it call you?'),
          ),
          const SizedBox(height: 16),
          _label('About you', optional: true),
          TextField(
            controller: _aboutYou,
            minLines: 5,
            maxLines: 10,
            style: field.copyWith(height: 1.5),
            decoration: copilotFieldDecoration(
              context,
              'What do you sell, and to whom? How do you like work presented? What should it never do without asking?\n\nThe more it knows, the less you repeat yourself.',
            ),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: c.gray100),
          const SizedBox(height: 16),
          Text(
            'Things ${cp.name} has learned about you:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray900),
          ),
          const SizedBox(height: 8),
          // ⚠️ Never seeded — a remembered "fact" the user never said is the
          // one mock they would have to argue with.
          Text('No memories saved yet.', style: TextStyle(fontSize: 13, color: c.gray500)),
          const SizedBox(height: 12),
          Text(
            'Your name and profile are held for this session — memory is stored by the Copilot backend.',
            style: TextStyle(fontSize: 11, height: 1.4, color: c.gray400),
          ),
        ],
      ],
    );
  }
}

// ── Channels ────────────────────────────────────────────────────────────────

/// Every place this copilot can be reached from outside the app. ⚠️ No
/// "browser extension" row — Creative Klux doesn't ship one.
class ChannelsPanel extends StatelessWidget {
  const ChannelsPanel({super.key, required this.onSelect});
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        for (final (i, ch) in copilotChannels.indexed)
          Container(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 16, bottom: 16),
            decoration: BoxDecoration(
              border: i == copilotChannels.length - 1 ? null : Border(bottom: BorderSide(color: c.gray100)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(color: ch.tint, shape: BoxShape.circle),
                  child: Icon(ch.icon, size: 14, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ch.short,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                      ),
                      const SizedBox(height: 2),
                      Text(ch.blurb, style: TextStyle(fontSize: 13, height: 1.5, color: c.gray500)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                GhostButton(label: 'Connect', onTap: () => onSelect(ch.id)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Where the deep links point when the response carries `link_code` but not
/// the `channels` block (useChannelLinks.js) — the block wins when present.
const _whatsAppNumber = '14155238886';
const _telegramBot = 'creativekluxbot';

/// "Connect to WhatsApp" — one view for every channel (ChannelConnectView.jsx).
///
/// One shared bot / number serves every copilot: the user sends `LINK <code>`
/// once and that chat is bound to this copilot. ⚠️ THE CODE IS A SECRET.
///
/// The links are fetched from `GET copilots/{id}` each time — the code rotates
/// with the copilot, and a stale one links nobody.
class ChannelConnectView extends StatefulWidget {
  const ChannelConnectView({super.key, required this.channel, required this.copilot, required this.store});
  final CopilotChannel channel;
  final Copilot copilot;
  final CopilotStore store;

  @override
  State<ChannelConnectView> createState() => _ChannelConnectViewState();
}

class _ChannelConnectViewState extends State<ChannelConnectView> {
  Map<String, dynamic>? _links;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The server's link block, else one built from the record's code.
  static Map<String, dynamic>? _linksFrom(dynamic payload) {
    if (payload is! Map) return null;
    for (final b in [payload['channels'], payload['data'] is Map ? payload['data']['channels'] : null]) {
      if (b is Map && b['link_code'] != null) return Map<String, dynamic>.from(b);
    }
    final record = payload['data'];
    final code = record is Map ? record['link_code'] : null;
    if (code == null) return null;
    final message = '${record['link_message'] ?? 'LINK $code'}';
    return {
      'link_code': code,
      'link_message': message,
      'whatsapp': 'https://wa.me/$_whatsAppNumber?text=${Uri.encodeComponent(message)}',
      'telegram': 'https://t.me/$_telegramBot?start=${Uri.encodeComponent('$code')}',
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final links = _linksFrom(await widget.store.api.getCopilot(widget.copilot.id));
      if (!mounted) return;
      setState(() {
        _links = links;
        _error = links == null ? 'This copilot has no link code yet.' : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is CopilotFailure ? e.detail : 'Could not load the link for this copilot.');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ch = widget.channel;
    final href = '${_links?[ch.id] ?? ''}';
    // The sandbox join goes FIRST — until it is sent, the test number drops
    // everything else, LINK message included.
    final steps = [
      if (ch.joinPhrase != null)
        ChannelStep(
          'Join the test number',
          'Before anything else, send “${ch.joinPhrase}” in the chat. Until you do, WhatsApp silently drops your messages.',
        ),
      ...ch.steps,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChannelPreview(channel: ch, copilot: widget.copilot),
        const SizedBox(height: 18),
        if (_loading)
          Container(
            height: 66,
            decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(12)),
          )
        else if (_error != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: c.redTint, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Expanded(
                  child: Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.red600)),
                ),
                TextButton(
                  onPressed: _load,
                  child: const Text(
                    'Try again',
                    style: TextStyle(fontSize: 13, color: AppColors.red600, decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          )
        else ...[
          CopyField(
            label: 'Your link message',
            value: '${_links?['link_message'] ?? ''}',
            hint: "Anyone with this code can chat with this copilot and use your brand's connected accounts. Keep it to yourself.",
          ),
          if (href.isNotEmpty) ...[const SizedBox(height: 14), _ChannelQr(href: href, channel: ch.short)],
        ],
        const SizedBox(height: 18),
        for (final (i, s) in steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    '${i + 1}.',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.gray500),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                      ),
                      const SizedBox(height: 2),
                      Text(s.body, style: TextStyle(fontSize: 13, height: 1.5, color: c.gray500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.gray50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.gray200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.shieldCheck, size: 16, color: c.gray500),
              const SizedBox(width: 10),
              Expanded(
                child: Text(channelPrivacyNote, style: TextStyle(fontSize: 13, height: 1.5, color: c.gray500)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: InkButton(
            label: ch.cta,
            icon: LucideIcons.externalLink,
            onTap: href.isEmpty
                ? null
                : () => launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication).then((ok) {
                    if (!ok) Toast.error("Couldn't open ${ch.short}");
                  }),
          ),
        ),
      ],
    );
  }
}

/// The picture at the top of a channel's connect view: a glimpse of the
/// destination — the copilot's own description as the ask, and its reply.
///
/// The web pairs this preview with a QR code; here the QR sits under the link
/// message instead ([_ChannelQr]), and the button below still opens the app
/// directly for the common case of WhatsApp / Telegram on this same phone.
class _ChannelPreview extends StatelessWidget {
  const _ChannelPreview({required this.channel, required this.copilot});
  final CopilotChannel channel;
  final Copilot copilot;

  /// What the copilot says back, in every preview.
  static const _reply = "On it — I'll report back right here.";

  @override
  Widget build(BuildContext context) {
    final ask = copilot.description.isNotEmpty ? copilot.description : 'Hi ${copilot.name}!';
    return Container(
      height: 200,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: channel.hero, borderRadius: BorderRadius.circular(14)),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: 240,
          margin: const EdgeInsets.only(top: 20),
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 8))],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  children: [
                    const Icon(LucideIcons.chevronLeft, size: 12, color: Color(0xFF99A1AF)),
                    const SizedBox(width: 6),
                    CopilotAvatar(copilot: copilot, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        copilot.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Tw.gray900),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: channel.surface,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Today',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 8, color: Color(0xFF6A7282)),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FractionallySizedBox(
                          widthFactor: 0.88,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(color: channel.bubble, borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              ask,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, height: 1.35, color: Tw.gray900),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.88,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                          child: const Text(
                            _reply,
                            style: TextStyle(fontSize: 10, height: 1.35, color: Color(0xFF364153)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Security ────────────────────────────────────────────────────────────────

/// What this copilot may do on its own. Both destructive permissions default
/// OFF and secret detection ON. ⚠️ Held locally until the backend enforces them.
class SecurityPanel extends StatefulWidget {
  const SecurityPanel({super.key, required this.copilot});
  final Copilot copilot;

  @override
  State<SecurityPanel> createState() => _SecurityPanelState();
}

class _SecurityPanelState extends State<SecurityPanel> {
  bool _updateData = false;
  bool _deleteData = false;
  bool _detectSecrets = true;

  void _pending() => Toast.info('Permissions save with the Copilot backend.');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Copilot permissions',
          description: 'Control what ${widget.copilot.name} can do on its own, without asking for your approval first.',
          children: [
            SettingsRow(
              title: 'Update data',
              description: 'Edit your designs, kits and scheduled posts without asking first',
              child: SettingsToggle(
                value: _updateData,
                onChanged: (v) {
                  setState(() => _updateData = v);
                  _pending();
                },
              ),
            ),
            SettingsRow(
              title: 'Delete data',
              description: 'Remove designs, assets and posts without asking first',
              child: SettingsToggle(
                value: _deleteData,
                onChanged: (v) {
                  setState(() => _deleteData = v);
                  _pending();
                },
              ),
            ),
            SettingsRow(
              title: 'Auto-detect secrets in messages',
              description: 'Automatically detect API keys and tokens you paste, save them securely, and hide the raw value from the copilot.',
              child: SettingsToggle(
                value: _detectSecrets,
                onChanged: (v) {
                  setState(() => _detectSecrets = v);
                  _pending();
                },
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Secrets',
          description: "Environment variables available to this copilot's backend functions.",
          last: true,
          action: GhostButton(label: 'Add', icon: LucideIcons.plus, onTap: () => notifyPending('Secrets')),
          children: const [
            EmptyNote('No secrets yet.\nValues are write-only — you can replace one, never read it back.'),
          ],
        ),
      ],
    );
  }
}

// ── Developer ───────────────────────────────────────────────────────────────

/// The API reference for driving this copilot from your own code.
///
/// ⚠️ NO KEY IS FABRICATED — a string labelled "Your API key" gets pasted
/// into a repo and treated as one. The base URL and the example ARE real.
class DeveloperPanel extends StatelessWidget {
  const DeveloperPanel({super.key, required this.copilot});
  final Copilot copilot;

  /// The shape a key will take, masked — no entropy in it.
  static const _maskedKey = 'ck_live_••••••••••••••••••••••••';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final baseUrl = '${AppConfig.apiBaseUrl}/copilots/${copilot.id}';
    final example =
        'curl $baseUrl/messages \\\n'
        '  -H "Authorization: Bearer \$CREATIVE_KLUX_API_KEY" \\\n'
        '  -H "Content-Type: application/json" \\\n'
        '  -d \'{"message": "${copilot.description}"}\'';

    void copy(String value, String what) {
      Clipboard.setData(ClipboardData(text: value));
      Toast.success('$what copied');
    }

    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        t,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
      ),
    );

    return SettingsSection(
      title: 'API reference',
      description: 'Connect this copilot to your own code or product.',
      last: true,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label('Your API key'),
            const MonoBox(_maskedKey, muted: true),
            const SizedBox(height: 8),
            Row(
              children: [
                GhostButton(label: 'Copy', icon: LucideIcons.copy, onTap: () => notifyPending('API keys')),
                const SizedBox(width: 8),
                GhostButton(label: 'Regenerate', icon: LucideIcons.refreshCw, onTap: () => notifyPending('API keys')),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Keys are minted by the Copilot backend and shown once. Nothing is issued yet, so this one is a placeholder.',
              style: TextStyle(fontSize: 11, height: 1.4, color: c.gray400),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label('Base URL'),
            Row(
              children: [
                Expanded(child: MonoBox(baseUrl)),
                const SizedBox(width: 8),
                GhostButton(label: 'Copy', icon: LucideIcons.copy, onTap: () => copy(baseUrl, 'Base URL')),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label('Quick example'),
            // Scrolls sideways rather than wrapping: a wrapped curl line pasted
            // into a terminal is a broken curl line.
            Container(
              decoration: BoxDecoration(
                color: c.gray50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.gray200),
              ),
              child: Stack(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(14, 14, 52, 14),
                    child: Text(
                      example,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.6, color: c.gray700),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: IconButton(
                      tooltip: 'Copy example',
                      onPressed: () => copy(example, 'Example'),
                      icon: Icon(LucideIcons.copy, size: 15, color: c.gray500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Docs have no home yet — it says so rather than linking elsewhere.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => notifyPending('The API documentation'),
            iconAlignment: IconAlignment.end,
            icon: Icon(LucideIcons.externalLink, size: 14, color: c.gray900),
            label: Text(
              'View full API documentation',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: c.gray900,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The channel link as a QR code (the web's ChannelConnectView QR) — for when
/// WhatsApp / Telegram lives on ANOTHER phone than this one. Always black on
/// white, in both themes: scanners read dark-on-light most reliably.
class _ChannelQr extends StatelessWidget {
  const _ChannelQr({required this.href, required this.channel});

  final String href;
  final String channel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: QrImageView(
              data: href,
              size: 112,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '$channel on another phone? Scan this with its camera — it opens $channel with your link ready.',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: c.gray500),
            ),
          ),
        ],
      ),
    );
  }
}
