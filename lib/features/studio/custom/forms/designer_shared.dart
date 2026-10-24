import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/ui/media.dart';
import '../../../auth/auth_controller.dart';
import '../../../editor/editor_api.dart';
import '../studio_form_kit.dart';

/// Pieces the Designer Creative forms (Logo, Business Card, Banners, Flyer,
/// Brochure) all re-declare on the web: the "Reference Images" / "Background
/// Image" last step and the two-up field grid.

/// The web's `<BrandImagesStrip>` cap — five images in total per form.
const designerImageCap = 5;

/// The web's `grid grid-cols-2 gap-4` field pairs. On a phone two inputs side
/// by side get too narrow to type in, so they stack until there's room.
class FieldPair extends StatelessWidget {
  const FieldPair({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => box.maxWidth >= 520
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 14),
              Expanded(child: right),
            ],
          )
        : FormColumn(children: [left, right]),
  );
}

/// The last step of every designer form: the brand images strip, what's been
/// picked, and the "Choose Media" zone. The web's zone opens MediaPickerModal
/// (web search / Magic Studio / device) then a cropper; here it's the phone's
/// gallery, uploaded to ours, so the payload gets hosted URLs.
class DesignerImagesStep extends StatelessWidget {
  const DesignerImagesStep({
    super.key,
    required this.host,
    required this.title,
    required this.images,
    required this.onChanged,
    required this.zoneTitle,
    required this.zoneSubtitle,
    this.intro,
    this.selectedLabel = 'Selected',
  });

  final StudioFormHost host;
  final String title;
  final String? intro;
  final List<String> images;
  final ValueChanged<List<String>> onChanged;
  final String zoneTitle;
  final String zoneSubtitle;
  final String selectedLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = host.color;
    return FormColumn(
      gap: 14,
      children: [
        FormSectionTitle(title),
        if (intro != null) Text(intro!, style: TextStyle(fontSize: 12, color: c.gray400, height: 1.4)),
        BrandImagesStrip(selected: images, onChanged: onChanged, accent: accent),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.25), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accent.withValues(alpha: 0.25)),
                    ),
                    child: Icon(LucideIcons.fileUp, size: 17, color: accent.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          zoneTitle,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.gray700),
                        ),
                        const SizedBox(height: 2),
                        Text(zoneSubtitle, style: TextStyle(fontSize: 11.5, color: c.gray400)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (images.isNotEmpty) ...[
                Text(
                  '$selectedLabel (${images.length})',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
                ),
                const SizedBox(height: 8),
              ],
              ImageListField(
                api: host.api,
                images: images,
                onChanged: onChanged,
                accent: accent,
                max: designerImageCap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Port of `(components)/BrandImagesStrip.jsx`: the first 8 images in the
/// user's library, tap to add / remove, capped at [designerImageCap] in total.
///
/// The web stages picks in a local set and confirms with "Use" (or "Crop");
/// on a phone a tap adds the image straight away — one less step, and there's
/// no cropper here.
class BrandImagesStrip extends StatefulWidget {
  const BrandImagesStrip({super.key, required this.selected, required this.onChanged, required this.accent});

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final Color accent;

  @override
  State<BrandImagesStrip> createState() => _BrandImagesStripState();
}

class _BrandImagesStripState extends State<BrandImagesStrip> {
  static const _maxImages = 8;

  List<GalleryItem>? _images;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (items, more) = await EditorApi(context.read<AuthController>().api).gallery();
    if (!mounted) return;
    // Dedupe by src — the backend sometimes returns duplicates (same as the web).
    final seen = <String>{};
    setState(() {
      _images = [
        for (final i in items)
          if (seen.add(i.src)) i,
      ];
      _hasMore = more;
    });
  }

  void _toggle(String src) {
    final sel = widget.selected;
    if (sel.contains(src)) return widget.onChanged([...sel]..remove(src));
    if (sel.length >= designerImageCap) return;
    widget.onChanged([...sel, src]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final all = _images;
    if (all == null) {
      return Row(
        children: [
          SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.5, color: c.gray400)),
          const SizedBox(width: 8),
          Text('Loading your images…', style: TextStyle(fontSize: 12, color: c.gray400)),
        ],
      );
    }
    if (all.isEmpty) return const SizedBox.shrink();
    final shown = all.take(_maxImages).toList();
    final atCap = widget.selected.length >= designerImageCap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(LucideIcons.image, size: 14, color: c.gray400),
            const SizedBox(width: 6),
            Text(
              'Your brand images',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
            ),
            const Spacer(),
            if (_hasMore || all.length > _maxImages) ...[
              Text('Showing $_maxImages', style: TextStyle(fontSize: 10.5, color: c.gray400)),
              const SizedBox(width: 6),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: atCap ? AppColors.amber500.withValues(alpha: 0.15) : c.gray100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${widget.selected.length} / $designerImageCap selected',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: atCap ? Color.lerp(AppColors.amber500, Colors.black, 0.35) : c.gray400,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (atCap) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.amber500.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.amber500.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Maximum of $designerImageCap images reached. Remove an image to add more.',
              style: TextStyle(fontSize: 11, color: Color.lerp(AppColors.amber500, Colors.black, 0.35)),
            ),
          ),
          const SizedBox(height: 8),
        ],
        GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [for (final img in shown) _tile(context, img.src, atCap)],
        ),
        if (!atCap) ...[
          const SizedBox(height: 6),
          Text(
            'Tap images to add them',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: c.gray400),
          ),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, String src, bool atCap) {
    final c = context.colors;
    final picked = widget.selected.contains(src);
    final disabled = atCap && !picked;
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: GestureDetector(
        onTap: disabled ? null : () => _toggle(src),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: picked ? widget.accent : c.gray100, width: picked ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MediaImage(src, cacheWidth: 200),
              Positioned(
                top: 5,
                left: 5,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: picked ? widget.accent : c.surface.withValues(alpha: 0.8),
                    border: Border.all(color: picked ? widget.accent : c.gray300, width: 1.5),
                  ),
                  child: picked ? const Icon(LucideIcons.check, size: 11, color: Colors.white) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
