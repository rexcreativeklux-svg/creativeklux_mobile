import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Static data + pure payload builders for the editor's Magic Studio panel.
///
/// Ports, trimmed to what the editor panel uses:
///   • `design/[id]/_components/panels/magic/constants.js` (tabs, placeholder
///     styles, inspire prompts, MIN_WORDS / GEN_COUNT)
///   • the three LIVE tool configs from
///     `(dashboard)/(pages)/magic-studio/magicStudioConfigs.jsx`
///     (text_to_image, image_to_variations, persona_generator): option cards,
///     validation and the `generate` payloads.
///
/// Kept free of widgets-with-state and of the network so the payloads can be
/// unit-tested against the web's (test/magic_panel_test.dart).

// ── Tabs (constants.js MAGIC_TABS) ───────────────────────────────────────────

/// One tab of the panel. A tab with a [tool] is LIVE — it runs the same
/// generate + history endpoints as the /magic-studio page. `tool == null` is a
/// placeholder whose pipeline isn't connected yet, so Generate explains that
/// instead of calling the backend.
///
/// No video tab, same as the web: a generated clip is a Magic Studio page
/// thing; the editor panel only offers tools whose output lands on a design.
class MagicTab {
  const MagicTab(this.id, this.label, this.tool, {this.noun = ''});
  final String id;
  final String label;
  final String? tool;

  /// Button noun for placeholder tabs ("Generate graphics" / "Generate 3D").
  final String noun;
}

const magicTabs = [
  MagicTab('images', 'Images', 'text_to_image'),
  MagicTab('variations', 'Variations', 'image_to_variations'),
  MagicTab('persona', 'Persona', 'persona_generator'),
  MagicTab('graphics', 'Graphics', null, noun: 'graphics'),
  MagicTab('3d', '3D', null, noun: '3D'),
];

// ── Placeholder tabs (constants.js + useMagicGenerate.js) ────────────────────

/// Visual styles for the placeholder Graphics tab. `id` is what a request
/// would send; "none" means "let the model decide".
const placeholderStyles = [
  (id: 'none', label: 'No style'),
  (id: 'photo', label: 'Photo'),
  (id: 'digital-art', label: 'Digital art'),
  (id: '3d', label: '3D render'),
  (id: 'painting', label: 'Painting'),
  (id: 'watercolor', label: 'Watercolor'),
  (id: 'anime', label: 'Anime'),
  (id: 'neon', label: 'Neon'),
  (id: 'pixel', label: 'Pixel art'),
  (id: 'minimal', label: 'Minimal'),
];

/// Seed prompts for the placeholder tabs' "Inspire me".
const placeholderInspire = [
  'A neon-lit cyberpunk street market in the rain at night',
  'A cozy reading nook by a rain-streaked window, warm morning light',
  'A majestic snow leopard resting on a mountain ridge at dawn',
  'An astronaut floating above a glowing coral-reef planet',
  'A minimalist product shot of a matte black watch on stone',
  'A whimsical treehouse village connected by rope bridges in a forest',
  'A vintage film-style portrait of a jazz musician in golden light',
  'An abstract flowing gradient of teal, violet and coral',
];

const magicMinWords = 5;
const magicGenCount = 4;

/// Words in a prompt, the way useMagicGenerate counts them (`/\s+/` split).
int magicWordCount(String prompt) {
  final t = prompt.trim();
  return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
}

/// The placeholder tabs' "not connected" message (useMagicGenerate.js).
String notConnectedMessage(String noun) =>
    "${noun.isEmpty ? '' : noun[0].toUpperCase()}${noun.length > 1 ? noun.substring(1) : ''} generation "
    "isn't connected yet — paste your Magic Studio API to enable it.";

// ── Option cards (magicStudioConfigs.jsx) ────────────────────────────────────

enum MagicPanelKind { list, cards, colors, ratios }

class MagicOptionItem {
  const MagicOptionItem(this.value, this.label, {this.desc, this.icon, this.img, this.ratio, this.w = 1, this.h = 1});
  final String value;
  final String label;
  final String? desc;
  final IconData? icon;

  /// Pexels thumbnail for style cards; a dead one falls back to the icon panel.
  final String? img;
  final String? ratio;
  final double w;
  final double h;
}

class MagicOption {
  const MagicOption({
    required this.key,
    required this.label,
    required this.panel,
    required this.defaultValue,
    required this.items,
  });
  final String key;
  final String label;
  final MagicPanelKind panel;
  final String defaultValue;
  final List<MagicOptionItem> items;
}

/// Row summary for an option's current value (magicPanelUI.jsx `summarize`).
String summarizeOption(MagicOption option, String? value) {
  for (final i in option.items) {
    if (i.value == value) return i.label;
  }
  // A colour typed into the hex box has no item behind it — show the hex.
  if (option.panel == MagicPanelKind.colors && value != null) return value.toUpperCase();
  return value ?? '';
}

// Pexels CDN helper for the style-card thumbnails (free licence, stable URLs).
String _px(int id) => 'https://images.pexels.com/photos/$id/pexels-photo-$id.jpeg?auto=compress&cs=tinysrgb&h=300';

/// UI ratio value → the "1:1" string the backend expects; unknown values pass
/// straight through (magicStudioConfigs.jsx `ratioString`).
String ratioString(String? v) =>
    const {'square': '1:1', 'landscape': '16:9', 'portrait': '9:16', 'wide': '21:9'}[v] ?? v ?? '';

const _ratioSquare = MagicOptionItem('square', 'Square', ratio: '1:1');
const _ratioLandscape = MagicOptionItem('landscape', 'Landscape', ratio: '16:9', w: 16, h: 9);
const _ratioPortrait = MagicOptionItem('portrait', 'Portrait', ratio: '9:16', w: 9, h: 16);
const _ratioWide = MagicOptionItem('wide', 'Ultra Wide', ratio: '21:9', w: 21, h: 9);

/// What the result is FOR. The VALUES are the backend contract (design-type
/// names) — change a label freely, a value only alongside the API.
const _purposeOption = MagicOption(
  key: 'purpose',
  label: 'Purpose',
  panel: MagicPanelKind.list,
  defaultValue: 'image-design',
  items: [
    MagicOptionItem(
      'ad-design',
      'Ads',
      desc: 'Built to sell — a clear offer and a reason to click',
      icon: LucideIcons.megaphone,
    ),
    MagicOptionItem(
      'social-design',
      'Social',
      desc: 'Built for the feed — native, scrollable, shareable',
      icon: LucideIcons.share2,
    ),
    MagicOptionItem('image-design', 'General', desc: 'No particular channel in mind', icon: LucideIcons.sparkles),
  ],
);

/// "No colour in particular" — the colour option's default. The swatch grid
/// draws it as a slashed square and the payload OMITS `color` while it's
/// selected; both key off this one constant.
const autoColor = 'auto';

const _colorOption = MagicOption(
  key: 'color',
  label: 'Colour',
  panel: MagicPanelKind.colors,
  defaultValue: autoColor,
  items: [
    MagicOptionItem(autoColor, 'No preference'),
    MagicOptionItem('#2563eb', 'Blue'),
    MagicOptionItem('#0ea5e9', 'Sky'),
    MagicOptionItem('#059669', 'Emerald'),
    MagicOptionItem('#f59e0b', 'Amber'),
    MagicOptionItem('#ef4444', 'Red'),
    MagicOptionItem('#ec4899', 'Pink'),
    MagicOptionItem('#7c3aed', 'Violet'),
    MagicOptionItem('#111827', 'Near-black'),
    MagicOptionItem('#f8fafc', 'Off-white'),
  ],
);

/// The nine styles the BACKEND knows by name — the `value` is the whole
/// contract (the hyphens are the backend's spelling; don't "tidy" them).
final _coreStyles = [
  MagicOptionItem(
    'photorealistic',
    'Photorealistic',
    desc: 'True-to-life detail',
    icon: LucideIcons.camera,
    img: _px(1707820),
  ),
  MagicOptionItem('cinematic', 'Cinematic', desc: 'Film-grade lighting', icon: LucideIcons.film, img: _px(2873486)),
  MagicOptionItem('3d-render', '3D Render', desc: 'Clean studio 3D', icon: LucideIcons.box, img: _px(28918449)),
  MagicOptionItem(
    'illustration',
    'Illustration',
    desc: 'Editorial artwork',
    icon: LucideIcons.brush,
    img: _px(19032025),
  ),
  MagicOptionItem(
    'flat-vector',
    'Flat Vector',
    desc: 'Geometric & solid',
    icon: LucideIcons.penTool,
    img: _px(12891180),
  ),
  MagicOptionItem('minimal', 'Minimal', desc: 'Clean & simple', icon: LucideIcons.minus, img: _px(1103970)),
  MagicOptionItem('gradient', 'Gradient', desc: 'Soft light blooms', icon: LucideIcons.blend, img: _px(7135007)),
  MagicOptionItem('collage', 'Collage', desc: 'Layered paper textures', icon: LucideIcons.scissors, img: _px(36591281)),
  MagicOptionItem('lifestyle', 'Lifestyle', desc: 'Candid & natural', icon: LucideIcons.users, img: _px(1616551)),
];

/// The styles these pickers carried before the backend published its nine.
final _legacyImageStyles = [
  MagicOptionItem('anime', 'Anime', desc: 'Japanese animation', icon: LucideIcons.star, img: _px(1183992)),
  MagicOptionItem('cartoon', 'Cartoon', desc: 'Bold & playful', icon: LucideIcons.smile, img: _px(207983)),
  MagicOptionItem(
    'watercolor',
    'Watercolor',
    desc: 'Soft painted washes',
    icon: LucideIcons.droplet,
    img: _px(1053687),
  ),
  MagicOptionItem(
    'oil_painting',
    'Oil Painting',
    desc: 'Rich brush texture',
    icon: LucideIcons.palette,
    img: _px(1585325),
  ),
  MagicOptionItem('cyberpunk', 'Cyberpunk', desc: 'Neon futuristic', icon: LucideIcons.cpu, img: _px(2311602)),
  MagicOptionItem('abstract', 'Abstract', desc: 'Shapes & color', icon: LucideIcons.shapes, img: _px(1616403)),
  MagicOptionItem('vintage', 'Vintage', desc: 'Retro film look', icon: LucideIcons.aperture, img: _px(1183434)),
  MagicOptionItem('neon', 'Neon / Glow', desc: 'Vivid glow', icon: LucideIcons.zap, img: _px(1631677)),
];

// ── Live tool configs ─────────────────────────────────────────────────────────

enum MagicInput { prompt, image, persona }

class PersonaSeed {
  const PersonaSeed(this.name, this.occupation, this.tone);
  final String name;
  final String occupation;
  final String tone;
}

class MagicToolConfig {
  const MagicToolConfig({
    required this.id,
    required this.input,
    required this.historyTool,
    required this.generateLabel,
    required this.options,
    this.label = '',
    this.placeholder = '',
    this.helper,
    this.maxLength,
    this.inspire = const [],
    this.personaInspire = const [],
    this.occupations = const [],
    this.ageGroups = const [],
    this.tones = const [],
  });

  final String id;
  final MagicInput input;

  /// Backend `tool` enum history is filed under (POST /magic-studio/history).
  final String historyTool;
  final String generateLabel;
  final List<MagicOption> options;

  // inputConfig
  final String label;
  final String placeholder;
  final String? helper;
  final int? maxLength;
  final List<String> inspire;
  final List<PersonaSeed> personaInspire;
  final List<String> occupations;
  final List<({String value, String label})> ageGroups;
  final List<({String value, IconData icon})> tones;

  /// Values seeded from each option's default (+ the persona sub-fields), as
  /// MagicToolTab's `useState(() => seed)` does.
  Map<String, String> seedValues() => {
    for (final o in options) o.key: o.defaultValue,
    if (input == MagicInput.persona) ...{
      // Persona can produce text / image / video; only an image has anywhere to
      // go on a design, so the editor locks it (PERSONA_CONTENT_TYPE).
      'contentType': personaContentType,
      'personaName': '',
      'personaAge': '',
      'personaOccupation': '',
      'personaTone': '',
    },
  };

  /// Option rows to draw — the locked persona content type isn't a choice here.
  List<MagicOption> get optionRows =>
      options.where((o) => !(input == MagicInput.persona && o.key == 'contentType')).toList();
}

const personaContentType = 'image';

final magicToolConfigs = <String, MagicToolConfig>{
  'text_to_image': MagicToolConfig(
    id: 'text_to_image',
    input: MagicInput.prompt,
    historyTool: 'text_to_image',
    generateLabel: 'Generate images',
    label: 'Text prompt',
    placeholder: 'Describe the image you want to create… be specific about subject, setting, lighting, and mood.',
    maxLength: 500,
    inspire: const [
      'A futuristic city at sunset with neon lights reflecting on wet streets',
      'A cozy coffee shop corner with warm lighting and rainy windows',
      'An elegant product shot of a luxury watch on dark marble',
      'A minimalist workspace with plants and golden hour light streaming in',
      'An abstract cosmic explosion of color and light in deep space',
      'A serene mountain lake at dawn with mist rolling over the water',
    ],
    options: [
      // Purpose leads: it frames every choice after it.
      _purposeOption,
      MagicOption(
        key: 'style',
        label: 'Visual style',
        panel: MagicPanelKind.cards,
        defaultValue: 'photorealistic',
        items: [..._coreStyles, ..._legacyImageStyles],
      ),
      _colorOption,
      const MagicOption(
        key: 'ratio',
        label: 'Aspect ratio',
        panel: MagicPanelKind.ratios,
        defaultValue: 'square',
        items: [_ratioSquare, _ratioLandscape, _ratioPortrait, _ratioWide],
      ),
    ],
  ),
  'image_to_variations': MagicToolConfig(
    id: 'image_to_variations',
    input: MagicInput.image,
    historyTool: 'image_to_variations',
    generateLabel: 'Generate variations',
    label: 'Source image',
    helper: 'Choose an image from your library, the web, or upload one.',
    options: [
      MagicOption(
        key: 'style',
        label: 'Visual style',
        panel: MagicPanelKind.cards,
        defaultValue: 'photorealistic',
        // Two naming conventions, deliberately: the backend's nine, then this
        // tool's older title-case set (kept so no style anyone uses vanishes).
        items: [
          ..._coreStyles,
          MagicOptionItem(
            'Vintage Sepia',
            'Vintage Sepia',
            desc: 'Warm retro tone',
            icon: LucideIcons.aperture,
            img: _px(1183434),
          ),
          MagicOptionItem(
            'Futuristic Cyberpunk',
            'Cyberpunk',
            desc: 'Neon futuristic',
            icon: LucideIcons.cpu,
            img: _px(2311602),
          ),
          MagicOptionItem(
            'Watercolor Painting',
            'Watercolor',
            desc: 'Soft washes',
            icon: LucideIcons.droplet,
            img: _px(1053687),
          ),
          MagicOptionItem('Pixel Art', 'Pixel Art', desc: 'Retro pixels', icon: LucideIcons.grid3x3, img: _px(1293269)),
          MagicOptionItem(
            'Oil Painting',
            'Oil Painting',
            desc: 'Rich texture',
            icon: LucideIcons.palette,
            img: _px(1585325),
          ),
          MagicOptionItem('Sketch Drawing', 'Sketch', desc: 'Hand-drawn', icon: LucideIcons.pencil, img: _px(1109541)),
          MagicOptionItem(
            'Cartoon Style',
            'Cartoon',
            desc: 'Bold & playful',
            icon: LucideIcons.smile,
            img: _px(207983),
          ),
          MagicOptionItem(
            'Abstract Art',
            'Abstract',
            desc: 'Shapes & color',
            icon: LucideIcons.shapes,
            img: _px(1616403),
          ),
        ],
      ),
      _colorOption,
    ],
  ),
  'persona_generator': const MagicToolConfig(
    id: 'persona_generator',
    input: MagicInput.persona,
    historyTool: 'persona_generator',
    generateLabel: 'Generate content',
    personaInspire: [
      PersonaSeed('Amara Osei', 'Marketing Manager', 'Friendly'),
      PersonaSeed('Raj Patel', 'Software Engineer', 'Professional'),
      PersonaSeed('Sofia Reyes', 'Creative Director', 'Inspirational'),
      PersonaSeed('James Whitfield', 'Sales Executive', 'Bold'),
      PersonaSeed('Yuki Tanaka', 'Product Manager', 'Casual'),
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
      (value: '18-24', label: '18–24'),
      (value: '25-34', label: '25–34'),
      (value: '35-44', label: '35–44'),
      (value: '45-54', label: '45–54'),
      (value: '55+', label: '55+'),
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
    options: [
      MagicOption(
        key: 'contentType',
        label: 'Content type',
        panel: MagicPanelKind.list,
        defaultValue: 'image',
        items: [
          MagicOptionItem('text', 'Text', desc: 'Copy & captions', icon: LucideIcons.fileText),
          MagicOptionItem('image', 'Image', desc: 'Visual content', icon: LucideIcons.fileImage),
          MagicOptionItem('video', 'Video', desc: 'Motion content', icon: LucideIcons.film),
        ],
      ),
      MagicOption(
        key: 'ratio',
        label: 'Aspect ratio',
        panel: MagicPanelKind.ratios,
        defaultValue: 'square',
        items: [_ratioSquare, _ratioLandscape, _ratioPortrait],
      ),
    ],
  ),
};

// ── Validation + payloads (each config's `validate` / `generate`) ─────────────

/// Ceiling on `variations` (useMagicGenerate.js MAX_VARIATIONS).
const maxMagicVariations = 30;

/// Clamp the way useMagicGenerate does. The editor panel has no variations chip,
/// so its runs always arrive here as null → 1, exactly like the web panel.
int clampVariations(int? requested) => requested == null ? 1 : requested.clamp(1, maxMagicVariations);

/// The first problem with this input, or null (each config's `validate`).
String? validateMagicInput(String toolId, {String? input, required Map<String, String> values}) {
  switch (toolId) {
    case 'text_to_image':
      return (input ?? '').trim().isEmpty ? 'Please enter a prompt.' : null;
    case 'image_to_variations':
      return (input ?? '').isEmpty ? 'Please pick a source image first.' : null;
    case 'persona_generator':
      if ((values['personaName'] ?? '').trim().isEmpty) return 'Please enter a persona name.';
      if ((values['personaAge'] ?? '').trim().isEmpty) return 'Please select or enter an age.';
      if ((values['personaOccupation'] ?? '').trim().isEmpty) return 'Please enter an occupation.';
      if ((values['personaTone'] ?? '').isEmpty) return 'Please select a tone.';
      return null;
  }
  return 'Unknown tool.';
}

/// `color` only when a real colour was chosen — the endpoint rejects unknown
/// fields, so an untouched composer must post what it always did.
Map<String, dynamic> _colorField(String? v) => v != null && v.isNotEmpty && v != autoColor ? {'color': v} : const {};

/// `description` only when something was written (same reason).
Map<String, dynamic> _descriptionField(String? v) {
  final t = (v ?? '').trim();
  return t.isEmpty ? const {} : {'description': t};
}

/// `brand_name` / `logo_url`, each only when filled in. ⚠️ The mark's wire name
/// is `logo_url`, not `brand_logo`. The editor panel never sets either (no
/// Brand chip there), so they're absent — same as the web panel.
Map<String, dynamic> _brandFields(String? name, String? logo) {
  final n = (name ?? '').trim();
  final l = (logo ?? '').trim();
  return {if (n.isNotEmpty) 'brand_name': n, if (l.isNotEmpty) 'logo_url': l};
}

/// The POST /magic-studio/generate body for [toolId] — a port of each config's
/// `generate`. [input] is the prompt (text_to_image) or the hosted source image
/// URL (image_to_variations); persona reads [values].
Map<String, dynamic> buildMagicPayload(
  String toolId, {
  String? input,
  required Map<String, String> values,
  int? variations,
}) {
  final count = clampVariations(variations);
  switch (toolId) {
    case 'text_to_image':
      return {
        // ⚠️ `tool` IS THE PURPOSE, not "text_to_image" — the backend routes by
        // the design type picked, so the two fields carry the same value.
        'tool': values['purpose'],
        'visual_style': values['style'],
        'ratio': ratioString(values['ratio']),
        'purpose': values['purpose'],
        'variations': count,
        ..._colorField(values['color']),
        ..._brandFields(values['brandName'], values['brandLogo']),
        'prompt': (input ?? '').trim(),
      };
    case 'image_to_variations':
      return {
        'tool': 'image_to_variations',
        'visual_style': values['style'],
        'variations': count,
        ..._colorField(values['color']),
        ..._descriptionField(values['description']),
        'image_url': input,
      };
    case 'persona_generator':
      return {
        'tool': 'persona_generator',
        'name': values['personaName']?.trim(),
        'age': values['personaAge']?.trim(),
        'occupation': values['personaOccupation']?.trim(),
        'communication_tone': [values['personaTone']],
        'content_type': values['contentType'],
        'ratio': ratioString(values['ratio']),
        'variations': count,
        ..._descriptionField(values['description']),
      };
  }
  throw ArgumentError.value(toolId, 'toolId', 'not a live Magic Studio tool');
}
