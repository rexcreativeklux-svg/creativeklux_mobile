// Port of `studio/forms/social/socialSizes.js`: the Social Creative "Image"
// tab, as data.
//
// /studio?creative=social_creative used to open onto five category pills —
// Posts, Reels, Banners / Covers, Thumbnails, Memes / Trends — each with its own
// form. Four of those five make an IMAGE and differ only in what they are FOR,
// so they are one form (SocialImageForm) and the old distinction is a tag:
// [socialKinds] below. Reels makes a video and keeps its own form.
//
// ⚠️ THIS FILE IS ALSO WHERE THE TARGET PLATFORM COMES FROM. The size presets
// are platform-named — "LinkedIn Square", "Facebook Feed" — and the old forms
// ALSO asked for a platform in a separate chip row, with nothing keeping the two
// answers in agreement. The platform now hangs off the size and the field is gone.

/// One size preset.
///
/// ⚠️ THE LABEL IS THE IDENTITY, NOT THE VALUE. LinkedIn Square and Instagram
/// Square are both 1080x1080, so tracking the value alone highlights both tiles
/// and resolves the wrong template category. Labels must stay unique WITHIN a
/// kind (across kinds they may repeat — only one kind is ever on screen).
///
/// ⚠️ `platform: null` IS A DECISION, NOT A GAP. "Stories / Reels" and
/// "1:1 — Square" name a shape, not a place, so they generate with no platform
/// rather than a plausible-looking one. Do not "complete" this column.
class SocialSize {
  const SocialSize(this.value, this.label, this.platform, [this._category]);

  /// "1200x630" — the dimensions the backend gets.
  final String value;

  /// What the user reads, and this size's identity.
  final String label;

  /// Publishing platform this size implies, or null.
  final String? platform;

  final String? _category;

  /// Scraive template category. Usually the label; thumbnails carry their own
  /// (an Instagram thumbnail wants "Instagram Square" templates).
  String get category => _category ?? label;
}

/// Feed posts. The eight presets the old Posts form offered.
const _postSizes = [
  SocialSize('1200x627', 'LinkedIn Horizontal', 'linkedin'),
  SocialSize('1080x1080', 'LinkedIn Square', 'linkedin'),
  SocialSize('1080x1080', 'Instagram Square', 'instagram'),
  SocialSize('1080x1350', 'Instagram Portrait', 'instagram'),
  SocialSize('1080x1920', 'Stories / Reels', null),
  SocialSize('1200x630', 'Facebook Feed', 'facebook'),
  SocialSize('1600x900', 'Twitter / X Post', 'twitter'),
  SocialSize('1000x1500', 'Pinterest Pin', 'pinterest'),
];

// Memes run the same eight presets as posts — which is exactly why the tag row
// exists: a size alone cannot tell a meme from a post. Written out rather than
// shared, as on the web, so a future meme-only preset needn't unpick a shared list.
const _memeSizes = [
  SocialSize('1200x627', 'LinkedIn Horizontal', 'linkedin'),
  SocialSize('1080x1080', 'LinkedIn Square', 'linkedin'),
  SocialSize('1080x1080', 'Instagram Square', 'instagram'),
  SocialSize('1080x1350', 'Instagram Portrait', 'instagram'),
  SocialSize('1080x1920', 'Stories / Reels', null),
  SocialSize('1200x630', 'Facebook Feed', 'facebook'),
  SocialSize('1600x900', 'Twitter / X Post', 'twitter'),
  SocialSize('1000x1500', 'Pinterest Pin', 'pinterest'),
];

// Profile and channel covers. The display-ad banners belong to Ads Creative.
const _bannerSizes = [
  SocialSize('851x315', 'Facebook Cover', 'facebook'),
  SocialSize('1500x500', 'Twitter / X Cover', 'twitter'),
  SocialSize('1128x191', 'LinkedIn Cover', 'linkedin'),
  SocialSize('2560x1440', 'YouTube Channel Art', 'youtube'),
  SocialSize('1080x1080', '1:1 — Square', null),
];

// Thumbnails were already platform-first: the label is the platform, and the
// category keeps the Scraive sub-category the old PLATFORM_SIZES map carried.
const _thumbnailSizes = [
  SocialSize('1280x720', 'YouTube', 'youtube', 'YouTube Thumbnail'),
  SocialSize('1280x720', 'Twitch', 'twitch', 'Twitch Thumbnail'),
  SocialSize('1080x1920', 'TikTok', 'tiktok', 'TikTok Thumbnail'),
  SocialSize('1080x1080', 'Instagram', 'instagram', 'Instagram Square'),
  SocialSize('1200x627', 'LinkedIn', 'linkedin', 'LinkedIn Horizontal'),
  SocialSize('1600x900', 'X / Twitter', 'twitter', 'Twitter / X Post'),
];

/// A (value, label) option — tones and visual styles.
typedef SocialOption = ({String value, String label});

/// One kind of social image.
class SocialKind {
  const SocialKind({
    required this.id,
    required this.label,
    required this.subType,
    required this.sizeLabel,
    required this.descLabel,
    required this.descPlaceholder,
    required this.generateLabel,
    required this.sizes,
    required this.goals,
    required this.audience,
    required this.formats,
    required this.tone,
    required this.cta,
    this.styles,
  });

  /// Tag id (the web's `formData.socialKind`).
  final String id;
  final String label;

  /// ⚠️ THE BACKEND CONTRACT, AND IT MUST NOT BECOME "image". Sent as
  /// `categoryType` → `create_sub_type`, which tells the generator it is making
  /// a channel cover rather than a feed post. These are the old category ids.
  final String subType;

  /// What the size field is called for this kind.
  final String sizeLabel;
  final String descLabel;
  final String descPlaceholder;

  /// The generate button's verb.
  final String generateLabel;
  final List<SocialSize> sizes;

  /// Campaign goals — they genuinely differ per kind.
  final List<String> goals;

  /// Whether the Audience field shows. Thumbnails never asked for one.
  final bool audience;
  final List<String> formats;

  /// Post Tone field (posts + memes).
  final bool tone;

  /// Call to Action field (banners).
  final bool cta;

  /// Visual Style options, or null where the kind has no such field.
  final List<SocialOption>? styles;
}

/// The four kinds of image, in tag-row order.
const socialKinds = [
  SocialKind(
    id: 'post',
    label: 'Post',
    subType: 'posts',
    sizeLabel: 'Post Size',
    descLabel: 'Post Description',
    descPlaceholder: 'What is this post about? Describe the message, product, or story you want to tell…',
    generateLabel: 'Generate Posts',
    sizes: _postSizes,
    goals: ['Brand Awareness', 'Engagement', 'Sales', 'Lead Generation', 'Website Traffic'],
    audience: true,
    formats: ['PNG', 'JPEG', 'WEBP', 'AVIF'],
    tone: true,
    cta: false,
  ),
  SocialKind(
    id: 'banner',
    label: 'Banner / Cover',
    subType: 'banners_covers',
    sizeLabel: 'Banner Size',
    descLabel: 'Description / Brief',
    descPlaceholder: "Describe what this banner is for. What's the message? What action should viewers take?",
    generateLabel: 'Generate Banners',
    sizes: _bannerSizes,
    goals: ['Brand Awareness', 'Engagement', 'Sales', 'Lead Generation', 'Website Traffic', 'Event Registration'],
    audience: true,
    formats: ['PNG', 'JPEG', 'WEBP', 'SVG'],
    tone: false,
    cta: true,
    styles: [
      (value: 'clean', label: 'Clean'),
      (value: 'bold', label: 'Bold'),
      (value: 'minimal', label: 'Minimal'),
      (value: 'vibrant', label: 'Vibrant'),
      (value: 'corporate', label: 'Corporate'),
      (value: 'dark', label: 'Dark'),
      (value: 'modern', label: 'Modern'),
    ],
  ),
  SocialKind(
    id: 'thumbnail',
    label: 'Thumbnail',
    subType: 'thumbnails',
    sizeLabel: 'Platform',
    descLabel: 'Video Description / Context',
    descPlaceholder: 'Brief description of the video — helps the AI match the thumbnail mood…',
    generateLabel: 'Generate Thumbnails',
    sizes: _thumbnailSizes,
    goals: ['Views / Reach', 'Subscriber Growth', 'Engagement', 'Website Traffic', 'Sales / Conversions'],
    audience: false,
    formats: ['PNG', 'JPEG', 'WEBP'],
    tone: false,
    cta: false,
    styles: [
      (value: 'bold', label: 'Bold & High Contrast'),
      (value: 'clean', label: 'Clean & Minimal'),
      (value: 'dramatic', label: 'Dramatic / Cinematic'),
      (value: 'playful', label: 'Playful / Colorful'),
      (value: 'professional', label: 'Professional'),
      (value: 'retro', label: 'Retro / Vintage'),
    ],
  ),
  SocialKind(
    id: 'meme',
    label: 'Meme / Trend',
    subType: 'memes',
    sizeLabel: 'Post Size',
    descLabel: 'Post Description',
    descPlaceholder: "What's the joke or trend? Describe the format and the punchline you're going for…",
    generateLabel: 'Generate Memes',
    sizes: _memeSizes,
    goals: ['Brand Awareness', 'Engagement', 'Sales', 'Lead Generation', 'Website Traffic'],
    audience: true,
    formats: ['PNG', 'JPEG', 'WEBP', 'AVIF'],
    tone: true,
    cta: false,
  ),
];

/// Call-to-action presets — the banner kind's only list of its own.
const ctaOptions = [
  'Learn More',
  'Shop Now',
  'Get Started',
  'Register Free',
  'Download Now',
  'Book a Demo',
  'View Offer',
];

/// Audience options. Identical across every kind that asks, so declared once.
const socialAudiences = [
  (value: 'B2B', label: 'B2B', desc: 'Business owners, startups, agencies'),
  (value: 'B2C', label: 'B2C', desc: 'End consumers, everyday users'),
  (value: 'Casual', label: 'Casual', desc: 'Broad social media audience'),
  (value: 'Inspirational', label: 'Inspirational', desc: 'Entrepreneurs & creators'),
  (value: 'Sales', label: 'Sales', desc: 'Hot leads, ad audiences'),
];

/// Post / meme tone options.
const socialTones = <SocialOption>[
  (value: 'professional', label: 'Professional'),
  (value: 'casual', label: 'Casual'),
  (value: 'humorous', label: 'Humorous'),
  (value: 'inspirational', label: 'Inspirational'),
  (value: 'urgent', label: 'Urgent'),
  (value: 'educational', label: 'Educational'),
];

/// The kind a tag id names, falling back to Post — the tab's default.
SocialKind socialKindById(String? id) => socialKinds.firstWhere((k) => k.id == id, orElse: () => socialKinds.first);

/// A size within a kind, by label — falling back to that kind's first preset,
/// so a form is never in a state with a kind but no size.
SocialSize socialSizeByLabel(String kindId, String? label) {
  final sizes = socialKindById(kindId).sizes;
  return sizes.firstWhere((s) => s.label == label, orElse: () => sizes.first);
}

/// The web's `imageGate.js`: generation needs between 3 and 5 images.
const minImages = 3;
const maxImages = 5;

String imageGateMessage(int count) => 'Select at least $minImages images to generate — you have $count.';

/// Too few or too many; null when [count] is within bounds.
String? imageBoundsMessage(int count) {
  if (count > maxImages) return 'Select no more than $maxImages images to generate — you have $count.';
  if (count < minImages) return imageGateMessage(count);
  return null;
}
