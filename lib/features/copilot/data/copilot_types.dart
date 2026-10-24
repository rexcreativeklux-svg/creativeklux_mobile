import 'dart:ui' show Color;

/// One starter idea / workflow — an entry of the web's `_data/ideas.js`.
///
/// ⚠️ A STANDING job with a trigger ("Every Friday…"), not a skill: the same
/// catalog feeds the /copilot home grid, the composer's suggestion chips and
/// the Workflows screen, so there is one list to keep honest.
class CopilotIdea {
  const CopilotIdea({required this.title, required this.platforms, required this.description});

  final String title;

  /// Ids from the integrations registry (`instagram`, `meta_ads`…). Empty is
  /// fine and deliberate: a brand-kit audit touches no platform.
  final List<String> platforms;
  final String description;
}

/// One skill — an entry of the web's `_data/skills.js`, invoked as `/slug`.
class CopilotSkill {
  const CopilotSkill({
    required this.slug,
    required this.surface,
    required this.description,
    this.name,
    this.category,
    this.updated,
    this.preview,
    this.tint,
    this.platforms = const [],
    this.featured = false,
  });

  final String slug;

  /// A key of the category surfaces ("Brand", "Ads"…), so the badge is the
  /// same glyph as the studio the skill runs in.
  final String surface;
  final String description;

  /// Featured skills only.
  final String? name;

  /// Browse skills only — a pill from `skillCategories`.
  final String? category;

  /// A written date ("Jun 16, 2026"), not a relative one — see skills.js.
  final String? updated;

  /// Featured only: which output mock the card draws ("brand", "campaign", "product").
  final String? preview;

  /// Featured only: the Tailwind tint class behind the preview ("bg-blue-600").
  final String? tint;
  final List<String> platforms;
  final bool featured;
}

/// One connectable platform — a row of the web's `(lib)/integrations/platforms.jsx`.
class CopilotPlatform {
  const CopilotPlatform({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.colors,
    required this.svg,
  });

  final String id;
  final String name;
  final String description;

  /// "Social" or "Advertising" (copilot/_data/connectors.js derives them from
  /// the two registry lists).
  final String category;

  /// The `iconBg` gradient's stops, top-left → bottom-right (135deg).
  final List<Color> colors;

  /// The brand's white-fill mark, as plain SVG markup.
  final String svg;
}
