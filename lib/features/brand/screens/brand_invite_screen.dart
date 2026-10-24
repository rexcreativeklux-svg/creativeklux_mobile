import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import '../brand.dart';
import '../brand_api.dart';
import '../widgets/brand_visuals.dart';

/// Port of `app/invites/[token]/page.jsx` — accept a brand invite.
///
/// Reached from an invite link (`https://app.creativeklux.com/invites/<token>`
/// once App Links are verified — see CLAUDE.md) or in-app. Signed-out users
/// park the token as a pending invite and come back here after signing in.
class BrandInviteScreen extends StatefulWidget {
  const BrandInviteScreen({super.key, required this.token});

  final String token;

  @override
  State<BrandInviteScreen> createState() => _BrandInviteScreenState();
}

class _BrandInviteScreenState extends State<BrandInviteScreen> {
  Map<String, dynamic>? _invite;
  String? _error;
  bool _accepting = false;

  // The invite page has its own dark look on the web, in both themes.
  static const _bg = Color(0xFF0A0A0B);
  static const _card = Color(0xFF161618);
  static const _muted = Color(0xFF9B9BA5);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    // Arriving here signed in means any parked invite has been picked up.
    if (auth.isLoggedIn && auth.pendingInvite != null) auth.setPendingInvite(null);
    if (widget.token.trim().isEmpty) {
      setState(() => _error = 'This invite link is invalid.');
      return;
    }
    final res = await auth.brandApi.invite(widget.token);
    if (!mounted) return;
    setState(() {
      if (res.ok) {
        final d = res.body['data'];
        _invite = d is Map<String, dynamic> ? d : res.body;
      } else {
        _error = "This invite couldn't be loaded. It may have expired or been revoked.";
      }
    });
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    final auth = context.read<AuthController>();
    final router = GoRouter.of(context);
    final res = await auth.brandApi.acceptInvite(widget.token);
    if (!mounted) return;
    if (res.ok) {
      Toast.success(res.body['message']?.toString() ?? "You've joined the brand!");
      final joinedId = BrandApi.joinedBrandId(res.body);
      final brands = await auth.fetchBrands();
      final joined = brands.where((b) => b.id == joinedId).firstOrNull;
      if (joined != null) await auth.setActiveBrand(joined);
      router.go('/');
    } else {
      Toast.error(res.status == 401 ? 'Please sign in to accept.' : "Couldn't accept the invite. Please try again.");
      setState(() => _accepting = false);
    }
  }

  Future<void> _signInFirst(String path) async {
    await context.read<AuthController>().setPendingInvite(widget.token);
    if (mounted) context.go(path);
  }

  String _expires(dynamic raw) {
    final d = DateTime.tryParse('$raw')?.toLocal();
    if (d == null) return '—';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${m[d.month - 1]} ${d.day}, ${d.year}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: _error != null
                    ? _errorView(auth)
                    : _invite == null
                    ? Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            CircularProgressIndicator(color: AppColors.blue500),
                            SizedBox(height: 14),
                            Text('Loading your invite…', style: TextStyle(color: _muted)),
                          ],
                        ),
                      )
                    : _inviteView(auth),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorView(AuthController auth) => Column(
    children: [
      const Text(
        'Invite unavailable',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      const SizedBox(height: 8),
      Text(
        _error!,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _muted, height: 1.45),
      ),
      const SizedBox(height: 20),
      _button(
        auth.isLoggedIn ? 'Go to dashboard' : 'Go to sign in',
        () => context.go(auth.isLoggedIn ? '/' : '/login'),
      ),
    ],
  );

  Widget _inviteView(AuthController auth) {
    final inv = _invite!;
    final brand = inv['brand'] is Map ? inv['brand'] as Map : const {};
    final by = inv['invited_by'] is Map ? inv['invited_by'] as Map : const {};
    final brandName = '${brand['name'] ?? 'this brand'}';
    final role = '${inv['role'] ?? 'member'}';

    Widget detail(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: const TextStyle(fontSize: 13, color: _muted)),
          ),
          Expanded(child: value),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Image.asset('assets/images/logo.png', width: 26, height: 26),
            const SizedBox(width: 8),
            const Text(
              'Creative Klux',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (Brand.resolveAssetUrl(brand['logo']?.toString()) != null)
          Center(
            child: BrandLogoTile(
              name: brandName,
              color: AppColors.blue600,
              logoUrl: Brand.resolveAssetUrl(brand['logo']?.toString()),
              size: 64,
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          "You're invited!",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF3B82F6)),
        ),
        const SizedBox(height: 6),
        Text(
          'Join $brandName and start collaborating',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: _muted),
        ),
        const SizedBox(height: 20),
        Divider(color: Colors.white.withValues(alpha: 0.08)),
        detail(
          'Brand',
          Text(
            brandName,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
        detail(
          'Invited by',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${by['name'] ?? '—'}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      role[0].toUpperCase() + role.substring(1),
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ),
                ],
              ),
              if (by['email'] != null) Text('${by['email']}', style: const TextStyle(fontSize: 12.5, color: _muted)),
            ],
          ),
        ),
        detail('Expires', Text(_expires(inv['expires_at']), style: const TextStyle(color: Colors.white))),
        Divider(color: Colors.white.withValues(alpha: 0.08)),
        const SizedBox(height: 16),
        if (auth.isLoggedIn) ...[
          _button(_accepting ? 'Joining…' : 'Accept invitation', _accepting ? null : _accept, loading: _accepting),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              Text('Signed in as ${auth.email}. ', style: const TextStyle(fontSize: 12.5, color: _muted)),
              GestureDetector(
                onTap: () async {
                  await auth.setPendingInvite(widget.token);
                  await auth.logout();
                },
                child: const Text(
                  'Not you?',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF3B82F6), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ] else ...[
          _button('Sign in to accept', () => _signInFirst('/login')),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => _signInFirst('/register'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Create an account'),
          ),
          const SizedBox(height: 10),
          const Text(
            "You'll come right back here to accept after signing in — your invite is saved.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _muted),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          "If you didn't expect this invitation, you can safely ignore it.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: Color(0xFF6B6B75)),
        ),
      ],
    );
  }

  Widget _button(String label, VoidCallback? onPressed, {bool loading = false}) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: const Color(0xFF2563EB),
      disabledBackgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.6),
      disabledForegroundColor: Colors.white,
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 8),
        ],
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
