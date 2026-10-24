import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import 'copilot_catalog.dart';
import 'copilot_types.dart';

// Hand-ported copilot data that is too small (or too tied to lucide / Tailwind
// classes) to be worth generating. The big lists — ideas, skills, platforms —
// are GENERATED into copilot_catalog.dart by tool/copilot/gen.mjs.

/// Tailwind v4 colours the copilot screens name by class, resolved once.
/// `bg-blue-600` follows the skin accent, as `--color-blue-600` does on the web.
class Tw {
  Tw._();
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald500 = Color(0xFF00BC7D);
  static const emerald600 = Color(0xFF009966);
  static const emerald700 = Color(0xFF007A55);
  static const orange400 = Color(0xFFFF8904);
  static const orange500 = Color(0xFFFF6900);
  static const orange600 = Color(0xFFF54900);
  static const violet100 = Color(0xFFEDE9FE);
  static const violet200 = Color(0xFFDDD6FF);
  static const violet500 = Color(0xFF8E51FF);
  static const violet600 = Color(0xFF7F22FE);
  static const rose200 = Color(0xFFFFCCD3);
  static const rose400 = Color(0xFFFF637E);
  static const rose500 = Color(0xFFFF2056);
  static const cyan600 = Color(0xFF0092B8);
  static const amber500 = Color(0xFFFE9A00);
  static const amber300 = Color(0xFFFFD230);
  static const amber700 = Color(0xFFBB4D00);
  static const red200 = Color(0xFFFFC9C9);
  static const red700 = Color(0xFFC10007);
  static const red900 = Color(0xFF82181A);
  static const gray900 = Color(0xFF101828);

  /// A `bg-*` class from the web's data (featured skill tints).
  static Color bg(String? cls) => switch (cls) {
    'bg-orange-500' => orange500,
    'bg-violet-600' => violet600,
    'bg-emerald-600' => emerald600,
    'bg-rose-500' => rose500,
    'bg-cyan-600' => cyan600,
    _ => AppColors.blue600,
  };
}

// ── Surfaces (_data/surfaces.js) ────────────────────────────────────────────

/// Which part of the app a workflow runs in — the badge every workflow card
/// carries, whether or not it touches an outside platform.
class CategorySurface {
  const CategorySurface(this.name, this.icon, this.color, this.blurb);
  final String name;
  final IconData icon;
  final Color color;

  /// What the surface lets a copilot DO, in one line.
  final String blurb;
}

const categorySurfaces = <String, CategorySurface>{
  'Brand': CategorySurface(
    'Brand Kits',
    LucideIcons.palette,
    Color(0xFF2563EB),
    "Read your kit's colors, fonts, logo and voice — and flag work that drifts from them.",
  ),
  'Social': CategorySurface(
    'Social Content',
    LucideIcons.share2,
    Color(0xFF059669),
    'Draft posts, size them per platform, and load them into your calendar.',
  ),
  'Ads': CategorySurface(
    'Ads Content',
    LucideIcons.megaphone,
    Color(0xFFF97316),
    'Build ad sets, variants and headlines, and stage them ready to run.',
  ),
  'Performance': CategorySurface(
    'Ad Intelligence',
    LucideIcons.brain,
    Color(0xFFE11D48),
    'Score creatives, watch competitors, and call which ad to scale or cut.',
  ),
  'Product': CategorySurface(
    'Product Studio',
    LucideIcons.bookImage,
    Color(0xFF7C3AED),
    'Clean up product photos, stage them in bulk, and turn them into video.',
  ),
  'Studio': CategorySurface(
    'Magic Studio',
    LucideIcons.sparkles,
    Color(0xFF0891B2),
    'Generate images, voiceovers and video from a prompt or a script.',
  ),
};

// ── Platforms / connectors (_data/connectors.js) ────────────────────────────

final Map<String, CopilotPlatform> platformsById = {for (final p in copilotPlatforms) p.id: p};

/// Category filter options: "All" first, then whatever the catalog holds.
final List<String> connectorCategories = [
  'All',
  ...({for (final p in copilotPlatforms) p.category}.toList()..sort()),
];

/// Sort options, in menu order. ⚠️ The catalog's own order IS "Most popular",
/// and its reverse is "Newest" — platforms are appended as they are added.
const connectorSorts = ['Most popular', 'Newest', 'A-Z', 'Z-A'];

List<CopilotPlatform> sortConnectors(List<CopilotPlatform> list, String sort) => switch (sort) {
  'Newest' => list.reversed.toList(),
  'A-Z' => [...list]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
  'Z-A' => [...list]..sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase())),
  _ => list,
};

// ── Skills (_data/skills.js helpers) ────────────────────────────────────────

/// Featured and browse skills as one list — what the browse sheet searches.
final List<CopilotSkill> allSkills = [...featuredSkills, ...browseSkills];

/// ⚠️ THE SLASH COMMAND IS THE PROMPT: activating drafts `/slug ` and stops.
String skillPrompt(String slug) => '/$slug ';

// ── Channels (_data/channels.js) ────────────────────────────────────────────

/// The reassurance line under every channel's steps — one promise, one string.
const channelPrivacyNote = 'We only see messages you send to your copilot. You can disconnect anytime.';

class ChannelStep {
  const ChannelStep(this.title, this.body);
  final String title;
  final String body;
}

/// A messaging channel a copilot can be carried on — deliberately separate
/// from the publishing platforms (see channels.js).
///
/// ⚠️ Lucide stand-ins on each service's colour, not the real marks — same as
/// the web, until the channels are wired.
class CopilotChannel {
  const CopilotChannel({
    required this.id,
    required this.label,
    required this.short,
    required this.icon,
    required this.tint,
    required this.blurb,
    required this.hero,
    required this.cta,
    required this.surface,
    required this.bubble,
    required this.steps,
    this.joinPhrase,
  });

  final String id;
  final String label;
  final String short;
  final IconData icon;
  final Color tint;
  final String blurb;

  /// The flat colour behind the preview — from each channel's design, not
  /// the service's brand colour.
  final Color hero;
  final String cta;

  /// The preview thread's background and outgoing-bubble colour.
  final Color surface;
  final Color bubble;
  final List<ChannelStep> steps;

  /// Prepends a "join the test number" step (WhatsApp sandbox only).
  final String? joinPhrase;
}

/// `NEXT_PUBLIC_WHATSAPP_SANDBOX_JOIN` on the web. Pass it with
/// `--dart-define=WHATSAPP_SANDBOX_JOIN=…` while on Twilio's sandbox number.
const _sandboxJoin = String.fromEnvironment('WHATSAPP_SANDBOX_JOIN');

const copilotChannels = [
  CopilotChannel(
    id: 'whatsapp',
    label: 'Continue on WhatsApp',
    short: 'WhatsApp',
    icon: LucideIcons.messageCircle,
    tint: Color(0xFF25D366),
    blurb: 'Chat with your copilot on WhatsApp. Scan the QR code and send the message it fills in.',
    hero: Color(0xFFF97316),
    cta: 'Open WhatsApp',
    joinPhrase: _sandboxJoin == '' ? null : _sandboxJoin,
    surface: Color(0xFFEFE7DE),
    bubble: Color(0xFFDCF8C6),
    steps: [
      ChannelStep('Scan the QR code or click the button', 'WhatsApp opens with your link message already typed in.'),
      ChannelStep(
        'Send the link message',
        'Send it as it is. Your copilot says hello, and from then on it answers every message from this number.',
      ),
    ],
  ),
  CopilotChannel(
    id: 'telegram',
    label: 'Continue on Telegram',
    short: 'Telegram',
    icon: LucideIcons.send,
    tint: Color(0xFF229ED9),
    blurb: "Chat with your copilot on Telegram. Scan the QR code, tap Start, and you're connected.",
    hero: Color(0xFFDCEB6E),
    cta: 'Open Telegram',
    surface: Color(0xFFCFE3F2),
    bubble: Color(0xFFE1FFC7),
    steps: [
      ChannelStep('Scan the QR code or click the button', 'Telegram opens the Creative Klux bot.'),
      ChannelStep(
        'Tap Start',
        "That links this chat to your copilot, with no code to type. If Start doesn't appear, send the link message instead.",
      ),
    ],
  ),
];

CopilotChannel? channelById(String? id) => copilotChannels.where((c) => c.id == id).firstOrNull;

// ── Greetings (_data/copilotGreetings.js) ───────────────────────────────────

/// `lead` + one blue `accent` + `tail` — the line's only emphasis.
class HeroLine {
  const HeroLine(this.lead, this.accent, this.tail);
  final String lead;
  final String accent;
  final String tail;
}

/// The question under "Hey `name`,". Every one is answerable by typing.
const copilotOpeners = [
  HeroLine('What can I', 'do for you', ' today?'),
  HeroLine('What should we', 'get done', '?'),
  HeroLine("What's", 'on your plate', '?'),
  HeroLine('What do you want to', 'hand over', '?'),
  HeroLine('Where should we', 'start', '?'),
  HeroLine('What are we', 'making', ' today?'),
  HeroLine('What can I', 'take off you', '?'),
];

/// The line under the question. ⚠️ A different length from the openers (5
/// against 7), so the two lines don't move in lockstep.
const copilotSubheadings = [
  HeroLine('Ask for something once, or set it to', 'run every week', '.'),
  HeroLine("Tell me the outcome and I'll", 'handle the steps', '.'),
  HeroLine('Everything I make comes out in your', "brand's colors and fonts", '.'),
  HeroLine('Designs, posts, ads or product shots —', 'just say which', '.'),
  HeroLine("I'll bring the work back for your", 'review', ', never straight out the door.'),
];

/// The line this hour lands on — rotates on the CLOCK, not the load (see the
/// ⚠️ in copilotGreetings.js), identical for every reader at the same moment.
T lineForNow<T>(List<T> pool, [DateTime? now]) =>
    pool[((now ?? DateTime.now()).millisecondsSinceEpoch ~/ 3600000) % pool.length];

// ── Introductions (_data/copilotIntros.js) ──────────────────────────────────

String _hello(String name) => name.isNotEmpty ? 'Hey $name — great to meet you!' : 'Hey there — great to meet you!';

final List<String Function(String name, String copilotName)> _intros = [
  (name, cn) => '''${_hello(name)} I'm **$cn**, your new copilot.

Here's what I can take off your plate:

- **Brand** — keep every design on your brand kit's colors, fonts and logo
- **Social** — draft posts in your voice, resize them per platform and fill your calendar
- **Ads** — build ad sets and variants, and check them for policy issues before launch
- **Performance** — score creatives, break down competitors' ads and tell you what to scale
- **Product** — clean up product photos, stage lifestyle shots and cut short videos
- **Studio** — turn scripts into voiceovers and videos, and generate image variations

I can run any of these on a schedule as a workflow, and you can reach me on WhatsApp or Telegram once you connect them.

So — what should I take on first?''',
  (name, cn) => '''${_hello(name)} **$cn** here.

Think of me as a teammate for your creative work rather than another tool to open. A few things I'm good at:

- Checking new designs against your **brand kit** and flagging anything that drifts
- Planning a week of **social posts**, sized for every platform
- Building and refreshing **ad creative**, then telling you which version is winning
- Turning **product photos** into launch-ready shots and short videos
- Writing **scripts, voiceovers and captions** from the content you already have

Not sure where to start? Tell me about your brand and your week, and I'll suggest where I'd help most.

What's first?''',
  (name, cn) => '''${_hello(name)} I'm **$cn**.

I work across Creative Klux, so you can hand me whole jobs, not just questions:

1. **Make** — designs, posts, ads, product shots and videos in your brand's style
2. **Check** — brand consistency, ad policy and creative scores before anything goes live
3. **Watch** — your competitors, your trends and how your creative is performing

Give me something once, or set it up as a workflow and I'll keep doing it — and we can pick this up on WhatsApp or Telegram whenever you're away from your desk.

What would you like handled?''',
  (name, cn) => '''${_hello(name)} I'm **$cn** — glad you're here.

I'm built for the creative side of running a brand. The busywork between *having an idea* and *having it live* is where I'm most useful:

- Turning one design into every size each platform needs
- Drafting captions, headlines and ad copy in your brand voice
- Scoring creatives before you spend on them
- Keeping an eye on what your competitors are running

Tell me what's on your list this week and I'll pick something up.

Where should we start?''',
  (name, cn) => '''${_hello(name)} **$cn**, reporting for duty.

Quick rundown of how I can help:

**Before you post** — I'll check it against your brand kit and your brand voice.

**Before you launch** — I'll run your ads through a policy check and give each creative a score.

**After it's live** — I'll tell you what's working, what's fading and what to make next.

You can ask me for something once, or turn it into a workflow that runs on a schedule.

What should I look at first?''',
  (name, cn) => '''${_hello(name)} I'm **$cn**.

Here are a few things people usually hand me first:

- *"Plan next week's posts for Instagram and TikTok."*
- *"Clean up these product photos and give me lifestyle shots."*
- *"Tell me which of my running ads to scale and which to cut."*
- *"Turn this script into a voiceover video."*

Any of those sound useful? Or tell me what you're working on and we'll go from there.''',
  (name, cn) => '''${_hello(name)} **$cn** here, ready to get to work.

The more I know about your brand, the better I get — so feel free to start by telling me who you're selling to and what you're launching next.

In the meantime, I can already:

1. **Create** posts, ads, banners and product shots in your brand's style
2. **Resize and repurpose** what you've made for every platform
3. **Analyse** your creative and your competitors', and tell you what to change

And once you connect WhatsApp or Telegram, you can message me from there too.

What's the first job?''',
  (name, cn) => '''${_hello(name)} Meet **$cn**, your creative copilot.

I can keep things moving even when you're busy — drafting the week's content, refreshing tired ads, restaging best-sellers for the season, or pulling a quick performance recap every Monday.

Set something up once as a workflow and I'll keep it running, or just ask whenever you need a hand.

So — what can I take care of for you?''',
];

/// The opening message for a copilot that was just created (Markdown).
/// Several variants, picked at random — three new copilots in a row should
/// not sound like one bot in different names.
String copilotIntro({String? copilotName, String? userName}) =>
    _intros[Random().nextInt(_intros.length)](userName ?? '', copilotName ?? 'your copilot');

// ── Settings: models + voices (General panel) ───────────────────────────────

class PickOption {
  const PickOption(this.id, this.label, {this.description, this.icon, this.svg, this.group});
  final String id;
  final String label;
  final String? description;
  final IconData? icon;

  /// A vendor mark (currentColor), drawn instead of [icon].
  final String? svg;
  final String? group;
}

class PickGroup {
  const PickGroup(this.id, this.label, {this.svg});
  final String id;
  final String label;
  final String? svg;
}

/// (components)/studio/composerModel.js `MODEL_GROUPS`.
const modelGroups = [PickGroup('claude', 'Claude', svg: claudeSvg), PickGroup('gpt', 'GPT', svg: openAiSvg)];

/// Let the backend pick per request — the default, and the first row.
const automaticModel = PickOption(
  'automatic',
  'Automatic',
  description: 'Matched with the best model for each request',
  icon: LucideIcons.sparkles,
);

/// `AUTOMATIC` + composerModel.js `MODEL_OPTIONS` — the studio's own line-up,
/// so a copilot cannot offer a model the studio cannot run.
const modelChoices = [
  automaticModel,
  PickOption('claude-sonnet-5', 'Claude Sonnet 5', group: 'claude', svg: claudeSvg),
  PickOption('claude-opus-5', 'Claude Opus 5', group: 'claude', svg: claudeSvg),
  PickOption('claude-opus-4-8', 'Claude Opus 4.8', group: 'claude', svg: claudeSvg),
  PickOption('claude-haiku-4-5', 'Claude Haiku 4.5', group: 'claude', svg: claudeSvg),
  PickOption('gpt-5.6-sol', 'GPT-5.6 Sol', group: 'gpt', svg: openAiSvg),
  PickOption('gpt-5.6-terra', 'GPT-5.6 Terra', group: 'gpt', svg: openAiSvg),
  PickOption('gpt-5.3-codex', 'GPT-5.3 Codex', group: 'gpt', svg: openAiSvg),
  PickOption('gpt-5.2-pro', 'GPT-5.2 Pro', group: 'gpt', svg: openAiSvg),
  PickOption('gpt-5.2', 'GPT-5.2', group: 'gpt', svg: openAiSvg),
  PickOption('gpt-5.1', 'GPT-5.1', group: 'gpt', svg: openAiSvg),
  PickOption('gpt-5-pro', 'GPT-5 Pro', group: 'gpt', svg: openAiSvg),
  PickOption('gpt-5', 'GPT-5', group: 'gpt', svg: openAiSvg),
  PickOption('gpt-5-mini', 'GPT-5 Mini', group: 'gpt', svg: openAiSvg),
  PickOption('gpt-5-nano', 'GPT-5 Nano', group: 'gpt', svg: openAiSvg),
  PickOption('gpt-4.1', 'GPT-4.1', group: 'gpt', svg: openAiSvg),
  PickOption('gpt-4.1-mini', 'GPT-4.1 Mini', group: 'gpt', svg: openAiSvg),
  PickOption('gpt-4o', 'GPT-4o', group: 'gpt', svg: openAiSvg),
  PickOption('gpt-4o-mini', 'GPT-4o Mini', group: 'gpt', svg: openAiSvg),
];

/// (lib)/ai-engine/models.js `KOKORO_TTS.voices` — the 28 voices Magic Studio
/// speaks with; each has a clip under the web app's /voice-samples/.
const _voices = [
  ('af_heart', 'Heart', 'female', 'US'),
  ('af_bella', 'Bella', 'female', 'US'),
  ('af_nicole', 'Nicole', 'female', 'US'),
  ('af_aoede', 'Aoede', 'female', 'US'),
  ('af_kore', 'Kore', 'female', 'US'),
  ('af_sarah', 'Sarah', 'female', 'US'),
  ('af_alloy', 'Alloy', 'female', 'US'),
  ('af_nova', 'Nova', 'female', 'US'),
  ('af_sky', 'Sky', 'female', 'US'),
  ('af_jessica', 'Jessica', 'female', 'US'),
  ('af_river', 'River', 'female', 'US'),
  ('am_fenrir', 'Fenrir', 'male', 'US'),
  ('am_michael', 'Michael', 'male', 'US'),
  ('am_puck', 'Puck', 'male', 'US'),
  ('am_echo', 'Echo', 'male', 'US'),
  ('am_eric', 'Eric', 'male', 'US'),
  ('am_liam', 'Liam', 'male', 'US'),
  ('am_onyx', 'Onyx', 'male', 'US'),
  ('am_santa', 'Santa', 'male', 'US'),
  ('am_adam', 'Adam', 'male', 'US'),
  ('bf_emma', 'Emma', 'female', 'British'),
  ('bf_isabella', 'Isabella', 'female', 'British'),
  ('bf_alice', 'Alice', 'female', 'British'),
  ('bf_lily', 'Lily', 'female', 'British'),
  ('bm_george', 'George', 'male', 'British'),
  ('bm_fable', 'Fable', 'male', 'British'),
  ('bm_lewis', 'Lewis', 'male', 'British'),
  ('bm_daniel', 'Daniel', 'male', 'British'),
];

final List<PickOption> voiceOptions = [
  for (final (id, name, gender, accent) in _voices)
    PickOption(id, name, description: '$accent · $gender', group: accent),
];

/// Grouped by accent, in the order the list already has.
final List<PickGroup> voiceGroups = [
  for (final accent in {for (final v in _voices) v.$4}) PickGroup(accent, '$accent voices'),
];

/// Kokoro's best-graded voice, and Magic Studio's default too.
const defaultVoice = 'af_heart';
