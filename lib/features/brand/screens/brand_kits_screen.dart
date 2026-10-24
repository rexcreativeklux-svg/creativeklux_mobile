import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import '../../shell/widgets/app_top_bar.dart';
import '../brand.dart';
import '../widgets/brand_visuals.dart';

/// Port of `brand/reuse/page.js` — the Brand Kits list.
///
/// Mobile adaptations: the web's inline detail panel (scrolled to on select)
/// is a bottom sheet here, and delete shows progress instead of closing
/// before the request finishes.
class BrandKitsScreen extends StatefulWidget {
  const BrandKitsScreen({super.key});

  @override
  State<BrandKitsScreen> createState() => _BrandKitsScreenState();
}

class _BrandKitsScreenState extends State<BrandKitsScreen> {
  String _query = '';
  bool _grid = true;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = context.watch<AuthController>();
    final q = _query.toLowerCase();
    final brands = auth.brands
        .where((b) => (b.name ?? '').toLowerCase().contains(q) || (b.industry ?? '').toLowerCase().contains(q))
        .toList();

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Brand Kits', showBack: true),
          Expanded(
            child: Container(
              color: c.page,
              child: RefreshIndicator(
                onRefresh: auth.fetchBrands,
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      sliver: SliverToBoxAdapter(child: _header(context)),
                    ),
                    if (auth.brandsLoading)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator(color: AppColors.blue600)),
                      )
                    else if (brands.isEmpty)
                      SliverFillRemaining(hasScrollBody: false, child: _empty(context))
                    else if (_grid)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final cols = (constraints.crossAxisExtent / 200).floor().clamp(1, 4);
                            return SliverGrid.builder(
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                mainAxisExtent: 236,
                              ),
                              itemCount: brands.length,
                              itemBuilder: (context, i) => _BrandCard(
                                brand: brands[i],
                                active: auth.activeBrand?.id == brands[i].id,
                                onTap: () => _openDetail(brands[i]),
                              ),
                            );
                          },
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        sliver: SliverList.separated(
                          itemCount: brands.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) => _BrandRow(
                            brand: brands[i],
                            active: auth.activeBrand?.id == brands[i].id,
                            onTap: () => _openDetail(brands[i]),
                          ),
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

  Widget _header(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Save your brand assets — colors, fonts, logos — and apply them instantly to any design',
                style: TextStyle(fontSize: 13, height: 1.4, color: c.gray500),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => context.push('/brand/create'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('New Brand', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(fontSize: 14, color: c.gray900),
                decoration: brandInputDecoration(context, hint: 'Search brands…').copyWith(
                  fillColor: c.surface,
                  prefixIcon: Icon(LucideIcons.search, size: 16, color: c.gray400),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  for (final (grid, icon, label) in [
                    (true, LucideIcons.layoutGrid, 'Grid view'),
                    (false, LucideIcons.list, 'List view'),
                  ])
                    Tooltip(
                      message: label,
                      child: GestureDetector(
                        onTap: () => setState(() => _grid = grid),
                        child: Container(
                          width: 36,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _grid == grid ? c.surface : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, size: 16, color: _grid == grid ? c.gray900 : c.gray400),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final c = context.colors;
    final searching = _query.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(16)),
            child: Icon(LucideIcons.tag, size: 24, color: c.gray400),
          ),
          const SizedBox(height: 14),
          Text(
            searching ? 'No brands match your search' : 'No brands yet',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray800),
          ),
          const SizedBox(height: 4),
          Text(
            searching ? 'Try a different keyword' : 'Create your first brand to get started',
            style: TextStyle(fontSize: 13, color: c.gray500),
          ),
          if (!searching) ...[
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => context.push('/brand/create'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
              child: const Text('Create Brand'),
            ),
          ],
        ],
      ),
    );
  }

  void _openDetail(Brand brand) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (_) => _BrandDetailSheet(brand: brand, hostContext: context),
    );
  }
}

/// ⋮ menu actions, shared by cards, rows and the detail sheet.
Future<void> _runAction(BuildContext context, String action, Brand brand) async {
  final auth = context.read<AuthController>();
  final router = GoRouter.of(context);
  switch (action) {
    case 'manage':
      if (await auth.setActiveBrand(brand)) router.push('/brand/manage');
    case 'edit':
      router.push('/brand/edit/${brand.id}');
    case 'visit':
      final url = brand.url!;
      await launchUrl(Uri.parse(url.startsWith('http') ? url : 'https://$url'), mode: LaunchMode.externalApplication);
    case 'delete':
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _DeleteBrandDialog(brand: brand),
      );
  }
}

class _BrandMenu extends StatelessWidget {
  const _BrandMenu({required this.brand, this.light = true});

  final Brand brand;

  /// Light icon (on a dark gradient) vs. dark icon.
  final bool light;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    PopupMenuItem<String> item(String value, IconData icon, String label, {Color? color}) => PopupMenuItem(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? c.gray600),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13.5, color: color ?? c.gray800)),
        ],
      ),
    );

    return PopupMenuButton<String>(
      tooltip: 'Brand actions',
      icon: Icon(LucideIcons.ellipsisVertical, size: 18, color: light ? Colors.white : c.gray500),
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (v) => _runAction(context, v, brand),
      itemBuilder: (_) => [
        item('manage', LucideIcons.settings, 'Manage'),
        item('edit', LucideIcons.pencil, 'Edit Brand'),
        if (brand.url != null) item('visit', LucideIcons.externalLink, 'Visit Site'),
        const PopupMenuDivider(),
        item('delete', LucideIcons.trash2, 'Delete', color: AppColors.red500),
      ],
    );
  }
}

/// Text on a brand gradient flips dark when the brand colour is very light.
bool _isLight(Color color) => color.computeLuminance() > 0.68;

class _BrandCard extends StatelessWidget {
  const _BrandCard({required this.brand, required this.active, required this.onTap});

  final Brand brand;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: active ? AppColors.blue500 : c.gray100, width: active ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 104,
              child: BrandGradient(
                primary: brand.color,
                secondary: brand.secondary,
                child: Stack(
                  children: [
                    Positioned(top: 10, left: 10, child: BrandStatusPill(active: active)),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _BrandMenu(brand: brand, light: !_isLight(brand.color)),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 10,
                      child: BrandLogoTile(
                        name: brand.displayName,
                        color: brand.color,
                        logoUrl: brand.logoUrl,
                        size: 44,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      brand.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.gray900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      brand.tagline ?? 'No tagline',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontStyle: brand.tagline != null ? FontStyle.italic : FontStyle.normal,
                        color: brand.tagline != null ? c.gray500 : c.gray300,
                      ),
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (brand.industry != null) InfoChip(brand.industry!, icon: LucideIcons.building2),
                        if (brand.fonts != null) InfoChip(brand.fonts!, icon: LucideIcons.type),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _ColorDots(brand: brand),
                  ],
                ),
              ),
            ),
            if (active) Container(height: 2, color: AppColors.blue500),
          ],
        ),
      ),
    );
  }
}

class _ColorDots extends StatelessWidget {
  const _ColorDots({required this.brand});

  final Brand brand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        SizedBox(
          width: 28,
          height: 16,
          child: Stack(
            children: [
              for (final (i, col) in [(0, brand.color), (1, brand.secondary)])
                Positioned(
                  left: i * 11.0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.surface, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          brand.primaryHex,
          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: c.gray400),
        ),
      ],
    );
  }
}

class _BrandRow extends StatelessWidget {
  const _BrandRow({required this.brand, required this.active, required this.onTap});

  final Brand brand;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: active ? AppColors.blue500 : c.gray100),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: BrandGradient(
                  primary: brand.color,
                  secondary: brand.secondary,
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: BrandLogoTile(name: brand.displayName, color: brand.color, logoUrl: brand.logoUrl, size: 30),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      brand.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [brand.industry, brand.tagline].whereType<String>().join(' · ').ifEmpty('No tagline'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.gray500),
                    ),
                  ],
                ),
              ),
              BrandStatusPill(active: active, onDark: false),
              _BrandMenu(brand: brand, light: false),
            ],
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// The web's "Brand details" panel, as a sheet.
class _BrandDetailSheet extends StatelessWidget {
  const _BrandDetailSheet({required this.brand, required this.hostContext});

  final Brand brand;

  /// The screen's context — actions run after this sheet has closed.
  final BuildContext hostContext;

  String _date(DateTime? d) {
    if (d == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = context.watch<AuthController>();
    final active = auth.activeBrand?.id == brand.id;
    final light = _isLight(brand.color);
    final onBanner = light ? c.gray900 : Colors.white;
    final meta = [
      ('Industry', brand.industry),
      ('Font', brand.fonts),
      ('Created', _date(brand.createdAt)),
      ('Updated', _date(brand.updatedAt)),
    ].where((e) => (e.$2 ?? '').isNotEmpty).toList();

    void act(String action) {
      Navigator.pop(context);
      _runAction(hostContext, action, brand);
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.zero,
          children: [
            BrandGradient(
              primary: brand.color,
              secondary: brand.secondary,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'BRAND DETAILS',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w700,
                            color: onBanner.withValues(alpha: 0.7),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(LucideIcons.x, size: 20, color: onBanner),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        BrandLogoTile(
                          name: brand.displayName,
                          color: brand.color,
                          logoUrl: brand.logoUrl,
                          size: 64,
                          circle: true,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                brand.displayName,
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: onBanner),
                              ),
                              if (brand.tagline != null)
                                Text(
                                  brand.tagline!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    color: onBanner.withValues(alpha: 0.7),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const SectionLabel('About'),
                      const Spacer(),
                      BrandStatusPill(active: active, onDark: false),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    brand.description ?? 'No description yet.',
                    style: TextStyle(fontSize: 14, height: 1.5, color: c.gray600),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 2.8,
                      children: [
                        for (final (label, value) in meta)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: c.gray50, borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SectionLabel(label),
                                const SizedBox(height: 2),
                                Text(
                                  value!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray800),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  const SectionLabel('🎨  Brand colors'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final (label, col, hex) in [
                        ('Primary', brand.color, brand.primaryHex),
                        ('Secondary', brand.secondary, brand.secondaryHex),
                      ])
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: col,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: c.gray200),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label, style: TextStyle(fontSize: 11, color: c.gray400)),
                                  Text(
                                    hex,
                                    style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: c.gray800),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (brand.url != null) ...[
                    const SizedBox(height: 18),
                    const SectionLabel('🌐  Website'),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => act('visit'),
                      child: Text(brand.url!, style: TextStyle(fontSize: 14, color: AppColors.blue600)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => act('edit'),
                          style: FilledButton.styleFrom(
                            backgroundColor: c.gray900,
                            foregroundColor: c.surface,
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(LucideIcons.pencil, size: 16),
                          label: const Text('Edit Brand'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => act('manage'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.gray800,
                            side: BorderSide(color: c.gray200),
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(LucideIcons.settings, size: 16),
                          label: const Text('Manage'),
                        ),
                      ),
                    ],
                  ),
                  if (!active) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () async {
                        if (await auth.setActiveBrand(brand) && context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(LucideIcons.check, size: 16),
                      label: const Text('Use this brand'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteBrandDialog extends StatefulWidget {
  const _DeleteBrandDialog({required this.brand});

  final Brand brand;

  @override
  State<_DeleteBrandDialog> createState() => _DeleteBrandDialogState();
}

class _DeleteBrandDialogState extends State<_DeleteBrandDialog> {
  bool _busy = false;

  Future<void> _delete() async {
    setState(() => _busy = true);
    final auth = context.read<AuthController>();
    final res = await auth.brandApi.delete(widget.brand.id);
    if (!mounted) return;
    if (res.ok) {
      Toast.success(res.body['message']?.toString() ?? 'Brand deleted.');
      if (auth.activeBrand?.id == widget.brand.id) auth.clearActiveBrand();
      Navigator.pop(context);
      await auth.fetchBrands();
    } else {
      Toast.error(res.message.isNotEmpty ? res.message : "Couldn't delete the brand. Please try again.");
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 384),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: c.redTint, borderRadius: BorderRadius.circular(14)),
                child: const Icon(LucideIcons.trash2, size: 22, color: AppColors.red500),
              ),
              const SizedBox(height: 14),
              Text(
                'Delete brand?',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.gray900),
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  style: TextStyle(fontSize: 13.5, height: 1.45, color: c.gray500),
                  children: [
                    TextSpan(
                      text: widget.brand.displayName,
                      style: TextStyle(fontWeight: FontWeight.w700, color: c.gray800),
                    ),
                    const TextSpan(text: ' will be permanently removed. This cannot be undone.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        side: BorderSide(color: c.gray200),
                        foregroundColor: c.gray700,
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _delete,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.red500,
                        disabledBackgroundColor: AppColors.red500.withValues(alpha: 0.6),
                        minimumSize: const Size(0, 44),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
