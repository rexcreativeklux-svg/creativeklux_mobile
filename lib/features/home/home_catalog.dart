/// What the home screen shows — Pixury-style rows of video and photo cards.
///
///   Creative tab  → short looping videos (ads, beauty, drinks, fashion,
///                   tech, travel) — all lead into Magic Studio.
///   Practical tab → product videos/photos, the photo editor's quick tools,
///                   social flat lays, retail, brand kits and design posters.
///
/// Videos and most photos are curated Pexels media (`pexels_media.dart`,
/// generated). Quick-tool tiles and design posters ship as local assets.
library;

import 'pexels_media.dart';

class HomeCard {
  const HomeCard({required this.title, required this.image, required this.path, this.video, this.credit});

  final String title;

  /// Poster/photo — an `assets/…` path or a URL.
  final String image;

  /// Optional looping video (URL). Plays muted while the card is on screen.
  final String? video;

  /// Where tapping the card goes.
  final String path;

  /// Photographer / videographer, for attribution.
  final String? credit;
}

enum HomeCardStyle {
  /// Portrait card, title over the image (most rows).
  portrait,

  /// Taller portrait card for featured rows.
  tall,

  /// Small square tile with the label underneath (tools).
  tile,
}

class HomeSection {
  const HomeSection({
    required this.title,
    required this.cards,
    required this.seeAllPath,
    this.emoji,
    this.style = HomeCardStyle.portrait,
  });

  final String title;
  final String? emoji;
  final List<HomeCard> cards;
  final String seeAllPath;
  final HomeCardStyle style;
}

class HeroSlide {
  const HeroSlide({required this.title, required this.image, required this.path, this.video, this.cta = 'Try'});

  final String title;
  final String image;
  final String? video;
  final String path;
  final String cta;
}

const heroSlides = pexelsHero;

const creativeSections = [
  HomeSection(title: 'Trending', emoji: '🔥', seeAllPath: '/magic-studio', cards: pexelsTrending),
  HomeSection(title: 'Beauty & Fragrance', seeAllPath: '/magic-studio', style: HomeCardStyle.tall, cards: pexelsBeauty),
  HomeSection(title: 'Food & Drink', seeAllPath: '/magic-studio', cards: pexelsDrinks),
  HomeSection(title: 'Fashion Reels', seeAllPath: '/magic-studio', style: HomeCardStyle.tall, cards: pexelsFashion),
  HomeSection(title: 'Tech & Gadgets', seeAllPath: '/magic-studio', cards: pexelsTech),
  HomeSection(title: 'Cinematic Travel', seeAllPath: '/magic-studio', style: HomeCardStyle.tall, cards: pexelsTravel),
];

const _qt = 'assets/images/quick-tools';
const _po = 'assets/images/posters';

const practicalSections = [
  HomeSection(
    title: 'Product Videos',
    emoji: '🎬',
    seeAllPath: '/product-studio',
    style: HomeCardStyle.tall,
    cards: pexelsProductVideos,
  ),
  HomeSection(
    title: 'Quick Tools',
    seeAllPath: '/edit_a_photo',
    style: HomeCardStyle.tile,
    cards: [
      HomeCard(title: 'Bg Remover', image: '$_qt/backgroundRemover.webp', path: '/edit_a_photo'),
      HomeCard(title: 'Magic Eraser', image: '$_qt/magicEraser.webp', path: '/edit_a_photo'),
      HomeCard(title: 'Magic Grab', image: '$_qt/magicGrab.webp', path: '/edit_a_photo'),
      HomeCard(title: 'Face Cutout', image: '$_qt/faceCutout.webp', path: '/edit_a_photo'),
      HomeCard(title: 'Bg Generator', image: '$_qt/backgroundGenerator.webp', path: '/edit_a_photo'),
      HomeCard(title: 'Sketchify', image: '$_qt/sketchify.webp', path: '/edit_a_photo'),
      HomeCard(title: 'Texture', image: '$_qt/texture.webp', path: '/edit_a_photo'),
      HomeCard(title: 'Crop', image: '$_qt/crop.webp', path: '/edit_a_photo'),
      HomeCard(title: 'Blur', image: '$_qt/blur.webp', path: '/edit_a_photo'),
      HomeCard(title: 'Perspective', image: '$_qt/perspective.webp', path: '/edit_a_photo'),
    ],
  ),
  HomeSection(title: 'Product Studio', seeAllPath: '/product-studio', cards: pexelsProductPhotos),
  HomeSection(title: 'Social Flat Lays', seeAllPath: '/social-content', cards: pexelsFlatLays),
  HomeSection(title: 'Retail & Ads', seeAllPath: '/ads-content', style: HomeCardStyle.tall, cards: pexelsRetail),
  HomeSection(title: 'Brand Kits', seeAllPath: '/brand/reuse', cards: pexelsBrandKits),
  HomeSection(
    title: 'Design Templates',
    seeAllPath: '/designs',
    cards: [
      HomeCard(title: 'Happy Home Guide', image: '$_po/HappyHomeGuidePoster.png', path: '/designs?tab=posters'),
      HomeCard(title: 'Boost Market Value', image: '$_po/BoostMarketValuePoster.png', path: '/designs?tab=posters'),
      HomeCard(title: 'Client Success', image: '$_po/ClientSuccessStoryPoster.png', path: '/designs?tab=posters'),
      HomeCard(title: 'Testimonial', image: '$_po/TestimonialWordPoster.png', path: '/designs?tab=posters'),
      HomeCard(title: 'Why Customers Stay', image: '$_po/WhyCustomersStayPoster.png', path: '/designs?tab=posters'),
      HomeCard(title: 'More Than Numbers', image: '$_po/MoreThanNumbersPoster.png', path: '/designs?tab=posters'),
      HomeCard(title: 'Unlock True Value', image: '$_po/UnlockTrueValuePoster.png', path: '/designs?tab=posters'),
      HomeCard(title: 'Corporate', image: '$_po/corporate-poster.png', path: '/designs?tab=posters'),
    ],
  ),
];
