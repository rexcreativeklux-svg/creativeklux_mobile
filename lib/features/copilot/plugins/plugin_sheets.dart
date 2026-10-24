import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart' show AppColorsContext;
import '../../../core/ui/toast.dart';
import '../data/copilot_data.dart';
import '../widgets/copilot_widgets.dart';
import 'brand_integrations.dart';
import 'plugins_screen.dart' show ConnectorCard;

// The Plugins screen's dialogs, as sheets: Connectors (ConnectorsModal.jsx),
// Request a connector (RequestConnectorModal.jsx) and Upload skill
// (UploadSkillModal.jsx).

/// The browse-everything sheet behind BOTH "Add Connector" and "Browse all" —
/// the same request, so the same catalog. Apps / MCP tabs, search, category,
/// sort. Search, filter and sort are real: they only touch the catalog here.
///
/// "Request a connector" REPLACES this sheet rather than stacking on it.
Future<void> showConnectorsSheet(
  BuildContext context,
  BrandIntegrations integrations, {
  required VoidCallback onRequest,
}) async {
  final request = await showCopilotSheet<bool>(
    context,
    title: 'Connectors',
    fullHeight: true,
    builder: (ctx) => _ConnectorsBody(integrations: integrations, onRequest: () => Navigator.pop(ctx, true)),
  );
  if (request == true) onRequest();
}

class _ConnectorsBody extends StatefulWidget {
  const _ConnectorsBody({required this.integrations, required this.onRequest});
  final BrandIntegrations integrations;
  final VoidCallback onRequest;

  @override
  State<_ConnectorsBody> createState() => _ConnectorsBodyState();
}

class _ConnectorsBodyState extends State<_ConnectorsBody> {
  String _tab = 'Apps';
  String _category = 'All';
  String _sort = connectorSorts.first;
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
    final visible = sortConnectors([
      for (final p in platformsById.values)
        if ((_category == 'All' || p.category == _category) &&
            (term.isEmpty || p.name.toLowerCase().contains(term) || p.description.toLowerCase().contains(term)))
          p,
    ], _sort);

    return ListenableBuilder(
      listenable: widget.integrations,
      builder: (context, _) => ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          Text(
            'Connect your copilot to the apps and services you already use.',
            style: TextStyle(fontSize: 13.5, color: c.gray500),
          ),
          const SizedBox(height: 14),
          UnderlineTabs(tabs: const ['Apps', 'MCP'], value: _tab, onChanged: (t) => setState(() => _tab = t)),
          const SizedBox(height: 14),
          if (_tab == 'Apps') ...[
            CopilotSearchField(controller: _query, hint: 'Search connectors...', onChanged: (_) => setState(() {})),
            const SizedBox(height: 8),
            Row(
              children: [
                DropdownTrigger(
                  label: _category,
                  onTap: () => showChoiceSheet(
                    context,
                    items: [
                      for (final cat in connectorCategories)
                        ChoiceItem(cat, selected: cat == _category, onTap: () => setState(() => _category = cat)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                DropdownTrigger(
                  label: _sort,
                  icon: LucideIcons.arrowUpDown,
                  onTap: () => showChoiceSheet(
                    context,
                    heading: 'Sort by',
                    items: [
                      for (final s in connectorSorts)
                        ChoiceItem(s, selected: s == _sort, onTap: () => setState(() => _sort = s)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'No connectors match “${_query.text}”.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: c.gray500),
                ),
              )
            else
              for (final p in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ConnectorCard(platform: p, integrations: widget.integrations, stacked: true),
                ),
            const SizedBox(height: 10),
            Divider(height: 1, color: c.gray200),
            const SizedBox(height: 12),
            // The end of the list, not an action on the sheet.
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text("Can't find what you need? ", style: TextStyle(fontSize: 13.5, color: c.gray500)),
                GestureDetector(
                  onTap: widget.onRequest,
                  child: Text(
                    'Request a connector',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: c.gray900,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ] else
            // Empty by construction: an MCP server is something the USER runs
            // and points the copilot at, so there is no catalog to seed.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(10)),
                    child: Icon(LucideIcons.plug, size: 17, color: c.gray500),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No MCP servers yet',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.gray900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Point your copilot at an MCP server to give it tools this catalog doesn't cover.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, height: 1.5, color: c.gray500),
                  ),
                  const SizedBox(height: 16),
                  InkButton(label: 'Add MCP server', onTap: () => notifyPending('MCP servers')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Request a connector". ⚠️ UI ONLY — Submit reports the click and closes;
/// the form still validates, because a request with no service name isn't one.
Future<void> showRequestConnectorSheet(BuildContext context) =>
    showCopilotSheet<void>(context, title: 'Request a connector', builder: (ctx) => const _RequestBody());

class _RequestBody extends StatefulWidget {
  const _RequestBody();

  @override
  State<_RequestBody> createState() => _RequestBodyState();
}

class _RequestBodyState extends State<_RequestBody> {
  final _service = TextEditingController();
  final _docs = TextEditingController();
  final _usage = TextEditingController();

  @override
  void dispose() {
    _service.dispose();
    _docs.dispose();
    _usage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget label(String t, {bool optional = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: t,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
          children: [
            if (optional)
              TextSpan(
                text: ' (optional)',
                style: TextStyle(color: c.gray400),
              ),
          ],
        ),
      ),
    );
    final field = TextStyle(fontSize: 14, color: c.gray900);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tell us what you want to connect and how you plan to use it.',
              style: TextStyle(fontSize: 13.5, color: c.gray500),
            ),
            const SizedBox(height: 16),
            label('Service name'),
            TextField(
              controller: _service,
              style: field,
              onChanged: (_) => setState(() {}),
              decoration: copilotFieldDecoration(context, 'For example, Canva'),
            ),
            const SizedBox(height: 14),
            label('Website or API documentation', optional: true),
            TextField(
              controller: _docs,
              style: field,
              keyboardType: TextInputType.url,
              decoration: copilotFieldDecoration(context, 'https://...'),
            ),
            const SizedBox(height: 14),
            label('What should your copilot do with it?'),
            TextField(
              controller: _usage,
              style: field,
              minLines: 4,
              maxLines: 6,
              decoration: copilotFieldDecoration(context, 'Describe the data or actions your copilot needs.'),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: c.gray500)),
                ),
                const SizedBox(width: 8),
                // Disabled rather than hidden: the action exists, and what's
                // missing is right above it.
                InkButton(
                  label: 'Submit request',
                  onTap: _service.text.trim().isEmpty
                      ? null
                      : () {
                          notifyPending('Connector requests');
                          Navigator.pop(context);
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Upload skill file". ⚠️ THE FILE NEVER LEAVES THE PHONE — there is no
/// endpoint yet, so after picking, the upload reports that the backend owes
/// one, exactly as the web does. The chosen file's name is echoed back so the
/// user can see the pick landed (UploadSkillModal.jsx `take`).
Future<void> showUploadSkillSheet(BuildContext context, {required VoidCallback onAskChat}) async {
  final askChat = await showCopilotSheet<bool>(
    context,
    title: 'Upload skill',
    builder: (ctx) {
      final c = ctx.colors;
      Widget code(String t) => Text(
        t,
        style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: c.gray900),
      );
      final body = TextStyle(fontSize: 13, height: 1.5, color: c.gray500);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SkillDropZone(),
              const SizedBox(height: 20),
              Text(
                'File requirements',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
              ),
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('•  A ', style: body),
                  code('.zip'),
                  Text(' or ', style: body),
                  code('.skill'),
                  Text(' file with a ', style: body),
                  code('SKILL.md'),
                  Text(' at the root level', style: body),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('•  ', style: body),
                  code('SKILL.md'),
                  Text(
                    ' starts with YAML frontmatter declaring the name and description, followed by the skill instructions in markdown',
                    style: body,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Read more about ', style: body),
                  GestureDetector(
                    onTap: () => notifyPending('The skill-authoring guide'),
                    child: Text(
                      'creating skills',
                      style: body.copyWith(
                        color: c.gray900,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  Text(' or ', style: body),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, true),
                    child: Text(
                      'ask the chat',
                      style: body.copyWith(
                        color: c.gray900,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  Text('.', style: body),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  if (askChat == true) onAskChat();
}

/// The upload zone: opens the phone's file chooser for a `.zip` / `.skill`.
class _SkillDropZone extends StatefulWidget {
  const _SkillDropZone();

  @override
  State<_SkillDropZone> createState() => _SkillDropZoneState();
}

class _SkillDropZoneState extends State<_SkillDropZone> {
  String? _fileName;

  Future<void> _pick() async {
    // FileType.any + our own check: Android has no MIME type for `.skill`,
    // so an extension filter would grey every skill file out.
    final file = (await FilePicker.pickFiles(type: FileType.any)).firstOrNull;
    if (file == null || !mounted) return;
    final name = file.name.toLowerCase();
    if (!name.endsWith('.zip') && !name.endsWith('.skill')) {
      Toast.error('Choose a .zip or .skill file');
      return;
    }
    setState(() => _fileName = file.name);
    notifyPending('Uploading a skill');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: _pick,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: c.gray100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.gray300, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.fileText, size: 24, color: c.gray400),
            const SizedBox(height: 10),
            if (_fileName == null)
              Text('Tap to upload', style: TextStyle(fontSize: 13.5, color: c.gray500))
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _fileName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray900),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove file',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _fileName = null),
                      icon: Icon(LucideIcons.x, size: 16, color: c.gray500),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
