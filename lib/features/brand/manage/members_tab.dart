import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/media.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import '../brand.dart';
import '../brand_api.dart';
import 'manage_ui.dart';

/// Port of `brand/manage/components/MembersTab.jsx` (+ InviteModals,
/// RemoveMemberModal). The web's 720px table becomes a list of member cards
/// on phones.
class MembersTab extends StatefulWidget {
  const MembersTab({super.key, required this.brand});

  final Brand brand;

  @override
  State<MembersTab> createState() => _MembersTabState();
}

const _roles = [('owner', 'Owner'), ('admin', 'Admin'), ('member', 'Member')];

class _Member {
  _Member(Map<String, dynamic> m)
    : id = m['id'] ?? m['member_id'] ?? m['user_id'],
      name = (m['name'] ?? (m['user'] is Map ? m['user']['name'] : null) ?? m['full_name'] ?? 'Unknown').toString(),
      email = (m['email'] ?? (m['user'] is Map ? m['user']['email'] : null) ?? '').toString(),
      role = (m['role'] ?? (m['pivot'] is Map ? m['pivot']['role'] : null) ?? 'member').toString().toLowerCase(),
      creditsUsed = num.tryParse('${m['credits_used'] ?? 0}') ?? 0,
      apps = m['apps_count'],
      agents = m['agents_count'],
      lastActive = m['last_active']?.toString(),
      avatar = (m['avatar'] ?? (m['user'] is Map ? m['user']['avatar'] : null))?.toString();

  final Object? id;
  final String name;
  final String email;
  String role;
  final num creditsUsed;
  final Object? apps;
  final Object? agents;
  final String? lastActive;
  final String? avatar;
}

class _MembersTabState extends State<MembersTab> {
  List<_Member> _members = [];
  bool _loading = true;
  String _query = '';
  Object? _updatingId;

  /// Role the list is narrowed to (null = everyone).
  String? _roleFilter;

  String _roleLabel(String role) => _roles.firstWhere((r) => r.$1 == role, orElse: () => (role, role)).$2;

  /// "Filter by" — on the web this button had no handler; here it narrows by role.
  Future<void> _pickFilter() async {
    final c = context.colors;
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Filter by role',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
                ),
              ),
            ),
            for (final (value, label) in [('', 'All roles'), ..._roles])
              ListTile(
                title: Text(label),
                trailing: (_roleFilter ?? '') == value
                    ? Icon(LucideIcons.check, size: 18, color: AppColors.blue600)
                    : null,
                onTap: () => Navigator.pop(ctx, value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _roleFilter = picked.isEmpty ? null : picked);
  }

  /// "Export" — also a dead button on the web; here it shares the visible
  /// members as a CSV through the system share sheet.
  Future<void> _export(List<_Member> members) async {
    String cell(Object? v) => '"${'${v ?? ''}'.replaceAll('"', '""')}"';
    final rows = [
      ['Name', 'Email', 'Role', 'Credits used', 'Apps', 'Agents', 'Last active'].map(cell).join(','),
      for (final m in members)
        [m.name, m.email, _roleLabel(m.role), m.creditsUsed, m.apps, m.agents, m.lastActive].map(cell).join(','),
    ];
    final slug = widget.brand.displayName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(utf8.encode(rows.join('\n')), mimeType: 'text/csv')],
          fileNameOverrides: ['$slug-members.csv'],
          subject: '${widget.brand.displayName} members',
        ),
      );
    } catch (_) {
      Toast.error("Couldn't export the member list.");
    }
  }

  Widget _toolButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    String? label,
    bool highlighted = false,
  }) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: highlighted ? c.blueTint : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: highlighted ? const Color(0xFFBEDBFF) : c.gray200),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: label == null ? 13 : 10),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: highlighted ? AppColors.blue600 : c.gray600),
                  if (label != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.blue600),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  BrandApi get _api => context.read<AuthController>().brandApi;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _api.members(widget.brand.id);
    if (!mounted) return;
    if (!res.ok) Toast.error("Couldn't load members.");
    setState(() {
      _members = res.ok ? listFrom(res.raw, 'members').map(_Member.new).toList() : [];
      _loading = false;
    });
  }

  Future<void> _changeRole(_Member m, String role) async {
    final previous = m.role;
    setState(() {
      m.role = role;
      _updatingId = m.id;
    });
    final res = await _api.updateMemberRole(widget.brand.id, m.id!, role);
    if (!mounted) return;
    setState(() {
      _updatingId = null;
      if (!res.ok) m.role = previous;
    });
    res.ok ? Toast.success("${m.name}'s role updated.") : Toast.error(res.message.ifBlank("Couldn't update the role."));
  }

  Future<void> _remove(_Member m) async {
    final removed = await showDialog<bool>(
      context: context,
      builder: (_) => _RemoveMemberDialog(brandId: widget.brand.id, member: m),
    );
    if (removed == true) _load();
  }

  void _inviteByEmail() => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _InviteByEmailSheet(brandId: widget.brand.id),
  );

  Future<void> _createLink() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CreateInviteLinkSheet(brandId: widget.brand.id),
    );
    if (created == true && mounted) _manageLinks();
  }

  void _manageLinks() => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _InviteLinksSheet(brandId: widget.brand.id, onCreate: _createLink),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _query.toLowerCase();
    final members = _members
        .where((m) => _roleFilter == null || m.role == _roleFilter)
        .where((m) => m.name.toLowerCase().contains(q) || m.email.toLowerCase().contains(q) || m.role.contains(q))
        .toList();
    int count(String role) => _members.where((m) => m.role == role).length;
    final credits = _members.fold<num>(0, (sum, m) => sum + m.creditsUsed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'View and manage members and roles for this brand.',
                style: TextStyle(fontSize: 13, color: c.gray500),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(LucideIcons.ellipsisVertical, size: 18, color: c.gray500),
              color: c.surface,
              onSelected: (_) => _manageLinks(),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'links',
                  child: Row(
                    children: [Icon(LucideIcons.link, size: 16), SizedBox(width: 10), Text('Manage Invite Link')],
                  ),
                ),
              ],
            ),
            PopupMenuButton<String>(
              tooltip: 'Invite Members',
              color: c.surface,
              onSelected: (v) => v == 'email' ? _inviteByEmail() : _createLink(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'email',
                  child: Row(
                    children: [Icon(LucideIcons.mail, size: 16), SizedBox(width: 10), Text('Invite by email')],
                  ),
                ),
                PopupMenuItem(
                  value: 'link',
                  child: Row(
                    children: [Icon(LucideIcons.link, size: 16), SizedBox(width: 10), Text('Create Invite Link')],
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: AppColors.blue600, borderRadius: BorderRadius.circular(10)),
                child: const Row(
                  children: [
                    Text(
                      'Invite',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(width: 4),
                    Icon(LucideIcons.chevronDown, size: 14, color: Colors.white),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final stats = [
              (
                'Brand members',
                '${_members.length}',
                '${count('owner')} Owner · ${count('admin')} Admin · ${count('member')} Members',
              ),
              ('Credits Usage', '$credits', 'Unlimited'),
              ('Top builders', '—', 'No activity in the last 30 days'),
            ];
            final cards = [
              for (final (label, value, sub) in stats)
                ManageCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: 12.5, color: c.gray500)),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c.gray900),
                      ),
                      Text(sub, style: TextStyle(fontSize: 11.5, color: c.gray400)),
                    ],
                  ),
                ),
            ];
            if (constraints.maxWidth >= 640) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, card) in cards.indexed) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: card),
                  ],
                ],
              );
            }
            return Column(
              children: [
                for (final (i, card) in cards.indexed) ...[if (i > 0) const SizedBox(height: 10), card],
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: manageInput(
                  context,
                  'Search by name, email, or role…',
                  prefixIcon: Icon(LucideIcons.search, size: 16, color: c.gray400),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _toolButton(
              context,
              icon: LucideIcons.download,
              tooltip: 'Export',
              onTap: members.isEmpty ? null : () => _export(members),
            ),
            const SizedBox(width: 8),
            _toolButton(
              context,
              icon: LucideIcons.listFilter,
              tooltip: 'Filter by',
              label: _roleFilter == null ? null : _roleLabel(_roleFilter!),
              highlighted: _roleFilter != null,
              onTap: _pickFilter,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'PEOPLE (${members.length})',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: c.gray400),
        ),
        const SizedBox(height: 8),
        if (_loading)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text('Loading members…', style: TextStyle(color: c.gray500)),
            ),
          )
        else if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                _query.isEmpty ? 'No members yet.' : 'No members match your search.',
                style: TextStyle(color: c.gray500),
              ),
            ),
          )
        else
          for (final m in members) ...[_memberCard(context, m), const SizedBox(height: 8)],
      ],
    );
  }

  Widget _memberCard(BuildContext context, _Member m) {
    final c = context.colors;
    return ManageCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Column(
        children: [
          Row(
            children: [
              _Avatar(member: m),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                    ),
                    if (m.email.isNotEmpty)
                      Text(
                        m.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.gray500),
                      ),
                  ],
                ),
              ),
              if (_updatingId == m.id)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              DropdownButton<String>(
                value: _roles.any((r) => r.$1 == m.role) ? m.role : 'member',
                underline: const SizedBox.shrink(),
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                dropdownColor: c.surface,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray800),
                items: [for (final (v, l) in _roles) DropdownMenuItem(value: v, child: Text(l))],
                onChanged: _updatingId != null ? null : (v) => v == null || v == m.role ? null : _changeRole(m, v),
              ),
              IconButton(
                tooltip: 'Remove member',
                onPressed: () => _remove(m),
                icon: const Icon(LucideIcons.userMinus, size: 17, color: AppColors.red500),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (label, value) in [
                ('Credits', '${m.creditsUsed}'),
                ('Apps', '${m.apps ?? '—'}'),
                ('Agents', '${m.agents ?? '—'}'),
                ('Last active', m.lastActive ?? '—'),
              ])
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label.toUpperCase(), style: TextStyle(fontSize: 9.5, letterSpacing: 0.8, color: c.gray400)),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: c.gray700),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.member, this.size = 36});

  final _Member member;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = Brand.resolveAssetUrl(member.avatar);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: context.colors.blueTint, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: url != null
          ? MediaImage(url)
          : Text(
              member.name.isEmpty ? '?' : member.name[0].toUpperCase(),
              style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700, color: AppColors.blue600),
            ),
    );
  }
}

class _RemoveMemberDialog extends StatefulWidget {
  const _RemoveMemberDialog({required this.brandId, required this.member});

  final int brandId;
  final _Member member;

  @override
  State<_RemoveMemberDialog> createState() => _RemoveMemberDialogState();
}

class _RemoveMemberDialogState extends State<_RemoveMemberDialog> {
  bool _busy = false;

  Future<void> _remove() async {
    setState(() => _busy = true);
    final res = await context.read<AuthController>().brandApi.removeMember(widget.brandId, widget.member.id!);
    if (!mounted) return;
    if (res.ok) {
      Toast.success('${widget.member.name} removed from the brand.');
      Navigator.pop(context, true);
    } else {
      Toast.error(res.message.ifBlank("Couldn't remove the member."));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConfirmCard(
      title: 'Remove member?',
      icon: LucideIcons.userMinus,
      confirmLabel: 'Remove member',
      busy: _busy,
      onConfirm: _remove,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This person will immediately lose access to this brand. You can invite them again later.',
            style: TextStyle(fontSize: 13.5, height: 1.45, color: c.gray600),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.gray50, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                _Avatar(member: widget.member, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.member.name,
                        style: TextStyle(fontWeight: FontWeight.w600, color: c.gray900),
                      ),
                      if (widget.member.email.isNotEmpty)
                        Text(widget.member.email, style: TextStyle(fontSize: 12, color: c.gray500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared sheet frame: title, close, padded body.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, this.subtitle, required this.children});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.gray900),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(LucideIcons.x, size: 18, color: c.gray400),
              ),
            ],
          ),
          if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 13, color: c.gray500)),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

Widget _select<T>(BuildContext context, T value, List<(T, String)> options, ValueChanged<T> onChanged) {
  final c = context.colors;
  return DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    dropdownColor: c.surface,
    borderRadius: BorderRadius.circular(10),
    style: TextStyle(fontSize: 14, color: c.gray900),
    decoration: manageInput(context, ''),
    items: [for (final (v, l) in options) DropdownMenuItem(value: v, child: Text(l))],
    onChanged: (v) => v == null ? null : onChanged(v),
  );
}

class _InviteByEmailSheet extends StatefulWidget {
  const _InviteByEmailSheet({required this.brandId});

  final int brandId;

  @override
  State<_InviteByEmailSheet> createState() => _InviteByEmailSheetState();
}

class _InviteByEmailSheetState extends State<_InviteByEmailSheet> {
  final _email = TextEditingController();
  String _role = 'member';
  bool _sending = false;

  bool get _valid => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim());

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_valid) {
      Toast.error('Enter a valid email address.');
      return;
    }
    setState(() => _sending = true);
    final email = _email.text.trim();
    final res = await context.read<AuthController>().brandApi.inviteByEmail(widget.brandId, email, _role);
    if (!mounted) return;
    if (res.ok) {
      Toast.success('Invitation sent to $email.');
      Navigator.pop(context);
    } else {
      Toast.error(res.message.ifBlank("Couldn't send the invitation."));
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Sheet(
      title: 'Invite people to your brand',
      subtitle: 'Invite teammates to collaborate in this brand.',
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Email address',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray800),
              ),
            ),
            SizedBox(
              width: 130,
              child: _select(context, _role, const [('admin', 'Admin'), ('member', 'Member')], (v) {
                setState(() => _role = v);
              }),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _send(),
          decoration: manageInput(context, 'teammate@company.com'),
        ),
        const SizedBox(height: 16),
        PrimaryAction(label: 'Send invitation', loading: _sending, onPressed: _valid ? _send : null),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Maybe later', style: TextStyle(color: c.gray500)),
        ),
      ],
    );
  }
}

class _CreateInviteLinkSheet extends StatefulWidget {
  const _CreateInviteLinkSheet({required this.brandId});

  final int brandId;

  @override
  State<_CreateInviteLinkSheet> createState() => _CreateInviteLinkSheetState();
}

class _CreateInviteLinkSheetState extends State<_CreateInviteLinkSheet> {
  String _role = 'member';
  int _maxUses = 10;
  bool _creating = false;

  Future<void> _create() async {
    setState(() => _creating = true);
    final res = await context.read<AuthController>().brandApi.createInviteLink(widget.brandId, _role, _maxUses);
    if (!mounted) return;
    if (res.ok) {
      Toast.success('Invite link created.');
      Navigator.pop(context, true);
    } else {
      Toast.error(res.message.ifBlank("Couldn't create the invite link."));
      setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Create invite link',
      children: [
        ManageField(
          label: 'Role',
          child: _select(context, _role, const [('admin', 'Admin'), ('member', 'Member')], (v) {
            setState(() => _role = v);
          }),
        ),
        const SizedBox(height: 12),
        ManageField(
          label: 'Maximum uses',
          child: _select(context, _maxUses, [
            for (final n in [1, 5, 10, 25, 50, 100]) (n, '$n ${n == 1 ? 'use' : 'uses'}'),
          ], (v) => setState(() => _maxUses = v)),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFEE685)),
          ),
          child: const Text(
            '⚠️ Anyone with this link can join your brand and access its data. Only share it with people you trust.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF973C00)),
          ),
        ),
        const SizedBox(height: 16),
        PrimaryAction(label: 'Create', loading: _creating, onPressed: _create),
      ],
    );
  }
}

class _InviteLinksSheet extends StatefulWidget {
  const _InviteLinksSheet({required this.brandId, required this.onCreate});

  final int brandId;
  final VoidCallback onCreate;

  @override
  State<_InviteLinksSheet> createState() => _InviteLinksSheetState();
}

class _InviteLinksSheetState extends State<_InviteLinksSheet> {
  List<Map<String, dynamic>> _links = [];
  bool _loading = true;
  Object? _copiedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await context.read<AuthController>().brandApi.inviteLinks(widget.brandId);
    if (!mounted) return;
    if (!res.ok) Toast.error("Couldn't load invite links.");
    setState(() {
      _links = res.ok ? listFrom(res.raw, 'invites') : [];
      _loading = false;
    });
  }

  /// `url`/`invite_url`/`link`, or a bare token turned into the web invite URL.
  String _url(Map<String, dynamic> l) {
    final direct = (l['url'] ?? l['invite_url'] ?? l['link'])?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    return '${AppConfig.webAppUrl}/invites/${l['token']}';
  }

  Future<void> _copy(Map<String, dynamic> l) async {
    try {
      await Clipboard.setData(ClipboardData(text: _url(l)));
      Toast.success('Link copied to clipboard.');
      setState(() => _copiedId = l['id']);
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _copiedId = null);
      });
    } catch (_) {
      Toast.error("Couldn't copy the link.");
    }
  }

  Future<void> _revoke(Map<String, dynamic> l) async {
    final res = await context.read<AuthController>().brandApi.deleteInviteLink(widget.brandId, l['id']);
    if (res.ok) {
      Toast.success('Invite link revoked.');
      _load();
    } else {
      Toast.error(res.message.ifBlank("Couldn't revoke the link."));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Sheet(
      title: 'Invite links',
      subtitle: 'Create and manage invite links for this brand.',
      children: [
        if (_loading)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text('Loading links…', style: TextStyle(color: c.gray500)),
            ),
          )
        else if (_links.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text('No invite links yet.', style: TextStyle(color: c.gray500)),
            ),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final l in _links)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.gray200),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.link, size: 16, color: c.gray400),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _url(l),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: c.gray800),
                              ),
                              Text(() {
                                final role = (l['role'] ?? 'member').toString();
                                final max = l['max_uses'];
                                final used = l['uses_count'] ?? l['used'] ?? 0;
                                return '${role[0].toUpperCase()}${role.substring(1)} · $used/${max ?? '∞'} ${max == 1 ? 'Use' : 'Uses'}';
                              }(), style: TextStyle(fontSize: 11.5, color: c.gray500)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy link',
                          onPressed: () => _copy(l),
                          icon: Icon(
                            _copiedId == l['id'] ? LucideIcons.check : LucideIcons.copy,
                            size: 16,
                            color: _copiedId == l['id'] ? AppColors.green600 : c.gray500,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Revoke link',
                          onPressed: () => _revoke(l),
                          icon: const Icon(LucideIcons.trash2, size: 16, color: AppColors.red500),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        PrimaryAction(
          label: 'Create Invite Link',
          icon: LucideIcons.link,
          onPressed: () {
            Navigator.pop(context);
            widget.onCreate();
          },
        ),
      ],
    );
  }
}

extension BlankFallback on String {
  String ifBlank(String fallback) => trim().isEmpty ? fallback : this;
}
