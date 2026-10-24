import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/api/app_exception.dart';
import '../../core/design/design_canvas.dart';
import '../../core/design/design_renderer.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import '../publish/publish_sheet.dart';
import 'chat_models.dart';
import 'magic_design.dart';
import 'studio_api.dart';

/// Port of `studio/ai-chat-page/page.jsx` — chat with the assistant, which
/// briefs a design run; the designs (layout JSON) land in the preview pane.
///
/// Entry params, as on the web: `creative`, `model`, `initialMessage`,
/// repeated `image`, `session`. Phones get Chat / Preview tabs; from 1024px
/// the two panes sit side by side.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({
    super.key,
    this.creative,
    this.model,
    this.initialMessage,
    this.images = const [],
    this.sessionId,
  });

  final String? creative;
  final String? model;
  final String? initialMessage;
  final List<String> images;
  final String? sessionId;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  late final CreativeConfig _config = configFor(widget.creative);
  late final StudioApi _api = StudioApi(context.read<AuthController>().api);
  late final MagicApi _magic = MagicApi(context.read<AuthController>().api);

  final _messages = <ChatMessage>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _sessionId;
  bool _loading = false;
  bool _started = false;

  // Attachments (hosted URLs).
  final _attachments = <String>[];
  bool _uploading = false;

  // Voice input.
  final _speech = SpeechToText();
  bool _listening = false;
  String _textBeforeDictation = '';

  // Design run.
  final _designs = <Map<String, dynamic>>[];
  int _freshFrom = 0; // index where the newest run starts
  int _expected = 0;
  bool _generating = false;
  DateTime? _finishedAt;
  String? _progressKind;
  int _progressIndex = 0;
  Timer? _progressTimer;
  final _selected = <String>{};
  final _savedIds = <String, int>{}; // variation id → saved design id
  bool _savingSelection = false;

  // History panel.
  bool _historyOpen = false;
  List<Map<String, dynamic>>? _sessions;
  String? _sessionsError;
  bool _sessionsLoading = false;
  String? _openingSession;

  int _tab = 0; // phones: 0 = Chat, 1 = Preview

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sending needs the active brand id — wait for brands to finish loading.
    final auth = context.watch<AuthController>();
    if (!_started && !auth.brandsLoading) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _boot() async {
    if (widget.sessionId != null && await _openSession(widget.sessionId!, initial: true)) return;
    final first = widget.initialMessage?.trim() ?? '';
    if (first.isNotEmpty) {
      _attachments.addAll(widget.images.take(10));
      _send(first);
    } else {
      setState(() => _messages.add(ChatMessage(fromUser: false, content: _config.greeting)));
    }
  }

  int? get _brandId => context.read<AuthController>().activeBrand?.id;

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  void _note(String text) {
    setState(() => _messages.add(ChatMessage(fromUser: false, content: text)));
    _scrollToEnd();
  }

  void _startProgress(String kind) {
    _progressTimer?.cancel();
    setState(() {
      _progressKind = kind;
      _progressIndex = 0;
    });
    _progressTimer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (mounted) setState(() => _progressIndex++);
    });
  }

  void _stopProgress() {
    _progressTimer?.cancel();
    setState(() => _progressKind = null);
  }

  String get _progressLine {
    final lines = progressLines[_progressKind] ?? const ['Working…'];
    return lines[_progressIndex % lines.length];
  }

  // ── Sending ───────────────────────────────────────────────────────────────

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _loading || _uploading) return;
    final brandId = _brandId;
    final brand = context.read<AuthController>().activeBrand;
    final images = List<String>.from(_attachments);
    if (_listening) await _toggleMic();

    setState(() {
      _messages.add(ChatMessage(fromUser: true, content: text, images: images));
      _attachments.clear();
      _input.clear();
      _loading = true;
    });
    _scrollToEnd();

    if (brandId == null) {
      setState(() => _loading = false);
      _note('Select a brand before starting a chat.');
      return;
    }

    try {
      _sessionId ??= await _api.createSession(brandId);
      final res = await _api.send(
        brandId: brandId,
        message: text,
        images: images,
        logo: brand?.logo,
        model: widget.model?.isEmpty ?? true ? null : widget.model,
        sessionId: _sessionId,
      );
      if (!mounted) return;
      if (!res.ok) {
        setState(() => _loading = false);
        _note(res.message.isNotEmpty ? res.message : 'Something went wrong.');
        return;
      }
      final data = res.body;
      final sid = data['session_id']?.toString();
      if (sid != null && sid.isNotEmpty) _sessionId = sid;
      final reply = '${data['reply'] ?? data['message'] ?? ''}';
      setState(() {
        if (reply.isNotEmpty || data['image_url'] != null) {
          _messages.add(ChatMessage(fromUser: false, content: reply, imageUrl: data['image_url']?.toString()));
        }
      });
      _scrollToEnd();

      if (data['type'] == 'design' && data['variations'] is List) {
        _startRun(0);
        _addDesigns([
          for (final v in data['variations'] as List)
            if (v is Map) Map<String, dynamic>.from(v),
        ]);
        _finishRun();
      } else if (data['type'] == 'create') {
        await _build(data, images);
      }
    } catch (_) {
      if (mounted) _note('Oops! Something went wrong.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Building designs ──────────────────────────────────────────────────────

  static String? _firstOf(Iterable<dynamic> values) {
    for (final v in values) {
      if (v != null && '$v'.trim().isNotEmpty) return '$v';
    }
    return null;
  }

  Future<void> _build(Map<String, dynamic> data, List<String> images) async {
    Map<String, dynamic> m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    final bd = m(data['brand_details']);
    final collected = m(data['collected']);
    final gen = m(data['generation_data']);
    final meta = m(data['meta']);

    // The backend picks the mode. Magic Designs never touch create-design;
    // Studio Designs carry on below.
    if (isMagicDesign(data)) {
      await _createWithMagic(data);
      return;
    }

    final category = _firstOf([
      bd['category'],
      gen['create_sub_type'],
      meta['platform_label'],
      meta['platform'],
      collected['platform'],
      bd['create_sub_type'],
    ]);
    final size = _firstOf([bd['size'], bd['type_size'], bd['typeSize'], gen['size'], meta['size'], collected['size']]);
    final count = max(
      1,
      int.tryParse(
            _firstOf([
                  data['variations'],
                  collected['num_variations'],
                  gen['num_variations'],
                  meta['num_variations'],
                ]) ??
                '',
          ) ??
          5,
    );

    if (category == null || size == null) {
      Toast.error("The assistant didn't say which platform and size to use. Ask it to confirm those and try again.");
      _note(
        "I'm missing the platform and size for this one. Tell me those (for example \"Instagram square 1080x1080\") "
        "and I'll build it.",
      );
      return;
    }
    final brand = context.read<AuthController>().activeBrand;
    if (brand == null) {
      Toast.error('Select a brand before generating a design.');
      _note('I need an active brand before I can build a design. Pick one from the brand switcher and ask me again.');
      return;
    }

    // Port of buildRedesignPayload (studio/designTemplates.js).
    final platforms = bd['platforms'];
    final payload = <String, dynamic>{
      'creativeType': _firstOf([bd['creative_type'], _config.key]),
      'categoryType': _firstOf([bd['create_sub_type'], category]),
      'brand_id': brand.id,
      ...bd,
      'brandName': _firstOf([bd['brandName'], brand.name]),
      'logo': _firstOf([bd['logo'], brand.logo, collected['logo']]),
      'description': _firstOf([bd['description'], brand.description]),
      'platforms': platforms is List ? platforms : (platforms == null || '$platforms'.isEmpty ? [] : [platforms]),
      'size': size,
      'type_size': size,
      'category': category.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
      'images': images.isNotEmpty ? images : (bd['images'] is List ? bd['images'] : []),
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'variations': count,
    };

    _startRun(count);
    var received = 0;
    try {
      final failures = await _api.createDesigns(
        payload,
        count: count,
        onBatch: (variations) {
          if (!mounted) return;
          received += variations.length;
          _addDesigns(variations);
        },
      );
      if (!mounted) return;
      if (received == 0 && failures.isNotEmpty) {
        Toast.error(failures.first.isNotEmpty ? failures.first : "Couldn't build the design.");
        _note("I ran into a problem creating the design: ${failures.first}. Ask me to try again and I'll rerun it.");
      } else if (received == 0) {
        Toast.error('The design came back empty. Please try again.');
        _note("The design came back empty — nothing was generated. Ask me to try again and I'll rerun it.");
      } else if (failures.isNotEmpty) {
        final skipped = count - received;
        Toast.warning('$skipped of $count designs couldn\'t be built.');
        _note(
          '$received design${received == 1 ? ' is' : 's are'} ready, but $skipped couldn\'t be built '
          '(${failures.first}). Ask me to try again for more.',
        );
      }
    } catch (_) {
      Toast.error("Couldn't build the design. Please try again.");
      _note("Something went wrong while creating the design. Ask me to try again and I'll rerun it.");
    } finally {
      if (mounted) _finishRun();
    }
  }

  /// Build a Magic Design: the Magic Studio tool for this reply (video / ads /
  /// social / stock — see magic_design.dart) makes it from the prompts the
  /// backend wrote, and what comes back is shown as returned.
  ///
  /// ⚠️ ONE PROMPT PER VERSION, SENT ONE AFTER THE OTHER. Each goes out as its
  /// own run with `variations: 1`, and each card lands as its run does. A
  /// failed run is reported and the rest still go. Only a reply with a single
  /// prompt asks Magic Studio for `variations` of it.
  Future<void> _createWithMagic(Map<String, dynamic> data) async {
    final prompts = magicPromptsFrom(data);
    if (prompts.isEmpty) {
      Toast.error("The assistant didn't describe what to make.");
      _note("I didn't get a description of what to make. Tell me what it should show and I'll try again.");
      return;
    }

    final values = MagicRunValues.from(data, context.read<AuthController>().activeBrand);
    final tool = values.tool;
    final perPrompt = prompts.length > 1;
    final expected = perPrompt ? prompts.length : values.variations;
    if (perPrompt) values.variations = 1;
    final what = values.isVideo ? 'video' : 'design';

    // "Instagram · Social Design" — where it's for, and what made it.
    final platforms = (data['brand_details'] is Map ? data['brand_details'] as Map : const {})['platforms'];
    final name = [
      platforms is List ? platforms.join(', ') : platforms,
      magicToolTitles[tool],
    ].where((s) => s != null && '$s'.isNotEmpty).join(' · ');

    void reportFailure(String message) {
      Toast.error("Couldn't make your $what: $message");
      _note(
        "I couldn't make this $what — Magic Studio reported: **$message**\n\nTell me what to change and I'll try again.",
      );
    }

    _startRun(expected, kind: 'magic');
    var made = 0;
    try {
      for (final prompt in prompts) {
        if (!mounted) return;
        final run = DateTime.now().millisecondsSinceEpoch;
        final outcome = await _magic.run(
          values.payload(prompt),
          isActive: () => mounted,
          onStillWorking: () => Toast.info('Still working on your $what — this one takes a few minutes.'),
        );
        if (!mounted) return;
        switch (outcome) {
          case MagicDone(:final urls) when urls.isEmpty:
            reportFailure('It finished but returned nothing.');
          case MagicDone(:final urls):
            final landed = await Future.wait([
              for (final (i, url) in urls.indexed)
                magicResultToVariation(
                  url,
                  name: expected > 1 ? '${name.isEmpty ? 'Magic Design' : name} (${made + i + 1})' : name,
                  ratio: values.ratio,
                  tool: tool,
                  run: run,
                  index: i,
                  video: values.isVideo,
                ),
            ]);
            if (!mounted) return;
            made += landed.length;
            // Each version shows as it lands; the rest keep shimmering.
            _addDesigns(landed);
          case MagicFailed(:final message):
            reportFailure(message);
          case MagicRefused(:final message):
            Toast.error(message);
            _note(
              "Magic Studio didn't accept this request — the reason is in the error message. Ask me to try again "
              "once it's sorted.",
            );
          case MagicTimedOut():
            _note(
              "Your $what is taking unusually long. It'll appear in your Magic Studio history as soon as it's done.",
            );
          case MagicCancelled():
            return;
        }
      }
    } finally {
      if (mounted) _finishRun();
    }
  }

  void _startRun(int expected, {String kind = 'designs'}) {
    setState(() {
      _freshFrom = _designs.length;
      _expected = expected;
      _generating = true;
      _finishedAt = null;
    });
    _startProgress(kind);
  }

  void _addDesigns(List<Map<String, dynamic>> variations) {
    setState(() {
      for (final v in variations) {
        // Give every card a unique id, even across runs.
        var id = '${v['id'] ?? 'design-${_designs.length}'}';
        if (_designs.any((d) => d['_key'] == id)) id = '$id-r${_designs.length}';
        _designs.add({...v, '_key': id});
      }
    });
  }

  void _finishRun() {
    _stopProgress();
    setState(() {
      _generating = false;
      _finishedAt = DateTime.now();
    });
  }

  // ── Attachments & voice ───────────────────────────────────────────────────

  Future<void> _attach() async {
    final room = 10 - _attachments.length;
    if (room <= 0) {
      Toast.error('You can attach up to 10 files — remove one to add another.');
      return;
    }
    final files = await ImagePicker().pickMultiImage(limit: room);
    if (files.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    final brandApi = context.read<AuthController>().brandApi;
    var added = 0;
    String? lastError;
    for (final f in files.take(room)) {
      try {
        final url = await brandApi.uploadImage(await f.readAsBytes(), f.name);
        if (url != null && mounted) {
          setState(() => _attachments.add(url));
          added++;
        }
      } catch (err) {
        lastError = toUserMessage(err, "Couldn't attach that file.");
      }
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    if (added == files.length) {
      Toast.success(added == 1 ? 'File attached' : '$added files attached');
    } else {
      Toast.error('$added of ${files.length} files attached${lastError != null ? ' — $lastError' : ''}');
    }
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ok = await _speech.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) setState(() => _listening = false);
        }
      },
    );
    if (!ok) {
      Toast.error('Voice input isn\'t available — check the microphone permission.');
      return;
    }
    _textBeforeDictation = _input.text.trim();
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        // Dictation is appended to whatever was already typed.
        _input.text = [_textBeforeDictation, r.recognizedWords].where((s) => s.isNotEmpty).join(' ');
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        setState(() {});
      },
    );
  }

  // ── History ───────────────────────────────────────────────────────────────

  Future<void> _loadSessions() async {
    final brandId = _brandId;
    if (brandId == null) {
      setState(() => _sessionsError = 'Select a brand to see its chats.');
      return;
    }
    setState(() {
      _sessionsLoading = true;
      _sessionsError = null;
    });
    final res = await _api.sessions(brandId);
    if (!mounted) return;
    final raw = res.raw;
    final list = raw is List ? raw : (raw is Map ? (raw['sessions'] ?? raw['data']) : null);
    setState(() {
      _sessionsLoading = false;
      if (res.ok) {
        _sessions = [
          if (list is List)
            for (final s in list)
              if (s is Map) Map<String, dynamic>.from(s),
        ];
      } else {
        _sessionsError = res.message.isNotEmpty ? res.message : 'Something went wrong.';
      }
    });
  }

  Future<bool> _openSession(String id, {bool initial = false}) async {
    setState(() => _openingSession = id);
    final res = await _api.session(id);
    if (!mounted) return false;
    setState(() => _openingSession = null);
    if (!res.ok) {
      if (!initial) Toast.error(res.message.isNotEmpty ? res.message : "Couldn't open that chat.");
      return false;
    }
    final b = res.raw;
    dynamic list = b is Map ? b['messages'] : null;
    if (list == null && b is Map && b['data'] is Map) list = (b['data'] as Map)['messages'];
    if (list == null && b is Map && b['data'] is List) list = b['data'];
    list ??= b;
    final messages = [if (list is List) ...list.map(ChatMessage.fromSaved).whereType<ChatMessage>()];
    if (messages.isEmpty) {
      if (!initial) Toast.error('That chat has no messages to show.');
      return false;
    }
    // Saved threads come back as text only — designs aren't stored with them.
    setState(() {
      _sessionId = id;
      _messages
        ..clear()
        ..addAll(messages);
      _designs.clear();
      _selected.clear();
      _historyOpen = false;
      _tab = 0;
    });
    _scrollToEnd();
    return true;
  }

  // ── Design actions ────────────────────────────────────────────────────────

  bool _isScraive(Map<String, dynamic> d) => d['source'] == 'scraive';
  Map<String, dynamic> _canvasOf(Map<String, dynamic> d) =>
      d['canvas'] is Map ? Map<String, dynamic>.from(d['canvas'] as Map) : {'width': 1080, 'height': 1080};
  List<dynamic> _elementsOf(Map<String, dynamic> d) => d['elements'] is List ? d['elements'] as List : const [];

  Future<int?> _saveOne(Map<String, dynamic> d) async {
    final existing = _savedIds[d['_key']];
    if (existing != null) return existing;
    final brandId = _brandId;
    if (brandId == null) return null;
    final res = await _api.save(brandId, [d], _config.key);
    if (!res.ok) throw AppException(res.message);
    if (res.ids.isNotEmpty) _savedIds[d['_key'] as String] = res.ids.first;
    return res.ids.firstOrNull;
  }

  Future<void> _saveSelection() async {
    final brandId = _brandId;
    if (brandId == null) return;
    setState(() => _savingSelection = true);
    final picked = _designs.where((d) => _selected.contains(d['_key'])).toList();
    try {
      final res = await _api.save(brandId, picked, _config.key);
      if (!mounted) return;
      if (res.ok) {
        for (final (i, id) in res.ids.indexed) {
          if (i < picked.length) _savedIds[picked[i]['_key'] as String] = id;
        }
        Toast.success('Design(s) saved successfully');
        setState(_selected.clear);
      } else {
        Toast.error(res.message);
      }
    } catch (_) {
      Toast.error("Couldn't save the design(s). Please try again.");
    } finally {
      if (mounted) setState(() => _savingSelection = false);
    }
  }

  Future<void> _designAction(String action, Map<String, dynamic> d) async {
    switch (action) {
      case 'preview':
        showDialog<void>(
          context: context,
          builder: (ctx) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Center(
                  child: d['kind'] == 'video' && hostedUrlOf(d) != null
                      ? AutoplayVideo(url: hostedUrlOf(d)!, poster: '')
                      : InteractiveViewer(maxScale: 5, child: _artwork(d, fit: BoxFit.contain)),
                ),
                SafeArea(
                  child: IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      case 'edit':
        final router = GoRouter.of(context);
        try {
          if (!_savedIds.containsKey(d['_key'])) Toast.info('Saving so it can open in the editor…');
          final id = await _saveOne(d);
          if (id != null) {
            Toast.info('Opening the editor…');
            router.push('/design/$id');
          } else {
            Toast.success('Saved — open it from your designs');
            router.go('/creatives');
          }
        } catch (_) {
          Toast.error("Couldn't open this design in the editor");
        }
      case 'download':
        try {
          Toast.info('Downloading…');
          final slug = '${d['name'] ?? 'design'}'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
          final file = '$slug-${DateTime.now().millisecondsSinceEpoch}';
          if (!await Gal.hasAccess()) await Gal.requestAccess();
          // A Magic Design is a hosted file — saved as it is; a creative is
          // painted first.
          final hosted = hostedUrlOf(d);
          if (hosted != null && d['kind'] == 'video') {
            final path = '${Directory.systemTemp.path}/$file.mp4';
            await Dio().download(hosted, path);
            await Gal.putVideo(path);
            unawaited(File(path).delete().catchError((_) => File(path)));
          } else if (hosted != null) {
            final res = await Dio().get<List<int>>(hosted, options: Options(responseType: ResponseType.bytes));
            await Gal.putImageBytes(Uint8List.fromList(res.data!), name: file);
          } else {
            final bytes = await renderDesignPng(_canvasOf(d), _elementsOf(d), scraive: _isScraive(d));
            await Gal.putImageBytes(bytes, name: file);
          }
          Toast.success('Saved to your photo gallery');
        } catch (_) {
          Toast.error("Couldn't download that design");
        }
      case 'save':
        try {
          Toast.info('Saving design…');
          await _saveOne(d);
          Toast.success('Saved to your designs');
        } catch (_) {
          Toast.error("Couldn't save the design");
        }
      case 'publish':
        // A Magic Design publishes its hosted file; a creative has none, so the
        // sheet paints canvas + elements and uploads that instead. A Magic
        // result can go out as a post OR an ad ("all"); a creative follows the
        // chat it was made in.
        final magic = d['source'] == 'magic';
        showPublishSheet(
          context,
          PublishCreative(
            name: '${d['name'] ?? 'Design'}',
            category: magic
                ? 'all'
                : switch (_config.key) {
                    'ads_creative' => 'ads',
                    'social_creative' => 'social',
                    _ => 'all',
                  },
            copy: d['copy'] is Map ? Map<String, dynamic>.from(d['copy'] as Map) : const {},
            image: hostedUrlOf(d),
            isVideo: d['kind'] == 'video',
            canvas: _canvasOf(d),
            elements: _elementsOf(d),
            scraive: _isScraive(d),
          ),
        );
    }
  }

  /// A design's artwork: a Magic result's hosted file as it is, a creative
  /// painted from its layout.
  Widget _artwork(Map<String, dynamic> d, {BoxFit fit = BoxFit.contain}) {
    final hosted = hostedUrlOf(d);
    if (hosted != null && d['kind'] == 'video') {
      return AspectRatio(
        aspectRatio: _aspectOf(d),
        child: AutoplayVideo(url: hosted, poster: ''),
      );
    }
    if (hosted != null) return MediaImage(hosted, fit: fit);
    return DesignCanvas(canvas: _canvasOf(d), elements: _elementsOf(d), scraive: _isScraive(d));
  }

  double _aspectOf(Map<String, dynamic> d) {
    final canvas = _canvasOf(d);
    final w = num.tryParse('${canvas['width']}') ?? 1, h = num.tryParse('${canvas['height']}') ?? 1;
    return h == 0 ? 1 : w / h;
  }

  // ── Leaving ───────────────────────────────────────────────────────────────

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.surface,
        title: const Text('Leave this page?'),
        content: const Text('Your designs will be lost if you continue. Save the ones you want to keep first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red500),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) _leave();
  }

  void _leave() => context.canPop() ? context.pop() : context.go('/');

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final guard = _designs.isNotEmpty || _generating;

    return PopScope(
      canPop: !guard,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(
          child: wide
              ? Row(
                  children: [
                    SizedBox(width: 440, child: _chatPane(context)),
                    VerticalDivider(width: 1, color: c.gray200),
                    Expanded(child: _previewPane(context)),
                  ],
                )
              : Column(
                  children: [
                    _mobileTabs(context),
                    Expanded(
                      child: IndexedStack(index: _tab, children: [_chatPane(context), _previewPane(context)]),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _mobileTabs(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.gray200)),
      ),
      child: Row(
        children: [
          for (final (i, label) in [(0, 'Chat'), (1, 'Preview')])
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _tab = i),
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: _tab == i ? AppColors.blue600 : Colors.transparent, width: 2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(fontWeight: FontWeight.w600, color: _tab == i ? AppColors.blue600 : c.gray500),
                      ),
                      if (i == 1 && (_designs.isNotEmpty || _generating)) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: c.blueTint, borderRadius: BorderRadius.circular(99)),
                          child: Text(
                            '${_designs.length}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.blue600),
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
    );
  }

  // ── Chat pane ─────────────────────────────────────────────────────────────

  Widget _chatPane(BuildContext context) {
    final c = context.colors;
    final accent = _config.color;
    return Stack(
      children: [
        Column(
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.gray200)),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => _designs.isNotEmpty || _generating ? _confirmLeave() : _leave(),
                    icon: Icon(LucideIcons.arrowLeft, size: 18, color: c.gray700),
                  ),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(_config.icon, size: 16, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _config.label,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.gray900),
                        ),
                        Text('Powered by CreativeKlux AI', style: TextStyle(fontSize: 11, color: c.gray400)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Recent chats',
                    onPressed: () {
                      setState(() => _historyOpen = !_historyOpen);
                      if (_historyOpen && _sessions == null) _loadSessions();
                    },
                    style: IconButton.styleFrom(backgroundColor: _historyOpen ? accent.withValues(alpha: 0.12) : null),
                    icon: Icon(LucideIcons.history, size: 18, color: _historyOpen ? accent : c.gray600),
                  ),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text('Online', style: TextStyle(fontSize: 11.5, color: c.gray500)),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                children: [
                  for (final m in _messages) ...[_bubble(context, m), const SizedBox(height: 14)],
                  if (_loading || _generating) _typing(context),
                  if (!_loading && !_generating && _designs.isNotEmpty && MediaQuery.sizeOf(context).width < 1024)
                    Center(
                      child: ActionChip(
                        avatar: Icon(LucideIcons.layoutGrid, size: 15, color: AppColors.blue600),
                        label: Text('View ${_designs.length} design${_designs.length == 1 ? '' : 's'}'),
                        onPressed: () => setState(() => _tab = 1),
                      ),
                    ),
                ],
              ),
            ),
            _composer(context),
          ],
        ),
        if (_historyOpen) Positioned.fill(top: 52, child: _historyPanel(context)),
      ],
    );
  }

  Widget _bubble(BuildContext context, ChatMessage m) {
    final c = context.colors;
    final accent = _config.color;
    final avatar = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: m.fromUser ? accent.withValues(alpha: 0.12) : c.surface,
        border: Border.all(color: c.gray200),
      ),
      padding: const EdgeInsets.all(5),
      child: m.fromUser ? Icon(LucideIcons.user, size: 15, color: accent) : Image.asset('assets/images/logo.png'),
    );
    final time = '${m.time.hour.toString().padLeft(2, '0')}:${m.time.minute.toString().padLeft(2, '0')}';
    final textStyle = TextStyle(fontSize: 13.5, height: 1.55, color: c.gray900);

    final bubble = Flexible(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
        child: Column(
          crossAxisAlignment: m.fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (m.images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final url in m.images)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(width: 56, height: 56, child: MediaImage(url, cacheWidth: 160)),
                      ),
                  ],
                ),
              ),
            if (m.content.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                decoration: BoxDecoration(
                  color: m.fromUser ? accent.withValues(alpha: 0.12) : c.gray100,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(m.fromUser ? 16 : 4),
                    bottomRight: Radius.circular(m.fromUser ? 4 : 16),
                  ),
                ),
                child: m.fromUser
                    ? Text(m.content, style: textStyle)
                    : MiniMarkdown(m.content, style: textStyle, accent: accent),
              ),
            if (m.imageUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: MediaImage(m.imageUrl!, fit: BoxFit.contain),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CopyIcon(text: m.content),
                  Text(time, style: TextStyle(fontSize: 10.5, color: c.gray400)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Row(
      mainAxisAlignment: m.fromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: m.fromUser ? [bubble, const SizedBox(width: 8), avatar] : [avatar, const SizedBox(width: 8), bubble],
    );
  }

  Widget _typing(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c.gray200),
          ),
          child: Image.asset('assets/images/logo.png'),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Dots(color: _config.color),
                if (_progressKind != null) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(_progressLine, style: TextStyle(fontSize: 12.5, color: c.gray600)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _composer(BuildContext context) {
    final c = context.colors;
    final accent = _config.color;
    final canSend = _input.text.trim().isNotEmpty && !_loading && !_uploading;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.gray200, width: 1.5),
            ),
            child: Column(
              children: [
                if (_attachments.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      children: [
                        for (final url in _attachments)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.only(left: 4, right: 2),
                            decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: SizedBox(width: 26, height: 26, child: MediaImage(url, cacheWidth: 80)),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                    Uri.tryParse(url)?.pathSegments.lastOrNull ?? 'image',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11.5, color: c.gray700),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => setState(() => _attachments.remove(url)),
                                  icon: Icon(LucideIcons.x, size: 14, color: c.gray500),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Add images (up to 10)',
                      onPressed: _uploading ? null : _attach,
                      icon: _uploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(LucideIcons.plus, size: 20, color: c.gray600),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 6,
                        maxLength: 2000,
                        textInputAction: TextInputAction.newline,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(fontSize: 14, color: c.gray900),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          hintText: _listening ? 'Listening — start speaking…' : _config.placeholder,
                          hintStyle: TextStyle(color: c.gray400, fontSize: 14),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _listening ? 'Stop dictation' : 'Dictate',
                      onPressed: _toggleMic,
                      style: IconButton.styleFrom(backgroundColor: _listening ? AppColors.red500 : null),
                      icon: Icon(
                        _listening ? LucideIcons.square : LucideIcons.mic,
                        size: 17,
                        color: _listening ? Colors.white : c.gray600,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 0, 6, 6),
                      child: GestureDetector(
                        onTap: canSend ? _send : null,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: canSend ? null : c.gray100,
                            gradient: canSend
                                ? LinearGradient(colors: [accent, Color.lerp(accent, Colors.white, 0.25)!])
                                : null,
                          ),
                          child: _loading
                              ? Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: c.gray400),
                                )
                              : Icon(LucideIcons.arrowUp, size: 18, color: canSend ? Colors.white : c.gray400),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _listening ? 'Listening… tap the square to finish' : 'Tap send when you\'re ready',
            style: TextStyle(fontSize: 10.5, color: _listening ? AppColors.red500 : c.gray400),
          ),
        ],
      ),
    );
  }

  Widget _historyPanel(BuildContext context) {
    final c = context.colors;
    final sessions = _sessions ?? const [];
    return Material(
      color: c.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
            child: Row(
              children: [
                Text(
                  'Recent chats${_sessions == null ? '' : ' (${sessions.length})'}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.gray900),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _sessionsLoading ? null : _loadSessions,
                  icon: Icon(LucideIcons.refreshCw, size: 16, color: c.gray500),
                ),
                IconButton(
                  tooltip: 'Close history',
                  onPressed: () => setState(() => _historyOpen = false),
                  icon: Icon(LucideIcons.x, size: 18, color: c.gray500),
                ),
              ],
            ),
          ),
          Expanded(
            child: _sessionsLoading
                ? ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (var i = 0; i < 6; i++)
                        Container(
                          height: 52,
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(10)),
                        ),
                    ],
                  )
                : _sessionsError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Couldn't load your chats",
                            style: TextStyle(fontWeight: FontWeight.w600, color: c.gray800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _sessionsError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.gray500),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(onPressed: _loadSessions, child: const Text('Try again')),
                        ],
                      ),
                    ),
                  )
                : sessions.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'No saved chats yet',
                            style: TextStyle(fontWeight: FontWeight.w600, color: c.gray800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Conversations you have with the assistant show up here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.gray500),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: sessions.length,
                    itemBuilder: (context, i) => _sessionRow(context, sessions[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sessionRow(BuildContext context, Map<String, dynamic> s) {
    final c = context.colors;
    final id = '${s['session_id'] ?? s['id']}';
    final title = '${s['title'] ?? ''}';
    // "Brand: X" in the title makes the brand the headline.
    final brandMatch = RegExp(r'Brand:\s*(.+)', caseSensitive: false).firstMatch(title);
    final flat = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    final head = brandMatch?.group(1)?.split('\n').first.trim() ?? (flat.isEmpty ? 'Untitled chat' : flat);
    final rest = brandMatch == null
        ? null
        : title.replaceFirst(brandMatch.group(0)!, '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final opening = _openingSession != null;
    final isThis = _openingSession == id;
    final current = _sessionId == id;

    String when() {
      final d = DateTime.tryParse('${s['started'] ?? s['created_at'] ?? ''}')?.toLocal();
      if (d == null) return '';
      final now = DateTime.now();
      if (DateUtils.isSameDay(d, now)) {
        return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      }
      if (DateUtils.isSameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
      const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${d.day} ${m[d.month - 1]}${d.year != now.year ? ' ${d.year}' : ''}';
    }

    return Opacity(
      opacity: opening && !isThis ? 0.5 : 1,
      child: Material(
        color: current ? _config.color.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: opening ? null : () => _openSession(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  head,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.gray900),
                ),
                if (rest != null && rest.isNotEmpty)
                  Text(
                    rest,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.gray500),
                  ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(when(), style: TextStyle(fontSize: 11, color: c.gray400)),
                    const SizedBox(width: 10),
                    Icon(LucideIcons.messageSquare, size: 11, color: c.gray400),
                    const SizedBox(width: 3),
                    Text('${s['messages'] ?? 0} messages', style: TextStyle(fontSize: 11, color: c.gray400)),
                    if (s['status'] == 'complete') ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'Designs',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF047857)),
                        ),
                      ),
                    ],
                    if (isThis) ...[const Spacer(), Text('Opening…', style: TextStyle(fontSize: 11, color: c.gray500))],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Preview pane ──────────────────────────────────────────────────────────

  Widget _previewPane(BuildContext context) {
    final c = context.colors;
    if (_designs.isEmpty && !_generating) return const _PreviewIdle();

    final width = MediaQuery.sizeOf(context).width;
    final paneWidth = width >= 1024 ? width - 441 : width;
    final cols = ((paneWidth - 32) / 280).floor().clamp(1, 3);
    final remaining = _generating ? max<int>(0, _expected - (_designs.length - _freshFrom)) : 0;
    final tiles = _designs.length + (_designs.isEmpty && _generating ? max<int>(1, _expected) : remaining);

    return Container(
      color: c.page,
      child: Column(
        children: [
          // Progress banner.
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.gray200),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _generating ? _config.color : const Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _generating
                        ? _progressLine
                        : 'Done — ${_designs.length} design${_designs.length == 1 ? '' : 's'} ready',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray800),
                  ),
                ),
                if (_generating && _designs.length > _freshFrom)
                  Text(
                    '${_designs.length - _freshFrom} of $_expected',
                    style: TextStyle(fontSize: 12.5, color: c.gray500),
                  ),
              ],
            ),
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _savingSelection ? null : _saveSelection,
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                    icon: _savingSelection
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(LucideIcons.bookmark, size: 15),
                    label: Text(
                      _savingSelection
                          ? 'Saving…'
                          : 'Save ${_selected.length} design${_selected.length == 1 ? '' : 's'}',
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: () => setState(_selected.clear), child: const Text('Clear')),
                ],
              ),
            ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.72,
              ),
              itemCount: tiles,
              itemBuilder: (context, i) =>
                  i < _designs.length ? _designCard(context, _designs[i]) : _PlaceholderTile(line: _progressLine),
            ),
          ),
          if (_finishedAt != null && !_generating)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Generated at ${_finishedAt!.hour.toString().padLeft(2, '0')}:${_finishedAt!.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 11.5, color: c.gray500),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _designCard(BuildContext context, Map<String, dynamic> d) {
    final c = context.colors;
    final key = d['_key'] as String;
    final selected = _selected.contains(key);
    final copy = d['copy'] is Map ? d['copy'] as Map : const {};
    final scoreText = '${copy['performance_score'] ?? ''}';
    final score = int.tryParse(scoreText.split('/').first.trim());

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: selected ? const Color(0xFF22C55E) : c.gray200, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => selected ? _selected.remove(key) : _selected.add(key)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Center(child: _artwork(d)),
                    ),
                  ),
                  if (selected)
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: Color(0xFF22C55E),
                        child: Icon(LucideIcons.check, size: 12, color: Colors.white),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: PopupMenuButton<String>(
                      tooltip: 'Design actions',
                      color: c.surface,
                      onSelected: (a) => _designAction(a, d),
                      icon: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4)],
                        ),
                        child: const Icon(LucideIcons.ellipsis, size: 16, color: Color(0xFF364153)),
                      ),
                      itemBuilder: (_) => [
                        for (final (value, icon, label) in [
                          ('preview', LucideIcons.eye, 'Preview'),
                          ('edit', LucideIcons.pencil, 'Edit'),
                          ('publish', LucideIcons.send, 'Publish'),
                          ('download', LucideIcons.download, 'Download'),
                          ('save', LucideIcons.bookmark, 'Save design'),
                        ])
                          PopupMenuItem(
                            value: value,
                            child: Row(
                              children: [
                                Icon(icon, size: 16, color: c.gray600),
                                const SizedBox(width: 10),
                                Text(label),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${d['name'] ?? 'Design'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.gray800),
                        ),
                      ),
                      if (d['category'] != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(99)),
                          child: Text('${d['category']}', style: TextStyle(fontSize: 9.5, color: c.gray600)),
                        ),
                    ],
                  ),
                  if ((copy['headline'] ?? '') != '')
                    Text(
                      '${copy['headline']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.gray900),
                    ),
                  if ((copy['tagline'] ?? '') != '')
                    Text(
                      '${copy['tagline']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: c.gray500),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if ((copy['cta'] ?? '') != '')
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: c.gray900, borderRadius: BorderRadius.circular(99)),
                            child: Text(
                              '${copy['cta']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, color: c.surface, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (score != null)
                        Tooltip(
                          message: scoreText.contains('—') ? scoreText.split('—').last.trim() : scoreText,
                          child: Text(
                            '★ $score/100',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyIcon extends StatefulWidget {
  const _CopyIcon({required this.text});

  final String text;

  @override
  State<_CopyIcon> createState() => _CopyIconState();
}

class _CopyIconState extends State<_CopyIcon> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) return const SizedBox.shrink();
    return IconButton(
      tooltip: _copied ? 'Copied!' : 'Copy',
      visualDensity: VisualDensity.compact,
      iconSize: 13,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.text));
        setState(() => _copied = true);
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _copied = false);
        });
      },
      icon: Icon(
        _copied ? LucideIcons.check : LucideIcons.copy,
        color: _copied ? AppColors.green600 : context.colors.gray400,
      ),
    );
  }
}

/// Three bouncing dots in the theme colour.
class _Dots extends StatefulWidget {
  const _Dots({required this.color});

  final Color color;

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset(0, -3 * sin(((_anim.value - i * 0.15) % 1) * pi).clamp(0, 1)),
              child: Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaceholderTile extends StatelessWidget {
  const _PlaceholderTile({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.gray100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.gray200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(height: 12),
          Text(
            line,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.gray500),
          ),
          const SizedBox(height: 10),
          Text('Template —— Design', style: TextStyle(fontSize: 10.5, color: c.gray400)),
        ],
      ),
    );
  }
}

/// "Ready to generate" — the idle preview (AiPreviewIdle.jsx).
class _PreviewIdle extends StatelessWidget {
  const _PreviewIdle();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.page,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.surface,
              border: Border.all(color: c.gray200),
            ),
            child: Center(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.blue600.withValues(alpha: 0.3 + i * 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Ready to generate',
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.gray900),
          ),
          const SizedBox(height: 6),
          Text(
            'Describe your idea in the chat — your creative will appear here instantly',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: c.gray500),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            children: [
              for (final chip in ['Social post', 'Ad creative', 'Brand visual'])
                Chip(
                  label: Text(chip, style: TextStyle(fontSize: 12, color: c.gray600)),
                  backgroundColor: c.surface,
                  side: BorderSide(color: c.gray200),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
