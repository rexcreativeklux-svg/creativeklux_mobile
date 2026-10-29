import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/auth_controller.dart';
import 'brand.dart';
import 'brand_avatar.dart';

/// Port of `(components)/ModalPage.jsx` — the blocking "Select a Brand" gate a
/// verified user sees until they have an active brand. No dismiss: picking a
/// brand (or creating one) is the only way through.
class BrandSelectGate extends StatefulWidget {
  const BrandSelectGate({super.key});

  @override
  State<BrandSelectGate> createState() => _BrandSelectGateState();
}

class _BrandSelectGateState extends State<BrandSelectGate> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = context.watch<AuthController>();
    final brands = auth.brands.where((b) => (b.name ?? '').toLowerCase().contains(_query.toLowerCase())).toList();

    return Material(
      color: Colors.black.withValues(alpha: 0.8),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 768),
              child: Container(
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(
                            'Select a Brand',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.gray900),
                          ),
                          TextButton.icon(
                            onPressed: () => context.push('/brand/create'),
                            icon: Icon(LucideIcons.folderInput, size: 18, color: AppColors.blue600),
                            label: Text(
                              'Create New Brand',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.blue600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        style: TextStyle(fontSize: 14, color: c.gray900),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Search brand',
                          hintStyle: TextStyle(color: c.gray400),
                          prefixIcon: Icon(LucideIcons.search, size: 16, color: c.gray500),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: c.gray200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: AppColors.blue600),
                          ),
                        ),
                      ),
                    ),
                    Flexible(child: _body(context, auth, brands)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AuthController auth, List<Brand> brands) {
    final c = context.colors;

    if (auth.brandsLoading) {
      return Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator(color: AppColors.blue600)),
      );
    }

    if (brands.isEmpty && _query.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          'No brands match “$_query”',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: c.gray600),
        ),
      );
    }

    if (auth.brands.isEmpty && auth.brandsFailed) {
      // The list didn't load — say so, and offer Retry. Offering "Create your
      // first brand" here led people with brands to make a duplicate.
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: c.redTint, borderRadius: BorderRadius.circular(16)),
              child: const Icon(LucideIcons.wifiOff, size: 28, color: AppColors.red500),
            ),
            const SizedBox(height: 16),
            Text(
              "Couldn't load your brands",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.gray800),
            ),
            const SizedBox(height: 6),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.gray500, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: auth.fetchBrands,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: auth.logout,
              child: Text('Sign out', style: TextStyle(fontSize: 13, color: c.gray500)),
            ),
          ],
        ),
      );
    }

    if (brands.isEmpty) {
      // No brands at all — the user must create one before continuing.
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: c.blueTint, borderRadius: BorderRadius.circular(16)),
              child: Icon(LucideIcons.building2, size: 28, color: AppColors.blue600),
            ),
            const SizedBox(height: 16),
            Text(
              'Create your first brand',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.gray800),
            ),
            const SizedBox(height: 6),
            Text(
              'You need at least one brand to start creating. It only takes a minute — set your name, colors, and logo.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.gray500, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/brand/create'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Create Brand', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: auth.logout,
              child: Text('Sign out', style: TextStyle(fontSize: 13, color: c.gray500)),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // One card per row on phones, two from 480px — same as the web's xs breakpoint.
        final columns = constraints.maxWidth >= 480 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 104,
          ),
          itemCount: brands.length,
          itemBuilder: (context, i) => _BrandCard(brand: brands[i]),
        );
      },
    );
  }
}

class _BrandCard extends StatelessWidget {
  const _BrandCard({required this.brand});

  final Brand brand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = context.watch<AuthController>();
    final switching = auth.switchingBrandId == brand.id;

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.gray200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: auth.switchingBrandId != null ? null : () => auth.setActiveBrand(brand),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BrandAvatar(brand: brand, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      brand.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.gray900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      brand.shortDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.gray600),
                    ),
                  ],
                ),
              ),
              if (switching)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue600),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
