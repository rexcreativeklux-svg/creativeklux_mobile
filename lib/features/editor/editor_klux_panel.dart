import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import 'design_editor_controller.dart';

/// Klux AI — port of the web's `panels/klux/*` (KluxAiPanel, useKluxAi,
/// kluxActions, KluxMessageList, KluxComposer).
///
/// One endpoint: `POST /creatives/ai-redesign {prompt, canvas}` with the live
/// design serialised the way it's saved. A reply carrying `canvas: {canvas,
/// elements}` replaces the page (undoable, then autosaved like any edit).
class KluxAiPanel extends StatefulWidget {
  const KluxAiPanel({super.key, required this.c, required this.api, this.seedRedesign = false, this.onSeedUsed});

  final DesignEditorController c;
  final ApiClient api;

  /// "Edit with AI" lands the user in a redesign that's already running.
  final bool seedRedesign;
  final VoidCallback? onSeedUsed;

  @override
  State<KluxAiPanel> createState() => _KluxAiPanelState();
}

/// Quick-action chips (kluxActions.js) — each just sends its prompt.
const _actions = [
  (
    LucideIcons.sparkles,
    'Redesign this page',
    'Redesign this page with a fresh, modern look while keeping the same content',
  ),
  (LucideIcons.imagePlus, 'Add background', 'Add a background that fits this design'),
  (LucideIcons.wand, 'Change style', 'Change the overall style of this design'),
];

/// The conversation survives closing and reopening the panel, like the web's
/// (where the hook lives as long as the editor).
final _conversations = <int, List<(bool, String)>>{};

class _KluxAiPanelState extends State<KluxAiPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final List<(bool fromUser, String text)> _messages = _conversations.putIfAbsent(widget.c.designId, () => []);
  bool _working = false;
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    if (widget.seedRedesign) {
      // Spend the seed before the (async) turn starts, so reopening the panel
      // doesn't fire the same redesign again.
      widget.onSeedUsed?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(_actions.first.$3));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  });

  void _push(bool fromUser, String text) {
    if (!mounted) return;
    setState(() => _messages.add((fromUser, text)));
    _scrollToEnd();
  }

  Future<void> _send([String? preset]) async {
    final prompt = (preset ?? _input.text).trim();
    if (prompt.isEmpty || _working) return;
    _input.clear();
    _push(true, prompt);
    setState(() => _working = true);
    final cancel = _cancel = CancelToken();
    try {
      final c = widget.c;
      final res = await widget.api.post(
        '/creatives/ai-redesign',
        body: {
          'prompt': prompt,
          'canvas': jsonEncode({'canvas': c.canvas, 'elements': c.elements}),
        },
        timeout: const Duration(minutes: 4),
        cancel: cancel,
      );
      if (cancel.isCancelled) {
        _push(false, 'Stopped.');
      } else if (!res.ok) {
        _push(false, res.message.isNotEmpty ? res.message : 'Klux AI ran into a problem. Try again.');
      } else {
        final body = res.body;
        final reply = '${body['reply'] ?? body['message'] ?? ''}'.trim();
        // Response: {name, canvas: {canvas, elements}} — the inner object IS
        // the design.
        final design = body['canvas'] is Map ? body['canvas'] as Map : null;
        if (design != null && design['elements'] is List) {
          c.replaceDesign(
            design['canvas'] is Map ? Map<String, dynamic>.from(design['canvas'] as Map) : c.canvas,
            design['elements'] as List,
          );
          _push(false, reply.isNotEmpty ? reply : 'Done — I’ve updated your design.');
        } else {
          _push(false, reply.isNotEmpty ? reply : 'Done.');
        }
      }
    } catch (e) {
      Toast.error('Klux AI ran into a problem. Try again.');
    } finally {
      _cancel = null;
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    final started = _messages.isNotEmpty || _working;
    return Column(
      children: [
        Expanded(
          child: started
              ? ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final (fromUser, text) in _messages)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: fromUser
                            ? Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  constraints: const BoxConstraints(maxWidth: 280),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.blue600,
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(16),
                                      bottomLeft: Radius.circular(16),
                                      bottomRight: Radius.circular(16),
                                      topRight: Radius.circular(4),
                                    ),
                                  ),
                                  child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                                ),
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const _KluxAvatar(),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        text,
                                        style: TextStyle(fontSize: 13.5, height: 1.45, color: col.gray700),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    if (_working)
                      Row(
                        children: [
                          _KluxAvatar(spinning: true),
                          SizedBox(width: 8),
                          Text(
                            'Preparing everything…',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.blue600),
                          ),
                        ],
                      ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    Text(
                      'What shall we do with this design?',
                      style: TextStyle(
                        fontSize: 22,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: AppColors.blue600,
                      ),
                    ),
                    const SizedBox(height: 28),
                    for (final (icon, label, prompt) in _actions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: col.surface,
                          shape: StadiumBorder(side: BorderSide(color: col.gray200)),
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: () => _send(prompt),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(color: AppColors.blue600, shape: BoxShape.circle),
                                    child: Icon(icon, size: 14, color: Colors.white),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    label,
                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: col.gray700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: col.gray100)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Describe your idea…',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _working ? () => _cancel?.cancel() : _send,
                style: IconButton.styleFrom(backgroundColor: AppColors.blue600),
                tooltip: _working ? 'Stop' : 'Send',
                icon: Icon(_working ? LucideIcons.square : LucideIcons.arrowUp, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KluxAvatar extends StatefulWidget {
  const _KluxAvatar({this.spinning = false});
  final bool spinning;

  @override
  State<_KluxAvatar> createState() => _KluxAvatarState();
}

class _KluxAvatarState extends State<_KluxAvatar> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _spin.repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(color: context.colors.blueTint, shape: BoxShape.circle),
    child: RotationTransition(turns: _spin, child: Image.asset('assets/images/logo.png')),
  );
}
