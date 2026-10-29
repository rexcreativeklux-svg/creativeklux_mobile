import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/skins.dart';

/// One page of a section (`{label, href, icon}` in the web's SectionLayout
/// NAV_ITEMS).
class SectionTab {
  const SectionTab(this.label, this.path, this.icon);

  final String label;
  final String path;
  final IconData icon;
}

/// The phone's stand-in for the web's `SectionLayout` secondary sidebar
/// (Social Content, Ads Content, Ad Intelligence…): the section's pages as a
/// row of tabs under the top bar. Tapping one REPLACES the page (`go`), so
/// switching tabs doesn't pile up history — the web swaps the content pane
/// the same way.
///
/// Scrolls sideways when the section has more pages than fit a 360dp phone.
class SectionTabs extends StatelessWidget {
  const SectionTabs({super.key, required this.tabs, required this.location});

  final List<SectionTab> tabs;

  /// The current route, to light the active tab.
  final String location;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: context.chromeColor,
        border: Border(bottom: BorderSide(color: c.gray200)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [for (final t in tabs) _Tab(tab: t, active: location == t.path || location.startsWith('${t.path}/'))],
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({required this.tab, required this.active});

  final SectionTab tab;
  final bool active;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  @override
  void initState() {
    super.initState();
    // Each page builds its own strip, so the active tab would start scrolled
    // out of view (Socials sat cut off at the edge). Bring it in on arrival.
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Scrollable.ensureVisible(context, alignment: 0.5);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final active = widget.active;
    final c = context.colors;
    final color = active ? AppColors.blue600 : c.gray500;
    return InkWell(
      onTap: active ? null : () => context.go(tab.path),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: active ? AppColors.blue600 : Colors.transparent, width: 2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              tab.label,
              style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
