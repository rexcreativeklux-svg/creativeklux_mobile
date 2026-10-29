import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/design/design_canvas.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../auth/auth_controller.dart';
import '../creatives/creatives_api.dart';
import '../creatives/design.dart';
import 'ad_intel_kit.dart';
import 'ad_intelligence_api.dart';

/// The input card Ad Guard AI and Ad Scorer AI share: "Upload Image" /
/// "Choose Design" tabs, the upload drop zone + preview, and a searchable grid
/// of the brand's saved designs. Both web pages carry their own copy of it
/// (ad-guard-ai/page.jsx, ad-scorer-ai/page.jsx), differing only in accent.
///
/// The PICK lives with the page (it's what the request sends); the tab, the
/// designs list and the search live here.
class CreativeSourceCard extends StatefulWidget {
  const CreativeSourceCard({
    super.key,
    required this.accent,
    required this.file,
    required this.design,
    required this.onFile,
    required this.onDesign,
    required this.onClear,
    this.header,
    this.footer,
    this.showFileMeta = false,
    this.badgeTop = AiHue.emerald,
  });

  final Color accent;
  final PickedCreative? file;
  final Design? design;
  final ValueChanged<PickedCreative> onFile;
  final ValueChanged<Design> onDesign;
  final VoidCallback onClear;

  /// Above the tabs (Ad Guard's platform toggles).
  final Widget? header;

  /// Under the tab body (Ad Scorer's Score button lives inside the card).
  final Widget? footer;

  /// Ad Guard shows the file name + size over the preview; Ad Scorer doesn't.
  final bool showFileMeta;

  /// Top band of the ★ score badge colour (Ad Guard: emerald; Ad Scorer: green).
  final Color badgeTop;

  @override
  State<CreativeSourceCard> createState() => _CreativeSourceCardState();
}

class _CreativeSourceCardState extends State<CreativeSourceCard> {
  String _tab = 'upload';
  List<Design> _designs = const [];
  bool _loading = false;
  String? _error;
  bool _loaded = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// `fetchDesigns(50)` — one page of 50 for the active brand.
  Future<void> _loadDesigns() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthController>();
    final brandId = auth.activeBrand?.id;
    final res = brandId == null ? null : await CreativesApi(auth.api).page(brandId, perPage: 50);
    if (!mounted) return;
    setState(() {
      if (res == null) {
        _error = 'Failed to load designs. Make sure you have an active brand selected.';
      } else {
        _designs = res.designs;
        _loaded = true;
      }
      _loading = false;
    });
  }

  Future<void> _pick() async {
    final f = await pickCreativeImage();
    if (f != null) widget.onFile(f);
  }

  void _switch(String tab) {
    setState(() => _tab = tab);
    if (tab == 'designs' && !_loaded) _loadDesigns();
    // Like the web, the Upload tab goes straight to the picker when empty.
    if (tab == 'upload' && widget.file == null) _pick();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header != null) Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: widget.header),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                _tabButton('upload', LucideIcons.upload, 'Upload Image'),
                const SizedBox(width: 6),
                _tabButton('designs', LucideIcons.layoutGrid, 'Choose Design'),
              ],
            ),
          ),
          Divider(height: 20, thickness: 1, color: c.gray100),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_tab == 'upload') _uploadBody(context) else _designsBody(context),
                if (widget.footer != null) widget.footer!,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String id, IconData icon, String label) {
    final c = context.colors;
    final active = _tab == id;
    final color = active ? widget.accent : c.gray400;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _switch(id),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: active ? widget.accent.withValues(alpha: 0.06) : null,
            border: Border.all(color: active ? widget.accent : Colors.transparent, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _uploadBody(BuildContext context) {
    final c = context.colors;
    final file = widget.file;
    if (file == null) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _pick,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 36),
          decoration: BoxDecoration(
            color: c.gray50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.gray200, width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(12)),
                child: Icon(LucideIcons.upload, size: 20, color: c.gray400),
              ),
              const SizedBox(height: 10),
              Text(
                'Tap to upload',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray700),
              ),
              const SizedBox(height: 3),
              Text('PNG, JPG, WEBP supported', style: TextStyle(fontSize: 12, color: c.gray400)),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: c.gray100,
            constraints: const BoxConstraints(maxHeight: 280),
            child: Stack(
              children: [
                Center(child: Image.memory(file.bytes, fit: BoxFit.contain, gaplessPlayback: true)),
                Positioned(top: 8, right: 8, child: _roundX(widget.onClear)),
                if (widget.showFileMeta)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: c.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.gray700),
                          ),
                          Text(
                            '${file.megabytes.toStringAsFixed(2)} MB',
                            style: TextStyle(fontSize: 10, color: c.gray400),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _pick,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(38),
            foregroundColor: c.gray500,
            side: BorderSide(color: c.gray200),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
          child: const Text('Replace image'),
        ),
      ],
    );
  }

  Widget _roundX(VoidCallback onTap) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: CircleBorder(side: BorderSide(color: c.gray200)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 30, height: 30, child: Icon(LucideIcons.x, size: 15, color: c.gray500)),
      ),
    );
  }

  Widget _designsBody(BuildContext context) {
    final c = context.colors;
    final q = _search.text.toLowerCase();
    final filtered = _designs
        .where((d) => d.name.toLowerCase().contains(q) || (d.tagline ?? '').toLowerCase().contains(q))
        .toList();
    final selected = widget.design;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_loading && _designs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(fontSize: 13, color: c.gray700),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: c.gray50,
                        hintText: 'Search designs…',
                        hintStyle: TextStyle(fontSize: 13, color: c.gray300),
                        prefixIcon: Icon(LucideIcons.search, size: 15, color: c.gray400),
                        prefixIconConstraints: const BoxConstraints(minWidth: 34),
                        contentPadding: const EdgeInsets.fromLTRB(0, 11, 12, 11),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: c.gray200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: widget.accent, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: OutlinedButton(
                    onPressed: _loadDesigns,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: BorderSide(color: c.gray200),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Icon(LucideIcons.refreshCw, size: 15, color: c.gray400),
                  ),
                ),
              ],
            ),
          ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Spinner(color: widget.accent, size: 26),
                const SizedBox(height: 12),
                Text('Loading designs…', style: TextStyle(fontSize: 13, color: c.gray400)),
              ],
            ),
          )
        else if (_error != null)
          ErrorBanner(_error!, bottom: 0)
        else if (_designs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(LucideIcons.layoutGrid, size: 34, color: c.gray200),
                const SizedBox(height: 8),
                Text('No saved designs found.', style: TextStyle(fontSize: 13, color: c.gray400)),
                const SizedBox(height: 2),
                Text('Create a design first from the Studio.', style: TextStyle(fontSize: 12, color: c.gray300)),
              ],
            ),
          )
        else if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                Text('No designs match "${_search.text}"', style: TextStyle(fontSize: 13, color: c.gray400)),
                TextButton(
                  onPressed: () => setState(_search.clear),
                  child: Text('Clear search', style: TextStyle(fontSize: 12, color: widget.accent)),
                ),
              ],
            ),
          )
        else
          // The web caps the grid at 340px and scrolls it; kept, so the
          // Run button below stays in reach with 50 designs loaded.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: filtered.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 148,
              ),
              itemBuilder: (_, i) => _DesignTile(
                design: filtered[i],
                selected: selected?.id == filtered[i].id,
                accent: widget.accent,
                badgeTop: widget.badgeTop,
                onTap: () => widget.onDesign(filtered[i]),
              ),
            ),
          ),
        if (selected != null)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: widget.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.circleCheck, size: 15, color: widget.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selected.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: widget.accent),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClear,
                  icon: Icon(LucideIcons.x, size: 15, color: widget.accent),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One saved design in the picker grid: preview, ★ score, selected check, name
/// and tagline (or headline).
class _DesignTile extends StatelessWidget {
  const _DesignTile({
    required this.design,
    required this.selected,
    required this.accent,
    required this.badgeTop,
    required this.onTap,
  });

  final Design design;
  final bool selected;
  final Color accent;
  final Color badgeTop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = design;
    final sub = d.tagline ?? str(d.copy['headline']);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? accent : c.gray100, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: c.gray100,
                    child: d.elements.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(4),
                            child: DesignCanvas(canvas: d.canvasSpec, elements: d.elements),
                          )
                        : d.previewUrl != null
                        ? MediaImage(d.previewUrl!, fit: BoxFit.contain, cacheWidth: 400)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.image, size: 22, color: c.gray300),
                              const SizedBox(height: 3),
                              Text('No preview', style: TextStyle(fontSize: 10, color: c.gray300)),
                            ],
                          ),
                  ),
                  if (d.score > 0)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '★ ${d.score}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: scoreColor(d.score, top: badgeTop),
                          ),
                        ),
                      ),
                    ),
                  if (selected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                        child: const Icon(LucideIcons.check, size: 13, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              color: selected ? accent.withValues(alpha: 0.08) : c.surface,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.gray800),
                  ),
                  if (sub != null)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: c.gray400,
                        fontStyle: d.tagline != null ? FontStyle.italic : FontStyle.normal,
                      ),
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
