import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../shell/widgets/app_top_bar.dart';
import '../copilot_store.dart';
import '../data/copilot_catalog.dart';
import '../widgets/copilot_widgets.dart';

/// The Copilot pages' tinted page colour: the web's `bg-[#eef1f7]` (a neutral
/// with a hint of the app blue), falling back to the page token in dark mode.
Color copilotPageColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? context.colors.page : const Color(0xFFEEF1F7);

/// /copilot — "Give your Copilot its first task" (port of copilot/page.jsx):
/// the hero with the task composer, then starter ideas by category.
///
/// `?task=` seeds the composer — a seed, not a source: the user edits freely.
class CopilotHomeScreen extends StatefulWidget {
  const CopilotHomeScreen({super.key, this.task});

  final String? task;

  @override
  State<CopilotHomeScreen> createState() => _CopilotHomeScreenState();
}

class _CopilotHomeScreenState extends State<CopilotHomeScreen> {
  late final _task = TextEditingController(text: widget.task ?? '');
  String _category = 'Brand';

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  /// ⚠️ THREE STEPS, in this order: the user names it, the copilot has to exist
  /// before there is anywhere to ask, and the task then rides `?send=` — posted
  /// as an asked message, because the user already pressed send once here.
  Future<void> _submit() async {
    final task = _task.text.trim();
    if (task.isEmpty) return;
    final router = GoRouter.of(context);
    final copilot = await showCreateCopilotSheet(context);
    if (copilot == null) return;
    router.push(
      Uri(
        path: '/copilot/${copilot.id}',
        queryParameters: {'new': '1', 'c': CopilotStore.newConversationId(), 'send': task},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ideas = copilotIdeas[_category] ?? const [];
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Copilot'),
          Expanded(
            child: ColoredBox(
              color: copilotPageColor(context),
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.zero,
                children: [
                  // ── Hero ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 36, 16, 36),
                    child: Column(
                      children: [
                        Text.rich(
                          TextSpan(
                            style: TextStyle(fontSize: 26, height: 1.25, fontWeight: FontWeight.w700, color: c.gray900),
                            children: [
                              const TextSpan(text: 'Give your\n'),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Icon(LucideIcons.bot, size: 26, color: AppColors.blue600),
                                ),
                              ),
                              TextSpan(
                                text: 'Copilot',
                                style: TextStyle(color: AppColors.blue600),
                              ),
                              const TextSpan(text: ' its first task.'),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        // The SAME composer a copilot's own conversation uses.
                        CopilotComposer(controller: _task, onSubmit: _submit),
                        const SizedBox(height: 36),
                        Text('Or start from one of these ideas:', style: TextStyle(fontSize: 12, color: c.gray500)),
                      ],
                    ),
                  ),

                  // ── Starter ideas ──
                  Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border(top: BorderSide(color: c.gray200)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              for (final cat in copilotCategories)
                                InkWell(
                                  onTap: () => setState(() => _category = cat),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
                                    child: Row(
                                      children: [
                                        if (cat == _category) ...[
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: AppColors.blue600,
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Text(
                                          cat,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: cat == _category ? FontWeight.w600 : FontWeight.w400,
                                            color: cat == _category ? c.gray900 : c.gray500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Hairline-divided cards, the web's gap-px grid in one column.
                        Container(
                          decoration: BoxDecoration(
                            border: Border.symmetric(horizontal: BorderSide(color: c.gray200)),
                          ),
                          child: Column(
                            children: [
                              for (final (i, idea) in ideas.indexed)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    border: i == 0 ? null : Border(top: BorderSide(color: c.gray200)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              idea.title,
                                              style: TextStyle(
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w600,
                                                color: c.gray900,
                                              ),
                                            ),
                                          ),
                                          for (final p in idea.platforms)
                                            Padding(padding: const EdgeInsets.only(left: 6), child: PlatformChip(p)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        idea.description,
                                        style: TextStyle(fontSize: 13, height: 1.5, color: c.gray500),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          child: Text(
                            'You can find these ideas anytime inside your Copilot.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: c.gray400),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
