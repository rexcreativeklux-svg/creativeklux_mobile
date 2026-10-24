import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// One navigation destination. Mirrors the item objects in the web's
/// `(components)/Sidebar.jsx`.
class NavItem {
  const NavItem({required this.id, required this.label, required this.path, required this.icon, this.short});

  final String id;
  final String label;
  final String path;
  final IconData icon;

  /// Bottom-bar caption — the full label doesn't fit a fifth of a phone.
  final String? short;
}

/// The "Designs" tab of the sidebar (`appsItems` on the web).
const appsItems = <NavItem>[
  NavItem(id: 'dashboard', label: 'Home', short: 'Home', path: '/', icon: LucideIcons.layoutDashboard),
  NavItem(id: 'brand', label: 'Brand Kits', path: '/brand/reuse', icon: LucideIcons.palette),
  NavItem(id: 'creatives', label: 'Creative Studio', short: 'Creative', path: '/creatives', icon: LucideIcons.folder),
  NavItem(
    id: 'product-studio',
    label: 'Product Studio',
    short: 'Product',
    path: '/product-studio',
    icon: LucideIcons.bookImage,
  ),
  NavItem(id: 'magic-studio', label: 'Magic Studio', short: 'Magic', path: '/magic-studio', icon: LucideIcons.sparkles),
  NavItem(id: 'social-content', label: 'Social', path: '/social-content', icon: LucideIcons.share2),
  // The web reaches this from the header's calendar button; on a phone the top
  // bar has no room for it, so it lives here.
  NavItem(
    id: 'content-calendar',
    label: 'Content Calendar',
    path: '/social-content/calendar',
    icon: LucideIcons.calendarCheck,
  ),
  NavItem(id: 'ads-content', label: 'Ads', path: '/ads-content', icon: LucideIcons.megaphone),
  NavItem(id: 'ad-intelligence', label: 'Ad Intelligence', path: '/ad-intelligence', icon: LucideIcons.brain),
];

/// The "Copilot" tab of the sidebar.
const copilotItems = <NavItem>[
  NavItem(id: 'copilot-home', label: 'Home', path: '/copilot', icon: LucideIcons.house),
  NavItem(id: 'copilot-all', label: 'All Copilots', path: '/copilot/all', icon: LucideIcons.layoutGrid),
];

/// The four destinations that get a permanent bottom-bar slot (`BOTTOM_NAV_IDS`).
/// Everything else lives behind "More".
const bottomNavIds = ['dashboard', 'creatives', 'magic-studio', 'product-studio'];

final bottomNavItems = [for (final id in bottomNavIds) appsItems.firstWhere((i) => i.id == id)];

/// The account menu (`bottomMenuLinks` on the web).
const accountLinks = <NavItem>[
  NavItem(id: 'profile', label: 'Profile Settings', path: '/profile', icon: LucideIcons.user),
  NavItem(id: 'gallery', label: 'Gallery', path: '/gallery', icon: LucideIcons.image),
  NavItem(id: 'integrations', label: 'Integrations', path: '/integrations', icon: LucideIcons.workflow),
  NavItem(id: 'resell', label: 'Resell', path: '/resell', icon: LucideIcons.shoppingCart),
  NavItem(id: 'billing', label: 'Plans And Billing', path: '/billing', icon: LucideIcons.creditCard),
  NavItem(id: 'help', label: 'Help', path: '/help', icon: LucideIcons.circleHelp),
];

/// Is [path] the active route for [location]? Prefix match, like `isActive()`.
bool isPathActive(String location, String path) =>
    path == '/' ? location == '/' : location == path || location.startsWith('$path/');

/// The single item in [items] that owns [location] — the LONGEST matching
/// path, so `/copilot/all` lights "All Copilots" and not "Home" as well.
String? activePathIn(List<NavItem> items, String location) {
  String? best;
  for (final item in items) {
    if (isPathActive(location, item.path) && item.path.length > (best?.length ?? -1)) best = item.path;
  }
  return best;
}
