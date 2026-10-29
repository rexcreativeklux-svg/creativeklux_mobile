import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import 'gallery_api.dart';

/// A file staged for upload. Everything is backed by a local file — a URL
/// load is written to the temp folder first — so the preview and the upload
/// read the same bytes (the web backs each one with a blob: URL for the same
/// reason).
class StagedFile {
  StagedFile({required this.path, required this.name, required this.category, required this.size});
  final String path;
  final String name;
  final String category;
  final int size;
  final key = UniqueKey();
}

/// Subtype → friendly extension, for names built from a content type.
const _extBySubtype = {'jpeg': 'jpg', 'svg+xml': 'svg', 'mpeg': 'mp3', 'quicktime': 'mov'};

/// Port of components/gallery/UploadMediaModal.jsx — stage one or more files,
/// preview them, then hand them to the page's upload pipeline (which
/// validates, uploads, refreshes and toasts). This sheet only stages.
///
/// Sources on a phone: the file browser and the photo library (stand-ins for
/// drag & drop and the device picker), plus "load from a URL". Clipboard
/// paste isn't ported — reading a copied image needs a package the app
/// doesn't have.
Future<void> showUploadMediaSheet(BuildContext context, {required Future<void> Function(List<StagedFile>) onUpload}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.colors.surface.withValues(alpha: 1),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _UploadSheet(onUpload: onUpload),
  );
}

class _UploadSheet extends StatefulWidget {
  const _UploadSheet({required this.onUpload});
  final Future<void> Function(List<StagedFile>) onUpload;

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  final _items = <StagedFile>[];
  Key? _activeKey;
  final _url = TextEditingController();
  bool _urlLoading = false;
  bool _uploading = false;

  StagedFile? get _active => _items.where((i) => i.key == _activeKey).firstOrNull ?? _items.lastOrNull;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// Validate type + size per file (the web's addFiles), then stage.
  void _add(List<({String path, String name, int size, String? mime})> files) {
    final accepted = <StagedFile>[];
    for (final f in files) {
      final category = fileCategory(f.name, mime: f.mime);
      if (category == null) {
        Toast.error("${f.name} isn't a supported file type. Supported: ${describeSupportedTypes()}.");
        continue;
      }
      if (f.size > fileLimits[category]!) {
        Toast.error('${f.name} is too large — max ${fileLimits[category]! ~/ (1024 * 1024)}MB for ${category}s.');
        continue;
      }
      accepted.add(StagedFile(path: f.path, name: f.name, category: category, size: f.size));
    }
    if (accepted.isEmpty || !mounted) return;
    setState(() {
      _items.addAll(accepted);
      _activeKey = accepted.last.key;
    });
  }

  Future<void> _browseFiles() async {
    // FileType.any + our own check, like the web's extension-first rule: an
    // extension filter on Android goes through MIME types and greys files out.
    final res = await FilePicker.pickFiles(type: FileType.any);
    final files = <({String path, String name, int size, String? mime})>[];
    for (final f in res) {
      var path = f.path;
      // A content:// pick has no local path — copy it to the temp folder so
      // the preview and the upload can read it like any other file.
      if (path == null) {
        path = '${Directory.systemTemp.path}/${DateTime.now().microsecondsSinceEpoch}-${f.name}';
        await f.xFile.saveTo(path);
      }
      files.add((path: path, name: f.name, size: f.lengthSync() ?? await f.length() ?? 0, mime: null));
    }
    _add(files);
  }

  Future<void> _browsePhotos() async {
    final picked = await ImagePicker().pickMultipleMedia();
    if (picked.isEmpty) return;
    _add([for (final f in picked) (path: f.path, name: f.name, size: await f.length(), mime: f.mimeType)]);
  }

  /// Fetch a remote file into the temp folder (fetchUrlAsFile). A phone has
  /// no CORS, so the web's /api/proxy-media fallback isn't needed.
  Future<void> _loadUrl() async {
    // No URL contains spaces; some keyboards add one after every ".".
    final url = _url.text.replaceAll(RegExp(r'\s+'), '');
    if (url.isEmpty) return;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
      Toast.error('Enter a valid http(s) URL.');
      return;
    }
    setState(() => _urlLoading = true);
    try {
      final res = await Dio(
        BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 60)),
      ).get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      final bytes = res.data ?? const <int>[];
      if (bytes.isEmpty) throw Exception("Couldn't load the media.");
      final mime = res.headers.value('content-type')?.split(';').first.trim();
      final name = _nameFromUrl(url, mime);
      final path = '${Directory.systemTemp.path}/${DateTime.now().millisecondsSinceEpoch}-$name';
      await File(path).writeAsBytes(bytes);
      _add([(path: path, name: name, size: bytes.length, mime: mime)]);
      _url.clear();
    } catch (err) {
      debugPrint('❌ [upload-sheet] URL load failed: $err');
      // Say WHICH failure — "(network)" alone gave nothing to act on.
      final (title, detail) = switch (err) {
        DioException(response: final r?) => ("Couldn't load the media (${r.statusCode}).", null),
        DioException(type: DioExceptionType.connectionTimeout || DioExceptionType.receiveTimeout) => (
          "Couldn't load the media",
          'The link took too long to answer.',
        ),
        DioException(type: DioExceptionType.connectionError) => (
          "Couldn't load the media",
          "Couldn't reach that address. Check your connection and the link.",
        ),
        DioException(error: FormatException()) => ("Couldn't load the media", "That link isn't a valid web address."),
        DioException(:final message) => ("Couldn't load the media", message),
        _ => ("Couldn't load that URL.", null),
      };
      Toast.error(title, description: detail);
    } finally {
      if (mounted) setState(() => _urlLoading = false);
    }
  }

  static String _nameFromUrl(String url, String? mime) {
    final path = url.split('?').first.split('#').first;
    final base = Uri.decodeComponent(path.substring(path.lastIndexOf('/') + 1));
    if (base.contains('.')) return base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final sub = (mime ?? '').split('/').last;
    final ext = _extBySubtype[sub] ?? (sub.isEmpty ? 'bin' : sub);
    return 'pasted-${DateTime.now().millisecondsSinceEpoch}.$ext';
  }

  void _remove(StagedFile f) => setState(() {
    _items.remove(f);
    if (_activeKey == f.key) _activeKey = _items.lastOrNull?.key;
  });

  Future<void> _upload() async {
    if (_items.isEmpty || _uploading) return;
    setState(() => _uploading = true);
    try {
      await widget.onUpload(List.of(_items));
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      // The pipeline reports its own failures; this only guards an
      // unexpected throw so the sheet never sticks in "Uploading…".
      Toast.error('Upload failed. Please try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = _active;
    return PopScope(
      canPop: !_uploading,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(
                children: [
                  Icon(LucideIcons.cloudUpload, size: 20, color: AppColors.blue600),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Upload media',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.gray900),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _uploading ? null : () => Navigator.of(context).pop(),
                    icon: Icon(LucideIcons.x, size: 19, color: c.gray400),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.gray100),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  // Main preview / empty drop area
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.gray200, width: 1.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: active != null ? _MainPreview(key: active.key, item: active) : _emptyDrop(c),
                  ),
                  if (_items.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 70,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(top: 6, right: 6),
                        children: [
                          for (final f in _items)
                            _Thumb(
                              item: f,
                              active: f.key == active?.key,
                              onSelect: () => setState(() => _activeKey = f.key),
                              onRemove: () => _remove(f),
                            ),
                          // Add more
                          InkWell(
                            onTap: _browseFiles,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: c.gray200, width: 1.5),
                              ),
                              child: Icon(LucideIcons.plus, size: 20, color: c.gray400),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // URL loader
                  Row(
                    children: [
                      Icon(LucideIcons.link2, size: 13, color: c.gray500),
                      const SizedBox(width: 6),
                      Text(
                        'Or load from a URL',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: TextField(
                            controller: _url,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.go,
                            onSubmitted: (_) => _urlLoading ? null : _loadUrl(),
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(fontSize: 13.5),
                            decoration: InputDecoration(
                              hintText: 'https://example.com/image.jpg',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 42,
                        child: FilledButton(
                          onPressed: _url.text.trim().isEmpty || _urlLoading ? null : _loadUrl,
                          style: FilledButton.styleFrom(
                            backgroundColor: c.gray100,
                            foregroundColor: c.gray700,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _urlLoading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: c.gray500),
                                )
                              : const Text('Load'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Footer
            Container(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
              decoration: BoxDecoration(
                color: c.gray50,
                border: Border(top: BorderSide(color: c.gray100)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _uploading ? null : () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: TextStyle(color: c.gray600)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _items.isEmpty || _uploading ? null : _upload,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.blue600,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(LucideIcons.upload, size: 17),
                    label: Text(_uploading ? 'Uploading…' : 'Upload${_items.isNotEmpty ? ' (${_items.length})' : ''}'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyDrop(AppColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
    child: Column(
      children: [
        Icon(LucideIcons.cloudUpload, size: 42, color: c.gray300),
        const SizedBox(height: 10),
        Text(
          'Choose files to upload',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.gray600),
        ),
        const SizedBox(height: 4),
        Text(
          'Images, videos, audio & documents',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: c.gray400),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _browsePhotos,
              icon: const Icon(LucideIcons.images, size: 16),
              label: const Text('Photos & videos'),
            ),
            OutlinedButton.icon(
              onPressed: _browseFiles,
              icon: const Icon(LucideIcons.folderOpen, size: 16),
              label: const Text('Browse files'),
            ),
          ],
        ),
      ],
    ),
  );
}

/// The big preview for the active item, by category (MainPreview).
class _MainPreview extends StatelessWidget {
  const _MainPreview({super.key, required this.item});
  final StagedFile item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxH = MediaQuery.sizeOf(context).height * 0.38;
    switch (item.category) {
      case 'image':
        return ColoredBox(
          color: c.gray50,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Image.file(File(item.path), fit: BoxFit.contain, width: double.infinity),
          ),
        );
      case 'video':
      case 'audio':
        return _StagedPlayer(item: item, maxHeight: maxH);
      default:
        return ColoredBox(
          color: c.gray50,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 36),
            child: Column(
              children: [
                Icon(LucideIcons.fileText, size: 40, color: c.gray400),
                const SizedBox(height: 10),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.gray600),
                ),
                const SizedBox(height: 4),
                Text("Preview isn't available for documents", style: TextStyle(fontSize: 12, color: c.gray400)),
              ],
            ),
          ),
        );
    }
  }
}

/// A local video / audio file with a play button — the web's
/// `<video controls>` / `<audio controls>` in the preview.
class _StagedPlayer extends StatefulWidget {
  const _StagedPlayer({required this.item, required this.maxHeight});
  final StagedFile item;
  final double maxHeight;

  @override
  State<_StagedPlayer> createState() => _StagedPlayerState();
}

class _StagedPlayerState extends State<_StagedPlayer> {
  late final VideoPlayerController _c = VideoPlayerController.file(File(widget.item.path));
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_tick);
    _c.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    }, onError: (Object e) => debugPrint('preview failed: $e'));
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final video = widget.item.category == 'video';
    final playing = _c.value.isPlaying;
    final button = IconButton.filled(
      onPressed: _ready ? () => playing ? _c.pause() : _c.play() : null,
      style: IconButton.styleFrom(backgroundColor: AppColors.blue600),
      icon: Icon(playing ? LucideIcons.pause : LucideIcons.play, size: 18, color: Colors.white),
    );
    if (video) {
      return Container(
        color: Colors.black,
        height: widget.maxHeight.clamp(160.0, 300.0),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_ready) AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c)),
            if (!playing) button,
            if (playing) Positioned.fill(child: GestureDetector(onTap: _c.pause)),
          ],
        ),
      );
    }
    return ColoredBox(
      color: c.gray50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Column(
          children: [
            Icon(LucideIcons.audioLines, size: 40, color: AppColors.blue500),
            const SizedBox(height: 10),
            Text(
              widget.item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.gray600),
            ),
            const SizedBox(height: 10),
            button,
          ],
        ),
      ),
    );
  }
}

/// One thumbnail in the strip: an image thumb or the category icon, with a
/// remove button on its corner.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.item, required this.active, required this.onSelect, required this.onRemove});
  final StagedFile item;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = switch (item.category) {
      'video' => LucideIcons.film,
      'audio' => LucideIcons.audioLines,
      _ => LucideIcons.fileText,
    };
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: onSelect,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: c.gray50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: active ? AppColors.blue500 : Colors.transparent, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: item.category == 'image'
                  ? Image.file(File(item.path), fit: BoxFit.cover, cacheWidth: 160)
                  : Icon(icon, size: 20, color: c.gray400),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: c.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.gray200),
                ),
                child: Icon(LucideIcons.trash2, size: 11, color: c.gray500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
