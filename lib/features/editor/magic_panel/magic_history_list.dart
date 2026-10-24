import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/media.dart';
import 'magic_history_api.dart';

/// One tool's generation history, sized for the editor panel — port of
/// `panels/magic/MagicHistoryList.jsx`. The same records the Magic Studio page
/// shows, newest first: tap a tile to put it on the design, trash to delete.
///
/// Non-image records still render (a video or persona copy made elsewhere is
/// part of the honest history); the panel's pick handler decides what can be
/// placed. Delete stays visible — there's no hover on touch.
///
/// Built as slivers so it shares the tab's one scroll view.
List<Widget> magicHistorySlivers(
  BuildContext context, {
  required List<MagicHistoryItem> items,
  required bool loading,
  required bool generating,
  required void Function(MagicHistoryItem) onPick,
  required void Function(MagicHistoryItem) onDelete,
  String? removingId,
}) {
  final c = context.colors;

  // First load with nothing to show — a spinner beats an empty grid that
  // fills in a beat later.
  if (loading && items.isEmpty && !generating) {
    return const [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
    ];
  }

  if (!generating && items.isEmpty) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
          child: Column(
            children: [
              Icon(LucideIcons.imageOff, size: 24, color: c.gray300),
              const SizedBox(height: 8),
              Text(
                'Nothing generated yet — your results will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.gray400),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  return [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Newest first · automatically deleted after 30 days',
          style: TextStyle(fontSize: 11, color: c.gray400),
        ),
      ),
    ),
    SliverGrid.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        // Leading tile for the run still in flight, so switching to History
        // mid-generation doesn't look empty.
        if (generating)
          DecoratedBox(
            decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(8)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue500),
                ),
                const SizedBox(height: 8),
                Text('Generating…', style: TextStyle(fontSize: 10, color: c.gray500)),
              ],
            ),
          ),
        for (final item in items)
          _HistoryTile(
            key: ValueKey(item.id),
            item: item,
            removing: removingId != null && item.generationId == removingId,
            onPick: () => onPick(item),
            onDelete: () => onDelete(item),
          ),
      ],
    ),
  ];
}

/// One record: image thumb, video poster with a play badge, or a snippet of copy.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    super.key,
    required this.item,
    required this.removing,
    required this.onPick,
    required this.onDelete,
  });

  final MagicHistoryItem item;
  final bool removing;
  final VoidCallback onPick;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Widget body;
    if (item.type == 'text') {
      body = Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          item.content ?? '',
          maxLines: 7,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, height: 1.35, color: c.gray600),
        ),
      );
    } else if (item.type == 'video') {
      // A poster when the record has one; a dark tile otherwise — spinning a
      // player per tile just to show a frame isn't worth it in a sheet.
      body = Stack(
        fit: StackFit.expand,
        children: [
          if (item.thumbnail != null) MediaImage(item.thumbnail!, cacheWidth: 300) else ColoredBox(color: c.gray800),
          Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(LucideIcons.play, size: 14, color: Colors.white),
            ),
          ),
        ],
      );
    } else {
      body = MediaImage(item.thumbnail ?? item.url ?? '', cacheWidth: 300);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Tooltip(
          message: item.prompt ?? 'Add to design',
          child: Material(
            color: item.type == 'text' ? c.surface : c.gray50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: c.gray200),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: removing ? null : onPick, child: body),
          ),
        ),
        if (removing)
          DecoratedBox(
            decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: Semantics(
            label: 'Delete result',
            button: true,
            child: GestureDetector(
              onTap: removing ? null : onDelete,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: removing ? 0.25 : 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(LucideIcons.trash2, size: 13, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
