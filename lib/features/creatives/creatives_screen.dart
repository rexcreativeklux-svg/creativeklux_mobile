import 'dart:convert';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design/design_canvas.dart';
import '../../core/design/design_renderer.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import '../publish/publish_sheet.dart';
import '../shell/widgets/app_top_bar.dart';
import 'create_sheet.dart';
import 'creatives_api.dart';
import 'design.dart';

/// Port of `(dashboard)/(pages)/creatives/page.jsx` — "My Creations", the
/// library of saved designs for the active brand.
///
/// Like the web, everything is fetched up front (the server ignores filters)
/// and filtered, searched, counted and paged on the device. Phone layout:
/// 2-column grid; the web's side drawer is a bottom sheet; "Download" saves
/// to the photo gallery.
class CreativesScreen extends StatefulWidget {
  const CreativesScreen({super.key});

  @override
  State<CreativesScreen> createState() => _CreativesScreenState();
}

const _tabs = [
  ('all', 'All', <String>[]),
  ('ads', 'Ads', ['ads']),
  ('social', 'Social', ['social']),
  ('design', 'Design', ['card', 'banner', 'designer', 'design']),
  ('favorites', '★ Favorites', <String>[]),
];

const _typeColors = {
  'ads': Color(0xFF2B7FFF),
  'social': Color(0xFF615FFF),
  'card': Color(0xFF8E51FF),
  'banner': Color(0xFF00BBA7),
  'image': Color(0xFF2B7FFF),
  'video': Color(0xFF00B8DB),
  'poster': Color(0xFFE12AFB),
  'flyer': Color(0xFF8E51FF),
};

Color _typeColor(String type) => _typeColors[type.toLowerCase()] ?? const Color(0xFF99A1AF);

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _shortDate(DateTime? d) {
  if (d == null) return '—';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[d.month - 1]} ${d.day}';
}

class _CreativesScreenState extends State<CreativesScreen> {
  static const _perPageKey = 'ck_creatives_per_page';

  List<Design> _designs = [];
  bool _loading = true;
  bool _error = false;
  int? _loadedBrandId;
  int _run = 0;

  String _search = '';
  String _tab = 'all';
  int _perPage = 12;
  int _page = 1;
  bool _grid = true;

  bool _selecting = false;
  final _selected = <int>{};

  late CreativesApi _api;

  @override
  void initState() {
    super.initState();
    _api = CreativesApi(context.read<AuthController>().api);
    SharedPreferences.getInstance().then((p) {
      final saved = p.getInt(_perPageKey);
      if (saved != null && mounted) setState(() => _perPage = saved);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload whenever the active brand changes (the only thing that triggers a fetch).
    final brandId = context.watch<AuthController>().activeBrand?.id;
    if (brandId != null && brandId != _loadedBrandId) {
      _loadedBrandId = brandId;
      _load(brandId);
    }
  }

  Future<void> _load(int brandId) async {
    final run = ++_run;
    setState(() {
      _loading = true;
      _error = false;
      _designs = [];
      _page = 1;
    });
    try {
      final all = await _api.all(
        brandId,
        onProgress: (sofar) {
          // Show page 1 as soon as it lands; ignore results from a stale brand.
          if (mounted && run == _run) {
            setState(() {
              _designs = sofar;
              _loading = false;
            });
          }
        },
      );
      if (!mounted || run != _run) return;
      setState(() {
        _designs = all ?? [];
        _loading = false;
      });
    } catch (_) {
      if (mounted && run == _run) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  bool _matchesTab(Design d, String tab) {
    if (tab == 'all') return true;
    if (tab == 'favorites') return d.favorite;
    final values = _tabs.firstWhere((t) => t.$1 == tab).$3;
    return values.contains(d.type.toLowerCase()) || values.contains(d.category.toLowerCase());
  }

  bool _matchesSearch(Design d) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    return d.name.toLowerCase().contains(q) ||
        d.type.toLowerCase().contains(q) ||
        (d.tagline ?? '').toLowerCase().contains(q);
  }

  Future<void> _setPerPage(int n) async {
    setState(() {
      _perPage = n.clamp(1, 500);
      _page = 1;
    });
    (await SharedPreferences.getInstance()).setInt(_perPageKey, _perPage);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _toggleFavorite(Design d) async {
    final next = !d.favorite;
    setState(() => d.favorite = next);
    final res = await _api.setFavorite(d.id, next);
    if (!res.ok && mounted) {
      setState(() => d.favorite = !next);
      Toast.error(res.message.isNotEmpty ? res.message : 'Could not update favorite');
    }
  }

  Future<void> _confirmDelete({Design? single}) async {
    final ids = single != null ? [single.id] : _selected.toList();
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(
        count: ids.length,
        onDelete: () async {
          final res = ids.length == 1 && single != null ? await _api.delete(ids.first) : await _api.bulkDelete(ids);
          return res.ok;
        },
      ),
    );
    if (ok == null || !mounted) return;
    if (ok) {
      setState(() {
        _designs.removeWhere((d) => ids.contains(d.id));
        _selected.clear();
        if (single == null) _selecting = false;
      });
      Toast.success(single != null ? 'Design deleted' : '${ids.length} design${ids.length == 1 ? '' : 's'} deleted');
    } else {
      Toast.error(single != null ? 'Failed to delete design' : 'Failed to delete designs');
    }
  }

  void _open(Design d) {
    if (_selecting) {
      setState(() => _selected.contains(d.id) ? _selected.remove(d.id) : _selected.add(d.id));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DesignDetailSheet(
        design: d,
        api: _api,
        onFavorite: () => _toggleFavorite(d),
        onDelete: () => _confirmDelete(single: d),
        onChanged: () => setState(() {}),
        onEdit: _edit,
      ),
    );
  }

  /// Open the editor, then reload so the list shows the edited design's new
  /// name and thumbnail when you come back.
  Future<void> _edit(String path) async {
    await context.push(path);
    final brandId = _loadedBrandId;
    if (mounted && brandId != null) _load(brandId);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final searched = _designs.where(_matchesSearch).toList();
    final filtered = searched.where((d) => _matchesTab(d, _tab)).toList();
    final totalPages = max(1, (filtered.length / _perPage).ceil());
    final page = _page.clamp(1, totalPages);
    final pageItems = filtered.skip((page - 1) * _perPage).take(_perPage).toList();
    final width = MediaQuery.sizeOf(context).width;
    final canList = width >= 768;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Creative Studio'),
          Expanded(
            child: Container(
              color: c.page,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context),
                  if (_selecting) _bulkBar(context, pageItems),
                  _toolbar(context, searched, canList),
                  Expanded(
                    child: _error
                        ? _errorView(context)
                        : _loading
                        ? _skeleton(context)
                        : filtered.isEmpty
                        ? _empty(context)
                        : RefreshIndicator(
                            onRefresh: () => _load(_loadedBrandId!),
                            child: _grid || !canList ? _gridView(pageItems, width) : _listView(pageItems),
                          ),
                  ),
                  if (!_loading && totalPages > 1) _pager(context, page, totalPages, filtered.length),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIBRARY',
                  style: TextStyle(fontSize: 10, letterSpacing: 1.6, fontWeight: FontWeight.w600, color: c.gray400),
                ),
                Text(
                  'My Creations',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.gray900),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () => showCreateSheet(context),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('New'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.blue600,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: const Size(0, 38),
              textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulkBar(BuildContext context, List<Design> pageItems) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.blueTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDBEAFE)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text(
            '${_selected.length} selected',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.blue600),
          ),
          TextButton(
            onPressed: () => setState(() => _selected.addAll(pageItems.map((d) => d.id))),
            child: const Text('Select all on page'),
          ),
          TextButton(onPressed: () => setState(_selected.clear), child: const Text('Deselect all')),
          if (_selected.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _confirmDelete(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.red500,
                side: const BorderSide(color: Color(0xFFFFC9C9)),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(LucideIcons.trash2, size: 15),
              label: Text('Delete ${_selected.length}'),
            ),
        ],
      ),
    );
  }

  Widget _toolbar(BuildContext context, List<Design> searched, bool canList) {
    final c = context.colors;
    Widget iconButton(IconData icon, String tip, VoidCallback onTap, {bool on = false}) => Tooltip(
      message: tip,
      child: Material(
        color: on ? c.blueTint : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: on ? const Color(0xFFBEDBFF) : c.gray200),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 17, color: on ? AppColors.blue600 : c.gray600),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() {
                    _search = v;
                    _page = 1;
                  }),
                  style: TextStyle(fontSize: 13.5, color: c.gray900),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search creations...',
                    hintStyle: TextStyle(color: c.gray400, fontSize: 13.5),
                    prefixIcon: Icon(LucideIcons.search, size: 16, color: c.gray400),
                    filled: true,
                    fillColor: c.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.gray200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.blue600),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              iconButton(
                _selecting ? LucideIcons.squareCheck : LucideIcons.square,
                _selecting ? 'Exit select mode' : 'Select multiple',
                () => setState(() {
                  _selecting = !_selecting;
                  _selected.clear();
                }),
                on: _selecting,
              ),
              const SizedBox(width: 8),
              PopupMenuButton<int>(
                tooltip: 'How many to show per page',
                color: c.surface,
                onSelected: _setPerPage,
                itemBuilder: (_) => [
                  for (final n in [12, 24, 48, 96])
                    PopupMenuItem(
                      value: n,
                      child: Text(
                        'Show $n',
                        style: TextStyle(
                          color: n == _perPage ? AppColors.blue600 : c.gray800,
                          fontWeight: n == _perPage ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.gray200),
                  ),
                  child: Row(
                    children: [
                      Text('Show $_perPage', style: TextStyle(fontSize: 13, color: c.gray700)),
                      Icon(LucideIcons.chevronDown, size: 14, color: c.gray400),
                    ],
                  ),
                ),
              ),
              if (canList) ...[
                const SizedBox(width: 8),
                iconButton(LucideIcons.layoutGrid, 'Grid view', () => setState(() => _grid = true), on: _grid),
                const SizedBox(width: 4),
                iconButton(LucideIcons.list, 'List view', () => setState(() => _grid = false), on: !_grid),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (key, label, _) in _tabs)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _tab = key;
                        _page = 1;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: _tab == key ? c.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: _tab == key ? const Color(0xFFDBEAFE) : Colors.transparent),
                        ),
                        child: Row(
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _tab == key ? AppColors.blue600 : c.gray500,
                              ),
                            ),
                            if (!_loading) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: _tab == key ? c.blueTint : c.gray100,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '${searched.where((d) => _matchesTab(d, key)).length}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _tab == key ? AppColors.blue600 : c.gray500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridView(List<Design> items, double width) {
    final cols = width >= 1280 ? 4 : (width >= 1024 ? 3 : 2);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.74,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _DesignCard(
        design: items[i],
        selecting: _selecting,
        checked: _selected.contains(items[i].id),
        onTap: () => _open(items[i]),
        onFavorite: () => _toggleFavorite(items[i]),
        onDelete: () => _confirmDelete(single: items[i]),
        onLongPress: () => setState(() {
          _selecting = true;
          _selected.add(items[i].id);
        }),
      ),
    );
  }

  Widget _listView(List<Design> items) {
    final c = context.colors;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: c.gray100),
      itemBuilder: (context, i) {
        final d = items[i];
        final checked = _selected.contains(d.id);
        return Material(
          color: checked ? c.blueTint : c.surface,
          child: InkWell(
            onTap: () => _open(d),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  if (_selecting)
                    Checkbox(value: checked, onChanged: (_) => _open(d), visualDensity: VisualDensity.compact),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(width: 56, height: 40, child: _Artwork(design: d, blurBackdrop: false)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Text(
                      d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, color: c.gray900),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      d.tagline ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.gray500),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _TypePill(type: d.type, label: d.category),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(d.score > 0 ? '★ ${d.score}' : '—', style: TextStyle(color: c.gray600)),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(_shortDate(d.createdAt), style: TextStyle(color: c.gray500)),
                  ),
                  _FavButton(design: d, onTap: () => _toggleFavorite(d)),
                  IconButton(
                    tooltip: 'Delete design',
                    onPressed: () => _confirmDelete(single: d),
                    icon: Icon(LucideIcons.trash2, size: 16, color: c.gray400),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pager(BuildContext context, int page, int totalPages, int total) {
    final c = context.colors;
    final from = (page - 1) * _perPage + 1;
    final to = min(page * _perPage, total);
    final narrow = MediaQuery.sizeOf(context).width < 480;

    // First, last, and a window around the current page.
    final pages = <int?>[];
    final window = narrow ? 0 : 1;
    for (var p = 1; p <= totalPages; p++) {
      if (p == 1 || p == totalPages || (p - page).abs() <= window) {
        pages.add(p);
      } else if (pages.isNotEmpty && pages.last != null) {
        pages.add(null);
      }
    }

    Widget btn(Widget child, VoidCallback? onTap, {bool active = false}) => Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: active ? AppColors.blue600 : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: active ? AppColors.blue600 : c.gray200),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 13, color: active ? Colors.white : c.gray700),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.gray200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${narrow ? '' : 'Showing '}$from–$to of $total',
              style: TextStyle(fontSize: 12.5, color: c.gray500),
            ),
          ),
          btn(
            Icon(LucideIcons.chevronLeft, size: 15, color: c.gray600),
            page > 1 ? () => setState(() => _page = page - 1) : null,
          ),
          for (final p in pages)
            p == null
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('…', style: TextStyle(color: c.gray400)),
                  )
                : btn(Text('$p'), () => setState(() => _page = p), active: p == page),
          btn(
            Icon(LucideIcons.chevronRight, size: 15, color: c.gray600),
            page < totalPages ? () => setState(() => _page = page + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _skeleton(BuildContext context) {
    final c = context.colors;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.74,
      ),
      itemCount: 6,
      itemBuilder: (_, _) => Container(
        decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final c = context.colors;
    final hasAny = _designs.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        Icon(LucideIcons.flaskConical, size: 72, color: c.gray300),
        const SizedBox(height: 16),
        Text(
          hasAny ? 'No creatives match your search.' : 'No designs have been created yet.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray700),
        ),
        if (!hasAny) ...[
          const SizedBox(height: 4),
          Text(
            'Tap New at the top right to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.gray500),
          ),
        ],
      ],
    );
  }

  Widget _errorView(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.triangleAlert, size: 32, color: AppColors.red500),
          const SizedBox(height: 12),
          Text('Failed to load designs.', style: TextStyle(color: c.gray700)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _load(_loadedBrandId!),
            icon: const Icon(LucideIcons.refreshCw, size: 15),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ── Card pieces ─────────────────────────────────────────────────────────────

/// Preview art, in the web's order: the server thumbnail contained over a
/// blurred copy of itself → the design painted from its layout JSON → the
/// image URL → a "No preview" placeholder.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.design, this.blurBackdrop = true});

  final Design design;
  final bool blurBackdrop;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final thumb = design.thumbnail != null && design.thumbnail!.startsWith('http') ? design.thumbnail : null;
    if (thumb == null && design.elementCount > 0) {
      return ColoredBox(
        color: c.gray50,
        child: Padding(
          padding: EdgeInsets.all(blurBackdrop ? 8 : 2),
          child: Center(
            child: DesignCanvas(canvas: design.canvasSpec, elements: design.elements),
          ),
        ),
      );
    }
    final url = design.previewUrl;
    if (url == null) {
      return ColoredBox(
        color: c.gray100,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.wand, size: 20, color: c.gray300),
            if (blurBackdrop) ...[
              const SizedBox(height: 4),
              Text('No preview', style: TextStyle(fontSize: 11, color: c.gray400)),
            ],
          ],
        ),
      );
    }
    if (!blurBackdrop) return MediaImage(url, cacheWidth: 160);
    return Stack(
      fit: StackFit.expand,
      children: [
        // The art's own colours, blurred, behind it. Full strength reads as a
        // rich backdrop; the web's faded version looked washed out on a phone.
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Transform.scale(scale: 1.3, child: MediaImage(url, cacheWidth: 200)),
        ),
        const ColoredBox(color: Color(0x14000000)),
        Padding(
          padding: const EdgeInsets.all(10),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: MediaImage(url, fit: BoxFit.contain, cacheWidth: 600),
          ),
        ),
      ],
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.type, this.label});

  final String type;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            _cap(label ?? type),
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _FavButton extends StatelessWidget {
  const _FavButton({required this.design, required this.onTap});

  final Design design;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: design.favorite ? 'Remove from favorites' : 'Add to favorites',
    visualDensity: VisualDensity.compact,
    onPressed: onTap,
    icon: Icon(
      LucideIcons.star,
      size: 16,
      color: design.favorite ? AppColors.amber500 : context.colors.gray400,
      fill: design.favorite ? 1 : 0,
    ),
  );
}

class _DesignCard extends StatelessWidget {
  const _DesignCard({
    required this.design,
    required this.selecting,
    required this.checked,
    required this.onTap,
    required this.onFavorite,
    required this.onDelete,
    required this.onLongPress,
  });

  final Design design;
  final bool selecting;
  final bool checked;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;

  /// Long-press starts multi-select with this card picked, like a phone's
  /// photo gallery.
  final VoidCallback onLongPress;

  /// The card's actions, from the ⋯ button. Delete lives here rather than on
  /// the card face, so it can't be hit by accident while scrolling.
  void _menu(BuildContext context) {
    final c = context.colors;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (sheet) {
        Widget item(IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
          leading: Icon(icon, size: 19, color: color ?? c.gray700),
          title: Text(label, style: TextStyle(color: color ?? c.gray900)),
          onTap: () {
            Navigator.pop(sheet);
            onTap();
          },
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  design.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
                ),
              ),
              item(LucideIcons.eye, 'Open', onTap),
              item(LucideIcons.star, design.favorite ? 'Remove from favorites' : 'Add to favorites', onFavorite),
              item(LucideIcons.squareCheck, 'Select', onLongPress),
              item(LucideIcons.trash2, 'Delete', onDelete, color: AppColors.red600),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = design;
    // The category is already on the chip over the art, so the line under the
    // title is the tagline (when there is one) and the date.
    final meta = [?d.tagline, _shortDate(d.createdAt)].where((s) => s.isNotEmpty).join(' · ');

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: checked ? BorderSide(color: AppColors.blue500, width: 2) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: selecting ? null : onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Artwork(design: d),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: selecting
                          ? Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: checked ? AppColors.blue600 : Colors.white.withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                                border: Border.all(color: checked ? AppColors.blue600 : Colors.white, width: 2),
                                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
                              ),
                              child: checked ? const Icon(LucideIcons.check, size: 14, color: Colors.white) : null,
                            )
                          : DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: _TypePill(type: d.type),
                            ),
                    ),
                    if (!selecting)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onFavorite,
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: Icon(
                                LucideIcons.star,
                                size: 15,
                                color: d.favorite ? AppColors.amber500 : c.gray500,
                                fill: d.favorite ? 1 : 0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (d.score > 0)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.green600, borderRadius: BorderRadius.circular(99)),
                          child: Text(
                            '★ ${d.score}',
                            style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: c.gray500),
                          ),
                        ],
                      ),
                    ),
                    if (!selecting)
                      IconButton(
                        tooltip: 'More',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _menu(context),
                        icon: Icon(LucideIcons.ellipsisVertical, size: 17, color: c.gray500),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dialogs & sheet ─────────────────────────────────────────────────────────

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.count, required this.onDelete});

  final int count;
  final Future<bool> Function() onDelete;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = widget.count;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: c.surface,
        title: Text(n == 1 ? 'Delete design?' : 'Delete $n designs?'),
        content: Text('This action cannot be undone.', style: TextStyle(color: c.gray600)),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    final ok = await widget.onDelete();
                    if (context.mounted) Navigator.pop(context, ok);
                  },
            style: FilledButton.styleFrom(backgroundColor: AppColors.red500),
            child: _busy
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// The web's right-side details drawer, as a bottom sheet.
class _DesignDetailSheet extends StatefulWidget {
  const _DesignDetailSheet({
    required this.design,
    required this.api,
    required this.onFavorite,
    required this.onDelete,
    required this.onChanged,
    required this.onEdit,
  });

  final Design design;
  final CreativesApi api;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final ValueChanged<String> onEdit;

  @override
  State<_DesignDetailSheet> createState() => _DesignDetailSheetState();
}

class _DesignDetailSheetState extends State<_DesignDetailSheet> {
  bool _showAllCopy = false;
  bool _copied = false;
  bool _downloading = false;

  Design get d => widget.design;

  /// Like the web: a design with layout is rendered at full resolution;
  /// image-only designs save their image.
  Future<void> _download() async {
    final url = d.previewUrl;
    if (d.elementCount == 0 && url == null) {
      Toast.error('This design has nothing to download.');
      return;
    }
    setState(() => _downloading = true);
    try {
      Uint8List bytes;
      if (d.elementCount > 0) {
        bytes = await renderDesignPng(d.canvasSpec, d.elements);
      } else {
        final res = await Dio().get<List<int>>(url!, options: Options(responseType: ResponseType.bytes));
        bytes = Uint8List.fromList(res.data ?? const []);
      }
      if (bytes.isEmpty) throw Exception('Could not fetch the image.');
      final rand = String.fromCharCodes(List.generate(5, (_) => 97 + Random().nextInt(26)));
      final now = DateTime.now();
      final time = [now.hour, now.minute, now.second].map((v) => '$v'.padLeft(2, '0')).join('-');
      if (!await Gal.hasAccess(toAlbum: false)) await Gal.requestAccess();
      await Gal.putImageBytes(bytes, name: 'creativeklux-$rand-$time');
      Toast.success('Design saved to your gallery ✓');
    } catch (err) {
      debugPrint('download failed: $err');
      Toast.error('Download failed. Please try again.');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _copyText() async {
    await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(d.copy)));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _editCopy() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditCopyDialog(design: d, api: widget.api),
    );
    if (saved == true) {
      setState(() {});
      widget.onChanged();
    }
  }

  /// A saved design publishes its hosted thumbnail / image straight away; one
  /// without a hosted file is painted and uploaded by the sheet first.
  void _publish({bool schedule = false}) => showPublishSheet(
    context,
    PublishCreative(
      name: d.name,
      category: d.category,
      copy: d.copy,
      image: d.previewUrl,
      isVideo: RegExp(r'\.(mp4|webm|mov|m4v)(\?|#|$)', caseSensitive: false).hasMatch(d.previewUrl ?? ''),
      canvas: d.canvasSpec,
      elements: d.elements,
    ),
    startInSchedule: schedule,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final copyEntries = d.copy.entries.where((e) => e.value is String && (e.value as String).isNotEmpty).toList();
    final visibleCopy = _showAllCopy ? copyEntries : copyEntries.take(3).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Row(
                  children: [
                    _TypePill(type: d.type),
                    const Spacer(),
                    IconButton(
                      tooltip: d.favorite ? 'Remove from favorites' : 'Add to favorites',
                      onPressed: () {
                        widget.onFavorite();
                        setState(() {});
                      },
                      icon: Icon(
                        LucideIcons.star,
                        size: 18,
                        color: d.favorite ? AppColors.amber500 : c.gray400,
                        fill: d.favorite ? 1 : 0,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete design',
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onDelete();
                      },
                      icon: Icon(LucideIcons.trash2, size: 18, color: c.gray400),
                    ),
                    IconButton(
                      tooltip: 'Close details',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(LucideIcons.x, size: 18, color: c.gray500),
                    ),
                  ],
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 200),
                    color: c.gray100,
                    child: Stack(
                      children: [
                        if (d.thumbnail?.startsWith('http') ?? false)
                          MediaImage(d.thumbnail!, fit: BoxFit.contain)
                        else if (d.elementCount > 0)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: DesignCanvas(canvas: d.canvasSpec, elements: d.elements),
                          )
                        else if (d.previewUrl != null)
                          MediaImage(d.previewUrl!, fit: BoxFit.contain)
                        else
                          SizedBox(
                            height: 200,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.wand, color: c.gray300),
                                  const SizedBox(height: 6),
                                  Text('No preview available', style: TextStyle(color: c.gray400)),
                                ],
                              ),
                            ),
                          ),
                        // Always visible on touch, like the web on touchscreens.
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 10,
                          child: Row(
                            children: [
                              for (final (label, icon, path) in [
                                ('Edit with editor', LucideIcons.pencilLine, '/design/${d.id}'),
                                ('Edit with AI', LucideIcons.sparkles, '/design/${d.id}?panel=klux'),
                              ]) ...[
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      widget.onEdit(path);
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: const Color(0xFF101828),
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      elevation: 3,
                                      shadowColor: const Color(0x55000000),
                                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                                    ),
                                    icon: Icon(icon, size: 15),
                                    label: Text(label, style: const TextStyle(fontSize: 12.5)),
                                  ),
                                ),
                                if (label.startsWith('Edit with e')) const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.gray900),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit copy',
                      onPressed: _editCopy,
                      icon: Icon(LucideIcons.pencil, size: 16, color: c.gray500),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(LucideIcons.clock, size: 12, color: c.gray400),
                    const SizedBox(width: 4),
                    Text(_shortDate(d.createdAt), style: TextStyle(fontSize: 12, color: c.gray400)),
                  ],
                ),
                if (d.tagline != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    d.tagline!,
                    style: TextStyle(fontStyle: FontStyle.italic, color: c.gray600),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final (label, value) in [
                      ('Type', _cap(d.type)),
                      ('Category', _cap(d.category)),
                      ('Score', d.score > 0 ? '★ ${d.score}' : '—'),
                    ]) ...[
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: c.gray50, borderRadius: BorderRadius.circular(10)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label.toUpperCase(),
                                style: TextStyle(fontSize: 9, letterSpacing: 1, color: c.gray400),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                value,
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.gray800),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (label != 'Score') const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Canvas', style: TextStyle(fontSize: 12.5, color: c.gray500)),
                    const Spacer(),
                    Text(
                      '${d.canvasWidth.round()} × ${d.canvasHeight.round()}px',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: c.gray700),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: _publish,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.blue600,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    icon: const Icon(LucideIcons.send, size: 16),
                    label: const Text('Publish'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: FilledButton.icon(
                          onPressed: () => _publish(schedule: true),
                          style: FilledButton.styleFrom(
                            backgroundColor: c.blueTint,
                            foregroundColor: AppColors.blue600,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          icon: const Icon(LucideIcons.calendarClock, size: 16),
                          label: const Text('Schedule'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: OutlinedButton.icon(
                          onPressed: _downloading ? null : _download,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.gray800,
                            side: BorderSide(color: c.gray200),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          icon: _downloading
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(LucideIcons.download, size: 16),
                          label: Text(_downloading ? 'Saving…' : 'Download'),
                        ),
                      ),
                    ),
                  ],
                ),
                if (copyEntries.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'GENERATED COPY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.blue600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final e in visibleCopy)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.key.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(fontSize: 9.5, letterSpacing: 1, color: c.gray400),
                          ),
                          const SizedBox(height: 2),
                          Text('${e.value}', style: TextStyle(fontSize: 13.5, height: 1.4, color: c.gray800)),
                        ],
                      ),
                    ),
                  if (copyEntries.length > 3)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => _showAllCopy = !_showAllCopy),
                        child: Text(_showAllCopy ? 'Show less' : 'See more'),
                      ),
                    ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _copyText,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    foregroundColor: _copied ? AppColors.green600 : c.gray800,
                    side: BorderSide(color: _copied ? AppColors.green600 : c.gray200),
                  ),
                  icon: Icon(_copied ? LucideIcons.check : LucideIcons.copy, size: 16),
                  label: Text(_copied ? 'Copied!' : 'Copy Text'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditCopyDialog extends StatefulWidget {
  const _EditCopyDialog({required this.design, required this.api});

  final Design design;
  final CreativesApi api;

  @override
  State<_EditCopyDialog> createState() => _EditCopyDialogState();
}

class _EditCopyDialogState extends State<_EditCopyDialog> {
  late final _name = TextEditingController(text: widget.design.name);
  late final _fields = {
    for (final k in ['headline', 'tagline', 'body', 'cta'])
      k: TextEditingController(text: '${widget.design.copy[k] ?? ''}'),
  };
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final copy = {...widget.design.copy, for (final e in _fields.entries) e.key: e.value.text};
    final res = await widget.api.updateCopy(widget.design.id, name: _name.text.trim(), copy: copy);
    if (!mounted) return;
    if (res.ok) {
      widget.design
        ..name = _name.text.trim().isEmpty ? widget.design.name : _name.text.trim()
        ..copy = copy;
      Toast.success('Design updated');
      Navigator.pop(context, true);
    } else {
      Toast.error('Failed to update design');
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget field(String label, TextEditingController ctrl, String hint, {int lines = 1}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 6,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
      ),
    );

    return AlertDialog(
      backgroundColor: c.surface,
      title: const Text('Edit Copy'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text('Update text content for this design', style: TextStyle(color: c.gray500)),
            ),
            field('Design Name', _name, 'e.g. Summer Campaign Card'),
            field('Headline', _fields['headline']!, 'e.g. Adventure Awaits'),
            field('Tagline', _fields['tagline']!, 'e.g. Discover your next thrill'),
            field('Body Copy', _fields['body']!, 'e.g. Join us for an unforgettable journey…', lines: 4),
            field('Call to Action', _fields['cta']!, 'e.g. Get Started'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AppColors.blue600),
          child: Text(_saving ? 'Saving…' : 'Save Changes'),
        ),
      ],
    );
  }
}
