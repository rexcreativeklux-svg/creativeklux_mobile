// The text of the public legal pages, word for word from the web's
// `(legal)/privacy/page.jsx` and `(legal)/terms/page.jsx`. Change it there
// and here together — they are the same documents.

/// A block inside a section: a paragraph, a sub-heading or a bullet list.
sealed class LegalBlock {
  const LegalBlock();
}

/// A paragraph. A `{email}` token renders as the tappable support address
/// (the web's mailto link).
class LegalP extends LegalBlock {
  const LegalP(this.text);
  final String text;
}

class LegalSub extends LegalBlock {
  const LegalSub(this.text);
  final String text;
}

class LegalBullets extends LegalBlock {
  const LegalBullets(this.items);
  final List<String> items;
}

class LegalSection {
  const LegalSection(this.id, this.tocLabel, this.title, this.blocks);
  final String id;

  /// The table-of-contents label (shorter than the title for some sections).
  final String tocLabel;
  final String title;
  final List<LegalBlock> blocks;
}

class LegalDocument {
  const LegalDocument({required this.title, required this.updated, required this.summary, required this.sections});
  final String title;
  final String updated;
  final String summary;
  final List<LegalSection> sections;
}

const legalEmail = 'support@creativeklux.com';

const privacyPolicy = LegalDocument(
  title: 'Privacy Policy',
  updated: 'July 17, 2026',
  summary: 'This Privacy Policy explains what information Creative Klux collects when you use our websites, applications, and APIs, how we use and protect that information, when we share it, and the choices and rights you have. We designed Creative Klux to help you create — and to handle your data responsibly while doing so.',
  sections: [
    LegalSection('overview', '1. Overview', '1. Overview', [
      LegalP(
        'Creative Klux (“we,” “us,” or “our”) provides an all-in-one creative platform with AI content generation, design tools, templates, client dashboards, analytics, and social publishing. This policy applies to the Services we offer at app.creativeklux.com and our related APIs and infrastructure. By using the Services, you agree to the practices described here.',
      ),
    ]),
    LegalSection('collect', '2. Information we collect', '2. Information we collect', [
      LegalSub('Information you provide'),
      LegalBullets([
        'Account details: your name, email address, and password (stored in hashed form), plus any license code you enter.',
        'Content you create or upload: prompts, images, video, audio, brand assets, templates, and generated Output.',
        'Billing information: plan selection and payment details, which are processed by our payment providers (we do not store full card numbers).',
        'Communications: messages you send to support and any feedback you share.',
      ]),
      LegalSub('Information collected automatically'),
      LegalBullets([
        'Usage data: features used, actions taken, and interactions with the Services.',
        'Device & log data: IP address, browser type, device identifiers, and timestamps.',
        'Cookies and local storage: used to keep you signed in, remember preferences, and operate certain on-device features.',
      ]),
      LegalSub('Information from connected platforms'),
      LegalP(
        'When you connect a social or advertising account (such as YouTube, TikTok, Meta, X, or Pinterest), we receive the access tokens and account information needed to provide the features you request, such as publishing posts or retrieving analytics.',
      ),
    ]),
    LegalSection('use', '3. How we use information', '3. How we use information', [
      LegalP('We use the information we collect to:'),
      LegalBullets([
        'Provide, operate, secure, and maintain the Services and your account.',
        'Generate the AI Output and designs you request, and store your files so you can access them.',
        'Publish content and retrieve analytics from platforms you connect.',
        'Process payments, manage trials and licenses, and prevent fraud and abuse.',
        'Communicate with you about your account, updates, security, and support requests.',
        'Understand usage and improve the performance, reliability, and features of the Services.',
        'Comply with legal obligations and enforce our Terms of Service.',
      ]),
    ]),
    LegalSection('ai', '4. AI processing of content', '4. AI processing of your content', [
      LegalP(
        'To power AI features, the prompts and content you submit may be sent to third-party AI providers and to our own on-device or cloud processing components solely to generate the Output you request. We do not sell your content, and we do not use it to train third-party foundation models except where a provider’s terms require it for delivering the feature. Where feasible, some processing runs directly in your browser so that your content is not transmitted to our servers.',
      ),
    ]),
    LegalSection('connected', '5. Connected accounts', '5. Connected accounts & integrations', [
      LegalP(
        'Access tokens for connected platforms are used only to perform the actions you authorize, such as posting or reading analytics. You can revoke access at any time by disconnecting the platform in your account settings or through the platform’s own security controls. Disconnecting stops future access but does not undo actions already taken at your request.',
      ),
    ]),
    LegalSection('share', '6. How we share information', '6. How we share information', [
      LegalP('We do not sell your personal information. We share information only in the following circumstances:'),
      LegalBullets([
        'Service providers: cloud hosting and storage, content delivery, AI providers, analytics, and payment processors that perform services on our behalf under confidentiality obligations.',
        'Connected platforms: the third-party services you choose to connect and publish to, according to your instructions.',
        'Legal and safety: when required by law, legal process, or to protect the rights, safety, and security of our users, the public, or Creative Klux.',
        'Business transfers: in connection with a merger, acquisition, or sale of assets, subject to this policy.',
      ]),
    ]),
    LegalSection('cookies', '7. Cookies & storage', '7. Cookies & local storage', [
      LegalP(
        'We use cookies and browser local storage to keep you signed in, remember preferences, run certain in-browser features, and understand how the Services are used. You can control cookies through your browser settings; disabling some cookies may affect functionality such as staying logged in.',
      ),
    ]),
    LegalSection('retention', '8. Data retention', '8. Data retention', [
      LegalP(
        'We keep your information for as long as your account is active or as needed to provide the Services. We may retain certain information after account closure where necessary to comply with legal obligations, resolve disputes, prevent abuse, and enforce our agreements. When information is no longer needed, we delete or anonymize it.',
      ),
    ]),
    LegalSection('security', '9. Data security', '9. Data security', [
      LegalP(
        'We use technical and organizational measures designed to protect your information, including encryption in transit, hashed passwords, and access controls. No method of transmission or storage is completely secure, however, so we cannot guarantee absolute security. Please help protect your account by using a strong, unique password and keeping your credentials confidential.',
      ),
    ]),
    LegalSection('rights', '10. Your rights & choices', '10. Your rights & choices', [
      LegalP('Depending on your location, you may have rights over your personal information, including the right to:'),
      LegalBullets([
        'Access, correct, or update the information we hold about you.',
        'Delete your account and associated personal information.',
        'Object to or restrict certain processing, and withdraw consent where processing is based on consent.',
        'Request a copy of your information in a portable format.',
        'Lodge a complaint with your local data protection authority.',
      ]),
      LegalP(
        'You can exercise many of these rights directly in your account settings, or by contacting us at {email}. We will respond in accordance with applicable law.',
      ),
    ]),
    LegalSection('transfers', '11. International transfers', '11. International data transfers', [
      LegalP(
        'Creative Klux operates globally, and your information may be processed and stored in countries other than your own, including where our service providers operate. Where required, we take steps to ensure appropriate safeguards are in place for such transfers.',
      ),
    ]),
    LegalSection('children', '12. Children’s privacy', '12. Children’s privacy', [
      LegalP(
        'The Services are not directed to children under 18, and we do not knowingly collect personal information from them. If you believe a child has provided us with personal information, please contact us so we can take appropriate action.',
      ),
    ]),
    LegalSection('changes', '13. Changes to this policy', '13. Changes to this policy', [
      LegalP(
        'We may update this Privacy Policy from time to time. When we make material changes, we will update the “Last updated” date above and, where appropriate, provide additional notice. We encourage you to review this policy periodically.',
      ),
    ]),
    LegalSection('contact', '14. Contact us', '14. Contact us', [
      LegalP('If you have questions about this Privacy Policy or how we handle your information, please contact us:'),
      LegalSub('Creative Klux'),
      LegalP('Email: {email}'),
    ]),
  ],
);

const termsOfService = LegalDocument(
  title: 'Terms of Service',
  updated: 'July 17, 2026',
  summary: 'These Terms of Service (the “Terms”) form a binding agreement between you and Creative Klux and govern your access to and use of our websites, applications, APIs, and related services (together, the “Services”). Please read them carefully — by creating an account or using the Services, you agree to these Terms.',
  sections: [
    LegalSection('acceptance', '1. Acceptance of terms', '1. Acceptance of terms', [
      LegalP(
        'By accessing or using Creative Klux — including the application at app.creativeklux.com and any associated tools, APIs, and content — you confirm that you have read, understood, and agree to be bound by these Terms and by our Privacy Policy, which is incorporated here by reference. If you are using the Services on behalf of a company or other organization, you represent that you have authority to bind that organization, and “you” refers to that organization.',
      ),
      LegalP('If you do not agree to these Terms, you must not access or use the Services.'),
    ]),
    LegalSection('accounts', '2. Eligibility & accounts', '2. Eligibility & accounts', [
      LegalP(
        'You must be at least 18 years old, or the age of legal majority in your jurisdiction, to use Creative Klux. To access most features you must create an account and verify your email address.',
      ),
      LegalBullets([
        'You are responsible for providing accurate information and keeping your account details up to date.',
        'You are responsible for safeguarding your password and for all activity that occurs under your account.',
        'Notify us promptly at support@creativeklux.com if you suspect any unauthorized use of your account.',
        'One person or entity may not maintain more than one free trial account.',
      ]),
    ]),
    LegalSection('plans', '3. Trials, licenses & plans', '3. Trials, licenses & plans', [
      LegalP(
        'Creative Klux offers a free trial as well as paid plans and license-based access. When you register without a license code, you may be granted a free trial account (currently 7 days). Continued access after a trial or license period may require a paid plan or a valid license code.',
      ),
      LegalBullets([
        'Trial access is provided “as is” and may be modified or discontinued at any time.',
        'License codes are issued for a specific account and plan and may not be shared, resold, or transferred except where we expressly permit reselling through our program.',
        'We may change plan features, limits, and pricing; where required, we will give you reasonable notice before changes take effect.',
      ]),
    ]),
    LegalSection('acceptable-use', '4. Acceptable use', '4. Acceptable use', [
      LegalP(
        'You agree to use the Services lawfully and responsibly. You must not, and must not permit anyone else to:',
      ),
      LegalBullets([
        'Create, upload, or distribute content that is unlawful, infringing, defamatory, hateful, harassing, deceptive, or sexually exploitative — particularly any content involving minors.',
        'Infringe the intellectual property, privacy, publicity, or other rights of any person or entity, including generating imitations of a real person or brand without authorization.',
        'Attempt to reverse engineer, decompile, scrape, or gain unauthorized access to the Services, our AI models, or our infrastructure.',
        'Interfere with, overload, or disrupt the Services, including by circumventing usage limits or security measures.',
        'Use the Services to generate spam, malware, or content that violates the rules of any connected third-party platform.',
        'Resell or provide the Services to third parties except through a reselling arrangement we authorize in writing.',
      ]),
      LegalP(
        'We may investigate suspected violations and may suspend or terminate access for conduct we reasonably believe breaches these Terms or harms other users, third parties, or Creative Klux.',
      ),
    ]),
    LegalSection('your-content', '5. Your content', '5. Your content', [
      LegalP(
        '“Your Content” means any text, images, audio, video, prompts, brand assets, and other materials you upload to or create with the Services. You retain all ownership rights you hold in Your Content.',
      ),
      LegalP(
        'You grant Creative Klux a worldwide, non-exclusive, royalty-free license to host, store, reproduce, process, and display Your Content solely as needed to operate, secure, maintain, and improve the Services and to provide them to you — for example, to store files on our content delivery network and to send content to the AI providers that power a feature you use. This license ends when Your Content is deleted, except where retention is required to comply with law or to resolve disputes.',
      ),
      LegalP(
        'You are solely responsible for Your Content and represent that you have all rights necessary to submit it and to grant the license above.',
      ),
    ]),
    LegalSection('ai-content', '6. AI-generated content', '6. AI-generated content', [
      LegalP(
        'Creative Klux includes AI-powered features that generate images, video, audio, voiceovers, and text based on your inputs (“Output”). You should be aware of the following:',
      ),
      LegalBullets([
        'Output is generated automatically and may be inaccurate, incomplete, or unintentionally similar to existing works. You are responsible for reviewing Output before relying on or publishing it.',
        'As between you and Creative Klux, you own the Output you create through your account, to the extent permitted by applicable law and by the terms of the underlying AI providers.',
        'You must not use AI features to create content that is illegal, deceptive, or that misappropriates the identity or likeness of others.',
        'AI Output is not professional advice (legal, medical, financial, or otherwise) and should not be treated as such.',
      ]),
    ]),
    LegalSection('integrations', '7. Third-party integrations', '7. Third-party integrations & platforms', [
      LegalP(
        'The Services let you connect and publish to third-party platforms such as YouTube, TikTok, Meta (Facebook and Instagram), X, and Pinterest. When you connect an account, you authorize Creative Klux to access and use that platform on your behalf as needed to provide the features you request.',
      ),
      LegalBullets([
        'Your use of each connected platform is also governed by that platform’s own terms and policies, and you are responsible for complying with them.',
        'We are not responsible for the availability, accuracy, or actions of third-party platforms, and they may change or revoke access at any time.',
        'You can disconnect a platform at any time from your account settings.',
      ]),
    ]),
    LegalSection('ip', '8. Intellectual property', '8. Intellectual property', [
      LegalP(
        'The Services, including our software, design, branding, templates, and underlying technology, are owned by Creative Klux and its licensors and are protected by intellectual property laws. Except for the rights expressly granted to you in these Terms, we reserve all rights in and to the Services.',
      ),
      LegalP(
        'Templates and stock assets we provide may be used within the Services to create your own designs, but you may not extract, redistribute, or resell them as standalone assets.',
      ),
    ]),
    LegalSection('billing', '9. Billing & refunds', '9. Billing & refunds', [
      LegalP(
        'Paid plans are billed in advance on the cycle shown at checkout. Unless otherwise stated or required by law:',
      ),
      LegalBullets([
        'Fees are charged through our third-party payment processors, and you authorize us to charge your selected payment method for the applicable fees and taxes.',
        'Subscriptions renew automatically until cancelled; you can cancel at any time and your plan will remain active until the end of the current billing period.',
        'Fees already paid are generally non-refundable except where required by applicable law or expressly stated in a plan’s terms.',
        'If a payment fails, we may suspend or downgrade your access until the balance is resolved.',
      ]),
    ]),
    LegalSection('termination', '10. Termination', '10. Termination', [
      LegalP(
        'You may stop using the Services and delete your account at any time. We may suspend or terminate your access, with or without notice, if we reasonably believe you have violated these Terms, if required by law, or to protect the Services or other users.',
      ),
      LegalP(
        'Upon termination, your right to use the Services ends immediately. We may delete Your Content after a reasonable period, so you should keep your own copies of anything you wish to retain. Provisions that by their nature should survive termination (including ownership, disclaimers, limitation of liability, and indemnification) will survive.',
      ),
    ]),
    LegalSection('disclaimers', '11. Disclaimers', '11. Disclaimers', [
      LegalP(
        'The Services are provided “as is” and “as available,” without warranties of any kind, whether express, implied, or statutory, including implied warranties of merchantability, fitness for a particular purpose, and non-infringement. We do not warrant that the Services will be uninterrupted, error-free, secure, or that any Output will meet your expectations. Your use of the Services is at your own risk.',
      ),
    ]),
    LegalSection('liability', '12. Limitation of liability', '12. Limitation of liability', [
      LegalP(
        'To the maximum extent permitted by law, Creative Klux and its officers, employees, and suppliers will not be liable for any indirect, incidental, special, consequential, or punitive damages, or for any loss of profits, revenue, data, or goodwill, arising out of or related to your use of the Services.',
      ),
      LegalP(
        'To the maximum extent permitted by law, our total aggregate liability for any claim relating to the Services will not exceed the greater of the amount you paid us for the Services in the twelve months before the event giving rise to the claim, or one hundred US dollars (USD 100).',
      ),
    ]),
    LegalSection('indemnification', '13. Indemnification', '13. Indemnification', [
      LegalP(
        'You agree to indemnify and hold harmless Creative Klux and its affiliates from any claims, damages, liabilities, and expenses (including reasonable legal fees) arising out of Your Content, your use of the Services, your violation of these Terms, or your violation of any law or the rights of a third party.',
      ),
    ]),
    LegalSection('changes', '14. Changes to these terms', '14. Changes to these terms', [
      LegalP(
        'We may update these Terms from time to time. When we make material changes, we will update the “Last updated” date above and, where appropriate, provide additional notice. Your continued use of the Services after changes take effect constitutes acceptance of the revised Terms.',
      ),
    ]),
    LegalSection('governing-law', '15. Governing law', '15. Governing law', [
      LegalP(
        'These Terms are governed by the laws applicable at Creative Klux’s principal place of business, without regard to conflict-of-laws rules. Any disputes will be subject to the exclusive jurisdiction of the competent courts in that location, unless mandatory local law provides otherwise.',
      ),
    ]),
    LegalSection('contact', '16. Contact us', '16. Contact us', [
      LegalP('If you have questions about these Terms, please contact us:'),
      LegalSub('Creative Klux'),
      LegalP('Email: {email}'),
    ]),
  ],
);
