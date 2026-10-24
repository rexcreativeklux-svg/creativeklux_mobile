import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/design/design_canvas.dart';
import '../../core/design/design_renderer.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import '../brand/brand.dart';
import 'publish_api.dart';

/// What gets published — the fields the web's PublishModal reads off `creative`.
class PublishCreative {
  const PublishCreative({
    required this.name,
    required this.category,
    this.copy = const {},
    this.image,
    this.isVideo = false,
    this.canvas,
    this.elements = const [],
    this.scraive = false,
  });

  final String name;

  /// "ads" → ad platforms, "all" / "social_ads" → both, anything else → social.
  final String category;
  final Map<String, dynamic> copy;

  /// An already-hosted file (a Magic result, or a saved design's thumbnail).
  /// Without one, [canvas] + [elements] are painted and uploaded first.
  final String? image;
  final bool isVideo;
  final Map<String, dynamic>? canvas;
  final List<dynamic> elements;
  final bool scraive;
}

/// Open the publish sheet (port of `(components)/PublishModal.jsx`).
/// `startInSchedule` jumps straight into Facebook's compose view with the
/// schedule picker open, like the web's Schedule button.
Future<void> showPublishSheet(BuildContext context, PublishCreative creative, {bool startInSchedule = false}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => _PublishSheet(creative: creative, startInSchedule: startInSchedule),
  );
}

// ── Platform catalog ───────────────────────────────────────────────────────────
// Lucide has no brand logos, so each tile is the platform's colour with a
// neutral glyph (see CLAUDE.md).
class _Platform {
  const _Platform(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

const _platforms = <String, _Platform>{
  'facebook': _Platform('Facebook Page', Color(0xFF1877F2), LucideIcons.thumbsUp),
  'instagram': _Platform('Instagram Business', Color(0xFFE1306C), LucideIcons.camera),
  'tiktok': _Platform('TikTok', Color(0xFF010101), LucideIcons.music),
  'twitter': _Platform('X / Twitter', Color(0xFF14171A), LucideIcons.atSign),
  'linkedin': _Platform('LinkedIn', Color(0xFF0A66C2), LucideIcons.briefcase),
  'youtube': _Platform('YouTube', Color(0xFFFF0000), LucideIcons.play),
  'pinterest': _Platform('Pinterest', Color(0xFFE60023), LucideIcons.pin),
  'meta_ads': _Platform('Meta Ads Manager', Color(0xFF0668E1), LucideIcons.megaphone),
  'google_ads': _Platform('Google Ads', Color(0xFF4285F4), LucideIcons.search),
  'tiktok_ads': _Platform('TikTok Ads', Color(0xFF010101), LucideIcons.music),
  'snapchat_ads': _Platform('Snapchat Ads', Color(0xFFFFC400), LucideIcons.ghost),
  'pinterest_ads': _Platform('Pinterest Ads', Color(0xFFE60023), LucideIcons.pin),
};

const _socialOrder = ['facebook', 'instagram', 'tiktok', 'twitter', 'linkedin', 'youtube', 'pinterest'];
// LinkedIn Ads is disabled on the web (needs LinkedIn Advertising API approval).
const _adsOrder = ['meta_ads', 'google_ads', 'tiktok_ads', 'snapchat_ads', 'pinterest_ads'];

List<String> _platformsFor(String category) => switch (category.toLowerCase()) {
  'ads' => _adsOrder,
  'all' || 'social_ads' => [..._socialOrder, ..._adsOrder],
  _ => _socialOrder,
};

const _adGoals = [
  ('awareness', 'Awareness — more people see it'),
  ('traffic', 'Traffic — visit your website'),
  ('engagement', 'Engagement — likes / comments / messages'),
];

const _adCountries = [
  ('NG', 'Nigeria'),
  ('US', 'United States'),
  ('GB', 'United Kingdom'),
  ('CA', 'Canada'),
  ('GH', 'Ghana'),
  ('KE', 'Kenya'),
  ('ZA', 'South Africa'),
  ('IN', 'India'),
  ('AU', 'Australia'),
  ('DE', 'Germany'),
  ('FR', 'France'),
  ('AE', 'United Arab Emirates'),
];

// The form's goal → each network's own objective vocabulary (integration.js).
// Google's "objective" is the channel type; an image creative is a Display ad.
const _adObjectives = {
  'meta_ads': {'awareness': 'OUTCOME_AWARENESS', 'traffic': 'OUTCOME_TRAFFIC', 'engagement': 'OUTCOME_ENGAGEMENT'},
  'tiktok_ads': {'awareness': 'REACH', 'traffic': 'TRAFFIC', 'engagement': 'ENGAGEMENT'},
  'snapchat_ads': {'awareness': 'AWARENESS', 'traffic': 'WEB_VIEW', 'engagement': 'ENGAGEMENT'},
  'pinterest_ads': {'awareness': 'AWARENESS', 'traffic': 'CONSIDERATION'},
  'google_ads': {'awareness': 'DISPLAY', 'traffic': 'DISPLAY', 'engagement': 'DISPLAY'},
};

// Facebook and YouTube are the two that schedule natively.
const _schedulable = ['facebook', 'youtube'];

// ── Caption helpers ────────────────────────────────────────────────────────────

String _captionFromCopy(Map<String, dynamic> copy) {
  String s(String k) => (copy[k] ?? '').toString();
  if (s('headline').isEmpty) return s('body').isNotEmpty ? s('body') : s('tagline');
  return '${s('headline')}${s('tagline').isNotEmpty ? ' — ${s('tagline')}' : ''}'
      '${s('body').isNotEmpty ? '\n\n${s('body')}' : ''}${s('cta').isNotEmpty ? '\n\n${s('cta')}' : ''}';
}

/// Take a headline out of capitals: all lower, then the first letter back up.
String _unshout(String text) {
  final lower = text.toLowerCase();
  final i = lower.indexOf(RegExp(r'\S'));
  return i < 0 ? lower : lower.replaceRange(i, i + 1, lower[i].toUpperCase());
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

// ── Sheet ──────────────────────────────────────────────────────────────────────

class _PublishSheet extends StatefulWidget {
  const _PublishSheet({required this.creative, required this.startInSchedule});

  final PublishCreative creative;
  final bool startInSchedule;

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  late final PublishApi _api = PublishApi(context.read<AuthController>().api);

  List<Map<String, dynamic>> _integrations = [];
  bool _fetching = true;
  bool _compose = false;
  String? _selected;

  // The caption, split where the web's composer splits it: the headline is the
  // first paragraph, the rest is the body.
  final _headline = TextEditingController();
  final _body = TextEditingController();

  // ⚠️ OFF BY DEFAULT, as on the web: bold already marks the headline, and
  // forced capitals wrecked anything with its own casing ("iPhone"). The case
  // lives in the text itself, so what's on screen is exactly what's published.
  bool _caps = false;

  String? _busy; // 'publish' | 'schedule'
  bool _published = false;
  bool _showSchedule = false;
  DateTime? _scheduleAt;

  // Ad form.
  String _adGoal = 'traffic';
  final _adBudget = TextEditingController();
  final _adDays = TextEditingController(text: '7');
  String _adCountry = 'NG';
  final _adAgeMin = TextEditingController(text: '18');
  final _adAgeMax = TextEditingController(text: '65');

  @override
  void initState() {
    super.initState();
    final caption = _captionFromCopy(widget.creative.copy);
    final i = caption.indexOf('\n\n');
    _headline.text = i < 0 ? caption : caption.substring(0, i);
    _body.text = i < 0 ? '' : caption.substring(i + 2);
    _headline.addListener(_refresh);
    _body.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    for (final c in [_headline, _body, _adBudget, _adDays, _adAgeMin, _adAgeMax]) {
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  String get _caption => _body.text.isEmpty ? _headline.text : '${_headline.text}\n\n${_body.text}';

  Future<void> _load() async {
    final rows = await _api.integrations();
    if (!mounted) return;
    setState(() {
      _integrations = rows ?? [];
      _fetching = false;
      if (widget.startInSchedule && _integrations.any((i) => i['platform'] == 'facebook')) {
        _selected = 'facebook';
        _compose = true;
        _showSchedule = true;
      }
    });
  }

  Set<String> get _connected => {for (final i in _integrations) '${i['platform']}'};

  bool get _isAd => _adsOrder.contains(_selected);

  Brand? get _brand => context.read<AuthController>().activeBrand;

  String get _accountName {
    final row = _integrations.where((i) => i['platform'] == _selected).firstOrNull;
    final name = row?['int_name']?.toString();
    if (name != null && name.isNotEmpty) return name;
    return _brand?.name ?? _platforms[_selected]?.label ?? 'Your Brand';
  }

  void _setCaps(bool on) {
    setState(() {
      _caps = on;
      final h = _headline.text;
      if (h.trim().isEmpty) return;
      // Turning capitals off only touches a headline that is ALL capitals — one
      // with lowercase in it keeps its own casing.
      _headline.text = on ? h.toUpperCase() : (RegExp(r'\p{Ll}', unicode: true).hasMatch(h) ? h : _unshout(h));
    });
  }

  void _goConnect() {
    final router = GoRouter.of(context);
    Navigator.pop(context);
    router.push('/integrations');
  }

  // ── Publish ──────────────────────────────────────────────────────────────────

  /// Resolve a publishable URL: the hosted file / thumbnail, or else paint the
  /// layout and upload it (platforms can't fetch an in-app render).
  Future<String> _imageUrl() async {
    final c = widget.creative;
    if (c.image != null && c.image!.startsWith('http')) return c.image!;
    if (c.canvas == null) throw PublishException("Couldn't prepare the design image for publishing.");
    try {
      final png = await renderDesignPng(c.canvas!, c.elements, scraive: c.scraive);
      return await _api.upload(png, '${c.name.isEmpty ? 'creative' : c.name}.png');
    } catch (_) {
      throw PublishException("Couldn't prepare the design image for publishing. Try downloading it first.");
    }
  }

  Future<void> _publish({DateTime? scheduledAt}) async {
    final selected = _selected;
    final brand = _brand;
    if (selected == null || brand == null) return;
    setState(() => _busy = scheduledAt != null ? 'schedule' : 'publish');

    try {
      // The publishing API has no "publish at" field, and one it ignored would
      // post immediately — the opposite of what was asked (same as the web).
      if (scheduledAt != null) {
        throw PublishException("Scheduling isn't available yet — the publishing API can only post now.");
      }

      final text = _caption.trim();
      final firstLine = text.split('\n').first.trim();
      final name = widget.creative.name;
      String? success;

      final url = await _imageUrl();
      // A clip goes out as `video_url`; YouTube and TikTok refuse a video sent
      // as `image_url`.
      final media = widget.creative.isVideo ? {'video_url': url} : {'image_url': url};
      String cut(String s, int n) => s.length > n ? s.substring(0, n) : s;

      if (_isAd) {
        final isGoogle = selected == 'google_ads';
        final rest = text.split('\n').skip(1).join(' ').trim();
        final days = int.tryParse(_adDays.text) ?? 0;
        String date(int offset) {
          final d = DateTime.now().add(Duration(days: offset));
          return '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';
        }

        final description = rest.isNotEmpty ? rest : firstLine;
        final ad = await _api.createAd({
          'platform': selected,
          'name': cut(name.isEmpty ? 'Creative Klux Ad' : name, 200),
          'objective': _adObjectives[selected]?[_adGoal],
          'daily_budget': num.tryParse(_adBudget.text),
          'countries': [_adCountry],
          ...media,
          'link': brand.url,
          'text': cut(text, 2000),
          'headline': cut(firstLine.isNotEmpty ? firstLine : name, isGoogle ? 30 : 255),
          'description': cut(description.isNotEmpty ? description : (isGoogle ? text : ''), isGoogle ? 90 : 500),
          'start_date': date(0),
          'end_date': date(days > 0 ? days : 7),
          'age_min': int.tryParse(_adAgeMin.text),
          'age_max': int.tryParse(_adAgeMax.text),
          'business_name': cut((brand.name ?? name).trim(), 25),
          'logo_url': brand.logo,
          if (isGoogle && !widget.creative.isVideo) 'square_image_url': await _api.squareImageFor(url),
        });
        success =
            'Ad created${ad['status'] == 'ACTIVE' ? ' and live' : ' — paused, resume it from Ads'}'
            '${ad['currency'] != null ? ' (budget in ${ad['currency']})' : ''}.';
      } else {
        final cap = _caps ? _captionCapsHeadline() : text;
        final fields = <String, dynamic>{...media};
        switch (selected) {
          case 'pinterest':
            fields.addAll({
              'title': cut(firstLine.isNotEmpty ? firstLine : name, 100),
              'text': text,
              'link': brand.url,
            });
          case 'youtube':
            fields.addAll({
              'title': cut(firstLine.isNotEmpty ? firstLine : (name.isNotEmpty ? name : 'Creative Klux video'), 100),
              'text': text,
              'privacy_level': 'public',
            });
          case 'tiktok':
            fields.addAll({'title': cut(firstLine.isNotEmpty ? firstLine : name, 90), 'text': cap});
          default: // facebook, instagram, linkedin, twitter
            fields['text'] = cap;
        }
        final res = await _api.publish(selected, brand.id, fields);
        // With video.upload only, TikTok takes it as a draft the creator
        // finishes in the app — say so rather than claiming it went live.
        if (res.draftOnly) success = 'Sent to your TikTok drafts.';
      }

      if (!mounted) return;
      setState(() => _published = true);
      Toast.success(success ?? 'Published to ${_platforms[selected]?.label ?? selected}!');
      Timer(const Duration(milliseconds: 1600), () {
        if (mounted) Navigator.pop(context);
      });
    } on PublishException catch (e) {
      Toast.error(e.message);
    } catch (_) {
      Toast.error('Publish failed');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Belt-and-braces: the headline is already capitalised as it's typed under
  /// "AA", but a platform receives characters, not a style.
  String _captionCapsHeadline() {
    final t = _caption.trim();
    final i = t.indexOf('\n\n');
    return i < 0 ? t.toUpperCase() : t.substring(0, i).toUpperCase() + t.substring(i);
  }

  void _toggleSchedule() {
    if (!_schedulable.contains(_selected)) {
      Toast.error('Scheduling is only available for Facebook and YouTube right now');
      return;
    }
    setState(() => _showSchedule = !_showSchedule);
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final min = now.add(const Duration(minutes: 11));
    final max = now.add(const Duration(days: 180));
    final day = await showDatePicker(context: context, initialDate: _scheduleAt ?? min, firstDate: min, lastDate: max);
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_scheduleAt ?? min));
    if (time == null) return;
    setState(() => _scheduleAt = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  void _confirmSchedule() {
    final at = _scheduleAt;
    if (at == null) {
      Toast.error('Pick a date & time');
      return;
    }
    final now = DateTime.now();
    if (at.isBefore(now.add(const Duration(minutes: 10)))) {
      Toast.error('Schedule at least 10 minutes from now');
      return;
    }
    if (at.isAfter(now.add(const Duration(days: 180)))) {
      Toast.error('Schedule within 6 months');
      return;
    }
    _publish(scheduledAt: at);
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(c),
            Divider(height: 1, color: c.gray100),
            Flexible(child: _compose && _selected != null ? _composeView(c) : _pickerView(c)),
            if (_compose && _selected != null) ...[Divider(height: 1, color: c.gray100), _footer(c)],
          ],
        ),
      ),
    );
  }

  Widget _header(AppColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
    child: Row(
      children: [
        if (_compose)
          IconButton(
            onPressed: () => setState(() => _compose = false),
            icon: Icon(LucideIcons.arrowLeft, size: 18, color: c.gray500),
            visualDensity: VisualDensity.compact,
          ),
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: c.blueTint,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.blue500.withValues(alpha: 0.2)),
          ),
          child: Icon(LucideIcons.send, size: 15, color: AppColors.blue500),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Publish Creative',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.gray900),
              ),
              Text(
                'Publishing “${widget.creative.name}”',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: c.gray400),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(LucideIcons.x, size: 18, color: c.gray400),
        ),
      ],
    ),
  );

  Widget _label(AppColors c, String text) => Text(
    text.toUpperCase(),
    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: c.gray400),
  );

  Widget _pickerView(AppColors c) {
    if (_fetching) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.gray400)),
            const SizedBox(width: 10),
            Text('Loading connected accounts…', style: TextStyle(fontSize: 13, color: c.gray400)),
          ],
        ),
      );
    }
    final order = _platformsFor(widget.creative.category);
    final connected = order.where(_connected.contains).toList();
    final notConnected = order.where((p) => !_connected.contains(p)).toList();

    Widget grid(List<String> ids, bool on) => LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final p in ids) SizedBox(width: w, child: _tile(c, p, on))],
        );
      },
    );

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (connected.isNotEmpty) ...[_label(c, 'Connected'), const SizedBox(height: 8), grid(connected, true)],
        if (notConnected.isNotEmpty) ...[
          const SizedBox(height: 16),
          _label(c, 'Not connected'),
          const SizedBox(height: 8),
          grid(notConnected, false),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _goConnect,
          icon: const Icon(LucideIcons.link2, size: 16),
          label: const Text('Connect More Platforms'),
          style: OutlinedButton.styleFrom(
            foregroundColor: c.gray600,
            side: BorderSide(color: c.gray200),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (connected.isEmpty) ...[
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.amber500.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.amber500.withValues(alpha: 0.35)),
              ),
              child: const Icon(LucideIcons.circleAlert, size: 16, color: AppColors.amber500),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'No platforms connected yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.gray500),
          ),
          const SizedBox(height: 12),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFEC4899)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextButton.icon(
                onPressed: _goConnect,
                icon: const Icon(LucideIcons.link2, size: 14, color: Colors.white),
                label: const Text(
                  'Connect Platforms',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tile(AppColors c, String id, bool connected) {
    final p = _platforms[id]!;
    return Material(
      color: connected ? c.surface : c.gray50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: connected ? c.gray200 : c.gray100),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: connected
            ? () => setState(() {
                _selected = id;
                _published = false;
                _compose = true;
              })
            : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: connected ? p.color : c.gray200, shape: BoxShape.circle),
                child: Icon(p.icon, size: 16, color: connected ? Colors.white : c.gray400),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: connected ? c.gray900 : c.gray500,
                      ),
                    ),
                    Text(
                      connected ? 'Connected' : 'Not connected',
                      style: TextStyle(fontSize: 11, color: connected ? AppColors.green600 : c.gray400),
                    ),
                  ],
                ),
              ),
              if (connected) const Icon(LucideIcons.check, size: 15, color: AppColors.green600),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composeView(AppColors c) {
    final p = _platforms[_selected]!;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: p.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              '${p.label} preview',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // For ads: the form first (the main task), the preview second.
        if (_isAd) ...[_adForm(c), const SizedBox(height: 14), _label(c, 'Preview'), const SizedBox(height: 8)],
        _preview(c),
        const SizedBox(height: 8),
        // The headline's case lives under the preview — inside it, it would
        // read as part of what gets published.
        Row(
          children: [
            Text('Headline', style: TextStyle(fontSize: 11.5, color: c.gray400)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: Border.all(color: c.gray200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  for (final (on, label) in [(true, 'AA'), (false, 'Aa')])
                    GestureDetector(
                      onTap: () => _setCaps(on),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _caps == on ? c.gray900 : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _caps == on ? c.surface : c.gray400,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                'Tap the caption to edit · ${_caption.length} chars',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: c.gray400),
              ),
            ),
          ],
        ),
        if (_showSchedule) ...[const SizedBox(height: 14), _schedulePanel(c)],
      ],
    );
  }

  Widget _visual(AppColors c, {bool square = false}) {
    final cr = widget.creative;
    Widget child;
    if (cr.image != null && cr.isVideo) {
      child = AspectRatio(
        aspectRatio: square ? 1 : 16 / 9,
        child: AutoplayVideo(url: cr.image!, poster: ''),
      );
    } else if (cr.image != null) {
      child = square
          ? AspectRatio(aspectRatio: 1, child: MediaImage(cr.image!))
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 288),
              child: MediaImage(cr.image!, fit: BoxFit.contain),
            );
    } else if (cr.canvas != null) {
      child = ColoredBox(
        color: c.gray50,
        child: Center(
          child: DesignCanvas(canvas: cr.canvas!, elements: cr.elements, scraive: cr.scraive, maxHeight: 288),
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
    return SizedBox(width: double.infinity, child: child);
  }

  Widget _avatar(Color color) {
    // Falls back to the initial when there's no logo OR it fails to load.
    final logo = _brand?.logoUrl;
    final initial = _accountName.isEmpty ? 'B' : _accountName[0].toUpperCase();
    return Container(
      width: 36,
      height: 36,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: logo != null
          ? Image.network(logo, fit: BoxFit.cover, width: 36, height: 36, errorBuilder: (_, _, _) => _initial(initial))
          : _initial(initial),
    );
  }

  Widget _initial(String s) => Text(
    s,
    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
  );

  Widget _captionEditor(AppColors c, {required String placeholder, String? prefix}) {
    final dense = InputDecoration(
      isCollapsed: true,
      border: InputBorder.none,
      hintStyle: TextStyle(color: c.gray400),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (prefix != null) ...[
                Text(
                  prefix,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray800),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: TextField(
                  controller: _headline,
                  maxLines: null,
                  inputFormatters: [if (_caps) _UpperCase()],
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.gray800),
                  decoration: dense.copyWith(hintText: placeholder),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _body,
            maxLines: null,
            style: TextStyle(fontSize: 13.5, color: c.gray800, height: 1.35),
            decoration: dense.copyWith(hintText: 'Write more…'),
          ),
        ],
      ),
    );
  }

  Widget _preview(AppColors c) {
    final p = _platforms[_selected]!;
    final card = BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: c.gray200),
      boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1))],
    );
    final name = _accountName;
    final more = Icon(LucideIcons.ellipsis, size: 16, color: c.gray400);
    final nameStyle = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray900);

    if (_selected == 'instagram') {
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _avatar(p.color),
                  const SizedBox(width: 10),
                  Expanded(child: Text(name, style: nameStyle)),
                  more,
                ],
              ),
            ),
            _visual(c, square: true),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  Icon(LucideIcons.heart, size: 20, color: c.gray800),
                  const SizedBox(width: 16),
                  Icon(LucideIcons.messageCircle, size: 20, color: c.gray800),
                  const SizedBox(width: 16),
                  Icon(LucideIcons.share2, size: 20, color: c.gray800),
                  const Spacer(),
                  Icon(LucideIcons.bookmark, size: 20, color: c.gray800),
                ],
              ),
            ),
            _captionEditor(c, placeholder: 'Write a caption…', prefix: name),
            const SizedBox(height: 10),
          ],
        ),
      );
    }

    final facebook = _selected == 'facebook';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _avatar(p.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: nameStyle),
                      Row(
                        children: [
                          Text(facebook ? 'Sponsored · ' : p.label, style: TextStyle(fontSize: 11, color: c.gray400)),
                          if (facebook) Icon(LucideIcons.globe, size: 11, color: c.gray400),
                        ],
                      ),
                    ],
                  ),
                ),
                more,
              ],
            ),
          ),
          _captionEditor(c, placeholder: facebook ? "What's on your mind?" : 'Write a caption…'),
          const SizedBox(height: 8),
          _visual(c),
          if (facebook)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.gray100)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final (icon, label) in [
                    (LucideIcons.thumbsUp, 'Like'),
                    (LucideIcons.messageCircle, 'Comment'),
                    (LucideIcons.share2, 'Share'),
                  ])
                    Row(
                      children: [
                        Icon(icon, size: 16, color: c.gray500),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
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

  InputDecoration _field(AppColors c, {String? hint}) => InputDecoration(
    isDense: true,
    hintText: hint,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: c.gray200),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: c.gray200),
    ),
  );

  Widget _numberField(AppColors c, String label, TextEditingController ctrl, {String? hint, String? helper}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label(c, label),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(fontSize: 13.5, color: c.gray900),
        decoration: _field(c, hint: hint),
      ),
      if (helper != null) ...[
        const SizedBox(height: 2),
        Text(helper, style: TextStyle(fontSize: 10.5, color: c.gray400)),
      ],
    ],
  );

  Widget _dropdown(AppColors c, String label, String value, List<(String, String)> items, ValueChanged<String> on) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(c, label),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            decoration: _field(c),
            dropdownColor: c.surface,
            style: TextStyle(fontSize: 13.5, color: c.gray900),
            items: [
              for (final (v, l) in items)
                DropdownMenuItem(
                  value: v,
                  child: Text(l, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => v == null ? null : on(v),
          ),
        ],
      );

  Widget _adForm(AppColors c) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: c.gray200),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(LucideIcons.megaphone, size: 14, color: AppColors.blue600),
            const SizedBox(width: 8),
            Text(
              'AD SETTINGS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: c.gray700),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.amber500.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: AppColors.amber500.withValues(alpha: 0.35)),
              ),
              child: const Text('Created paused', style: TextStyle(fontSize: 10.5, color: Color(0xFFB45309))),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Google Ads has no goal: an image is a Display ad.
        if (_selected != 'google_ads') ...[
          _dropdown(c, 'Goal', _adGoal, _adGoals, (v) => setState(() => _adGoal = v)),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _numberField(
                c,
                'Daily budget',
                _adBudget,
                hint: 'e.g. 50',
                helper: 'In your ad account’s currency',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _numberField(c, 'Run for (days)', _adDays)),
          ],
        ),
        const SizedBox(height: 12),
        _dropdown(c, 'Show to people in', _adCountry, _adCountries, (v) => setState(() => _adCountry = v)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _numberField(c, 'Min age', _adAgeMin)),
            const SizedBox(width: 8),
            Expanded(child: _numberField(c, 'Max age', _adAgeMax)),
          ],
        ),
      ],
    ),
  );

  Widget _schedulePanel(AppColors c) {
    final at = _scheduleAt;
    final label = at == null
        ? 'Pick a date & time'
        : '${MaterialLocalizations.of(context).formatMediumDate(at)} · '
              '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at))}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: c.gray200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(c, 'Schedule for'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickSchedule,
                  icon: Icon(LucideIcons.calendar, size: 15, color: c.gray500),
                  label: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: at == null ? c.gray400 : c.gray800),
                  ),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    side: BorderSide(color: c.gray200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _gradientButton(
                onPressed: _busy != null || _published ? null : _confirmSchedule,
                busy: _busy == 'schedule',
                icon: LucideIcons.calendarClock,
                label: _busy == 'schedule' ? 'Scheduling…' : 'Schedule',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_selected == 'youtube' ? 'YouTube' : 'Facebook'} publishes it automatically · 10 min–6 months ahead.',
            style: TextStyle(fontSize: 10.5, color: c.gray400),
          ),
        ],
      ),
    );
  }

  Widget _gradientButton({
    required VoidCallback? onPressed,
    required bool busy,
    required IconData icon,
    required String label,
  }) => Opacity(
    opacity: onPressed == null ? 0.6 : 1,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFEC4899)]),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon, size: 14, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
      ),
    ),
  );

  Widget _footer(AppColors c) {
    final locked = _busy != null || _published;
    final isAd = _isAd;
    final publishing = _busy == 'publish';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: _busy != null ? null : () => setState(() => _compose = false),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.gray600,
                side: BorderSide(color: c.gray200),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Back'),
            ),
            if (!isAd) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: locked ? null : _toggleSchedule,
                icon: const Icon(LucideIcons.calendarClock, size: 14),
                label: const Text('Schedule'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _showSchedule ? AppColors.blue600 : c.gray700,
                  backgroundColor: _showSchedule ? c.blueTint : null,
                  side: BorderSide(color: _showSchedule ? AppColors.blue500 : c.gray200),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Flexible(
              child: FilledButton.icon(
                onPressed: locked ? null : () => _publish(),
                icon: publishing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(_published ? LucideIcons.check : LucideIcons.send, size: 14),
                label: Text(
                  publishing
                      ? (isAd ? 'Creating ad…' : 'Publishing…')
                      : _published
                      ? (isAd ? 'Ad created!' : 'Published!')
                      : (isAd ? 'Create Ad' : 'Publish Now'),
                  overflow: TextOverflow.ellipsis,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue600,
                  disabledBackgroundColor: AppColors.blue600.withValues(alpha: 0.6),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
