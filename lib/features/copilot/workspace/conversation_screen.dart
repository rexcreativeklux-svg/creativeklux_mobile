import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import '../../studio/chat_models.dart' show MiniMarkdown;
import '../copilot_api.dart';
import '../copilot_store.dart';
import '../data/copilot_catalog.dart';
import '../data/copilot_data.dart';
import '../data/copilot_types.dart';
import '../widgets/copilot_widgets.dart';
import '../widgets/read_aloud.dart';
import 'copilot_workspace.dart';

/// /copilot/:id — a copilot's conversation (port of [id]/page.jsx +
/// Conversation.jsx). Full screen, outside the shell: the thread and the
/// keyboard need the room.
///
/// ⚠️ WHICH conversation is on screen comes from `?c=`, and it is the thread's
/// key — a handoff (Send to chat, Activate skill) is an ordinary push, and Back
/// returns to the thread that was open.
///
/// ⚠️ NO `?c=` MEANS "SHOW ME OUR HISTORY": opening a copilot loads everything
/// said to it from the server. Only a `?c=` minted this session opens blank.
///
/// Two handoff params, two intentions:
///   `?task=` a DRAFT (Plugins' Activate skill: `/slug ` waits for what to run it on);
///   `?send=` a MESSAGE, already asked (Workflows' Send to chat, the home create).
/// `?new=1` — just created, so the copilot introduces itself.
class CopilotConversationScreen extends StatelessWidget {
  const CopilotConversationScreen({
    super.key,
    required this.id,
    this.conversationId,
    this.task = '',
    this.send = '',
    this.isNew = false,
  });

  final String id;
  final String? conversationId;
  final String task;
  final String send;
  final bool isNew;

  @override
  Widget build(BuildContext context) => CopilotWorkspace(
    id: id,
    section: WorkspaceSection.conversation,
    builder: (context, copilot) => _Conversation(
      key: ValueKey('${copilot.id}:${conversationId ?? 'latest'}'),
      copilot: copilot,
      conversationId: conversationId,
      initialDraft: task,
      initialMessage: send,
      isNew: isNew,
    ),
  );
}

class _Message {
  _Message({
    required this.id,
    required this.fromUser,
    required this.text,
    required this.at,
    this.pending = false,
    this.error = false,
  });

  final String id;
  final bool fromUser;
  String text;
  final DateTime at;
  bool pending;

  /// The request failed and [text] is the server's own words.
  bool error;
}

/// The name to greet someone by: the first word of their name / username,
/// capitalised; empty drops the name rather than saying "Hey ,".
String _firstName(Map<String, dynamic>? user) {
  final raw = '${user?['name'] ?? ''}'.trim().isNotEmpty ? '${user!['name']}' : '${user?['username'] ?? ''}';
  final first = raw.trim().split(RegExp(r'[\s._@-]+')).first;
  return first.isEmpty ? '' : '${first[0].toUpperCase()}${first.substring(1)}';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
String _time(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

class _Conversation extends StatefulWidget {
  const _Conversation({
    super.key,
    required this.copilot,
    required this.conversationId,
    required this.initialDraft,
    required this.initialMessage,
    required this.isNew,
  });

  final Copilot copilot;
  final String? conversationId;
  final String initialDraft;
  final String initialMessage;
  final bool isNew;

  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  late final _draft = TextEditingController(text: widget.initialDraft);
  final _scroll = ScrollController();
  final _messages = <_Message>[];
  _Message? _intro;

  /// The server's id for this thread, once a reply names one.
  Object? _serverConversation;
  late final bool _wantsHistory =
      widget.initialMessage.isEmpty && !CopilotStore.isSessionConversation(widget.conversationId);
  late bool _loadingHistory = _wantsHistory;
  bool _showChips = true;

  /// Both hero lines picked once per mount, from the hour.
  final _opener = lineForNow(copilotOpeners);
  final _subheading = lineForNow(copilotSubheadings);

  CopilotApi get _api => CopilotStore.of(context).api;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthController>().user;
    // Seeded before the first frame, so a started thread never flashes the
    // empty hero. The intro comes before a pre-sent task: hello, then asked.
    if (widget.isNew) {
      _intro = _Message(
        id: 'intro',
        fromUser: false,
        at: DateTime.now(),
        text: copilotIntro(copilotName: widget.copilot.name, userName: _firstName(user)),
      );
      _messages.add(_intro!);
    }
    if (widget.initialMessage.isNotEmpty) {
      final reply = _turn(widget.initialMessage);
      WidgetsBinding.instance.addPostFrameCallback((_) => _answer(widget.initialMessage, reply));
    }
    if (_wantsHistory) _loadHistory();
  }

  @override
  void dispose() {
    // A message still being read would keep talking after the chat is gone.
    ReadAloud.stop();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The pair one send produces: what was asked, and a pending placeholder.
  _Message _turn(String text) {
    final at = DateTime.now();
    final i = _messages.length;
    _messages.add(_Message(id: 'u-$i', fromUser: true, text: text, at: at));
    final reply = _Message(id: 'a-$i', fromUser: false, text: '', at: at, pending: true);
    _messages.add(reply);
    return reply;
  }

  void _pinToBottom({bool jump = false}) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!_scroll.hasClients) return;
    final end = _scroll.position.maxScrollExtent;
    jump
        ? _scroll.jumpTo(end)
        : _scroll.animateTo(end, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  });

  /// Make the request and settle the placeholder it belongs to — by identity,
  /// so an answer can't land under a later question.
  Future<void> _answer(String text, _Message reply) async {
    try {
      final data = await _api.sendChat(
        message: text,
        copilotId: widget.copilot.id,
        conversationId: _serverConversation,
      );
      // Keep the thread id if the server names one, so the next turn continues it.
      final id = data is Map
          ? (data['conversation_id'] ??
                (data['conversation'] is Map ? data['conversation']['id'] : null) ??
                (data['data'] is Map ? data['data']['conversation_id'] : null))
          : null;
      if (id != null) _serverConversation = id;
      reply.text = replyTextFrom(data);
    } catch (e) {
      reply
        ..text = CopilotFailure.of(e).text
        ..error = true;
    }
    if (!mounted) return;
    setState(() => reply.pending = false);
    _pinToBottom();
  }

  void _send() {
    final text = _draft.text.trim();
    if (text.isEmpty) return;
    late _Message reply;
    setState(() => reply = _turn(text));
    _draft.clear();
    // You sent this, so you get to watch it be answered.
    _pinToBottom();
    _answer(text, reply);
  }

  /// Opening a copilot: load everything said to it. Empty means you've never
  /// talked to it, so the hero (or a new copilot's intro).
  ///
  /// ⚠️ A FAILURE IS SHOWN, NOT SWALLOWED: failing silently into the empty hero
  /// looks exactly like "your history is gone".
  Future<void> _loadHistory() async {
    try {
      final rows = await _api.fetchMessages(widget.copilot.id);
      if (!mounted) return;
      if (rows.isEmpty && _intro != null) return;
      final last = rows.lastOrNull;
      if (last?['conversation_id'] != null) _serverConversation = last!['conversation_id'];
      final loaded = <_Message>[];
      for (final (i, row) in rows.indexed) {
        // ⚠️ Anything not explicitly the user is the copilot — the ambiguous case
        // falls to the side that can't put words in the user's mouth.
        final fromUser = row['role'] == 'user' || row['sender'] == 'user';
        final text = '${row['content'] ?? row['text'] ?? row['message'] ?? ''}';
        if (text.isEmpty || text == 'null') continue;
        loaded.add(
          _Message(
            id: 's-${row['id'] ?? i}',
            fromUser: fromUser,
            text: text,
            at: (DateTime.tryParse('${row['created_at'] ?? row['at'] ?? ''}') ?? DateTime.now()).toLocal(),
          ),
        );
      }
      setState(() {
        _messages
          ..clear()
          ..addAll(loaded);
      });
      _pinToBottom(jump: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll([
            ?_intro,
            _Message(
              id: 'history-error',
              fromUser: false,
              at: DateTime.now(),
              error: true,
              text: CopilotFailure.of(e).text,
            ),
          ]);
      });
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Widget _composer({required bool started}) => CopilotComposer(
    controller: _draft,
    onSubmit: _send,
    minLines: started ? 1 : 3,
    placeholder: 'Tell ${widget.copilot.name} what you want to do',
    sendLabel: 'Send message',
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final started = _messages.isNotEmpty;

    // ⚠️ Checked BEFORE the empty state: reopening a thread must not greet you
    // as if it were brand new for the length of the request.
    if (_loadingHistory && !started) {
      return Center(
        child: Text('Loading conversation…', style: TextStyle(fontSize: 12, color: c.gray400)),
      );
    }

    // ── Empty thread ──
    if (!started) {
      final name = _firstName(context.read<AuthController>().user);
      return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: max(0, box.maxHeight - 40)),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ONE blue phrase in an otherwise gray-900 line — a highlight.
                    Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 25, height: 1.25, fontWeight: FontWeight.w700, color: c.gray900),
                        children: [
                          TextSpan(text: name.isNotEmpty ? 'Hey $name,\n' : 'Hey,\n'),
                          TextSpan(text: '${_opener.lead} '),
                          TextSpan(
                            text: _opener.accent,
                            style: TextStyle(color: AppColors.blue600),
                          ),
                          TextSpan(text: _opener.tail),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w500, color: c.gray900),
                        children: [
                          TextSpan(text: '${_subheading.lead} '),
                          TextSpan(
                            text: _subheading.accent,
                            style: TextStyle(color: AppColors.blue600),
                          ),
                          TextSpan(text: _subheading.tail),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    _composer(started: false),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // ── Started ──
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            children: [
              // Date divider — hairline, date, hairline.
              Row(
                children: [
                  Expanded(child: Divider(color: c.gray200)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(_date(_messages.first.at), style: TextStyle(fontSize: 12, color: c.gray500)),
                  ),
                  Expanded(child: Divider(color: c.gray200)),
                ],
              ),
              for (final m in _messages)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: _ChatMessage(message: m, copilot: widget.copilot),
                ),
            ],
          ),
        ),
        // Docked: the thread scrolls under it instead of pushing it off screen.
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              children: [
                if (_showChips)
                  _SuggestionChips(
                    ideas: copilotIdeas[widget.copilot.category] ?? const [],
                    onPick: (idea) {
                      _draft.text = idea.description;
                      _draft.selection = TextSelection.collapsed(offset: _draft.text.length);
                    },
                    onDismiss: () => setState(() => _showChips = false),
                  ),
                _composer(started: true),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One turn (ChatMessage.jsx). The copilot speaks as PAGE TEXT, not in a
/// bubble — its answers are the screen's content; the user's lines get a
/// bubble so "what I asked" separates from "what it said".
class _ChatMessage extends StatelessWidget {
  const _ChatMessage({required this.message, required this.copilot});
  final _Message message;
  final Copilot copilot;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (message.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: AppColors.blue600, borderRadius: BorderRadius.circular(16)),
            // Plain, not Markdown — the user's * and _ are theirs.
            child: Text(message.text, style: const TextStyle(fontSize: 14.5, height: 1.45, color: Colors.white)),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CopilotAvatar(copilot: copilot, size: 20),
            const SizedBox(width: 8),
            Text(
              copilot.name,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray900),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (message.pending)
          // Three dots rather than a spinner: this reads as someone about to speak.
          _Dots(color: c.gray300)
        else if (message.error)
          // ⚠️ A FAILURE IS NOT THE COPILOT SPEAKING. The box, icon and mono type
          // say this came from the server, worded exactly as the server put it.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.redTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.red600.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(LucideIcons.triangleAlert, size: 14, color: Tw.red700),
                    SizedBox(width: 6),
                    Text(
                      'Request failed',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Tw.red700),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  message.text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                    color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFFA2A2) : Tw.red900,
                  ),
                ),
              ],
            ),
          )
        else
          MiniMarkdown(
            message.text,
            style: TextStyle(fontSize: 15, height: 1.55, color: c.gray900),
            accent: c.gray900,
          ),
        // No time / copy / read-aloud while pending — there is nothing yet.
        if (!message.pending)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Text(_time(message.at), style: TextStyle(fontSize: 11, color: c.gray400)),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Copy message',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: message.text));
                    Toast.success('Copied');
                  },
                  icon: Icon(LucideIcons.copy, size: 14, color: c.gray400),
                ),
                ValueListenableBuilder<String?>(
                  valueListenable: ReadAloud.speaking,
                  builder: (context, speaking, _) {
                    final on = speaking == message.text;
                    return IconButton(
                      tooltip: on ? 'Stop reading' : 'Read message aloud',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => ReadAloud.toggle(message.text),
                      icon: Icon(
                        on ? LucideIcons.squareStop : LucideIcons.volume2,
                        size: 14,
                        color: on ? AppColors.blue600 : c.gray400,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The starters above the composer (SuggestionChips.jsx) — THIS copilot's own
/// ideas, by category. ↻ cycles a window of three through them and wraps.
class _SuggestionChips extends StatefulWidget {
  const _SuggestionChips({required this.ideas, required this.onPick, required this.onDismiss});
  final List<CopilotIdea> ideas;
  final ValueChanged<CopilotIdea> onPick;
  final VoidCallback onDismiss;

  @override
  State<_SuggestionChips> createState() => _SuggestionChipsState();
}

class _SuggestionChipsState extends State<_SuggestionChips> {
  static const _window = 3;
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ideas = widget.ideas;
    if (ideas.isEmpty) return const SizedBox.shrink();
    final shown = [for (var i = 0; i < min(_window, ideas.length); i++) ideas[(_offset + i) % ideas.length]];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final idea in shown)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Material(
                        color: c.surface,
                        shape: StadiumBorder(side: BorderSide(color: c.gray200)),
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: () => widget.onPick(idea),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Row(
                              children: [
                                for (final p in idea.platforms.take(2))
                                  Padding(padding: const EdgeInsets.only(right: 6), child: PlatformChip(p, size: 18)),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 200),
                                  child: Text(
                                    idea.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.gray900),
                                  ),
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
          ),
          IconButton(
            tooltip: 'Show other suggestions',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _offset = (_offset + _window) % ideas.length),
            icon: Icon(LucideIcons.refreshCw, size: 15, color: c.gray500),
          ),
          IconButton(
            tooltip: 'Hide suggestions',
            visualDensity: VisualDensity.compact,
            onPressed: widget.onDismiss,
            icon: Icon(LucideIcons.x, size: 15, color: c.gray500),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatefulWidget {
  const _Dots({required this.color});
  final Color color;

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, _) => Row(
      children: [
        // Pulsing, staggered 150ms apart like the web's animate-pulse dots.
        for (var i = 0; i < 3; i++)
          Opacity(
            opacity: 0.35 + 0.65 * (0.5 + 0.5 * cos(2 * pi * (_anim.value - i * 0.125))),
            child: Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
            ),
          ),
      ],
    ),
  );
}
