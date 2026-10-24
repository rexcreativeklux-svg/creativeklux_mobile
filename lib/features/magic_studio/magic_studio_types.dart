import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Shared types for the Magic Studio section (`/magic-studio/:tool`).
///
/// The screen (magic_studio_screen.dart) wires three parts that talk only
/// through these types:
///   • the lattice (history + this session's results)   → magic_lattice.dart
///   • the composer (prompt + per-tool options, runs it)  → magic_composer.dart
///   • the templates gallery (examples to start from)     → magic_templates.dart

// ── Tools (port of magic-studio/magicTools.js) ─────────────────────────────

class MagicStudioTool {
  const MagicStudioTool({
    required this.id,
    required this.slug,
    required this.label,
    required this.short,
    required this.working,
    required this.icon,
    this.emptyHint,
    this.backend = true,
    this.publish = false,
    this.nav = true,
    this.group,
  });

  /// Category id — the backend's `tool` enum value.
  final String id;

  /// URL segment under /magic-studio.
  final String slug;
  final String label;

  /// Compact label for pills and pickers.
  final String short;

  /// What the in-flight tile says while this tool runs. Per tool, because an
  /// image is seconds and a video is minutes.
  final String working;
  final IconData icon;
  final String? emptyHint;

  /// Whether generations persist to server history. Every tool does today
  /// (both audio tools run on the backend engine — AUDIO_ENGINE in
  /// (lib)/magic-studio-audio.js).
  final bool backend;

  /// Whether a result may go straight to the publish sheet from its ⋯ menu.
  final bool publish;

  /// `false` keeps it out of the tool picker while the route still works.
  final bool nav;

  /// The web's side-nav grouping (layout.jsx NAV_GROUPS); null = ungrouped top.
  final String? group;

  String get path => '/magic-studio/$slug';
}

const magicStudioTools = <MagicStudioTool>[
  MagicStudioTool(
    id: 'text_to_image',
    slug: 'text-to-image',
    label: 'Text to Image',
    short: 'Image',
    working: 'Painting your image…',
    publish: true,
    icon: LucideIcons.fileImage,
    // Out of the picker — Stock Image, Social Design and Ads Design cover it.
    nav: false,
  ),
  // Design tools: Text to Image with the Purpose fixed. Their ids ARE the
  // design-type values Text to Image sends as `tool`.
  MagicStudioTool(
    id: 'image-design',
    slug: 'stock-image',
    label: 'Stock Image',
    short: 'Stock',
    working: 'Painting your image…',
    publish: true,
    icon: LucideIcons.images,
  ),
  MagicStudioTool(
    id: 'social-design',
    slug: 'social-design',
    label: 'Social Design',
    short: 'Social',
    working: 'Designing your post…',
    publish: true,
    icon: LucideIcons.share2,
  ),
  MagicStudioTool(
    id: 'ad-design',
    slug: 'ads-design',
    label: 'Ads Design',
    short: 'Ads',
    working: 'Designing your ad…',
    publish: true,
    icon: LucideIcons.megaphone,
  ),
  MagicStudioTool(
    id: 'image_to_variations',
    slug: 'image-to-variations',
    label: 'Image to Variations',
    short: 'Variations',
    working: 'Spinning up variations…',
    publish: true,
    icon: LucideIcons.layers,
    group: 'Image',
  ),
  MagicStudioTool(
    id: 'persona_generator',
    slug: 'persona-generator',
    label: 'Persona-based Generator',
    short: 'Persona',
    working: "Writing in your persona's voice…",
    publish: true,
    icon: LucideIcons.user,
    group: 'Image',
  ),
  MagicStudioTool(
    id: 'text_to_video',
    slug: 'text-to-video',
    label: 'Text to Video',
    short: 'Video',
    working: 'Rendering your video — this one takes a few minutes…',
    publish: true,
    icon: LucideIcons.video,
    group: 'Video',
  ),
  MagicStudioTool(
    id: 'image_to_video',
    slug: 'image-to-video',
    label: 'Image to Video',
    short: 'Animate',
    working: 'Animating your image — this one takes a few minutes…',
    publish: true,
    icon: LucideIcons.imagePlay,
    group: 'Video',
  ),
  MagicStudioTool(
    id: 'script_to_voiceover',
    slug: 'script-to-voiceover',
    label: 'Script to Voiceover to Video',
    short: 'Voiceover',
    working: 'Recording the voiceover and cutting the video…',
    publish: true,
    icon: LucideIcons.mic,
    group: 'Video',
  ),
  MagicStudioTool(
    id: 'digital_human',
    slug: 'digital-human',
    label: 'Digital Human Video',
    short: 'Avatar',
    working: 'Bringing your portrait to life — this one takes a few minutes…',
    publish: true,
    icon: LucideIcons.speech,
    group: 'Video',
  ),
  MagicStudioTool(
    id: 'video_enhancer',
    slug: 'video-enhancer',
    label: 'Video Enhancer',
    short: 'Enhance',
    working: 'Enhancing your video — this one takes a few minutes…',
    publish: true,
    icon: LucideIcons.maximize2,
    group: 'Video',
  ),
  MagicStudioTool(
    id: 'video_effects',
    slug: 'video-effects',
    label: 'Video Effects',
    short: 'Effects',
    working: 'Applying the effect — this one takes a few minutes…',
    publish: true,
    icon: LucideIcons.wandSparkles,
    group: 'Video',
  ),
  MagicStudioTool(
    id: 'video_background_remover',
    slug: 'video-background-remover',
    label: 'Video Background Remover',
    short: 'Cut out',
    working: 'Cutting the background out — this one takes a few minutes…',
    emptyHint: 'Your cut-out clips appear here.',
    // An alpha MOV / chroma-green MP4 is an intermediate asset, not a post.
    publish: false,
    icon: LucideIcons.eraser,
    group: 'Video',
  ),
  MagicStudioTool(
    id: 'text_to_audio',
    slug: 'text-to-audio',
    label: 'Text to Audio',
    short: 'Audio',
    working: 'Generating your audio…',
    icon: LucideIcons.music,
    group: 'Audio',
  ),
  MagicStudioTool(
    id: 'audio_to_text',
    slug: 'audio-to-text',
    label: 'Audio to Text',
    short: 'Transcribe',
    working: 'Transcribing your audio…',
    emptyHint: 'Your transcript appears here.',
    icon: LucideIcons.audioLines,
    group: 'Audio',
  ),
];

MagicStudioTool? magicToolBySlug(String? slug) {
  for (final t in magicStudioTools) {
    if (t.slug == slug) return t;
  }
  return null;
}

MagicStudioTool? magicToolById(String? id) {
  for (final t in magicStudioTools) {
    if (t.id == id) return t;
  }
  return null;
}

/// The first tool in the picker — where bare `/magic-studio` lands (page.jsx).
MagicStudioTool get firstMagicTool => magicStudioTools.firstWhere((t) => t.nav);

// ── Lattice items ────────────────────────────────────────────────────────────

/// One tile on the canvas: a history asset, or a result of this session.
/// History records map from `MagicHistoryItem` (editor/magic_panel/magic_history_api.dart).
class MagicItem {
  const MagicItem({
    required this.id,
    required this.type,
    this.generationId,
    this.url,
    this.videoUrl,
    this.thumbnail,
    this.content,
    this.prompt,
    this.createdAt,
    this.tool,
  });

  final String id;

  /// For DELETE (`/magic-studio/{generationId}`); null for unsaved results.
  final String? generationId;

  /// "image" | "video" | "audio" | "text".
  final String type;
  final String? url;
  final String? videoUrl;
  final String? thumbnail;

  /// Text results (persona copy, transcripts).
  final String? content;
  final String? prompt;
  final String? createdAt;
  final String? tool;

  /// The playable/viewable media URL.
  String? get mediaUrl => videoUrl ?? url;
}

// ── Composer ↔ screen ────────────────────────────────────────────────────────

/// What the composer reports while it runs (the web's `onStatusChange`).
class MagicComposerStatus {
  const MagicComposerStatus({
    this.generating = false,
    this.progress,
    this.prompt = '',
    this.count = 1,
    this.resultType = 'image',
  });

  final bool generating;

  /// 0–1 when known, else null.
  final double? progress;
  final String prompt;

  /// How many results the run in flight will produce (placeholder tiles).
  final int count;

  /// What it will produce: "image" | "video" | "audio" | "text".
  final String resultType;
}

/// Pushed into the composer from outside (a template's "Use", or the
/// in-flight tile's ✎). [nonce] makes the same text re-apply.
class MagicRefill {
  const MagicRefill({required this.nonce, this.text, this.values, this.image, this.video});

  final int nonce;
  final String? text;

  /// Option values to preset (e.g. `{'ratio': '9:16'}`).
  final Map<String, dynamic>? values;

  /// A source image / clip for the tools that start from one.
  final String? image;
  final String? video;
}

// ── Templates ────────────────────────────────────────────────────────────────

/// One example on the Templates canvas (textToImageTemplates.js,
/// designTemplates.js, templates/*.js via mediaTemplates.js).
class MagicTemplate {
  const MagicTemplate({
    required this.id,
    required this.prompt,
    this.title,
    this.image,
    this.video,
    this.aspectRatio,
    this.values,
    this.sourceImage,
    this.sourceVideo,
    this.designFormat,
    this.category,
  });

  final String id;
  final String prompt;
  final String? title;

  /// Preview image / clip.
  final String? image;
  final String? video;

  /// width / height of the preview, for the masonry.
  final double? aspectRatio;

  /// Option values that suit this example.
  final Map<String, dynamic>? values;
  final String? sourceImage;
  final String? sourceVideo;

  /// Social/Ads designs set the ratio (`design.format`).
  final String? designFormat;
  final String? category;

  /// What "Use" pushes into the composer (the web's `applyTemplate`). A sample
  /// clip's words only caption it, so they don't seed the prompt.
  MagicRefill toRefill() => MagicRefill(
    nonce: DateTime.now().microsecondsSinceEpoch,
    text: sourceVideo != null ? '' : prompt,
    values: designFormat != null ? {'ratio': designFormat} : values,
    image: sourceImage,
    video: sourceVideo,
  );
}
