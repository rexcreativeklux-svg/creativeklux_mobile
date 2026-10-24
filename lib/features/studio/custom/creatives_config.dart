import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Port of `(pages)/studio/creatives.js`: every creative type the Custom
/// Creation studio offers and its categories (the pill row above the form).
class StudioCategory {
  const StudioCategory(this.id, this.label, {this.disabled = false});

  final String id;
  final String label;

  /// Shown greyed out with "Coming soon…", like the web.
  final bool disabled;
}

class StudioCreative {
  const StudioCreative({
    required this.id,
    required this.label,
    required this.tagline,
    required this.description,
    required this.icon,
    required this.color,
    required this.tags,
    required this.categories,
  });

  final String id;
  final String label;

  /// The small uppercase line on the chooser card ("RUN ADS").
  final String tagline;
  final String description;
  final IconData icon;
  final Color color;

  /// Example outputs listed on the chooser card.
  final List<String> tags;
  final List<StudioCategory> categories;
}

/// Only these three are offered on the web's /studio/select; Magic Studio's
/// card is commented out there and lives on its own page.
const studioCreatives = <StudioCreative>[
  StudioCreative(
    id: 'ads_creative',
    label: 'Ads Creative',
    tagline: 'Run Ads',
    description: 'Create high-converting ads for Google, Meta, TikTok & more',
    icon: LucideIcons.tv,
    color: Color(0xFF2563EB),
    tags: ['Image Ads', 'Video Ads', 'Interactive Ads'],
    categories: [
      StudioCategory('image', 'Image'),
      StudioCategory('video', 'Video'),
      StudioCategory('interactive', 'Interactive', disabled: true),
      StudioCategory('playable', 'Playable', disabled: true),
    ],
  ),
  StudioCreative(
    id: 'social_creative',
    label: 'Social Creative',
    tagline: 'Create Content',
    description: 'Posts, reels, and stories for Instagram, TikTok, LinkedIn & more',
    icon: LucideIcons.share2,
    color: Color(0xFF059669),
    tags: ['Posts', 'Reels / Stories', 'Banners / Covers'],
    // Two categories: Posts, Banners/Covers, Thumbnails and Memes are one
    // Image form with a "kind" tag row inside it (see the web's
    // forms/social/socialSizes.js).
    categories: [StudioCategory('image', 'Image'), StudioCategory('video', 'Video')],
  ),
  StudioCreative(
    id: 'designer_creative',
    label: 'Designer Creative',
    tagline: 'Design Anything',
    description: 'Logos, flyers, banners, brand assets & more',
    icon: LucideIcons.palette,
    color: Color(0xFF7C3AED),
    tags: ['Logos', 'Business Cards', 'Banners'],
    categories: [
      StudioCategory('logos', 'Logos & Brand Identity'),
      StudioCategory('business_cards', 'Business Cards'),
      StudioCategory('banners_print', 'Banners (Print & Digital)'),
      StudioCategory('flyers', 'Flyers'),
      StudioCategory('brochures', 'Brochures'),
      StudioCategory('posters', 'Posters'),
      StudioCategory('infographics', 'Infographics'),
      StudioCategory('presentation_decks', 'Presentation Decks'),
      StudioCategory('packaging', 'Packaging Mockups'),
      StudioCategory('digital_biz_cards', 'Digital Business Cards'),
    ],
  ),
];

StudioCreative creativeById(String? id) =>
    studioCreatives.firstWhere((c) => c.id == id, orElse: () => studioCreatives.first);
