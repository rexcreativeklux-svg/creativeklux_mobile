import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../copilot_store.dart';
import 'copilot_widgets.dart';

/// One copilot, as a tile or as a row (CopilotCard.jsx). Both views are the
/// same widget because they carry the same behaviour: the body opens it, the
/// star favourites it, ⋯ opens the shared action menu, and Rename edits the
/// title in place (useInlineRename.js).
///
/// There is no hover on a phone, so the star is always visible (the web's
/// below-`lg` rule) and stays lit once favourited.
class CopilotCard extends StatefulWidget {
  const CopilotCard({super.key, required this.copilot, this.grid = true});

  final Copilot copilot;
  final bool grid;

  @override
  State<CopilotCard> createState() => _CopilotCardState();
}

class _CopilotCardState extends State<CopilotCard> {
  bool _renaming = false;
  bool _saving = false;
  final _draft = TextEditingController();
  final _focus = FocusNode();

  Copilot get copilot => widget.copilot;

  @override
  void initState() {
    super.initState();
    // Leaving the field is what saves, as blur does on the web.
    _focus.addListener(() {
      if (!_focus.hasFocus && _renaming) _commit();
    });
  }

  @override
  void dispose() {
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startRename() {
    setState(() {
      _renaming = true;
      _draft.text = copilot.name;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  /// Trimmed; an empty box or an unchanged name just closes the editor —
  /// neither is worth a request.
  Future<void> _commit() async {
    if (_saving) return;
    final name = _draft.text.trim();
    if (name.isEmpty || name == copilot.name) {
      setState(() => _renaming = false);
      return;
    }
    setState(() => _saving = true);
    try {
      await CopilotStore.of(context).update(copilot.id, {'name': name});
    } catch (e) {
      reportFailure(e, "Couldn't rename this copilot"); // the store already rolled back
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _renaming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final grid = widget.grid;

    final body = Row(
      children: [
        CopilotAvatar(copilot: copilot, size: grid ? 48 : 36),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_renaming)
                TextField(
                  controller: _draft,
                  focusNode: _focus,
                  enabled: !_saving,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _commit(),
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.gray900),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AppColors.blue500),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AppColors.blue500),
                    ),
                  ),
                )
              else
                Text(
                  copilot.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.gray900),
                ),
              // The row has room for the description; the tile shows the edit time alone.
              if (!grid && copilot.description.isNotEmpty)
                Text(
                  copilot.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: c.gray500),
                ),
              Padding(
                padding: EdgeInsets.only(top: grid ? 2 : 1),
                child: Text(
                  'Last edited ${copilot.editedAgo}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: grid ? 12.5 : 11, color: c.gray500),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Material(
      color: grid ? c.surface : Colors.transparent,
      shape: grid
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: c.gray200),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // While renaming the body is not the open target — a tap meant for the
        // field would open the copilot instead.
        onTap: _renaming ? null : () => context.push('/copilot/${copilot.id}'),
        child: Padding(
          padding: grid ? const EdgeInsets.fromLTRB(16, 16, 6, 16) : const EdgeInsets.fromLTRB(16, 12, 6, 12),
          child: Row(
            children: [
              Expanded(child: body),
              IconButton(
                tooltip: copilot.favorite
                    ? 'Remove ${copilot.name} from favorites'
                    : 'Add ${copilot.name} to favorites',
                onPressed: () => toggleFavoriteWithToast(context, copilot),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  copilot.favorite ? Icons.star_rounded : LucideIcons.star,
                  size: copilot.favorite ? 19 : 16,
                  color: copilot.favorite ? AppColors.amber500 : c.gray500,
                ),
              ),
              IconButton(
                tooltip: '${copilot.name} actions',
                onPressed: () => showCopilotActions(context, copilot, onRename: _startRename),
                visualDensity: VisualDensity.compact,
                icon: Icon(LucideIcons.ellipsis, size: 17, color: c.gray500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The success toast waits for the server — the star flips instantly
/// (optimistic) but "added to favorites" must not show if it rolls back.
Future<void> toggleFavoriteWithToast(BuildContext context, Copilot copilot) async {
  try {
    await CopilotStore.of(context).toggleFavorite(copilot.id);
    Toast.success(copilot.favorite ? '${copilot.name} removed from favorites' : '${copilot.name} added to favorites');
  } catch (e) {
    reportFailure(e, "Couldn't update favorites");
  }
}

/// The ⋯ menu for ONE copilot, in one place (copilotActions.js). The success
/// toasts wait for the server; sharing and settings still need endpoints and
/// say so.
Future<void> showCopilotActions(BuildContext context, Copilot copilot, {VoidCallback? onRename}) {
  final store = CopilotStore.of(context);
  Future<void> run(Future<void> Function() write, String done, String failed) async {
    try {
      await write();
      Toast.success(done);
    } catch (e) {
      reportFailure(e, failed);
    }
  }

  return showChoiceSheet(
    context,
    items: [
      ChoiceItem(
        copilot.favorite ? 'Remove from favorites' : 'Add to favorites',
        icon: copilot.favorite ? LucideIcons.starOff : LucideIcons.star,
        onTap: () => toggleFavoriteWithToast(context, copilot),
      ),
      ChoiceItem('Share', icon: LucideIcons.share2, onTap: () => notifyPending('Sharing')),
      null,
      ChoiceItem('Rename', icon: LucideIcons.pencil, onTap: onRename ?? () => notifyPending('Renaming')),
      ChoiceItem(
        'Clone copilot',
        icon: LucideIcons.copyPlus,
        onTap: () => run(() => store.clone(copilot.id), '${copilot.name} cloned', "Couldn't clone this copilot"),
      ),
      ChoiceItem(
        'Copy copilot ID',
        icon: LucideIcons.hash,
        onTap: () {
          Clipboard.setData(ClipboardData(text: copilot.id));
          Toast.success('Copilot ID copied');
        },
      ),
      ChoiceItem('Copilot settings', icon: LucideIcons.settings, onTap: () => notifyPending('Copilot settings')),
      null,
      ChoiceItem(
        'Delete',
        icon: LucideIcons.trash2,
        danger: true,
        onTap: () => run(() => store.remove(copilot.id), '${copilot.name} deleted', "Couldn't delete this copilot"),
      ),
    ],
  );
}
