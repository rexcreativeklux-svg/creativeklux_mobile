import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../shell/widgets/app_top_bar.dart';

/// An asset handed to "Create post" — the web's `selectedAssetsForPost`
/// localStorage rows (`{id, src, fileFormat, alt}`).
class PostNowAsset {
  const PostNowAsset({required this.id, required this.src, this.fileFormat, this.alt});

  final String id;
  final String src;
  final String? fileFormat;
  final String? alt;

  bool get isVideo => fileFormat == 'mp4' || fileFormat == 'mov';
}

/// Port of `(pages)/PostNow/page.jsx` — "Create post": pick media, write the
/// text, set scheduling / story / privacy options and see a feed preview.
///
/// ⚠️ Like the web, this page posts NOTHING: Post / Post All only log the
/// payload, say it worked and go back (the web's `alert` + `router.back()`).
/// The real publish flow is the Publish sheet (`features/publish/`). The
/// web's only links here are from the old-studio pages, which open it in a
/// new tab with the platform / action / assets in localStorage; here they
/// come in as [platform], [schedule] and [assets] (the router reads them
/// from the query string and `extra`).
///
/// Phone layout: the web's three columns (assets · form · preview) stack —
/// an asset strip, the form, then the preview — and the web's sticky action
/// row (Boost · Cancel · Post) is pinned to the bottom of the screen.
class PostNowScreen extends StatefulWidget {
  const PostNowScreen({
    super.key,
    this.platform = 'facebook',
    this.text = '',
    this.schedule = false,
    this.assets = const [],
  });

  static const path = '/PostNow';

  final String platform;
  final String text;

  /// The web's `actionType === 'schedule'`: open with scheduling on.
  final bool schedule;
  final List<PostNowAsset> assets;

  @override
  State<PostNowScreen> createState() => _PostNowScreenState();
}

/// A piece of the post's media: a hosted asset ([url]) or a file picked on
/// the phone ([bytes]; videos keep only their name, there's no frame grab).
class _Media {
  _Media({required this.id, required this.type, this.url, this.bytes});

  final String id;

  /// `photo` | `video`
  final String type;
  final String? url;
  final Uint8List? bytes;
}

/// Everything the form holds, saved per asset so switching assets in the
/// strip keeps each one's own text and options (the web's `assetFormStates`).
class _Form {
  _Form({
    this.text = '',
    this.mediaType = 'photo',
    this.isScheduling = false,
    this.scheduleDate = '',
    this.scheduleTime = '',
    this.boost = false,
    this.collaborators = '',
    this.shareStory = false,
    this.privacy = 'public',
    this.shareOption = 'shareOnce',
  });

  String text;
  String mediaType;
  bool isScheduling;
  String scheduleDate;
  String scheduleTime;
  bool boost;
  String collaborators;
  bool shareStory;
  String privacy;
  String shareOption;

  _Form copy() => _Form(
    text: text,
    mediaType: mediaType,
    isScheduling: isScheduling,
    scheduleDate: scheduleDate,
    scheduleTime: scheduleTime,
    boost: boost,
    collaborators: collaborators,
    shareStory: shareStory,
    privacy: privacy,
    shareOption: shareOption,
  );
}

String _two(int n) => n.toString().padLeft(2, '0');
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _PostNowScreenState extends State<PostNowScreen> {
  final _textCtl = TextEditingController();
  final _collabCtl = TextEditingController();

  late String _platform;
  var _form = _Form();
  List<_Media> _media = [];
  String? _activeAssetId;
  final _saved = <String, _Form>{};
  int _uploadSeq = 0;

  @override
  void initState() {
    super.initState();
    _platform = widget.platform;
    // The first asset is the default media.
    if (widget.assets.isNotEmpty) {
      final first = widget.assets.first;
      _media = [_Media(id: first.id, type: first.isVideo ? 'video' : 'photo', url: first.src)];
      _form.mediaType = first.isVideo ? 'video' : 'photo';
      _activeAssetId = first.id;
    }
    _form.text = widget.text;
    _textCtl.text = widget.text;
    if (widget.schedule) _turnOnScheduling();
  }

  @override
  void dispose() {
    _textCtl.dispose();
    _collabCtl.dispose();
    super.dispose();
  }

  /// Scheduling starts at tomorrow, 11:25 (the web's default).
  void _turnOnScheduling() {
    final t = DateTime.now().add(const Duration(days: 1));
    _form
      ..isScheduling = true
      ..scheduleDate = '${t.year}-${_two(t.month)}-${_two(t.day)}'
      ..scheduleTime = '11:25';
  }

  void _saveActive() {
    final id = _activeAssetId;
    if (id != null) _saved[id] = _form.copy();
  }

  void _selectAsset(PostNowAsset asset) {
    _saveActive();
    setState(() {
      _media = [_Media(id: asset.id, type: asset.isVideo ? 'video' : 'photo', url: asset.src)];
      _activeAssetId = asset.id;
      // Restore that asset's saved form, or start it fresh.
      _form = _saved[asset.id]?.copy() ?? _Form(mediaType: asset.isVideo ? 'video' : 'photo');
      _textCtl.text = _form.text;
      _collabCtl.text = _form.collaborators;
    });
  }

  Future<void> _addPhotos() async {
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty) return;
    final added = [
      for (final f in files) _Media(id: 'upload-${_uploadSeq++}', type: 'photo', bytes: await f.readAsBytes()),
    ];
    if (!mounted) return;
    setState(() {
      _media = [..._media, ...added];
      _form.mediaType = 'photo';
      // New uploads aren't any one asset's media any more.
      _activeAssetId = null;
    });
  }

  Future<void> _addVideo() async {
    final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    setState(() {
      _media = [..._media, _Media(id: 'upload-${_uploadSeq++}', type: 'video')];
      _form.mediaType = 'video';
      _activeAssetId = null;
    });
  }

  void _removeMedia(_Media m) {
    setState(() {
      if (_media.length == 1) _activeAssetId = null;
      _media = _media.where((x) => x.id != m.id).toList();
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_form.scheduleDate) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (d != null) setState(() => _form.scheduleDate = '${d.year}-${_two(d.month)}-${_two(d.day)}');
  }

  Future<void> _pickTime() async {
    final parts = _form.scheduleTime.split(':');
    final initial = parts.length == 2
        ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 11, minute: int.tryParse(parts[1]) ?? 25)
        : const TimeOfDay(hour: 11, minute: 25);
    final t = await showTimePicker(context: context, initialTime: initial);
    if (t != null) setState(() => _form.scheduleTime = '${_two(t.hour)}:${_two(t.minute)}');
  }

  void _close() => context.canPop() ? context.pop() : context.go('/');

  /// The web only logs the post and says it went out (see the class note);
  /// here it only logs.
  void _publish() {
    debugPrint(
      'Publishing post: {platform: [$_platform], text: ${_form.text}, media: ${_media.length}, '
      'isScheduled: ${_form.isScheduling}, ${_form.scheduleDate} ${_form.scheduleTime}, boost: ${_form.boost}, '
      'collaborators: ${_form.collaborators}, shareStory: ${_form.shareStory}, privacy: ${_form.privacy}}',
    );
    _saveActive();
    // ⚠️ NOTHING IS SENT — the web only logs here, then says "Post published
    // successfully!". Telling someone a post went out when it didn't is
    // worse than the gap itself, so the app says so plainly (as Ads Now does)
    // and keeps the form open. Use Publish on a design for a real post.
    Toast.info(
      "Posting from this page isn't available yet",
      description: 'Open a design in My Creations and tap Publish to post it.',
    );
  }

  void _publishAll() {
    _saveActive();
    for (final a in widget.assets) {
      final f = _saved[a.id] ?? _Form(mediaType: a.isVideo ? 'video' : 'photo');
      debugPrint(
        'Publishing/scheduling ${a.id}: {platform: [$_platform], text: ${f.text}, scheduled: ${f.isScheduling}}',
      );
    }
    // Same as [_publish]: nothing is sent, so don't claim it was.
    Toast.info(
      "Posting from this page isn't available yet",
      description: 'Open a design in My Creations and tap Publish to post it.',
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final platformName = _cap(_platform);
    return Scaffold(
      backgroundColor: c.page,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AppTopBar(title: 'Create post', showBack: true),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _assets(context),
                  const SizedBox(height: 16),
                  _Section(
                    title: 'Post to',
                    child: _Box(
                      child: Text(platformName, style: TextStyle(fontSize: 13.5, color: c.gray900)),
                    ),
                  ),
                  _Section(
                    title: 'Media',
                    subtitle: 'Share photos or a video, $_platform posts can\'t exceed 10 photos.',
                    child: _mediaPicker(context),
                  ),
                  _Section(title: 'Text', child: _textField(context)),
                  _Section(
                    title: 'Scheduling Options',
                    trailing: _Toggle(
                      label: 'Set date and time',
                      value: _form.isScheduling,
                      onChanged: (v) => setState(() => v ? _turnOnScheduling() : _form.isScheduling = false),
                    ),
                    child: _form.isScheduling ? _scheduling(context, platformName) : null,
                  ),
                  _Section(
                    title: 'Collaborator',
                    child: _Input(
                      controller: _collabCtl,
                      hint: 'Enter collaborator name',
                      onChanged: (v) => _form.collaborators = v,
                    ),
                  ),
                  _Section(
                    title: 'Share to Your Story',
                    subtitle: 'Share this post to your story for 24 hours.',
                    trailing: _Toggle(
                      label: 'Enable',
                      value: _form.shareStory,
                      onChanged: (v) => setState(() => _form.shareStory = v),
                    ),
                    child: _form.shareStory
                        ? Column(
                            children: [
                              _Radio(
                                title: 'Share Always',
                                body: 'Automatically share this and all future posts to your story.',
                                selected: _form.shareOption == 'shareAlways',
                                onTap: () => setState(() => _form.shareOption = 'shareAlways'),
                              ),
                              _Radio(
                                title: 'Share Once',
                                body: 'Post will be shared to your story once for 24 hours.',
                                selected: _form.shareOption == 'shareOnce',
                                onTap: () => setState(() => _form.shareOption = 'shareOnce'),
                              ),
                            ],
                          )
                        : null,
                  ),
                  _Section(
                    title: 'Privacy Settings',
                    subtitle:
                        'Adjust your privacy settings to control who can see your post in News Feed, in Watch, in '
                        'search results and on your profile.',
                    child: Column(
                      children: [
                        _Radio(
                          title: 'Public',
                          body: 'Anyone can see your post.',
                          selected: _form.privacy == 'public',
                          onTap: () => setState(() => _form.privacy = 'public'),
                        ),
                        _Radio(
                          title: 'Restricted',
                          body: 'Only certain people can see your post.',
                          selected: _form.privacy == 'restricted',
                          onTap: () => setState(() => _form.privacy = 'restricted'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.gray200),
                    ),
                    child: Text('$platformName feed preview', style: TextStyle(fontSize: 13, color: c.gray800)),
                  ),
                  const SizedBox(height: 12),
                  _preview(context),
                ],
              ),
            ),
            _actionBar(context),
          ],
        ),
      ),
    );
  }

  Widget _assets(BuildContext context) {
    final c = context.colors;
    final assets = widget.assets;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Selected Assets',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                ),
              ),
              FilledButton(
                onPressed: assets.isEmpty ? null : _publishAll,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue600,
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(_form.isScheduling ? 'Schedule All' : 'Post All'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (assets.isEmpty)
            Text('No assets selected.', style: TextStyle(fontSize: 12.5, color: c.gray500))
          else
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: assets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final a = assets[i];
                  final active = _activeAssetId == a.id;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _selectAsset(a),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: active ? c.blueTint : null,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: active ? AppColors.blue600 : c.gray200),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: a.isVideo
                                  ? ColoredBox(
                                      color: c.gray500,
                                      child: const Icon(LucideIcons.video, size: 16, color: Colors.white),
                                    )
                                  : MediaImage(a.src, cacheWidth: 120),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Asset ${i + 1}',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.gray700),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _mediaPicker(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _PickButton(icon: LucideIcons.imagePlus, label: 'Add Photo', onTap: _addPhotos),
            const SizedBox(width: 10),
            _PickButton(icon: LucideIcons.video, label: 'Add Video', onTap: _addVideo),
          ],
        ),
        if (_media.isNotEmpty) ...[
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              for (final m in _media)
                Stack(
                  fit: StackFit.expand,
                  children: [
                    _MediaTile(media: m, radius: 8),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: AppColors.red500,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _removeMedia(m),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(LucideIcons.x, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _textField(BuildContext context) {
    final c = context.colors;
    // The web's hashtag / emoji / location / gift / call / message icons are
    // decoration with no handlers; they're kept as plain icons.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            _Input(
              controller: _textCtl,
              hint: "What's on your mind?",
              minLines: 6,
              maxLines: 10,
              onChanged: (v) => setState(() => _form.text = v),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  Icon(LucideIcons.hash, size: 18, color: c.gray400),
                  const SizedBox(width: 8),
                  Icon(LucideIcons.smile, size: 18, color: c.gray400),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final icon in [
              LucideIcons.smile,
              LucideIcons.mapPin,
              LucideIcons.gift,
              LucideIcons.phone,
              LucideIcons.messageCircle,
            ]) ...[Icon(icon, size: 16, color: AppColors.blue600), const SizedBox(width: 22)],
          ],
        ),
      ],
    );
  }

  Widget _scheduling(BuildContext context, String platformName) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Schedule your post for the times when your audience is most active, or manually select a date and time '
          'in the future to publish your post.',
          style: TextStyle(fontSize: 12, color: c.gray500, height: 1.4),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.blue600, borderRadius: BorderRadius.circular(4)),
              child: Text(
                _platform.isEmpty ? '' : _platform[0],
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              platformName,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.gray900),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Box(
                onTap: _pickDate,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_form.scheduleDate, style: TextStyle(fontSize: 13.5, color: c.gray900)),
                    ),
                    Icon(LucideIcons.calendar, size: 16, color: c.gray600),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Box(
                onTap: _pickTime,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_form.scheduleTime, style: TextStyle(fontSize: 13.5, color: c.gray900)),
                    ),
                    Icon(LucideIcons.clock, size: 16, color: c.gray600),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The web's `PreviewPost` — a mock feed post.
  Widget _preview(BuildContext context) {
    final c = context.colors;
    final timestamp = _form.isScheduling && _form.scheduleDate.isNotEmpty && _form.scheduleTime.isNotEmpty
        ? 'Scheduled for ${_form.scheduleDate} at ${_form.scheduleTime}'
        : 'Just now';

    Widget mediaBlock() {
      if (_media.isEmpty) {
        // The web shows a stock placeholder picture here; a neutral block
        // stands in for it.
        return Container(
          height: 260,
          color: c.gray100,
          alignment: Alignment.center,
          child: Icon(LucideIcons.image, size: 40, color: c.gray300),
        );
      }
      if (_media.length == 1) return SizedBox(height: 260, child: _MediaTile(media: _media.first));
      final shown = _media.take(4).toList();
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.6,
        children: [
          for (var i = 0; i < shown.length; i++)
            Stack(
              fit: StackFit.expand,
              children: [
                _MediaTile(media: shown[i]),
                if (i == 3 && _media.length > 4)
                  ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: Text(
                        '+${_media.length - 4}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      );
    }

    Widget action(IconData icon, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: c.gray600),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 13, color: c.gray600)),
      ],
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.gray900, shape: BoxShape.circle),
                  child: Text(
                    'S',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.surface),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'User',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                      ),
                      Text(timestamp, style: TextStyle(fontSize: 11.5, color: c.gray500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_form.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(_form.text, style: TextStyle(fontSize: 13.5, color: c.gray900)),
            )
          else
            // The web's "no text yet" placeholder image, as skeleton lines.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final w in [1.0, 0.85, 0.6]) ...[
                    FractionallySizedBox(
                      widthFactor: w,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          mediaBlock(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                action(LucideIcons.heart, 'Like'),
                action(LucideIcons.messageCircle, 'Comment'),
                action(LucideIcons.share, 'Share'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The web's sticky bottom row: Boost toggle, Cancel, Post / Schedule.
  Widget _actionBar(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.gray200)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              _Switch(value: _form.boost, onChanged: (v) => setState(() => _form.boost = v)),
              const SizedBox(width: 8),
              Text(
                'Boost',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.gray900),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _close,
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.gray800,
                  side: BorderSide(color: c.gray200),
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _publish,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue600,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(_form.isScheduling ? 'Schedule' : 'Post'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

/// One of the form's white cards: a title (and optional subtitle / control on
/// the right), then its body.
class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, this.trailing, this.child});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!, style: TextStyle(fontSize: 11.5, color: c.gray500, height: 1.35)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          if (child != null) ...[const SizedBox(height: 10), child!],
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.gray300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({required this.controller, required this.hint, this.onChanged, this.minLines, this.maxLines = 1});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final int? minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      minLines: minLines,
      maxLines: maxLines,
      style: TextStyle(fontSize: 13.5, color: c.gray900),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(color: c.gray400, fontSize: 13.5),
        filled: true,
        fillColor: c.surface,
        contentPadding: EdgeInsets.fromLTRB(12, 12, 12, maxLines > 1 ? 34 : 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.gray300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.blue600, width: 1.5),
        ),
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.gray50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.gray300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: c.gray600),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13, color: c.gray800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.media, this.radius = 0});

  final _Media media;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Widget body;
    if (media.type == 'video') {
      // No frame grab on the phone, so a picked clip shows as a video tile.
      body = ColoredBox(
        color: c.gray800,
        child: const Center(child: Icon(LucideIcons.circlePlay, size: 26, color: Colors.white)),
      );
    } else if (media.bytes != null) {
      body = Image.memory(media.bytes!, fit: BoxFit.cover, cacheWidth: 600);
    } else {
      body = MediaImage(media.url ?? '', cacheWidth: 600);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: radius > 0
          ? DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: c.gray200),
              ),
              child: body,
            )
          : body,
    );
  }
}

/// The label + switch on the right of a section header.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: context.colors.gray500)),
      const SizedBox(width: 6),
      _Switch(value: value, onChanged: onChanged),
    ],
  );
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Transform.scale(
    scale: 0.8,
    child: Switch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: AppColors.blue600,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}

class _Radio extends StatelessWidget {
  const _Radio({required this.title, required this.body, required this.selected, required this.onTap});

  final String title;
  final String body;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.circleDot : LucideIcons.circle,
              size: 18,
              color: selected ? AppColors.blue600 : c.gray400,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray900),
                  ),
                  Text(body, style: TextStyle(fontSize: 12, color: c.gray600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
