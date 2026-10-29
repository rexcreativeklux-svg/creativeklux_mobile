import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'ads_api.dart';
import 'ads_widgets.dart';

/// Port of `ads-content/calendar/page.jsx` — the brand's campaigns on a month
/// grid, each on the day it was created (the only date the backend gives).
///
/// Phone layout: the web's 7-column grid with title pills becomes a compact
/// grid with a status-coloured dot per campaign (a 360dp cell is ~46px wide),
/// and the right-hand day panel becomes the list under the grid.
class AdsCalendarScreen extends StatefulWidget {
  const AdsCalendarScreen({super.key});

  static const path = '/ads-content/calendar';

  @override
  State<AdsCalendarScreen> createState() => _AdsCalendarScreenState();
}

class _AdsCalendarScreenState extends State<AdsCalendarScreen> {
  late final AdsApi _api;
  final _search = TextEditingController();

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<AdCampaign> _rows = [];
  DateTime? _selectedDay;

  // Filters (mirror the Publishing page): status / platform / free-text search.
  String _status = 'all';
  String _platform = 'all';

  /// An empty month grid is indistinguishable from a month with no campaigns,
  /// so the page holds a skeleton until the backend has answered.
  bool _loading = true;

  int? _brandId;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _api = AdsApi(context.read<AuthController>().api);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A brand switch clears the previous brand's month and holds the skeleton
    // until the backend answers for the new one.
    final brandId = context.watch<AuthController>().activeBrand?.id;
    if (brandId != _brandId) {
      _brandId = brandId;
      _fetchLive();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The campaigns, exactly as the backend lists them — nothing kept locally.
  Future<void> _fetchLive() async {
    final run = ++_run;
    setState(() {
      _rows = [];
      _loading = true;
    });
    try {
      final ints = await _api.integrations();
      final res = await _api.liveCampaigns(ints);
      if (!mounted || run != _run) return;
      setState(() => _rows = res.rows);
      if (res.errors.isNotEmpty) Toast.error(res.errors.join(' · '));
    } catch (e) {
      if (mounted && run == _run) Toast.error(e is AdsException ? e.message : "Couldn't load campaigns");
    } finally {
      if (mounted && run == _run) setState(() => _loading = false);
    }
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Monday-first weeks covering the month (`startOfWeek(…, {weekStartsOn: 1})`).
  List<DateTime> _days() {
    final first = DateTime(_month.year, _month.month);
    final last = DateTime(_month.year, _month.month + 1, 0);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final end = last.add(Duration(days: 7 - last.weekday));
    return [for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) d];
  }

  @override
  Widget build(BuildContext context) {
    final days = _days();
    return AdsSectionScaffold(
      location: AdsCalendarScreen.path,
      // Match the number of week rows the real grid is about to draw, so the
      // page doesn't jump when the ads land.
      child: _loading ? _skeleton(days.length ~/ 7) : _body(context, days),
    );
  }

  Widget _body(BuildContext context, List<DateTime> days) {
    final posts = _rows;
    // Platform options come from what's actually present, so the picker never lists empties.
    final platformOptions = {for (final p in posts) p.platform}.toList();
    final counts = {
      'all': posts.length,
      'ACTIVE': posts.where((p) => p.status == 'ACTIVE').length,
      'PAUSED': posts.where((p) => p.status == 'PAUSED').length,
    };
    final filtered = filterCampaigns(posts, status: _status, platform: _platform, search: _search.text);
    List<AdCampaign> postsFor(DateTime day) =>
        filtered.where((p) => p.createdAt != null && _sameDay(p.createdAt!, day)).toList();
    final totalActive = filtered.where((p) => p.status == 'ACTIVE').length;
    final totalPaused = filtered.where((p) => p.status == 'PAUSED').length;

    return RefreshIndicator(
      onRefresh: _fetchLive,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          AdsPageHeader(
            title: 'Ads Calendar',
            subtitle: '$totalActive active · $totalPaused paused · shown on the day each campaign was created',
            action: AdsButton(
              label: 'New Ad',
              icon: LucideIcons.plus,
              filled: true,
              onTap: () => context.go('/creatives'),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _legend(context, statusColor('ACTIVE')!, 'Active'),
              const SizedBox(width: 12),
              _legend(context, statusColor('PAUSED')!, 'Paused'),
            ],
          ),
          const SizedBox(height: 16),
          _monthNav(context),
          const SizedBox(height: 12),
          if (posts.isNotEmpty) ...[
            AdsFilterPanel(
              status: _status,
              counts: counts,
              onStatus: (s) => setState(() => _status = s),
              platform: _platform,
              platformGroupLabel: '── Ad Platforms',
              platformOptions: [
                for (final p in platformOptions)
                  (
                    p,
                    '${platformMetaOf(p).emoji} ${p.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ')}',
                  ),
              ],
              onPlatform: (p) => setState(() => _platform = p),
              search: _search,
              onSearch: (_) => setState(() {}),
              resultCount: filtered.length,
            ),
            const SizedBox(height: 14),
          ],
          _grid(context, days, postsFor),
          const SizedBox(height: 16),
          _dayPanel(context, _selectedDay == null ? const [] : postsFor(_selectedDay!)),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, Color color, String label) {
    return Row(
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

  Widget _monthNav(BuildContext context) {
    final c = context.colors;
    Widget arrow(IconData icon, int delta) => InkWell(
      onTap: () => setState(() => _month = DateTime(_month.year, _month.month + delta)),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.gray200),
        ),
        child: Icon(icon, size: 16, color: c.gray600),
      ),
    );
    return Row(
      children: [
        arrow(LucideIcons.chevronLeft, -1),
        Expanded(
          child: Text(
            '${monthsLong[_month.month - 1]} ${_month.year}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.gray900),
          ),
        ),
        arrow(LucideIcons.chevronRight, 1),
        const SizedBox(width: 4),
        TextButton(
          onPressed: () => setState(() => _month = DateTime(DateTime.now().year, DateTime.now().month)),
          style: TextButton.styleFrom(foregroundColor: c.gray500, textStyle: const TextStyle(fontSize: 12.5)),
          child: const Text('Today'),
        ),
      ],
    );
  }

  Widget _grid(BuildContext context, List<DateTime> days, List<AdCampaign> Function(DateTime) postsFor) {
    final c = context.colors;
    final now = DateTime.now();
    return AdsCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.gray100)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                for (final d in weekdaysShort)
                  Expanded(
                    child: Text(
                      d.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.gray400, letterSpacing: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          for (var w = 0; w < days.length ~/ 7; w++)
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(child: _dayCell(context, days[w * 7 + i], postsFor(days[w * 7 + i]), now, i == 6)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayCell(BuildContext context, DateTime day, List<AdCampaign> dayPosts, DateTime now, bool lastCol) {
    final c = context.colors;
    final selected = _selectedDay != null && _sameDay(day, _selectedDay!);
    final inMonth = day.month == _month.month;
    final today = _sameDay(day, now);
    return Opacity(
      opacity: inMonth ? 1 : 0.3,
      child: InkWell(
        onTap: () => setState(() => _selectedDay = selected ? null : day),
        child: Container(
          height: 58,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected ? c.blueTint : null,
            border: Border(
              bottom: BorderSide(color: c.gray100),
              right: lastCol ? BorderSide.none : BorderSide(color: c.gray100),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: today ? BoxDecoration(color: AppColors.blue600, shape: BoxShape.circle) : null,
                child: Text(
                  '${day.day}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: today ? Colors.white : c.gray700),
                ),
              ),
              const SizedBox(height: 4),
              // Up to three campaigns as status dots, then "+n" — the phone's
              // stand-in for the web's three pills + "+n more".
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final p in dayPosts.take(3))
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(color: statusColor(p.status) ?? c.gray300, shape: BoxShape.circle),
                    ),
                  if (dayPosts.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Text('+${dayPosts.length - 3}', style: TextStyle(fontSize: 9, color: c.gray400)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The web's "Day detail panel".
  Widget _dayPanel(BuildContext context, List<AdCampaign> dayPosts) {
    final c = context.colors;
    final day = _selectedDay;
    if (day == null) {
      return AdsCard(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Icon(LucideIcons.calendarDays, size: 28, color: c.gray300),
            const SizedBox(height: 8),
            Text('Tap a day to see its ads', style: TextStyle(fontSize: 12.5, color: c.gray400)),
          ],
        ),
      );
    }
    return AdsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.calendarDays, size: 16, color: AppColors.blue600),
              const SizedBox(width: 8),
              Text(
                '${weekdaysShort[day.weekday - 1]}, ${monthsShort[day.month - 1]} ${day.day}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (dayPosts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Text('No ads on this day', style: TextStyle(fontSize: 12.5, color: c.gray400)),
                  const SizedBox(height: 10),
                  AdsButton(label: 'Create an ad', icon: LucideIcons.plus, onTap: () => context.go('/creatives')),
                ],
              ),
            )
          else
            for (final p in dayPosts) ...[_DayPostCard(post: p), const SizedBox(height: 10)],
        ],
      ),
    );
  }

  /// `CalendarSkeleton`: header, month nav, the grid's week rows, the panel.
  Widget _skeleton(int weeks) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const SkeletonBox(width: 150, height: 20),
        const SizedBox(height: 8),
        const SkeletonBox(width: 260, height: 12),
        const SizedBox(height: 24),
        const SkeletonBox(height: 34),
        const SizedBox(height: 14),
        SkeletonBox(height: 34.0 + weeks * 58, radius: 12),
        const SizedBox(height: 16),
        const SkeletonBox(height: 110, radius: 12),
      ],
    );
  }
}

/// One campaign in the day list.
class _DayPostCard extends StatelessWidget {
  const _DayPostCard({required this.post});

  final AdCampaign post;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = statusColor(post.status);
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
              child: SizedBox(height: 120, child: MediaImage(post.imageUrl!, cacheWidth: 900)),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            post.title,
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
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color?.withValues(alpha: 0.14) ?? c.gray100,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  statusLabel(post.status),
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: color ?? c.gray600),
                ),
              ),
              const Spacer(),
              Text(
                '${platformMetaOf(post.platform).emoji} ${post.createdAt == null ? '' : formatTime12(post.createdAt!)}',
                style: TextStyle(fontSize: 11, color: c.gray400),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
