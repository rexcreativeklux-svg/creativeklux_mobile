import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../copilot_store.dart';
import '../data/copilot_catalog.dart';
import '../data/copilot_data.dart';
import '../data/copilot_types.dart';
import '../widgets/copilot_widgets.dart';

/// Which pill a copilot's own work lands under (SkillsTab.jsx) — the one
/// place that translates a product surface into "what you came to do".
const _categoryToPill = {
  'Brand': 'Make designs',
  'Social': 'Plan content',
  'Ads': 'Run ads',
  'Performance': 'Study performance',
  'Product': 'Prep products',
  'Studio': 'Plan content',
};

/// The Plugins screen's Skills tab: three featured cards with a preview of
/// what each hands back, then the browse list under pills.
///
/// ⚠️ ACTIVATING A SKILL DRAFTS `/slug ` in a new chat, NOT sent — `/brand-audit`
/// on its own names nothing to run on. (Workflows' Send to chat does send.)
class SkillsTab extends StatefulWidget {
  const SkillsTab({super.key, required this.copilot, required this.onOpenInChat, required this.onBrowseAll});
  final Copilot copilot;
  final ValueChanged<String> onOpenInChat;
  final VoidCallback onBrowseAll;

  @override
  State<SkillsTab> createState() => _SkillsTabState();
}

class _SkillsTabState extends State<SkillsTab> {
  late String _pill = _categoryToPill[widget.copilot.category] ?? 'Recommended';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cat = widget.copilot.category;
    // "Recommended" is a view, not a category: this copilot's own work first,
    // then everything else — so it never opens empty.
    final visible = _pill == 'Recommended'
        ? [
            ...browseSkills.where((s) => s.surface == cat),
            ...browseSkills.where((s) => s.surface != cat),
          ].take(6).toList()
        : browseSkills.where((s) => s.category == _pill).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Text(
          'Recommended skills',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.gray900),
        ),
        const SizedBox(height: 12),
        for (final s in featuredSkills)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _FeaturedSkillCard(skill: s, onActivate: () => widget.onOpenInChat(skillPrompt(s.slug))),
          ),
        const SizedBox(height: 10),
        Divider(height: 1, color: c.gray200),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Browse by what you want to do',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.gray900),
              ),
            ),
            TextButton.icon(
              onPressed: widget.onBrowseAll,
              iconAlignment: IconAlignment.end,
              icon: Icon(LucideIcons.arrowRight, size: 15, color: c.gray500),
              label: Text('Browse all', style: TextStyle(fontSize: 13, color: c.gray500)),
            ),
          ],
        ),
        // Counted, not written down — the line cannot drift from the list.
        Text(
          '${allSkills.length} skills across every part of your brand.',
          style: TextStyle(fontSize: 13, color: c.gray500),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in skillCategories)
              Material(
                color: p == _pill ? c.gray200 : Colors.transparent,
                shape: StadiumBorder(side: BorderSide(color: p == _pill ? Colors.transparent : c.gray200)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => setState(() => _pill = p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                    child: Text(
                      p,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: p == _pill ? FontWeight.w600 : FontWeight.w500,
                        color: p == _pill ? c.gray900 : c.gray500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        for (final s in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SkillCard(skill: s, onTap: () => widget.onOpenInChat(skillPrompt(s.slug))),
          ),
      ],
    );
  }
}

class _FeaturedSkillCard extends StatelessWidget {
  const _FeaturedSkillCard({required this.skill, required this.onActivate});
  final CopilotSkill skill;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.gray100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Container(
              decoration: BoxDecoration(color: Tw.bg(skill.tint), borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              alignment: Alignment.center,
              // ⚠️ A fixed 16/10 box keeps the three cards level (the mocks are
              // different natural heights); scale-down keeps a tall mock inside
              // it instead of clipping, at the width its 10px type was drawn for.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(width: 260, child: SkillPreview(preview: skill.preview)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        skill.name ?? skill.slug,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.gray900),
                      ),
                    ),
                    SurfaceChip(skill.surface),
                    for (final p in skill.platforms)
                      Padding(padding: const EdgeInsets.only(left: 6), child: PlatformChip(p)),
                  ],
                ),
                const SizedBox(height: 2),
                // The slash command IS the skill's name in use — set in mono.
                Text(
                  '/${skill.slug}',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: c.gray500),
                ),
                const SizedBox(height: 8),
                Text(
                  skill.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, height: 1.5, color: c.gray500),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkButton(label: 'Activate skill', onTap: onActivate),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One skill as a card: slash command, what it does, who published it
/// (SkillCard.jsx). [action] (the browse sheet's +/✓) or [onTap] (run it).
class SkillCard extends StatelessWidget {
  const SkillCard({super.key, required this.skill, this.onTap, this.action});
  final CopilotSkill skill;
  final VoidCallback? onTap;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.gray200),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SurfaceChip(skill.surface),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '/${skill.slug}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: c.gray900,
                          ),
                        ),
                      ),
                      ?action,
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    skill.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, height: 1.5, color: c.gray500),
                  ),
                ],
              ),
            ),
            // Provenance under a rule — who wrote it, not what it does.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.gray200)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.badgeCheck, size: 14, color: c.gray400),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '$skillAuthor  •  Updated on ${skill.updated ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.gray500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The little mock inside a featured card (SkillPreview.jsx) — an illustration
/// of the skill's OUTPUT, not a screenshot, so it can't go stale.
class SkillPreview extends StatelessWidget {
  const SkillPreview({super.key, required this.preview});
  final String? preview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(9),
      boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1))],
    );
    Widget label(String t, {double size = 8}) => Text(
      t,
      style: TextStyle(fontSize: size, height: 1, color: c.gray400),
    );

    switch (preview) {
      case 'brand':
        Widget flag(Color tint, Color dot, String text, [String? count]) => Container(
          margin: const EdgeInsets.only(top: 5),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(6)),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Tw.gray900),
                ),
              ),
              if (count != null) Text(count, style: const TextStyle(fontSize: 10, color: Color(0xFF99A1AF))),
            ],
          ),
        );
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Brand check',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.gray900),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final s in [AppColors.blue600, Tw.gray900, Tw.orange500, Tw.emerald600])
                    Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(color: s, borderRadius: BorderRadius.circular(4)),
                    ),
                  // The odd one out — the mock shows the check failing.
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Tw.rose400,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Tw.rose200, width: 2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              flag(const Color(0xFFFFF1F2), Tw.rose500, 'Off-brand red', '2 designs'),
              flag(const Color(0xFFFFFBEB), Tw.amber500, 'Wrong heading font', '1 design'),
              flag(Tw.emerald50, Tw.emerald500, '9 on brand'),
            ],
          ),
        );
      case 'campaign':
        const pieces = [('Post', 1.0), ('Story', 9 / 16), ('Ad', 4 / 5), ('Banner', 16 / 9)];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Spring launch',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.gray900),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, (name, ratio)) in pieces.indexed) ...[
                    if (i > 0) const SizedBox(width: 6),
                    // Each tile at the real aspect it would be produced at.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: ratio,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Tw.orange400, Tw.orange600],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          label(name),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Container(
                height: 6,
                decoration: BoxDecoration(color: c.gray200, borderRadius: BorderRadius.circular(99)),
              ),
              const SizedBox(height: 4),
              FractionallySizedBox(
                widthFactor: 0.6,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(color: c.gray200, borderRadius: BorderRadius.circular(99)),
                ),
              ),
            ],
          ),
        );
      default:
        Widget shot(String name, Widget inner, Decoration bg) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Container(padding: const EdgeInsets.all(8), decoration: bg, child: inner),
              ),
              const SizedBox(height: 4),
              label(name),
            ],
          ),
        );
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // "Before": the product on whatever it was shot against.
                  shot(
                    'Before',
                    Container(
                      decoration: BoxDecoration(
                        color: c.gray400.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    BoxDecoration(color: c.gray200, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(width: 8),
                  shot(
                    'Staged',
                    Container(
                      decoration: BoxDecoration(color: Tw.violet500, borderRadius: BorderRadius.circular(2)),
                    ),
                    BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Tw.violet100, Tw.violet200],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              label('12 products · 24 shots', size: 9),
            ],
          ),
        );
    }
  }
}

/// The browse-everything sheet behind "Browse all" and "Browse skills"
/// (SkillsModal.jsx): Your workspace / Suggested over one catalog. ⚠️ Adding
/// is real and local, so an added skill shows under Your workspace at once.
Future<void> showSkillsSheet(BuildContext context, CopilotStore store) => showCopilotSheet<void>(
  context,
  title: 'Skills',
  fullHeight: true,
  builder: (ctx) => _SkillsSheetBody(store: store),
);

class _SkillsSheetBody extends StatefulWidget {
  const _SkillsSheetBody({required this.store});
  final CopilotStore store;

  @override
  State<_SkillsSheetBody> createState() => _SkillsSheetBodyState();
}

class _SkillsSheetBodyState extends State<_SkillsSheetBody> {
  String _tab = 'Suggested';
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final added = widget.store.addedSkills;
        final term = _query.text.trim().toLowerCase();
        final pool = _tab == 'Your workspace' ? allSkills.where((s) => added.contains(s.slug)) : allSkills;
        final visible = [
          for (final s in pool)
            if (term.isEmpty || s.slug.toLowerCase().contains(term) || s.description.toLowerCase().contains(term)) s,
        ];
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom),
          children: [
            Text('Discover and add skills your copilot can run.', style: TextStyle(fontSize: 13.5, color: c.gray500)),
            const SizedBox(height: 14),
            UnderlineTabs(
              tabs: const ['Your workspace', 'Suggested'],
              value: _tab,
              counts: {'Your workspace': added.length},
              onChanged: (t) => setState(() => _tab = t),
            ),
            const SizedBox(height: 14),
            CopilotSearchField(controller: _query, hint: 'Search skills', onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              // Two different nothings — a search that found nothing, and an
              // empty workspace — so two different sentences.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text(
                  term.isNotEmpty ? 'No skills match your search' : 'No skills added yet — add one from Suggested.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: c.gray500),
                ),
              )
            else
              for (final s in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SkillCard(
                    skill: s,
                    action: IconButton(
                      tooltip: added.contains(s.slug)
                          ? 'Remove /${s.slug} from your workspace'
                          : 'Add /${s.slug} to your workspace',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => widget.store.toggleSkill(s.slug),
                      icon: Icon(
                        added.contains(s.slug) ? LucideIcons.check : LucideIcons.plus,
                        size: 17,
                        color: added.contains(s.slug) ? Tw.emerald600 : c.gray500,
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
