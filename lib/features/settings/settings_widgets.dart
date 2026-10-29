import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/section_tabs.dart';
import '../shell/widgets/app_top_bar.dart';

/// The settings pages as tabs. The web has no settings index or section nav:
/// `(settings)/page.jsx` is a dead legacy panel (it links to `/settings/*`
/// routes that don't exist), and only Profile, Resell and Billing are linked,
/// from the account menu. Team, Socials, Sessions & Password and Custom Domain
/// are reachable only by URL there — on a phone there's no URL bar, so the
/// whole group gets one tab strip.
final settingsTabs = [
  const SectionTab('Profile', '/profile', LucideIcons.user),
  const SectionTab('Sessions & Password', '/sessions-and-password', LucideIcons.keyRound),
  const SectionTab('Team', '/team', LucideIcons.users),
  const SectionTab('Socials', '/socials', LucideIcons.share2),
  const SectionTab('Billing', '/billing', LucideIcons.creditCard),
  const SectionTab('Resell', '/resell', LucideIcons.shoppingCart),
  const SectionTab('Custom Domain', '/custom-domain', LucideIcons.globe),
];

/// Top bar + the settings tabs + a scrolling page with 16 gutters. The web's
/// `(settings)` group shares one shape too (see its loading.jsx): a heading,
/// then stacked bordered panels.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({super.key, required this.children, this.onRefresh, this.scrollController});

  final List<Widget> children;

  /// Pull-to-refresh, for the pages that list server data.
  final Future<void> Function()? onRefresh;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget body = SingleChildScrollView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
    if (onRefresh != null) body = RefreshIndicator(onRefresh: onRefresh!, child: body);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Settings'),
          SectionTabs(tabs: settingsTabs, location: GoRouterState.of(context).uri.path),
          Expanded(
            child: ColoredBox(color: c.page, child: body),
          ),
        ],
      ),
    );
  }
}

/// The page heading + its line of supporting copy (`text-xl`/`text-2xl` on the
/// web, scaled down to phone size).
class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.gray900),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!, style: TextStyle(fontSize: 12.5, color: c.gray500, height: 1.35)),
          ],
        ],
      ),
    );
  }
}

/// `bg-surface border border-gray-200 rounded-xl p-6` — padding trimmed for a
/// phone.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.gray200),
      ),
      child: child,
    );
  }
}

/// `text-xs font-medium text-gray-400 uppercase tracking-widest`.
class CardLabel extends StatelessWidget {
  const CardLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: context.colors.gray400),
    ),
  );
}

/// A rounded status/role pill. Tinted from one colour, so it reads in both
/// themes (the web's `bg-green-100 text-green-800` pairs don't flip in dark).
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, this.color, {super.key, this.solid = false});

  final String label;
  final Color color;

  /// The web's Owner role badge is solid (`bg-blue-700 text-white`).
  final bool solid;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: solid ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: solid ? color : color.withValues(alpha: 0.3)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: solid ? Colors.white : color),
    ),
  );
}

/// Pill colours the settings tables use.
abstract final class PillColors {
  static const green = Color(0xFF16A34A);
  static const amber = Color(0xFFD97706);
  static const red = Color(0xFFDC2626);
  static const gray = Color(0xFF6B7280);
}

/// A filled or outlined button at the phone's 42–44 height.
class SettingsButton extends StatelessWidget {
  const SettingsButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.outlined = false,
    this.color,
    this.foreground,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool outlined;

  /// Defaults to the accent blue.
  final Color? color;

  /// Label colour on a filled button (white by default). A `gray900` button
  /// passes `surface`, like the web's `bg-gray-900 text-surface`, so it still
  /// reads once dark mode flips the ramp.
  final Color? foreground;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = color ?? AppColors.blue600;
    final enabled = onPressed != null && !loading;
    final fg = outlined ? accent : (foreground ?? Colors.white);
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2, color: outlined ? accent : c.gray400),
          )
        else if (icon != null)
          Icon(icon, size: 15),
        if (loading || icon != null) const SizedBox(width: 7),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    const text = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600);
    if (outlined) {
      return OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          side: BorderSide(color: enabled ? accent.withValues(alpha: 0.45) : c.gray200),
          shape: shape,
          textStyle: text,
        ),
        child: child,
      );
    }
    return FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: fg,
        disabledBackgroundColor: c.gray200,
        disabledForegroundColor: c.gray500,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: shape,
        textStyle: text,
      ),
      child: child,
    );
  }
}

/// The search box the Team / Resell / Custom Domain tables sit under.
class SettingsSearchField extends StatelessWidget {
  const SettingsSearchField({super.key, required this.onChanged, this.placeholder = 'Search...'});

  final ValueChanged<String> onChanged;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color),
    );
    return SizedBox(
      height: 42,
      child: TextField(
        onChanged: onChanged,
        style: TextStyle(fontSize: 13.5, color: c.gray900),
        decoration: InputDecoration(
          isDense: true,
          hintText: placeholder,
          hintStyle: TextStyle(fontSize: 13.5, color: c.gray400),
          prefixIcon: Icon(LucideIcons.search, size: 16, color: c.gray400),
          filled: true,
          fillColor: c.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
          enabledBorder: border(c.gray200),
          focusedBorder: border(AppColors.blue600),
        ),
      ),
    );
  }
}

/// The "entries per page" select (10 / 25 / 50).
class EntriesSelect extends StatelessWidget {
  const EntriesSelect({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<int>(
      initialValue: value,
      onSelected: onChanged,
      tooltip: 'Entries per page',
      itemBuilder: (_) => [
        for (final n in const [10, 25, 50]) PopupMenuItem(value: n, child: Text('$n')),
      ],
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.gray200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$value', style: TextStyle(fontSize: 13.5, color: c.gray800)),
            const SizedBox(width: 6),
            Icon(LucideIcons.chevronDown, size: 15, color: c.gray400),
          ],
        ),
      ),
    );
  }
}

/// Page clamp shared by the paged lists — the web's resell page derives a
/// `safePage` rather than resetting in an effect, so shrinking the list (a
/// search, a smaller page size, a delete on the last page) can't strand the
/// user on a page that no longer exists.
int safePage(int page, int total, int perPage) => min(page, max(1, (total / perPage).ceil()));

/// "Showing 1 to 10 of 23 entries" + prev / up to five page numbers / next.
/// Rendered only when there's more than one page (the resell page's rule —
/// the team page's always-on bar read "Showing 1–0 of 0" when empty).
class SettingsPager extends StatelessWidget {
  const SettingsPager({
    super.key,
    required this.page,
    required this.perPage,
    required this.total,
    required this.onPage,
  });

  final int page;
  final int perPage;
  final int total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pages = (total / perPage).ceil();
    if (pages <= 1) return const SizedBox.shrink();
    final start = (page - 1) * perPage;

    Widget box({required Widget child, VoidCallback? onTap, bool active = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: active ? AppColors.blue600 : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: active ? AppColors.blue600 : c.gray200),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 38, height: 38, child: Center(child: child)),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          Text(
            'Showing ${start + 1} to ${min(start + perPage, total)} of $total entries',
            style: TextStyle(fontSize: 12.5, color: c.gray600),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              box(
                onTap: page > 1 ? () => onPage(page - 1) : null,
                child: Icon(LucideIcons.chevronLeft, size: 16, color: page > 1 ? c.gray700 : c.gray300),
              ),
              for (var i = 1; i <= min(5, pages); i++)
                box(
                  active: i == page,
                  onTap: () => onPage(i),
                  child: Text(
                    '$i',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: i == page ? Colors.white : c.gray700,
                    ),
                  ),
                ),
              box(
                onTap: page < pages ? () => onPage(page + 1) : null,
                child: Icon(LucideIcons.chevronRight, size: 16, color: page < pages ? c.gray700 : c.gray300),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A grey initial avatar (`bg-gray-300 rounded-full` + the first letter).
class InitialAvatar extends StatelessWidget {
  const InitialAvatar(this.text, {super.key, this.size = 40});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.gray200, shape: BoxShape.circle),
      child: Text(
        text.isEmpty ? '?' : text.characters.first.toUpperCase(),
        style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w600, color: c.gray700),
      ),
    );
  }
}

/// The illustrated empty state, as an icon disc + heading + copy (the web's
/// animated SVG networks don't earn their 224px on a phone).
class SettingsEmptyState extends StatelessWidget {
  const SettingsEmptyState({super.key, required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: c.blueTint, shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: AppColors.blue600),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.gray800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.gray500, height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// A centred spinner for a list that's still loading.
class SettingsLoading extends StatelessWidget {
  const SettingsLoading({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(
      child: SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.blue600),
      ),
    ),
  );
}

/// An icon + text row inside a member card (`Mail` + the address…).
class InfoRow extends StatelessWidget {
  const InfoRow(this.icon, this.text, {super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.gray400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: c.gray600),
            ),
          ),
        ],
      ),
    );
  }
}

/// `toLocaleDateString()` in en-US form (M/D/YYYY), or "N/A".
String shortDate(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return 'N/A';
  return '${d.month}/${d.day}/${d.year}';
}
