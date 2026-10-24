import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/skins.dart';
import '../shell/widgets/app_top_bar.dart';
import 'home_catalog.dart';
import 'widgets/hero_carousel.dart';
import 'widgets/home_section_row.dart';

/// Home, in the Pixury layout:
///
///   top bar (wordmark + round actions)       ← pinned
///   hero carousel
///   Creative | Practical tabs                ← sticks under the top bar
///   rows of horizontally scrolling cards
///
/// Replaces the web home's prompt composer + template rail; the composer is
/// reached through the first hero slide ("Create with AI") for now.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _selectTab(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    // If the tabs are already stuck to the top, jump back to the first row of
    // the new tab instead of leaving the user mid-way down a different list.
    final heroExtent = _heroHeight(context) + 28;
    if (_scroll.hasClients && _scroll.offset > heroExtent) _scroll.jumpTo(heroExtent);
  }

  double _heroHeight(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - 32;
    return (width * 0.64).clamp(190.0, 380.0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sections = _tab == 0 ? creativeSections : practicalSections;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(),
          Expanded(
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  sliver: SliverToBoxAdapter(
                    child: SizedBox(
                      height: _heroHeight(context),
                      child: HeroCarousel(slides: heroSlides),
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabsHeader(
                    tab: _tab,
                    onSelect: _selectTab,
                    background: context.chromeColor,
                    divider: c.gray200,
                    active: c.gray900,
                    inactive: c.gray500,
                  ),
                ),
                SliverList.builder(
                  itemCount: sections.length,
                  itemBuilder: (context, i) => HomeSectionRow(key: ValueKey('$_tab-$i'), section: sections[i]),
                ),
                // Attribution for the stock media (Pexels guidelines).
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
                    child: Text(
                      'Photos and videos provided by Pexels',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: c.gray400),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Creative | Practical" — two equal halves, a thick underline under the
/// active one, a hairline across the bottom.
class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({
    required this.tab,
    required this.onSelect,
    required this.background,
    required this.divider,
    required this.active,
    required this.inactive,
  });

  final int tab;
  final ValueChanged<int> onSelect;
  final Color background;
  final Color divider;
  final Color active;
  final Color inactive;

  static const _height = 46.0;
  static const _labels = ['Creative', 'Practical'];

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: background,
      child: Stack(
        children: [
          Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 1, color: divider)),
          Row(
            children: [
              for (var i = 0; i < _labels.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onSelect(i),
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 150),
                              style: TextStyle(
                                fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                                fontSize: 15,
                                fontWeight: i == tab ? FontWeight.w700 : FontWeight.w600,
                                color: i == tab ? active : inactive,
                              ),
                              child: Text(_labels[i]),
                            ),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 3,
                          color: i == tab ? active : Colors.transparent,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_TabsHeader old) =>
      old.tab != tab || old.background != background || old.active != active || old.inactive != inactive;
}
