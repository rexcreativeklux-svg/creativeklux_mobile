import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/design/design_renderer.dart';
import '../../core/design/grids.dart';
import '../../core/design/js_values.dart';
import '../../core/design/table_utils.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import '../creatives/creatives_api.dart';
import '../publish/publish_sheet.dart';
import 'design_editor_controller.dart';
import 'design_stage.dart';
import 'editor_api.dart';
import 'editor_context_bar.dart';
import 'editor_draw_panel.dart';
import 'editor_extras.dart';
import 'editor_klux_panel.dart';
import 'element_libraries/element_sheets.dart';
import 'magic_panel/magic_media_panel.dart';
import 'editor_panels.dart';
import 'editor_sheets.dart';
import 'editor_templates_panel.dart';
import 'editor_uploads_panel.dart';

/// `/design/:id` — port of the web's `design/[id]/page.jsx` + `DesignEditor.jsx`.
///
/// Ported (phase 1): load / save / autosave, rename, undo / redo, the stage
/// (move, scale, crop, rotate, inline text editing, pinch-zoom), the
/// contextual toolbar, and the Text, Elements (shapes), Uploads, Brand,
/// Layers and Resize panels; download to the gallery and Publish.
///
/// Not yet: the Creatives, Tools, Klux AI and Magic Studio panels, text
/// effects / templates, image editing (adjust, filters, AI tools), video,
/// animation, tables / charts / grids / frames inserts, multi-select, grouping,
/// copy-paste, comments, collaborators and the timer.
class DesignEditorScreen extends StatefulWidget {
  const DesignEditorScreen({super.key, required this.designId, this.initialDesign, this.initialPanel});

  final int designId;

  /// `?panel=klux` — "Edit with AI" opens Klux AI and starts a redesign.
  final String? initialPanel;

  /// Skips the fetch — for previews and tests.
  final EditorDesign? initialDesign;

  @override
  State<DesignEditorScreen> createState() => _DesignEditorScreenState();
}

enum _Panel { templates, text, elements, uploads, draw, brand, klux, magic, layers, resize }

class _DesignEditorScreenState extends State<DesignEditorScreen> {
  late final EditorApi _api = EditorApi(context.read<AuthController>().api);
  final _scene = DesignScene();
  final _previews = DesignScene();
  final _stageKey = GlobalKey<DesignStageState>();

  DesignEditorController? _c;
  EditorInserts? _insert;
  bool _loading = true;
  bool _saving = false;
  String? _editingId;
  _Panel? _panel;
  Timer? _autosave;
  late bool _kluxSeed = widget.initialPanel == 'klux';
  bool _timerOpen = false;
  DrawTool _drawTool = const DrawTool(type: 'pen', color: '#111827', size: 6, opacity: 1);

  @override
  void initState() {
    super.initState();
    if (_kluxSeed) _panel = _Panel.klux;
    _load();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _c?.removeListener(_onChange);
    _c?.dispose();
    _scene.dispose();
    _previews.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final design = widget.initialDesign ?? await _api.load(widget.designId);
    if (!mounted) return;
    if (design == null) {
      setState(() => _loading = false);
      return;
    }
    final c = DesignEditorController(
      designId: design.id,
      name: design.name,
      canvas: design.canvas,
      elements: design.elements,
      notes: design.notes,
      raw: design.raw,
    );
    c.addListener(_onChange);
    _scene.prepare(c.canvas, c.elements);
    setState(() {
      _c = c;
      _insert = EditorInserts(c);
      _loading = false;
    });
    // Autosave every 15s while there are unsaved changes (web behaviour)…
    _autosave = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_c?.dirty == true && !_saving && _editingId == null) _save(silent: true);
    });
    // …and once on open, which backfills a thumbnail for designs saved before
    // saves carried one.
    _save(silent: true);
  }

  void _onChange() {
    final c = _c!;
    _scene.prepare(c.canvas, c.elements);
    // Leaving text edit mode if its element went away (undo, delete).
    if (_editingId != null && c.byId(_editingId!) == null) setState(() => _editingId = null);
    setState(() {});
  }

  // ── Saving ─────────────────────────────────────────────────────────────────

  /// Every save carries a freshly painted preview so My Creations shows what
  /// opens here. Best-effort: a preview that can't be painted is left out
  /// rather than costing the edits the same request carries. Capped at 1080px
  /// on the long side — it's a list thumbnail, and phone uploads are slow.
  Future<bool> _save({bool silent = false}) async {
    final c = _c;
    if (c == null || _saving) return false;
    setState(() => _saving = true);
    try {
      String? thumbnail;
      try {
        final long = math.max(c.canvasWidth, c.canvasHeight);
        final png = await renderDesignPng(c.canvas, c.elements, pixelRatio: math.min(1, 1080 / long));
        thumbnail = 'data:image/png;base64,${base64Encode(png)}';
      } catch (_) {}
      final res = await _api.save(c.designId, name: c.name, canvasJson: c.toCanvasJson(), thumbnail: thumbnail);
      if (!res.ok) throw Exception(res.message.isNotEmpty ? res.message : 'Save failed');
      c.markSaved();
      if (!silent) Toast.success('Design saved');
      return true;
    } catch (err) {
      if (!silent) Toast.error('Could not save design', description: '$err'.replaceFirst('Exception: ', ''));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _download() async {
    final c = _c!;
    Toast.info('Preparing your download…');
    try {
      final png = await renderDesignPng(c.canvas, c.elements);
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImageBytes(
        png,
        name: '${c.name.replaceAll(RegExp(r'\s+'), '-')}-${DateTime.now().millisecondsSinceEpoch}',
      );
      Toast.success('Saved to your photo gallery');
    } catch (_) {
      Toast.error("Couldn't download the design");
    }
  }

  void _publish() {
    final c = _c!;
    final raw = c.raw;
    showPublishSheet(
      context,
      PublishCreative(
        name: c.name,
        category: '${raw['type'] ?? 'all'}',
        copy: raw['copy'] is Map ? Map<String, dynamic>.from(raw['copy'] as Map) : const {},
        canvas: c.canvas,
        elements: c.elements,
      ),
    );
  }

  Future<void> _rename() async {
    final c = _c!;
    final ctrl = TextEditingController(text: c.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.surface,
        title: const Text('Rename design'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Rename')),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null) c.rename(name);
  }

  // ── Leaving ────────────────────────────────────────────────────────────────

  Future<void> _leave() async {
    final c = _c;
    if (c != null && c.dirty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.colors.surface,
          title: const Text('Save your changes?'),
          content: const Text('You have edits that haven’t been saved yet.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Leave without saving')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save & leave')),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'save' && !await _save()) return;
    }
    if (!mounted) return;
    context.canPop() ? context.pop() : context.go('/creatives');
  }

  // ── Text editing ───────────────────────────────────────────────────────────

  void _startEdit(String id) {
    _c?.select(id);
    setState(() => _editingId = id);
  }

  void _commitText(String id, String text) {
    final el = _c?.byId(id);
    if (el != null && '${el['content'] ?? el['text'] ?? ''}' != text) {
      _c!.updateElement(id, {
        'content': text,
        'text': text,
        if (truthy(el['sticky']) && el['autoFit'] != false) 'fontSize': _fitStickyFont(el, text),
      });
    }
    setState(() => _editingId = null);
  }

  /// Tapping a selected table opens the cell under the finger; a grid, that
  /// cell's picture; a frame, its picture.
  void _tapAgain(String id, Offset local) {
    final el = _c?.byId(id);
    if (el == null) return;
    switch (el['type']) {
      case 'table':
        final cell = tableCellAt(el, local);
        if (cell != null) showTableCellSheet(context, _c!, cell.$1, cell.$2);
      case 'grid':
        final i = gridCellAt(el, local);
        if (i != null) showFrameImageSheet(context, _c!, cellIndex: i);
      case 'frame':
        showFrameImageSheet(context, _c!);
      case 'chart':
        showChartDataSheet(context, _c!);
    }
  }

  /// A sticky note's type size auto-fits its box: the largest size whose
  /// word-wrapped lines fit inside the padding (the web's `fitFontSize`).
  double _fitStickyFont(Map<String, dynamic> el, String text) {
    final pad = nnNum(el['padding'], 2);
    final maxW = math.max(1.0, orNum(el['width'], 100) - pad * 2);
    final maxH = math.max(1.0, orNum(el['height'], 100) - pad * 2);
    final base = _scene.textStyleFor(el);
    bool fits(double size) {
      final tp = TextPainter(
        text: TextSpan(
          text: text.isEmpty ? ' ' : text,
          style: base.copyWith(fontSize: size, height: 1.3),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxW);
      final ok = tp.height <= maxH && tp.computeLineMetrics().every((l) => l.width <= maxW + 0.5);
      tp.dispose();
      return ok;
    }

    var lo = 6.0, hi = math.max(6.0, maxH);
    for (var i = 0; i < 18; i++) {
      final mid = (lo + hi) / 2;
      if (fits(mid)) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo.floorToDouble();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    if (_loading) {
      return Scaffold(
        backgroundColor: col.gray100,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(strokeWidth: 2.5),
              const SizedBox(height: 14),
              Text('Loading your design', style: TextStyle(color: col.gray500)),
            ],
          ),
        ),
      );
    }
    final c = _c;
    if (c == null) {
      return Scaffold(
        backgroundColor: col.gray100,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.triangleAlert, size: 32, color: AppColors.amber500),
              const SizedBox(height: 10),
              Text('We couldn’t load this design.', style: TextStyle(color: col.gray500)),
              const SizedBox(height: 14),
              FilledButton(onPressed: () => context.go('/creatives'), child: const Text('Back to My Creations')),
            ],
          ),
        ),
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final stageView = DesignStage(
      key: _stageKey,
      controller: c,
      scene: _scene,
      editingId: _editingId,
      onStartEdit: _startEdit,
      onCommitText: _commitText,
      drawTool: _panel == _Panel.draw ? _drawTool : null,
      onTapAgain: _tapAgain,
    );
    // The timer floats over the artboard, out of the way in a corner.
    final stage = Stack(
      children: [
        Positioned.fill(child: stageView),
        if (_timerOpen)
          Positioned(right: 12, bottom: 12, child: EditorTimer(onClose: () => setState(() => _timerOpen = false))),
      ],
    );
    final contextBar = _editingId != null
        ? _editingBar(context)
        : EditorContextBar(
            c: c,
            brand: context.watch<AuthController>().activeBrand,
            brandApi: context.read<AuthController>().brandApi,
            onEditText: _startEdit,
            onFitView: () => _stageKey.currentState?.fit(),
            scene: _scene,
            onPlayAnimation: () => _stageKey.currentState?.playAnimations(),
          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: col.surface,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(context, c),
              Expanded(
                child: wide
                    ? Row(
                        children: [
                          _rail(context, vertical: true),
                          if (_panel != null)
                            Container(
                              width: 300,
                              decoration: BoxDecoration(
                                border: Border(right: BorderSide(color: col.gray200)),
                              ),
                              child: _panelBody(context),
                            ),
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(child: stage),
                                contextBar,
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: stage),
                          contextBar,
                          // A sheet above the rail: enough of a panel to scan a
                          // list while the artboard stays big enough to see the change.
                          if (_panel != null && _editingId == null)
                            SizedBox(height: MediaQuery.sizeOf(context).height * 0.42, child: _panelBody(context)),
                          if (_editingId == null) _rail(context, vertical: false),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editingBar(BuildContext context) => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: context.colors.surface,
      border: Border(top: BorderSide(color: context.colors.gray200)),
    ),
    child: Row(
      children: [
        Icon(LucideIcons.pencil, size: 15, color: context.colors.gray500),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Editing text', style: TextStyle(fontSize: 13, color: context.colors.gray600)),
        ),
        FilledButton(
          onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
          style: FilledButton.styleFrom(backgroundColor: AppColors.blue600),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  Widget _topBar(BuildContext context, DesignEditorController c) {
    final col = context.colors;
    final status = _saving
        ? 'Saving…'
        : c.dirty
        ? 'Unsaved changes'
        : 'All changes saved';
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: col.surface,
        border: Border(bottom: BorderSide(color: col.gray200)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _leave,
            icon: Icon(LucideIcons.arrowLeft, size: 20, color: col.gray700),
          ),
          Expanded(
            child: InkWell(
              onTap: _rename,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: col.gray900),
                    ),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: col.gray400),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Undo',
            onPressed: c.canUndo ? c.undo : null,
            icon: const Icon(LucideIcons.undo2, size: 19),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: c.canRedo ? c.redo : null,
            icon: const Icon(LucideIcons.redo2, size: 19),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            color: col.surface,
            icon: Icon(LucideIcons.ellipsisVertical, size: 19, color: col.gray700),
            onSelected: (v) => switch (v) {
              'save' => _save(),
              'download' => _download(),
              'rename' => _rename(),
              'notes' => showNotesSheet(context, c),
              'people' => showCollaboratorsSheet(context),
              'timer' => setState(() => _timerOpen = !_timerOpen),
              _ => null,
            },
            itemBuilder: (_) => [
              for (final (v, icon, label) in [
                ('save', LucideIcons.save, 'Save now'),
                ('download', LucideIcons.download, 'Download PNG'),
                ('rename', LucideIcons.pencilLine, 'Rename'),
                ('notes', LucideIcons.notebookPen, 'Notes'),
                ('people', LucideIcons.users, 'Collaborators'),
                ('timer', LucideIcons.timer, _timerOpen ? 'Hide timer' : 'Timer'),
              ])
                PopupMenuItem(
                  value: v,
                  child: Row(
                    children: [
                      Icon(icon, size: 16, color: col.gray600),
                      const SizedBox(width: 10),
                      Text(label),
                    ],
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilledButton.icon(
              onPressed: _publish,
              icon: const Icon(LucideIcons.send, size: 15),
              label: const Text('Share'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue600,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _tabs = [
    (_Panel.templates, LucideIcons.layoutTemplate, 'Creatives'),
    (_Panel.text, LucideIcons.type, 'Text'),
    (_Panel.elements, LucideIcons.shapes, 'Elements'),
    (_Panel.uploads, LucideIcons.cloudUpload, 'Uploads'),
    (_Panel.draw, LucideIcons.penTool, 'Draw'),
    (_Panel.brand, LucideIcons.palette, 'Brand'),
    (_Panel.klux, LucideIcons.sparkles, 'Klux AI'),
    (_Panel.magic, LucideIcons.wandSparkles, 'Magic Studio'),
    (_Panel.layers, LucideIcons.layers, 'Layers'),
    (_Panel.resize, LucideIcons.scaling, 'Resize'),
  ];

  /// The panel rail: a vertical column from 1024px (the web's `lg`), a bottom
  /// bar of icons below it.
  Widget _rail(BuildContext context, {required bool vertical}) {
    final col = context.colors;
    final buttons = [
      for (final (panel, icon, label) in _tabs)
        _RailButton(
          icon: icon,
          label: label,
          on: _panel == panel,
          onTap: () {
            setState(() => _panel = _panel == panel ? null : panel);
            // Drawing starts on a clean page — no selection box in the way.
            if (_panel == _Panel.draw) _c?.select(null);
          },
        ),
    ];
    return Container(
      width: vertical ? 72 : null,
      decoration: BoxDecoration(
        color: col.surface,
        border: vertical ? Border(right: BorderSide(color: col.gray200)) : Border(top: BorderSide(color: col.gray200)),
      ),
      child: vertical
          ? ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: buttons)
          : SizedBox(
              height: 62,
              // Fixed-width tabs in a scrolling bar, like the web below `lg` —
              // eight squeezed into a phone's width would be unreadable.
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                children: [for (final b in buttons) SizedBox(width: 66, child: b)],
              ),
            ),
    );
  }

  Widget _panelBody(BuildContext context) {
    final c = _c!;
    final auth = context.read<AuthController>();
    final brand = context.watch<AuthController>().activeBrand;
    final col = context.colors;
    final (_, _, title) = _tabs.firstWhere((t) => t.$1 == _panel);
    return Container(
      color: col.surface,
      child: Column(
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: col.gray200),
                bottom: BorderSide(color: col.gray100),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: col.gray800),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _panel = null),
                  icon: Icon(LucideIcons.chevronDown, size: 17, color: col.gray400),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (_panel!) {
              _Panel.templates => TemplatesPanel(c: c, api: CreativesApi(auth.api), brandId: brand?.id),
              _Panel.draw => DrawPanel(tool: _drawTool, onTool: (t) => setState(() => _drawTool = t), insert: _insert!),
              _Panel.magic => MagicMediaPanel(
                onInsertImage: _insert!.imageUrl,
                onInsertVideo: _insert!.videoUrl,
                selectedImageSrc: () => c.selected?['type'] == 'image' ? c.selected!['src'] as String? : null,
              ),
              _Panel.klux => KluxAiPanel(
                c: c,
                api: auth.api,
                seedRedesign: _kluxSeed,
                onSeedUsed: () => _kluxSeed = false,
              ),
              _Panel.text => TextPanel(
                insert: _insert!,
                onPickFont: () {
                  if (c.selected?['type'] != 'text') {
                    Toast.info('Select some text first');
                    return;
                  }
                  showFontSheet(context, c, brand: brand);
                },
              ),
              _Panel.elements => ElementsPanel(insert: _insert!, previews: _previews),
              _Panel.uploads => UploadsPanel(c: c, insert: _insert!, api: _api, brandApi: auth.brandApi),
              _Panel.brand => BrandPanel(c: c, insert: _insert!, brand: brand),
              _Panel.layers => LayersPanel(c: c),
              _Panel.resize => ResizePanel(c: c),
            },
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.label, required this.on, required this.onTap});

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = on ? AppColors.blue600 : context.colors.gray500;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: on ? context.colors.blueTint : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
