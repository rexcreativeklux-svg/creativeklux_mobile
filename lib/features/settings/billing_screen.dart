import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/api/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'billing_data.dart';
import 'settings_api.dart';
import 'settings_widgets.dart';

/// Port of `(settings)/billing/page.jsx` — Plans & Billing.
///
/// - Current Subscription is LIVE: it reads `AuthController.activePackage`
///   (`GET /package`).
/// - License code: `POST /apply-promotion-code` (real), then the package is
///   re-read so the drawer's plan name updates along with this card.
/// - Plan checkout and token top-ups are placeholders on the web too (no
///   checkout-session endpoint yet), so they toast "coming soon". When the web
///   gets a Stripe URL, open it with url_launcher — there's no card form here.
/// - The plans grid is HANDCODED (billing_data.dart), stacked on a phone.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  BillingCycle _cycle = BillingCycle.monthly;

  /// The license entry stays hidden until "Upgrade plan" is pressed.
  bool _showLicense = false;
  final _licenseKey = GlobalKey();

  void _startUpgrade() {
    setState(() => _showLicense = true);
    // Wait a frame so the revealed card exists before scrolling to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _licenseKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      }
    });
  }

  // The web's handleUpgrade/handleBuyTokens are placeholders too, until
  // POST /billing/checkout-session exists to hand back a Stripe URL.
  void _upgrade(Plan plan) => Toast.info('Secure checkout with Stripe is coming soon.');

  void _buyTokens() => Toast.info('Token purchases are coming soon.');

  Future<void> _redeem(String code) async {
    final auth = context.read<AuthController>();
    final pkg = await SettingsApi(auth.api).applyPromotionCode(code);
    final next = Subscription.fromPackage(pkg);
    // The controller has no setter for the package; re-reading it is the same
    // result (the web writes the response straight into AuthContext).
    await auth.fetchPackage();
    Toast.success('${next.planName} activated with your license code.');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final sub = Subscription.fromPackage(auth.activePackage);
    final c = context.colors;

    return SettingsScaffold(
      children: [
        const SettingsHeader('Plans & Billing', subtitle: 'Manage your subscription and upgrades'),
        _SubscriptionCard(sub: sub, email: auth.email, onBuyTokens: _buyTokens, onUpgrade: _startUpgrade),
        if (_showLicense) ...[const SizedBox(height: 16), _LicenseCodeCard(key: _licenseKey, onRedeem: _redeem)],
        const SizedBox(height: 26),
        Text(
          'Plans',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.gray900),
        ),
        const SizedBox(height: 3),
        Text(
          'Pick the plan that matches how much you create. Change or cancel whenever you like.',
          style: TextStyle(fontSize: 12.5, color: c.gray500, height: 1.35),
        ),
        const SizedBox(height: 12),
        _CycleToggle(value: _cycle, onChanged: (v) => setState(() => _cycle = v)),
        const SizedBox(height: 22),
        for (final plan in plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: _PlanCard(
              plan: plan,
              cycle: _cycle,
              // Faithful to the web: planId is the package's numeric id, so it
              // never equals a tier id and no card reads "Current plan" yet.
              isCurrent: plan.id == sub.planId,
              onSelect: _upgrade,
            ),
          ),
      ],
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.sub, required this.email, required this.onBuyTokens, required this.onUpgrade});

  final Subscription sub;
  final String email;
  final VoidCallback onBuyTokens;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget stat(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 14, color: c.gray500),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: c.gray500)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
            ),
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.gray200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gradient band (`from-[#155dfc] to-blue-400`).
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.blue600, const Color(0xFF51A2FF)])),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Subscription',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                SizedBox(height: 2),
                Text(
                  'Your active plan and renewal details',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFFEFF6FF)),
                ),
              ],
            ),
          ),
          stat(LucideIcons.badgeCheck, 'Plan', sub.planName),
          Divider(height: 1, color: c.gray200),
          stat(LucideIcons.calendarDays, 'Registered', sub.registeredOn),
          Divider(height: 1, color: c.gray200),
          stat(LucideIcons.sparkles, 'Renews', sub.renews),
          // Status strip.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.gray50,
              border: Border(top: BorderSide(color: c.gray200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: c.blueTint, shape: BoxShape.circle),
                      child: Icon(LucideIcons.badgeCheck, size: 17, color: AppColors.blue600),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "You're on the ${sub.planName}",
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${sub.tagline}${email.isNotEmpty ? ' · billed to $email' : ''}',
                            style: TextStyle(fontSize: 12, color: c.gray500, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SettingsButton(
                        label: 'Buy tokens',
                        icon: LucideIcons.coins,
                        outlined: true,
                        expand: true,
                        onPressed: onBuyTokens,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SettingsButton(
                        label: 'Upgrade plan',
                        icon: LucideIcons.sparkles,
                        expand: true,
                        onPressed: onUpgrade,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Port of `LicenseCodeCard.jsx` — redeem a key instead of paying by card.
class _LicenseCodeCard extends StatefulWidget {
  const _LicenseCodeCard({super.key, required this.onRedeem});

  /// Throws on failure so the card can toast it.
  final Future<void> Function(String code) onRedeem;

  @override
  State<_LicenseCodeCard> createState() => _LicenseCodeCardState();
}

class _LicenseCodeCardState extends State<_LicenseCodeCard> {
  final _code = TextEditingController();
  bool _redeeming = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Uppercase, A–Z/0–9/dash only, single dashes, at most 29 characters —
  /// users paste all sorts (spaces, lowercase, trailing dashes).
  static String normalize(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9-]'), '').replaceAll(RegExp(r'-{2,}'), '-');

  /// At least three dash-separated blocks and ten characters — enough to
  /// reject obvious typos without guessing the backend's key format.
  static bool plausible(String code) => code.split('-').where((p) => p.isNotEmpty).length >= 3 && code.length >= 10;

  Future<void> _apply() async {
    final cleaned = normalize(_code.text).replaceFirst(RegExp(r'-$'), '');
    if (cleaned.isEmpty) {
      Toast.error('Enter your license code first.');
      return;
    }
    if (!plausible(cleaned)) {
      Toast.error("That doesn't look like a valid license code.");
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _redeeming = true);
    try {
      await widget.onRedeem(cleaned);
      _code.clear();
    } catch (e) {
      Toast.error(toUserMessage(e, "We couldn't redeem that code. Please try again."));
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color),
    );

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c.blueTint, shape: BoxShape.circle),
                child: Icon(LucideIcons.ticket, size: 17, color: AppColors.blue600),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Have a license code?',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Redeem a key to activate or upgrade your plan instantly — no card required.',
                      style: TextStyle(fontSize: 12, color: c.gray500, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            enabled: !_redeeming,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _apply(),
            inputFormatters: [
              TextInputFormatter.withFunction((_, v) {
                final t = normalize(v.text);
                final clipped = t.length > 29 ? t.substring(0, 29) : t;
                return TextEditingValue(
                  text: clipped,
                  selection: TextSelection.collapsed(offset: clipped.length),
                );
              }),
            ],
            style: TextStyle(fontSize: 13.5, letterSpacing: 0.6, color: c.gray900),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'e.g. CKLUX-PRO-XXXX-XXXX',
              hintStyle: TextStyle(fontSize: 13.5, color: c.gray400),
              filled: true,
              fillColor: c.gray50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: border(c.gray200),
              disabledBorder: border(c.gray200),
              focusedBorder: border(AppColors.blue600),
            ),
          ),
          const SizedBox(height: 10),
          SettingsButton(
            label: _redeeming ? 'Applying…' : 'Apply code',
            loading: _redeeming,
            expand: true,
            onPressed: _apply,
          ),
        ],
      ),
    );
  }
}

/// Monthly / Annual ("2 months free") / Lifetime. Full width on a phone, the
/// badge on its own line under "Annual" so all three fit at 360dp.
class _CycleToggle extends StatelessWidget {
  const _CycleToggle({required this.value, required this.onChanged});

  final BillingCycle value;
  final ValueChanged<BillingCycle> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const tabs = [
      (BillingCycle.monthly, 'Monthly', null),
      (BillingCycle.annual, 'Annual', '2 months free'),
      (BillingCycle.lifetime, 'Lifetime', null),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.gray200),
      ),
      child: Row(
        children: [
          for (final (id, label, badge) in tabs)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 40,
                  decoration: BoxDecoration(
                    color: value == id ? AppColors.blue600 : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: value == id ? Colors.white : c.gray500,
                        ),
                      ),
                      if (badge != null)
                        Text(
                          badge,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: value == id ? const Color(0xFFDBEAFE) : AppColors.green600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Port of `PlanCard.jsx`. The promoted tier gets a blue ring + a "MOST
/// POPULAR" ribbon on its top border.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.cycle, required this.isCurrent, required this.onSelect});

  final Plan plan;
  final BillingCycle cycle;
  final bool isCurrent;
  final ValueChanged<Plan> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = plan.cycles.containsKey(cycle) ? cycle : BillingCycle.monthly;
    final price = plan.cycles[active]!.price;
    final (unit, note) = cycleCopy[active]!;

    final card = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: plan.highlight ? AppColors.blue600 : c.gray200, width: plan.highlight ? 2 : 1),
        boxShadow: plan.highlight
            ? [BoxShadow(color: AppColors.blue600.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            plan.name,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.gray900),
          ),
          const SizedBox(height: 2),
          Text(plan.tagline, style: TextStyle(fontSize: 12, color: c.gray500)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$$price',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1, color: c.gray900),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(unit, style: TextStyle(fontSize: 13, color: c.gray500)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(note, style: TextStyle(fontSize: 11.5, color: c.gray400)),
          const SizedBox(height: 16),
          for (final f in plan.features(active))
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(LucideIcons.check, size: 15, color: AppColors.blue600),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(f, style: TextStyle(fontSize: 13, color: c.gray700)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          SettingsButton(
            label: isCurrent ? 'Current plan' : 'Upgrade to ${plan.name}',
            expand: true,
            onPressed: isCurrent ? null : () => onSelect(plan),
          ),
        ],
      ),
    );

    if (!plan.highlight) return card;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: -11,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.blue600, borderRadius: BorderRadius.circular(20)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.sparkles, size: 11, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'MOST POPULAR',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
