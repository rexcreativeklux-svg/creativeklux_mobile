import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/media.dart';
import '../../../core/ui/toast.dart';
import '../../studio/magic_design.dart';
import 'magic_history_api.dart';
import 'magic_history_list.dart';
import 'magic_media_panel.dart' show MagicGenerateButton, MagicResultsGrid;
import 'magic_option_body.dart';
import 'magic_tools.dart';

/// One LIVE Magic Studio tool inside the editor panel (Images / Variations /
/// Persona) — port of `panels/magic/MagicToolTab.jsx`.
///
/// The same machine the /magic-studio page runs on: the tool's config (prompt
/// copy, option cards, validation, payload → POST /magic-studio/generate, see
/// magic_tools.dart), the run follower (`MagicApi.run`, magic_design.dart) and
/// the backend history (POST /magic-studio/history). A result made here shows
/// up in the Magic Studio page's history too, and vice versa.
///
/// Editor-specific, as on the web:
///   • Generate / History views; generating never flips the view.
///   • A finished generation goes straight onto the design (and into History).
///   • Image to Variations can take the image selected on the canvas.
///
/// ⚠️ THE RUN LIVES IN THIS STATE. Closing the panel mid-run stops following it
/// (`isActive` = mounted) — the backend still finishes, and the result is then
/// in History (whose pending tile picks the wait back up on reopen), but it is
/// NOT auto-inserted. Same trade-off as the web, where unmounting cancels the
/// watch, not the generation.
class MagicToolTab extends StatefulWidget {
  const MagicToolTab({
    super.key,
    required this.config,
    required this.api,
    required this.onInsertImage,
    required this.onInsertVideo,
    this.selectedImageSrc,
  });

  final MagicToolConfig config;
  final ApiClient api;
  final Future<void> Function(String url) onInsertImage;
  final Future<void> Function(String url) onInsertVideo;
  final String? Function()? selectedImageSrc;

  @override
  State<MagicToolTab> createState() => _MagicToolTabState();
}

class _MagicToolTabState extends State<MagicToolTab> {
  late final _history = MagicHistoryApi(widget.api);
  late final Map<String, String> _values = widget.config.seedValues();
  final _random = Random();

  var _historyView = false;
  String? _openOption;
  String? _error;
  var _generating = false;

  // Primary inputs.
  final _text = TextEditingController();
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _occupation = TextEditingController();
  ({String url, Uint8List? bytes})? _image;
  var _preparingImage = false;

  /// This session's newest results — the web's "Created by Magic Studio" strip,
  /// so a result can be placed again without digging through History.
  List<String> _results = const [];

  // History (useMagicHistory.js).
  List<MagicHistoryItem> _records = const [];
  var _historyLoading = true;
  String? _removingId;
  var _fetchToken = 0;
  Timer? _poll;

  MagicToolConfig get _config => widget.config;

  @override
  void initState() {
    super.initState();
    _refreshHistory();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    _name.dispose();
    _age.dispose();
    _occupation.dispose();
    super.dispose();
  }

  // ── History ────────────────────────────────────────────────────────────────

  List<MagicHistoryItem> get _items => _records.where((r) => !r.pending).toList();

  /// Runs still in flight — and recent enough to be believed. The age cutoff is
  /// what stops a crashed job haunting the tool with a loading tile forever.
  List<MagicHistoryItem> get _pending =>
      _records.where((r) => r.pending && magicElapsedSince(r.startedAt ?? r.createdAt) < magicStaleAfter).toList();

  /// [quiet] skips the loading flag — the poll re-fetches every few seconds and
  /// must not blink the spinner/empty state for the whole wait.
  Future<void> _refreshHistory({bool quiet = false}) async {
    final token = ++_fetchToken;
    if (!quiet) setState(() => _historyLoading = true);
    final list = await _history.list(_config.historyTool);
    if (!mounted || token != _fetchToken) return;
    setState(() {
      _records = list ?? const [];
      _historyLoading = false;
    });
    _schedulePoll();
  }

  /// While anything is still running, poll on the shared escalating schedule,
  /// paced off the OLDEST run (a job started minutes ago resumes unhurried).
  void _schedulePoll() {
    _poll?.cancel();
    final pending = _pending;
    if (pending.isEmpty) return;
    final oldest = pending.map((r) => magicElapsedSince(r.startedAt ?? r.createdAt)).reduce((a, b) => a > b ? a : b);
    _poll = Timer(magicNextPollDelay(oldest), () {
      if (mounted) _refreshHistory(quiet: true);
    });
  }

  /// Delete one generation — every tile of its batch goes with it, because one
  /// record stands behind them. Optimistic; restored + re-synced on failure.
  Future<void> _remove(MagicHistoryItem item) async {
    if (_removingId != null) return;
    final prev = _records;
    setState(() {
      _removingId = item.generationId;
      _records = _records.where((r) => r.generationId != item.generationId).toList();
    });
    final err = await _history.delete(item.generationId);
    if (!mounted) return;
    setState(() => _removingId = null);
    if (err == null) {
      Toast.success('Deleted');
    } else {
      Toast.error(err);
      setState(() => _records = prev);
      _refreshHistory(quiet: true);
    }
  }

  /// The editor's one media-insert rule (useMediaInsert.js): images and videos
  /// go on the page; anything else says why it can't.
  Future<void> _pick(MagicHistoryItem item) async {
    final url = item.url;
    if (item.type != 'image' && item.type != 'video') {
      Toast.info(
        item.type == 'audio' ? 'Audio can’t be added to a design yet.' : 'That file can’t be added to a design.',
      );
      return;
    }
    if (url == null) {
      Toast.error('That ${item.type} has no usable URL.');
      return;
    }
    await (item.type == 'video' ? widget.onInsertVideo(url) : widget.onInsertImage(url));
  }

  // ── Source image (Image to Variations) ─────────────────────────────────────
  // The backend needs a hosted `image_url`, so anything local is uploaded first.

  Future<String?> _host(Uint8List bytes, String name) async {
    final hosted = await _history.uploadImage(bytes, name);
    if (hosted == null) {
      Toast.error('Couldn’t prepare that image.');
    } else {
      Toast.success('Image ready');
    }
    return hosted;
  }

  Future<void> _uploadImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    setState(() => _preparingImage = true);
    final bytes = await file.readAsBytes();
    final hosted = await _host(bytes, file.name);
    if (!mounted) return;
    setState(() {
      _preparingImage = false;
      if (hosted != null) _image = (url: hosted, bytes: bytes);
    });
  }

  Future<void> _useSelected() async {
    final src = widget.selectedImageSrc?.call();
    if (src == null || src.isEmpty) {
      Toast.info('Select an image on the canvas first');
      return;
    }
    // Already hosted (a saved design's images are CDN URLs) → use it as-is.
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(src)) {
      setState(() => _image = (url: src, bytes: null));
      return;
    }
    // A data: image the user just dropped in isn't reachable by the backend
    // yet — push it to the gallery to get a URL.
    final data = src.startsWith('data:') ? UriData.parse(src) : null;
    if (data == null) {
      Toast.error('Couldn’t read the selected image. Try uploading it instead.');
      return;
    }
    setState(() => _preparingImage = true);
    final bytes = data.contentAsBytes();
    final ext = data.mimeType.split('/').last;
    final hosted = await _host(bytes, 'canvas-image.${ext.isEmpty ? 'png' : ext}');
    if (!mounted) return;
    setState(() {
      _preparingImage = false;
      if (hosted != null) _image = (url: hosted, bytes: bytes);
    });
  }

  // ── Inspire + generate ─────────────────────────────────────────────────────

  void _inspire() {
    if (_config.input == MagicInput.persona) {
      final list = _config.personaInspire;
      if (list.isEmpty) return;
      final roll = list[_random.nextInt(list.length)];
      setState(() {
        _name.text = _values['personaName'] = roll.name;
        _occupation.text = _values['personaOccupation'] = roll.occupation;
        _values['personaTone'] = roll.tone;
      });
      return;
    }
    final list = _config.inspire;
    if (list.isEmpty) return;
    setState(() => _text.text = list[_random.nextInt(list.length)]);
  }

  String? get _primaryInput => switch (_config.input) {
    MagicInput.prompt => _text.text,
    MagicInput.image => _image?.url,
    MagicInput.persona => null,
  };

  Future<void> _generate() async {
    if (_generating || _preparingImage) return;
    final input = _primaryInput;
    final err = validateMagicInput(_config.id, input: input, values: _values);
    if (err != null) {
      setState(() => _error = err);
      Toast.error(err);
      return;
    }
    setState(() {
      _error = null;
      _generating = true;
      _openOption = null;
    });

    final payload = buildMagicPayload(_config.id, input: input, values: _values);
    final outcome = await MagicApi(widget.api).run(
      payload,
      isActive: () => mounted,
      onStillWorking: () => Toast.info('Your result is generating — this can take a minute…'),
    );
    if (!mounted) return;

    switch (outcome) {
      case MagicDone(:final urls):
        setState(() => _results = urls);
        // Every image lands on the design, in order. Counted off the RESULT,
        // not the request — the backend may cap or partially fail.
        for (final url in urls) {
          await widget.onInsertImage(url);
        }
        if (urls.isEmpty) {
          Toast.info('Nothing came back — try adjusting your inputs.');
        } else {
          Toast.success(urls.length > 1 ? '${urls.length} generated successfully!' : 'Generated successfully!');
        }
      case MagicFailed(:final message) || MagicRefused(:final message):
        setState(() => _error = message);
        Toast.error(message);
      case MagicTimedOut():
        // Not an error: the run is still going and will be in History. "Try
        // again" here would charge someone twice for the same picture.
        Toast.info('This is taking longer than usual — it’ll be in your history as soon as it’s done.');
      case MagicCancelled():
        break;
    }
    if (!mounted) return;
    setState(() => _generating = false);
    _refreshHistory(quiet: true);
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final waiting = _generating || _pending.isNotEmpty;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          sliver: SliverToBoxAdapter(child: _viewSwitch(context, waiting)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: _historyView
              ? SliverMainAxisGroup(
                  slivers: magicHistorySlivers(
                    context,
                    items: _items,
                    loading: _historyLoading,
                    generating: waiting,
                    removingId: _removingId,
                    onPick: _pick,
                    onDelete: _remove,
                  ),
                )
              : SliverList.list(children: _generateView(context)),
        ),
      ],
    );
  }

  Widget _viewSwitch(BuildContext context, bool waiting) {
    final c = context.colors;
    Widget seg(String label, bool history) {
      final on = _historyView == history;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _historyView = history),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: on ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: on ? const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))] : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: on ? AppColors.blue600 : c.gray500,
                  ),
                ),
                if (history && waiting) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.blue500),
                  ),
                ] else if (history && _items.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    '(${_items.length})',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: c.gray400),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [seg('Generate', false), seg('History', true)]),
    );
  }

  List<Widget> _generateView(BuildContext context) {
    final c = context.colors;
    const gap = SizedBox(height: 16);
    return [
      switch (_config.input) {
        MagicInput.prompt => _promptInput(context),
        MagicInput.image => _imageInput(context),
        MagicInput.persona => _personaFields(context),
      },
      for (final option in _config.optionRows) ...[
        gap,
        MagicOptionRow(
          option: option,
          value: _values[option.key],
          open: _openOption == option.key,
          onToggle: () => setState(() => _openOption = _openOption == option.key ? null : option.key),
          onSelect: (v, {keepOpen = false}) => setState(() {
            _values[option.key] = v;
            if (!keepOpen) _openOption = null;
          }),
        ),
      ],
      if (_error != null) ...[
        gap,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c.redTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.red500.withValues(alpha: 0.3)),
          ),
          child: Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.red600)),
        ),
      ],
      gap,
      MagicGenerateButton(
        label: _config.generateLabel,
        generating: _generating,
        onPressed: _generating || _preparingImage ? null : _generate,
      ),
      const SizedBox(height: 8),
      Text(
        'Results drop straight onto your design and are saved to History.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: c.gray400),
      ),
      if (_generating || _results.isNotEmpty) ...[
        gap,
        MagicResultsGrid(
          urls: _results,
          generating: _generating,
          skeletons: 1,
          onPick: (url) => widget.onInsertImage(url),
        ),
      ],
    ];
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.gray500),
    ),
  );

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  Widget _smallButton(BuildContext context, String label, VoidCallback? onTap, {IconData? icon}) {
    final c = context.colors;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 13),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: c.gray600,
        side: BorderSide(color: c.gray200),
        textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _promptInput(BuildContext context) {
    final c = context.colors;
    final max = _config.maxLength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, _config.label),
        TextField(
          controller: _text,
          minLines: 4,
          maxLines: 6,
          maxLength: max,
          onChanged: (_) => setState(() {}),
          style: TextStyle(fontSize: 14, color: c.gray700),
          decoration: _decoration(_config.placeholder).copyWith(
            counterText: '',
            hintStyle: TextStyle(fontSize: 12, color: c.gray400),
            hintMaxLines: 3,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (_config.inspire.isNotEmpty) _smallButton(context, 'Inspire me', _inspire, icon: LucideIcons.sparkles),
            const Spacer(),
            if (max != null) Text('${_text.text.length}/$max', style: TextStyle(fontSize: 10, color: c.gray400)),
          ],
        ),
      ],
    );
  }

  Widget _imageInput(BuildContext context) {
    final c = context.colors;
    final image = _image;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, _config.label),
        if (image != null)
          Container(
            height: 128,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.blue500, width: 2),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image.bytes != null)
                  Image.memory(image.bytes!, fit: BoxFit.cover)
                else
                  MediaImage(image.url, cacheWidth: 600),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Semantics(
                    label: 'Remove source image',
                    button: true,
                    child: GestureDetector(
                      onTap: () => setState(() => _image = null),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(LucideIcons.x, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          InkWell(
            onTap: _preparingImage ? null : _uploadImage,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.gray200, width: 2),
              ),
              child: Column(
                children: [
                  if (_preparingImage)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue500),
                    )
                  else
                    Icon(LucideIcons.upload, size: 20, color: c.gray500),
                  const SizedBox(height: 6),
                  Text(
                    _preparingImage ? 'Preparing…' : 'Upload an image',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.blue600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _config.helper ?? 'Choose an image from your device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: c.gray400),
                  ),
                ],
              ),
            ),
          ),
        // Straight from the design: the image selected on the canvas.
        if (widget.selectedImageSrc != null) ...[
          const SizedBox(height: 8),
          _smallButton(context, 'Use selected image', _preparingImage ? null : _useSelected, icon: LucideIcons.layers),
        ],
      ],
    );
  }

  Widget _chip(BuildContext context, String label, bool active, VoidCallback onTap, {IconData? icon}) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? c.blueTint : c.gray50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppColors.blue500 : c.gray200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: active ? AppColors.blue600 : c.gray600),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.blue600 : c.gray600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Name / age / occupation / tone — the four things the persona payload needs
  /// (MagicToolTab.jsx `PersonaFields`). Choices come from the shared config.
  Widget _personaFields(BuildContext context) {
    final age = _values['personaAge'] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, 'Persona name'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _name,
                onChanged: (v) => _values['personaName'] = v,
                decoration: _decoration('e.g. Jane Doe'),
              ),
            ),
            const SizedBox(width: 8),
            _smallButton(context, 'Inspire', _inspire, icon: LucideIcons.sparkles),
          ],
        ),
        const SizedBox(height: 12),
        _label(context, 'Age'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final a in _config.ageGroups)
              _chip(
                context,
                a.label,
                age == a.value,
                () => setState(() {
                  _values['personaAge'] = a.value;
                  _age.clear();
                }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _age,
          keyboardType: TextInputType.number,
          onChanged: (v) => setState(() => _values['personaAge'] = v),
          decoration: _decoration('Or exact age (e.g. 32)'),
        ),
        const SizedBox(height: 12),
        _label(context, 'Occupation'),
        TextField(
          controller: _occupation,
          onChanged: (v) => setState(() => _values['personaOccupation'] = v),
          decoration: _decoration('e.g. Marketing Manager'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final o in _config.occupations.take(6))
              _chip(
                context,
                o,
                _values['personaOccupation'] == o,
                () => setState(() => _occupation.text = _values['personaOccupation'] = o),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _label(context, 'Communication tone'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in _config.tones)
              _chip(
                context,
                t.value,
                _values['personaTone'] == t.value,
                () => setState(() => _values['personaTone'] = t.value),
                icon: t.icon,
              ),
          ],
        ),
      ],
    );
  }
}
