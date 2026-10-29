import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import '../shell/widgets/app_top_bar.dart';

/// One row of `GET /tutorial-videos`. Every field but the link is optional.
class Tutorial {
  Tutorial(Map<String, dynamic> m)
    : id = m['id'],
      title = _s(m['title']) ?? '',
      description = _s(m['description']) ?? '',
      thumbnail = _s(m['thumbnail']),
      source = _s(m['source']),
      videoLink = _s(m['video_link']) ?? '',
      difficulty = _s(m['difficulty']),
      duration = _s(m['duration']),
      views = _s(m['views']),
      feature = _s(m['feature']);

  static String? _s(Object? v) => v == null || '$v'.trim().isEmpty ? null : '$v';

  final Object? id;
  final String title;
  final String description;
  final String? thumbnail;
  final String? source;
  final String videoLink;
  final String? difficulty;
  final String? duration;
  final String? views;
  final String? feature;

  /// The YouTube id out of an embed link (`…/embed/{id}?…`), else null.
  String? get youtubeId {
    final m = RegExp(r'(?:/embed/|youtu\.be/|[?&]v=)([A-Za-z0-9_-]{6,})').firstMatch(videoLink);
    return m?.group(1);
  }

  /// thumbnail → the YouTube still → the web's stock fallback (getThumbnail).
  String get thumb {
    if (thumbnail != null) return thumbnail!;
    final yt = source == 'youtube' ? youtubeId : null;
    if (yt != null) return 'https://img.youtube.com/vi/$yt/mqdefault.jpg';
    return 'https://images.unsplash.com/photo-1611162617474-5b21e879e113?w=400&h=225&fit=crop';
  }

  /// A link the phone can play itself (a plain video file).
  bool get isDirectFile => RegExp(r'\.(mp4|m4v|mov|webm)(\?|#|$)', caseSensitive: false).hasMatch(videoLink);
}

/// `fetchTutorialVideos` in the web's AuthContext. The list arrives as an
/// array, under `videos`, or under `data`.
Future<List<Tutorial>> fetchTutorials(ApiClient api) async {
  final res = await api.get('/tutorial-videos');
  if (!res.ok) throw Exception(res.body['message']?.toString() ?? 'Failed to fetch tutorial videos');
  final raw = res.raw;
  final list = raw is List
      ? raw
      : raw is Map && raw['videos'] is List
      ? raw['videos'] as List
      : raw is Map && raw['data'] is List
      ? raw['data'] as List
      : const [];
  return [
    for (final v in list)
      if (v is Map) Tutorial(Map<String, dynamic>.from(v)),
  ];
}

/// (fg, bg) for a difficulty badge (getDifficultyColor).
(Color, Color) _difficultyColors(String d) => switch (d) {
  'Beginner' => (const Color(0xFF008236), const Color(0xFFDCFCE7)),
  'Intermediate' => (const Color(0xFF1447E6), const Color(0xFFDBEAFE)),
  'Advanced' => (const Color(0xFF8200DB), const Color(0xFFF3E8FF)),
  _ => (const Color(0xFF364153), const Color(0xFFF3F4F6)),
};

/// /help/tutorial-videos — port of `help/tutorial-videos/page.jsx`: search,
/// "All Tutorials (n)", and a card per video that opens it.
///
/// The web plays the link in an `<iframe>` (they're YouTube embeds). The app
/// has no web view, so a tap opens the details sheet and Play hands YouTube
/// links to the YouTube app / browser; a plain video file plays in the sheet.
class TutorialVideosScreen extends StatefulWidget {
  const TutorialVideosScreen({super.key});

  @override
  State<TutorialVideosScreen> createState() => _TutorialVideosScreenState();
}

class _TutorialVideosScreenState extends State<TutorialVideosScreen> {
  List<Tutorial> _videos = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool retry = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final videos = await fetchTutorials(context.read<AuthController>().api);
      if (!mounted) return;
      setState(() => _videos = videos);
      if (retry) Toast.success('Tutorials loaded successfully!');
    } catch (err) {
      final msg = '$err'.replaceFirst('Exception: ', '');
      if (!mounted) return;
      setState(() => _error = msg);
      Toast.error(msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _query.toLowerCase();
    final filtered = [
      for (final t in _videos)
        if (t.title.toLowerCase().contains(q) || t.description.toLowerCase().contains(q)) t,
    ];

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Tutorial Videos', showBack: true),
          Expanded(
            child: ColoredBox(
              color: c.page,
              child: _error != null && !_loading
                  ? _errorView(c)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(16, 18, 16, 28 + MediaQuery.paddingOf(context).bottom),
                        children: [
                          Text(
                            'Tutorial Videos',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.gray900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Master Creative Klux with step-by-step video guides',
                            style: TextStyle(fontSize: 13, color: c.gray600),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 44,
                            child: TextField(
                              enabled: !_loading,
                              onChanged: (v) => setState(() => _query = v),
                              textInputAction: TextInputAction.search,
                              style: const TextStyle(fontSize: 13.5),
                              decoration: InputDecoration(
                                hintText: 'Search tutorials...',
                                prefixIcon: Icon(LucideIcons.search, size: 18, color: c.gray400),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // The heading and grid are known before the fetch
                          // returns; only the thumbnails are pending.
                          if (_loading) ...[
                            for (var i = 0; i < 3; i++)
                              Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                height: 250,
                                decoration: BoxDecoration(color: c.gray200, borderRadius: BorderRadius.circular(14)),
                              ),
                          ] else ...[
                            Text(
                              'All Tutorials (${filtered.length})',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
                            ),
                            const SizedBox(height: 12),
                            if (filtered.isEmpty)
                              _emptyView(c)
                            else
                              for (final t in filtered)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _TutorialCard(tutorial: t, onTap: () => _open(t)),
                                ),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView(AppColors c) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.gray200),
        ),
        child: Column(
          children: [
            Icon(LucideIcons.video, size: 48, color: AppColors.red500.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: AppColors.red500),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _load(retry: true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.blue600),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _emptyView(AppColors c) => Container(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: c.gray200),
    ),
    child: Column(
      children: [
        Icon(LucideIcons.video, size: 48, color: c.gray300),
        const SizedBox(height: 12),
        Text('No tutorials found', style: TextStyle(fontSize: 15, color: c.gray500)),
        const SizedBox(height: 4),
        Text(
          _videos.isEmpty ? 'No tutorials available yet' : 'Try adjusting your search',
          style: TextStyle(fontSize: 12.5, color: c.gray400),
        ),
      ],
    ),
  );

  void _open(Tutorial t) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.black,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _TutorialSheet(tutorial: t),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.fg, required this.bg});
  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
    ),
  );
}

class _TutorialCard extends StatelessWidget {
  const _TutorialCard({required this.tutorial, required this.onTap});
  final Tutorial tutorial;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = tutorial;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.gray100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xFF101828)),
                    MediaImage(t.thumb, cacheWidth: 700),
                    const ColoredBox(color: Color(0x66000000)),
                    Center(
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(color: Color(0xB3000000), shape: BoxShape.circle),
                        child: const Icon(LucideIcons.play, size: 24, color: Colors.white),
                      ),
                    ),
                    if (t.difficulty != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Builder(
                          builder: (_) {
                            final (fg, bg) = _difficultyColors(t.difficulty!);
                            return _Badge(t.difficulty!, fg: fg, bg: bg);
                          },
                        ),
                      ),
                    if (t.duration != null)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xCC000000),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.clock, size: 11, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                t.duration!,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.gray900),
                    ),
                    if (t.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        t.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, height: 1.4, color: c.gray600),
                      ),
                    ],
                    if (t.views != null || t.feature != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (t.views != null) ...[
                            Icon(LucideIcons.eye, size: 12, color: c.gray500),
                            const SizedBox(width: 4),
                            Text(t.views!, style: TextStyle(fontSize: 12, color: c.gray500)),
                          ],
                          const Spacer(),
                          if (t.feature != null)
                            Text(
                              t.feature!,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.blue600),
                            ),
                        ],
                      ),
                    ],
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

/// The web's video modal: the player on top, the title, description and
/// badges under it, on black.
class _TutorialSheet extends StatefulWidget {
  const _TutorialSheet({required this.tutorial});
  final Tutorial tutorial;

  @override
  State<_TutorialSheet> createState() => _TutorialSheetState();
}

class _TutorialSheetState extends State<_TutorialSheet> {
  VideoPlayerController? _player;
  bool _starting = false;

  Tutorial get t => widget.tutorial;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  /// YouTube (and anything else that isn't a plain file) opens outside the
  /// app — the YouTube app when it's installed.
  Future<void> _play() async {
    if (t.videoLink.isEmpty) {
      Toast.error('This tutorial has no video link yet.');
      return;
    }
    if (!t.isDirectFile) {
      final yt = t.youtubeId;
      final url = yt != null ? 'https://www.youtube.com/watch?v=$yt' : t.videoLink;
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) Toast.error("Couldn't open the video.");
      return;
    }
    final existing = _player;
    if (existing != null) {
      existing.value.isPlaying ? await existing.pause() : await existing.play();
      return;
    }
    setState(() => _starting = true);
    final p = VideoPlayerController.networkUrl(Uri.parse(t.videoLink));
    try {
      await p.initialize();
      if (!mounted) {
        p.dispose();
        return;
      }
      p.addListener(_tick);
      setState(() {
        _player = p;
        _starting = false;
      });
      await p.play();
    } catch (err) {
      p.dispose();
      if (mounted) setState(() => _starting = false);
      Toast.error("Couldn't play this video.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    const white = Color(0xFFF9FAFB);
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: 20 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(LucideIcons.x, size: 20, color: Colors.white70),
            ),
          ),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: GestureDetector(
              onTap: _play,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (p != null)
                    Center(
                      child: AspectRatio(aspectRatio: p.value.aspectRatio, child: VideoPlayer(p)),
                    )
                  else
                    MediaImage(t.thumb, cacheWidth: 900),
                  if (p == null || !p.value.isPlaying)
                    Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(color: AppColors.blue600, shape: BoxShape.circle),
                        child: _starting
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(
                                t.isDirectFile ? LucideIcons.play : LucideIcons.externalLink,
                                size: 24,
                                color: Colors.white,
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (p != null)
            VideoProgressIndicator(
              p,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              colors: VideoProgressColors(playedColor: AppColors.blue500, backgroundColor: Colors.white12),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: white),
                ),
                if (t.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(t.description, style: const TextStyle(fontSize: 13.5, height: 1.5, color: white)),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (t.duration != null) _meta(LucideIcons.clock, t.duration!),
                    if (t.views != null) _meta(LucideIcons.eye, '${t.views} views'),
                    if (t.difficulty != null)
                      Builder(
                        builder: (_) {
                          final (fg, bg) = _difficultyColors(t.difficulty!);
                          return _Badge(t.difficulty!, fg: fg, bg: bg);
                        },
                      ),
                    if (t.feature != null) _Badge(t.feature!, fg: const Color(0xFF1447E6), bg: white),
                    if (t.source != null)
                      _Badge(
                        '${t.source![0].toUpperCase()}${t.source!.substring(1)}',
                        fg: const Color(0xFF101828),
                        bg: white,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: const Color(0xFFF9FAFB)),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFFF9FAFB))),
    ],
  );
}
