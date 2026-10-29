import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/api/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/app_input.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'settings_api.dart';
import 'settings_widgets.dart';

/// Port of `(settings)/resell/page.jsx` — invite resell partners by email and
/// manage them. `GET /resells`, `POST /resells {email}`, `DELETE /resells/{id}`
/// are all real.
///
/// The web's list/card toggle collapses to cards: its table already stacks
/// each row into a card below `md` (ResponsiveTable), so on a phone both views
/// were cards anyway. The NotificationModal popups are toasts.
class ResellScreen extends StatefulWidget {
  const ResellScreen({super.key});

  @override
  State<ResellScreen> createState() => _ResellScreenState();
}

class _ResellScreenState extends State<ResellScreen> {
  late final SettingsApi _api = SettingsApi(context.read<AuthController>().api);
  final _email = TextEditingController();

  List<Map<String, dynamic>> _members = const [];
  bool _loading = true;
  bool _inviting = false;
  String _search = '';
  int _perPage = 10;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _email.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _api.resells();
      if (mounted) setState(() => _members = list);
    } catch (e) {
      Toast.error('Error', description: 'Failed to load resell accounts.');
      if (mounted) setState(() => _members = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _invite() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      Toast.error('Invalid Email', description: 'Please enter a valid email address.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _inviting = true);
    try {
      await _api.createResell(email);
      Toast.success('Success!', description: '$email has been invited to resell.');
      _email.clear();
      await _load();
    } catch (e) {
      Toast.error('Failed', description: toUserMessage(e, 'Could not send invitation.'));
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> m) async {
    await showConfirmDialog(
      context,
      title: 'Remove resell account?',
      message: 'Remove ${m['email'] ?? 'this account'} from resell accounts?',
      confirmLabel: 'Remove',
      danger: true,
      onConfirm: () async {
        try {
          await _api.deleteResell(m['id'] as Object);
          if (mounted) setState(() => _members = _members.where((x) => x['id'] != m['id']).toList());
          Toast.success('Success', description: 'Resell account removed.');
        } catch (e) {
          Toast.error('Error', description: toUserMessage(e, 'Failed to remove resell account.'));
        }
      },
    );
  }

  static bool _isActive(Object? s) => s == 1 || s == '1';

  static String _statusLabel(Object? s) => _isActive(s) ? 'Active' : (s == 0 || s == '0' ? 'Inactive' : 'Pending');

  static Color _statusColor(Object? s) =>
      _isActive(s) ? PillColors.green : (s == 0 || s == '0' ? PillColors.red : PillColors.amber);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final term = _search.toLowerCase();
    final filtered = _members
        .where(
          (m) =>
              '${m['name'] ?? ''}'.toLowerCase().contains(term) || '${m['email'] ?? ''}'.toLowerCase().contains(term),
        )
        .toList();
    final page = safePage(_page, filtered.length, _perPage);
    final pageItems = filtered.skip((page - 1) * _perPage).take(_perPage).toList();
    final activeCount = _members.where((m) => _isActive(m['status'])).length;

    return SettingsScaffold(
      onRefresh: _load,
      children: [
        const SettingsHeader(
          'Resell accounts',
          subtitle: 'Expand Your Business by Managing Resell Accounts Effectively',
        ),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Invite Resell Members',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
              ),
              const SizedBox(height: 2),
              Text(
                '$activeCount/5 members available in your plan.',
                style: TextStyle(fontSize: 12.5, color: c.gray500),
              ),
              const SizedBox(height: 14),
              AppInput(
                label: 'Email Address',
                controller: _email,
                placeholder: 'Enter email address',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.send,
                enabled: !_inviting,
                onSubmitted: (_) => _invite(),
              ),
              const SizedBox(height: 12),
              SettingsButton(
                label: 'Send',
                icon: LucideIcons.send,
                loading: _inviting,
                expand: true,
                onPressed: _email.text.trim().isEmpty ? null : _invite,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            EntriesSelect(value: _perPage, onChanged: (v) => setState(() => _perPage = v)),
            const SizedBox(width: 10),
            Expanded(child: SettingsSearchField(onChanged: (v) => setState(() => _search = v))),
          ],
        ),
        const SizedBox(height: 14),
        if (_loading)
          const SettingsLoading()
        else if (filtered.isEmpty)
          const SettingsEmptyState(
            icon: LucideIcons.handCoins,
            title: 'No resell accounts yet',
            message: 'Start growing your business! Invite your first resell partner using the form above.',
          )
        else
          for (final m in pageItems) _memberCard(context, m),
        SettingsPager(page: page, perPage: _perPage, total: filtered.length, onPage: (p) => setState(() => _page = p)),
      ],
    );
  }

  Widget _memberCard(BuildContext context, Map<String, dynamic> m) {
    final c = context.colors;
    final email = '${m['email'] ?? ''}';
    final name = '${m['name'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SettingsCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
        child: Row(
          children: [
            InitialAvatar(email, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name.isEmpty ? '—' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                        ),
                      ),
                      const SizedBox(width: 6),
                      StatusPill(_statusLabel(m['status']), _statusColor(m['status'])),
                    ],
                  ),
                  InfoRow(LucideIcons.mail, email),
                  InfoRow(LucideIcons.calendar, 'Joined: ${shortDate(m['created_at'])}'),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _remove(m),
              tooltip: 'Remove $email',
              icon: const Icon(LucideIcons.trash2, size: 18, color: AppColors.red500),
            ),
          ],
        ),
      ),
    );
  }
}
