import 'package:go_router/go_router.dart';

import 'ad_guard_screen.dart';
import 'ad_performance_screen.dart';
import 'ad_scorer_screen.dart';
import 'creative_comparison_screen.dart';
import 'market_spy_screen.dart';

/// The Ad Intelligence routes, for the dashboard ShellRoute. Every page keeps
/// the web's path. Bare `/ad-intelligence` forwards to the first tool, as the
/// web's `ad-intelligence/page.jsx` does.
///
/// Creative Comparison takes the web's `?image=&label=` hand-off (Magic
/// Studio's "Compare") to seed Creative A.
final adIntelligenceRoutes = <RouteBase>[
  GoRoute(path: '/ad-intelligence', redirect: (_, _) => '/ad-intelligence/ad-performance'),
  GoRoute(path: '/ad-intelligence/ad-performance', builder: (_, _) => const AdPerformanceScreen()),
  GoRoute(path: '/ad-intelligence/market-spy', builder: (_, _) => const MarketSpyScreen()),
  GoRoute(path: '/ad-intelligence/ad-guard-ai', builder: (_, _) => const AdGuardScreen()),
  GoRoute(path: '/ad-intelligence/ad-scorer-ai', builder: (_, _) => const AdScorerScreen()),
  GoRoute(
    path: '/ad-intelligence/creative-comparison',
    builder: (_, state) => CreativeComparisonScreen(
      initialImage: state.uri.queryParameters['image'],
      initialLabel: state.uri.queryParameters['label'],
    ),
  ),
];
