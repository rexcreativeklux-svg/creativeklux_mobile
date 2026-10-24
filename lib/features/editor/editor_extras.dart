import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'design_editor_controller.dart';

/// The editor's extras: Collaborators (`collaborators/*`), Notes
/// (`notes/EditorNotes.jsx`) and the Timer (`timer/EditorTimer.jsx`).

// ── Collaborators ─────────────────────────────────────────────────────────────

const _avatarColors = [
  Color(0xFF2563EB),
  Color(0xFF7C3AED),
  Color(0xFF059669),
  Color(0xFFD97706),
  Color(0xFFE11D48),
  Color(0xFF0891B2),
];

/// Same person, same colour, on every screen (web `avatarColor`).
Color avatarColor(Map<String, dynamic> person) {
  final key = '${person['email'] ?? person['name'] ?? person['id'] ?? ''}';
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _avatarColors[hash % _avatarColors.length];
}

String initialsOf(Map<String, dynamic> person) {
  final name = '${person['name'] ?? ''}'.trim();
  if (name.isNotEmpty) {
    final parts = name.split(RegExp(r'\s+'));
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }
  final email = '${person['email'] ?? '?'}';
  return email.isEmpty ? '?' : email[0].toUpperCase();
}

/// "Everyone on your team can open this design" — the team is the access
/// list. `GET /teams` → `{teams: [...]}`, `POST /teams {email}` invites,
/// `DELETE /teams/{id}` removes.
Future<void> showCollaboratorsSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: context.colors.surface.withValues(alpha: 1),
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (_) => const _Collaborators(),
);

class _Collaborators extends StatefulWidget {
  const _Collaborators();

  @override
  State<_Collaborators> createState() => _CollaboratorsState();
}

class _CollaboratorsState extends State<_Collaborators> {
  final _email = TextEditingController();
  List<Map<String, dynamic>>? _members;
  bool _sending = false;
  Object? _removing;

  AuthController get _auth => context.read<AuthController>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await _auth.api.get('/teams');
    if (!mounted) return;
    final list = res.body['teams'];
    setState(() => _members = [if (list is List) ...list.whereType<Map>().map(Map<String, dynamic>.from)]);
  }

  Future<void> _invite() async {
    final value = _email.text.trim();
    if (!value.contains('@')) {
      Toast.error('Enter an email address.');
      return;
    }
    setState(() => _sending = true);
    final res = await _auth.api.post('/teams', body: {'email': value});
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.ok) {
      _email.clear();
      Toast.success('Invite sent to $value');
      _load();
    } else {
      Toast.error('${res.body['error'] ?? (res.message.isNotEmpty ? res.message : 'Could not send that invite')}');
    }
  }

  Future<void> _remove(Map<String, dynamic> m) async {
    setState(() => _removing = m['id']);
    final res = await _auth.api.delete('/teams/${m['id']}');
    if (!mounted) return;
    setState(() => _removing = null);
    if (res.ok) {
      Toast.success('Removed');
      _load();
    } else {
      Toast.error(res.message.isNotEmpty ? res.message : 'Could not remove them');
    }
  }

  Widget _row(Map<String, dynamic> person, String subtitle, {bool muted = false, bool removable = true}) {
    final col = context.colors;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: muted ? col.gray300 : avatarColor(person),
        child: Text(
          initialsOf(person),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
      title: Text(
        '${person['name'] ?? person['email'] ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13.5, color: muted ? col.gray500 : col.gray900),
      ),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 11.5, color: col.gray400)),
      trailing: !removable
          ? null
          : _removing == person['id']
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : IconButton(
              tooltip: 'Remove',
              icon: Icon(LucideIcons.trash2, size: 16, color: col.gray400),
              onPressed: () => _remove(person),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    final me = context.watch<AuthController>().user;
    final members = _members;
    final accepted = members?.where((m) => m['status'] != 'pending').toList() ?? const [];
    final pending = members?.where((m) => m['status'] == 'pending').toList() ?? const [];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                'Collaborators',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: col.gray900),
              ),
              // Said plainly, because a row of faces invites the other reading.
              subtitle: Text(
                'Everyone on your team can open this design.',
                style: TextStyle(fontSize: 11.5, color: col.gray400),
              ),
              trailing: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x, size: 18)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'name@company.com',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onSubmitted: (_) => _invite(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _invite,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.blue600),
                    child: _sending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Invite'),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: col.gray100),
            Flexible(
              child: members == null
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        if (me != null) _row(me, 'You', removable: false),
                        for (final m in accepted) _row(m, '${m['role'] ?? 'Member'}'),
                        if (pending.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              'Pending invites',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: col.gray400),
                            ),
                          ),
                          for (final m in pending) _row(m, 'Hasn’t accepted yet', muted: true),
                        ],
                        if (accepted.isEmpty && pending.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'It’s just you so far. Invite someone above.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12.5, color: col.gray400),
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

// ── Notes ─────────────────────────────────────────────────────────────────────

/// Feedback and to-dos that shouldn't end up on the canvas. Saved inside the
/// design's canvas JSON — visible to anyone who can open it.
Future<void> showNotesSheet(BuildContext context, DesignEditorController c) {
  final ctrl = TextEditingController(text: c.notes);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.colors.surface.withValues(alpha: 1),
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) {
      final col = ctx.colors;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.notebookPen, size: 16, color: col.gray400),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notes',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: col.gray800),
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(LucideIcons.x, size: 18)),
              ],
            ),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 6,
              maxLines: 12,
              onChanged: c.setNotes,
              decoration: InputDecoration(
                hintText: 'Feedback, to-dos, anything that shouldn’t end up on the canvas…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Saved with the design. Visible to anyone who can open it.',
              style: TextStyle(fontSize: 11, color: col.gray400),
            ),
          ],
        ),
      );
    },
  ).whenComplete(ctrl.dispose);
}

// ── Timer ─────────────────────────────────────────────────────────────────────

/// A floating countdown for timed work sessions (EditorTimer.jsx). Time is
/// measured against a deadline rather than counted down by ticks, so a busy
/// frame can't make it drift. At zero it plays the system alert sound and
/// vibrates — the web's synthesised tones need a sound package the app doesn't
/// have.
class EditorTimer extends StatefulWidget {
  const EditorTimer({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  State<EditorTimer> createState() => _EditorTimerState();
}

class _EditorTimerState extends State<EditorTimer> {
  static const _min = 1, _max = 180;
  int _total = 5 * 60;
  double _remaining = 5 * 60;
  DateTime? _deadline;
  Timer? _tick;

  bool get _running => _deadline != null;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _start() {
    if (_remaining <= 0) _remaining = _total.toDouble();
    _deadline = DateTime.now().add(Duration(milliseconds: (_remaining * 1000).round()));
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final left = _deadline!.difference(DateTime.now()).inMilliseconds / 1000;
      if (left <= 0) {
        _tick?.cancel();
        setState(() {
          _remaining = 0;
          _deadline = null;
        });
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.heavyImpact();
      } else {
        setState(() => _remaining = left);
      }
    });
    setState(() {});
  }

  void _pause() {
    _tick?.cancel();
    setState(() => _deadline = null);
  }

  void _setMinutes(int m) {
    final v = m.clamp(_min, _max);
    _pause();
    setState(() {
      _total = v * 60;
      _remaining = _total.toDouble();
    });
  }

  String _mmss(double s) {
    final t = math.max(0, s.ceil());
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    final finished = _remaining <= 0;
    final progress = _total > 0 ? (_remaining / _total).clamp(0.0, 1.0) : 0.0;
    final minutes = (_total / 60).round();
    return Material(
      elevation: 8,
      color: col.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 6,
                    backgroundColor: col.gray200,
                    color: finished ? AppColors.red500 : AppColors.blue600,
                  ),
                  Center(
                    child: Text(
                      _mmss(_remaining),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: finished ? AppColors.red600 : col.gray800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _running ? null : () => _setMinutes(minutes - 1),
                  icon: const Icon(LucideIcons.minus, size: 15),
                ),
                Text('$minutes min', style: TextStyle(fontSize: 11.5, color: col.gray500)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _running ? null : () => _setMinutes(minutes + 1),
                  icon: const Icon(LucideIcons.plus, size: 15),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filled(
                  onPressed: _running ? _pause : _start,
                  style: IconButton.styleFrom(backgroundColor: AppColors.blue600),
                  icon: Icon(_running ? LucideIcons.pause : LucideIcons.play, size: 16),
                ),
                IconButton(
                  tooltip: 'Reset',
                  onPressed: () {
                    _pause();
                    setState(() => _remaining = _total.toDouble());
                  },
                  icon: const Icon(LucideIcons.rotateCcw, size: 16),
                ),
                IconButton(tooltip: 'Close', onPressed: widget.onClose, icon: const Icon(LucideIcons.x, size: 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
