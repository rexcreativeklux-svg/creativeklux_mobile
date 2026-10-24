import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/media.dart';
import '../home_catalog.dart';

/// One home row: "Title ›" with a "See all" pill on the right, then a
/// horizontally scrolling strip of cards that bleeds off the right edge.
class HomeSectionRow extends StatelessWidget {
  const HomeSectionRow({super.key, required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final width = MediaQuery.sizeOf(context).width;

    // Cards are sized off the screen so ~3.2 show on a phone (the peek of the
    // fourth says "scroll me"), and cap out on tablets.
    final (cardWidth, cardHeight) = switch (section.style) {
      HomeCardStyle.portrait => ((width * 0.29).clamp(104.0, 180.0), (width * 0.29).clamp(104.0, 180.0) * 1.23),
      HomeCardStyle.tall => ((width * 0.32).clamp(116.0, 200.0), (width * 0.32).clamp(116.0, 200.0) * 1.77),
      HomeCardStyle.tile => ((width * 0.21).clamp(76.0, 110.0), (width * 0.21).clamp(76.0, 110.0) + 26),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.push(section.seeAllPath),
                    child: Row(
                      children: [
                        if (section.emoji != null) ...[
                          Text(section.emoji!, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            section.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: c.gray900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(LucideIcons.chevronRight, size: 17, color: c.gray500),
                      ],
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => context.push(section.seeAllPath),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.gray500,
                    side: BorderSide(color: c.gray200),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  child: const Text('See all'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: section.cards.length,
              separatorBuilder: (_, _) => SizedBox(width: section.style == HomeCardStyle.tile ? 12 : 10),
              itemBuilder: (context, i) {
                final card = section.cards[i];
                return SizedBox(
                  width: cardWidth,
                  child: section.style == HomeCardStyle.tile
                      ? _ToolTile(card: card, size: cardWidth)
                      : _ImageCard(card: card),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Portrait image card with the title over a bottom gradient.
class _ImageCard extends StatelessWidget {
  const _ImageCard({required this.card});

  final HomeCard card;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.gray100,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(card.path),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (card.video != null)
              AutoplayVideo(url: card.video!, poster: card.image, posterWidth: 480)
            else
              MediaImage(card.image, cacheWidth: 480),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.55, 1],
                  colors: [Colors.transparent, Color(0xA6000000)],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Text(
                card.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Square tool tile with the label underneath.
class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.card, required this.size});

  final HomeCard card;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: () => context.push(card.path),
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: c.gray100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.gray200),
            ),
            clipBehavior: Clip.antiAlias,
            child: MediaImage(card.image, cacheWidth: 240),
          ),
          const SizedBox(height: 6),
          Text(
            card.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: c.gray700),
          ),
        ],
      ),
    );
  }
}
