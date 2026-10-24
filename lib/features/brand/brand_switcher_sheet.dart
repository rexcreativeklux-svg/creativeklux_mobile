import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/auth_controller.dart';
import 'brand_avatar.dart';

/// The header's brand dropdown (Header.jsx), as a bottom sheet — easier to
/// reach one-handed on a phone than a dropdown anchored to the top corner.
///
/// Search, "Create Brand", the list (tap to switch) and a gear per row that
/// switches and then opens the brand's settings.
Future<void> showBrandSwitcher(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _BrandSwitcherSheet(),
  );
}

class _BrandSwitcherSheet extends StatefulWidget {
  const _BrandSwitcherSheet();

  @override
  State<_BrandSwitcherSheet> createState() => _BrandSwitcherSheetState();
}

class _BrandSwitcherSheetState extends State<_BrandSwitcherSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = context.watch<AuthController>();
    final switching = auth.switchingBrandId != null;
    final brands = auth.brands.where((b) => (b.name ?? '').toLowerCase().contains(_query.toLowerCase())).toList();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Switch brand',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(fontSize: 14, color: c.gray900),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search brands...',
                  hintStyle: TextStyle(color: c.gray400),
                  prefixIcon: Icon(LucideIcons.search, size: 16, color: c.gray400),
                  filled: true,
                  fillColor: c.gray50,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(LucideIcons.plus, size: 18, color: c.gray900),
              title: Text(
                'Create Brand',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
              ),
              onTap: () {
                Navigator.pop(context);
                context.push('/brand/create');
              },
            ),
            Flexible(
              child: brands.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No brands found',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: c.gray400),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      itemCount: brands.length,
                      itemBuilder: (context, i) {
                        final b = brands[i];
                        final selected = auth.activeBrand?.id == b.id;
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: selected ? c.blueTint : null,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            enabled: !switching,
                            leading: BrandAvatar(brand: b, size: 28),
                            title: Text(
                              b.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                color: selected ? AppColors.blue600 : c.gray700,
                              ),
                            ),
                            onTap: () async {
                              final ok = await auth.setActiveBrand(b);
                              if (ok && context.mounted) Navigator.pop(context);
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (auth.switchingBrandId == b.id)
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue600),
                                  )
                                else if (selected)
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(color: AppColors.blue600, shape: BoxShape.circle),
                                  ),
                                IconButton(
                                  tooltip: 'Manage ${b.displayName}',
                                  icon: Icon(LucideIcons.settings, size: 17, color: c.gray400),
                                  onPressed: switching
                                      ? null
                                      : () async {
                                          final ok = await auth.setActiveBrand(b);
                                          if (ok && context.mounted) {
                                            Navigator.pop(context);
                                            context.push('/brand/manage');
                                          }
                                        },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
