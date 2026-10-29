import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/section_tabs.dart';
import '../shell/widgets/app_top_bar.dart';
import 'ads_api.dart';

// Shared pieces of the Ads Content section. Kept private to this folder (the
// Social Content port has its own copy) so the two sections can drift apart
// the way the web's pages do.

/// The section's pages — `NAV_ITEMS` in `ads-content/layout.jsx`.
const adsSectionTabs = [
  SectionTab('Publishing', '/ads-content/publishing', LucideIcons.megaphone),
  SectionTab('Calendar', '/ads-content/calendar', LucideIcons.calendar),
  SectionTab('Analytics', '/ads-content/analytics', LucideIcons.activity),
];

/// Port of `ads-content/layout.jsx`: `SectionLayout title="Ads Content"`. The
/// web's secondary sidebar becomes [SectionTabs] under the top bar.
class AdsSectionScaffold extends StatelessWidget {
  const AdsSectionScaffold({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Ads Content'),
          SectionTabs(tabs: adsSectionTabs, location: location),
          Expanded(
            child: ColoredBox(color: context.colors.page, child: child),
          ),
        ],
      ),
    );
  }
}

// ── Platforms ───────────────────────────────────────────────────────────────

/// `PLATFORM_META` from publishing/page.jsx (full names + the pill colour),
/// with calendar/page.jsx's short `label` as [short]. The web's emoji icons
/// are kept: Lucide has no brand logos.
class AdPlatformMeta {
  const AdPlatformMeta(this.label, this.short, this.emoji, this.color, {this.ads = false});

  final String label;
  final String short;
  final String emoji;
  final Color color;
  final bool ads;
}

const adPlatformMeta = {
  'facebook': AdPlatformMeta('Facebook', 'FB', '🔵', Color(0xFF1D4ED8)),
  'instagram': AdPlatformMeta('Instagram', 'IG', '📸', Color(0xFFBE185D)),
  'twitter': AdPlatformMeta('X / Twitter', 'X', '🐦', Color(0xFF334155)),
  'linkedin': AdPlatformMeta('LinkedIn', 'LI', '💼', Color(0xFF1E40AF)),
  'tiktok': AdPlatformMeta('TikTok', 'TikTok', '🎵', Color(0xFF374151)),
  'youtube': AdPlatformMeta('YouTube', 'YT', '▶️', Color(0xFFB91C1C)),
  'pinterest': AdPlatformMeta('Pinterest', 'PIN', '📌', Color(0xFFBE123C)),
  'meta_ads': AdPlatformMeta('Meta Ads', 'Meta', '📢', Color(0xFF4338CA), ads: true),
  'google_ads': AdPlatformMeta('Google Ads', 'G.Ads', '🔍', Color(0xFF15803D), ads: true),
  'tiktok_ads': AdPlatformMeta('TikTok Ads', 'TT.Ads', '🎯', Color(0xFF0E7490), ads: true),
  'linkedin_ads': AdPlatformMeta('LinkedIn Ads', 'LI.Ads', '📊', Color(0xFF1E40AF), ads: true),
  'snapchat_ads': AdPlatformMeta('Snapchat Ads', 'Snap.Ads', '💥', Color(0xFFA16207), ads: true),
  'pinterest_ads': AdPlatformMeta('Pinterest Ads', 'PIN.Ads', '🎯', Color(0xFFBE123C), ads: true),
};

AdPlatformMeta platformMetaOf(String platform) =>
    adPlatformMeta[platform] ?? AdPlatformMeta(platform, platform, '🌐', const Color(0xFF6B7280));

/// `{meta.icon} {meta.label}` in a tinted pill.
class PlatformPill extends StatelessWidget {
  const PlatformPill(this.platform, {super.key});

  final String platform;

  @override
  Widget build(BuildContext context) {
    final m = platformMetaOf(platform);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Color.lerp(m.color, Colors.white, 0.45)! : m.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: m.color.withValues(alpha: dark ? 0.22 : 0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: m.color.withValues(alpha: 0.25)),
      ),
      child: Text(
        '${m.emoji} ${m.label}',
        maxLines: 1,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ── Status ──────────────────────────────────────────────────────────────────

const _emerald = Color(0xFF059669);
const _amber = Color(0xFFD97706);

/// The colour the web gives each of the network's status words (green for
/// ACTIVE, amber for PAUSED); any other status is neutral.
Color? statusColor(String status) => switch (status) {
  'ACTIVE' => _emerald,
  'PAUSED' => _amber,
  _ => null,
};

/// The network's status word, as the backend returned it ("ACTIVE" → "Active").
String statusLabel(String s) => s.isEmpty ? 'Unknown' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

/// Port of publishing/page.jsx `StatusBadge`.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.icon = true});

  final String status;
  final bool icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = statusColor(status) ?? c.gray600;
    final iconData = switch (status) {
      'ACTIVE' => LucideIcons.circleCheck,
      'PAUSED' => LucideIcons.circlePause,
      _ => LucideIcons.circleDot,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: statusColor(status)?.withValues(alpha: 0.1) ?? c.gray50,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: statusColor(status)?.withValues(alpha: 0.3) ?? c.gray200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon) ...[Icon(iconData, size: 11, color: color), const SizedBox(width: 4)],
          Text(
            statusLabel(status),
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

// ── Formatting ──────────────────────────────────────────────────────────────

const monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const monthsLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _two(int n) => n.toString().padLeft(2, '0');

/// publishing/page.jsx `formatDate`: "Oct 29, 14:05" (24-hour).
String formatCreated(DateTime? d) =>
    d == null ? '—' : '${monthsShort[d.month - 1]} ${d.day}, ${_two(d.hour)}:${_two(d.minute)}';

/// date-fns "MMM d HH:mm".
String formatUpdated(DateTime? d) =>
    d == null ? '—' : '${monthsShort[d.month - 1]} ${d.day} ${_two(d.hour)}:${_two(d.minute)}';

/// date-fns "h:mm a".
String formatTime12(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${_two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// `toLocaleString()` for whole numbers: 12,345.
String groupDigits(num v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b';
}

/// A metric, or an em dash so an empty cell still reads as a cell.
String metric(num? v) => v == null ? '—' : groupDigits(v);

/// `${Number(ctr).toFixed(2)}%`, or a dash when the CTR is 0 / missing (the
/// web's `stats.ctr ? … : "—"`).
String ctrText(num? v) => v == null || v == 0 ? '—' : '${v.toStringAsFixed(2)}%';

// ── Shared bits of page chrome ──────────────────────────────────────────────

/// Page title + subtitle, scaled down from the web's text-2xl.
class AdsPageHeader extends StatelessWidget {
  const AdsPageHeader({super.key, required this.title, required this.subtitle, this.action});

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.gray900),
              ),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(fontSize: 12.5, color: c.gray500)),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    );
  }
}

/// The small bordered / filled button the web's headers use.
class AdsButton extends StatelessWidget {
  const AdsButton({super.key, required this.label, this.icon, this.onTap, this.filled = false, this.spinning = false});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool filled;

  /// Swaps the icon for a small spinner (the web's `animate-spin`).
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = filled ? Colors.white : c.gray700;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: filled ? AppColors.blue600 : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: filled ? BorderSide.none : BorderSide(color: c.gray200),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (spinning)
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.6, color: filled ? Colors.white : c.gray500),
                  )
                else if (icon != null)
                  Icon(icon, size: 14, color: filled ? Colors.white : c.gray500),
                if (spinning || icon != null) const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A card surface — `rounded-xl bg-surface border border-gray-200`.
class AdsCard extends StatelessWidget {
  const AdsCard({super.key, required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray200),
      ),
      child: child,
    );
  }
}

/// The empty states' dashed box (a solid hairline here — Flutter has no
/// dashed border).
class AdsEmptyState extends StatelessWidget {
  const AdsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final Widget message;
  final Widget? action;

  /// The brand-tinted icon tile ("No campaigns yet") vs the gray circle
  /// ("No ads match your filters").
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AdsCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent ? AppColors.blue600.withValues(alpha: 0.08) : c.gray100,
              borderRadius: BorderRadius.circular(accent ? 14 : 24),
            ),
            child: Icon(icon, size: 22, color: accent ? AppColors.blue600 : c.gray400),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
          ),
          const SizedBox(height: 4),
          DefaultTextStyle.merge(
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: c.gray400, height: 1.4),
            child: message,
          ),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// Status tabs with counts + the filter bar (platform picker, search, result
/// count) — the block publishing/page.jsx and calendar/page.jsx share.
class AdsFilterPanel extends StatelessWidget {
  const AdsFilterPanel({
    super.key,
    required this.status,
    required this.counts,
    required this.onStatus,
    required this.platform,
    required this.platformGroupLabel,
    required this.platformOptions,
    required this.onPlatform,
    required this.search,
    required this.onSearch,
    required this.resultCount,
  });

  final String status;
  final Map<String, int> counts;
  final ValueChanged<String> onStatus;
  final String platform;
  final String platformGroupLabel;

  /// `(id, "emoji label")` pairs.
  final List<(String, String)> platformOptions;
  final ValueChanged<String> onPlatform;
  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final int resultCount;

  static const tabs = [('all', 'All'), ('ACTIVE', 'Active'), ('PAUSED', 'Paused')];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AdsCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.gray200)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final (key, label) in tabs) _statusTab(context, key, label)]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                _platformPicker(context),
                const SizedBox(width: 8),
                Expanded(child: _searchField(context)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Text(
              '$resultCount result${resultCount != 1 ? 's' : ''}',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11.5, color: c.gray400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusTab(BuildContext context, String key, String label) {
    final c = context.colors;
    final active = status == key;
    return InkWell(
      onTap: () => onStatus(key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: active ? AppColors.blue600 : Colors.transparent, width: 2)),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: active ? AppColors.blue600 : c.gray500,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: active ? AppColors.blue600 : c.gray100,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${counts[key] ?? 0}',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: active ? Colors.white : c.gray500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _platformPicker(BuildContext context) {
    final c = context.colors;
    final current = platform == 'all'
        ? 'All Platforms'
        : platformOptions.where((o) => o.$1 == platform).firstOrNull?.$2 ?? platform;
    return PopupMenuButton<String>(
      tooltip: 'Platform',
      initialValue: platform,
      onSelected: onPlatform,
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'all',
          child: Text('All Platforms', style: TextStyle(fontSize: 13)),
        ),
        PopupMenuItem(
          enabled: false,
          height: 30,
          child: Text(platformGroupLabel, style: TextStyle(fontSize: 11, color: c.gray400)),
        ),
        for (final (id, label) in platformOptions)
          PopupMenuItem(
            value: id,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
      ],
      child: Container(
        height: 38,
        constraints: const BoxConstraints(maxWidth: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: c.gray50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.gray200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.funnel, size: 13, color: c.gray400),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                current,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.gray700),
              ),
            ),
            Icon(LucideIcons.chevronDown, size: 13, color: c.gray400),
          ],
        ),
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 38,
      child: TextField(
        controller: search,
        onChanged: onSearch,
        style: TextStyle(fontSize: 13, color: c.gray800),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search by title or caption…',
          hintStyle: TextStyle(fontSize: 13, color: c.gray400),
          filled: true,
          fillColor: c.gray50,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          prefixIcon: Icon(LucideIcons.search, size: 14, color: c.gray400),
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          suffixIcon: search.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(LucideIcons.x, size: 14, color: c.gray400),
                  onPressed: () {
                    search.clear();
                    onSearch('');
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: c.gray200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: c.gray200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.blue600),
          ),
        ),
      ),
    );
  }
}

/// Status / platform / free-text filtering, as publishing and calendar both do it.
List<AdCampaign> filterCampaigns(
  List<AdCampaign> rows, {
  required String status,
  required String platform,
  required String search,
}) {
  final q = search.trim().toLowerCase();
  return rows.where((p) {
    if (status != 'all' && p.status != status) return false;
    if (platform != 'all' && p.platform != platform) return false;
    if (q.isNotEmpty && !p.title.toLowerCase().contains(q) && !p.caption.toLowerCase().contains(q)) return false;
    return true;
  }).toList();
}

/// A gray placeholder block for the loading skeletons
/// (`skeletons/ContentSectionSkeletons`).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: context.colors.gray100, borderRadius: BorderRadius.circular(radius)),
    );
  }
}

/// A small square thumbnail (or its gray stand-in).
class AdThumb extends StatelessWidget {
  const AdThumb({super.key, required this.url, this.size = 40});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.gray100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.gray200),
      ),
      child: url == null ? null : MediaImage(url!, cacheWidth: (size * 3).round()),
    );
  }
}
