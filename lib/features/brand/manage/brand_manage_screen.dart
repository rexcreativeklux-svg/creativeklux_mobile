import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import '../../shell/widgets/app_top_bar.dart';
import '../brand.dart';
import 'ai_keys_tab.dart';
import 'allocation_tab.dart';
import 'manage_ui.dart';
import 'members_tab.dart';

/// Port of `brand/manage/page.jsx` — "Brand Settings" for the ACTIVE brand.
class BrandManageScreen extends StatefulWidget {
  const BrandManageScreen({super.key});

  @override
  State<BrandManageScreen> createState() => _BrandManageScreenState();
}

class _Tab {
  const _Tab(this.id, this.label, this.icon, {this.badge});
  final String id;
  final String label;
  final IconData icon;
  final String? badge;
}

const _tabs = [
  _Tab('basic', 'Basic Information', LucideIcons.fileText),
  _Tab('members', 'Members', LucideIcons.users),
  _Tab('allocation', 'Allocation', LucideIcons.slidersHorizontal),
  _Tab('auth', 'Auth and Security', LucideIcons.lock),
  _Tab('integrations', 'Integrations', LucideIcons.puzzle, badge: 'Builder+'),
  _Tab('ai-keys', 'AI Keys', LucideIcons.keyRound),
  _Tab('skills', 'Skills', LucideIcons.sparkles, badge: 'Builder+'),
  _Tab('config', 'Configuration', LucideIcons.settings, badge: 'Enterprise'),
];

class _BrandManageScreenState extends State<BrandManageScreen> {
  String _tab = 'basic';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = context.watch<AuthController>();
    final brand = auth.activeBrand;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Brand Settings', showBack: true),
          Expanded(
            child: Container(
              color: c.page,
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  Text(
                    'Manage members, allocation, and configuration for this brand.',
                    style: TextStyle(fontSize: 13.5, color: c.gray500),
                  ),
                  const SizedBox(height: 14),
                  _tabBar(context),
                  const SizedBox(height: 16),
                  if (auth.brandsLoading)
                    Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator(color: AppColors.blue600)),
                    )
                  else if (brand == null)
                    _noBrand(context)
                  else
                    // Keyed on the brand so every panel starts fresh after a switch.
                    KeyedSubtree(key: ValueKey('${brand.id}-$_tab'), child: _panel(brand)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBar(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gray200),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            for (final t in _tabs)
              InkWell(
                onTap: () => setState(() => _tab = t.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: _tab == t.id ? AppColors.blue600 : Colors.transparent, width: 2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(t.icon, size: 15, color: _tab == t.id ? AppColors.blue600 : c.gray500),
                      const SizedBox(width: 6),
                      Text(
                        t.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _tab == t.id ? AppColors.blue600 : c.gray600,
                        ),
                      ),
                      if (t.badge != null) ...[const SizedBox(width: 6), AmberBadge(t.badge!)],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _noBrand(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.gray300),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.building2, size: 28, color: c.gray400),
          const SizedBox(height: 10),
          Text(
            'No active brand',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
          ),
          const SizedBox(height: 4),
          Text(
            'Select a brand to manage its members, allocation, and settings.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.gray500),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go('/brand/reuse'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.blue600),
            child: const Text('Choose a brand'),
          ),
        ],
      ),
    );
  }

  Widget _panel(Brand brand) => switch (_tab) {
    'basic' => _BasicInfoTab(brand: brand),
    'members' => MembersTab(brand: brand),
    'allocation' => AllocationTab(brand: brand),
    'integrations' => const _IntegrationsTab(),
    'ai-keys' => AiKeysTab(brand: brand),
    'auth' => const _ComingSoon(
      'Auth and security',
      'Manage sign-in methods, session policies, and security settings for this brand.',
    ),
    'skills' => const _ComingSoon('Skills', 'Equip this brand with reusable AI skills and automations for your team.'),
    _ => const _ComingSoon('Configuration', 'Fine-tune advanced brand behaviour, defaults, and enterprise controls.'),
  };
}

// ── Basic information ───────────────────────────────────────────────────────

class _BasicInfoTab extends StatefulWidget {
  const _BasicInfoTab({required this.brand});

  final Brand brand;

  @override
  State<_BasicInfoTab> createState() => _BasicInfoTabState();
}

class _BasicInfoTabState extends State<_BasicInfoTab> {
  late final _name = TextEditingController(text: widget.brand.name ?? '');
  late final _description = TextEditingController(text: widget.brand.description ?? '');
  bool _saving = false;

  bool get _dirty =>
      _name.text.trim() != (widget.brand.name ?? '') || _description.text != (widget.brand.description ?? '');

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _description.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      Toast.error("Brand name can't be empty.");
      return;
    }
    setState(() => _saving = true);
    final auth = context.read<AuthController>();
    final b = widget.brand;
    final res = await auth.brandApi.update(
      b.id,
      name: _name.text.trim(),
      description: _description.text,
      tagline: b.tagline,
      fonts: b.fonts,
      industry: b.industry,
      primaryColor: Brand.cleanHex(b.primaryColor),
      secondaryColor: Brand.cleanHex(b.secondaryColor),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Toast.success('Brand updated.');
      await auth.fetchBrands();
    } else {
      Toast.error(res.message.isNotEmpty ? res.message : "Couldn't update the brand. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        ManageCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ManageField(
                label: 'Brand name',
                child: TextField(controller: _name, decoration: manageInput(context, 'My Brand')),
              ),
              const SizedBox(height: 14),
              ManageField(
                label: 'Brand description',
                child: TextField(
                  controller: _description,
                  minLines: 4,
                  maxLines: 8,
                  decoration: manageInput(context, 'What is this brand about?'),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: PrimaryAction(
                  label: 'Save Changes',
                  loading: _saving,
                  onPressed: _dirty && !_saving ? _save : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ManageCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Leave brand',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
              ),
              const SizedBox(height: 4),
              Text(
                'If you leave this brand, you will lose access to all associated apps.',
                style: TextStyle(fontSize: 13, color: c.gray500),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _LeaveBrandDialog(brand: widget.brand),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red600,
                  side: const BorderSide(color: Color(0xFFFFC9C9)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(LucideIcons.house, size: 16),
                label: const Text('Leave Brand'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LeaveBrandDialog extends StatefulWidget {
  const _LeaveBrandDialog({required this.brand});

  final Brand brand;

  @override
  State<_LeaveBrandDialog> createState() => _LeaveBrandDialogState();
}

class _LeaveBrandDialogState extends State<_LeaveBrandDialog> {
  bool _busy = false;

  Future<void> _leave() async {
    setState(() => _busy = true);
    final auth = context.read<AuthController>();
    final router = GoRouter.of(context);
    final res = await auth.brandApi.leave(widget.brand.id);
    if (!mounted) return;
    if (res.ok) {
      Toast.success("You've left this brand.");
      Navigator.pop(context);
      auth.clearActiveBrand();
      router.go('/brand/reuse');
      await auth.fetchBrands();
    } else {
      Toast.error(res.message.isNotEmpty ? res.message : "Couldn't leave the brand.");
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConfirmCard(
      title: 'Leave this brand?',
      body: Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 13.5, height: 1.45, color: c.gray600),
          children: [
            const TextSpan(text: "You'll immediately lose access to "),
            TextSpan(
              text: widget.brand.displayName,
              style: TextStyle(fontWeight: FontWeight.w700, color: c.gray900),
            ),
            const TextSpan(text: " and everything in it. This can't be undone."),
          ],
        ),
      ),
      confirmLabel: 'Leave',
      busy: _busy,
      onConfirm: _leave,
    );
  }
}

// ── Integrations (presentational, like the web) ─────────────────────────────

class _IntegrationsTab extends StatefulWidget {
  const _IntegrationsTab();

  @override
  State<_IntegrationsTab> createState() => _IntegrationsTabState();
}

class _IntegrationsTabState extends State<_IntegrationsTab> {
  final _connected = <String>{};

  static const _social = [
    (
      'Facebook Pages',
      'Publish posts & images to your Facebook Pages.',
      LucideIcons.thumbsUp,
      [Color(0xFF1877F2), Color(0xFF0E5FCC)],
    ),
    (
      'Instagram Business',
      'Publish photos & reels to Instagram Business accounts.',
      LucideIcons.camera,
      [Color(0xFFF58529), Color(0xFFDD2A7B)],
    ),
    (
      'X / Twitter',
      'Post tweets, images, and videos to X (Twitter).',
      LucideIcons.atSign,
      [Color(0xFF111111), Color(0xFF333333)],
    ),
    (
      'LinkedIn',
      'Share posts and articles on LinkedIn pages.',
      LucideIcons.briefcase,
      [Color(0xFF0A66C2), Color(0xFF004182)],
    ),
    (
      'YouTube',
      'Upload videos and manage your YouTube channel.',
      LucideIcons.play,
      [Color(0xFFFF0000), Color(0xFFCC0000)],
    ),
    ('Pinterest', 'Create pins and manage Pinterest boards.', LucideIcons.pin, [Color(0xFFE60023), Color(0xFFAD081F)]),
    ('TikTok', 'Publish videos and create TikTok content.', LucideIcons.music2, [Color(0xFF010101), Color(0xFF25F4EE)]),
  ];

  static const _ads = [
    (
      'Meta Ads Manager',
      'Create & manage Facebook and Instagram ad campaigns.',
      LucideIcons.megaphone,
      [Color(0xFF0668E1), Color(0xFF0080FB)],
    ),
    (
      'Google Ads',
      'Manage Google Search, Display & YouTube campaigns.',
      LucideIcons.chartBar,
      [Color(0xFF4285F4), Color(0xFF34A853)],
    ),
    (
      'TikTok Ads',
      'Launch and manage TikTok ad campaigns.',
      LucideIcons.music2,
      [Color(0xFF010101), Color(0xFFFE2C55)],
    ),
    (
      'Snapchat Ads',
      'Create and manage Snapchat advertising campaigns.',
      LucideIcons.ghost,
      [Color(0xFFFFFC00), Color(0xFFF5D400)],
    ),
    (
      'Pinterest Ads',
      'Run Pinterest ad campaigns and promoted pins.',
      LucideIcons.pin,
      [Color(0xFFE60023), Color(0xFFAD081F)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget group(String title, List<(String, String, IconData, List<Color>)> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.gray900),
        ),
        const SizedBox(height: 10),
        for (final (name, desc, icon, colors) in items) ...[
          ManageCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(colors: colors),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: colors.first.computeLuminance() > 0.6 ? Colors.black : Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _connected.contains(name)
                              ? const StatusChip('✓ Connected', fg: Color(0xFF047857), bg: Color(0xFFECFDF5))
                              : StatusChip('Not connected', fg: c.gray500, bg: c.gray100),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(desc, style: TextStyle(fontSize: 12.5, color: c.gray500)),
                      const SizedBox(height: 10),
                      _connected.contains(name)
                          ? OutlinedButton(
                              onPressed: () => setState(() => _connected.remove(name)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.red600,
                                side: const BorderSide(color: Color(0xFFFFC9C9)),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: const Text('Disconnect'),
                            )
                          : GradientButton(label: 'Connect', onPressed: () => setState(() => _connected.add(name))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoBanner(
          children: [
            const TextSpan(
              text: 'Connect your accounts: ',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const TextSpan(
              text:
                  'Link social and advertising platforms to publish and run campaigns for this brand. '
                  'For the full one-click connect flow, open the ',
            ),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => context.push('/integrations'),
                child: const Text(
                  'Integrations page ↗',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1E40AF),
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const TextSpan(text: '.'),
          ],
        ),
        const SizedBox(height: 16),
        group('Social Media', _social),
        const SizedBox(height: 8),
        group('Advertising Platforms', _ads),
      ],
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon(this.title, this.description);

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ManageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.gray900),
              ),
              const SizedBox(width: 8),
              const AmberBadge('Coming Soon'),
            ],
          ),
          const SizedBox(height: 6),
          Text(description, style: TextStyle(fontSize: 13.5, height: 1.45, color: c.gray500)),
        ],
      ),
    );
  }
}
