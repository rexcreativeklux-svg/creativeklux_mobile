import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/app_exception.dart';
import '../../core/config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../brand/brand_api.dart';
import 'design_editor_controller.dart';
import 'editor_api.dart';
import 'editor_panels.dart';
import 'editor_video.dart';

/// Uploads — port of the web's `panels/UploadsPanel.jsx` (+ `uploads/*`): your
/// gallery by type (Images / Videos), uploading from the phone, and stock
/// photos & videos from Pexels once you search.
///
/// Stock search goes through the WEB APP's own `/api/pexels` route, exactly as
/// the web does: the Pexels key stays on that server, never in the app. (CORS
/// doesn't apply to a phone, so the app can call it directly.)
class UploadsPanel extends StatefulWidget {
  const UploadsPanel({super.key, required this.c, required this.insert, required this.api, required this.brandApi});

  final DesignEditorController c;
  final EditorInserts insert;
  final EditorApi api;
  final BrandApi brandApi;

  @override
  State<UploadsPanel> createState() => _UploadsPanelState();
}

class _Stock {
  const _Stock({required this.thumb, required this.full, this.duration});
  final String thumb;
  final String full;
  final double? duration;
}

class _UploadsPanelState extends State<UploadsPanel> {
  String _type = 'image'; // 'image' | 'video'
  final _items = <GalleryItem>[];
  var _page = 1;
  var _hasMore = true;
  var _loading = false;
  var _uploading = false;

  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<_Stock>? _stock;
  String? _stockError;
  var _stockRun = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _reset() {
    _items.clear();
    _page = 1;
    _hasMore = true;
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final type = _type;
    final (items, more) = await widget.api.gallery(type: type, page: _page);
    if (!mounted || type != _type) return;
    setState(() {
      _items.addAll(items);
      _hasMore = more;
      _page++;
      _loading = false;
    });
  }

  void _setType(String t) {
    if (t == _type) return;
    setState(() {
      _type = t;
      _loading = false;
      _reset();
    });
    _load();
    if (_query.isNotEmpty) _runStock();
  }

  // ── Stock (usePexelsSearch.js) ─────────────────────────────────────────────

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _query = q.trim());
      _runStock();
    });
  }

  Future<void> _runStock() async {
    final q = _query;
    final run = ++_stockRun;
    if (q.isEmpty) {
      setState(() => _stock = null);
      return;
    }
    setState(() {
      _stock = null;
      _stockError = null;
    });
    final kind = _type == 'video' ? 'videos' : 'photos';
    try {
      final res = await Dio().get<Map<String, dynamic>>(
        '${AppConfig.webAppUrl}/api/pexels',
        queryParameters: {'query': q, 'type': kind, 'per_page': 30},
      );
      if (!mounted || run != _stockRun) return;
      final data = res.data ?? const {};
      setState(() => _stock = kind == 'videos' ? _videos(data['videos']) : _photos(data['photos']));
    } catch (_) {
      if (mounted && run == _stockRun) setState(() => _stockError = 'Stock search failed');
    }
  }

  /// large2x is what gets placed — medium is thumbnail-resolution.
  static List<_Stock> _photos(Object? list) => [
    for (final p in (list is List ? list : const []).whereType<Map>())
      if (p['src'] is Map)
        _Stock(
          thumb: '${(p['src'] as Map)['medium'] ?? (p['src'] as Map)['small'] ?? (p['src'] as Map)['original']}',
          full: '${(p['src'] as Map)['large2x'] ?? (p['src'] as Map)['large'] ?? (p['src'] as Map)['original']}',
        ),
  ];

  /// The largest MP4 that's still ≤1080p on its short side (pickVideoFile).
  static List<_Stock> _videos(Object? list) {
    String? pick(Object? files) {
      final all = (files is List ? files : const []).whereType<Map>().where((f) => f['link'] != null).toList();
      final mp4 = all.where((f) => '${f['file_type'] ?? ''}'.contains('mp4')).toList();
      final pool = mp4.isNotEmpty ? mp4 : all;
      double short(Map f) {
        final w = (f['width'] as num?)?.toDouble() ?? 0, h = (f['height'] as num?)?.toDouble() ?? 0;
        return w < h ? w : h;
      }

      final fits = pool.where((f) => short(f) <= 1080).toList();
      final ranked = (fits.isNotEmpty ? fits : pool)
        ..sort((a, b) => fits.isNotEmpty ? short(b).compareTo(short(a)) : short(a).compareTo(short(b)));
      return ranked.isEmpty ? null : '${ranked.first['link']}';
    }

    return [
      for (final v in (list is List ? list : const []).whereType<Map>())
        if (pick(v['video_files']) case final full?)
          _Stock(thumb: '${v['image']}', full: full, duration: (v['duration'] as num?)?.toDouble()),
    ];
  }

  // ── Upload ─────────────────────────────────────────────────────────────────

  Future<void> _upload() async {
    final picker = ImagePicker();
    final files = _type == 'video'
        ? [?await picker.pickVideo(source: ImageSource.gallery)]
        : await picker.pickMultiImage(limit: 10);
    if (files.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    try {
      for (final f in files) {
        final url = await widget.brandApi.uploadImage(await f.readAsBytes(), f.name);
        if (url == null) continue;
        _type == 'video' ? await insertVideo(widget.c, url) : await widget.insert.imageUrl(url);
      }
      setState(_reset);
      await _load();
    } catch (err) {
      Toast.error(toUserMessage(err, 'Upload failed.'));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _place(String src, {String? poster, double? duration}) =>
      _type == 'video' ? insertVideo(widget.c, src, poster: poster, duration: duration) : widget.insert.imageUrl(src);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final searching = _query.isNotEmpty;
    final video = _type == 'video';

    Widget tile(String thumb, VoidCallback onTap, {double? duration}) => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: c.gray100,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // A gallery video has no still of its own; show a tile icon.
              if (thumb.isEmpty || (video && !searching))
                Icon(LucideIcons.video, color: c.gray400)
              else
                MediaImage(thumb, cacheWidth: 300),
              if (video)
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      duration != null ? formatSeconds(duration) : '▶',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (!searching && n.metrics.extentAfter < 300) _load();
        return false;
      },
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            sliver: SliverList.list(
              children: [
                TextField(
                  controller: _search,
                  onChanged: _onQuery,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search stock ${video ? 'videos' : 'photos'}',
                    prefixIcon: const Icon(LucideIcons.search, size: 16),
                    suffixIcon: searching
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 16),
                            onPressed: () {
                              _search.clear();
                              _onQuery('');
                            },
                          )
                        : null,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _uploading ? null : _upload,
                  icon: _uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.cloudUpload, size: 16),
                  label: Text(_uploading ? 'Uploading…' : (video ? 'Upload a video' : 'Upload images')),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue600,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'image', label: Text('Images'), icon: Icon(LucideIcons.image, size: 15)),
                    ButtonSegment(value: 'video', label: Text('Videos'), icon: Icon(LucideIcons.video, size: 15)),
                  ],
                  selected: {_type},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _setType(s.first),
                ),
                if (searching) ...[
                  const SizedBox(height: 8),
                  Text('Stock from Pexels', style: TextStyle(fontSize: 11, color: c.gray400)),
                ],
              ],
            ),
          ),
          if (searching) ...[
            if (_stock == null && _stockError == null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              )
            else if (_stockError != null || _stock!.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _stockError ?? 'Nothing found for "$_query".',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: c.gray400),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 120,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: _stock!.length,
                  itemBuilder: (context, i) {
                    final s = _stock![i];
                    return tile(
                      s.thumb,
                      () => _place(s.full, poster: s.thumb, duration: s.duration),
                      duration: s.duration,
                    );
                  },
                ),
              ),
          ] else ...[
            if (_items.isEmpty && !_loading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Your ${video ? 'videos' : 'uploads'} will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: c.gray400),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 120,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _items.length,
                itemBuilder: (context, i) => tile(_items[i].src, () => _place(_items[i].src)),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
