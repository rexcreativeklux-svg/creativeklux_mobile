import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/auth_controller.dart';
import '../shell/widgets/app_top_bar.dart';
import 'magic_composer.dart';
import 'magic_history.dart';
import 'magic_lattice.dart';
import 'magic_studio_types.dart';
import 'magic_templates.dart';

/// Port of `magic-studio/[tool]/page.jsx`: one Magic Studio tool.
///
///   Templates · Create · History   ← which canvas the lattice shows
///   ┌──────────────────────────┐
///   │ lattice / template grid  │
///   └──────────────────────────┘
///   [ composer — always docked ]
///
/// The web lists the tools in a secondary sidebar; on a phone the tool name in
/// the header opens a picker sheet instead.
class MagicStudioScreen extends StatelessWidget {
  const MagicStudioScreen({super.key, required this.slug});

  final String? slug;

  @override
  Widget build(BuildContext context) {
    final tool = magicToolBySlug(slug) ?? firstMagicTool;
    // Keyed on the tool so history, options and the typed prompt all reset
    // together when switching tools, as the web remounts on navigation.
    return _MagicToolView(key: ValueKey(tool.id), tool: tool);
  }
}

enum _View { templates, create, history }

class _MagicToolView extends StatefulWidget {
  const _MagicToolView({super.key, required this.tool});

  final MagicStudioTool tool;

  @override
  State<_MagicToolView> createState() => _MagicToolViewState();
}

class _MagicToolViewState extends State<_MagicToolView> {
  MagicStudioTool get tool => widget.tool;

  late final bool _templated = magicToolHasTemplates(tool.id);
  late final Future<List<MagicTemplate>>? _templates = _templated ? loadMagicTemplates(tool.id) : null;

  // Templates first where the tool has examples (a blank box is hardest to
  // write into on a first visit); otherwise Create.
  late _View _view = _templated ? _View.templates : _View.create;

  late final MagicHistoryController _history = MagicHistoryController(
    context.read<AuthController>().api,
    tool.backend ? tool.id : null,
  );

  MagicComposerStatus _status = const MagicComposerStatus();
  MagicRefill? _refill;
  bool _waitHidden = false;

  /// Results of this visit that history hasn't caught up with yet.
  final _sessionItems = <MagicItem>[];

  /// History ids present when the first load settled — what came AFTER is
  /// what you made in this sitting, and that is the Create canvas.
  Set<String>? _baseline;

  @override
  void initState() {
    super.initState();
    _history.addListener(_onHistory);
    _history.refresh();
  }

  @override
  void dispose() {
    _history.removeListener(_onHistory);
    _history.dispose();
    super.dispose();
  }

  void _onHistory() {
    if (!mounted) return;
    setState(() {
      // Snapped after the first load, not at mount: items are empty while it
      // is in flight, and a mount-time baseline would show the whole backlog
      // as "just made".
      if (_baseline == null && !_history.loading) _baseline = {for (final i in _history.items) i.id};
    });
  }

  void _onStatus(MagicComposerStatus s) {
    setState(() {
      if (s.generating && !_status.generating) {
        _waitHidden = false;
        // The wait tile and the result both live on Create.
        if (_view == _View.templates) _view = _View.create;
      }
      _status = s;
    });
  }

  void _onResult(List<MagicItem> items) {
    if (items.isEmpty) return;
    setState(() => _sessionItems.insertAll(0, items));
  }

  List<MagicItem> get _visible {
    final historyIds = {for (final i in _history.items) i.id};
    // A session result that history now carries under the same id is drawn once.
    final session = [
      for (final i in _sessionItems)
        if (!historyIds.contains(i.id)) i,
    ];
    if (_view == _View.create) {
      final baseline = _baseline;
      final fresh = baseline == null
          ? <MagicItem>[]
          : [
              for (final i in _history.items)
                if (!baseline.contains(i.id)) i,
            ];
      return [...session, ...fresh];
    }
    return [...session, ..._history.items];
  }

  void _pickTool() {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) {
        final c = sheet.colors;
        final groups = <String?, List<MagicStudioTool>>{};
        for (final t in magicStudioTools.where((t) => t.nav)) {
          groups.putIfAbsent(t.group, () => []).add(t);
        }
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          builder: (_, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Magic Studio',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.gray900),
                ),
              ),
              for (final MapEntry(key: group, value: tools) in groups.entries) ...[
                if (group != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      group.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w600,
                        color: c.gray400,
                      ),
                    ),
                  ),
                for (final t in tools)
                  ListTile(
                    leading: Icon(t.icon, size: 19, color: t.id == tool.id ? AppColors.blue600 : c.gray600),
                    title: Text(
                      t.label,
                      style: TextStyle(
                        fontWeight: t.id == tool.id ? FontWeight.w600 : FontWeight.w400,
                        color: t.id == tool.id ? AppColors.blue600 : c.gray900,
                      ),
                    ),
                    trailing: t.id == tool.id ? Icon(LucideIcons.check, size: 17, color: AppColors.blue600) : null,
                    onTap: () {
                      Navigator.pop(sheet);
                      if (t.id != tool.id) context.go(t.path);
                    },
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pending = _history.pending;
    // Runs started elsewhere (or before a reload) get the same wait tiles.
    final resumed = !_status.generating && pending.isNotEmpty;

    final Widget sliver;
    if (_view == _View.templates) {
      sliver = FutureBuilder<List<MagicTemplate>>(
        future: _templates,
        builder: (context, snap) => snap.hasData
            ? MagicTemplateGallery(
                templates: snap.data!,
                onUse: (t) => setState(() {
                  _refill = t.toRefill();
                  _view = _View.create;
                }),
                bottomPadding: 16,
              )
            : const MagicTemplateGallerySkeleton(bottomPadding: 16),
      );
    } else {
      final creating = _view == _View.create;
      sliver = MagicLattice(
        items: _visible,
        loading: !creating && _history.loading,
        generating: (_status.generating || resumed) && !_waitHidden,
        generatingCount: resumed ? pending.length : _status.count,
        generatingProgress: resumed ? null : _status.progress,
        generatingPrompt: resumed ? pending.first.prompt : _status.prompt,
        generatingType: resumed ? (pending.first.type ?? 'image') : _status.resultType,
        generatingLabel: tool.working,
        onDismissGenerating: () => setState(() => _waitHidden = true),
        onEditGenerating: () => setState(
          () => _refill = MagicRefill(
            nonce: DateTime.now().microsecondsSinceEpoch,
            text: (resumed ? pending.first.prompt : _status.prompt) ?? '',
          ),
        ),
        onDelete: (item) {
          _sessionItems.removeWhere((i) => i.id == item.id);
          _history.remove(item);
        },
        removingId: _history.removingId,
        emptyHint: creating
            ? 'Describe what you want below. Everything you make lands here.'
            : tool.emptyHint ?? 'Everything you make with ${tool.short} lands here.',
        publishable: tool.publish,
        bottomPadding: 16,
      );
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Magic Studio'),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(bottom: BorderSide(color: c.gray200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickTool,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        children: [
                          Icon(tool.icon, size: 17, color: AppColors.blue600),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              tool.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(LucideIcons.chevronDown, size: 15, color: c.gray500),
                        ],
                      ),
                    ),
                  ),
                ),
                _ViewSwitch(
                  view: _view,
                  templated: _templated,
                  historyEnabled: tool.backend,
                  loading: _history.loading,
                  onChanged: (v) {
                    setState(() => _view = v);
                    // History doubles as its own reload, like the web.
                    if (v == _View.history) _history.refresh();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: c.page,
              child: RefreshIndicator(
                onRefresh: () => _history.refresh(),
                notificationPredicate: (_) => _view != _View.templates,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [sliver],
                ),
              ),
            ),
          ),
          MagicComposer(
            key: ValueKey('composer-${tool.id}'),
            tool: tool,
            refill: _refill,
            onStatus: _onStatus,
            onResult: _onResult,
            onRunFinished: () => _history.refresh(quiet: true),
          ),
        ],
      ),
    );
  }
}

/// Templates · Create · History as a compact segmented control.
class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({
    required this.view,
    required this.templated,
    required this.historyEnabled,
    required this.loading,
    required this.onChanged,
  });

  final _View view;
  final bool templated;
  final bool historyEnabled;
  final bool loading;
  final ValueChanged<_View> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget seg(_View v, IconData icon, String tooltip, {bool enabled = true, bool spinning = false}) {
      final on = view == v;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: enabled ? () => onChanged(v) : null,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 38,
            height: 32,
            decoration: BoxDecoration(
              color: on ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: on ? const [BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1))] : null,
            ),
            child: Center(
              child: spinning
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(icon, size: 16, color: !enabled ? c.gray300 : (on ? c.gray900 : c.gray500)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (templated) seg(_View.templates, LucideIcons.layoutTemplate, 'Templates — pick one to start from'),
          seg(_View.create, LucideIcons.sparkles, 'Create — just what you make from here'),
          seg(
            _View.history,
            LucideIcons.history,
            'History — everything made with this tool',
            enabled: historyEnabled,
            spinning: loading && view == _View.history,
          ),
        ],
      ),
    );
  }
}
