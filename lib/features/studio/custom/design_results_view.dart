import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/design/design_canvas.dart';
import '../../../core/theme/app_colors.dart';

/// Port of `DesignResultPanel` in the web's `studio/Adpreview.jsx`: the
/// generated designs as a two-column masonry, tap to select, then save the
/// selection to the brand's library. Designs still being generated show as
/// shimmering skeletons.
class DesignResultsView extends StatefulWidget {
  const DesignResultsView({
    super.key,
    required this.variations,
    required this.expectedCount,
    required this.done,
    required this.onBack,
    required this.onSave,
  });

  final List<Map<String, dynamic>> variations;
  final int expectedCount;
  final bool done;
  final VoidCallback onBack;

  /// Saves the given designs; resolves with an error message or null.
  final Future<String?> Function(List<Map<String, dynamic>> designs) onSave;

  @override
  State<DesignResultsView> createState() => _DesignResultsViewState();
}

class _DesignResultsViewState extends State<DesignResultsView> {
  final _selected = <int>{};
  bool _saving = false;

  int get _pending => widget.done ? 0 : (widget.expectedCount - widget.variations.length).clamp(0, 99);

  Future<void> _save() async {
    setState(() => _saving = true);
    final picked = [for (final i in _selected.toList()..sort()) widget.variations[i]];
    final error = await widget.onSave(picked);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error == null) _selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = widget.variations.length;
    final loadingMore = _pending > 0;
    final allSelected = count > 0 && _selected.length == count;

    // Masonry by hand: alternate cards into two columns.
    final cards = <Widget>[
      for (var i = 0; i < count; i++)
        _ResultCard(
          variation: widget.variations[i],
          selected: _selected.contains(i),
          onTap: () => setState(() => _selected.contains(i) ? _selected.remove(i) : _selected.add(i)),
        ),
      for (var i = 0; i < _pending; i++) const _SkeletonCard(),
    ];
    final left = [for (var i = 0; i < cards.length; i += 2) cards[i]];
    final right = [for (var i = 1; i < cards.length; i += 2) cards[i]];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: BorderSide(color: c.gray200)),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: widget.onBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.gray600,
                  side: BorderSide(color: c.gray200),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(LucideIcons.chevronLeft, size: 15),
                label: const Text('Back', style: TextStyle(fontSize: 12.5)),
              ),
              const SizedBox(width: 10),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: loadingMore ? AppColors.amber500 : AppColors.green500,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  loadingMore ? 'Generating $count of ${widget.expectedCount}…' : '$count designs ready',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.gray600),
                ),
              ),
              if (count > 0)
                TextButton(
                  onPressed: () => setState(() {
                    if (allSelected) {
                      _selected.clear();
                    } else {
                      _selected.addAll(List.generate(count, (i) => i));
                    }
                  }),
                  style: TextButton.styleFrom(
                    foregroundColor: c.gray600,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                  child: Text(allSelected ? 'Deselect all' : 'Select all'),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: left)),
                const SizedBox(width: 10),
                Expanded(child: Column(children: right)),
              ],
            ),
          ),
        ),
        // Save bar — slides in once something is picked.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _selected.isEmpty
              ? const SizedBox(width: double.infinity)
              : Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border(top: BorderSide(color: c.gray200)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.green600,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(LucideIcons.save, size: 16),
                        label: Text(
                          _saving
                              ? 'Saving…'
                              : 'Save ${_selected.length} design${_selected.length == 1 ? '' : 's'} to My Creations',
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

int _score(Map<String, dynamic> v) {
  final copy = v['copy'] is Map ? v['copy'] as Map : const {};
  return int.tryParse('${copy['performance_score'] ?? ''}'.split('/').first.trim()) ?? 0;
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.variation, required this.selected, required this.onTap});

  final Map<String, dynamic> variation;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = variation;
    final copy = v['copy'] is Map ? v['copy'] as Map : const {};
    final score = _score(v);
    final canvas = v['canvas'] is Map ? Map<String, dynamic>.from(v['canvas'] as Map) : <String, dynamic>{};
    final elements = v['elements'] is List ? v['elements'] as List : const [];
    String? str(Object? x) => x == null || '$x'.trim().isEmpty ? null : '$x';
    final tagline = str(copy['tagline']) ?? str(copy['hook']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? AppColors.green500 : c.gray200, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  Container(
                    color: c.page,
                    padding: const EdgeInsets.all(8),
                    child: DesignCanvas(
                      canvas: canvas,
                      elements: elements,
                      scraive: v['source'] == 'scraive',
                      maxHeight: 260,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.green500 : c.surface,
                        shape: BoxShape.circle,
                        border: selected ? null : Border.all(color: c.gray300, width: 1.5),
                        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 4)],
                      ),
                      child: selected ? const Icon(LucideIcons.check, size: 13, color: Colors.white) : null,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            str(v['name']) ?? 'Design',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.gray900),
                          ),
                        ),
                        if (str(v['category']) != null) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(99)),
                            child: Text('${v['category']}', style: TextStyle(fontSize: 9.5, color: c.gray500)),
                          ),
                        ],
                      ],
                    ),
                    if (str(copy['headline']) != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${copy['headline']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.gray800),
                      ),
                    ],
                    if (tagline != null)
                      Text(
                        tagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: c.gray500),
                      ),
                    if (str(copy['cta']) != null || score > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (str(copy['cta']) != null)
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: c.gray900, borderRadius: BorderRadius.circular(99)),
                                child: Text(
                                  '${copy['cta']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: c.surface),
                                ),
                              ),
                            ),
                          const Spacer(),
                          if (score > 0)
                            Text(
                              '★ $score/100',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: score >= 90
                                    ? AppColors.green500
                                    : score >= 75
                                    ? AppColors.amber500
                                    : c.gray400,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder for a design still on its way, with a sweeping shimmer.
class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(color: c.gray200, borderRadius: BorderRadius.circular(4)),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(-1 + 3 * _anim.value - 1, 0),
            end: Alignment(3 * _anim.value - 1, 0),
            colors: [Colors.transparent, Colors.white.withValues(alpha: 0.6), Colors.transparent],
          ).createShader(rect),
          child: child,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.gray200),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(color: c.gray200, borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              bar(0.6, 10),
              const SizedBox(height: 6),
              bar(0.9, 8),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
