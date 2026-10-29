import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import '../shell/widgets/app_top_bar.dart';

class _Faq {
  const _Faq(this.id, this.question, this.answer, this.category, {this.popular = false});
  final int id;
  final String question;
  final String answer;
  final String category;
  final bool popular;
}

const _categories = <(String, IconData)>[
  ('All', LucideIcons.circleQuestionMark),
  ('Getting Started', LucideIcons.rocket),
  ('Account & Billing', LucideIcons.creditCard),
  ('Features', LucideIcons.zap),
  ('Technical', LucideIcons.settings),
  ('Security', LucideIcons.shield),
];

const _faqs = <_Faq>[
  _Faq(
    1,
    'How do I get started with Creative Klux?',
    'Getting started is easy! Sign up for a free account, complete the onboarding tutorial, and start creating. You can choose from templates or start from scratch using our AI-powered tools.',
    'Getting Started',
    popular: true,
  ),
  _Faq(
    2,
    'What payment methods do you accept?',
    'We accept all major credit cards (Visa, MasterCard, American Express), PayPal, and bank transfers for enterprise accounts. All payments are processed securely through our encrypted payment gateway.',
    'Account & Billing',
    popular: true,
  ),
  _Faq(
    3,
    'Can I cancel my subscription anytime?',
    "Yes, you can cancel your subscription at any time from your account settings. You'll continue to have access until the end of your billing period. No cancellation fees or hidden charges.",
    'Account & Billing',
    popular: true,
  ),
  _Faq(
    4,
    'What AI features are included?',
    'Creative Klux includes text-to-image generation, text-to-video creation, image variations, background removal, AI writing assistant, script-to-video, and smart design suggestions. All AI features are included in paid plans.',
    'Features',
    popular: true,
  ),
  _Faq(
    5,
    'How many projects can I create?',
    'Free accounts can create up to 3 projects. Pro accounts have unlimited projects. Each project can contain multiple assets, designs, and variations.',
    'Features',
  ),
  _Faq(
    6,
    'Can I collaborate with my team?',
    'Yes! Team and Enterprise plans include collaboration features like shared workspaces, comments, version history, and role-based permissions. You can invite unlimited team members.',
    'Features',
    popular: true,
  ),
  _Faq(
    7,
    'What file formats can I export?',
    'You can export your creations in PNG, JPG, SVG, PDF, MP4, and GIF formats. We also support high-resolution exports for print materials.',
    'Technical',
  ),
  _Faq(
    8,
    'Is my data secure?',
    "Absolutely. We use bank-level 256-bit SSL encryption for all data transmission. Your files are stored on secure servers with regular backups. We're GDPR compliant and never share your data with third parties.",
    'Security',
    popular: true,
  ),
  _Faq(
    9,
    'Do you offer refunds?',
    "Yes, we offer a 30-day money-back guarantee for all paid plans. If you're not satisfied, contact our support team within 30 days of purchase for a full refund.",
    'Account & Billing',
  ),
  _Faq(
    10,
    'How do I upgrade my plan?',
    "You can upgrade your plan anytime from the Billing section in your account settings. The upgrade takes effect immediately, and you'll only pay the prorated difference.",
    'Account & Billing',
  ),
  _Faq(
    11,
    'Can I use Creative Klux offline?',
    "Creative Klux is a cloud-based platform that requires an internet connection. However, we're working on an offline mode that will be available soon for desktop users.",
    'Technical',
  ),
  _Faq(
    12,
    'What browsers are supported?',
    'Creative Klux works best on the latest versions of Chrome, Firefox, Safari, and Edge. We recommend using Chrome for the best experience with AI features.',
    'Technical',
  ),
];

const _supportEmail = 'support@creativeklux.com';

/// /help/support — port of `(dashboard)/(pages)/help/support/page.jsx`:
/// search, contact methods, Popular Questions, Browse by Category, the full
/// FAQ list and Additional Resources. All of it is static content, as on the
/// web (the ticket form there is commented out, so there's no endpoint).
///
/// The web's contact and resource buttons do nothing. Here:
///   · "Send Email" opens a mail to support@creativeklux.com (the address
///     the card shows, and the one the legal pages use);
///   · "Video Tutorials" opens /help/tutorial-videos;
///   · Live Chat, Call Us and the other resources say they aren't available
///     yet — the phone number on the card is a placeholder, so it isn't dialled.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  String _query = '';
  String _category = 'All';
  int? _expanded;

  List<_Faq> get _filtered {
    final q = _query.toLowerCase();
    return [
      for (final f in _faqs)
        if ((f.question.toLowerCase().contains(q) || f.answer.toLowerCase().contains(q)) &&
            (_category == 'All' || f.category == _category))
          f,
    ];
  }

  void _toggle(int id) => setState(() => _expanded = _expanded == id ? null : id);

  Future<void> _email() async {
    final ok = await launchUrl(Uri(scheme: 'mailto', path: _supportEmail));
    if (!ok) Toast.error("Couldn't open your email app.", description: _supportEmail);
  }

  void _notYet(String what) => Toast.info('$what isn’t available yet.');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final filtered = _filtered;

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.gray900),
      ),
    );

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const AppTopBar(title: 'Support', showBack: true),
          Expanded(
            child: ColoredBox(
              color: c.page,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 32 + MediaQuery.paddingOf(context).bottom),
                children: [
                  // Header
                  Icon(LucideIcons.circleQuestionMark, size: 40, color: AppColors.blue600),
                  const SizedBox(height: 10),
                  Text(
                    'How can we help you?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.gray900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Search our knowledge base or get in touch with our support team',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: c.gray600),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 44,
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'Search for answers...',
                        prefixIcon: Icon(LucideIcons.search, size: 18, color: c.gray400),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Contact methods
                  _ContactCard(
                    icon: LucideIcons.messageCircle,
                    color: AppColors.blue500,
                    title: 'Live Chat',
                    description: 'Chat with our support team',
                    availability: 'Mon-Fri, 9 AM - 6 PM EST',
                    action: 'Start Chat',
                    onTap: () => _notYet('Live chat'),
                  ),
                  _ContactCard(
                    icon: LucideIcons.mail,
                    color: const Color(0xFFAD46FF),
                    title: 'Email Support',
                    description: _supportEmail,
                    availability: 'Response within 24 hours',
                    action: 'Send Email',
                    onTap: _email,
                  ),
                  _ContactCard(
                    icon: LucideIcons.phone,
                    color: const Color(0xFF00C950),
                    title: 'Phone Support',
                    description: '+1 (555) 123-4567',
                    availability: 'Enterprise customers only',
                    action: 'Call Us',
                    onTap: () => _notYet('Phone support'),
                  ),
                  const SizedBox(height: 20),

                  // Popular questions
                  heading('Popular Questions'),
                  for (final f in _faqs.where((f) => f.popular))
                    _FaqCard(faq: f, expanded: _expanded == f.id, onTap: () => _toggle(f.id), popularStyle: true),
                  const SizedBox(height: 20),

                  // Category filter
                  heading('Browse by Category'),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final (name, icon) in _categories)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _CategoryChip(
                              label: name,
                              icon: icon,
                              active: _category == name,
                              onTap: () => setState(() => _category = name),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // All questions
                  heading(_category == 'All' ? 'All Questions' : '$_category Questions'),
                  if (filtered.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: c.gray200),
                      ),
                      child: Column(
                        children: [
                          Icon(LucideIcons.circleAlert, size: 44, color: c.gray300),
                          const SizedBox(height: 12),
                          Text('No questions found', style: TextStyle(fontSize: 15, color: c.gray500)),
                          const SizedBox(height: 4),
                          Text(
                            'Try adjusting your search or filters',
                            style: TextStyle(fontSize: 12.5, color: c.gray400),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final f in filtered) _FaqCard(faq: f, expanded: _expanded == f.id, onTap: () => _toggle(f.id)),
                  const SizedBox(height: 24),

                  // Resources
                  heading('Additional Resources'),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.95,
                    children: [
                      _ResourceCard(
                        icon: LucideIcons.book,
                        color: const Color(0xFFF54900),
                        title: 'Documentation',
                        description: 'Comprehensive guides and API docs',
                        onTap: () => _notYet('Documentation'),
                      ),
                      _ResourceCard(
                        icon: LucideIcons.video,
                        color: AppColors.red600,
                        title: 'Video Tutorials',
                        description: 'Step-by-step video guides',
                        onTap: () => context.push('/help/tutorial-videos'),
                      ),
                      _ResourceCard(
                        icon: LucideIcons.users,
                        color: AppColors.blue600,
                        title: 'Community Forum',
                        description: 'Connect with other users',
                        onTap: () => _notYet('The community forum'),
                      ),
                      _ResourceCard(
                        icon: LucideIcons.fileText,
                        color: AppColors.green600,
                        title: 'Blog & Updates',
                        description: 'Latest news and tips',
                        onTap: () => _notYet('The blog'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.availability,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String availability;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.gray900),
                    ),
                    const SizedBox(height: 2),
                    Text(description, style: TextStyle(fontSize: 13, color: c.gray600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(LucideIcons.clock, size: 12, color: c.gray500),
              const SizedBox(width: 6),
              Text(availability, style: TextStyle(fontSize: 12, color: c.gray500)),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
              foregroundColor: c.gray800,
              side: BorderSide(color: c.gray200),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
            ),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

/// A question that opens to its answer. Popular cards lead with a help mark
/// and indent the answer; the full list shows the category badge instead.
class _FaqCard extends StatelessWidget {
  const _FaqCard({required this.faq, required this.expanded, required this.onTap, this.popularStyle = false});
  final _Faq faq;
  final bool expanded;
  final VoidCallback onTap;
  final bool popularStyle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.gray200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (popularStyle) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(LucideIcons.circleQuestionMark, size: 17, color: AppColors.blue600),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        faq.question,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: popularStyle ? c.gray800 : c.gray900,
                        ),
                      ),
                      if (!popularStyle) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.blue500.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            faq.category,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.blue500),
                          ),
                        ),
                      ],
                      if (expanded) ...[
                        const SizedBox(height: 10),
                        Text(
                          faq.answer,
                          style: TextStyle(fontSize: 13, height: 1.5, color: popularStyle ? c.gray500 : c.gray600),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18, color: c.gray400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.icon, required this.active, required this.onTap});
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = active ? Colors.white : c.gray700;
    return Material(
      color: active ? AppColors.blue600 : c.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? AppColors.blue600 : c.gray200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.gray200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.gray900),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  description,
                  overflow: TextOverflow.fade,
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: c.gray600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
