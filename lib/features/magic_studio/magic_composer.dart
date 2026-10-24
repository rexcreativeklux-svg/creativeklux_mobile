import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'magic_composer_media.dart';
import 'magic_composer_panels.dart';
import 'magic_composer_run.dart';
import 'magic_configs.dart';
import 'magic_studio_types.dart';

/// MagicComposer — the working control at the foot of a Magic Studio tool.
/// Port of `magic-studio/StudioComposer.jsx` + `ToolbarChip.jsx`.
///
/// ⚠️ THIS GENERATES. Send runs the tool for real, through the same machine
/// every Magic surface drives: the tool's config (magic_configs.dart) for
/// validation and the exact payload, then MagicComposerRunner →
/// `MagicApi.run` (magic_design.dart) for generate → follow → recover.
///
/// ⚠️ IT CARRIES WHATEVER THE TOOL ACTUALLY NEEDS, and the tools don't agree:
///   prompt / script / text  a text box, with that tool's placeholder and cap
///   image                   a source picture (phone upload or gallery), hosted
///   video                   a source clip, hosted the same way
///   audio                   a gallery audio file (Audio to Text posts its bytes)
///   persona                 four fields, folded into a chip
/// A picture/form tool may ALSO take words: `describable` is an optional note
/// (never gates send), `requiresPrompt` is the real input (gates send).
///
/// Each option is an icon chip; tapping one opens a BOTTOM SHEET with the same
/// chooser the web's drop-up panel shows — the phone version of ToolbarChip's
/// portalled panel. The options row scrolls sideways; SEND DOES NOT SCROLL,
/// it's pinned outside the scroller so it never rides off-screen.
///
/// ⚠️ NO MODEL MENU. The web draws the app-wide model picker on most tools but
/// no config's payload sends it ("NOT sent to the backend yet"), and that
/// preference isn't ported to the app — a control with nothing on the other
/// end of it would only imply a choice that was never made.
///
/// ⚠️ NOTHING IS CLEARED ON SEND — re-running the same input with a different
/// style is the normal loop, and a minute-long prompt is expensive to retype.
///
/// Give it `key: ValueKey(tool.id)` so switching tools resets the options and
/// the typed prompt together (the web remounts per tool for the same reason);
/// a changed [tool] without a new key is also handled, by reseeding.
class MagicComposer extends StatefulWidget {
  const MagicComposer({
    super.key,
    required this.tool,
    this.refill,
    required this.onStatus,
    required this.onResult,
    this.onRunFinished,
  });

  final MagicStudioTool tool;

  /// Applied whenever its nonce changes (a template's Use, the in-flight
  /// tile's ✎) — keyed on the nonce so asking for the same words twice lands.
  final MagicRefill? refill;

  /// generating / progress / prompt / count / resultType, frozen per run.
  final ValueChanged<MagicComposerStatus> onStatus;

  /// The finished results of THIS run. Ids match history's `<gid>:<i>` where
  /// the record could be found, so a history refresh dedupes against them.
  final ValueChanged<List<MagicItem>> onResult;

  /// After every run settles (done, failed or timed out) — refresh history.
  final VoidCallback? onRunFinished;

  @override
  State<MagicComposer> createState() => _MagicComposerState();
}

class _MagicComposerState extends State<MagicComposer> {
  MagicToolConfig? _config;
  Map<String, String> _values = {};

  final _text = TextEditingController();
  final _personaName = TextEditingController();
  final _personaAge = TextEditingController();
  final _personaOccupation = TextEditingController();
  final _brandName = TextEditingController();

  /// Hosted source image / clip / gallery audio.
  String? _image;
  ({String url, ({Duration duration, Size size})? meta})? _video;
  MagicAudioSource? _audio;

  /// Digital Human's voice track — a hosted URL that rides as `audio_url`.
  /// ⚠️ NOT [_audio]: that one is downloaded and posted as bytes.
  MagicPickedMedia? _voiceTrack;
  String? _brandLogo;

  var _variations = 1;
  var _generating = false;
  String? _error;
  int? _appliedNonce;
  var _runToken = 0;

  /// What the LAST run asked for and how many — frozen at send, so the
  /// in-flight tiles keep showing THAT run while the box stays live.
  ({String prompt, int count, String resultType}) _lastRun = (prompt: '', count: 1, resultType: 'image');

  MagicStudioTool get _tool => widget.tool;
  ApiClient get _api => context.read<AuthController>().api;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
    _brandName.addListener(_onTextChanged);
    _seed();
    _applyRefill(widget.refill);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emitStatus();
    });
  }

  @override
  void didUpdateWidget(MagicComposer old) {
    super.didUpdateWidget(old);
    if (old.tool.id != widget.tool.id) {
      _runToken++; // stop following the old tool's run
      _seed();
      _text.clear();
      _image = null;
      _video = null;
      _audio = null;
      _voiceTrack = null;
      _brandLogo = null;
      _brandName.clear();
      _variations = 1;
      _generating = false;
      _error = null;
      _lastRun = (prompt: '', count: 1, resultType: 'image');
      // ⚠️ AFTER THE FRAME: this runs inside the parent's build, and telling
      // the parent now would be a setState during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _emitStatus();
      });
    }
    // didUpdateWidget is always followed by a build — no setState needed.
    if (widget.refill?.nonce != _appliedNonce) _applyRefill(widget.refill);
  }

  @override
  void dispose() {
    _runToken++;
    _text.dispose();
    _personaName.dispose();
    _personaAge.dispose();
    _personaOccupation.dispose();
    _brandName.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _seed() {
    _config = magicConfigFor(_tool.id);
    _values = _config?.seedValues() ?? {};
    _personaName.clear();
    _personaAge.clear();
    _personaOccupation.clear();
  }

  /// A template's Use or the ✎ — text, option values, and a source picture or
  /// clip on the tools that start from one. Absent pieces leave what's there.
  void _applyRefill(MagicRefill? r) {
    if (r == null || r.nonce == _appliedNonce) return;
    _appliedNonce = r.nonce;
    _text.text = r.text ?? '';
    r.values?.forEach((k, v) {
      if (v == null) return;
      _values[k] = '$v';
      switch (k) {
        case 'personaName':
          _personaName.text = '$v';
        case 'personaAge':
          _personaAge.text = RegExp(r'^\d+$').hasMatch('$v') ? '$v' : '';
        case 'personaOccupation':
          _personaOccupation.text = '$v';
      }
    });
    if (r.image != null && r.image!.isNotEmpty) _image = _hostedUrl(r.image!);
    if (r.video != null && r.video!.isNotEmpty) _setVideo(_hostedUrl(r.video!));
  }

  /// A source URL the backend can fetch: template stills are written as
  /// app-relative "/templates/…", which means nothing to a server — resolve
  /// them against the web app's origin (StudioComposer.jsx `hostedUrl`).
  static String _hostedUrl(String src) {
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(src)) return src;
    return Uri.parse(AppConfig.webAppUrl).resolve(src).toString();
  }

  void _setVideo(String url) {
    _video = (url: url, meta: null);
    // Usable at once; the probe only fills in the strip's duration and size.
    probeMagicVideo(url).then((meta) {
      // Keyed on the URL so a late probe can't label a different clip.
      if (!mounted || meta == null || _video?.url != url) return;
      setState(() => _video = (url: url, meta: meta));
    });
  }

  void _emitStatus() => widget.onStatus(
    MagicComposerStatus(
      generating: _generating,
      // ⚠️ NULL IS A DELIBERATE ANSWER: a backend run is a request we're
      // waiting on — a bar invented for it would be a bar that lies.
      progress: null,
      prompt: _lastRun.prompt,
      count: _lastRun.count,
      resultType: _lastRun.resultType,
    ),
  );

  // ── Derived state ──────────────────────────────────────────────────────────

  MagicInputKind? get _kind => _config?.input;
  bool get _typeable => _config?.typeable ?? false;
  bool get _requiresPrompt => !_typeable && (_config?.requiresPrompt ?? false);
  bool get _promptable => _config?.promptable ?? false;
  bool get _extraAudio => _config?.extraInput != null;
  bool get _variationsEnabled => _config?.variations ?? false;
  bool get _brandEnabled => _config?.brand ?? false;
  String get _typed => _text.text.trim();
  String get _brandNameValue => _brandName.text.trim();

  Object? get _primaryInput => switch (_kind) {
    MagicInputKind.prompt || MagicInputKind.script || MagicInputKind.text => _text.text,
    MagicInputKind.image => _image,
    MagicInputKind.video => _video?.url,
    MagicInputKind.audio => _audio,
    _ => null, // persona generates from the values alone
  };

  /// Why send won't run, or null — ordered as the composer is filled, so it
  /// names the piece you'd reach for next. ⚠️ ANSWERS *WHY*, NOT *WHETHER*:
  /// a dead button is a dead end when the missing piece is inside a closed chip.
  String? get _blocker {
    if (_generating || _config == null) return null;
    final config = _config!;
    if (_typeable) {
      if (_typed.isEmpty) return 'Describe what you want to create.';
      return null;
    }
    if (_requiresPrompt && _typed.isEmpty) return 'Add a description to go with it.';
    if (_extraAudio && config.extraInput!.required && _voiceTrack == null) {
      return 'Add the voice track to lip-sync to.';
    }
    switch (_kind) {
      case MagicInputKind.image when _image == null:
        return 'Choose a source image.';
      case MagicInputKind.video when _video == null:
        return 'Choose a source video.';
      case MagicInputKind.audio when _audio == null:
        return 'Record a take or upload an audio file.';
      case MagicInputKind.persona when (_values['personaName'] ?? '').trim().isEmpty:
        return 'Give the persona a name.';
      default:
        return null;
    }
  }

  /// Whether anything has been entered yet — what keeps the hint from nagging
  /// an untouched composer that is, by definition, missing everything.
  bool get _touched =>
      _typed.isNotEmpty ||
      _image != null ||
      _video != null ||
      _audio != null ||
      _voiceTrack != null ||
      _brandNameValue.isNotEmpty ||
      _brandLogo != null ||
      (_values['personaName'] ?? '').trim().isNotEmpty;

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final config = _config;
    if (config == null) return;
    // ⚠️ A BLOCKED SEND SAYS WHY instead of doing nothing.
    final blocker = _blocker;
    if (blocker != null) {
      Toast.error(blocker);
      return;
    }
    if (_generating) return;
    FocusScope.of(context).unfocus();

    final count = _variationsEnabled ? _variations : 1;
    final typed = _typed;
    final input = _primaryInput;
    final values = <String, String>{
      ..._values,
      // The composer's names for these, not the wire names — each config's
      // payload decides (`audio_url`, `description` / `prompt`, `brand_name`).
      if (_extraAudio) 'audioUrl': _voiceTrack?.url ?? '',
      if (_promptable) 'description': typed,
      if (_brandEnabled) ...{'brandName': _brandNameValue, 'brandLogo': _brandLogo ?? ''},
    };

    final err = config.validate(input, values);
    if (err != null) {
      setState(() => _error = err);
      Toast.error(err);
      return;
    }

    final resultType = config.resolveResultType(_values);
    final prompt = _typeable
        ? typed
        : typed.isNotEmpty
        ? typed
        : _kind == MagicInputKind.persona
        ? (_values['personaName'] ?? '').trim()
        : '';
    final token = ++_runToken;
    setState(() {
      _error = null;
      _generating = true;
      _lastRun = (prompt: prompt, count: count, resultType: resultType);
    });
    _emitStatus();

    // ⚠️ CLAMPED ON THE WAY IN — the slider is a UI affordance, not a guarantee,
    // and 30 is thirty billed generations from one tap.
    final payload = config.buildPayload(input, values, max(1, min(magicMaxVariations, count)));
    debugPrint('✨ [magic-studio] generating with "${_tool.label}"');

    MagicRunResult result;
    try {
      result = await MagicComposerRunner(_api).run(
        config: config,
        tool: _tool,
        payload: payload,
        resultType: resultType,
        prompt: prompt,
        audio: input is MagicAudioSource ? input : null,
        isActive: () => mounted && token == _runToken,
        onStillWorking: () => Toast.info(
          config.resultType == 'video'
              ? 'Your video is generating — this can take a minute…'
              : 'Your result is generating — this can take a minute…',
        ),
      );
    } catch (e) {
      debugPrint('❌ [magic-studio:${config.id}] generate failed: $e');
      result = const MagicRunError('Generation failed. Please try again.');
    }
    if (!mounted || token != _runToken) return;

    switch (result) {
      case MagicRunDone(:final items):
        if (items.isEmpty) {
          Toast.info('Nothing came back — try adjusting your inputs.');
        } else {
          widget.onResult(items);
          // Counted off the RESULT, not the request — the backend may cap.
          Toast.success(
            items.length > 1
                ? '${items.length} generated successfully!'
                : resultType == 'video'
                ? 'Your video is ready!'
                : 'Generated successfully!',
          );
        }
      case MagicRunError(:final message):
        setState(() => _error = message);
        Toast.error(message);
      case MagicRunTimedOut():
        // Not an error: it's still going and will be in history. "Try again"
        // would charge someone twice for the same picture.
        Toast.info('This is taking longer than usual — it’ll be in your history as soon as it’s done.');
      case MagicRunCancelled():
        break;
    }
    setState(() => _generating = false);
    _emitStatus();
    widget.onRunFinished?.call();
  }

  // ── Source pickers ─────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final picked = await pickMagicMedia(context, api: _api, kind: 'image', title: 'Choose a source image');
    if (picked != null && mounted) setState(() => _image = picked.url);
  }

  Future<void> _pickVideo() async {
    final picked = await pickMagicMedia(context, api: _api, kind: 'video', title: 'Choose a source video');
    if (picked != null && mounted) setState(() => _setVideo(picked.url));
  }

  Future<void> _pickVoiceTrack() async {
    final extra = _config?.extraInput;
    final picked = await pickMagicMedia(
      context,
      api: _api,
      kind: 'audio',
      title: extra?.label ?? 'Choose a voice track',
      emptyHint: extra?.emptyHint,
    );
    if (picked != null && mounted) setState(() => _voiceTrack = picked);
  }

  Future<void> _pickAudio() async {
    final picked = await pickMagicMedia(context, api: _api, kind: 'audio', title: 'Choose audio to transcribe');
    if (picked != null && mounted) setState(() => _audio = MagicAudioSource(url: picked.url, name: picked.name));
  }

  Future<void> _pickLogo() async {
    final picked = await pickMagicMedia(context, api: _api, kind: 'image', title: 'Choose a logo');
    if (picked != null && mounted) setState(() => _brandLogo = picked.url);
  }

  // ── Option sheets (ToolbarChip's panel, as a bottom sheet) ─────────────────

  Future<void> _sheet(String label, Widget Function(BuildContext sheet, StateSetter setSheet) body) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) {
          final c = sheet.colors;
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ⚠️ THE ONLY PLACE AN ICON CHIP'S SETTING IS NAMED IN
                  // WRITING — a tooltip never appears on a touch screen.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Text(
                      label.toUpperCase(),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: c.gray400),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: body(sheet, setSheet),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openOption(MagicOptionSpec option) {
    _sheet(
      option.label,
      (sheet, setSheet) => MagicOptionPanelBody(
        option: option,
        value: _values[option.key],
        onSelect: (v, {keepOpen = false}) {
          setState(() {
            _values[option.key] = v;
            // ⚠️ ONE OPTION MAY WRITE INTO THE PROMPT BOX (Video Effects' template
            // IS a written prompt). "" — the custom card — leaves the box alone.
            final from = _config?.promptFrom;
            if (from != null && from.$1 == option.key) {
              final seeded = from.$2(v);
              if (seeded.isNotEmpty) _text.text = seeded;
            }
          });
          setSheet(() {});
          if (!keepOpen) Navigator.pop(sheet);
        },
      ),
    );
  }

  void _openVariations() {
    _sheet('Variations', (sheet, setSheet) {
      final c = sheet.colors;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '${_variations}x',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
                ),
                const Spacer(),
                Text(
                  _variations == 1 ? 'One at a time' : '$_variations from the same prompt',
                  style: TextStyle(fontSize: 12, color: c.gray400),
                ),
              ],
            ),
            // ⚠️ A SLIDER, NOT A LIST — thirty entries is a menu you scroll to
            // answer a question you already know the answer to. It doesn't
            // close on change: onChanged fires on every step of the drag.
            Slider(
              value: _variations.toDouble(),
              min: 1,
              max: magicMaxVariations.toDouble(),
              divisions: magicMaxVariations - 1,
              activeColor: AppColors.blue600,
              label: '${_variations}x',
              onChanged: (v) {
                setState(() => _variations = v.round());
                setSheet(() {});
              },
            ),
            Row(
              children: [
                Text('1', style: TextStyle(fontSize: 11, color: c.gray400)),
                const Spacer(),
                Text('$magicMaxVariations', style: TextStyle(fontSize: 11, color: c.gray400)),
              ],
            ),
          ],
        ),
      );
    });
  }

  void _openBrand() {
    _sheet('Brand', (sheet, setSheet) {
      final c = sheet.colors;
      Widget heading(String text) => Row(
        children: [
          Text(
            text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
          ),
          const Spacer(),
          Text('Optional', style: TextStyle(fontSize: 11, color: c.gray400)),
        ],
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading('Brand name'),
            const SizedBox(height: 6),
            TextField(
              controller: _brandName,
              autofocus: _brandLogo == null && _brandNameValue.isEmpty,
              textInputAction: TextInputAction.done,
              // ⚠️ DONE CLOSES THE SHEET, IT DOES NOT GENERATE — naming the
              // brand isn't the same gesture as committing to a paid run.
              onSubmitted: (_) => Navigator.pop(sheet),
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
              style: TextStyle(fontSize: 14, color: c.gray900),
              decoration: _fieldDecoration(sheet, 'e.g. Creative Klux'),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: c.gray100),
            const SizedBox(height: 12),
            heading('Logo'),
            const SizedBox(height: 8),
            if (_brandLogo != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.gray200),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: c.gray50, borderRadius: BorderRadius.circular(8)),
                      child: MediaImage(_brandLogo!, fit: BoxFit.contain, cacheWidth: 120),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This mark rides on every run until you remove it.',
                        style: TextStyle(fontSize: 12, color: c.gray500),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(sheet);
                      _pickLogo();
                    },
                    child: const Text('Replace'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() => _brandLogo = null);
                      setSheet(() {});
                    },
                    style: TextButton.styleFrom(foregroundColor: c.gray500),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ] else
              Material(
                color: c.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: c.gray200),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    // The sheet closes first — the picker is a sheet of its own.
                    Navigator.pop(sheet);
                    _pickLogo();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    child: Row(
                      children: [
                        Icon(LucideIcons.imagePlus, size: 17, color: c.gray500),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Choose a logo',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray900),
                              ),
                              Text(
                                'From your phone or your gallery',
                                style: TextStyle(fontSize: 11.5, color: c.gray500),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  /// The persona's four fields, folded behind one chip — four boxes across a
  /// composer would make it a form. The lists come from the tool's own
  /// `inputConfig`, never from constants here.
  void _openPersona() {
    final ic = _config!.inputConfig;
    _sheet('Persona', (sheet, setSheet) {
      final c = sheet.colors;
      void set(String key, String v) {
        setState(() => _values[key] = v);
        setSheet(() {});
      }

      Widget label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          t,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
        ),
      );

      final age = _values['personaAge'] ?? '';
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label('Name'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _personaName,
                    onChanged: (v) => set('personaName', v),
                    style: TextStyle(fontSize: 14, color: c.gray900),
                    decoration: _fieldDecoration(sheet, 'e.g. Maya Chen'),
                  ),
                ),
                if (ic.personaInspire.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      // Random is fine here — it runs from a tap.
                      final pick = ic.personaInspire[Random().nextInt(ic.personaInspire.length)];
                      _personaName.text = pick.name;
                      _personaOccupation.text = pick.occupation;
                      setState(() {
                        _values['personaName'] = pick.name;
                        _values['personaOccupation'] = pick.occupation;
                        _values['personaTone'] = pick.tone;
                      });
                      setSheet(() {});
                    },
                    icon: const Icon(LucideIcons.sparkles, size: 13),
                    label: const Text('Inspire'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.gray600,
                      side: BorderSide(color: c.gray200),
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ],
            ),
            if (ic.ageGroups.isNotEmpty) ...[
              const SizedBox(height: 14),
              label('Age'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final g in ic.ageGroups)
                    _Pill(
                      label: g.label,
                      active: age == g.value,
                      onTap: () {
                        _personaAge.clear();
                        set('personaAge', g.value);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // A band is the quick answer; an exact age the precise one. Only
              // filled while the value ISN'T one of the bands.
              TextField(
                controller: _personaAge,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) => set('personaAge', v),
                style: TextStyle(fontSize: 14, color: c.gray900),
                decoration: _fieldDecoration(sheet, 'Or an exact age (e.g. 32)'),
              ),
            ],
            const SizedBox(height: 14),
            label('Occupation'),
            TextField(
              controller: _personaOccupation,
              onChanged: (v) => set('personaOccupation', v),
              style: TextStyle(fontSize: 14, color: c.gray900),
              decoration: _fieldDecoration(sheet, 'e.g. Product designer'),
            ),
            if (ic.occupations.isNotEmpty) ...[
              const SizedBox(height: 8),
              // Six of the ten — a wall of pills stops being a shortcut.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final o in ic.occupations.take(6))
                    _Pill(
                      label: o,
                      active: _values['personaOccupation'] == o,
                      onTap: () {
                        _personaOccupation.text = o;
                        set('personaOccupation', o);
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            label('Tone'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in ic.tones)
                  _Pill(
                    label: t.value,
                    icon: t.icon,
                    active: _values['personaTone'] == t.value,
                    onTap: () => set('personaTone', t.value),
                  ),
              ],
            ),
          ],
        ),
      );
    });
  }

  InputDecoration _fieldDecoration(BuildContext context, String hint) {
    final c = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color),
    );
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: c.gray400),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      enabledBorder: border(c.gray200),
      focusedBorder: border(AppColors.blue500),
      border: border(c.gray200),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final config = _config;
    if (config == null) return const SizedBox.shrink();
    final blocker = _blocker;
    final ic = config.inputConfig;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.gray200),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 30, spreadRadius: -12, offset: Offset(0, 14)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The picked source, as a strip above the toolbar — what you're
          // working from stays in view while you set the options acting on it.
          if (_kind == MagicInputKind.image && _image != null)
            _strip(
              context,
              leading: _thumb(context, MediaImage(_image!, cacheWidth: 120)),
              text: 'Source image ready',
              onClear: () => setState(() => _image = null),
              clearLabel: 'Remove source image',
            ),
          // The brand rides on every run until changed. ⚠️ ONLY THE LOGO HAS
          // AN X — the name is edited where it is entered.
          if (_brandEnabled && (_brandNameValue.isNotEmpty || _brandLogo != null))
            _strip(
              context,
              leading: _thumb(
                context,
                _brandLogo != null
                    ? Padding(
                        padding: const EdgeInsets.all(3),
                        child: MediaImage(_brandLogo!, fit: BoxFit.contain, cacheWidth: 120),
                      )
                    : Icon(LucideIcons.type, size: 18, color: c.gray400),
                light: true,
              ),
              text:
                  '${_brandNameValue.isNotEmpty ? _brandNameValue : 'No brand name yet'}${_brandLogo != null ? ' · logo ready' : ''}',
              onClear: _brandLogo != null ? () => setState(() => _brandLogo = null) : null,
              clearLabel: 'Remove logo',
            ),
          if (_extraAudio && _voiceTrack != null)
            _strip(
              context,
              leading: MagicAudioPlayButton(url: _voiceTrack!.url),
              text: _voiceTrack!.name.isNotEmpty ? _voiceTrack!.name : 'Voice track ready',
              onClear: () => setState(() => _voiceTrack = null),
              clearLabel: 'Remove voice track',
            ),
          if (_kind == MagicInputKind.video && _video != null)
            _strip(
              context,
              leading: Container(
                width: 56,
                height: 40,
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                child: const Icon(LucideIcons.fileVideo, size: 16, color: Colors.white70),
              ),
              // Whatever the probe could read, and nothing invented otherwise.
              text: _video!.meta != null
                  ? 'Source video · ${formatMagicDuration(_video!.meta!.duration)} · '
                        '${_video!.meta!.size.width.round()}×${_video!.meta!.size.height.round()}'
                  : 'Source video ready',
              onClear: () => setState(() => _video = null),
              clearLabel: 'Remove source video',
            ),
          if (_kind == MagicInputKind.audio && _audio != null)
            _strip(
              context,
              leading: MagicAudioPlayButton(url: _audio!.url),
              text: _audio!.name.isNotEmpty ? _audio!.name : 'Audio ready',
              onClear: () => setState(() => _audio = null),
              clearLabel: 'Remove audio',
            ),

          if (_typeable || _promptable)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
              child: TextField(
                controller: _text,
                // A required box gets a typed tool's room; a note gets less.
                minLines: _typeable || _requiresPrompt ? 2 : 1,
                maxLines: 5,
                inputFormatters: [if (ic.maxLength != null) LengthLimitingTextInputFormatter(ic.maxLength)],
                keyboardType: TextInputType.multiline,
                style: TextStyle(fontSize: 14, height: 1.4, color: c.gray900),
                decoration: InputDecoration.collapsed(
                  hintText: _typeable || _requiresPrompt
                      ? (ic.placeholder ?? 'Describe what you want…')
                      : (ic.placeholder ?? 'Add a description (optional)…'),
                  hintStyle: TextStyle(fontSize: 13.5, height: 1.4, color: c.gray400),
                ).copyWith(hintMaxLines: 3),
              ),
            ),

          // What this tool is still waiting for. ⚠️ IT SURVIVES THE
          // DESCRIPTION BOX — the box is optional and says nothing about
          // whether a source has been picked.
          if (!_typeable)
            Padding(
              padding: _promptable ? const EdgeInsets.fromLTRB(14, 6, 14, 0) : const EdgeInsets.fromLTRB(14, 14, 14, 6),
              child: Text(
                _helperLine(config),
                style: TextStyle(fontSize: _promptable ? 11.5 : 13, height: 1.35, color: c.gray400),
              ),
            ),

          if (_error != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: c.redTint,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.red500.withValues(alpha: 0.3)),
              ),
              child: Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.red600)),
            ),

          // Why send is dead — right above the button that won't take it.
          if (blocker != null && _touched)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    const Icon(LucideIcons.circleAlert, size: 13, color: AppColors.amber500),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(blocker, style: const TextStyle(fontSize: 11.5, color: AppColors.amber500)),
                    ),
                  ],
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final chip in _toolbar(context, config))
                          Padding(padding: const EdgeInsets.only(right: 6), child: chip),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _sendButton(context, config, blocker),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _helperLine(MagicToolConfig config) {
    final ic = config.inputConfig;
    switch (_kind) {
      case MagicInputKind.image:
        if (_image == null) return ic.helper ?? 'Choose a source image to begin.';
        // ⚠️ ON A TWO-PART TOOL THE SOURCE IS ONLY HALF — name the missing half.
        if (_extraAudio && config.extraInput!.required && _voiceTrack == null) {
          return config.extraInput!.helper;
        }
        if (_requiresPrompt && _typed.isEmpty) return 'Now write what you want above.';
        return 'Set your options, then generate.';
      case MagicInputKind.video:
        return _video == null ? (ic.helper ?? 'Choose a source video to begin.') : 'Set your options, then generate.';
      case MagicInputKind.audio:
        return _audio != null
            ? 'Set your options, then transcribe.'
            : (ic.helper ?? 'Upload a file or record from your mic.');
      case MagicInputKind.persona:
        final name = (_values['personaName'] ?? '').trim();
        return name.isNotEmpty ? 'Generating as $name.' : 'Describe who this is in the Persona panel.';
      default:
        return '';
    }
  }

  List<Widget> _toolbar(BuildContext context, MagicToolConfig config) {
    final extra = config.extraInput;
    return [
      if (_kind == MagicInputKind.image)
        _ToolbarChip(
          icon: LucideIcons.imagePlus,
          label: _image != null ? 'Replace source image' : 'Choose a source image',
          onTap: _pickImage,
        ),
      if (extra != null)
        _ToolbarChip(
          icon: LucideIcons.audioLines,
          label: _voiceTrack != null ? 'Replace the voice track' : extra.label,
          highlighted: _voiceTrack != null,
          onTap: _pickVoiceTrack,
        ),
      if (_kind == MagicInputKind.video)
        _ToolbarChip(
          icon: LucideIcons.fileVideo,
          label: _video != null ? 'Replace source video' : 'Choose a source video',
          onTap: _pickVideo,
        ),
      if (_kind == MagicInputKind.audio) ...[
        _ToolbarChip(icon: LucideIcons.upload, label: 'Upload an audio file', onTap: _pickAudio),
        // No recorder in this app yet (no `record` package).
        _ToolbarChip(
          icon: LucideIcons.mic,
          label: 'Record from your mic',
          onTap: () => Toast.info(
            'Recording from your mic is coming soon',
            description: 'Pick an audio file from your gallery for now.',
          ),
        ),
      ],
      if (_kind == MagicInputKind.persona)
        _ToolbarChip(icon: LucideIcons.user, label: 'Persona', text: 'Persona', onTap: _openPersona),
      for (final option in config.options)
        _ToolbarChip(
          icon: magicOptionIcons[option.key],
          label: option.label,
          // ⚠️ SLIDERS WEAR THEIR VALUE; EVERYTHING ELSE WEARS ITS GLYPH —
          // the number is the whole point of a duration before you send.
          badge: option.panel == MagicPanel.slider ? summarizeMagicOption(option, _values[option.key]) : null,
          // On a phone there's no hover tooltip, so the chip names its value.
          text: option.panel == MagicPanel.slider
              ? null
              : _chipText(summarizeMagicOption(option, _values[option.key]), option.label),
          onTap: () => _openOption(option),
        ),
      if (_brandEnabled) _ToolbarChip(icon: LucideIcons.stamp, label: 'Brand', text: 'Brand', onTap: _openBrand),
      // Its value IS its label — "3x" is no wider than a glyph.
      if (_variationsEnabled) _ToolbarChip(label: 'Variations', badge: '${_variations}x', onTap: _openVariations),
    ];
  }

  /// A chip's caption: the picked value, kept short; the setting's name when
  /// nothing readable is picked.
  static String _chipText(String value, String fallback) {
    final v = value.trim().isEmpty ? fallback : value.trim();
    return v.length > 16 ? '${v.substring(0, 15)}…' : v;
  }

  Widget _sendButton(BuildContext context, MagicToolConfig config, String? blocker) {
    final c = context.colors;
    final ready = !_generating && blocker == null;
    return Semantics(
      button: true,
      label: config.generateLabel,
      // ⚠️ STILL TAPPABLE WHILE BLOCKED — tapping explains why (see _submit).
      // Only an in-flight run really disables it: a second tap would start a
      // second paid generation.
      child: GestureDetector(
        onTap: _generating ? null : _submit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: ready ? AppColors.blue600 : c.gray100, shape: BoxShape.circle),
          child: Center(
            child: _generating
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.gray400))
                : Icon(LucideIcons.arrowUp, size: 18, color: ready ? Colors.white : c.gray400),
          ),
        ),
      ),
    );
  }

  Widget _thumb(BuildContext context, Widget child, {bool light = false}) => Container(
    width: 40,
    height: 40,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: light ? context.colors.gray50 : context.colors.gray100,
      borderRadius: BorderRadius.circular(8),
      border: light ? Border.all(color: context.colors.gray100) : null,
    ),
    child: child,
  );

  Widget _strip(
    BuildContext context, {
    required Widget leading,
    required String text,
    required VoidCallback? onClear,
    required String clearLabel,
  }) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.gray100)),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.gray500),
            ),
          ),
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              tooltip: clearLabel,
              visualDensity: VisualDensity.compact,
              icon: Icon(LucideIcons.x, size: 16, color: c.gray400),
            ),
        ],
      ),
    );
  }
}

/// A chip in the toolbar — port of ToolbarChip.jsx's trigger. The web draws
/// these icon-only and explains them on hover; a phone has no hover, so with
/// [text] the chip is a pill naming its current value ("Photorealistic").
/// [label] stays the tooltip and accessible name. [badge] is drawn instead of
/// a glyph for the settings whose value is the only useful label ("3x", "5s").
class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.badge,
    this.text,
    this.highlighted = false,
  });

  final String label;
  final String? text;
  final IconData? icon;
  final String? badge;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = highlighted ? AppColors.blue600 : c.gray600;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 32,
            constraints: const BoxConstraints(minWidth: 32),
            padding: EdgeInsets.symmetric(horizontal: text != null ? 10 : 8),
            alignment: Alignment.center,
            decoration: text != null
                ? BoxDecoration(
                    color: highlighted ? c.blueTint : c.gray50,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: highlighted ? AppColors.blue500 : c.gray200),
                  )
                : null,
            child: badge != null
                ? Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  )
                : icon != null && text != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 15, color: color),
                      const SizedBox(width: 5),
                      Text(
                        text!,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray700),
                      ),
                    ],
                  )
                : icon != null
                ? Icon(icon, size: 18, color: color)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: color),
                      ),
                      const SizedBox(width: 4),
                      Icon(LucideIcons.chevronDown, size: 14, color: c.gray400),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// The small selectable pill in the persona sheet.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active, required this.onTap, this.icon});

  final String label;
  final bool active;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = active ? AppColors.blue600 : c.gray600;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? c.blueTint : c.gray50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppColors.blue500 : c.gray200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 5)],
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
