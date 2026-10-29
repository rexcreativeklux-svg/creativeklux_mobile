import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'social_content_api.dart';
import 'social_widgets.dart';

/// Port of `(pages)/social-content/calendar/page.jsx` — "Social Calendar":
/// the month's posts on a Monday-first grid, with the same status / platform /
/// search filters as Publishing.
///
/// Phone layout: the grid is too narrow for the web's title pills, so each
/// day shows up to three status-coloured dots (+N). The web's side "day
/// detail" panel sits under the grid.
class SocialCalendarScreen extends StatefulWidget {
  const SocialCalendarScreen({super.key, this.location = path});

  static const path = '/social-content/calendar';

  /// The current route, for the section tabs.
  final String location;

  @override
  State<SocialCalendarScreen> createState() => _SocialCalendarScreenState();
}

const _publishedColor = AppColors.green500;
const _scheduledColor = Color(0xFF3B82F6);

Color _statusColor(String status) => switch (status) {
  'published' => _publishedColor,
  'scheduled' => _scheduledColor,
  _ => const Color(0xFFD1D5DC),
};

class _SocialCalendarScreenState extends State<SocialCalendarScreen> {
  late final SocialContentApi _api;
  final _searchCtl = TextEditingController();

  int? _brandId;
  bool _brandSeen = false;
  int _run = 0;

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<SocialPost> _allPosts = [];
  DateTime? _selectedDay;

  /// An empty month grid is indistinguishable from a month with nothing
  /// posted, so the page holds a skeleton until the backend has answered.
  /// Later refetches (after a delete) keep the grid up.
  bool _loading = true;

  String _status = 'all';
  String _platform = 'all';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _api = SocialContentApi(context.read<AuthController>().api);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A brand switch clears the previous brand's month and holds the skeleton
    // until the backend answers for the new one.
    final brandId = context.watch<AuthController>().activeBrand?.id;
    if (!_brandSeen || brandId != _brandId) {
      _brandSeen = true;
      _brandId = brandId;
      setState(() {
        _allPosts = [];
        _loading = true;
      });
      _fetchLive();
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  /// The posts, exactly as the backend lists them — nothing kept locally.
  Future<void> _fetchLive() async {
    final run = ++_run;
    try {
      final ints = await _api.integrations();
      final live = await _api.livePosts(ints, _brandId);
      if (!mounted || run != _run) return;
      setState(() => _allPosts = live.rows);
      if (live.errors.isNotEmpty) Toast.error(live.errors.join(' · '));
    } catch (e) {
      if (!mounted || run != _run) return;
      Toast.error(e is SocialApiException ? e.message : "Couldn't load posts");
    } finally {
      if (mounted && run == _run) setState(() => _loading = false);
    }
  }

  Future<void> _confirmDelete(SocialPost post) async {
    await showConfirmDialog(
      context,
      title: 'Delete this post?',
      message: deleteMessage(post),
      confirmLabel: 'Delete',
      danger: true,
      onConfirm: () async {
        try {
          await _api.deletePost(post, _brandId);
          await _fetchLive();
          Toast.success('Post deleted');
        } on SocialApiException catch (e) {
          Toast.error(e.message);
        }
      },
    );
  }

  /// Monday-first weeks covering the whole month (date-fns `startOfWeek` /
  /// `endOfWeek` with `weekStartsOn: 1`).
  List<DateTime> get _days {
    final first = DateTime(_month.year, _month.month);
    final last = DateTime(_month.year, _month.month + 1, 0);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final end = last.add(Duration(days: 7 - last.weekday));
    // Stepped by calendar fields, not by adding 24h, so a DST change can't
    // shift a day.
    return [for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) d];
  }

  @override
  Widget build(BuildContext context) {
    return SocialSectionScaffold(
      location: widget.location,
      child: _loading ? _CalendarSkeleton(weeks: _days.length ~/ 7) : _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final c = context.colors;
    final posts = _allPosts.where((p) => p.type == 'social').toList();
    final filtered = filterPosts(posts, status: _status, platform: _platform, search: _search);

    // Platform options come from what's actually present, so the menu never
    // lists empties.
    final platformOptions = <(String, String)>[
      for (final p in {for (final p in posts) p.platform})
        (p, p.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ')),
    ];

    List<SocialPost> postsFor(DateTime day) => filtered.where((p) => p.when != null && sameDay(p.when!, day)).toList();

    final totalScheduled = filtered.where((p) => p.status == 'scheduled').length;
    final totalPublished = filtered.where((p) => p.status == 'published').length;
    final selected = _selectedDay;
    final selectedPosts = selected == null ? const <SocialPost>[] : postsFor(selected);

    return RefreshIndicator(
      onRefresh: _fetchLive,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          SocialPageHeader(
            title: 'Social Calendar',
            subtitle: '$totalScheduled scheduled · $totalPublished published',
            action: SocialButton(
              label: 'New Post',
              icon: LucideIcons.plus,
              filled: true,
              onTap: () => context.go('/creatives'),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _LegendDot(color: _publishedColor, label: 'Published'),
              const SizedBox(width: 12),
              _LegendDot(color: _scheduledColor, label: 'Scheduled'),
            ],
          ),
          const SizedBox(height: 16),

          // ── Month nav ──
          Row(
            children: [
              _NavButton(
                icon: LucideIcons.chevronLeft,
                onTap: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              ),
              Expanded(
                child: Text(
                  fmtMonthYear(_month),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.gray900),
                ),
              ),
              _NavButton(
                icon: LucideIcons.chevronRight,
                onTap: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
              ),
              TextButton(
                onPressed: () => setState(() => _month = DateTime(DateTime.now().year, DateTime.now().month)),
                style: TextButton.styleFrom(foregroundColor: c.gray500, textStyle: const TextStyle(fontSize: 12.5)),
                child: const Text('Today'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (posts.isNotEmpty) ...[
            PostFilterCard(
              counts: statusCounts(posts),
              status: _status,
              onStatus: (s) => setState(() => _status = s),
              platformOptions: platformOptions,
              platform: _platform,
              onPlatform: (p) => setState(() => _platform = p),
              searchController: _searchCtl,
              onSearch: (v) => setState(() => _search = v),
              resultCount: filtered.length,
            ),
            const SizedBox(height: 16),
          ],

          _MonthGrid(
            month: _month,
            days: _days,
            selected: selected,
            postsFor: postsFor,
            onTap: (day) => setState(() => _selectedDay = selected != null && sameDay(day, selected) ? null : day),
          ),
          const SizedBox(height: 16),

          _DayPanel(
            day: selected,
            posts: selectedPosts,
            onDelete: _confirmDelete,
            onNew: () => context.go('/creatives'),
          ),
        ],
      ),
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 12, color: context.colors.gray500)),
    ],
  );
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.gray200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(width: 34, height: 34, child: Icon(icon, size: 16, color: c.gray600)),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.days,
    required this.selected,
    required this.postsFor,
    required this.onTap,
  });

  final DateTime month;
  final List<DateTime> days;
  final DateTime? selected;
  final List<SocialPost> Function(DateTime) postsFor;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = DateTime.now();
    final weeks = days.length ~/ 7;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.gray100)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                for (final d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                  Expanded(
                    child: Text(
                      d.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.gray400, letterSpacing: 0.4),
                    ),
                  ),
              ],
            ),
          ),
          for (var w = 0; w < weeks; w++)
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: _DayCell(
                      day: days[w * 7 + i],
                      posts: postsFor(days[w * 7 + i]),
                      inMonth: days[w * 7 + i].month == month.month,
                      isToday: sameDay(days[w * 7 + i], today),
                      isSelected: selected != null && sameDay(days[w * 7 + i], selected!),
                      lastInRow: i == 6,
                      lastRow: w == weeks - 1,
                      onTap: () => onTap(days[w * 7 + i]),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.posts,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.lastInRow,
    required this.lastRow,
    required this.onTap,
  });

  final DateTime day;
  final List<SocialPost> posts;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final bool lastInRow;
  final bool lastRow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Opacity(
      opacity: inMonth ? 1 : 0.3,
      child: Material(
        color: isSelected ? c.blueTint : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 58,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border(
                right: lastInRow ? BorderSide.none : BorderSide(color: c.gray100),
                bottom: lastRow ? BorderSide.none : BorderSide(color: c.gray100),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: isToday ? AppColors.blue600 : null, shape: BoxShape.circle),
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isToday ? Colors.white : c.gray700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                if (posts.isNotEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final p in posts.take(3))
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(color: _statusColor(p.status), shape: BoxShape.circle),
                        ),
                    ],
                  ),
                if (posts.length > 3)
                  Text('+${posts.length - 3}', style: TextStyle(fontSize: 9, color: c.gray400, height: 1.4)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The web's "day detail" panel.
class _DayPanel extends StatelessWidget {
  const _DayPanel({required this.day, required this.posts, required this.onDelete, required this.onNew});

  final DateTime? day;
  final List<SocialPost> posts;
  final ValueChanged<SocialPost> onDelete;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = day;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray200),
      ),
      child: d == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(LucideIcons.calendarDays, size: 30, color: c.gray300),
                  const SizedBox(height: 8),
                  Text('Tap a day to see its posts', style: TextStyle(fontSize: 12, color: c.gray400)),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.calendarDays, size: 16, color: AppColors.blue600),
                    const SizedBox(width: 8),
                    Text(
                      fmtWeekdayMonthDay(d),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray800),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (posts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        Text('No posts on this day', style: TextStyle(fontSize: 12, color: c.gray400)),
                        const SizedBox(height: 12),
                        SocialButton(label: 'Schedule a post', icon: LucideIcons.plus, onTap: onNew),
                      ],
                    ),
                  )
                else
                  for (final p in posts) ...[
                    _DayPost(post: p, onDelete: canDelete(p) ? () => onDelete(p) : null),
                    if (p != posts.last) const SizedBox(height: 10),
                  ],
              ],
            ),
    );
  }
}

class _DayPost extends StatelessWidget {
  const _DayPost({required this.post, this.onDelete});

  final SocialPost post;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final when = post.when;
    final badge = _statusColor(post.status);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (post.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(height: 140, child: MediaImage(post.imageUrl!, cacheWidth: 900)),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.projectTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray800),
                    ),
                    if (post.caption.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          post.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: c.gray400),
                        ),
                      ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: Icon(LucideIcons.trash2, size: 15, color: AppColors.red500.withValues(alpha: 0.8)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badge.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  post.status,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: badge),
                ),
              ),
              const Spacer(),
              Text(
                '${platformMeta(post.platform).emoji} ${when == null ? '' : fmtTime12(when)}',
                style: TextStyle(fontSize: 11, color: c.gray400),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The web's `CalendarSkeleton` — the same number of week rows the real grid
/// is about to draw, so the page doesn't jump when the posts land.
class _CalendarSkeleton extends StatelessWidget {
  const _CalendarSkeleton({required this.weeks});

  final int weeks;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const SkeletonBox(width: 170, height: 20),
        const SizedBox(height: 8),
        const SkeletonBox(width: 150, height: 12),
        const SizedBox(height: 40),
        const SkeletonBox(height: 34),
        const SizedBox(height: 16),
        SkeletonBox(height: 34 + weeks * 58.0, radius: 12),
        const SizedBox(height: 16),
        const SkeletonBox(height: 100, radius: 12),
      ],
    );
  }
}
