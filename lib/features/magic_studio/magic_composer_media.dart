import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../editor/editor_api.dart' show EditorApi, GalleryItem;
import '../editor/magic_panel/magic_history_api.dart' show pickHostedUrl;

/// Where the composer's source media comes from — the phone stand-in for the
/// web's MediaPickerModal (Library tab + its upload button), opened by the
/// image / video / voice-track / logo / audio buttons in the toolbar.
///
/// ⚠️ EVERYTHING ENDS UP HOSTED. The backend reads `image_url` / `video_url` /
/// `audio_url` server-side, so a file from the phone is uploaded to the
/// gallery (`POST /gallery`) first and its hosted URL is what comes back —
/// the same rule as the web, where the picker's Library tab is the upload path.
///
/// ⚠️ NO PEXELS SEARCH TAB. The web's search tab is a Pexels image search
/// proxied through the web app; the composer here offers the phone and the
/// gallery, which cover "a picture I have".
///
/// ⚠️ NO AUDIO FROM THE PHONE YET. There is no file picker in this app
/// (`file_picker` isn't a dependency) and no recorder, so a voice track or a
/// take to transcribe has to already be in the gallery — the phone row says
/// "coming soon" instead.

/// A picked, hosted file.
class MagicPickedMedia {
  const MagicPickedMedia({required this.url, this.name = ''});
  final String url;
  final String name;
}

/// "image" | "video" | "audio".
Future<MagicPickedMedia?> pickMagicMedia(
  BuildContext context, {
  required ApiClient api,
  required String kind,
  required String title,
  String? emptyHint,
}) {
  return showModalBottomSheet<MagicPickedMedia>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _MediaSourceSheet(api: api, kind: kind, title: title, emptyHint: emptyHint),
  );
}

/// The gallery's own cap on video (FILE_LIMITS in the web's utils/helpers.js).
const _maxVideoBytes = 50 * 1024 * 1024;

class _MediaSourceSheet extends StatefulWidget {
  const _MediaSourceSheet({required this.api, required this.kind, required this.title, this.emptyHint});
  final ApiClient api;
  final String kind;
  final String title;
  final String? emptyHint;

  @override
  State<_MediaSourceSheet> createState() => _MediaSourceSheetState();
}

class _MediaSourceSheetState extends State<_MediaSourceSheet> {
  late final _gallery = EditorApi(widget.api);
  final List<GalleryItem> _items = [];
  var _page = 0;
  var _more = true;
  var _loading = false;
  var _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_more) return;
    setState(() => _loading = true);
    final (rows, more) = await _gallery.gallery(type: widget.kind, page: _page + 1);
    if (!mounted) return;
    setState(() {
      _page++;
      _items.addAll(rows);
      _more = more;
      _loading = false;
    });
  }

  Future<void> _fromPhone() async {
    if (widget.kind == 'audio') {
      Toast.info(
        'Uploading audio from your phone is coming soon',
        description: 'Pick a file from your gallery for now.',
      );
      return;
    }
    final picker = ImagePicker();
    final file = widget.kind == 'video'
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048);
    if (file == null || !mounted) return;
    if (widget.kind == 'video' && await File(file.path).length() > _maxVideoBytes) {
      Toast.error('That video is too large. Please choose one under 50 MB.');
      return;
    }
    setState(() => _uploading = true);
    final res = await widget.api.post(
      '/gallery',
      body: FormData.fromMap({'file': await MultipartFile.fromFile(file.path, filename: file.name)}),
      timeout: const Duration(minutes: 5),
    );
    if (!mounted) return;
    final url = res.ok ? pickHostedUrl(res.raw) : null;
    setState(() => _uploading = false);
    if (url == null) {
      Toast.error("Couldn't upload that ${widget.kind}. Please try again.");
      return;
    }
    Navigator.pop(context, MagicPickedMedia(url: url, name: file.name));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final phoneLabel = switch (widget.kind) {
      'video' => 'Upload a video from your phone',
      'audio' => 'Upload audio from your phone',
      _ => 'Upload a photo from your phone',
    };
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              widget.title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.gray900),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: c.gray50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: c.gray200),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _uploading ? null : _fromPhone,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      if (_uploading)
                        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Icon(LucideIcons.upload, size: 18, color: c.gray600),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _uploading ? 'Uploading…' : phoneLabel,
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray900),
                        ),
                      ),
                      if (widget.kind == 'audio') Text('Coming soon', style: TextStyle(fontSize: 11, color: c.gray400)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'FROM YOUR GALLERY',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: c.gray400),
            ),
          ),
          Expanded(child: _galleryView(context)),
        ],
      ),
    );
  }

  Widget _galleryView(BuildContext context) {
    final c = context.colors;
    if (_items.isEmpty) {
      return Center(
        child: _loading
            ? const CircularProgressIndicator(strokeWidth: 2)
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  widget.emptyHint ?? 'Nothing in your gallery yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: c.gray500),
                ),
              ),
      );
    }
    void pick(GalleryItem g) => Navigator.pop(context, MagicPickedMedia(url: g.src, name: g.name));
    final loadMore = _more
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(onPressed: _loadMore, child: const Text('Load more')),
            ),
          )
        : const SizedBox(height: 16);

    if (widget.kind == 'audio') {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final g in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: c.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: c.gray200),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => pick(g),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    child: Row(
                      children: [
                        Icon(LucideIcons.audioLines, size: 16, color: AppColors.blue600),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            g.name.isNotEmpty ? g.name : 'Audio file',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: c.gray900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          loadMore,
        ],
      );
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid.count(
            crossAxisCount: 3,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (final g in _items)
                GestureDetector(
                  onTap: () => pick(g),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: widget.kind == 'video'
                        ? ColoredBox(
                            color: Colors.black,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                const Center(child: Icon(LucideIcons.fileVideo, size: 22, color: Colors.white70)),
                                Positioned(
                                  left: 6,
                                  right: 6,
                                  bottom: 5,
                                  child: Text(
                                    g.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : MediaImage(g.src, cacheWidth: 240),
                  ),
                ),
            ],
          ),
        ),
        SliverToBoxAdapter(child: loadMore),
      ],
    );
  }
}

// ── Video metadata (StudioComposer.jsx `probeVideo`) ─────────────────────────

/// What the player can tell us about a hosted clip, or null.
///
/// ⚠️ IT REPORTS, IT NEVER REFUSES — there's no duration limit anything here
/// knows, and a clip whose header can't be read still generates fine. The 8s
/// timeout keeps a source that never answers from holding a player open.
Future<({Duration duration, Size size})?> probeMagicVideo(String url) async {
  final controller = VideoPlayerController.networkUrl(Uri.parse(url));
  try {
    await controller.initialize().timeout(const Duration(seconds: 8));
    return (duration: controller.value.duration, size: controller.value.size);
  } catch (_) {
    return null;
  } finally {
    unawaited(controller.dispose());
  }
}

/// Seconds → "1:04"; blank for anything unreadable.
String formatMagicDuration(Duration? d) {
  if (d == null || d <= Duration.zero) return '';
  final s = (d.inMilliseconds / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

// ── Audio preview ────────────────────────────────────────────────────────────

/// A play/pause button for a hosted voice track — the phone stand-in for the
/// web's `<audio controls>`: what matters before minutes of render is that
/// this is the RIGHT take, and the only way to know is to hear it.
/// `video_player` plays audio URLs too, so no extra package is needed.
class MagicAudioPlayButton extends StatefulWidget {
  const MagicAudioPlayButton({super.key, required this.url});
  final String url;

  @override
  State<MagicAudioPlayButton> createState() => _MagicAudioPlayButtonState();
}

class _MagicAudioPlayButtonState extends State<MagicAudioPlayButton> {
  VideoPlayerController? _controller;
  var _loading = false;

  @override
  void didUpdateWidget(MagicAudioPlayButton old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _release();
  }

  void _release() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    _controller = null;
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    final c = _controller;
    if (c != null) {
      if (c.value.isPlaying) {
        await c.pause();
      } else {
        if (c.value.position >= c.value.duration) await c.seekTo(Duration.zero);
        await c.play();
      }
      return;
    }
    setState(() => _loading = true);
    final next = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await next.initialize();
      if (!mounted) {
        unawaited(next.dispose());
        return;
      }
      next.addListener(_onTick);
      _controller = next;
      await next.play();
    } catch (_) {
      unawaited(next.dispose());
      Toast.error("Couldn't play that audio.");
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = _controller?.value.isPlaying ?? false;
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: playing ? 'Pause' : 'Play',
        onPressed: _loading ? null : _toggle,
        style: IconButton.styleFrom(backgroundColor: context.colors.blueTint),
        icon: _loading
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(playing ? LucideIcons.pause : LucideIcons.play, size: 15, color: AppColors.blue600),
      ),
    );
  }
}
