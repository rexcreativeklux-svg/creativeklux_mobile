import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../copilot_store.dart';
import '../data/copilot_catalog.dart';
import '../data/copilot_types.dart';
import '../widgets/copilot_widgets.dart';
import 'copilot_workspace.dart';

/// /copilot/:id/workflows — the standing jobs this copilot can be set up to
/// run (port of [id]/workflows/page.jsx). The cards are THIS copilot's own
/// starters from the shared idea catalog, by its category.
///
/// ⚠️ "Send to chat" SENDS — `?send=`, not `?task=` — in a fresh `?c=`, so it
/// lands as an asked message in a new thread. Sending is not RUNNING: the
/// message asks the copilot to set the workflow up.
class CopilotWorkflowsScreen extends StatelessWidget {
  const CopilotWorkflowsScreen({super.key, required this.id});
  final String id;

  /// Three on the screen; the rest behind "Browse more workflows".
  static const _shown = 3;

  @override
  Widget build(BuildContext context) => CopilotWorkspace(
    id: id,
    section: WorkspaceSection.workflows,
    builder: (context, copilot) {
      final c = context.colors;
      final workflows = (copilotIdeas[copilot.category] ?? const <CopilotIdea>[]).take(_shown);
      void sendToChat(CopilotIdea w) => context.push(
        Uri(
          path: '/copilot/${copilot.id}',
          queryParameters: {'c': CopilotStore.newConversationId(), 'send': w.description},
        ).toString(),
      );

      return ListView(
        padding: EdgeInsets.fromLTRB(16, 28, 16, 28 + MediaQuery.paddingOf(context).bottom),
        children: [
          Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 19, height: 1.3, fontWeight: FontWeight.w700, color: c.gray900),
              children: [
                const TextSpan(text: 'Set up a workflow. Let '),
                TextSpan(
                  text: copilot.name,
                  style: TextStyle(color: AppColors.blue600),
                ),
                const TextSpan(text: ' handle it.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Workflows run automatically in the background on a schedule, or when something changes in your brand.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: c.gray500),
          ),
          const SizedBox(height: 24),
          for (final w in workflows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: WorkflowCard(workflow: w, category: copilot.category, onSend: sendToChat),
            ),
          const SizedBox(height: 12),
          Center(
            child: InkButton(
              label: 'Browse more workflows',
              icon: LucideIcons.sparkles,
              onTap: () => _showSuggestedWorkflows(context, copilot.category, sendToChat),
            ),
          ),
        ],
      );
    },
  );
}

/// One standing job, offered (WorkflowCard.jsx) — used by the screen and the
/// browse sheet so they can't disagree. ⚠️ The icon row is ALWAYS populated:
/// the surface it runs in first, then any platforms it publishes to.
class WorkflowCard extends StatelessWidget {
  const WorkflowCard({super.key, required this.workflow, required this.category, required this.onSend});

  final CopilotIdea workflow;
  final String category;
  final ValueChanged<CopilotIdea> onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            workflow.title,
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.gray900),
          ),
          const SizedBox(height: 6),
          Text(workflow.description, style: TextStyle(fontSize: 13, height: 1.5, color: c.gray500)),
          const SizedBox(height: 14),
          Row(
            children: [
              SurfaceChip(category),
              for (final p in workflow.platforms)
                Padding(padding: const EdgeInsets.only(left: 6), child: PlatformChip(p)),
              const Spacer(),
              GhostButton(label: 'Send to chat', icon: LucideIcons.messageSquare, onTap: () => onSend(workflow)),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Browse more workflows": the whole catalog by product surface, without
/// leaving the copilot (SuggestedWorkflowsModal.jsx). Opens on the copilot's
/// own surface. Sending closes the sheet and opens the chat.
Future<void> _showSuggestedWorkflows(BuildContext context, String defaultCategory, ValueChanged<CopilotIdea> onSend) {
  return showCopilotSheet<void>(
    context,
    title: 'Suggested workflows',
    fullHeight: true,
    builder: (ctx) => _SuggestedBody(
      defaultCategory: defaultCategory,
      onSend: (w) {
        Navigator.pop(ctx);
        onSend(w);
      },
    ),
  );
}

class _SuggestedBody extends StatefulWidget {
  const _SuggestedBody({required this.defaultCategory, required this.onSend});
  final String defaultCategory;
  final ValueChanged<CopilotIdea> onSend;

  @override
  State<_SuggestedBody> createState() => _SuggestedBodyState();
}

class _SuggestedBodyState extends State<_SuggestedBody> {
  late String _category = copilotCategories.contains(widget.defaultCategory)
      ? widget.defaultCategory
      : copilotCategories.first;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        Text(
          'Standing jobs your copilot can take on, by what they work with.',
          style: TextStyle(fontSize: 13.5, color: c.gray500),
        ),
        const SizedBox(height: 14),
        // Segmented tabs, scrolling sideways — six labels don't fit a phone.
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.gray100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.gray200),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final cat in copilotCategories)
                  GestureDetector(
                    onTap: () => setState(() => _category = cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: cat == _category ? c.surface : null,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: cat == _category
                            ? const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))]
                            : null,
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: cat == _category ? FontWeight.w600 : FontWeight.w500,
                          color: cat == _category ? c.gray900 : c.gray500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final w in copilotIdeas[_category] ?? const <CopilotIdea>[])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: WorkflowCard(workflow: w, category: _category, onSend: widget.onSend),
          ),
      ],
    );
  }
}
