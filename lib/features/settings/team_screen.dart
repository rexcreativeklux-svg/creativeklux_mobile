import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/app_input.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'settings_api.dart';
import 'settings_widgets.dart';

/// Port of `(settings)/team/page.jsx` + `TeamsList.jsx` — invite by email,
/// then the members as cards (the web forces cards below `md` too; its table
/// view isn't offered on a phone), searched and paged on the device.
///
/// `GET /teams`, `POST /teams {email}`, `DELETE /teams/{id}` — all real.
/// The web's NotificationModal popups are toasts here.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  late final SettingsApi _api = SettingsApi(context.read<AuthController>().api);
  final _email = TextEditingController();

  List<Map<String, dynamic>> _teams = const [];
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

  /// A failed read empties the list quietly, as AuthContext's fetchTeams does.
  Future<void> _load() async {
    try {
      final list = await _api.teams();
      if (mounted) setState(() => _teams = list);
    } catch (e) {
      debugPrint('Fetching teams failed: $e');
      if (mounted) setState(() => _teams = const []);
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
      await _api.inviteTeamMember(email);
      Toast.success('Success!', description: '$email has been invited!');
      _email.clear();
      await _load();
    } catch (e) {
      Toast.error('Failed', description: toUserMessage(e, 'Could not send invitation.'));
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> m) async {
    final name = '${m['name'] ?? m['email'] ?? 'this member'}';
    await showConfirmDialog(
      context,
      title: 'Remove member?',
      message: 'Are you sure you want to remove $name?',
      confirmLabel: 'Remove',
      danger: true,
      onConfirm: () async {
        try {
          final msg = await _api.removeTeamMember(m['id'] as Object);
          if (mounted) setState(() => _teams = _teams.where((t) => t['id'] != m['id']).toList());
          Toast.success('Success', description: msg ?? '$name removed successfully.');
        } catch (e) {
          Toast.error('Error', description: toUserMessage(e, 'Failed to remove member.'));
        }
      },
    );
  }

  static bool _isActive(Object? status) => status is String ? status.toLowerCase() == 'active' : status == 1;

  static String _statusLabel(Object? status) {
    if (status is String && status.isNotEmpty) return status[0].toUpperCase() + status.substring(1);
    return status == 1 ? 'Active' : (status == 0 ? 'Inactive' : 'Unknown');
  }

  static Color _statusColor(Object? status) {
    final s = status is String ? status.toLowerCase() : (status == 1 ? 'active' : (status == 0 ? 'inactive' : ''));
    return switch (s) {
      'active' => PillColors.green,
      'pending' => PillColors.amber,
      'inactive' => PillColors.red,
      _ => PillColors.gray,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final term = _search.toLowerCase();
    final filtered = _teams.where((t) {
      return '${t['name'] ?? ''}'.toLowerCase().contains(term) ||
          '${t['email'] ?? ''}'.toLowerCase().contains(term) ||
          '${t['phone'] ?? ''}'.contains(_search);
    }).toList();
    final page = safePage(_page, filtered.length, _perPage);
    final pageItems = filtered.skip((page - 1) * _perPage).take(_perPage).toList();
    final activeCount = _teams.where((t) => _isActive(t['status'])).length;

    return SettingsScaffold(
      onRefresh: _load,
      children: [
        const SettingsHeader('Team Members', subtitle: 'Manage and Collaborate with Your Team Efficiently'),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Invite Team Members',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
              ),
              const SizedBox(height: 2),
              Text('$activeCount/5 members available in your plan', style: TextStyle(fontSize: 12.5, color: c.gray500)),
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
                label: 'Send Invite',
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
            icon: LucideIcons.users,
            title: 'No team members yet',
            message: 'Build your dream team! Invite your first member using the form above to start collaborating.',
          )
        else
          for (final m in pageItems) _memberCard(context, m),
        SettingsPager(page: page, perPage: _perPage, total: filtered.length, onPage: (p) => setState(() => _page = p)),
      ],
    );
  }

  Widget _memberCard(BuildContext context, Map<String, dynamic> m) {
    final c = context.colors;
    final name = '${m['name'] ?? ''}';
    final email = '${m['email'] ?? ''}';
    final phone = '${m['phone'] ?? ''}'.trim();
    final role = '${m['role'] ?? ''}';
    final roleKey = role.toLowerCase();
    final domain = '${m['custom_domain'] ?? ''}';

    Widget contact(IconData icon, String tooltip, String? uri) => IconButton(
      onPressed: uri == null ? null : () => launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 17, color: uri == null ? c.gray200 : c.gray400),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SettingsCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  InitialAvatar(name.isEmpty ? email : name),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? email : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            StatusPill(role.isEmpty ? 'No Role' : role, switch (roleKey) {
                              'owner' => const Color(0xFF1D4ED8),
                              'admin' => AppColors.blue600,
                              _ => PillColors.gray,
                            }, solid: roleKey == 'owner'),
                            StatusPill(_statusLabel(m['status']), _statusColor(m['status'])),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                children: [
                  InfoRow(LucideIcons.mail, email),
                  InfoRow(LucideIcons.phone, phone.isEmpty ? 'N/A' : phone),
                  InfoRow(LucideIcons.mapPin, domain.isEmpty ? 'Unknown' : domain),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: c.gray100),
            Row(
              children: [
                contact(LucideIcons.mail, 'Email', email.isEmpty ? null : 'mailto:$email'),
                contact(LucideIcons.phone, 'Call', phone.isEmpty ? null : 'tel:$phone'),
                contact(
                  LucideIcons.messageCircle,
                  'WhatsApp',
                  phone.isEmpty ? null : 'https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}',
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _remove(m),
                  tooltip: 'Remove',
                  icon: const Icon(LucideIcons.trash2, size: 17, color: AppColors.red500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
