import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/api/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import '../../shell/widgets/app_top_bar.dart';
import '../brand.dart';
import '../widgets/brand_visuals.dart';

const _maxLogoBytes = 500 * 1024;
const _blue = Color(0xFF2563EB);

/// Create (`brand/create/page.jsx`) and edit (`brand/edit/page.jsx`) in one
/// screen — the two web pages share the same fields, preview and logo upload.
///
/// Create has two modes: Smart Import (scrape a URL, prefill the form) and
/// Manual. Edit loads the brand by id. On phones the live preview stacks under
/// the form; from 1024px it sits beside it, as on the web.
class BrandFormScreen extends StatefulWidget {
  const BrandFormScreen.create({super.key}) : brandId = null;
  const BrandFormScreen.edit({super.key, required int this.brandId});

  final int? brandId;

  bool get isEdit => brandId != null;

  @override
  State<BrandFormScreen> createState() => _BrandFormScreenState();
}

enum _Mode { import, manual }

class _BrandFormScreenState extends State<BrandFormScreen> {
  _Mode _mode = _Mode.import;

  // Import mode: 0 = waiting for a URL, 1 = form shown.
  int _step = 0;
  final _url = TextEditingController();
  String? _urlError;
  bool _importing = false;
  String _sourceUrl = '';

  final _name = TextEditingController();
  final _tagline = TextEditingController();
  final _description = TextEditingController();
  String _industry = '';
  String _font = 'Inter';
  String _primary = '#2563eb';
  String _secondary = '#0ea5e9';

  /// Hosted logo URL to send (null = none / keep existing on edit).
  String? _logo;

  /// What the preview shows: picked bytes, else an existing URL.
  Uint8List? _logoBytes;
  String? _logoPreviewUrl;
  bool _uploading = false;

  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _tagline, _description]) {
      c.addListener(() => setState(() {}));
    }
    if (widget.isEdit) _load();
  }

  @override
  void dispose() {
    for (final c in [_url, _name, _tagline, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final brand = await context.read<AuthController>().brandApi.fetchById(widget.brandId!);
    if (!mounted) return;
    if (brand == null) {
      Toast.error('Failed to load brand details.');
      setState(() => _loading = false);
      return;
    }
    _name.text = brand.name ?? '';
    _tagline.text = brand.tagline ?? '';
    _description.text = brand.description ?? '';
    setState(() {
      _industry = brand.industry ?? '';
      _font = brand.fonts ?? 'Inter';
      _primary = Brand.cleanHex(brand.primaryColor) ?? '#1e3a8a';
      _secondary = Brand.cleanHex(brand.secondaryColor) ?? '#10b981';
      _logoPreviewUrl = brand.logoUrl;
      _loading = false;
    });
  }

  void _setMode(_Mode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _step = mode == _Mode.import ? 0 : 1;
      _url.clear();
      _urlError = null;
      _resetForm();
    });
  }

  void _resetForm() {
    _name.clear();
    _tagline.clear();
    _description.clear();
    _industry = '';
    _font = 'Inter';
    _primary = '#2563eb';
    _secondary = '#0ea5e9';
    _logo = null;
    _logoBytes = null;
    _logoPreviewUrl = null;
  }

  bool _validUrl(String v) {
    final uri = Uri.tryParse(v.trim());
    return uri != null && uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  Future<void> _import() async {
    final url = _url.text.trim();
    if (!_validUrl(url)) {
      setState(() => _urlError = 'Please enter a valid URL (e.g. https://yourdomain.com)');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _importing = true);
    try {
      final res = await context.read<AuthController>().brandApi.importFromUrl(url);
      if (!mounted) return;
      if (!res.ok) {
        Toast.error(res.message.isNotEmpty ? res.message : 'Import failed. Check the URL and try again.');
        return;
      }
      final body = res.body;
      final d = (body['data'] is Map ? body['data'] : body) as Map;
      final fields = d['data'] is Map ? d['data'] as Map : d;
      String s(String k) => fields[k]?.toString() ?? '';
      _name.text = s('name');
      _description.text = s('description');
      _tagline.text = s('tagline');
      setState(() {
        _font = s('font').isEmpty ? 'Inter' : s('font');
        _primary = Brand.cleanHex(s('primary_color')) ?? '#2563eb';
        _secondary = Brand.cleanHex(s('secondary_color')) ?? '#0ea5e9';
        final logo = s('logo');
        _logo = logo.isEmpty ? null : logo;
        _logoPreviewUrl = Brand.resolveAssetUrl(_logo);
        // An imported industry outside the list can't be selected — leave it blank.
        _industry = brandIndustries.contains(s('industry')) ? s('industry') : '';
        _sourceUrl = url;
        _step = 1;
      });
    } catch (_) {
      Toast.error('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _pickLogo() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxLogoBytes) {
      Toast.error('Logo too large. Please choose a logo under 500 KB.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _logoBytes = bytes;
      _uploading = true;
    });
    try {
      final url = await context.read<AuthController>().brandApi.uploadImage(bytes, file.name);
      if (!mounted) return;
      if (url == null) {
        Toast.error("Couldn't get a URL for your logo. Please try again.");
        setState(() => _logoBytes = null);
      } else {
        setState(() => _logo = url);
      }
    } catch (err) {
      Toast.error(toUserMessage(err, "Couldn't upload your logo. Please try again."));
      if (mounted) setState(() => _logoBytes = null);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      Toast.error('Please enter a brand name.');
      return;
    }
    if (!widget.isEdit && _industry.isEmpty) {
      Toast.error('Please select an industry.');
      return;
    }
    if (_uploading) {
      Toast.info('Please wait for the logo upload to finish.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final auth = context.read<AuthController>();
    final router = GoRouter.of(context);

    try {
      if (widget.isEdit) {
        final res = await auth.brandApi.update(
          widget.brandId!,
          name: _name.text.trim(),
          description: _description.text,
          tagline: _tagline.text,
          fonts: _font,
          industry: _industry,
          logo: _logo,
          primaryColor: _primary,
          secondaryColor: _secondary,
        );
        if (!res.ok) {
          Toast.error(res.message.isNotEmpty ? res.message : 'Could not update brand.');
          return;
        }
        Toast.success('Saved!', description: 'Brand updated successfully.');
        await auth.fetchBrands();
        router.go('/brand/reuse');
      } else {
        final isImport = _mode == _Mode.import;
        final res = await auth.brandApi.create({
          'name': _name.text.trim(),
          'description': _description.text,
          'tagline': _tagline.text,
          'fonts': _font,
          'primary_color': Brand.cleanHex(_primary) ?? '#1e3a8a',
          'secondary_color': Brand.cleanHex(_secondary) ?? '#10b981',
          // Literal JSON strings — that's what the endpoint expects.
          'social_accounts': '[]',
          'ad_accounts': '[]',
          'industry': _industry,
          'url': isImport ? _url.text.trim() : '',
          'source_url': isImport ? (_sourceUrl.isNotEmpty ? _sourceUrl : _url.text.trim()) : '',
          'landing_page_flag': '0',
          'logo': ?_logo,
        });
        if (!res.ok) {
          final msg = res.errors?.values.expand((v) => v is List ? v : [v]).firstOrNull?.toString();
          Toast.error(msg ?? (res.message.isNotEmpty ? res.message : 'Something went wrong.'));
          return;
        }
        Toast.success('Brand created!', description: 'Connect its accounts on the Integrations page.');
        await auth.fetchBrands();
        router.go('/brand/reuse');
      }
    } catch (_) {
      Toast.error('Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final showForm = widget.isEdit || _mode == _Mode.manual || _step > 0;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          AppTopBar(title: widget.isEdit ? 'Edit Brand' : 'Create your brand', showBack: true),
          Expanded(
            child: Stack(
              children: [
                Container(
                  color: c.page,
                  child: _loading
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: AppColors.blue600),
                              const SizedBox(height: 12),
                              Text('Loading brand…', style: TextStyle(color: c.gray500)),
                            ],
                          ),
                        )
                      : ListView(
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                          children: [
                            if (widget.isEdit)
                              Text(
                                'Update your brand details below.',
                                style: TextStyle(fontSize: 13.5, color: c.gray500),
                              )
                            else ...[
                              _modeTabs(context),
                              const SizedBox(height: 10),
                              Text(
                                _mode == _Mode.import
                                    ? "Paste your website URL — we'll auto-extract your brand identity."
                                    : 'Fill in your brand details manually to get started.',
                                style: TextStyle(fontSize: 13.5, color: c.gray500),
                              ),
                              if (_mode == _Mode.import) ...[const SizedBox(height: 14), _urlBar(context)],
                            ],
                            const SizedBox(height: 16),
                            if (!showForm)
                              _importEmpty(context)
                            else if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _formCard(context)),
                                  const SizedBox(width: 20),
                                  SizedBox(width: 340, child: _preview()),
                                ],
                              )
                            else ...[
                              _formCard(context),
                              const SizedBox(height: 24),
                              _preview(),
                            ],
                          ],
                        ),
                ),
                if (_importing) const _ImportingOverlay(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeTabs(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        for (final (mode, label) in [(_Mode.import, 'Smart Import 🌐'), (_Mode.manual, 'Manual Creation ✏️')])
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: GestureDetector(
              onTap: () => _setMode(mode),
              child: Container(
                padding: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: _mode == mode ? AppColors.blue600 : Colors.transparent, width: 2),
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _mode == mode ? AppColors.blue600 : c.gray900,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _urlBar(BuildContext context) {
    final c = context.colors;
    final canImport = !_importing && _url.text.trim().isNotEmpty && _urlError == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _urlError != null ? AppColors.red500 : c.gray200),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: c.blueTint, borderRadius: BorderRadius.circular(10)),
                child: Icon(LucideIcons.link, size: 17, color: AppColors.blue600),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onChanged: (_) => setState(() => _urlError = null),
                  onSubmitted: (_) => _import(),
                  style: TextStyle(fontSize: 14, color: c.gray900),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'https://yourdomain.com',
                    hintStyle: TextStyle(color: c.gray400),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: canImport ? _import : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(LucideIcons.upload, size: 15),
                label: const Text('Import'),
              ),
            ],
          ),
        ),
        if (_urlError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text('• $_urlError', style: const TextStyle(fontSize: 12, color: AppColors.red500)),
          ),
      ],
    );
  }

  Widget _importEmpty(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: c.blueTint, borderRadius: BorderRadius.circular(16)),
            child: Icon(LucideIcons.globe, size: 26, color: AppColors.blue600),
          ),
          const SizedBox(height: 14),
          Text(
            'Paste a URL above to get started',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray800),
          ),
          const SizedBox(height: 4),
          Text(
            "We'll extract your brand name, colors, logo, and description automatically.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.gray500),
          ),
        ],
      ),
    );
  }

  Widget _preview() => BrandPreviewCard(
    name: _name.text,
    tagline: _tagline.text,
    description: _description.text,
    industry: _industry,
    font: _font,
    primary: _primary,
    secondary: _secondary,
    logoUrl: _logoPreviewUrl,
    logoBytes: _logoBytes,
    emptyDescription: widget.isEdit
        ? 'Your brand description will appear here.'
        : 'Your brand description will appear here once you fill in the details.',
  );

  Widget _formCard(BuildContext context) {
    final c = context.colors;
    final hasLogo = _logoBytes != null || _logoPreviewUrl != null;

    Widget field(String label, Widget child, {bool required = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(label, required: required),
        const SizedBox(height: 6),
        child,
      ],
    );

    Widget dropdown(String value, List<String> options, String placeholder, ValueChanged<String> onChanged) =>
        DropdownButtonFormField<String>(
          initialValue: value.isEmpty ? null : value,
          isExpanded: true,
          hint: Text(placeholder, style: TextStyle(fontSize: 14, color: c.gray400)),
          style: TextStyle(fontSize: 14, color: c.gray900),
          dropdownColor: c.surface,
          borderRadius: BorderRadius.circular(12),
          decoration: brandInputDecoration(context),
          items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: (v) => setState(() => onChanged(v ?? '')),
        );

    final industryField = field(
      'Industry',
      dropdown(_industry, brandIndustries, 'Select industry…', (v) => _industry = v),
      required: true,
    );
    final fontField = field('Font', dropdown(_font, brandFonts, 'Select font…', (v) => _font = v));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c.blueTint, borderRadius: BorderRadius.circular(10)),
                child: Icon(LucideIcons.star, size: 16, color: AppColors.blue600),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Brand Details',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.gray900),
                  ),
                  if (widget.isEdit)
                    Text('Update your brand identity', style: TextStyle(fontSize: 12, color: c.gray500)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: c.gray100),
          const SizedBox(height: 16),
          field(
            'Brand Name',
            TextField(
              controller: _name,
              style: TextStyle(fontSize: 14, color: c.gray900),
              decoration: brandInputDecoration(context, hint: 'e.g. Acme Corp'),
            ),
            required: true,
          ),
          const SizedBox(height: 14),
          field(
            'Tagline / Slogan',
            TextField(
              controller: _tagline,
              style: TextStyle(fontSize: 14, color: c.gray900),
              decoration: brandInputDecoration(context, hint: 'e.g. Just do it'),
            ),
          ),
          const SizedBox(height: 14),
          field(
            'Description',
            TextField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              style: TextStyle(fontSize: 14, color: c.gray900),
              decoration: brandInputDecoration(context, hint: 'Brief brand description…'),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 420
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: industryField),
                      const SizedBox(width: 12),
                      Expanded(child: fontField),
                    ],
                  )
                : Column(children: [industryField, const SizedBox(height: 14), fontField]),
          ),
          const SizedBox(height: 14),
          field(
            'Logo',
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploading ? null : _pickLogo,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: c.gray600,
                      side: BorderSide(color: c.gray300, style: BorderStyle.solid),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _uploading
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(LucideIcons.upload, size: 16),
                    label: Text(
                      _uploading
                          ? 'Uploading…'
                          : hasLogo
                          ? 'Replace Logo'
                          : 'Upload Logo',
                    ),
                  ),
                ),
                if (hasLogo) ...[
                  const SizedBox(width: 10),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      BrandLogoTile(
                        name: _name.text,
                        color: Brand.parseHex(_primary) ?? AppColors.brandFallback,
                        logoUrl: _logoPreviewUrl,
                        logoBytes: _logoBytes,
                        size: 48,
                      ),
                      if (_uploading)
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Center(
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ColorField(
                  label: 'Primary Color',
                  value: _primary,
                  onChanged: (v) => setState(() => _primary = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ColorField(
                  label: 'Secondary Color',
                  value: _secondary,
                  onChanged: (v) => setState(() => _secondary = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: c.gray100),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () {
                        if (!widget.isEdit && _mode == _Mode.import && _step > 0) {
                          setState(() {
                            _step = 0;
                            _url.clear();
                          });
                        } else if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/brand/reuse');
                        }
                      },
                style: TextButton.styleFrom(foregroundColor: c.gray600),
                icon: const Icon(LucideIcons.arrowLeft, size: 16),
                label: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _saving || _uploading || _name.text.trim().isEmpty || (!widget.isEdit && _industry.isEmpty)
                    ? null
                    : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(LucideIcons.sparkles, size: 16),
                label: Text(
                  widget.isEdit ? (_saving ? 'Saving…' : 'Save Changes') : (_saving ? 'Creating…' : 'Create Brand'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImportingOverlay extends StatelessWidget {
  const _ImportingOverlay();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.4),
        child: Center(
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.blue600)),
                      Icon(LucideIcons.upload, size: 20, color: AppColors.blue600),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Importing your brand…',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray900),
                ),
                const SizedBox(height: 4),
                Text('Extracting colors, fonts, and assets', style: TextStyle(fontSize: 12.5, color: c.gray500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
