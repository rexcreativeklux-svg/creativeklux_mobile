/// Port of `(components)/billing/billingData.js` — the active package →
/// subscription mapper, and the HANDCODED plans grid (there is no public plans
/// endpoint yet, so the tiers live here, as on the web).
library;

enum BillingCycle { monthly, annual, lifetime }

/// Unit after the price, and the small print under it (CYCLE_COPY).
const cycleCopy = <BillingCycle, (String, String)>{
  BillingCycle.monthly: ('/mo', 'billed monthly'),
  BillingCycle.annual: ('/yr', 'billed yearly — 12 months for the price of 10'),
  BillingCycle.lifetime: ('', 'one-time payment, perpetual access'),
};

/// The Current Subscription card's shape.
class Subscription {
  const Subscription({
    required this.planId,
    required this.planName,
    required this.tagline,
    required this.registeredOn,
    required this.renews,
    required this.status,
  });

  final Object? planId;
  final String planName;
  final String tagline;
  final String registeredOn;
  final String renews;
  final String status;

  /// Shown before `GET /package` answers (SUBSCRIPTION_FALLBACK).
  static const fallback = Subscription(
    planId: null,
    planName: 'Free plan',
    tagline: '3 projects per month included',
    registeredOn: '—',
    renews: 'Lifetime',
    status: 'Active',
  );

  /// `packageToSubscription(pkg)` — the `data` object of `GET /package` or
  /// `POST /apply-promotion-code`.
  factory Subscription.fromPackage(Map<String, dynamic>? pkg) {
    if (pkg == null) return fallback;
    return Subscription(
      planId: pkg['id'],
      planName: displayPlanName(pkg['name']?.toString()),
      tagline: _tagline(pkg),
      registeredOn: _formatRegistered(pkg['created_at']?.toString()),
      // No per-user renewal date is returned yet, so the plan reads as Lifetime.
      renews: 'Lifetime',
      status: pkg['status'] == 1 ? 'Active' : 'Inactive',
    );
  }
}

/// Keep the name reading naturally after "You're on the …" — append "plan"
/// only when it doesn't already carry a plan/package/tier word.
String displayPlanName(String? name) {
  if (name == null || name.isEmpty) return 'Current plan';
  return RegExp(r'plan|package|tier|subscription', caseSensitive: false).hasMatch(name) ? name : '$name plan';
}

/// `toLocaleString()` for an integer: 30000 → "30,000".
String thousands(num n) {
  final s = n.round().abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// "100 creatives, 10 brands & 30,000 AI tokens included" — only the quotas
/// that are set.
String _tagline(Map<String, dynamic> pkg) {
  final parts = <String>[];
  void add(Object? value, String label) {
    final n = num.tryParse('${value ?? ''}');
    if (n != null && n.isFinite && n > 0) parts.add('${thousands(n)} $label');
  }

  add(pkg['num_creatives'], 'creatives');
  add(pkg['num_brands'], 'brands');
  add(pkg['num_tokens'], 'AI tokens');

  if (parts.isEmpty) return 'Plan details';
  if (parts.length == 1) return '${parts.first} included';
  final last = parts.removeLast();
  return '${parts.join(', ')} & $last included';
}

String _ordinal(int n) {
  const suffixes = ['th', 'st', 'nd', 'rd'];
  final r = n % 100;
  // The web's `suffixes[(r - 20) % 10] || suffixes[r]` leans on JS's negative
  // modulo (undefined below 20); Dart's % is never negative, so branch on it.
  final i = r >= 20 ? (r - 20) % 10 : r;
  return '$n${i < 4 ? suffixes[i] : suffixes[0]}';
}

/// "28th December 2024", UTC so the day never shifts; "—" when missing.
String _formatRegistered(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toUtc();
  if (d == null) return '—';
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${_ordinal(d.day)} ${months[d.month - 1]} ${d.year}';
}

/// One cycle of a tier.
class PlanCycle {
  const PlanCycle(this.price, this.tokens, this.creatives, this.resells);

  final int price;
  final int tokens;
  final int creatives;
  final int resells;
}

/// One pricing tier. `shared` quotas are the same on every cycle.
class Plan {
  const Plan({
    required this.id,
    required this.name,
    required this.tagline,
    required this.highlight,
    required this.brands,
    required this.teams,
    required this.integrations,
    required this.copilots,
    required this.storage,
    required this.cycles,
  });

  final String id;
  final String name;
  final String tagline;

  /// The promoted tier ("Most popular").
  final bool highlight;
  final int brands;
  final int teams;
  final int integrations;
  final int copilots;
  final int storage;
  final Map<BillingCycle, PlanCycle> cycles;

  /// `quotaFeatures` — tokens and creatives are PER MONTH on every package,
  /// lifetime included. Resells are agency-only, so the line drops at zero.
  List<String> features(BillingCycle cycle) {
    final q = cycles[cycle] ?? cycles[BillingCycle.monthly]!;
    String count(int n, String noun) => '${thousands(n)} $noun${n == 1 ? '' : 's'}';
    return [
      '${thousands(q.tokens)} AI tokens / month',
      '${thousands(q.creatives)} creatives / month',
      count(brands, 'brand'),
      count(teams, 'team member'),
      count(integrations, 'integration'),
      count(copilots, 'copilot'),
      '$storage GB storage',
      if (q.resells > 0) count(q.resells, 'resell'),
    ];
  }
}

/// The nine packages — three tiers × three cycles — mirroring the admin
/// Packages form (duration 30 / 365 / 36500 days).
const plans = <Plan>[
  Plan(
    id: 'starter',
    name: 'Starter',
    tagline: 'For solo creators getting started',
    highlight: false,
    brands: 1,
    teams: 1,
    integrations: 3,
    copilots: 1,
    storage: 5,
    cycles: {
      BillingCycle.monthly: PlanCycle(15, 45000, 50, 0),
      BillingCycle.annual: PlanCycle(150, 45000, 50, 0),
      BillingCycle.lifetime: PlanCycle(59, 15000, 20, 0),
    },
  ),
  Plan(
    id: 'growth',
    name: 'Growth',
    tagline: 'For growing brands and small teams',
    highlight: true,
    brands: 5,
    teams: 5,
    integrations: 10,
    copilots: 5,
    storage: 25,
    cycles: {
      BillingCycle.monthly: PlanCycle(39, 110000, 150, 0),
      BillingCycle.annual: PlanCycle(390, 110000, 150, 0),
      BillingCycle.lifetime: PlanCycle(129, 36000, 50, 0),
    },
  ),
  Plan(
    id: 'agency',
    name: 'Agency',
    tagline: 'For agencies with their own clients',
    highlight: false,
    brands: 20,
    teams: 20,
    integrations: 25,
    copilots: 20,
    storage: 100,
    cycles: {
      BillingCycle.monthly: PlanCycle(89, 250000, 400, 25),
      BillingCycle.annual: PlanCycle(890, 250000, 400, 25),
      BillingCycle.lifetime: PlanCycle(249, 60000, 100, 10),
    },
  ),
];
