import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/design/design_canvas.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../creatives/creatives_api.dart';
import '../creatives/design.dart';
import 'design_editor_controller.dart';
import 'editor_sheets.dart';

/// "My Creatives" — port of the web's `panels/TemplatesPanel.jsx`. The brand's
/// own saved designs, as templates: tapping one swaps the whole canvas for it
/// (undoable), after asking when there's unsaved work to lose.
///
/// The web's second source, Scraive's template library, is switched off there
/// (its endpoint 500s), so it isn't ported.
class TemplatesPanel extends StatefulWidget {
  const TemplatesPanel({super.key, required this.c, required this.api, required this.brandId});

  final DesignEditorController c;
  final CreativesApi api;
  final int? brandId;

  @override
  State<TemplatesPanel> createState() => _TemplatesPanelState();
}

class _TemplatesPanelState extends State<TemplatesPanel> {
  List<Design>? _designs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final brandId = widget.brandId;
    setState(() => _loading = true);
    final res = brandId == null ? null : await widget.api.page(brandId, perPage: 30);
    if (!mounted) return;
    setState(() {
      _loading = false;
      // Only structured designs make useful templates; not the one open here.
      _designs = [
        for (final d in res?.designs ?? const <Design>[])
          if (d.elementCount > 0 && d.id != widget.c.designId) d,
      ];
    });
  }

  Future<void> _pick(Design d) async {
    if (widget.c.dirty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.colors.surface,
          title: const Text('Replace current design?'),
          content: const Text('This swaps the whole canvas for the selected design. You can undo it.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.red500),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    widget.c.replaceDesign(d.canvasSpec, d.elements);
    Toast.success('Template applied');
  }

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    final designs = _designs ?? const <Design>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        Row(
          children: [
            Expanded(child: sectionLabel(context, 'Your designs')),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: Icon(LucideIcons.refreshCw, size: 15, color: col.gray400),
            ),
          ],
        ),
        if (_loading && designs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (designs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Icon(LucideIcons.layoutTemplate, size: 30, color: col.gray300),
                const SizedBox(height: 8),
                Text(
                  'No saved designs yet. Anything you create shows up here as a reusable template.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: col.gray400),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.8,
            ),
            itemCount: designs.length,
            itemBuilder: (context, i) {
              final d = designs[i];
              return Material(
                color: col.gray50,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: col.gray200),
                ),
                child: InkWell(
                  onTap: () => _pick(d),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Center(
                      child: d.previewUrl != null
                          ? MediaImage(d.previewUrl!, fit: BoxFit.contain, cacheWidth: 360)
                          : DesignCanvas(canvas: d.canvasSpec, elements: d.elements),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
