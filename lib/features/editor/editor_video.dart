import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/app_exception.dart';
import '../../core/design/js_values.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import '../brand/brand_api.dart';
import 'design_editor_controller.dart';
import 'editor_sheets.dart';

/// Video elements — port of the web's `(lib)/design/video.js` (the element
/// shape and `clipRange`), `insertVideoUrl` / `replaceVideo` in DesignEditor.jsx
/// and the essentials of `video/EditVideoPanel.jsx` + `VideoTrimBar.jsx`.
///
/// A video is `{type: 'video', src, poster, duration, natW, natH, trimStart,
/// trimEnd, volume, muted, speed, loop, …}`. The stage and every export paint
/// its `poster` (renderer: a video draws as its poster image); playback lives
/// in the Edit video sheet's preview, where trim, speed and sound are set.
///
/// ⚠️ NO POSTER CAPTURE YET. The web grabs a still frame off a `<video>` on
/// insert; the app has no frame-grabbing plugin, so a clip with no poster of
/// its own (a phone upload) paints nothing until one exists. Stock clips and
/// gallery videos with a thumbnail are fine.

const videoSpeeds = [0.25, 0.5, 1.0, 1.5, 2.0];

/// The playable window, in source seconds (`clipRange`). A missing trimEnd
/// means "to the end".
({double start, double end, double length}) clipRange(Map<String, dynamic> el) {
  final duration = numOf(el['duration']) ?? 0;
  final start = math.max(0.0, numOf(el['trimStart']) ?? 0);
  final rawEnd = numOf(el['trimEnd']) ?? 0;
  final end = rawEnd > start ? rawEnd : (duration > start ? duration : start);
  return (start: start, end: end, length: math.max(0, end - start));
}

String formatSeconds(double s) {
  final total = s.isFinite ? s.round() : 0;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

final _videoUrl = RegExp(r'\.(mp4|webm|mov|m4v)(\?|#|$)', caseSensitive: false);

/// Size and length of a hosted video, or null (`videoMeta`).
Future<({double width, double height, double duration})?> videoMeta(String src) async {
  final ctrl = VideoPlayerController.networkUrl(Uri.parse(src));
  try {
    await ctrl.initialize().timeout(const Duration(seconds: 15));
    final v = ctrl.value;
    return (width: v.size.width, height: v.size.height, duration: v.duration.inMilliseconds / 1000);
  } catch (_) {
    return null;
  } finally {
    unawaited(ctrl.dispose());
  }
}

/// Place a hosted video at 60% of the page width, keeping its aspect.
Future<void> insertVideo(DesignEditorController c, String src, {String? poster, double? duration}) async {
  final meta = await videoMeta(src);
  final natW = meta?.width ?? 1920, natH = meta?.height ?? 1080;
  final w = math.min(c.canvasWidth * 0.6, natW);
  final h = w * (natH / natW);
  final len = meta?.duration ?? duration ?? 0;
  c.addElement({
    'type': 'video',
    'src': src,
    // A poster has to be a picture — some gallery rows put the video itself here.
    'poster': poster != null && poster != src && !_videoUrl.hasMatch(poster) ? poster : null,
    'natW': natW,
    'natH': natH,
    'duration': len,
    'trimStart': 0,
    'trimEnd': len > 0 ? len : null,
    'volume': 1,
    'muted': false,
    'speed': 1,
    'x': c.canvasWidth / 2 - w / 2,
    'y': c.canvasHeight / 2 - h / 2,
    'width': w,
    'height': h,
  });
}

/// Replace a video's footage from the phone, keeping its box and look. Trim
/// and crop reset — they described the old clip.
Future<void> replaceVideoFromPhone(DesignEditorController c, String id, BrandApi brandApi) async {
  final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
  if (file == null) return;
  Toast.info('Uploading video…');
  try {
    final url = await brandApi.uploadImage(await file.readAsBytes(), file.name);
    if (url == null) throw AppException('The upload returned no file URL.');
    final meta = await videoMeta(url);
    final len = meta?.duration ?? 0;
    c.updateElement(id, {
      'src': url,
      'poster': null,
      'natW': meta?.width,
      'natH': meta?.height,
      'duration': len,
      'trimStart': 0,
      'trimEnd': len > 0 ? len : null,
      'crop': null,
    });
    Toast.success('Video replaced');
  } catch (err) {
    Toast.error(toUserMessage(err, "Couldn't replace the video."));
  }
}

/// Edit video — preview + trim, speed, sound and repeat.
Future<void> showVideoSheet(BuildContext context, DesignEditorController c) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  barrierColor: Colors.black.withValues(alpha: 0.08),
  backgroundColor: context.colors.surface.withValues(alpha: 1),
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (ctx) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
    child: _VideoSheet(c: c),
  ),
);

class _VideoSheet extends StatefulWidget {
  const _VideoSheet({required this.c});
  final DesignEditorController c;

  @override
  State<_VideoSheet> createState() => _VideoSheetState();
}

class _VideoSheetState extends State<_VideoSheet> {
  VideoPlayerController? _player;
  String? _loadedSrc;
  Timer? _tick;
  bool _committedTrim = false;

  DesignEditorController get c => widget.c;

  @override
  void dispose() {
    _tick?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _ensurePlayer(Map<String, dynamic> el) async {
    final src = '${el['src'] ?? ''}';
    if (src.isEmpty || src == _loadedSrc) return;
    _loadedSrc = src;
    final old = _player;
    final p = VideoPlayerController.networkUrl(Uri.parse(src));
    setState(() => _player = p);
    await old?.dispose();
    try {
      await p.initialize();
      // Backfill the length on clips inserted before it was known.
      if ((numOf(el['duration']) ?? 0) <= 0 && p.value.duration > Duration.zero) {
        final len = p.value.duration.inMilliseconds / 1000;
        c.updateElement(el['id'] as String, {'duration': len, 'trimEnd': len}, record: false);
      }
      await p.seekTo(Duration(milliseconds: (clipRange(el).start * 1000).round()));
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) Toast.error("Couldn't load that video.");
    }
  }

  /// Play the trimmed window at the element's speed and volume, looping back
  /// to the start at its end when Repeat is on.
  Future<void> _togglePlay(Map<String, dynamic> el) async {
    final p = _player;
    if (p == null || !p.value.isInitialized) return;
    if (p.value.isPlaying) {
      await p.pause();
      _tick?.cancel();
      setState(() {});
      return;
    }
    final r = clipRange(el);
    final pos = p.value.position.inMilliseconds / 1000;
    if (pos < r.start || pos >= r.end - 0.05) await p.seekTo(Duration(milliseconds: (r.start * 1000).round()));
    await p.setPlaybackSpeed(nnNum(el['speed'], 1));
    await p.setVolume(truthy(el['muted']) ? 0 : nnNum(el['volume'], 1).clamp(0, 1).toDouble());
    await p.play();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      final live = c.byId(el['id'] as String) ?? el;
      final w = clipRange(live);
      final t = p.value.position.inMilliseconds / 1000;
      if (t >= w.end) {
        if (truthy(live['loop'])) {
          await p.seekTo(Duration(milliseconds: (w.start * 1000).round()));
        } else {
          await p.pause();
          _tick?.cancel();
        }
      }
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final el = c.selected;
        if (el == null || el['type'] != 'video') return const SizedBox(height: 80);
        final id = el['id'] as String;
        _ensurePlayer(el);
        final p = _player;
        final ready = p != null && p.value.isInitialized;
        final duration = math.max(numOf(el['duration']) ?? 0, ready ? p.value.duration.inMilliseconds / 1000 : 0.0);
        final r = clipRange({...el, 'duration': duration});
        final speed = nnNum(el['speed'], 1);
        final muted = truthy(el['muted']);
        final volume = nnNum(el['volume'], 1).clamp(0.0, 1.0);

        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Edit video',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: col.gray800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(LucideIcons.chevronDown, size: 18, color: col.gray400),
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: ready && p.value.aspectRatio > 0 ? p.value.aspectRatio : 16 / 9,
                child: ColoredBox(
                  color: Colors.black,
                  child: ready
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Transform.flip(
                              flipX: truthy(el['flipH']),
                              flipY: truthy(el['flipV']),
                              child: VideoPlayer(p),
                            ),
                            Center(
                              child: IconButton.filled(
                                onPressed: () => _togglePlay(el),
                                style: IconButton.styleFrom(backgroundColor: Colors.black45),
                                icon: Icon(p.value.isPlaying ? LucideIcons.pause : LucideIcons.play, size: 22),
                              ),
                            ),
                          ],
                        )
                      : const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            sectionLabel(
              context,
              'Trim · ${formatSeconds(r.start)} – ${formatSeconds(r.end)} (${formatSeconds(r.length)})',
            ),
            if (duration > 0)
              RangeSlider(
                values: RangeValues(r.start.clamp(0, duration), r.end.clamp(0, duration)),
                max: duration,
                onChanged: (v) {
                  if (v.end - v.start < 0.5) return;
                  if (!_committedTrim) {
                    c.commit();
                    _committedTrim = true;
                  }
                  c.updateElement(id, {'trimStart': v.start, 'trimEnd': v.end}, record: false);
                  // Show the frame under the handle that moved.
                  final at = (v.start - r.start).abs() > 0.01 ? v.start : v.end;
                  p?.seekTo(Duration(milliseconds: (at * 1000).round()));
                },
                onChangeEnd: (_) => _committedTrim = false,
              )
            else
              Text('Loading length…', style: TextStyle(fontSize: 12, color: col.gray400)),
            const SizedBox(height: 8),
            sectionLabel(context, 'Speed'),
            Wrap(
              spacing: 6,
              children: [
                for (final s in videoSpeeds)
                  ChoiceChip(
                    label: Text('${s == s.roundToDouble() ? s.round() : s}×'),
                    selected: speed == s,
                    onSelected: (_) {
                      c.updateElement(id, {'speed': s});
                      p?.setPlaybackSpeed(s);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            sectionLabel(context, 'Sound'),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    c.updateElement(id, {'muted': !muted});
                    p?.setVolume(!muted ? 0 : volume);
                  },
                  icon: Icon(muted ? LucideIcons.volumeX : LucideIcons.volume2, size: 20, color: col.gray700),
                ),
                Expanded(
                  child: Slider(
                    value: muted ? 0 : volume,
                    onChanged: (v) {
                      c.updateElement(id, {'volume': v, 'muted': v == 0}, record: false);
                      p?.setVolume(v);
                    },
                    onChangeStart: (_) => c.commit(),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Play on repeat', style: TextStyle(fontSize: 13.5, color: col.gray800)),
              value: truthy(el['loop']),
              activeThumbColor: AppColors.blue600,
              onChanged: (v) => c.updateElement(id, {'loop': v}),
            ),
          ],
        );
      },
    );
  }
}
