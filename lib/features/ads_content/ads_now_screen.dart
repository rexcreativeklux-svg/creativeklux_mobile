import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../shell/widgets/app_top_bar.dart';

/// Port of `(pages)/AdsNow/page.jsx` — "Set Up Your Ad Campaign in a Snap".
///
/// The web opens it in a new tab from `AdsIntegrationModal` ("Continue" after
/// choosing an ad platform), reached from the studio's ads flows.
///
/// ⚠️ IT IS A MOCK ON THE WEB TOO: "Publish Ads" only `console.log`s the
/// compiled form, nothing is sent, and the preview's copy is placeholder
/// ("Your Name", the "Weviy" blurb). The real ad flow is the publish sheet's
/// Ads tab (`POST creatives/ads`). Here the button compiles the same object,
/// logs it, and says publishing isn't available yet rather than doing nothing.
///
/// The web reads `?url=` / `?projectName=` and the assets the wizard left in
/// localStorage (`selectedAssetsForPost`); those arrive as [initialUrl],
/// [initialProjectName] and [initialMedia] (hosted URLs).
///
/// Phone layout: the web's two 50% columns stack — setup, then budget, then
/// ad set + preview.
class AdsNowScreen extends StatefulWidget {
  const AdsNowScreen({super.key, this.initialUrl, this.initialProjectName, this.initialMedia = const []});

  final String? initialUrl;
  final String? initialProjectName;
  final List<String> initialMedia;

  @override
  State<AdsNowScreen> createState() => _AdsNowScreenState();
}

const _goals = [
  ('Brand Awareness', 'Increase visibility and recognition of your brand.'),
  ('Engagement', 'Encourage likes, comments, and shares on your content.'),
  ('Sales', 'Drive purchases of your products or services.'),
  ('Lead Generation', 'Collect contact information from potential customers.'),
  ('Website Traffic', 'Get more people to visit your website.'),
];

const _audiences = [
  ('B2B', 'B2B (Professional)', 'Business owners, startups, agencies'),
  ('B2C', 'B2C (Customer-Friendly)', 'End consumers, everyday users'),
  ('Casual', 'Casual / Social-first', 'Broad social media audience'),
  ('Inspirational', 'Inspirational / Motivational', 'Entrepreneurs, creators, startups'),
  ('Sales', 'Direct / Sales-oriented', 'Hot leads, ad audiences'),
];

const _conversionButtons = ['Use App', 'Learn More', 'Shop Now', 'Sign Up', 'Contact Us', 'Get Quote', 'Download'];

const _countries = ['United States', 'Canada', 'United Kingdom', 'Australia', 'Germany', 'France', 'Japan'];

const _previewBlurb =
    'Step into the future with Weviy! ✨ From sleek gadgets to lifestyle-enhancing digital solutions...';
const _previewHeadline = 'Discover Cutting-Edge...';

class _Media {
  _Media({required this.url, required this.video, this.file});

  /// A hosted URL, or null for a picked file.
  final String? url;
  final File? file;
  final bool video;
}

class _AdsNowScreenState extends State<AdsNowScreen> {
  late final TextEditingController _url;
  late final TextEditingController _projectName;
  late final TextEditingController _budgetText;
  String _goal = '';
  // The web's initial value, "Button", isn't one of the options; its select
  // shows the first one until changed, and the preview shows "Button".
  String _conversionButton = 'Button';
  late DateTime _start;
  late DateTime _end;
  String _country = 'United States';
  int _dailyBudget = 100;
  final List<_Media> _media = [];
  final List<String> _selectedAudiences = [];
  bool _adContentOpen = false;

  @override
  void initState() {
    super.initState();
    // The preview's link line follows the URL as it's typed.
    _url = TextEditingController(text: widget.initialUrl ?? '')..addListener(() => setState(() {}));
    _projectName = TextEditingController(text: widget.initialProjectName ?? '');
    _budgetText = TextEditingController(text: '$_dailyBudget');
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _end = _start.add(const Duration(days: 2));
    for (final src in widget.initialMedia) {
      final ext = src.split('?').first.split('.').last.toLowerCase();
      _media.add(_Media(url: src, video: ext == 'mp4' || ext == 'mov'));
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _projectName.dispose();
    _budgetText.dispose();
    super.dispose();
  }

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _pickMedia() async {
    try {
      final files = await ImagePicker().pickMultipleMedia();
      if (files.isEmpty || !mounted) return;
      setState(() {
        for (final f in files) {
          final mime = f.mimeType ?? '';
          final ext = f.path.split('.').last.toLowerCase();
          final video = mime.startsWith('video/') || const ['mp4', 'mov', 'm4v', 'webm', '3gp'].contains(ext);
          _media.add(_Media(url: null, file: File(f.path), video: video));
        }
      });
    } catch (e) {
      Toast.error("Couldn't open your gallery");
    }
  }

  Future<void> _pickDateTime({required bool start}) async {
    final initial = start ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return;
    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => start ? _start = picked : _end = picked);
  }

  void _setBudget(int v, {bool fromSlider = false}) {
    setState(() => _dailyBudget = v);
    if (fromSlider) _budgetText.text = '$v';
  }

  void _publish() {
    final adData = {
      'url': _url.text,
      'projectName': _projectName.text,
      'selectedGoal': _goal,
      'conversionButton': _conversionButton,
      'startDate': _fmt(_start),
      'endDate': _fmt(_end),
      'selectedCountry': _country,
      'dailyBudget': _dailyBudget,
      'selectedAdSet': '',
      'uploadedMedia': [
        for (final m in _media) {'type': m.video ? 'video' : 'image', 'url': m.url ?? m.file?.path},
      ],
      'selectedAudiences': _selectedAudiences,
    };
    debugPrint('Compiled Ad Data: $adData');
    Toast.info("Publishing from this page isn't available yet.");
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.page,
      body: SafeArea(
        child: Column(
          children: [
            const AppTopBar(title: 'Ads', showBack: true),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text(
                    'Set Up Your Ad Campaign in a Snap',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.gray900),
                  ),
                  const SizedBox(height: 20),
                  _urlBox(context),
                  const SizedBox(height: 24),
                  _label(context, 'Project name'),
                  _textField(context, _projectName, 'Project Name'),
                  const SizedBox(height: 24),
                  _label(context, 'Ad Goal'),
                  const SizedBox(height: 4),
                  for (final (goal, description) in _goals) _goalCard(context, goal, description),
                  const SizedBox(height: 16),
                  _label(context, 'Ad Conversion Button', info: true),
                  _dropdown(
                    context,
                    // The web's select shows its first option while the
                    // state still holds the non-option "Button".
                    value: _conversionButtons.contains(_conversionButton)
                        ? _conversionButton
                        : _conversionButtons.first,
                    items: _conversionButtons,
                    onChanged: (v) => setState(() => _conversionButton = v),
                  ),
                  const SizedBox(height: 24),
                  _dates(context),
                  const SizedBox(height: 24),
                  _label(context, 'Cities and Countries to Advertise', info: true),
                  _dropdown(
                    context,
                    value: _country,
                    items: _countries,
                    onChanged: (v) => setState(() => _country = v),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.blue600.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(_country, style: TextStyle(fontSize: 13, color: AppColors.blue600)),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.gray200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _budget(context),
                        Divider(height: 1, color: c.gray200),
                        _adSet(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The URL block. The web clips it to a custom notched SVG shape; a plain
  /// rounded panel here.
  Widget _urlBox(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'URL',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray800),
          ),
          const SizedBox(height: 8),
          _textField(context, _url, 'https://yourdomain.com', keyboard: TextInputType.url, fill: c.surface),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text, {bool info = false}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: AppColors.blue600, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray700),
            ),
          ),
          if (info) ...[const SizedBox(width: 6), Icon(LucideIcons.info, size: 14, color: c.gray400)],
        ],
      ),
    );
  }

  InputDecoration _decoration(BuildContext context, {String? hint, Color? fill}) {
    final c = context.colors;
    OutlineInputBorder border(Color color, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: w),
    );
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13.5, color: c.gray400),
      filled: true,
      fillColor: fill ?? c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: border(c.gray300),
      enabledBorder: border(c.gray300),
      focusedBorder: border(AppColors.blue500, 2),
    );
  }

  Widget _textField(
    BuildContext context,
    TextEditingController controller,
    String hint, {
    TextInputType? keyboard,
    Color? fill,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      style: TextStyle(fontSize: 13.5, color: context.colors.gray900),
      decoration: _decoration(context, hint: hint, fill: fill),
    );
  }

  Widget _dropdown(
    BuildContext context, {
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    final c = context.colors;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      icon: Icon(LucideIcons.chevronDown, size: 18, color: c.gray400),
      dropdownColor: c.surface,
      style: TextStyle(fontSize: 13.5, color: c.gray900),
      decoration: _decoration(context),
      items: [for (final i in items) DropdownMenuItem(value: i, child: Text(i))],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _goalCard(BuildContext context, String goal, String description) {
    final c = context.colors;
    final selected = _goal == goal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _goal = goal),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? AppColors.blue600 : c.gray200),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.gray900),
                    ),
                    const SizedBox(height: 3),
                    Text(description, style: TextStyle(fontSize: 12, color: c.gray500)),
                  ],
                ),
              ),
              if (selected) Icon(LucideIcons.circleCheck, size: 20, color: AppColors.blue600),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dates(BuildContext context) {
    final c = context.colors;
    Widget field(DateTime value, bool start) => InkWell(
      onTap: () => _pickDateTime(start: start),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.gray300),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(_fmt(value), style: TextStyle(fontSize: 13.5, color: c.gray900)),
            ),
            Icon(LucideIcons.calendar, size: 16, color: c.gray400),
          ],
        ),
      ),
    );
    Widget quick(String label, int days) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: c.gray100,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          // Dead buttons on the web; here they set the end date that many
          // days after the start.
          onTap: () => setState(() => _end = _start.add(Duration(days: days))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            child: Text(label, style: TextStyle(fontSize: 12.5, color: c.gray600)),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, 'Start date', info: true),
        field(_start, true),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _label(context, 'End date', info: true)),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [quick('3D', 3), quick('14D', 14), quick('30D', 30)]),
            ),
          ],
        ),
        field(_end, false),
        const SizedBox(height: 10),
        Text(
          'Meta ads typically need 2-3 days to calibrate and scale. Run for at least 3 days for optimal results.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: c.gray500),
        ),
      ],
    );
  }

  Widget _budget(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.calendar, size: 18, color: AppColors.blue600),
              const SizedBox(width: 8),
              Text(
                'Daily Budget',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray700),
              ),
              const SizedBox(width: 6),
              Icon(LucideIcons.info, size: 14, color: c.gray400),
              const Spacer(),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.gray200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '\$',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: c.gray600),
                    ),
                    SizedBox(
                      width: 48,
                      child: TextField(
                        controller: _budgetText,
                        keyboardType: TextInputType.number,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.gray600),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.only(left: 2),
                        ),
                        onChanged: (v) => _setBudget(int.tryParse(v) ?? 0),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: AppColors.blue600,
              inactiveTrackColor: c.gray200,
              thumbColor: AppColors.blue600,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              min: 1,
              max: 1000,
              value: _dailyBudget.clamp(1, 1000).toDouble(),
              onChanged: (v) => _setBudget(v.round(), fromSlider: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final t in ['Limited', 'Basic Reach', '2x + Results'])
                  Text(t, style: TextStyle(fontSize: 11.5, color: c.gray500)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.gray100, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.gray300, shape: BoxShape.circle),
                  child: const Text(
                    '!',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Please increase your budget to achieve better results',
                    style: TextStyle(fontSize: 12.5, color: c.gray700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _adSet(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _pickMedia,
              icon: const Icon(LucideIcons.upload, size: 16),
              label: const Text('Add Media'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.blue600,
                side: BorderSide(color: AppColors.blue600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          if (_media.isNotEmpty) ...[const SizedBox(height: 10), _mediaStrip(context)],
          const SizedBox(height: 8),
          // Ad Content (collapsible)
          InkWell(
            onTap: () => setState(() => _adContentOpen = !_adContentOpen),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.gray200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ad Content',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.gray700),
                    ),
                  ),
                  Icon(_adContentOpen ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 16, color: c.gray400),
                ],
              ),
            ),
          ),
          if (_adContentOpen)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.gray200)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _contentItem(
                    context,
                    'Audience Description',
                    _selectedAudiences.isNotEmpty
                        ? _selectedAudiences
                              .map((a) => _audiences.where((o) => o.$1 == a).firstOrNull?.$3 ?? '')
                              .join(', ')
                        : 'Select an audience to see description',
                  ),
                  _contentItem(context, 'Headline', _previewHeadline),
                  _contentItem(context, 'Description', _previewBlurb, last: true),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Audience Targeting',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.gray700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label, _) in _audiences)
                _audienceChip(context, value, label, _selectedAudiences.contains(value)),
            ],
          ),
          const SizedBox(height: 18),
          _preview(context),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: _publish,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              child: const Text('Publish Ads'),
            ),
          ),
        ],
      ),
    );
  }

  /// The picked media, removable — the web keeps `removeMedia` but never
  /// draws a way to call it.
  Widget _mediaStrip(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _media.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final m = _media[i];
          return Stack(
            children: [
              Container(
                width: 64,
                height: 64,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: c.gray100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.gray200),
                ),
                child: m.video
                    ? Icon(LucideIcons.video, size: 20, color: c.gray400)
                    : m.file != null
                    ? Image.file(m.file!, fit: BoxFit.cover, cacheWidth: 200)
                    : MediaImage(m.url!, cacheWidth: 200),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () => setState(() => _media.removeAt(i)),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                    child: const Icon(LucideIcons.x, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _contentItem(BuildContext context, String label, String text, {bool last = false}) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.gray700),
          ),
          const SizedBox(height: 3),
          Text(text, style: TextStyle(fontSize: 12, color: c.gray500)),
        ],
      ),
    );
  }

  Widget _audienceChip(BuildContext context, String value, String label, bool selected) {
    final c = context.colors;
    return InkWell(
      onTap: () => setState(() => selected ? _selectedAudiences.remove(value) : _selectedAudiences.add(value)),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.gray50 : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppColors.blue600 : c.gray200),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: c.gray800)),
      ),
    );
  }

  /// `AdPreview` — a social feed card with the first media item.
  Widget _preview(BuildContext context) {
    final c = context.colors;
    final first = _media.firstOrNull;
    Widget action(IconData icon, String label) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c.gray600),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: c.gray600)),
        ],
      ),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Color(0xFF1D4ED8), shape: BoxShape.circle),
                  child: const Text(
                    'YN',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Name',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.gray900),
                    ),
                    Text('Sponsored', style: TextStyle(fontSize: 10.5, color: c.gray500)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(_previewBlurb, style: TextStyle(fontSize: 12, color: c.gray800)),
          ),
          SizedBox(
            height: 200,
            child: first == null
                ? GestureDetector(
                    onTap: _pickMedia,
                    child: Container(
                      color: c.gray100,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Tap to upload images and videos and see the preview here!',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: c.gray500),
                      ),
                    ),
                  )
                : first.video
                ? _PreviewVideo(key: ObjectKey(first), file: first.file, url: first.url)
                : first.file != null
                ? Image.file(first.file!, fit: BoxFit.cover, cacheWidth: 1000)
                : MediaImage(first.url!, cacheWidth: 1000),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.gray200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _url.text.isEmpty ? 'url.com' : _url.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.gray500),
                      ),
                      Text(
                        _previewHeadline,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray900),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.gray200),
                  ),
                  child: Text(_conversionButton, style: TextStyle(fontSize: 12, color: c.gray900)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                action(LucideIcons.heart, 'Like'),
                action(LucideIcons.messageCircle, 'Comment'),
                action(LucideIcons.share, 'Share'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The preview's `<video controls>`: tap to play / pause.
class _PreviewVideo extends StatefulWidget {
  const _PreviewVideo({super.key, this.file, this.url});

  final File? file;
  final String? url;

  @override
  State<_PreviewVideo> createState() => _PreviewVideoState();
}

class _PreviewVideoState extends State<_PreviewVideo> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.file != null
        ? VideoPlayerController.file(widget.file!)
        : VideoPlayerController.networkUrl(Uri.parse(widget.url!));
    _controller.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    }, onError: (_) {});
    _controller.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_tick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _controller.value.isPlaying ? _controller.pause() : _controller.play(),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ready)
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            if (!_controller.value.isPlaying)
              const Center(child: Icon(LucideIcons.circlePlay, size: 40, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
