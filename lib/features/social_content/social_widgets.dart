import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/section_tabs.dart';
import '../shell/widgets/app_top_bar.dart';
import 'social_content_api.dart';

/// Pieces the three Social Content pages share. On the web each page repeats
/// them (the status tabs, the filter bar, PLATFORM_META); here they're written
/// once.

// ── Section shell ───────────────────────────────────────────────────────────

/// `social-content/layout.jsx` NAV_ITEMS.
final socialSectionTabs = [
  const SectionTab('Publishing', '/social-content/publishing', LucideIcons.share2),
  const SectionTab('Calendar', '/social-content/calendar', LucideIcons.calendar),
  const SectionTab('Analytics', '/social-content/analytics', LucideIcons.activity),
];

/// The web's `SectionLayout title="Social Content"`: the top bar, the
/// section's pages as tabs under it, then the page.
class SocialSectionScaffold extends StatelessWidget {
  const SocialSectionScaffold({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Social Content'),
          SectionTabs(tabs: socialSectionTabs, location: location),
          Expanded(
            child: ColoredBox(color: context.colors.page, child: child),
          ),
        ],
      ),
    );
  }
}

// ── Platforms ───────────────────────────────────────────────────────────────

/// One platform's look. The web keeps a PLATFORM_META per page; the fields
/// each page reads are merged here: [label] (Publishing / Analytics),
/// [short] (the Calendar's dense pills), [name] (prose like the delete
/// confirmation) and [color] (the Analytics charts).
class PlatformMeta {
  const PlatformMeta(this.label, this.short, this.name, this.emoji, this.color);

  final String label;
  final String short;
  final String name;
  final String emoji;
  final Color color;
}

const _platforms = {
  'facebook': PlatformMeta('Facebook', 'FB', 'Facebook', '🔵', Color(0xFF3B82F6)),
  'instagram': PlatformMeta('Instagram', 'IG', 'Instagram', '📸', Color(0xFFEC4899)),
  'twitter': PlatformMeta('X / Twitter', 'X', 'X', '🐦', Color(0xFF475569)),
  'linkedin': PlatformMeta('LinkedIn', 'LI', 'LinkedIn', '💼', Color(0xFF2563EB)),
  'tiktok': PlatformMeta('TikTok', 'TikTok', 'TikTok', '🎵', Color(0xFF94A3B8)),
  'youtube': PlatformMeta('YouTube', 'YT', 'YouTube', '▶️', Color(0xFFEF4444)),
  'pinterest': PlatformMeta('Pinterest', 'PIN', 'Pinterest', '📌', Color(0xFFF43F5E)),
};

PlatformMeta platformMeta(String platform) =>
    _platforms[platform] ?? PlatformMeta(platform, platform, platform, '🌐', const Color(0xFF888888));

/// The Publishing page's platform filter lists every social platform.
const socialPlatformIds = ['facebook', 'instagram', 'twitter', 'linkedin', 'tiktok', 'youtube', 'pinterest'];

/// `“Title” will be deleted from Facebook. This can't be undone.`
String deleteMessage(SocialPost post) {
  final title = post.projectTitle.isEmpty ? 'Untitled' : post.projectTitle;
  return '“$title” will be deleted from ${platformMeta(post.platform).name}. This can\'t be undone.';
}

bool canDelete(SocialPost post) => post.postId != null && SocialContentApi.supportsDelete(post.platform);

// ── Formatting ──────────────────────────────────────────────────────────────

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsLong = [
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
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _two(int n) => n.toString().padLeft(2, '0');

/// `toLocaleString()` for a count: 12,345.
String fmtNum(num n) {
  final s = n is int || n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(2);
  final parts = s.split('.');
  final neg = parts[0].startsWith('-');
  final digits = neg ? parts[0].substring(1) : parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '${neg ? '-' : ''}$buf${parts.length > 1 ? '.${parts[1]}' : ''}';
}

/// A metric, or an em dash so an empty cell still reads as a cell.
String fmtStat(num? v) => v == null ? '—' : fmtNum(v);

/// Publishing's `formatDate`: `Oct 29, 14:05`.
String fmtShortDateTime(DateTime? d) =>
    d == null ? '—' : '${_months[d.month - 1]} ${d.day}, ${_two(d.hour)}:${_two(d.minute)}';

/// date-fns `MMM d`.
String fmtMonthDay(DateTime d) => '${_months[d.month - 1]} ${d.day}';

/// date-fns `MMM d HH:mm`.
String fmtMonthDayTime(DateTime d) => '${fmtMonthDay(d)} ${_two(d.hour)}:${_two(d.minute)}';

/// date-fns `MMMM yyyy`.
String fmtMonthYear(DateTime d) => '${_monthsLong[d.month - 1]} ${d.year}';

/// date-fns `EEE, MMM d`.
String fmtWeekdayMonthDay(DateTime d) => '${_weekdays[d.weekday - 1]}, ${fmtMonthDay(d)}';

/// date-fns `h:mm a`.
String fmtTime12(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${_two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

// ── Filtering (shared by Publishing + Calendar) ─────────────────────────────

/// "Scheduled" is a post the platform itself reports as scheduled.
const statusTabs = [('all', 'All'), ('published', 'Published'), ('scheduled', 'Scheduled')];

Map<String, int> statusCounts(List<SocialPost> posts) => {
  'all': posts.length,
  'published': posts.where((p) => p.status == 'published').length,
  'scheduled': posts.where((p) => p.status == 'scheduled').length,
};

/// Status / platform / free-text (title or caption) filters.
List<SocialPost> filterPosts(
  List<SocialPost> posts, {
  required String status,
  required String platform,
  required String search,
}) {
  final q = search.trim().toLowerCase();
  return posts.where((p) {
    if (status != 'all' && p.status != status) return false;
    if (platform != 'all' && p.platform != platform) return false;
    if (q.isNotEmpty && !p.projectTitle.toLowerCase().contains(q) && !p.caption.toLowerCase().contains(q)) {
      return false;
    }
    return true;
  }).toList();
}

/// The status tab row + filter bar, in one card — the web draws them as two
/// joined boxes (tabs on top, filters below).
class PostFilterCard extends StatelessWidget {
  const PostFilterCard({
    super.key,
    required this.counts,
    required this.status,
    required this.onStatus,
    required this.platformOptions,
    required this.platform,
    required this.onPlatform,
    required this.searchController,
    required this.onSearch,
    required this.resultCount,
  });

  final Map<String, int> counts;
  final String status;
  final ValueChanged<String> onStatus;

  /// `(id, label)` for each platform the menu offers, after "All Platforms".
  final List<(String, String)> platformOptions;
  final String platform;
  final ValueChanged<String> onPlatform;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final platformLabel = platform == 'all'
        ? 'All Platforms'
        : platformOptions.firstWhere((o) => o.$1 == platform, orElse: () => (platform, platform)).$2;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Scrolls sideways on narrow screens instead of squeezing.
          Container(
            height: 44,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.gray200)),
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              children: [
                for (final (key, label) in statusTabs)
                  _StatusTab(label: label, count: counts[key] ?? 0, active: status == key, onTap: () => onStatus(key)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    PopupMenuButton<String>(
                      useRootNavigator: true,
                      initialValue: platform,
                      onSelected: onPlatform,
                      tooltip: 'Filter by platform',
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'all', height: 40, child: Text('All Platforms')),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          enabled: false,
                          height: 28,
                          child: Text('Social Media', style: TextStyle(fontSize: 11, color: c.gray400)),
                        ),
                        for (final (id, label) in platformOptions)
                          PopupMenuItem(value: id, height: 40, child: Text('${platformMeta(id).emoji}  $label')),
                      ],
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: c.gray50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.gray200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.funnel, size: 14, color: c.gray400),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 110),
                              child: Text(
                                platformLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: c.gray700),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(LucideIcons.chevronDown, size: 14, color: c.gray400),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$resultCount result${resultCount != 1 ? 's' : ''}',
                      style: TextStyle(fontSize: 12, color: c.gray400),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ValueListenableBuilder(
                    valueListenable: searchController,
                    builder: (context, value, _) => TextField(
                      controller: searchController,
                      onChanged: onSearch,
                      style: TextStyle(fontSize: 13.5, color: c.gray900),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search by title or caption…',
                        hintStyle: TextStyle(color: c.gray400, fontSize: 13.5),
                        prefixIcon: Icon(LucideIcons.search, size: 15, color: c.gray400),
                        suffixIcon: value.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: Icon(LucideIcons.x, size: 15, color: c.gray400),
                                onPressed: () {
                                  searchController.clear();
                                  onSearch('');
                                },
                              ),
                        filled: true,
                        fillColor: c.gray50,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTab extends StatelessWidget {
  const _StatusTab({required this.label, required this.count, required this.active, required this.onTap});

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = AppColors.blue600;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: active ? accent : Colors.transparent, width: 2)),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: active ? accent : c.gray500),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: active ? accent : c.gray100, borderRadius: BorderRadius.circular(99)),
              child: Text(
                '$count',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: active ? Colors.white : c.gray500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small pieces ────────────────────────────────────────────────────────────

/// Page heading + subtitle, with optional actions on the right.
class SocialPageHeader extends StatelessWidget {
  const SocialPageHeader({super.key, required this.title, required this.subtitle, this.action});

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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.gray900, letterSpacing: -0.2),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12.5, color: c.gray500)),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    );
  }
}

/// A small header button: filled (the web's brand-blue links) or outlined.
class SocialButton extends StatelessWidget {
  const SocialButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.filled = false,
    this.spinning = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool filled;

  /// Swaps the icon for a spinner (the web's `animate-spin` refresh icon).
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
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
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
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Published (green) / Scheduled (blue) pill.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final published = status == 'published';
    final color = published ? AppColors.green600 : AppColors.blue600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(published ? LucideIcons.circleCheck : LucideIcons.clock, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            published ? 'Published' : 'Scheduled',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

/// Emoji + platform name pill, tinted with the platform's colour.
class PlatformPill extends StatelessWidget {
  const PlatformPill({super.key, required this.platform});

  final String platform;

  @override
  Widget build(BuildContext context) {
    final m = platformMeta(platform);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: m.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: m.color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '${m.emoji} ${m.label}',
        maxLines: 1,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: m.color),
      ),
    );
  }
}

/// A post's thumbnail, or an empty tile when it has none.
class PostThumb extends StatelessWidget {
  const PostThumb({super.key, required this.url, this.size = 44, this.radius = 8});

  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.gray100,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.gray200),
      ),
      child: url == null ? null : MediaImage(url!, cacheWidth: (size * 3).round()),
    );
  }
}

/// A dashed-border empty state (icon, title, body, optional action).
class SocialEmptyState extends StatelessWidget {
  const SocialEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.accentIcon = false,
  });

  final IconData icon;
  final String title;
  final Widget body;
  final Widget? action;

  /// The brand-tinted rounded square (Publishing's "no posts yet") instead of
  /// the plain grey circle.
  final bool accentIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accentIcon ? AppColors.blue600.withValues(alpha: 0.08) : c.gray100,
              borderRadius: BorderRadius.circular(accentIcon ? 14 : 24),
            ),
            child: Icon(icon, size: accentIcon ? 24 : 20, color: accentIcon ? AppColors.blue600 : c.gray400),
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
            child: body,
          ),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// A grey block for the loading skeletons (the web's ContentSectionSkeletons).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: context.colors.gray100, borderRadius: BorderRadius.circular(radius)),
  );
}
