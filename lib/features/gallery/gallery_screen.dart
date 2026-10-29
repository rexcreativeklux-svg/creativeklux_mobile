import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/api/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import '../shell/widgets/app_top_bar.dart';
import 'gallery_api.dart';
import 'media_actions.dart';
import 'media_card.dart';
import 'upload_media_sheet.dart';

/// Per-type pagination (an EMPTY_ENTRY-shaped record in useGalleryMedia.js).
class _TypeState {
  final items = <GalleryMedia>[];
  int page = 0;
  int lastPage = 1;
  bool loading = false;
  bool loaded = false;
}

/// /gallery — port of `(dashboard)/(pages)/gallery/ImageGallery.jsx` with
/// `useGalleryMedia.js` folded in.
///
/// The user's media: Images · Videos · Audio · Docs tabs (the primary
/// navigation), with Search stock (Pexels) and Upload as toolbar actions.
/// The backend paginates PER TYPE; each visited tab keeps its own items and
/// cursor, so switching back never refetches, and the next page loads as
/// the list nears its end (the web's infinite-scroll sentinel). Tab badges
/// come from one tiny `per_page=1` request per type, reading `total`.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late final GalleryApi _api = GalleryApi(context.read<AuthController>().api);

  String _type = 'image';
  final _byType = <String, _TypeState>{};
  final _counts = <String, int>{};
  bool _uploading = false;

  // ── Pexels search mode ──
  bool _searchMode = false;
  final _query = TextEditingController();
  bool _pexelsVideos = false;
  List<GalleryMedia> _results = const [];
  bool _searchLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPage(_type, 1);
    _refreshCounts();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  _TypeState _state(String type) => _byType.putIfAbsent(type, _TypeState.new);

  // ── Data (useGalleryMedia.js) ─────────────────────────────────────────────

  Future<void> _loadPage(String type, int page) async {
    final s = _state(type);
    if (s.loading) return;
    setState(() => s.loading = true);
    final res = await _api.page(type, page: page);
    if (!mounted || _byType[type] != s) return; // dropped by a refresh meanwhile
    setState(() {
      // Page 1 replaces; later pages append, de-duped by id in case an
      // upload shifted items across the page boundary.
      if (page == 1) s.items.clear();
      final seen = {for (final i in s.items) i.id};
      s.items.addAll(res.items.where((i) => !seen.contains(i.id)));
      s.page = res.page;
      s.lastPage = res.lastPage;
      s.loading = false;
      s.loaded = true;
      if (res.total != null) _counts[type] = res.total!;
    });
  }

  Future<void> _refreshCounts() async {
    final results = await Future.wait(
      mediaTypes.map((t) async => MapEntry(t.id, (await _api.page(t.id, perPage: 1)).total ?? 0)),
    );
    if (mounted) setState(() => _counts.addAll(Map.fromEntries(results)));
  }

  void _loadMore() {
    final s = _state(_type);
    if (s.loading || !s.loaded || s.page >= s.lastPage) return;
    _loadPage(_type, s.page + 1);
  }

  /// Reload from scratch after an upload/delete: clear every tab, then
  /// reload the active one and the counts.
  Future<void> _refresh() async {
    setState(_byType.clear);
    await Future.wait([_loadPage(_type, 1), _refreshCounts()]);
  }

  void _setType(String type) {
    if (type == _type) return;
    setState(() => _type = type);
    if (!_state(type).loaded) _loadPage(type, 1);
  }

  // ── Item actions ──────────────────────────────────────────────────────────

  Future<void> _delete(GalleryMedia item) async {
    await showConfirmDialog(
      context,
      title: 'Delete this permanently?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
      onConfirm: () async {
        final error = await _api.delete(item.id!);
        if (error != null) {
          Toast.error('Delete failed', description: error);
          return;
        }
        Toast.success('Deleted!', description: 'Item permanently removed');
        await _refresh();
      },
    );
  }

  List<MediaAction> get _libraryActions => [
    const MediaAction('Download', LucideIcons.download, downloadGalleryMedia),
    const MediaAction('Copy link', LucideIcons.link2, copyMediaLink),
    MediaAction('Delete', LucideIcons.trash2, _delete, danger: true),
  ];

  // ── Upload (handleFileUpload) ─────────────────────────────────────────────

  Future<void> _uploadFiles(List<StagedFile> files) async {
    if (files.isEmpty) return;
    Toast.info('Uploading ${files.length} file(s)…');
    setState(() => _uploading = true);
    var ok = 0;
    Object? lastError;
    String? firstCategory;
    for (final f in files) {
      try {
        await _api.upload(path: f.path, filename: f.name);
        firstCategory ??= f.category;
        ok++;
      } catch (err) {
        debugPrint('❌ [gallery] upload failed for ${f.name}: $err');
        lastError = err;
      }
    }
    if (!mounted) return;
    // Jump to the tab of what was just uploaded, then reload.
    if (ok > 0 && firstCategory != null) _type = firstCategory;
    await _refresh();
    if (!mounted) return;
    setState(() => _uploading = false);
    ok > 0
        ? Toast.success('$ok file(s) uploaded successfully')
        : Toast.error(toUserMessage(lastError, 'Nothing was uploaded'));
  }

  // ── Pexels search ─────────────────────────────────────────────────────────

  Future<void> _runSearch() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searchLoading = true);
    try {
      final results = await GalleryApi.searchStock(q, videos: _pexelsVideos);
      if (mounted) setState(() => _results = results);
    } catch (err) {
      final msg = err is DioException ? null : '$err'.replaceFirst('Exception: ', '');
      Toast.error('Search failed', description: msg ?? 'Try again later');
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  /// Save a stock photo into the gallery (saveUrlToGallery): fetch it, then
  /// upload it like any other file.
  Future<void> _saveStockPhoto(GalleryMedia item) async {
    Toast.info('Saving…', description: 'Adding to your gallery');
    try {
      final url = item.downloadUrl ?? item.src;
      final res = await Dio().get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      await _api.upload(bytes: res.data ?? const [], filename: 'pexels-${DateTime.now().millisecondsSinceEpoch}.jpg');
      await _refresh();
      Toast.success('Saved!', description: 'Added to your gallery');
    } catch (err) {
      Toast.error('Save failed', description: toUserMessage(err, 'Could not save to gallery'));
    }
  }

  void _closeSearch() => setState(() {
    _searchMode = false;
    _results = const [];
    _query.clear();
  });

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      // Back leaves search mode first, like the web's "Back to gallery".
      canPop: !_searchMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _searchMode) _closeSearch();
      },
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AppTopBar(title: 'Gallery', showBack: true),
            Expanded(
              child: ColoredBox(
                color: c.page,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (!_searchMode && n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 500) _loadMore();
                    return false;
                  },
                  child: RefreshIndicator(
                    onRefresh: _searchMode ? _runSearch : _refresh,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          sliver: SliverToBoxAdapter(child: _header()),
                        ),
                        if (_searchMode) ..._searchSlivers(c) else ..._librarySlivers(c),
                        SliverToBoxAdapter(child: SizedBox(height: 28 + MediaQuery.paddingOf(context).bottom)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    decoration: BoxDecoration(
      color: AppColors.blue600,
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))],
    ),
    child: const Row(
      children: [
        Icon(LucideIcons.image, size: 26, color: Colors.white),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Gallery',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              SizedBox(height: 3),
              Text(
                'All your media in one place — images, videos, audio & docs.',
                style: TextStyle(fontSize: 12.5, color: Color(0xCCFFFFFF)),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ── Library mode ──────────────────────────────────────────────────────────

  List<Widget> _librarySlivers(AppColors c) {
    final s = _state(_type);
    final items = s.items;
    final firstLoad = !s.loaded || (s.loading && items.isEmpty);
    final loadingMore = s.loading && items.isNotEmpty;
    final label = mediaTypeMeta(_type).label.toLowerCase();

    return [
      SliverToBoxAdapter(child: _tabs(c)),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _uploading ? null : () => setState(() => _searchMode = true),
                  icon: const Icon(LucideIcons.search, size: 16),
                  label: const Text('Search stock'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    foregroundColor: c.gray700,
                    side: BorderSide(color: c.gray200),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _uploading ? null : () => showUploadMediaSheet(context, onUpload: _uploadFiles),
                  icon: _uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.upload, size: 16),
                  label: const Text('Upload'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    backgroundColor: AppColors.blue600,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      if (firstLoad)
        // The grid the tab is ABOUT to show, not a spinner (the web's reason:
        // the layout is known before the media is).
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: _type == 'image'
                ? MasonryColumns(items: const [], itemBuilder: (_, _) => const SizedBox(), loadingMore: true)
                : _grid([for (var i = 0; i < 6; i++) MediaSkeleton(type: _type)]),
          ),
        )
      else if (items.isEmpty)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(child: _empty(c, label)),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: _type == 'image'
                ? MasonryColumns(
                    items: items,
                    loadingMore: loadingMore,
                    itemBuilder: (item, i) => MediaCard(item: item, index: i, actions: _libraryActions),
                  )
                : _grid([
                    for (var i = 0; i < items.length; i++)
                      MediaCard(key: ValueKey(items[i].id), item: items[i], index: i, actions: _libraryActions),
                    if (loadingMore)
                      for (var i = 0; i < 2; i++) MediaSkeleton(type: _type),
                  ]),
          ),
        ),
    ];
  }

  /// Underline tabs with count badges (MediaTypeTabs, "primary" variant).
  Widget _tabs(AppColors c) => Container(
    height: 46,
    margin: const EdgeInsets.only(top: 16),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: c.gray200)),
    ),
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      children: [
        for (final t in mediaTypes)
          Builder(
            builder: (context) {
              final active = t.id == _type;
              final color = active ? AppColors.blue600 : c.gray500;
              final count = _counts[t.id] ?? 0;
              return InkWell(
                onTap: () => _setType(t.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: active ? AppColors.blue600 : Colors.transparent, width: 2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(t.icon, size: 15, color: color),
                      const SizedBox(width: 6),
                      Text(
                        t.label,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: active ? c.blueTint : c.gray100,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(fontSize: 11, color: active ? AppColors.blue600 : c.gray500),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );

  /// Videos and docs sit two to a row; audio players are wide, so one
  /// (galleryGridClass).
  Widget _grid(List<Widget> children, {int? columns}) {
    final cols = columns ?? (_type == 'audio' ? 1 : 2);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < cols; j++) ...[
                if (j > 0) const SizedBox(width: 10),
                Expanded(child: i + j < children.length ? children[i + j] : const SizedBox()),
              ],
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _empty(AppColors c, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: c.gray200, width: 1.5),
    ),
    child: Column(
      children: [
        Icon(LucideIcons.cloudUpload, size: 44, color: c.gray300),
        const SizedBox(height: 12),
        Text(
          'No $label yet',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray600),
        ),
        const SizedBox(height: 4),
        Text(
          _type == 'image'
              ? 'Use Upload to add images to get started.'
              : 'Your $label will appear here once you create or save some.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: c.gray400),
        ),
      ],
    ),
  );

  // ── Search mode ───────────────────────────────────────────────────────────

  List<Widget> _searchSlivers(AppColors c) => [
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 0),
      sliver: SliverToBoxAdapter(
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _closeSearch,
            icon: Icon(LucideIcons.arrowLeft, size: 17, color: c.gray600),
            label: Text(
              'Back to gallery',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.gray600),
            ),
          ),
        ),
      ),
    ),
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      sliver: SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.gray100),
          ),
          // The field owns the first row; the type picker and Search split
          // the row under it (the web's mobile layout).
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _runSearch(),
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Search millions of free stock images & videos…',
                    prefixIcon: Icon(LucideIcons.search, size: 17, color: c.gray400),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Images')),
                        ButtonSegment(value: true, label: Text('Videos')),
                      ],
                      selected: {_pexelsVideos},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _pexelsVideos = s.first),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _searchLoading ? null : _runSearch,
                    icon: _searchLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(LucideIcons.search, size: 16),
                    label: const Text('Search'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      backgroundColor: AppColors.blue600,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    if (_searchLoading)
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 72),
          child: Center(child: CircularProgressIndicator()),
        ),
      )
    else if (_results.isEmpty)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 72),
          child: Text(
            'Search for images or videos to see results.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: c.gray400),
          ),
        ),
      )
    else
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: _results.first.type == 'video'
              ? _grid(columns: 2, [
                  for (var i = 0; i < _results.length; i++)
                    MediaCard(item: _results[i], index: i, actions: _stockActions(_results[i])),
                ])
              : MasonryColumns(
                  items: _results,
                  itemBuilder: (item, i) => MediaCard(item: item, index: i, actions: _stockActions(item)),
                ),
        ),
      ),
  ];

  List<MediaAction> _stockActions(GalleryMedia item) => [
    if (item.type == 'image') MediaAction('Save to gallery', LucideIcons.folderPlus, _saveStockPhoto),
    const MediaAction('Download', LucideIcons.download, downloadGalleryMedia),
    const MediaAction('Copy link', LucideIcons.link2, copyMediaLink),
  ];
}
