import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../studio_form_kit.dart';
import 'banners_form.dart';
import 'brochure_form.dart';
import 'business_card_form.dart';
import 'digital_business_card_form.dart';
import 'flyer_form.dart';
import 'image_ads_form.dart';
import 'infographic_form.dart';
import 'logo_form.dart';
import 'packaging_form.dart';
import 'poster_form.dart';
import 'presentation_deck_form.dart';
import 'reels_form.dart';
import 'social_image_form.dart';
import 'video_ads_form.dart';

/// The web's `renderForm()` switch in `(pages)/studio/page.jsx`: which form a
/// creative + category pair shows.
Widget buildStudioForm(StudioFormHost host) => switch ((host.creative.id, host.category.id)) {
  ('ads_creative', 'image') => ImageAdsForm(host: host),
  ('ads_creative', 'video') => VideoAdsForm(host: host),
  ('designer_creative', 'logos') => LogoForm(host: host),
  ('designer_creative', 'business_cards') => BusinessCardForm(host: host),
  ('designer_creative', 'banners_print') => BannersForm(host: host),
  ('designer_creative', 'flyers') => FlyerForm(host: host),
  ('designer_creative', 'brochures') => BrochureForm(host: host),
  ('designer_creative', 'infographics') => InfographicForm(host: host),
  ('designer_creative', 'posters') => PosterForm(host: host),
  ('designer_creative', 'presentation_decks') => PresentationDeckForm(host: host),
  ('designer_creative', 'packaging') => PackagingForm(host: host),
  ('designer_creative', 'digital_biz_cards') => DigitalBusinessCardForm(host: host),
  ('social_creative', 'video') => ReelsForm(host: host),
  ('social_creative', _) => SocialImageForm(host: host),
  _ => ComingSoonForm(host: host),
};

/// The web's `<ComingSoon>` card.
class ComingSoonForm extends StatelessWidget {
  const ComingSoonForm({super.key, required this.host});

  final StudioFormHost host;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: host.color.withValues(alpha: 0.2), width: 2),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: host.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text('🚧', style: TextStyle(fontSize: 22)),
          ),
          const SizedBox(height: 12),
          Text(
            host.category.label,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray600),
          ),
          const SizedBox(height: 4),
          Text(
            "This form is coming soon. We're building it next!",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: c.gray400),
          ),
        ],
      ),
    );
  }
}
