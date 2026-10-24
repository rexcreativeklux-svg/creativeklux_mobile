import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/ui/media.dart';
import '../../../../../core/ui/toast.dart';
import '../../../../auth/auth_controller.dart';
import '../../../../editor/editor_api.dart';
import '../../custom_studio_api.dart';
import 'social_sizes.dart';

/// The image step of SocialImageForm / ReelsForm: the web's `BrandImagesStrip`
/// (your gallery, tap to pick) + the "Selected (n)" grid + the
/// `MediaPickerModal` upload zone, as one phone-sized field. Holds hosted URLs,
/// capped at [maxImages] across every source, like the web.
///
/// The web's cropper (`ImageCropperModal`, to the selected size's aspect) and
/// the picker's web search / Magic Studio tabs aren't here: images go in as
/// they are, from the gallery, the brand import, or the phone.
class SocialMediaField extends StatefulWidget {
  const SocialMediaField({
    super.key,
    required this.api,
    required this.images,
    required this.onChanged,
    required this.accent,
    required this.title,
    required this.subtitle,
    this.icon = LucideIcons.fileUp,
    this.suggested = const [],
  });

  final CustomStudioApi api;
  final List<String> images;
  final ValueChanged<List<String>> onChanged;
  final Color accent;

  /// The upload zone's heading and hint.
  final String title;
  final String subtitle;
  final IconData icon;

  /// Images the URL import found (the web's `formData.importedImages`), shown
  /// ahead of the gallery.
  final List<String> suggested;

  @override
  State<SocialMediaField> createState() => _SocialMediaFieldState();
}

class _SocialMediaFieldState extends State<SocialMediaField> {
  List<String> _gallery = const [];
  bool _loadingGallery = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadGallery();
  }

  Future<void> _loadGallery() async {
    final (items, _) = await EditorApi(context.read<AuthController>().api).gallery();
    if (!mounted) return;
    setState(() {
      _gallery = [for (final i in items) i.src];
      _loadingGallery = false;
    });
  }

  int get _remaining => (maxImages - widget.images.length).clamp(0, maxImages);

  void _toggle(String url) {
    if (widget.images.contains(url)) return widget.onChanged([...widget.images]..remove(url));
    if (_remaining <= 0) return Toast.warning('Max $maxImages items reached.');
    widget.onChanged([...widget.images, url]);
  }

  /// Phone stand-in for the picker's Upload tab: pick up to the remaining
  /// slots, upload each to the gallery, and add the hosted URLs.
  Future<void> _upload() async {
    if (_remaining <= 0) return Toast.warning('Max $maxImages items reached.');
    final picker = ImagePicker();
    // pickMultiImage needs a limit of at least 2.
    final files = _remaining == 1
        ? [?await picker.pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048)]
        : await picker.pickMultiImage(limit: _remaining, maxWidth: 2048, maxHeight: 2048);
    if (files.isEmpty || !mounted) return;
    final toAdd = files.take(_remaining).toList();
    setState(() => _uploading = true);
    final urls = <String>[];
    var failed = 0;
    for (final f in toAdd) {
      final bytes = await f.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        failed++;
        continue;
      }
      try {
        final url = await widget.api.uploadImage(bytes, f.name);
        url == null ? failed++ : urls.add(url);
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _gallery = [...urls, ..._gallery];
    });
    if (urls.isNotEmpty) {
      widget.onChanged([...widget.images, ...urls]);
      Toast.success('${urls.length} image${urls.length > 1 ? 's' : ''} added ✓');
    }
    if (failed > 0) Toast.error("Some images couldn't be uploaded (max 10 MB each).");
    if (files.length > toAdd.length) Toast.warning('Only added what fits — max $maxImages.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = widget.accent;
    final strip = <String>{...widget.suggested, ..._gallery}.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Brand images strip ──
        Row(
          children: [
            Icon(LucideIcons.images, size: 14, color: c.gray500),
            const SizedBox(width: 6),
            Text(
              'Your images',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
            ),
            const Spacer(),
            Text('Tap to select', style: TextStyle(fontSize: 11, color: c.gray400)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 76,
          child: _loadingGallery && strip.isEmpty
              ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : strip.isEmpty
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'No images in your gallery yet — upload some below.',
                    style: TextStyle(fontSize: 12, color: c.gray400),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: strip.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final url = strip[i];
                    final selected = widget.images.contains(url);
                    return GestureDetector(
                      onTap: () => _toggle(url),
                      child: Container(
                        width: 76,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: selected ? accent : c.gray200, width: selected ? 2 : 1),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MediaImage(url, cacheWidth: 200),
                            if (selected)
                              Container(
                                color: accent.withValues(alpha: 0.25),
                                alignment: Alignment.topRight,
                                padding: const EdgeInsets.all(4),
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                                  child: const Icon(LucideIcons.check, size: 11, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // ── Already-selected previews ──
        if (widget.images.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Selected (${widget.images.length})',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            clipBehavior: Clip.none,
            children: [
              for (final url in widget.images)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: MediaImage(url, cacheWidth: 160),
                      ),
                    ),
                    Positioned(
                      top: -5,
                      right: -5,
                      child: GestureDetector(
                        onTap: () => widget.onChanged([...widget.images]..remove(url)),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(color: AppColors.red500, shape: BoxShape.circle),
                          child: const Icon(LucideIcons.x, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],

        // ── Upload zone ──
        const SizedBox(height: 16),
        InkWell(
          onTap: _uploading ? null : _upload,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: c.gray50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.gray200, width: 1.5),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.gray200),
                  ),
                  child: Icon(widget.icon, size: 19, color: c.gray400),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.gray700),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: c.gray400),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _uploading ? null : _upload,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  icon: _uploading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.images, size: 16),
                  label: Text(_uploading ? 'Uploading…' : 'Choose Media'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
