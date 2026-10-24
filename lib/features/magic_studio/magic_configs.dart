import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../editor/magic_panel/magic_tools.dart' show MagicOptionItem, autoColor, ratioString;

/// Per-tool configuration for the /magic-studio composer — port of
/// `magic-studio/magicStudioConfigs.jsx` (plus the data it imports from
/// `(lib)/magic-studio-audio.js` and `magic-studio/videoEffectTemplates.js`).
///
/// Every tool is described here as data — which input it takes, its option
/// chips, what it produces, how it validates and the exact request body it
/// posts — so the composer (magic_composer.dart) stays generic, exactly like
/// the web's StudioComposer.
///
/// ⚠️ BACKEND PATHS ONLY. Both audio tools run on the backend today
/// (AUDIO_ENGINE in magic-studio-audio.js is "backend" for each), so the
/// on-device Whisper / Kokoro branches — and the option rows only they honour
/// (transcript format, audio quality, export format) — are not ported. Their
/// web counterparts are filtered out by `onlyOptions` on that engine too.
///
/// ⚠️ THE VALUES ARE THE CONTRACT. Option `value`s, payload keys and the
/// omit-when-empty rules match the web byte for byte; change a `label` freely,
/// a `value` only alongside the API.

// ── Kinds ────────────────────────────────────────────────────────────────────

/// Which primary input the composer draws (config `input`).
enum MagicInputKind { prompt, script, text, image, video, audio, persona }

/// The `input` kinds that are typed into. The rest need a file or a form.
bool isTypeable(MagicInputKind k) =>
    k == MagicInputKind.prompt || k == MagicInputKind.script || k == MagicInputKind.text;

/// How an option's chooser is laid out (config `panel`).
enum MagicPanel { list, cards, colors, ratios, flags, voices, pills, slider, templates }

// ── Option data ──────────────────────────────────────────────────────────────

/// One choice in an option panel. Extends the editor panel's item so the four
/// shared panel kinds (list / cards / colors / ratios) render through the same
/// `MagicOptionBody` the editor's Magic tab uses — a style card looks the same
/// wherever you meet it, as on the web (magicPanelUI.jsx is shared there too).
class MagicChoice extends MagicOptionItem {
  const MagicChoice(
    super.value,
    super.label, {
    super.desc,
    super.icon,
    super.img,
    super.ratio,
    super.w,
    super.h,
    this.flag,
    this.gender,
    this.group,
    this.top = false,
    this.category,
    this.prompt,
  });

  /// Language panels.
  final String? flag;

  /// Voice panels: "female" | "male", the heading it's grouped under, and the
  /// ★ for the provider's flagship voices.
  final String? gender;
  final String? group;
  final bool top;

  /// Template panels: the heading, and the words the template seeds.
  final String? category;
  final String? prompt;
}

/// One option chip (config `options[]`).
class MagicOptionSpec {
  const MagicOptionSpec({
    required this.key,
    required this.label,
    required this.panel,
    required this.defaultValue,
    this.items = const [],
    this.min = 1,
    this.max = 10,
    this.step = 1,
    this.unit = '',
    this.hint,
    this.categoryOrder = const [],
  });

  final String key;
  final String label;
  final MagicPanel panel;

  /// Always a string, like every option value on the web — it rides into the
  /// payload untouched (`duration: values.duration`).
  final String defaultValue;
  final List<MagicChoice> items;

  // Slider panels.
  final double min;
  final double max;
  final double step;
  final String unit;
  final String Function(double value)? hint;

  /// Template panels: the order the category headings appear in.
  final List<String> categoryOrder;
}

/// The glyph for each setting, keyed by the option's own `key` — the web's
/// OPTION_ICONS in StudioComposer.jsx. ⚠️ Keyed centrally so the same setting
/// wears the same picture on every tool; anything missing falls back to a text
/// chip, which still works.
const magicOptionIcons = <String, IconData>{
  'purpose': LucideIcons.target,
  'style': LucideIcons.palette,
  'color': LucideIcons.swatchBook,
  'ratio': LucideIcons.ratio,
  'duration': LucideIcons.clock,
  'voice': LucideIcons.audioLines,
  'tone': LucideIcons.drama,
  'pace': LucideIcons.gauge,
  'format': LucideIcons.fileText,
  'language': LucideIcons.languages,
  'quality': LucideIcons.gem,
  'contentType': LucideIcons.layoutGrid,
  'template': LucideIcons.wandSparkles,
  'engine': LucideIcons.cpu,
  'motion': LucideIcons.move3d,
  'resolution': LucideIcons.monitorPlay,
  'sound': LucideIcons.volume2,
  'background': LucideIcons.paintBucket,
  'effect': LucideIcons.wandSparkles,
};

/// Human label for an option's current value (magicPanelUI.jsx `summarize`).
String summarizeMagicOption(MagicOptionSpec option, String? value) {
  for (final i in option.items) {
    if (i.value == value) return i.label;
  }
  // A slider's value IS its label; the unit makes "7" read as a length.
  if (option.panel == MagicPanel.slider) return '${_trimNum(value ?? option.defaultValue)}${option.unit}';
  if (option.panel == MagicPanel.colors && value != null) return value.toUpperCase();
  return value ?? '';
}

String _trimNum(String v) {
  final n = double.tryParse(v);
  if (n == null) return v;
  return n == n.roundToDouble() ? '${n.round()}' : '$n';
}

// ── Input config ─────────────────────────────────────────────────────────────

class MagicPersonaExample {
  const MagicPersonaExample(this.name, this.occupation, this.tone);
  final String name;
  final String occupation;
  final String tone;
}

/// Config `inputConfig`.
class MagicInputConfig {
  const MagicInputConfig({
    this.label,
    this.placeholder,
    this.helper,
    this.maxLength,
    this.inspire = const [],
    this.personaInspire = const [],
    this.occupations = const [],
    this.ageGroups = const [],
    this.tones = const [],
  });

  final String? label;
  final String? placeholder;
  final String? helper;
  final int? maxLength;
  final List<String> inspire;
  final List<MagicPersonaExample> personaInspire;
  final List<String> occupations;
  final List<({String value, String label, String desc})> ageGroups;
  final List<({String value, IconData icon})> tones;

  MagicInputConfig withPlaceholder(String p) => MagicInputConfig(
    label: label,
    placeholder: p,
    helper: helper,
    maxLength: maxLength,
    inspire: inspire,
    personaInspire: personaInspire,
    occupations: occupations,
    ageGroups: ageGroups,
    tones: tones,
  );
}

/// A SECOND media input (config `extraInput`) — Digital Human's voice track.
class MagicExtraInput {
  const MagicExtraInput({required this.label, required this.helper, this.required = false, this.emptyHint});
  final String label;
  final String helper;
  final bool required;
  final String? emptyHint;
}

// ── The tool config ──────────────────────────────────────────────────────────

/// What `buildPayload` / `validate` read. [input] is the prompt text, a hosted
/// source image / video URL, or (Audio to Text) a non-null audio source;
/// [values] are the option values plus the composer's extras (`description`,
/// `audioUrl`, `brandName`, `brandLogo`, the persona fields).
typedef MagicValidate = String? Function(Object? input, Map<String, String> values);
typedef MagicPayload = Map<String, dynamic> Function(Object? input, Map<String, String> values, int variations);

class MagicToolConfig {
  const MagicToolConfig({
    required this.id,
    required this.input,
    required this.resultType,
    required this.generateLabel,
    required this.historyTool,
    required this.inputConfig,
    required this.options,
    required this.validate,
    required this.buildPayload,
    this.variations = false,
    this.describable = false,
    this.requiresPrompt = false,
    this.brand = false,
    this.extraInput,
    this.promptFrom,
    this.multipartAudio = false,
  });

  final String id;
  final MagicInputKind input;

  /// "image" | "video" | "audio" | "text" | "auto" (persona — the Content type
  /// option decides; see [resolveResultType]).
  final String resultType;
  final String generateLabel;

  /// Backend `tool` enum history is filed under.
  final String historyTool;
  final MagicInputConfig inputConfig;
  final List<MagicOptionSpec> options;
  final MagicValidate validate;
  final MagicPayload buildPayload;

  /// Offers the "3x" chip; the backend fans out from `variations` in ONE request.
  final bool variations;

  /// An optional note riding alongside a picture or form — never gates submit.
  final bool describable;

  /// The secondary box IS the input — gates submit (Video Effects).
  final bool requiresPrompt;

  /// Puts the Brand chip on the composer (`brand_name` / `logo_url`).
  final bool brand;
  final MagicExtraInput? extraInput;

  /// Picking this option writes its words into the prompt box: (option key,
  /// resolve). "" leaves the box alone.
  final (String, String Function(String value))? promptFrom;

  /// Audio to Text posts the audio FILE as multipart field `audio` alongside
  /// the [buildPayload] fields, instead of a JSON body.
  final bool multipartAudio;

  bool get typeable => isTypeable(input);
  bool get promptable => !typeable && (describable || requiresPrompt);

  /// What a run will produce (StudioComposer.jsx `resolveResultType`).
  String resolveResultType(Map<String, String> values) {
    if (resultType != 'auto') return resultType;
    return switch (values['contentType']) {
      'text' => 'text',
      'video' => 'video',
      _ => 'image',
    };
  }

  /// Option values seeded from each option's default (+ the persona fields).
  Map<String, String> seedValues() => {
    for (final o in options) o.key: o.defaultValue,
    if (input == MagicInputKind.persona) ...{
      'personaName': '',
      'personaAge': '',
      'personaOccupation': '',
      'personaTone': '',
    },
  };
}

// ── Shared pieces ────────────────────────────────────────────────────────────

String _px(int id) => 'https://images.pexels.com/photos/$id/pexels-photo-$id.jpeg?auto=compress&cs=tinysrgb&h=300';

const _ratioSquare = MagicChoice('square', 'Square', ratio: '1:1');
const _ratioLandscape = MagicChoice('landscape', 'Landscape', ratio: '16:9', w: 16, h: 9);
const _ratioPortrait = MagicChoice('portrait', 'Portrait', ratio: '9:16', w: 9, h: 16);
const _ratioWide = MagicChoice('wide', 'Ultra Wide', ratio: '21:9', w: 21, h: 9);

MagicOptionSpec _ratioOption(String fallback, List<MagicChoice> items) => MagicOptionSpec(
  key: 'ratio',
  label: 'Aspect ratio',
  panel: MagicPanel.ratios,
  defaultValue: fallback,
  items: items,
);

/// What the result is FOR. Sent as `purpose`; the VALUES are the backend's
/// design-type names.
const _purposeOption = MagicOptionSpec(
  key: 'purpose',
  label: 'Purpose',
  panel: MagicPanel.list,
  defaultValue: 'image-design',
  items: [
    MagicChoice(
      'ad-design',
      'Ads',
      desc: 'Built to sell — a clear offer and a reason to click',
      icon: LucideIcons.megaphone,
    ),
    MagicChoice(
      'social-design',
      'Social',
      desc: 'Built for the feed — native, scrollable, shareable',
      icon: LucideIcons.share2,
    ),
    MagicChoice('image-design', 'General', desc: 'No particular channel in mind', icon: LucideIcons.sparkles),
  ],
);

/// A colour to build the image around. ⚠️ Sent as `color` ONLY when one is
/// chosen — this endpoint rejects fields it doesn't know.
const _colorOption = MagicOptionSpec(
  key: 'color',
  label: 'Colour',
  panel: MagicPanel.colors,
  defaultValue: autoColor,
  items: [
    MagicChoice(autoColor, 'No preference'),
    MagicChoice('#2563eb', 'Blue'),
    MagicChoice('#0ea5e9', 'Sky'),
    MagicChoice('#059669', 'Emerald'),
    MagicChoice('#f59e0b', 'Amber'),
    MagicChoice('#ef4444', 'Red'),
    MagicChoice('#ec4899', 'Pink'),
    MagicChoice('#7c3aed', 'Violet'),
    MagicChoice('#111827', 'Near-black'),
    MagicChoice('#f8fafc', 'Off-white'),
  ],
);

Map<String, dynamic> _colorField(String? v) => v != null && v.isNotEmpty && v != autoColor ? {'color': v} : const {};

/// `description` only when something was written (omitted when empty: the
/// endpoint rejects undeclared fields, so an untouched composer must post what
/// it always did).
Map<String, dynamic> _descriptionField(String? v) {
  final t = (v ?? '').trim();
  return t.isEmpty ? const {} : {'description': t};
}

/// `prompt` only when something was written — on the image→video tools the
/// words describe the MOTION, so they go up as `prompt`, not `description`.
Map<String, dynamic> _promptField(String? v) {
  final t = (v ?? '').trim();
  return t.isEmpty ? const {} : {'prompt': t};
}

/// `brand_name` / `logo_url`, each only when filled in. ⚠️ The mark's wire name
/// is `logo_url`, not `brand_logo`.
Map<String, dynamic> _brandFields(String? name, String? logo) {
  final n = (name ?? '').trim();
  final l = (logo ?? '').trim();
  return {if (n.isNotEmpty) 'brand_name': n, if (l.isNotEmpty) 'logo_url': l};
}

/// `sound: true` only for "With sound" — silence keeps the old payload.
Map<String, dynamic> _soundField(String? v) => v == 'on' ? const {'sound': true} : const {};

/// ⚠️ The one place [autoColor] is NOT an omission: for the background remover
/// it means transparent, which is the whole product.
String _backgroundValue(String? v) => v == null || v.isEmpty || v == autoColor ? 'transparent' : v;

/// Transparency needs an alpha container; MP4 has none — derived, never chosen.
String _formatForBackground(String? v) => _backgroundValue(v) == 'transparent' ? 'mov' : 'mp4';

/// The nine styles the BACKEND knows by name. ⚠️ The hyphens are the backend's
/// spelling — don't "tidy" them into the underscored legacy values.
final _coreStyles = [
  MagicChoice(
    'photorealistic',
    'Photorealistic',
    desc: 'True-to-life detail',
    icon: LucideIcons.camera,
    img: _px(1707820),
  ),
  MagicChoice('cinematic', 'Cinematic', desc: 'Film-grade lighting', icon: LucideIcons.film, img: _px(2873486)),
  MagicChoice('3d-render', '3D Render', desc: 'Clean studio 3D', icon: LucideIcons.box, img: _px(28918449)),
  MagicChoice('illustration', 'Illustration', desc: 'Editorial artwork', icon: LucideIcons.brush, img: _px(19032025)),
  MagicChoice('flat-vector', 'Flat Vector', desc: 'Geometric & solid', icon: LucideIcons.penTool, img: _px(12891180)),
  MagicChoice('minimal', 'Minimal', desc: 'Clean & simple', icon: LucideIcons.minus, img: _px(1103970)),
  MagicChoice('gradient', 'Gradient', desc: 'Soft light blooms', icon: LucideIcons.blend, img: _px(7135007)),
  MagicChoice('collage', 'Collage', desc: 'Layered paper textures', icon: LucideIcons.scissors, img: _px(36591281)),
  MagicChoice('lifestyle', 'Lifestyle', desc: 'Candid & natural', icon: LucideIcons.users, img: _px(1616551)),
];

/// The styles these pickers carried before the backend published its nine.
final _legacyImageStyles = [
  MagicChoice('anime', 'Anime', desc: 'Japanese animation', icon: LucideIcons.star, img: _px(1183992)),
  MagicChoice('cartoon', 'Cartoon', desc: 'Bold & playful', icon: LucideIcons.smile, img: _px(207983)),
  MagicChoice('watercolor', 'Watercolor', desc: 'Soft painted washes', icon: LucideIcons.droplet, img: _px(1053687)),
  MagicChoice('oil_painting', 'Oil Painting', desc: 'Rich brush texture', icon: LucideIcons.palette, img: _px(1585325)),
  MagicChoice('cyberpunk', 'Cyberpunk', desc: 'Neon futuristic', icon: LucideIcons.cpu, img: _px(2311602)),
  MagicChoice('abstract', 'Abstract', desc: 'Shapes & color', icon: LucideIcons.shapes, img: _px(1616403)),
  MagicChoice('vintage', 'Vintage', desc: 'Retro film look', icon: LucideIcons.aperture, img: _px(1183434)),
  MagicChoice('neon', 'Neon / Glow', desc: 'Vivid glow', icon: LucideIcons.zap, img: _px(1631677)),
];

// ── Speaking speed ───────────────────────────────────────────────────────────

/// The words these options used to be, and the multiplier each meant — kept
/// as a translation table so a stale word still resolves.
const _speakingSpeed = {'slow': 0.75, 'normal': 1.0, 'fast': 1.25, 'rapid': 1.5};

/// The multiplier to speak at — always a usable positive number (1 when unsure).
double _speakingSpeedOf(String? v) {
  final named = _speakingSpeed[v];
  if (named != null) return named;
  final n = double.tryParse(v ?? '');
  return n != null && n.isFinite && n > 0 ? n : 1;
}

/// ⚠️ Script to Voiceover's `speaking_pace` has always been one of four WORDS;
/// the slider only chooses which.
String _paceName(String? v) {
  if (v != null && _speakingSpeed.containsKey(v)) return v;
  final n = _speakingSpeedOf(v);
  if (n < 0.9) return 'slow';
  if (n < 1.15) return 'normal';
  if (n < 1.4) return 'fast';
  return 'rapid';
}

String _speedWord(double n) {
  if (n < 0.9) return 'Slower — contemplative';
  if (n < 1.05) return 'Normal — balanced';
  if (n < 1.3) return 'Faster — energetic';
  return 'Rapid — punchy';
}

// ── Audio (magic-studio-audio.js, backend engine) ────────────────────────────

String _face(int id) =>
    'https://images.pexels.com/photos/$id/pexels-photo-$id.jpeg?auto=compress&cs=tinysrgb&h=130&w=130&fit=crop';

/// Stock portraits illustrating the voices (NOT the speaker) — dealt per
/// gender by index, so a voice keeps its face across launches.
final _voiceFaces = {
  'female': [415829, 774909, 733872, 1130626, 1181690, 1239291, 1310522, 1181519, 762020].map(_face).toList(),
  'male': [1043471, 2379004, 3831645, 2182970, 428364, 736716, 220453, 91227, 3760263].map(_face).toList(),
};

/// Aura-2's 40 voices, verbatim from the API's own enum (US English only).
const _auraVoices = [
  ('amalthea', 'f'), ('andromeda', 'f'), ('asteria', 'f'), ('athena', 'f'), //
  ('aurora', 'f'), ('callista', 'f'), ('cora', 'f'), ('cordelia', 'f'),
  ('delia', 'f'), ('electra', 'f'), ('harmonia', 'f'), ('helena', 'f'),
  ('hera', 'f'), ('iris', 'f'), ('janus', 'f'), ('juno', 'f'),
  ('luna', 'f'), ('minerva', 'f'), ('ophelia', 'f'), ('pandora', 'f'),
  ('phoebe', 'f'), ('thalia', 'f'), ('theia', 'f'), ('vesta', 'f'),
  ('apollo', 'm'), ('arcas', 'm'), ('aries', 'm'), ('atlas', 'm'),
  ('draco', 'm'), ('hermes', 'm'), ('hyperion', 'm'), ('jupiter', 'm'),
  ('mars', 'm'), ('neptune', 'm'), ('odysseus', 'm'), ('orion', 'm'),
  ('orpheus', 'm'), ('pluto', 'm'), ('saturn', 'm'), ('zeus', 'm'),
];

/// Deepgram's flagship voices — the ★.
const _auraTopVoices = {'asteria', 'luna', 'athena', 'hera', 'apollo', 'arcas', 'orion', 'zeus'};

const _defaultAuraVoice = 'asteria';

/// Voice cards for the "voices" panel (AURA_VOICE_ITEMS).
final List<MagicChoice> auraVoiceItems = () {
  final seen = {'female': 0, 'male': 0};
  return [
    for (final (id, g) in _auraVoices)
      () {
        final gender = g == 'f' ? 'female' : 'male';
        final pool = _voiceFaces[gender]!;
        final i = seen[gender]!;
        seen[gender] = i + 1;
        return MagicChoice(
          id,
          '${id[0].toUpperCase()}${id.substring(1)}',
          desc: 'US · $gender',
          icon: g == 'f' ? LucideIcons.venus : LucideIcons.mars,
          img: pool[i % pool.length],
          gender: gender,
          group: 'US $gender voices',
          top: _auraTopVoices.contains(id),
        );
      }(),
  ];
}();

final _auraIds = {for (final (id, _) in _auraVoices) id};

/// Kokoro id → nearest Aura-2 voice, same gender. A safety net for a stale
/// Kokoro id (e.g. pushed in by a refill) — translating beats a 422.
const _kokoroToAura = {
  'af_heart': 'asteria',
  'af_bella': 'luna',
  'af_nicole': 'athena',
  'af_aoede': 'aurora',
  'af_kore': 'cora',
  'af_sarah': 'callista',
  'af_alloy': 'delia',
  'af_nova': 'andromeda',
  'af_sky': 'iris',
  'af_jessica': 'juno',
  'af_river': 'phoebe',
  'am_fenrir': 'zeus',
  'am_michael': 'apollo',
  'am_puck': 'orion',
  'am_echo': 'arcas',
  'am_eric': 'atlas',
  'am_liam': 'hermes',
  'am_onyx': 'draco',
  'am_santa': 'saturn',
  'am_adam': 'mars',
  'bf_emma': 'helena',
  'bf_isabella': 'ophelia',
  'bf_alice': 'cordelia',
  'bf_lily': 'theia',
  'bm_george': 'jupiter',
  'bm_fable': 'orpheus',
  'bm_lewis': 'neptune',
  'bm_daniel': 'odysseus',
};

String _backendVoiceId(String? v) => _auraIds.contains(v) ? v! : (_kokoroToAura[v] ?? _defaultAuraVoice);

/// Whisper's language picks; `auto` is omitted from the payload so the backend
/// runs its own detection.
const _transcribeLanguages = [
  MagicChoice('auto', 'Auto Detect', flag: '🌐'),
  MagicChoice('en', 'English', flag: '🇺🇸'),
  MagicChoice('es', 'Spanish', flag: '🇪🇸'),
  MagicChoice('fr', 'French', flag: '🇫🇷'),
  MagicChoice('de', 'German', flag: '🇩🇪'),
  MagicChoice('it', 'Italian', flag: '🇮🇹'),
  MagicChoice('pt', 'Portuguese', flag: '🇧🇷'),
  MagicChoice('zh', 'Chinese', flag: '🇨🇳'),
  MagicChoice('ja', 'Japanese', flag: '🇯🇵'),
  MagicChoice('ko', 'Korean', flag: '🇰🇷'),
  MagicChoice('ar', 'Arabic', flag: '🇸🇦'),
  MagicChoice('hi', 'Hindi', flag: '🇮🇳'),
  MagicChoice('ru', 'Russian', flag: '🇷🇺'),
  MagicChoice('nl', 'Dutch', flag: '🇳🇱'),
];

// ── Video pieces ─────────────────────────────────────────────────────────────

/// ⚠️ The key is `engine`, never `model` — the web composer merges its own
/// model preference into the values as `model`, which would overwrite it.
const _engineOption = MagicOptionSpec(
  key: 'engine',
  label: 'Motion engine',
  panel: MagicPanel.list,
  defaultValue: 'fast',
  items: [
    MagicChoice('fast', 'Fast', desc: 'Quick, lively motion for the feed', icon: LucideIcons.zap),
    MagicChoice('cinematic', 'Cinematic', desc: 'High fidelity, steadier subject', icon: LucideIcons.film),
    MagicChoice('creative', 'Creative', desc: 'Looser and more inventive', icon: LucideIcons.sparkles),
  ],
);

const _motionOption = MagicOptionSpec(
  key: 'motion',
  label: 'Motion',
  panel: MagicPanel.list,
  defaultValue: 'balanced',
  items: [
    MagicChoice('subtle', 'Subtle', desc: 'Small, believable movement', icon: LucideIcons.waves),
    MagicChoice('balanced', 'Balanced', desc: 'Recommended', icon: LucideIcons.gauge),
    MagicChoice('dynamic', 'Dynamic', desc: 'Bigger camera and subject motion', icon: LucideIcons.wind),
  ],
);

const _resolutionItems = {
  '480p': MagicChoice('480p', '480p', desc: 'Fastest', icon: LucideIcons.frame),
  '720p': MagicChoice('720p', '720p', desc: 'Recommended', icon: LucideIcons.monitorPlay),
  '1080p': MagicChoice('1080p', '1080p', desc: 'Sharpest', icon: LucideIcons.expand),
  '2k': MagicChoice('2k', '2K', desc: 'Maximum detail', icon: LucideIcons.maximize2),
};

/// A factory: the tools differ on range and default, but the CARDS must match.
MagicOptionSpec _resolutionOption(List<String> values, String fallback) => MagicOptionSpec(
  key: 'resolution',
  label: 'Resolution',
  panel: MagicPanel.list,
  defaultValue: fallback,
  items: [for (final v in values) _resolutionItems[v]!],
);

/// ⚠️ ONE duration for every video tool; the 1–30 range is the provider's.
final _videoDurationOption = MagicOptionSpec(
  key: 'duration',
  label: 'Duration',
  panel: MagicPanel.slider,
  min: 1,
  max: 30,
  step: 1,
  unit: 's',
  defaultValue: '5',
  hint: (s) => s <= 5
      ? 'Quick to render'
      : s <= 10
      ? 'Short form'
      : 'Longer clips take longer to render',
);

const _soundOption = MagicOptionSpec(
  key: 'sound',
  label: 'Sound',
  panel: MagicPanel.list,
  defaultValue: 'off',
  items: [
    MagicChoice('off', 'Silent', desc: 'Video only', icon: LucideIcons.volumeX),
    MagicChoice('on', 'With sound', desc: 'Generate matching audio', icon: LucideIcons.volume2),
  ],
);

/// The narration voices — VALUES shared, row label per tool.
const _voiceItems = [
  MagicChoice('male_deep', 'Deep male', desc: 'Rich & authoritative', icon: LucideIcons.mic),
  MagicChoice('male_neutral', 'Neutral male', desc: 'Clear & professional', icon: LucideIcons.user),
  MagicChoice('female_warm', 'Warm female', desc: 'Friendly & engaging', icon: LucideIcons.heart),
  MagicChoice('female_pro', 'Pro female', desc: 'Polished & confident', icon: LucideIcons.mic),
  MagicChoice('energetic', 'Energetic', desc: 'Upbeat & exciting', icon: LucideIcons.zap),
  MagicChoice('calm', 'Calm & soothing', desc: 'Relaxed & meditative', icon: LucideIcons.leaf),
  MagicChoice('dramatic', 'Dramatic', desc: 'Powerful & intense', icon: LucideIcons.flame),
  MagicChoice('neutral_ai', 'Neutral AI', desc: 'Clean synthetic voice', icon: LucideIcons.cpu),
];

// ── Video Effects templates (videoEffectTemplates.js) ────────────────────────
//
// ⚠️ NO STILLS OR CLIPS. The web's cards show cutout.pro's showcase media from
// /public/templates/video-effects, which isn't ours and isn't shipped in this
// app (see CLAUDE.md). The cards keep their words; applying one fills the
// prompt box but — with no still to hand over — does NOT select a source
// image (the web's `imageFrom`). The user picks their own picture.

const magicCustomEffect = 'custom';

const _effectCategoryOrder = ['Camera moves', 'Portraits', 'Nature', 'Time-lapse', 'Stylised'];

const _effectTemplates = [
  MagicChoice(magicCustomEffect, 'Write your own', desc: 'Describe the motion yourself', icon: LucideIcons.wand2),
  // Camera moves
  MagicChoice(
    'rain_cyclist',
    'Puddle Splash',
    desc: 'Tracking shot, slow motion',
    category: 'Camera moves',
    icon: LucideIcons.bike,
    prompt: 'The cyclist rides through the puddle and the water throws up in a high arc, individual droplets hanging in the air before they fall. The camera tracks alongside at wheel height, holding the rider centred. Neon signage reflects off the wet road and off every droplet; the light is cold and the street is dark around it. Cinematic slow motion, dusk, high contrast.',
  ),
  MagicChoice(
    'desert_dancer',
    'Dune Orbit',
    desc: 'Low orbit, silk in the wind',
    category: 'Camera moves',
    icon: LucideIcons.wind,
    prompt: 'The dancer turns slowly on the crest of the dune and the silk robes catch the wind, lifting and folding in long fluid arcs around them. The camera orbits from a low angle, keeping the figure against the sky as the empty desert opens up behind. Warm low sun rakes across the sand and lights the fabric from behind. Wide, epic, unhurried.',
  ),
  MagicChoice(
    'canyon_flight',
    'Drone Chase',
    desc: 'Aerial descent at speed',
    category: 'Camera moves',
    icon: LucideIcons.mountain,
    prompt: 'The kayak runs the canyon at full speed, bouncing and swaying with the water rather than gliding over it, waves breaking against the hull and the rock walls. The camera drops rapidly from above and settles into a chase directly behind, holding tight through the turns. Hard daylight overhead, deep shadow in the canyon. Fast, physical, exhilarating.',
  ),
  MagicChoice(
    'dolly_zoom',
    'Dolly Zoom',
    desc: 'Vertigo push on a fixed subject',
    category: 'Camera moves',
    icon: LucideIcons.search,
    prompt: 'The figure holds still and steady in frame while the alley behind him stretches and distorts — the camera pushes in as the lens widens, so his size never changes and the background pulls away from him. Hard side light, deep shadow, haze in the air. Tense and disorienting, a classic vertigo shot.',
  ),
  // Portraits
  MagicChoice(
    'head_turn',
    'Turn and Smile',
    desc: 'Slow turn to camera',
    category: 'Portraits',
    icon: LucideIcons.smile,
    prompt: 'She completes the turn toward the camera in one smooth, natural movement, and as she arrives a warm smile spreads across her face, her eyes creasing with it. The camera holds a steady close shot. Soft light picks out the hair as it swings and settles, and catches the shine in her eyes. Slow motion, gentle, unforced.',
  ),
  MagicChoice(
    'embrace',
    'Tender Kiss',
    desc: 'Close, affectionate beat',
    category: 'Portraits',
    icon: LucideIcons.heart,
    prompt: 'The person behind leans in and kisses the other softly on one cheek, then the other, both of them smiling into it. The camera holds a close two-shot and drifts almost imperceptibly closer. Warm, soft light with no hard shadows. Intimate and unhurried, natural micro-expressions throughout.',
  ),
  MagicChoice(
    'teardrop',
    'Teardrop',
    desc: 'Super slow motion, one tear',
    category: 'Portraits',
    icon: LucideIcons.droplet,
    prompt: 'A single tear leaves the corner of the eye and rolls the whole way down, following the lines of the face, while the mouth lifts into the faintest smile. The camera holds a locked-off close-up. Dust drifts through a shaft of low light, clearly visible at this speed. Super slow motion, poetic, the expression continuous and unbroken.',
  ),
  MagicChoice(
    'dog_run',
    'Off the Lead',
    desc: 'Play in the grass',
    category: 'Portraits',
    icon: LucideIcons.dog,
    prompt: 'She lets the dog go and it bounds forward and rolls over in the grass, tail going, while she laughs and turns after a butterfly. The camera follows loosely at their height, handheld and easy. Late golden light across the field, long soft shadows. Joyful and natural, faces and coat markings staying exactly as they are.',
  ),
  // Nature
  MagicChoice(
    'wave_crash',
    'Wave on Rock',
    desc: 'Slow-motion impact',
    category: 'Nature',
    icon: LucideIcons.waves,
    prompt: 'The wave hits the cliff and explodes upward into white foam, the spray breaking apart into thousands of separate droplets that hang and then fall. The camera holds wide and steady, letting the water fill the frame. Low sun behind the spray turns every droplet into a point of light against the dark rock. Slow motion, powerful, elemental.',
  ),
  MagicChoice(
    'forest_hop',
    'Forest Dash',
    desc: 'Low tracking chase',
    category: 'Nature',
    icon: LucideIcons.rabbit,
    prompt: "The rabbit hops through the undergrowth, pauses with its ears twitching, then bolts — weaving between stems as the camera chases it. The camera stays low, at the animal's own height, moving with it. Sunlight comes through the canopy in shifting patches across the forest floor. Quick, alert, alive.",
  ),
  // Time-lapse
  MagicChoice(
    'city_timelapse',
    'Crossing, Dusk to Dawn',
    desc: 'Fixed-camera time-lapse',
    category: 'Time-lapse',
    icon: LucideIcons.building2,
    prompt: 'Traffic and pedestrians blur into continuous light trails as the crossing runs from sunset through the dark of midnight and into pale dawn. The camera never moves and the buildings never shift — only the light does: windows coming on and going out, the sky sliding from blue to black to grey. Time-lapse, stable, hypnotic.',
  ),
  MagicChoice(
    'bloom',
    'Bloom',
    desc: 'A bud opening, time-lapse',
    category: 'Time-lapse',
    icon: LucideIcons.flower2,
    prompt: 'The closed bud opens petal by petal until the flower stands fully open, the movement continuous and smooth with no jump or stutter anywhere in it. The camera holds a still close shot. Soft even light, the background falling away to nothing. Time-lapse, delicate, patient.',
  ),
  MagicChoice(
    'star_arc',
    'Star Trails',
    desc: 'Slow arc under moving stars',
    category: 'Time-lapse',
    icon: LucideIcons.stars,
    prompt: 'The stars and the Milky Way wheel overhead at a visible pace, drawing long trails across the sky, while the tree stands motionless beneath them. The camera arcs around it extremely slowly. Ambient light on the ground shifts as the moon climbs. Time-lapse, vast, still.',
  ),
  // Stylised
  MagicChoice(
    'pixel_runner',
    'Side-Scroller',
    desc: 'Retro platformer run',
    category: 'Stylised',
    icon: LucideIcons.gamepad2,
    prompt: 'The character runs steadily to the right through one hand-painted level after another, never stopping and never turning back, with the bouncing rhythm of a platformer. The camera scrolls sideways to keep pace. Bright, flat retro pixel art with a game HUD across the top. Playful and relentlessly forward-moving.',
  ),
  MagicChoice(
    'watercolor_fox',
    'Watercolour',
    desc: 'Painted, in soft focus',
    category: 'Stylised',
    icon: LucideIcons.brush,
    prompt: 'The fox turns its head slowly and settles, and the dew on the leaves around it shimmers as it moves. The camera creeps in toward its eyes. Everything is rendered as watercolour — soft brushstrokes, colours bleeding into one another, mist between the trees. Quiet, painterly, gently alive.',
  ),
  MagicChoice(
    'astronaut_drift',
    'First Contact',
    desc: 'Light ripples from a touch',
    category: 'Stylised',
    icon: LucideIcons.rocket,
    prompt: 'The astronaut reaches out and touches the mushroom, and rings of light ripple outward through the whole cluster in response, one after another. The camera pushes in slowly on the point of contact. The glow is the only real light source, throwing colour up onto the visor and the suit. Otherworldly, hushed, wondrous.',
  ),
];

/// The words a template seeds into the prompt box — "" for the custom card.
String _effectPrompt(String value) {
  for (final t in _effectTemplates) {
    if (t.value == value) return t.prompt ?? '';
  }
  return '';
}

// ── Validation helpers ───────────────────────────────────────────────────────

bool _blank(Object? input) => input == null || (input is String && input.trim().isEmpty);

// ── The configs ──────────────────────────────────────────────────────────────

final _textToImage = MagicToolConfig(
  id: 'text_to_image',
  input: MagicInputKind.prompt,
  resultType: 'image',
  generateLabel: 'Generate images',
  historyTool: 'text_to_image',
  variations: true,
  brand: true,
  inputConfig: const MagicInputConfig(
    label: 'Text prompt',
    placeholder: 'Describe the image you want to create… be specific about subject, setting, lighting, and mood.',
    maxLength: 500,
    inspire: [
      'A futuristic city at sunset with neon lights reflecting on wet streets',
      'A cozy coffee shop corner with warm lighting and rainy windows',
      'An elegant product shot of a luxury watch on dark marble',
      'A minimalist workspace with plants and golden hour light streaming in',
      'An abstract cosmic explosion of color and light in deep space',
      'A serene mountain lake at dawn with mist rolling over the water',
    ],
  ),
  options: [
    // Purpose leads: it frames every choice after it.
    _purposeOption,
    MagicOptionSpec(
      key: 'style',
      label: 'Visual style',
      panel: MagicPanel.cards,
      defaultValue: 'photorealistic',
      items: [..._coreStyles, ..._legacyImageStyles],
    ),
    _colorOption,
    _ratioOption('square', const [_ratioSquare, _ratioLandscape, _ratioPortrait, _ratioWide]),
  ],
  validate: (input, _) => _blank(input) ? 'Please enter a prompt.' : null,
  buildPayload: (input, v, n) => {
    // ⚠️ `tool` IS THE PURPOSE, not "text_to_image" — the backend routes by
    // the design type picked, so the two fields carry the same value.
    'tool': v['purpose'],
    'visual_style': v['style'],
    'ratio': ratioString(v['ratio']),
    'purpose': v['purpose'],
    'variations': n,
    ..._colorField(v['color']),
    ..._brandFields(v['brandName'], v['brandLogo']),
    'prompt': '${input ?? ''}'.trim(),
  },
);

/// Stock Image / Social Design / Ads Design: Text to Image with the Purpose
/// chip taken away and its value fixed. Their ids ARE the design-type values.
MagicToolConfig _designTool(String purpose, String placeholder) {
  final base = _textToImage;
  return MagicToolConfig(
    id: purpose,
    input: base.input,
    resultType: base.resultType,
    generateLabel: base.generateLabel,
    historyTool: purpose,
    variations: base.variations,
    brand: base.brand,
    inputConfig: base.inputConfig.withPlaceholder(placeholder),
    options: base.options.where((o) => o.key != 'purpose').toList(),
    validate: base.validate,
    buildPayload: (input, v, n) => base.buildPayload(input, {...v, 'purpose': purpose}, n),
  );
}

final _configs = <String, MagicToolConfig>{
  'text_to_image': _textToImage,
  'image-design': _designTool(
    'image-design',
    'Describe the image you want… be specific about subject, setting, lighting, and mood.',
  ),
  'social-design': _designTool(
    'social-design',
    "Describe the post you want… what it's about, the mood, and who it's for.",
  ),
  'ad-design': _designTool('ad-design', 'Describe the ad you want… the product, the offer, and the audience.'),

  // ── TEXT → VIDEO ─────────────────────────────────────────────────────────
  'text_to_video': MagicToolConfig(
    id: 'text_to_video',
    input: MagicInputKind.prompt,
    resultType: 'video',
    generateLabel: 'Generate videos',
    historyTool: 'text_to_video',
    variations: true,
    inputConfig: const MagicInputConfig(
      label: 'Video prompt',
      placeholder: 'Describe the video scene… include subject, movement, lighting, setting, and camera motion.',
      maxLength: 500,
      inspire: [
        'A luxury car driving on coastal road at sunset with cinematic motion',
        'A chef cooking in cozy kitchen with warm cinematic lighting',
        'Peaceful timelapse of stars over snowy mountains',
        'A rocket launching into space with dramatic slow-motion flames',
        'Brand product reveal with elegant lighting and smooth camera movement',
      ],
    ),
    options: [
      _purposeOption,
      MagicOptionSpec(
        key: 'style',
        label: 'Visual style',
        panel: MagicPanel.cards,
        defaultValue: 'photorealistic',
        // Named exclusions, not an index range — vintage and neon stay out
        // however the list grows.
        items: [..._coreStyles, ..._legacyImageStyles.where((s) => s.value != 'vintage' && s.value != 'neon')],
      ),
      _videoDurationOption,
      _ratioOption('landscape', const [_ratioSquare, _ratioLandscape, _ratioPortrait]),
    ],
    validate: (input, _) => _blank(input) ? 'Please enter a prompt.' : null,
    buildPayload: (input, v, n) => {
      'tool': 'text_to_video',
      'visual_style': v['style'],
      'ratio': ratioString(v['ratio']),
      'duration': v['duration'],
      'purpose': v['purpose'],
      'variations': n,
      'prompt': '${input ?? ''}'.trim(),
    },
  ),

  // ── IMAGE → VARIATIONS ───────────────────────────────────────────────────
  'image_to_variations': MagicToolConfig(
    id: 'image_to_variations',
    input: MagicInputKind.image,
    resultType: 'image',
    generateLabel: 'Generate variations',
    historyTool: 'image_to_variations',
    variations: true,
    describable: true,
    inputConfig: const MagicInputConfig(
      label: 'Source image',
      helper: 'Choose an image from your library, the web, or upload one.',
      placeholder: 'Optional — what should change, and what should stay? e.g. keep the product exactly as it is, make the background a warm studio grey',
      maxLength: 300,
    ),
    options: [
      MagicOptionSpec(
        key: 'style',
        label: 'Visual style',
        panel: MagicPanel.cards,
        defaultValue: 'photorealistic',
        // ⚠️ Two naming conventions, deliberately: the backend's nine, then
        // this tool's older title-case set.
        items: [
          ..._coreStyles,
          MagicChoice(
            'Vintage Sepia',
            'Vintage Sepia',
            desc: 'Warm retro tone',
            icon: LucideIcons.aperture,
            img: _px(1183434),
          ),
          MagicChoice(
            'Futuristic Cyberpunk',
            'Cyberpunk',
            desc: 'Neon futuristic',
            icon: LucideIcons.cpu,
            img: _px(2311602),
          ),
          MagicChoice(
            'Watercolor Painting',
            'Watercolor',
            desc: 'Soft washes',
            icon: LucideIcons.droplet,
            img: _px(1053687),
          ),
          MagicChoice('Pixel Art', 'Pixel Art', desc: 'Retro pixels', icon: LucideIcons.grid3x3, img: _px(1293269)),
          MagicChoice(
            'Oil Painting',
            'Oil Painting',
            desc: 'Rich texture',
            icon: LucideIcons.palette,
            img: _px(1585325),
          ),
          MagicChoice('Sketch Drawing', 'Sketch', desc: 'Hand-drawn', icon: LucideIcons.pencil, img: _px(1109541)),
          MagicChoice('Cartoon Style', 'Cartoon', desc: 'Bold & playful', icon: LucideIcons.smile, img: _px(207983)),
          MagicChoice('Abstract Art', 'Abstract', desc: 'Shapes & color', icon: LucideIcons.shapes, img: _px(1616403)),
        ],
      ),
      _colorOption,
    ],
    validate: (input, _) => _blank(input) ? 'Please pick a source image first.' : null,
    buildPayload: (input, v, n) => {
      'tool': 'image_to_variations',
      'visual_style': v['style'],
      'variations': n,
      ..._colorField(v['color']),
      ..._descriptionField(v['description']),
      'image_url': input,
    },
  ),

  // ── SCRIPT → VOICEOVER → VIDEO ───────────────────────────────────────────
  'script_to_voiceover': MagicToolConfig(
    id: 'script_to_voiceover',
    input: MagicInputKind.script,
    resultType: 'video',
    generateLabel: 'Generate video',
    historyTool: 'script_to_voiceover',
    variations: true,
    inputConfig: const MagicInputConfig(
      label: 'Script',
      placeholder: "Enter your script here… e.g. 'Welcome to our product launch, where innovation meets possibility…'",
      maxLength: 2000,
      inspire: [
        "Welcome to our product launch event, where innovation meets possibility. Today, we're unveiling something that will change the way you work forever.",
        'Imagine a world where your brand speaks directly to the heart of every customer. That world starts here, with a single story told the right way.',
        "The future of marketing isn't louder — it's smarter. Join thousands of brands already using AI to connect with their audience on a deeper level.",
      ],
    ),
    options: [
      _purposeOption,
      const MagicOptionSpec(
        key: 'voice',
        label: 'Voiceover style',
        panel: MagicPanel.list,
        defaultValue: 'neutral_ai',
        items: _voiceItems,
      ),
      const MagicOptionSpec(
        key: 'tone',
        label: 'Narration tone',
        panel: MagicPanel.list,
        defaultValue: 'Conversational',
        items: [
          MagicChoice('Conversational', 'Conversational', desc: 'Natural & relaxed', icon: LucideIcons.messageCircle),
          MagicChoice('Formal', 'Formal', desc: 'Structured & precise', icon: LucideIcons.landmark),
          MagicChoice('Inspirational', 'Inspirational', desc: 'Uplifting & bold', icon: LucideIcons.sparkles),
          MagicChoice('Urgent', 'Urgent', desc: 'Fast & compelling', icon: LucideIcons.alarmClock),
          MagicChoice('Storytelling', 'Storytelling', desc: 'Narrative flow', icon: LucideIcons.bookOpen),
          MagicChoice('Informative', 'Informative', desc: 'Clear & factual', icon: LucideIcons.info),
          MagicChoice('Humorous', 'Humorous', desc: 'Light & witty', icon: LucideIcons.laugh),
          MagicChoice('Empathetic', 'Empathetic', desc: 'Warm & caring', icon: LucideIcons.heart),
        ],
      ),
      // ⚠️ The 0.25 step is the point: this sends a NAME, so the four stops
      // are the four words the backend knows (see _paceName).
      const MagicOptionSpec(
        key: 'pace',
        label: 'Speaking pace',
        panel: MagicPanel.slider,
        min: 0.75,
        max: 1.5,
        step: 0.25,
        unit: '×',
        defaultValue: '1',
        hint: _speedWord,
      ),
      _ratioOption('landscape', const [_ratioSquare, _ratioLandscape, _ratioPortrait]),
      const MagicOptionSpec(
        key: 'format',
        label: 'Export format',
        panel: MagicPanel.pills,
        defaultValue: 'mp4',
        items: [
          MagicChoice('mp4', 'MP4'),
          MagicChoice('mkv', 'MKV'),
          MagicChoice('webm', 'WebM'),
          MagicChoice('mov', 'MOV'),
        ],
      ),
    ],
    validate: (input, _) => _blank(input) ? 'Please enter a script first.' : null,
    buildPayload: (input, v, n) => {
      'tool': 'script_to_voiceover',
      'visual_style': v['voice'],
      'narration_tone': v['tone'],
      'speaking_pace': _paceName(v['pace']),
      'ratio': ratioString(v['ratio']),
      'export_format': v['format'],
      'purpose': v['purpose'],
      'variations': n,
      'prompt': '${input ?? ''}'.trim(),
    },
  ),

  // ── AUDIO → TEXT (backend) ───────────────────────────────────────────────
  'audio_to_text': MagicToolConfig(
    id: 'audio_to_text',
    input: MagicInputKind.audio,
    resultType: 'text',
    generateLabel: 'Transcribe audio',
    historyTool: 'audio_to_text',
    multipartAudio: true,
    inputConfig: const MagicInputConfig(
      label: 'Audio',
      helper: 'Pick from your gallery — or upload to it right there · MP3 · WAV · OGG · M4A · WEBM · up to 100 MB',
    ),
    // Backend transcription takes `language` and nothing else.
    options: const [
      MagicOptionSpec(
        key: 'language',
        label: 'Language',
        panel: MagicPanel.flags,
        defaultValue: 'auto',
        items: _transcribeLanguages,
      ),
    ],
    validate: (input, _) => input == null ? 'Please upload or record some audio.' : null,
    // ⚠️ MULTIPART: the composer adds the file as `audio` (not `file`).
    // `language` is omitted for "auto" so the backend detects it itself.
    buildPayload: (_, v, _) => {
      'tool': 'audio_to_text',
      if (v['language'] != null && v['language'] != 'auto') 'language': v['language'],
    },
  ),

  // ── PERSONA-BASED GENERATOR ──────────────────────────────────────────────
  'persona_generator': MagicToolConfig(
    id: 'persona_generator',
    input: MagicInputKind.persona,
    resultType: 'auto',
    generateLabel: 'Generate content',
    historyTool: 'persona_generator',
    variations: true,
    describable: true,
    inputConfig: const MagicInputConfig(
      placeholder: 'Optional — what is this content about? e.g. launching a free trial for our scheduling app',
      maxLength: 300,
      personaInspire: [
        MagicPersonaExample('Amara Osei', 'Marketing Manager', 'Friendly'),
        MagicPersonaExample('Raj Patel', 'Software Engineer', 'Professional'),
        MagicPersonaExample('Sofia Reyes', 'Creative Director', 'Inspirational'),
        MagicPersonaExample('James Whitfield', 'Sales Executive', 'Bold'),
        MagicPersonaExample('Yuki Tanaka', 'Product Manager', 'Casual'),
      ],
      occupations: [
        'Marketing Manager',
        'Software Engineer',
        'Entrepreneur',
        'Sales Executive',
        'Creative Director',
        'Product Manager',
        'HR Specialist',
        'Financial Analyst',
        'Teacher',
        'Consultant',
      ],
      ageGroups: [
        (value: '18-24', label: '18–24', desc: 'Gen Z'),
        (value: '25-34', label: '25–34', desc: 'Millennial'),
        (value: '35-44', label: '35–44', desc: 'Gen X'),
        (value: '45-54', label: '45–54', desc: 'Boomer+'),
        (value: '55+', label: '55+', desc: 'Senior'),
      ],
      tones: [
        (value: 'Professional', icon: LucideIcons.briefcase),
        (value: 'Friendly', icon: LucideIcons.smile),
        (value: 'Authoritative', icon: LucideIcons.crown),
        (value: 'Casual', icon: LucideIcons.leaf),
        (value: 'Inspirational', icon: LucideIcons.sparkles),
        (value: 'Empathetic', icon: LucideIcons.heart),
        (value: 'Bold', icon: LucideIcons.flame),
        (value: 'Witty', icon: LucideIcons.laugh),
        (value: 'Formal', icon: LucideIcons.landmark),
        (value: 'Conversational', icon: LucideIcons.messageCircle),
      ],
    ),
    options: [
      const MagicOptionSpec(
        key: 'contentType',
        label: 'Content type',
        panel: MagicPanel.list,
        defaultValue: 'image',
        items: [
          MagicChoice('text', 'Text', desc: 'Copy & captions', icon: LucideIcons.fileText),
          MagicChoice('image', 'Image', desc: 'Visual content', icon: LucideIcons.fileImage),
          MagicChoice('video', 'Video', desc: 'Motion content', icon: LucideIcons.film),
        ],
      ),
      _ratioOption('square', const [_ratioSquare, _ratioLandscape, _ratioPortrait]),
    ],
    validate: (_, v) {
      if ((v['personaName'] ?? '').trim().isEmpty) return 'Please enter a persona name.';
      if ((v['personaAge'] ?? '').trim().isEmpty) return 'Please select or enter an age.';
      if ((v['personaOccupation'] ?? '').trim().isEmpty) return 'Please enter an occupation.';
      if ((v['personaTone'] ?? '').isEmpty) return 'Please select a tone.';
      return null;
    },
    buildPayload: (_, v, n) => {
      'tool': 'persona_generator',
      'name': v['personaName']?.trim(),
      'age': v['personaAge']?.trim(),
      'occupation': v['personaOccupation']?.trim(),
      'communication_tone': [v['personaTone']],
      'content_type': v['contentType'],
      'ratio': ratioString(v['ratio']),
      'variations': n,
      ..._descriptionField(v['description']),
    },
  ),

  // ── TEXT → AUDIO (backend, Aura-2 voices) ────────────────────────────────
  'text_to_audio': MagicToolConfig(
    id: 'text_to_audio',
    input: MagicInputKind.text,
    resultType: 'audio',
    generateLabel: 'Generate audio',
    historyTool: 'text_to_audio',
    inputConfig: const MagicInputConfig(
      label: 'Text to convert',
      placeholder: 'Type or paste the text you want to convert to audio… scripts, announcements, narrations, and more.',
      maxLength: 2000,
      inspire: [
        "Welcome to our product launch event. Today we're thrilled to introduce something that will change the way you work forever.",
        'In a world where every second counts, precision and speed are not just advantages — they are necessities.',
        'Thank you for joining us on this journey. Your support means everything to our team and our mission.',
        "Attention shoppers! For this weekend only, enjoy up to fifty percent off on all premium items storewide.",
      ],
    ),
    // Backend speech takes `voice` + `speaking_speed` only.
    options: [
      MagicOptionSpec(
        key: 'voice',
        label: 'Voice',
        panel: MagicPanel.voices,
        defaultValue: _defaultAuraVoice,
        items: auraVoiceItems,
      ),
      // ⚠️ 0.75–1.25 is what the backend has been SHOWN to accept.
      const MagicOptionSpec(
        key: 'speed',
        label: 'Speaking speed',
        panel: MagicPanel.slider,
        min: 0.75,
        max: 1.25,
        step: 0.05,
        unit: '×',
        defaultValue: '1',
        hint: _speedWord,
      ),
    ],
    validate: (input, _) {
      final t = '${input ?? ''}'.trim();
      if (t.isEmpty) return 'Please enter some text to convert.';
      if (t.length > 2000) return 'Text is limited to 2000 characters.';
      return null;
    },
    // ⚠️ Flat payload, and `voice` is an Aura-2 name.
    buildPayload: (input, v, _) => {
      'tool': 'text_to_audio',
      'prompt': '${input ?? ''}'.trim(),
      'voice': _backendVoiceId(v['voice']),
      'speaking_speed': _speakingSpeedOf(v['speed']),
    },
  ),

  // ── IMAGE → VIDEO ────────────────────────────────────────────────────────
  'image_to_video': MagicToolConfig(
    id: 'image_to_video',
    input: MagicInputKind.image,
    resultType: 'video',
    generateLabel: 'Generate video',
    historyTool: 'image_to_video',
    describable: true,
    // ⚠️ NO `variations`: the poll follows ONE job.
    inputConfig: const MagicInputConfig(
      label: 'Source image',
      helper: 'Choose an image from your library, the web, or upload one.',
      placeholder: 'Optional — describe the motion. e.g. the camera pushes in slowly while steam rises and the light shifts across the surface',
      maxLength: 500,
    ),
    options: [
      _engineOption,
      _motionOption,
      _videoDurationOption,
      _ratioOption('landscape', const [_ratioSquare, _ratioLandscape, _ratioPortrait]),
      _resolutionOption(const ['480p', '720p', '1080p'], '720p'),
      _soundOption,
    ],
    validate: (input, _) => _blank(input) ? 'Please pick a source image first.' : null,
    buildPayload: (input, v, _) => {
      'tool': 'image_to_video',
      'image_url': input,
      'engine': v['engine'],
      'motion': v['motion'],
      'duration': v['duration'],
      'ratio': ratioString(v['ratio']),
      'resolution': v['resolution'],
      ..._promptField(v['description']),
      ..._soundField(v['sound']),
    },
  ),

  // ── DIGITAL HUMAN ────────────────────────────────────────────────────────
  'digital_human': MagicToolConfig(
    id: 'digital_human',
    input: MagicInputKind.image,
    resultType: 'video',
    generateLabel: 'Generate video',
    historyTool: 'digital_human',
    // Direction for the performance, never the words being said.
    describable: true,
    extraInput: const MagicExtraInput(
      required: true,
      label: 'Voice track',
      helper: 'Pick the voice this portrait should speak from your gallery.',
      emptyHint: 'No voice track yet? Generate one with Text to Audio.',
    ),
    inputConfig: const MagicInputConfig(
      label: 'Portrait',
      helper: 'Choose a portrait from your library, the web, or upload one.',
      placeholder: 'Optional — how should they deliver it? e.g. warm and smiling, with a slight nod',
      maxLength: 600,
    ),
    options: [
      _resolutionOption(const ['480p', '720p', '1080p'], '720p'),
    ],
    validate: (input, v) {
      if (_blank(input)) return 'Please pick a portrait first.';
      if ((v['audioUrl'] ?? '').isEmpty) return 'Please add the voice track to lip-sync to.';
      return null;
    },
    buildPayload: (input, v, _) => {
      'tool': 'digital_human',
      'image_url': input,
      'audio_url': v['audioUrl'],
      'resolution': v['resolution'],
      ..._promptField(v['description']),
    },
  ),

  // ── VIDEO BACKGROUND REMOVER ─────────────────────────────────────────────
  'video_background_remover': MagicToolConfig(
    id: 'video_background_remover',
    input: MagicInputKind.video,
    resultType: 'video',
    generateLabel: 'Remove background',
    historyTool: 'video_background_remover',
    inputConfig: const MagicInputConfig(
      label: 'Source video',
      helper: 'Pick a video from your gallery — or upload to it right there · MP4 · MOV · WEBM · MKV · M4V · AVI · up to 50 MB',
    ),
    options: const [
      MagicOptionSpec(
        key: 'background',
        label: 'Background',
        panel: MagicPanel.colors,
        defaultValue: autoColor,
        items: [
          MagicChoice(autoColor, 'Transparent'),
          MagicChoice('#00b140', 'Green screen'),
          MagicChoice('#0047bb', 'Blue screen'),
          MagicChoice('#ffffff', 'White'),
          MagicChoice('#111827', 'Near-black'),
          MagicChoice('#f8fafc', 'Off-white'),
          MagicChoice('#2563eb', 'Blue'),
          MagicChoice('#ef4444', 'Red'),
        ],
      ),
    ],
    validate: (input, _) => _blank(input) ? 'Please pick a video to work on.' : null,
    buildPayload: (input, v, _) => {
      'tool': 'video_background_remover',
      'video_url': input,
      'background': _backgroundValue(v['background']),
      'format': _formatForBackground(v['background']),
    },
  ),

  // ── VIDEO ENHANCER ───────────────────────────────────────────────────────
  'video_enhancer': MagicToolConfig(
    id: 'video_enhancer',
    input: MagicInputKind.video,
    resultType: 'video',
    generateLabel: 'Enhance video',
    historyTool: 'video_enhancer',
    inputConfig: const MagicInputConfig(
      label: 'Source video',
      helper: 'Pick a video from your gallery — or upload to it right there · MP4 · MOV · WEBM · MKV · M4V · AVI · up to 50 MB',
    ),
    // One option, deliberately: the model decides the rest.
    options: [
      _resolutionOption(const ['1080p', '2k'], '1080p'),
    ],
    validate: (input, _) => _blank(input) ? 'Please pick a video to enhance.' : null,
    buildPayload: (input, v, _) => {'tool': 'video_enhancer', 'video_url': input, 'resolution': v['resolution']},
  ),

  // ── VIDEO EFFECTS ────────────────────────────────────────────────────────
  'video_effects': MagicToolConfig(
    id: 'video_effects',
    input: MagicInputKind.image,
    resultType: 'video',
    generateLabel: 'Apply effect',
    historyTool: 'video_effects',
    // Required, but rarely typed: a template fills the box.
    requiresPrompt: true,
    promptFrom: ('template', _effectPrompt),
    inputConfig: const MagicInputConfig(
      label: 'Source image',
      helper: 'Choose an image from your library, the web, or upload one.',
      placeholder: 'Use a template above to fill this in — or describe the motion yourself.',
      maxLength: 800,
    ),
    options: [
      const MagicOptionSpec(
        key: 'template',
        label: 'Template',
        panel: MagicPanel.templates,
        defaultValue: magicCustomEffect,
        items: _effectTemplates,
        categoryOrder: _effectCategoryOrder,
      ),
      _videoDurationOption,
    ],
    validate: (input, v) {
      if (_blank(input)) return 'Please pick a source image first.';
      if ((v['description'] ?? '').trim().isEmpty) return 'Pick an effect, or describe the motion you want.';
      return null;
    },
    // ⚠️ THE WORDS, NEVER A TEMPLATE ID — the whole template travels in `prompt`.
    buildPayload: (input, v, _) => {
      'tool': 'video_effects',
      'image_url': input,
      'prompt': (v['description'] ?? '').trim(),
      'duration': v['duration'],
    },
  ),
};

/// The config for a tool id (`getMagicConfig`), or null.
MagicToolConfig? magicConfigFor(String toolId) => _configs[toolId];

/// Ceiling on `variations` (useMagicGenerate.js MAX_VARIATIONS) — the slider's
/// max AND the clamp on what reaches the API, so the two can't drift.
const magicMaxVariations = 30;
