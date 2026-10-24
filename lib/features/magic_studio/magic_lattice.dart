import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../publish/publish_sheet.dart';
import 'magic_studio_types.dart';

/// The Magic Studio canvas — history and this session's results.
/// Port of `magic-studio/HistoryLattice.jsx` (+ `GeneratingArt.jsx`, which it
/// draws its in-flight cells with).
///
/// ⚠️ A SLIVER, not a box. It goes inside the screen's CustomScrollView, so the
/// grid builds lazily — which is what lets video tiles and audio players be torn
/// down as they scroll off instead of a whole backlog of them living at once.
///
/// A hairline grid that runs edge to edge, with generations filling it from the
/// top-left. The lattice is drawn WHETHER OR NOT there is anything in it: an
/// account with no history sees the empty cells, not a placeholder
/// illustration, so the screen reads as a canvas waiting to be filled rather
/// than as a failure.
///
/// ⚠️ THE CELL COUNT IS PADDED TO A MULTIPLE OF 12 — the lowest common multiple
/// of the 2 / 3 / 4 column counts this grid uses across widths. Padding to it
/// means the last row is full at EVERY width, so the lattice never ends in a
/// ragged half-row that reads as a rendering bug. The same multiple doubles as
/// the floor, so an empty account still gets a full screen of cells.
///
/// How the hairlines are drawn: the first row owns the top edge, the first
/// column the left, and every cell its right and bottom. Each line therefore has
/// exactly one author — give all four sides to every cell and each interior line
/// is drawn twice and the grid visibly thickens in the middle.
class MagicLattice extends StatefulWidget {
  const MagicLattice({
    super.key,
    required this.items,
    this.loading = false,
    this.generating = false,
    this.generatingCount = 1,
    this.generatingProgress,
    this.generatingPrompt,
    this.generatingType = 'image',
    this.generatingLabel = 'Generating…',
    this.onDismissGenerating,
    this.onEditGenerating,
    this.onDelete,
    this.removingId,
    this.emptyHint = '',
    this.publishable = true,
    this.bottomPadding = 0,
  });

  /// History (and session results), newest first.
  final List<MagicItem> items;

  /// Initial fetch in flight — a spinner in the first empty cell.
  final bool loading;

  /// A run is in flight — it takes the first cells, so the wait is visible
  /// where the result will land.
  final bool generating;

  /// How many cells that run will fill (the composer's "3x"). One tile per
  /// pending result, so the canvas already shows the shape of what is coming.
  final int generatingCount;

  /// 0–1 when the run can actually report one; null draws the elapsed counter
  /// alone — see [_GeneratingCell] for why that isn't a bar at zero.
  final double? generatingProgress;

  /// What was asked for — the in-flight cell's content when there is one.
  final String? generatingPrompt;

  /// "image" | "video" | "audio" | "text" — decides the in-flight backdrop.
  final String generatingType;

  /// The tool's working copy, for runs with no words of their own.
  final String generatingLabel;

  /// Take the in-flight cells off the canvas. Does NOT cancel the run.
  final VoidCallback? onDismissGenerating;

  /// Put [generatingPrompt] back in the composer to be reworded.
  final VoidCallback? onEditGenerating;
  final ValueChanged<MagicItem>? onDelete;
  final String? removingId;

  /// One quiet line in the first cell when there is nothing at all.
  final String emptyHint;

  /// Whether results may go to the publish sheet (the tool's `publish`).
  final bool publishable;

  /// Room under the last row for the docked composer.
  final double bottomPadding;

  @override
  State<MagicLattice> createState() => _MagicLatticeState();
}

/// See the ⚠️ above — LCM of the 2 / 3 / 4 column counts.
const _cellMultiple = 12;

/// The shape of one cell. The web's is wide (3:2) so a desktop screen shows
/// more row rules; on a phone's two columns that cropped every square and
/// portrait design, so cells here are square.
/// ⚠️ Every cell kind uses it — result, audio, generating, empty. The lattice
/// only reads as a lattice while they all agree on one shape.
const _cellAspect = 1.0;

/// How much of the prompt an in-flight cell shows before "…". The line clamp
/// alone isn't enough: it cuts wherever line two ends, so a 400-word prompt
/// still fills both lines and the tile turns into a wall of text.
const _promptChars = 64;

String _truncate(String text) {
  if (text.length <= _promptChars) return text;
  final cut = text.substring(0, _promptChars);
  // Back off to the last space so the cut doesn't land mid-word — unless that
  // would throw away most of what we kept (one very long token).
  final space = cut.lastIndexOf(' ');
  return '${(space > _promptChars * 0.6 ? cut.substring(0, space) : cut).trimRight()}…';
}

/// "8s" / "1:24" — minutes only once there are any.
String _formatElapsed(int seconds) =>
    seconds < 60 ? '${seconds}s' : '${seconds ~/ 60}:${'${seconds % 60}'.padLeft(2, '0')}';

String _clock(Duration d) => '${d.inMinutes}:${'${d.inSeconds % 60}'.padLeft(2, '0')}';

bool _isMedia(MagicItem item) => item.type == 'image' || item.type == 'video';

/// What a result should be saved as when the URL doesn't say. ⚠️ The fallback
/// carries real weight: a single default of "png" once saved speech as a .png.
const _defaultExt = {'video': 'mp4', 'audio': 'mp3', 'image': 'png'};

String _extFromUrl(String? url, String type) {
  final clean = (url ?? '').split('?').first.split('#').first;
  final m = RegExp(r'\.([a-z0-9]{2,5})$', caseSensitive: false).firstMatch(clean);
  return m != null ? m.group(1)!.toLowerCase() : (_defaultExt[type] ?? 'png');
}

class _MagicLatticeState extends State<MagicLattice> {
  // ── Actions ───────────────────────────────────────────────────────────────

  /// Pictures and clips go to the photo gallery. A sound can't live there, so
  /// an audio take goes out through the share sheet ("Save to Files" etc.).
  Future<void> _download(MagicItem item) async {
    final url = item.mediaUrl;
    if (url == null) return;
    final name = 'magic-${DateTime.now().millisecondsSinceEpoch}';
    Toast.info('Downloading…');
    try {
      if (item.type == 'image') {
        final res = await Dio().get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
        if (!await Gal.hasAccess()) await Gal.requestAccess();
        await Gal.putImageBytes(Uint8List.fromList(res.data ?? const []), name: name);
        Toast.success('Saved to your photo gallery');
        return;
      }
      final path = '${Directory.systemTemp.path}/$name.${_extFromUrl(url, item.type)}';
      await Dio().download(url, path);
      if (item.type == 'video') {
        if (!await Gal.hasAccess()) await Gal.requestAccess();
        await Gal.putVideo(path);
        Toast.success('Saved to your photo gallery');
        unawaited(File(path).delete().catchError((_) => File(path)));
      } else {
        await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
      }
    } catch (err) {
      debugPrint('❌ [magic-studio] download failed: $err');
      Toast.error("Couldn't download that result");
    }
  }

  /// Two conditions, and both are needed: the TOOL makes something publishable,
  /// and THIS result is a picture or a clip with a hosted URL behind it — the
  /// persona generator is a publishing tool that returns text half the time.
  bool _canPublish(MagicItem item) =>
      widget.publishable && (magicToolById(item.tool)?.publish ?? true) && item.url != null && _isMedia(item);

  void _publish(MagicItem item) {
    showPublishSheet(
      context,
      PublishCreative(
        name: magicToolById(item.tool)?.label ?? 'Magic Studio creation',
        // "all" → social platforms AND ad accounts: what a Magic Studio result
        // is for is decided by the person who made it, not the tool.
        category: 'all',
        image: item.mediaUrl,
        isVideo: item.type == 'video',
      ),
    );
  }

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    Toast.success(done);
  }

  void _openMenu(MagicItem item) {
    final actions = <_Action>[
      if (_canPublish(item)) _Action(LucideIcons.send, 'Publish', () => _publish(item)),
      if (item.mediaUrl != null)
        _Action(
          LucideIcons.download,
          item.type == 'audio' ? 'Download' : 'Save to photo gallery',
          () => _download(item),
        ),
      if (item.mediaUrl != null) _Action(LucideIcons.link, 'Copy link', () => _copy(item.mediaUrl!, 'Link copied!')),
      if ((item.content ?? '').isNotEmpty)
        _Action(LucideIcons.copy, 'Copy text', () => _copy(item.content!, 'Copied!')),
      if (widget.onDelete != null)
        _Action(LucideIcons.trash2, 'Delete', () => widget.onDelete!(item), destructive: true),
    ];
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (sheet) => _ActionsSheet(
        title: (item.prompt ?? '').trim().isNotEmpty ? item.prompt!.trim() : magicToolById(item.tool)?.label,
        actions: actions,
        onPick: (a) {
          Navigator.of(sheet).pop();
          a.onTap();
        },
      ),
    );
  }

  void _open(MagicItem item) {
    if (_isMedia(item)) {
      // Keyed off the media subset, so swiping skips a persona's text result
      // instead of opening a blank frame on it.
      final media = widget.items.where((i) => _isMedia(i) && i.mediaUrl != null).toList();
      final index = media.indexWhere((m) => m.id == item.id);
      if (index < 0) return;
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          opaque: false,
          barrierColor: Colors.black,
          pageBuilder: (_, _, _) => _Lightbox(items: media, initial: index, onDownload: _download, onMenu: _openMenu),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
        ),
      );
    } else if (item.type == 'text' && (item.content ?? '').isNotEmpty) {
      // A transcript is the whole point of Audio to Text, and five clamped
      // lines in a tile is not somewhere you can read one.
      _showTextReader(context, item);
    }
  }

  // ── Grid ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    // The generating cells occupy the slots the results will take, so the grid
    // doesn't reshuffle when the run lands.
    final pending = widget.generating ? math.max(1, widget.generatingCount) : 0;
    final used = pending + items.length;
    final total = math.max(_cellMultiple, (used / _cellMultiple).ceil() * _cellMultiple);

    return SliverPadding(
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.crossAxisExtent;
          final columns = w >= 1024
              ? 4
              : w >= 600
              ? 3
              : 2;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: _cellAspect,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              Widget child;
              Key? key;
              if (index < pending) {
                // Index-keyed on purpose: interchangeable placeholders for one batch.
                key = ValueKey('pending-$index');
                child = _GeneratingCell(
                  label: widget.generatingLabel,
                  prompt: widget.generatingPrompt,
                  progress: widget.generatingProgress,
                  type: widget.generatingType,
                  onDismiss: widget.onDismissGenerating,
                  onEdit: widget.onEditGenerating,
                );
              } else if (index < used) {
                final item = items[index - pending];
                key = ValueKey('item-${item.id}');
                child = _ResultCell(
                  item: item,
                  removing: widget.removingId != null && widget.removingId == item.id,
                  onOpen: () => _open(item),
                  onMenu: () => _openMenu(item),
                  onDownload: () => _download(item),
                );
              } else {
                key = ValueKey('empty-${index - used}');
                child = _EmptyCell(
                  first: index == used,
                  hint: items.isEmpty && pending == 0 && !widget.loading ? widget.emptyHint : '',
                  loading: widget.loading,
                );
              }
              return _Hairlines(key: key, index: index, columns: columns, child: child);
            }, childCount: total),
          );
        },
      ),
    );
  }
}

/// Draws the cell's share of the lattice — see the note on [MagicLattice].
class _Hairlines extends StatelessWidget {
  const _Hairlines({super.key, required this.index, required this.columns, required this.child});

  final int index;
  final int columns;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final line = BorderSide(color: context.colors.gray200);
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border(
          top: index < columns ? line : BorderSide.none,
          left: index % columns == 0 ? line : BorderSide.none,
          right: line,
          bottom: line,
        ),
      ),
      child: ClipRect(child: child),
    );
  }
}

class _EmptyCell extends StatelessWidget {
  const _EmptyCell({required this.first, required this.hint, required this.loading});

  final bool first;
  final String hint;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!first) return const SizedBox.expand();
    if (loading) {
      return Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.gray300),
        ),
      );
    }
    // The hint rides in the FIRST cell only, and only while the whole grid is
    // empty — once there is any result the lattice explains itself.
    if (hint.isEmpty) return const SizedBox.expand();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Text(
          hint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, height: 1.5, color: context.colors.gray400),
        ),
      ),
    );
  }
}

// ── Result cells ──────────────────────────────────────────────────────────────

class _ResultCell extends StatelessWidget {
  const _ResultCell({
    required this.item,
    required this.removing,
    required this.onOpen,
    required this.onMenu,
    required this.onDownload,
  });

  final MagicItem item;
  final bool removing;
  final VoidCallback onOpen;
  final VoidCallback onMenu;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tool = magicToolById(item.tool);
    final media = _isMedia(item);

    // ⚠️ AUDIO LEAVES THE TILE ENTIRELY — it is not a picture with a player
    // crammed in, it is the player, with its own download and ⋯.
    if (item.type == 'audio') {
      return _AudioTile(item: item, onMenu: onMenu, onDownload: onDownload, removing: removing);
    }

    Widget body;
    switch (item.type) {
      case 'image':
        body = item.url == null ? ColoredBox(color: c.gray100) : MediaImage(item.url!, cacheWidth: 600);
      case 'video':
        // A poster when the record has one; otherwise the clip itself, muted
        // and only while it's on screen — a phone has no `preload="metadata"`
        // first frame to fall back on, and a black box says nothing.
        body = Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            if (item.thumbnail != null)
              MediaImage(item.thumbnail!, cacheWidth: 600)
            else if (item.mediaUrl != null)
              AutoplayVideo(url: item.mediaUrl!, poster: ''),
            Center(
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(color: Color(0x80000000), shape: BoxShape.circle),
                child: const Icon(LucideIcons.play, size: 17, color: Colors.white),
              ),
            ),
          ],
        );
      default:
        body = Padding(
          padding: const EdgeInsets.fromLTRB(12, 34, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.content ?? '',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, height: 1.45, color: c.gray600),
                ),
              ),
              // Says the tile is a preview, so a clamped transcript reads as
              // "there is more" rather than as all there is.
              Text(
                'Read full text →',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.blue600),
              ),
            ],
          ),
        );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Material(
          color: media ? c.gray100 : c.surface,
          child: InkWell(onTap: onOpen, child: body),
        ),
        // Which tool made it — in a merged grid the answer isn't implied by the
        // screen you're on. Not over pictures: this screen is one tool, so on
        // a phone the pill only covered the art it sat on.
        if (tool != null && !media)
          Positioned(
            left: 6,
            top: 6,
            child: IgnorePointer(
              child: _ToolPill(tool: tool, onMedia: media),
            ),
          ),
        // Always on — there is no hover on a phone.
        Positioned(right: 4, top: 4, child: _MoreButton(onTap: onMenu)),
        if (removing) const _RemovingScrim(),
      ],
    );
  }
}

class _ToolPill extends StatelessWidget {
  const _ToolPill({required this.tool, required this.onMedia});

  final MagicStudioTool tool;
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final fg = onMedia ? Colors.white : context.colors.gray600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: onMedia ? const Color(0x8C000000) : context.colors.gray100,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tool.icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            tool.short,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: fg),
          ),
        ],
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Result actions',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // A small dark disc inside a 40px target — quieter over the art than
        // the white one was.
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(color: Color(0x73000000), shape: BoxShape.circle),
            child: const Icon(LucideIcons.ellipsis, size: 14, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _RemovingScrim extends StatelessWidget {
  const _RemovingScrim();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0x66000000),
    child: Center(
      child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)),
    ),
  );
}

/// An audio result — the player itself, since a sound has no picture of
/// itself to put in a tile. Port of the web's AudioTile/AudioCard `fill` mode,
/// trimmed to what a ~180px phone cell holds: title, a scrub bar, the clock
/// and the transport. The player is only created on first play, so a grid of
/// takes doesn't open a decoder per tile.
class _AudioTile extends StatefulWidget {
  const _AudioTile({required this.item, required this.onMenu, required this.onDownload, required this.removing});

  final MagicItem item;
  final VoidCallback onMenu;
  final VoidCallback onDownload;
  final bool removing;

  @override
  State<_AudioTile> createState() => _AudioTileState();
}

class _AudioTileState extends State<_AudioTile> {
  VideoPlayerController? _player;
  bool _starting = false;

  Future<void> _toggle() async {
    final url = widget.item.mediaUrl;
    if (url == null || _starting) return;
    final p = _player;
    if (p != null) {
      p.value.isPlaying ? await p.pause() : await p.play();
      return;
    }
    setState(() => _starting = true);
    final created = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await created.initialize();
      if (!mounted) {
        created.dispose();
        return;
      }
      created.addListener(_onTick);
      _player = created;
      await created.play();
    } catch (err) {
      debugPrint('audio failed ($url): $err');
      created.dispose();
      Toast.error("Couldn't play that audio");
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player?.removeListener(_onTick);
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = _player?.value;
    final playing = v?.isPlaying ?? false;
    final duration = v?.duration ?? Duration.zero;
    final position = v?.position ?? Duration.zero;
    final total = duration.inMilliseconds;
    final title = (widget.item.prompt ?? '').trim().isNotEmpty ? widget.item.prompt!.trim() : 'Audio';

    return Stack(
      children: [
        Container(
          color: c.gray50,
          padding: const EdgeInsets.fromLTRB(10, 8, 2, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.music, size: 13, color: c.gray400),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.gray800),
                    ),
                  ),
                  _MoreButton(onTap: widget.onMenu),
                ],
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: AppColors.blue600,
                    inactiveTrackColor: c.gray200,
                    thumbColor: AppColors.blue600,
                    padding: EdgeInsets.zero,
                  ),
                  child: SizedBox(
                    height: 20,
                    child: Slider(
                      value: total == 0 ? 0 : (position.inMilliseconds / total).clamp(0.0, 1.0),
                      onChanged: _player == null || total == 0
                          ? null
                          : (f) => _player!.seekTo(Duration(milliseconds: (f * total).round())),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  GestureDetector(
                    onTap: _toggle,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(color: AppColors.blue600, shape: BoxShape.circle),
                      child: _starting
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(playing ? LucideIcons.pause : LucideIcons.play, size: 14, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      total == 0 ? '0:00' : '${_clock(position)} / ${_clock(duration)}',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        color: c.gray500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onDownload,
                    tooltip: 'Download',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(LucideIcons.download, size: 15, color: c.gray500),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (widget.removing) const Positioned.fill(child: _RemovingScrim()),
      ],
    );
  }
}

// ── The in-flight cell ───────────────────────────────────────────────────────

/// YOUR OWN WORDS over a backdrop shaped like the thing being made.
///
/// ⚠️ THE BACKDROP IS PER RESULT TYPE (GeneratingArt) and carries NO progress —
/// it loops the same at second 2 as at second 200. Everything that makes a
/// claim about how far along the run is — the elapsed clock, and the bar on the
/// engines that report a real percentage — is drawn over it. A bar is drawn
/// ONLY when there is a true number behind it; a backend generation reports
/// nothing, and gets the orbiting beam instead.
///
/// ⚠️ THIS CELL IS SUPPOSED TO SHOUT. Blue tint AND an inset ring: two signals,
/// either of which reads at a glance, so starting a run is never invisible.
///
/// The counter runs from mount, which is exactly the life of one run.
class _GeneratingCell extends StatefulWidget {
  const _GeneratingCell({
    required this.label,
    required this.prompt,
    required this.progress,
    required this.type,
    required this.onDismiss,
    required this.onEdit,
  });

  final String label;
  final String? prompt;
  final double? progress;
  final String type;
  final VoidCallback? onDismiss;
  final VoidCallback? onEdit;

  @override
  State<_GeneratingCell> createState() => _GeneratingCellState();
}

class _GeneratingCellState extends State<_GeneratingCell> with SingleTickerProviderStateMixin {
  // A long linear clock the painter reads seconds off — the art's loops have
  // unrelated periods (1.3s, 2.4s, 2.6s…), so no short repeat would wrap
  // cleanly for all of them.
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(hours: 1));
  late final Timer _ticker;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _seconds++));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour reduced motion: a still, legible shape rather than a jitter.
    if (MediaQuery.of(context).disableAnimations) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _ticker.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final progress = widget.progress;
    final hasProgress = progress != null;
    final prompt = (widget.prompt ?? '').trim();
    final reduced = MediaQuery.of(context).disableAnimations;
    final pct = hasProgress ? (progress.clamp(0.0, 1.0) * 100).round() : 0;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: c.blueTint),
        RepaintBoundary(
          child: CustomPaint(
            painter: _GeneratingArtPainter(
              clock: _clock,
              type: widget.type,
              beam: !hasProgress && !reduced,
              plate: c.blueTint,
            ),
          ),
        ),
        // The static inset ring — it carries the state on its own when motion
        // is reduced and the beam is hidden.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: AppColors.blue500.withValues(alpha: 0.25), width: 2)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Says outright what is happening — the art alone is atmosphere.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(color: AppColors.blue600, borderRadius: BorderRadius.circular(99)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 9,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'GENERATING',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              // Its own translucent plate rather than a scrim over the whole
              // tile, so the art keeps its colour everywhere else.
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.surface.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    _truncate(prompt.isNotEmpty ? prompt : widget.label),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, height: 1.3, color: c.gray800),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Take it off the canvas. The run is NOT cancelled — the result still
        // lands in history when it arrives.
        if (widget.onDismiss != null)
          Positioned(
            left: 0,
            top: 0,
            child: _CornerButton(icon: LucideIcons.x, label: 'Hide this from the canvas', onTap: widget.onDismiss!),
          ),
        Positioned(
          left: 9,
          bottom: 7,
          child: Text(
            hasProgress ? '$pct% · ${_formatElapsed(_seconds)}' : _formatElapsed(_seconds),
            style: TextStyle(fontSize: 10.5, color: c.gray400, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        // Puts the prompt back in the composer to be reworded and run again.
        if (widget.onEdit != null && prompt.isNotEmpty)
          Positioned(
            right: 0,
            bottom: 0,
            child: _CornerButton(icon: LucideIcons.pencil, label: 'Edit this prompt', onTap: widget.onEdit!),
          ),
        if (hasProgress)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 3,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 3,
                color: AppColors.blue600,
                backgroundColor: AppColors.blue500.withValues(alpha: 0.2),
                semanticsLabel: widget.label,
              ),
            ),
          ),
      ],
    );
  }
}

class _CornerButton extends StatelessWidget {
  const _CornerButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 14, color: context.colors.gray400),
      ),
    ),
  );
}

/// GeneratingArt.jsx — one backdrop per KIND of result, plus the `.ck-beam`
/// comet that orbits the cell's edge (globals.css). ⚠️ All decoration, and all
/// cheap: a dozen of these can be on screen for minutes, so it's one painter on
/// a shared clock with plain gradients — no blur filters.
class _GeneratingArtPainter extends CustomPainter {
  _GeneratingArtPainter({required this.clock, required this.type, required this.beam, required this.plate})
    : super(repaint: clock);

  final Animation<double> clock;
  final String type;
  final bool beam;
  final Color plate;

  double get _s => clock.value * 3600;

  /// Tailwind's `animate-pulse`: opacity 1 → .5 → 1 over [dur] seconds.
  double _pulse(double dur, [double delay = 0]) => 0.75 + 0.25 * math.cos(2 * math.pi * (_s - delay) / dur);

  /// Deterministic pseudo-random in [0,1) from an index — NOT Random(): the
  /// shape must be the same on every repaint or the waveform is noise.
  static double _jitter(int i) {
    final x = math.sin(i * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (beam) {
      // One comet: opaque at its head, gone within ~90°, rotating backwards
      // once every 2.6s. The plate inset 3px leaves only the edge of it lit.
      final turn = -(_s / 2.6) * 2 * math.pi;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = SweepGradient(
            colors: const [
              Color(0x002563EB),
              Color(0x002563EB),
              Color(0x8C2563EB),
              Color(0xFF2563EB),
              Color(0x002563EB),
            ],
            stops: const [0, 268 / 360, 320 / 360, 352 / 360, 1],
            transform: GradientRotation(turn),
          ).createShader(Rect.fromCenter(center: rect.center, width: size.longestSide, height: size.longestSide)),
      );
      canvas.drawRect(rect.deflate(3), Paint()..color = plate);
    }

    final w = size.width, h = size.height;
    switch (type) {
      case 'video':
        // Four film frames pulsing in turn, with a highlight sweeping across
        // them like a playhead (the web's `shimmer-sweep`).
        const frames = 4, gap = 4.0, frameH = 44.0;
        final left = 12.0, fw = (w - 24 - gap * (frames - 1)) / frames;
        final top = (h - frameH) / 2;
        for (var i = 0; i < frames; i++) {
          final r = Rect.fromLTWH(left + i * (fw + gap), top, fw, frameH);
          canvas.drawRRect(
            RRect.fromRectAndRadius(r, const Radius.circular(2)),
            Paint()..color = const Color(0xFF64748B).withValues(alpha: 0.6 * _pulse(2.4, i * 0.22)),
          );
        }
        final sweep = ((_s / 2) % 1) * (w + 120) - 60;
        canvas.drawRect(
          Rect.fromLTWH(left, top, w - 24, frameH),
          Paint()
            ..shader = LinearGradient(colors: const [Color(0x00FFFFFF), Color(0x59FFFFFF), Color(0x00FFFFFF)])
                .createShader(Rect.fromLTWH(sweep - 40, top, 80, frameH)),
        );
      case 'audio':
        // A bar per slot, heights hashed off the index so the shape is a wave.
        const bars = 14, bw = 5.0, gap = 4.0, boxH = 52.0;
        final total = bars * bw + (bars - 1) * gap;
        final x0 = (w - total) / 2;
        for (var i = 0; i < bars; i++) {
          final bh = boxH * (0.25 + _jitter(i) * 0.7);
          final r = Rect.fromLTWH(x0 + i * (bw + gap), (h - bh) / 2, bw, bh);
          canvas.drawRRect(
            RRect.fromRectAndRadius(r, const Radius.circular(3)),
            Paint()..color = const Color(0xFF6366F1).withValues(alpha: 0.7 * _pulse(1.3, i * 0.09)),
          );
        }
      case 'text':
        // Skeleton lines of uneven width, the last one short — the shape a
        // paragraph actually has.
        const lines = 3, lh = 9.0, gap = 9.0;
        final span = w - 40;
        final y0 = (h - (lines * lh + (lines - 1) * gap)) / 2;
        for (var i = 0; i < lines; i++) {
          final lw = span * (i == lines - 1 ? 0.55 : 0.8 + _jitter(i) * 0.18);
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(20, y0 + i * (lh + gap), lw, lh), const Radius.circular(9)),
            Paint()..color = const Color(0xFF818CF8).withValues(alpha: 0.6 * _pulse(1.9, i * 0.25)),
          );
        }
      default:
        // Three soft colour fields drifting at different speeds — pigment
        // spreading rather than a loading widget.
        void blob(Offset c, double rw, double rh, Color color, double dur, double delay) {
          final r = Rect.fromCenter(center: c, width: rw * 1.6, height: rh * 1.6);
          canvas.drawOval(
            r,
            Paint()
              ..shader = RadialGradient(
                colors: [
                  color.withValues(alpha: color.a * _pulse(dur, delay)),
                  color.withValues(alpha: 0),
                ],
              ).createShader(r),
          );
        }

        blob(Offset(w * 0.18, h * 0.22), w * 0.6, h * 0.6, const Color(0xB360A5FA), 2.8, 0);
        blob(Offset(w * 0.59, h * 0.55), w * 0.5, h * 0.5, const Color(0xA6A78BFA), 3.4, 0.7);
        blob(Offset(w * 0.63, h * 0.65), w * 0.5, h * 0.5, const Color(0xA6FCD34D), 4, 1.4);
    }
  }

  @override
  bool shouldRepaint(_GeneratingArtPainter old) => old.type != type || old.beam != beam || old.plate != plate;
}

// ── ⋯ menu ───────────────────────────────────────────────────────────────────

class _Action {
  const _Action(this.icon, this.label, this.onTap, {this.destructive = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}

/// The result's ⋯ — the web's ResultActionsMenu, as a bottom sheet.
class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({required this.title, required this.actions, required this.onPick});

  final String? title;
  final List<_Action> actions;
  final ValueChanged<_Action> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: c.gray300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          if ((title ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Text(
                title!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, height: 1.4, color: c.gray500),
              ),
            ),
          for (final a in actions)
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: Icon(a.icon, size: 18, color: a.destructive ? AppColors.red600 : c.gray700),
              title: Text(
                a.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: a.destructive ? AppColors.red600 : c.gray900,
                ),
              ),
              onTap: () => onPick(a),
            ),
        ],
      ),
    );
  }
}

// ── Lightbox ─────────────────────────────────────────────────────────────────

/// Full-screen viewer for the image / video results (the web's shared
/// `(components)/Lightbox.jsx`): swipe between them, pinch to zoom a picture,
/// and a clip plays here with sound.
class _Lightbox extends StatefulWidget {
  const _Lightbox({required this.items, required this.initial, required this.onDownload, required this.onMenu});

  final List<MagicItem> items;
  final int initial;
  final ValueChanged<MagicItem> onDownload;
  final ValueChanged<MagicItem> onMenu;

  @override
  State<_Lightbox> createState() => _LightboxState();
}

class _LightboxState extends State<_Lightbox> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    final prompt = (item.prompt ?? '').trim();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final it = widget.items[i];
              return it.type == 'video'
                  ? _LightboxVideo(key: ValueKey(it.id), item: it, active: i == _index)
                  : InteractiveViewer(
                      maxScale: 4,
                      child: Center(child: MediaImage(it.url!, fit: BoxFit.contain)),
                    );
            },
          ),
          SafeArea(
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                  icon: const Icon(LucideIcons.x, color: Colors.white, size: 22),
                ),
                Expanded(
                  child: Text(
                    '${_index + 1} of ${widget.items.length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.white70,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => widget.onDownload(item),
                  tooltip: 'Save to photo gallery',
                  icon: const Icon(LucideIcons.download, color: Colors.white, size: 20),
                ),
                IconButton(
                  onPressed: () => widget.onMenu(item),
                  tooltip: 'More',
                  icon: const Icon(LucideIcons.ellipsis, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
          if (prompt.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  padding: EdgeInsets.fromLTRB(16, 28, 16, 16 + MediaQuery.of(context).padding.bottom),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xB3000000), Color(0x00000000)],
                    ),
                  ),
                  child: Text(
                    prompt,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, height: 1.45, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One clip in the lightbox: plays while it's the page you're on, pauses when
/// you swipe off it, tap to pause / play, scrub along the bottom.
class _LightboxVideo extends StatefulWidget {
  const _LightboxVideo({super.key, required this.item, required this.active});

  final MagicItem item;
  final bool active;

  @override
  State<_LightboxVideo> createState() => _LightboxVideoState();
}

class _LightboxVideoState extends State<_LightboxVideo> {
  VideoPlayerController? _player;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final p = VideoPlayerController.networkUrl(Uri.parse(widget.item.mediaUrl!));
    try {
      await p.initialize();
      await p.setLooping(true);
      if (!mounted) {
        p.dispose();
        return;
      }
      setState(() => _player = p);
      if (widget.active) await p.play();
    } catch (err) {
      debugPrint('lightbox video failed: $err');
      p.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(_LightboxVideo old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) widget.active ? _player?.play() : _player?.pause();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    if (p == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (widget.item.thumbnail != null) MediaImage(widget.item.thumbnail!, fit: BoxFit.contain),
          Center(
            child: _failed
                ? const Text("Couldn't play this clip", style: TextStyle(fontSize: 13, color: Colors.white70))
                : const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
        ],
      );
    }
    return GestureDetector(
      onTap: () => setState(() => p.value.isPlaying ? p.pause() : p.play()),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(aspectRatio: p.value.aspectRatio, child: VideoPlayer(p)),
          ),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: p,
            builder: (_, v, _) => v.isPlaying
                ? const SizedBox.shrink()
                : Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(color: Color(0x80000000), shape: BoxShape.circle),
                      child: const Icon(LucideIcons.play, size: 24, color: Colors.white),
                    ),
                  ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 96 + MediaQuery.of(context).padding.bottom,
            child: VideoProgressIndicator(
              p,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white38,
                backgroundColor: Colors.white12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Text reader ──────────────────────────────────────────────────────────────

/// The full text of a result — a transcript, a persona's copy — in something
/// shaped for reading, with Copy and a .txt to hand. Its own viewer rather than
/// the lightbox, which is built around media.
void _showTextReader(BuildContext context, MagicItem item) {
  final text = item.content ?? '';
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 680),
    builder: (sheet) {
      final c = sheet.colors;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scroll) => Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
                child: Row(
                  children: [
                    Icon(LucideIcons.fileText, size: 16, color: c.gray400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.tool == 'audio_to_text' ? 'Transcript' : 'Result text',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: text));
                        Toast.success('Copied!');
                      },
                      icon: Icon(LucideIcons.copy, size: 14, color: c.gray600),
                      label: Text('Copy', style: TextStyle(fontSize: 12.5, color: c.gray600)),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await SharePlus.instance.share(
                            ShareParams(
                              files: [XFile.fromData(utf8.encode(text), mimeType: 'text/plain')],
                              fileNameOverrides: const ['transcript.txt'],
                            ),
                          );
                        } catch (_) {
                          Toast.error("Couldn't share the text.");
                        }
                      },
                      icon: Icon(LucideIcons.download, size: 14, color: c.gray600),
                      label: Text('.txt', style: TextStyle(fontSize: 12.5, color: c.gray600)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheet).pop(),
                      tooltip: 'Close',
                      icon: Icon(LucideIcons.x, size: 18, color: c.gray400),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.gray200),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: SelectableText(text, style: TextStyle(fontSize: 14, height: 1.6, color: c.gray700)),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
