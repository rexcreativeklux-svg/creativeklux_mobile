import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/skins.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/ui/media.dart';

/// Port of `appearance/AppearancePanel.jsx`: Theme on top, then Skins · Art ·
/// Images.
///
/// ⚠️ NO DIMMING BEHIND IT — the web is explicit about this: a skin changes the
/// whole app, so the app IS the preview. The sheet takes the lower part of the
/// screen and leaves the app visible (and live) above it.
Future<void> showAppearanceSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  barrierColor: Colors.transparent,
  elevation: 12,
  builder: (_) => const _AppearanceSheet(),
);

enum _Tab { skins, art, images }

class _AppearanceSheet extends StatefulWidget {
  const _AppearanceSheet();

  @override
  State<_AppearanceSheet> createState() => _AppearanceSheetState();
}

class _AppearanceSheetState extends State<_AppearanceSheet> {
  // Not persisted, like the web: Skins is the right tab to reopen on.
  _Tab _tab = _Tab.skins;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Appearance',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(LucideIcons.x, size: 18, color: c.gray400),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Caption(icon: LucideIcons.sunMedium, text: 'Theme'),
                const SizedBox(height: 8),
                const _ThemePills(),
                const SizedBox(height: 14),
                Divider(height: 1, color: c.gray200),
                const SizedBox(height: 12),
                _Pills<_Tab>(
                  value: _tab,
                  options: const [
                    (_Tab.skins, LucideIcons.palette, 'Skins'),
                    (_Tab.art, LucideIcons.brush, 'Art'),
                    (_Tab.images, LucideIcons.image, 'Images'),
                  ],
                  onChanged: (t) => setState(() => _tab = t),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          Expanded(
            child: switch (_tab) {
              _Tab.skins => _SkinGrid(scroll: scroll),
              // Keyed: Art and Images are the same picker in two modes, and
              // must not show each other's results while the next fetch lands.
              _Tab.art => _WallpaperPicker(key: const ValueKey('art'), art: true, scroll: scroll),
              _Tab.images => _WallpaperPicker(key: const ValueKey('images'), art: false, scroll: scroll),
            },
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Icon(icon, size: 14, color: c.gray400),
        const SizedBox(width: 6),
        Text(
          text.toUpperCase(),
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: c.gray400),
        ),
      ],
    );
  }
}

/// The panel's one idea of "a choice of several": a full-width pill group.
class _Pills<T> extends StatelessWidget {
  const _Pills({required this.value, required this.options, required this.onChanged});

  final T value;
  final List<(T, IconData, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(99)),
      child: Row(
        children: [
          for (final (v, icon, label) in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 32,
                  decoration: BoxDecoration(
                    color: v == value ? AppColors.blue600 : Colors.transparent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 14, color: v == value ? Colors.white : c.gray500),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: v == value ? Colors.white : c.gray600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemePills extends StatelessWidget {
  const _ThemePills();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return _Pills<ThemeMode>(
      value: theme.mode,
      options: const [
        (ThemeMode.light, LucideIcons.sun, 'Light'),
        (ThemeMode.system, LucideIcons.monitor, 'System'),
        (ThemeMode.dark, LucideIcons.moon, 'Dark'),
      ],
      onChanged: theme.setMode,
    );
  }
}

// ── Skins ────────────────────────────────────────────────────────────────────

class _SkinGrid extends StatelessWidget {
  const _SkinGrid({required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final skins = context.watch<SkinController>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GridView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.08,
      ),
      itemCount: skinSpecs.length,
      itemBuilder: (context, i) {
        final spec = skinSpecs[i];
        return _SkinTile(
          spec: spec,
          palette: spec.palette(dark),
          active: spec.id == skins.skinId,
          onTap: () => skins.setSkin(spec.id),
        );
      },
    );
  }
}

/// A skin, rendered small: its art, plus a little card, a line of "text" and
/// an accent dot — what's being chosen is a UI, not a wallpaper (the web's
/// `.ck-skin-swatch`). "None" previews the app as it is.
class _SkinTile extends StatelessWidget {
  const _SkinTile({required this.spec, required this.palette, required this.active, required this.onTap});

  final SkinSpec spec;
  final SkinPalette? palette;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final p = palette;
    final base = dark ? AppColors.dark : AppColors.light;
    final surface = p?.surface ?? base.surface;
    final ink = p?.ink ?? base.gray900;
    final accent = p?.accent ?? const Color(0xFF155DFC);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: active ? AppColors.blue600 : c.gray200, width: active ? 2 : 1),
                boxShadow: active
                    ? [BoxShadow(color: AppColors.blue600.withValues(alpha: 0.3), blurRadius: 0, spreadRadius: 2)]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (p != null)
                    SkinBackdrop(palette: p, wallpaper: null, fallback: base.page)
                  else
                    ColoredBox(color: base.page),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    top: 46,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: ink.withValues(alpha: 0.14)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(
                            widthFactor: 0.66,
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: ink.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (active)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(color: AppColors.blue600, shape: BoxShape.circle),
                        child: const Icon(LucideIcons.check, size: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            spec.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? c.gray900 : c.gray600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Art / Images (WallpaperPicker.jsx + wallpapers.js) ──────────────────────

/// What the Images grid shows before anyone searches.
const _defaultQuery = 'abstract gradient texture';

/// Curated Pexels searches that come back looking like ARTWORK. Every query
/// was picked on what the live API returns, not on how it sounds (see
/// wallpapers.js) — keep them in step with the web.
const _artCollections = [
  ('cosmic', 'Cosmic', 'nebula galaxy space'),
  ('aurora', 'Aurora', 'aurora borealis'),
  ('gradient', 'Gradient', 'gradient color background'),
  ('fluid', 'Fluid', 'fluid art marble'),
  ('watercolour', 'Watercolour', 'watercolor background'),
  ('geometric', 'Geometric', 'geometric abstract art'),
  ('clay', 'Clay', 'clay 3d render abstract'),
  ('blossom', 'Blossom', 'cherry blossom night'),
  ('surreal', 'Surreal', 'digital art landscape'),
  ('street', 'Street art', 'mural street art'),
  ('spooky', 'Spooky', 'halloween night illustration'),
];

/// Six real Pexels photos, so the grid is NEVER empty — before the first
/// search lands, or when Pexels can't be reached.
const _fallbackWallpapers = [
  Wallpaper(
    id: '7135053',
    url: 'https://images.pexels.com/photos/7135053/pexels-photo-7135053.jpeg?auto=compress&cs=tinysrgb&dpr=2&h=650&w=940',
    thumb: 'https://images.pexels.com/photos/7135053/pexels-photo-7135053.jpeg?auto=compress&cs=tinysrgb&h=350',
    photographer: 'Codioful',
  ),
  Wallpaper(
    id: '6985120',
    url: 'https://images.pexels.com/photos/6985120/pexels-photo-6985120.jpeg?auto=compress&cs=tinysrgb&dpr=2&h=650&w=940',
    thumb: 'https://images.pexels.com/photos/6985120/pexels-photo-6985120.jpeg?auto=compress&cs=tinysrgb&h=350',
    photographer: 'Codioful',
  ),
  Wallpaper(
    id: '7130471',
    url: 'https://images.pexels.com/photos/7130471/pexels-photo-7130471.jpeg?auto=compress&cs=tinysrgb&dpr=2&h=650&w=940',
    thumb: 'https://images.pexels.com/photos/7130471/pexels-photo-7130471.jpeg?auto=compress&cs=tinysrgb&h=350',
    photographer: 'Codioful',
  ),
  Wallpaper(
    id: '29355930',
    url: 'https://images.pexels.com/photos/29355930/pexels-photo-29355930.jpeg?auto=compress&cs=tinysrgb&dpr=2&h=650&w=940',
    thumb: 'https://images.pexels.com/photos/29355930/pexels-photo-29355930.jpeg?auto=compress&cs=tinysrgb&h=350',
    photographer: 'Landiva Weber',
  ),
  Wallpaper(
    id: '12564253',
    url: 'https://images.pexels.com/photos/12564253/pexels-photo-12564253.jpeg?auto=compress&cs=tinysrgb&dpr=2&h=650&w=940',
    thumb: 'https://images.pexels.com/photos/12564253/pexels-photo-12564253.jpeg?auto=compress&cs=tinysrgb&h=350',
    photographer: 'Steve A Johnson',
  ),
  Wallpaper(
    id: '28494633',
    url: 'https://images.pexels.com/photos/28494633/pexels-photo-28494633.jpeg?auto=compress&cs=tinysrgb&dpr=2&h=650&w=940',
    thumb: 'https://images.pexels.com/photos/28494633/pexels-photo-28494633.jpeg?auto=compress&cs=tinysrgb&h=350',
    photographer: 'Steve A Johnson',
  ),
];

/// Search Pexels through the web app's own route (it holds the key server
/// side). PORTRAIT here, where the web asks for landscape: a phone is a tall
/// screen, and a landscape photo behind it is cropped to its middle third.
Future<List<Wallpaper>> _searchWallpapers(String query, CancelToken cancel) async {
  final res = await Dio().get<Map<String, dynamic>>(
    '${AppConfig.webAppUrl}/api/pexels',
    queryParameters: {'query': query, 'type': 'photos', 'per_page': 18, 'orientation': 'portrait'},
    cancelToken: cancel,
  );
  final photos = res.data?['photos'];
  return [
    if (photos is List)
      for (final p in photos.whereType<Map>())
        if (p['src'] is Map)
          Wallpaper(
            id: '${p['id']}',
            // `large2x`, not `original` — originals are 5–8 MB for a background.
            url: '${(p['src'] as Map)['large2x'] ?? (p['src'] as Map)['large'] ?? ''}',
            thumb: '${(p['src'] as Map)['medium'] ?? (p['src'] as Map)['small'] ?? ''}',
            photographer: '${p['photographer'] ?? ''}',
          ),
  ].where((w) => w.url.startsWith('http')).toList();
}

class _WallpaperPicker extends StatefulWidget {
  const _WallpaperPicker({super.key, required this.art, required this.scroll});

  /// Art = curated collections; Images = free search.
  final bool art;
  final ScrollController scroll;

  @override
  State<_WallpaperPicker> createState() => _WallpaperPickerState();
}

class _WallpaperPickerState extends State<_WallpaperPicker> {
  late final _query = TextEditingController(text: _defaultQuery);
  String _collection = _artCollections.first.$1;
  List<Wallpaper> _photos = _fallbackWallpapers;
  bool _busy = true;
  String _note = '';
  Timer? _debounce;
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    _fetch(widget.art ? _artCollections.first.$3 : _defaultQuery);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancel?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _fetch(String query) async {
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    setState(() => _busy = true);
    try {
      final results = await _searchWallpapers(query, cancel);
      if (!mounted || cancel.isCancelled) return;
      setState(() {
        // Only swap when there's something to swap IN — the grid never blanks.
        if (results.isNotEmpty) {
          _photos = results;
          _note = '';
        } else {
          _note = 'Nothing for “$query” — showing the last set.';
        }
        _busy = false;
      });
    } catch (_) {
      if (!mounted || cancel.isCancelled) return;
      setState(() {
        _note = "Couldn't reach Pexels — showing a saved set.";
        _busy = false;
      });
    }
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _fetch(v.trim().isEmpty ? _defaultQuery : v.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final skins = context.watch<SkinController>();
    final current = skins.wallpaper;

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (widget.art)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (id, label, query) in _artCollections)
                GestureDetector(
                  onTap: () {
                    setState(() => _collection = id);
                    _fetch(query);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: id == _collection ? AppColors.blue600 : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: id == _collection ? AppColors.blue600 : c.gray200),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: id == _collection ? Colors.white : c.gray600,
                      ),
                    ),
                  ),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          )
        else
          TextField(
            controller: _query,
            onChanged: _onQuery,
            textInputAction: TextInputAction.search,
            style: TextStyle(fontSize: 13.5, color: c.gray900),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search',
              prefixIcon: Icon(LucideIcons.search, size: 16, color: c.gray400),
              suffixIcon: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
              filled: true,
              fillColor: c.gray50,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.gray200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.gray200),
              ),
            ),
          ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // None first: clearing must be as easy as choosing.
            GestureDetector(
              onTap: () => skins.setWallpaper(null),
              child: Container(
                decoration: BoxDecoration(
                  color: current == null ? c.blueTint : c.gray50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: current == null ? AppColors.blue600 : c.gray200,
                    width: current == null ? 2 : 1,
                  ),
                ),
                child: Icon(LucideIcons.ban, size: 18, color: current == null ? AppColors.blue600 : c.gray400),
              ),
            ),
            for (final w in _photos)
              Tooltip(
                // Pexels asks for the photographer to be credited.
                message: 'Photo by ${w.photographer} on Pexels',
                child: GestureDetector(
                  onTap: () => skins.setWallpaper(w),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: current?.url == w.url ? AppColors.blue600 : c.gray200,
                        width: current?.url == w.url ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: MediaImage(w.thumb, fit: BoxFit.cover, cacheWidth: 300),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _note.isNotEmpty
              ? _note
              : current != null
              ? 'Photo by ${current.photographer} on Pexels.'
              : 'Photos from Pexels. Long-press a tile for its photographer.',
          style: TextStyle(fontSize: 11, height: 1.4, color: c.gray400),
        ),
      ],
    );
  }
}
