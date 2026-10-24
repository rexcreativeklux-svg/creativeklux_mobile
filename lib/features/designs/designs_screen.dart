import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import '../shell/widgets/app_top_bar.dart';
import 'posters.dart';
import 'template_card.dart';
import 'template_details_sheet.dart';
import 'templates_api.dart';

// /designs — the app's Templates screen. Two tabs:
//
//   "Klux Templates" (default) → the public template pool, ported from the web
//       home rail's Templates tab (app/(components)/studio/TemplatesSection.jsx,
//       TemplateCard.jsx, TemplateDetailsModal.jsx, templatesApi.js). The web's
//       "Browse all" on that tab links to /designs, which on the web is only
//       the static poster gallery — here /designs is where that link lands.
//   "Posters" (`?tab=posters`) → the web's actual /designs page
//       ((dashboard)/(pages)/designs/DesignsLayout.jsx), see posters.dart.
//
// The pool endpoint answers a RANDOM 20 of ~200 templates and takes no filters
// or paging (templates_api.dart), so there's nothing to search or filter
// server-side — the web rail has neither. A full page with only one draw felt
// thin, so "Show more" pulls another draw and appends the templates not seen
// yet, and pull-to-refresh starts over with a fresh one.
//
// `?template=<slug>&name=…` (the web's share link) opens that template's
// details sheet on load, resolved exactly from its CDN object.

const _tabPosters = 'posters';

class DesignsScreen extends StatefulWidget {
  const DesignsScreen({super.key, this.initialTab});

  /// `posters` opens the Posters tab; anything else the Klux tab.
  final String? initialTab;

  @override
  State<DesignsScreen> createState() => _DesignsScreenState();
}

class _DesignsScreenState extends State<DesignsScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this, initialIndex: _indexOf(widget.initialTab));

  /// Card previews, shared by the grid and the details sheet.
  final _cache = TemplatePreviewCache();

  static int _indexOf(String? tab) => tab == _tabPosters ? 1 : 0;

  @override
  void didUpdateWidget(DesignsScreen old) {
    super.didUpdateWidget(old);
    if (old.initialTab != widget.initialTab) _tabs.animateTo(_indexOf(widget.initialTab));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Templates', showBack: true),
          Container(
            color: c.surface,
            child: Column(
              children: [
                TabBar(
                  controller: _tabs,
                  labelColor: c.gray900,
                  unselectedLabelColor: c.gray500,
                  indicatorColor: AppColors.blue600,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  tabs: const [
                    Tab(height: 42, text: 'Klux Templates'),
                    Tab(height: 42, text: 'Posters'),
                  ],
                ),
                Divider(height: 1, color: c.gray200),
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: c.page,
              child: TabBarView(
                controller: _tabs,
                children: [
                  _KluxTab(cache: _cache),
                  const PostersGrid(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Klux templates ──────────────────────────────────────────────────────────

class _KluxTab extends StatefulWidget {
  const _KluxTab({required this.cache});

  final TemplatePreviewCache cache;

  @override
  State<_KluxTab> createState() => _KluxTabState();
}

class _KluxTabState extends State<_KluxTab> with AutomaticKeepAliveClientMixin {
  late final TemplatesApi _api = TemplatesApi(context.read<AuthController>().api);

  bool _loading = true;
  String? _error;
  List<KluxTemplate> _items = const [];
  bool _loadingMore = false;
  bool _shareChecked = false;

  @override
  bool get wantKeepAlive => true; // keep the draw (and scroll) across tab switches

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read once: the share link is a one-shot "open this", not state.
    if (_shareChecked) return;
    _shareChecked = true;
    final q = GoRouterState.of(context).uri.queryParameters;
    final slug = q['template'];
    if (slug != null && slug.isNotEmpty) {
      _openShared(slug, q);
    }
  }

  Future<void> _load() async {
    // A refresh over a filled grid keeps it on screen; only a retry after an
    // error goes back to skeletons.
    if (_error != null) {
      setState(() {
        _error = null;
        _loading = true;
      });
    }
    final res = await _api.fetchPublicTemplates();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _items = res.items;
      } else if (_items.isEmpty) {
        _error = res.message;
      } else {
        Toast.error(res.message ?? "We couldn't load templates. Please try again.");
      }
    });
  }

  /// Another random draw, keeping only what isn't on screen yet.
  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    final res = await _api.fetchPublicTemplates();
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (!res.ok) {
        Toast.error(res.message ?? "We couldn't load templates. Please try again.");
        return;
      }
      final fresh = res.items.where((t) => !_items.any(t.isSameAs)).toList();
      if (fresh.isEmpty) {
        Toast.info('No new templates in that batch. Try again for more.');
        return;
      }
      _items = [..._items, ...fresh];
    });
  }

  /// A web share link resolves exactly by slug, never by hunting the pool.
  Future<void> _openShared(String slug, Map<String, String> q) async {
    final res = await _api.fetchTemplateBySlug(
      slug,
      title: q['name'],
      formatKey: q['format'],
      designTypeKey: q['kind'],
      pricing: q['tier'],
    );
    if (!mounted) return;
    if (res.status == 'ok' && res.item != null) {
      _open(res.item!);
    } else {
      Toast.error(res.message ?? "We couldn't open that template.");
    }
  }

  void _open(KluxTemplate item) {
    showTemplateDetailsSheet(context, item: item, pool: _items, cache: widget.cache);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1024 ? 4 : (width >= 640 ? 3 : 2);
    const gap = 12.0;
    final cellWidth = (width - 32 - gap * (columns - 1)) / columns;
    final delegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: gap,
      mainAxisSpacing: gap,
      mainAxisExtent: TemplateCard.cellExtent(cellWidth),
    );

    if (_error != null) {
      return _StatePanel(
        icon: LucideIcons.refreshCw,
        title: _error!,
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(LucideIcons.refreshCw, size: 14),
          label: const Text('Try again'),
        ),
      );
    }

    if (!_loading && _items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 40),
            _StatePanel(
              icon: LucideIcons.sparkles,
              title: 'No templates to show yet',
              body: "Fresh templates land here as soon as they're published — check back shortly.",
            ),
          ],
        ),
      );
    }

    final bottom = MediaQuery.paddingOf(context).bottom;
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            sliver: SliverToBoxAdapter(
              child: Text(
                _loading
                    ? 'Loading templates…'
                    : '${_items.length} templates from the Klux library. Tap one for details, then save it to your designs.',
                style: TextStyle(fontSize: 12.5, color: context.colors.gray500),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _loading
                ? SliverGrid.builder(
                    gridDelegate: delegate,
                    itemCount: columns * 2,
                    itemBuilder: (_, _) => const TemplateCardSkeleton(),
                  )
                : SliverGrid.builder(
                    gridDelegate: delegate,
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final item = _items[i];
                      return TemplateCard(
                        key: ValueKey(item.cacheKey),
                        item: item,
                        cache: widget.cache,
                        onOpen: () => _open(item),
                      );
                    },
                  ),
          ),
          if (!_loading)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 24 + bottom),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: OutlinedButton.icon(
                    onPressed: _loadingMore ? null : _loadMore,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.gray700,
                      side: BorderSide(color: context.colors.gray200),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    icon: _loadingMore
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(LucideIcons.plus, size: 15),
                    label: Text(_loadingMore ? 'Loading…' : 'Show more'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shared empty / error panel (the web's StatePanel).
class _StatePanel extends StatelessWidget {
  const _StatePanel({required this.icon, required this.title, this.body, this.action});

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.blue500.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: AppColors.blue600),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray700),
            ),
            if (body != null) ...[
              const SizedBox(height: 4),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.5, color: c.gray500),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
