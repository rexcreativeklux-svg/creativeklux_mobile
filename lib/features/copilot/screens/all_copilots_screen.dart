import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../shell/widgets/app_top_bar.dart';
import '../copilot_store.dart';
import '../widgets/copilot_card.dart';
import '../widgets/copilot_widgets.dart';
import 'copilot_home_screen.dart' show copilotPageColor;

/// How the list can be ordered. ⚠️ On the SERVER's timestamps, not on the
/// rendered "about 2 hours ago"; a row with no timestamp sorts last.
const _sorts = <String, String>{'edited': 'Last edited', 'created': 'Date created', 'az': 'Name A–Z', 'za': 'Name Z–A'};

int _byTime(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

/// /copilot/all — the catalog (port of copilot/all/page.jsx): Create, search,
/// sort, a favourites filter, a grid/list toggle and the copilots themselves.
///
/// ⚠️ No folders and no "Created by me" — the web removed both (no endpoint /
/// no creator on the row) rather than leave them saying "coming soon".
class AllCopilotsScreen extends StatefulWidget {
  const AllCopilotsScreen({super.key});

  @override
  State<AllCopilotsScreen> createState() => _AllCopilotsScreenState();
}

class _AllCopilotsScreenState extends State<AllCopilotsScreen> {
  final _query = TextEditingController();
  bool _grid = true;
  bool _favoritesOnly = false;
  String _sort = 'edited';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final router = GoRouter.of(context);
    final copilot = await showCreateCopilotSheet(context);
    if (copilot != null) router.push('/copilot/${copilot.id}?new=1');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final store = CopilotStore.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'All Copilots', showBack: true),
          Expanded(
            child: ColoredBox(
              color: copilotPageColor(context),
              child: ListenableBuilder(
                listenable: store,
                builder: (context, _) {
                  final term = _query.text.trim().toLowerCase();
                  final copilots = store.items;
                  final visible = [
                    for (final cp in copilots)
                      if ((!_favoritesOnly || cp.favorite) &&
                          (term.isEmpty ||
                              cp.name.toLowerCase().contains(term) ||
                              cp.description.toLowerCase().contains(term)))
                        cp,
                  ];
                  // ⚠️ Sorted on a COPY — the store's list is shared.
                  visible.sort(
                    (a, b) => switch (_sort) {
                      'created' => _byTime(a.createdAt, b.createdAt),
                      'az' => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                      'za' => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
                      _ => _byTime(a.updatedAt, b.updatedAt),
                    },
                  );
                  // An empty catalog and an over-filtered one are different problems.
                  final filtered = copilots.isNotEmpty && visible.isEmpty;

                  return RefreshIndicator(
                    onRefresh: store.refresh,
                    child: ListView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                'Create, organize, and manage all copilots in your workspace.',
                                style: TextStyle(fontSize: 13.5, height: 1.4, color: c.gray500),
                              ),
                            ),
                            const SizedBox(width: 12),
                            InkButton(label: 'Create copilot', icon: LucideIcons.plus, onTap: _create),
                          ],
                        ),
                        const SizedBox(height: 16),
                        CopilotSearchField(
                          controller: _query,
                          hint: 'Search copilots',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Sorting needs no endpoint — the whole catalog is here.
                            Flexible(
                              child: DropdownTrigger(
                                label: _sorts[_sort]!,
                                icon: LucideIcons.arrowUpDown,
                                onTap: () => showChoiceSheet(
                                  context,
                                  heading: 'Sort by',
                                  items: [
                                    for (final e in _sorts.entries)
                                      ChoiceItem(
                                        e.value,
                                        selected: e.key == _sort,
                                        onTap: () => setState(() => _sort = e.key),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _ToggleBox(
                              tooltip: 'Show favorites only',
                              active: _favoritesOnly,
                              activeColor: AppColors.amber500,
                              onTap: () => setState(() => _favoritesOnly = !_favoritesOnly),
                              icon: _favoritesOnly ? Icons.star_rounded : LucideIcons.star,
                            ),
                            const SizedBox(width: 8),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: c.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: c.gray300),
                              ),
                              child: Row(
                                children: [
                                  _ViewButton(
                                    icon: LucideIcons.layoutGrid,
                                    label: 'Grid view',
                                    on: _grid,
                                    onTap: () => setState(() => _grid = true),
                                  ),
                                  _ViewButton(
                                    icon: LucideIcons.list,
                                    label: 'List view',
                                    on: !_grid,
                                    onTap: () => setState(() => _grid = false),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // ⚠️ FOUR STATES, not interchangeable: loading, failed,
                        // nothing matches, and genuinely none.
                        if (store.loading && copilots.isEmpty)
                          const StateBlock.loading('Loading your copilots…')
                        else if (store.error != null && copilots.isEmpty)
                          StateBlock.error(
                            "Couldn't load your copilots",
                            store.error,
                            action: InkButton(label: 'Try again', onTap: store.refresh),
                          )
                        else if (visible.isEmpty)
                          StateBlock.empty(
                            filtered ? 'No copilots found' : 'No copilots yet',
                            filtered
                                ? 'No copilots found matching your criteria.'
                                : 'Create your first copilot to see it here.',
                          )
                        else if (_grid)
                          for (final cp in visible)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: CopilotCard(key: ValueKey('g${cp.id}'), copilot: cp),
                            )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: c.gray200),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                for (final (i, cp) in visible.indexed) ...[
                                  if (i > 0) Divider(height: 1, color: c.gray200),
                                  CopilotCard(key: ValueKey('l${cp.id}'), copilot: cp, grid: false),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleBox extends StatelessWidget {
  const _ToggleBox({
    required this.tooltip,
    required this.active,
    required this.activeColor,
    required this.onTap,
    required this.icon,
  });

  final String tooltip;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active ? activeColor.withValues(alpha: 0.1) : c.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? activeColor.withValues(alpha: 0.5) : c.gray300),
          ),
          child: Icon(icon, size: active ? 19 : 16, color: active ? activeColor : c.gray500),
        ),
      ),
    );
  }
}

class _ViewButton extends StatelessWidget {
  const _ViewButton({required this.icon, required this.label, required this.on, required this.onTap});
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: on ? c.gray200 : null, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: on ? c.gray900 : c.gray500),
        ),
      ),
    );
  }
}
