import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import 'settings_widgets.dart';

/// Port of `(settings)/custom-domain/page.jsx` — the integration rules, the
/// connect form and the domains table.
///
/// ⚠️ MOCK on the web: the website list is hardcoded and Connect POSTs to
/// `/api/connect-domain`, a Next route that doesn't exist (the request fails
/// and only logs). There's no backend endpoint to call, so Connect says it
/// isn't available yet and the table stays empty — the state every web user
/// sees.
///
/// Two copy fixes: the web heading repeats the Resell page's ("Resell
/// accounts"), and rule 3 says "return to Weviy" — another product's name.
class CustomDomainScreen extends StatefulWidget {
  const CustomDomainScreen({super.key});

  @override
  State<CustomDomainScreen> createState() => _CustomDomainScreenState();
}

const _websites = [
  ('website1', 'My Portfolio Site'),
  ('website2', 'Business Landing Page'),
  ('website3', 'E-commerce Store'),
];

class _CustomDomainScreenState extends State<CustomDomainScreen> {
  String? _website;
  final _domain = TextEditingController();

  @override
  void initState() {
    super.initState();
    _domain.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  void _connect() {
    FocusScope.of(context).unfocus();
    Toast.info("Custom domains aren't available yet.");
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canConnect = _website != null && _domain.text.trim().isNotEmpty;

    Widget rule(String title, List<String> lines, {Widget? extra}) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.gray900),
          ),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(l, style: TextStyle(fontSize: 13, color: c.gray700, height: 1.45)),
            ),
          ?extra,
        ],
      ),
    );

    Widget nameserver(String text) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: c.blueTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.blue600.withValues(alpha: 0.25)),
      ),
      child: SelectableText(
        text,
        style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.blue600),
      ),
    );

    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color),
    );
    final decoration = InputDecoration(
      isDense: true,
      filled: true,
      fillColor: c.surface,
      hintStyle: TextStyle(fontSize: 13.5, color: c.gray400),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: border(c.gray300),
      focusedBorder: border(AppColors.blue600),
    );

    return SettingsScaffold(
      children: [
        const SettingsHeader('Custom Domain'),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  'Custom Domain Integration Rules',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: c.gray900),
                ),
              ),
              rule('1. Change Nameservers', const [
                "*Go to your domain registrar (e.g., GoDaddy, Namecheap, etc.), and edit your domain's DNS "
                    "settings and change your domain's nameservers to",
              ], extra: Column(children: [nameserver('website.com'), nameserver('website.com')])),
              rule('2. Allow DNS Propagation Time', const [
                '*Keep in mind that DNS changes may take up to 48 hours to propagate, although they often '
                    'happen much quicker.',
              ]),
              rule('3. Verify & Connect Your Domain', const [
                '*After saving your DNS settings, return to Creative Klux, enter your domain and click on '
                    '"Connect Domain"',
                '*We will automatically detect the domain, link it to your site, and install an SSL certificate.',
              ]),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Website Address',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.gray900),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _website,
          isExpanded: true,
          hint: Text('Select Website', style: TextStyle(fontSize: 13.5, color: c.gray400)),
          icon: Icon(LucideIcons.chevronDown, size: 18, color: c.gray400),
          style: TextStyle(fontSize: 13.5, color: c.gray800),
          dropdownColor: c.surface,
          decoration: decoration,
          items: [for (final (value, label) in _websites) DropdownMenuItem(value: value, child: Text(label))],
          onChanged: (v) => setState(() => _website = v),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _domain,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: TextStyle(fontSize: 13.5, color: c.gray900),
          decoration: decoration.copyWith(hintText: 'Domain name'),
        ),
        const SizedBox(height: 12),
        SettingsButton(label: 'Connect Domain', expand: true, onPressed: canConnect ? _connect : null),
        const SizedBox(height: 24),
        const SettingsSearchField(onChanged: _noop, placeholder: 'Search domains...'),
        const SizedBox(height: 12),
        // Nothing can be added (see the class note), so the table is always
        // its empty state — the web's "No data available in table".
        Container(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.gray200),
          ),
          child: Text(
            'No data available in table',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.gray500),
          ),
        ),
      ],
    );
  }
}

void _noop(String _) {}
