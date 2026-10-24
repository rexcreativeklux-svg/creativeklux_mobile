import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/media.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import 'magic_tool_tab.dart';
import 'magic_tools.dart';

/// Magic Studio panel — the editor's take on Canva's Magic Media. Port of
/// `design/[id]/_components/panels/magic/MagicMediaPanel.jsx`.
///
/// Two kinds of tab, as declared in [magicTabs]:
///   • LIVE (Images, Variations, Persona) → [MagicToolTab], the same generate +
///     history endpoints as the /magic-studio page. A finished image drops onto
///     the design via [onInsertImage] and lands in that tool's History.
///   • PLACEHOLDER (Graphics, 3D) → [_PlaceholderTab]; their pipelines aren't
///     connected, so Generate explains that instead of calling the backend.
///
/// No video tab, as on the web. [onInsertVideo] is still needed: History shows
/// every record of a tool, and a video made elsewhere can be placed from there.
///
/// Tabs are built lazily and then KEPT (an IndexedStack of the visited ones),
/// unlike the web, which remounts per tool. Each still keeps its own form, but
/// switching tabs mid-run no longer abandons the run. Closing the whole panel
/// does — see [MagicToolTab].
class MagicMediaPanel extends StatefulWidget {
  const MagicMediaPanel({super.key, required this.onInsertImage, required this.onInsertVideo, this.selectedImageSrc});

  final Future<void> Function(String url) onInsertImage;
  final Future<void> Function(String url) onInsertVideo;

  /// The `src` of the image currently selected on the canvas, read when
  /// "Use selected image" (Variations) is tapped. Leave null to hide the button.
  final String? Function()? selectedImageSrc;

  @override
  State<MagicMediaPanel> createState() => _MagicMediaPanelState();
}

class _MagicMediaPanelState extends State<MagicMediaPanel> {
  var _tab = 0;
  final _visited = <int>{0};

  @override
  Widget build(BuildContext context) {
    final api = context.read<AuthController>().api;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MagicTabs(
          value: _tab,
          onChange: (i) => setState(() {
            _tab = i;
            _visited.add(i);
          }),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            sizing: StackFit.expand,
            children: [
              for (var i = 0; i < magicTabs.length; i++)
                if (!_visited.contains(i))
                  const SizedBox.shrink()
                else if (magicTabs[i].tool case final tool?)
                  MagicToolTab(
                    key: ValueKey(tool),
                    config: magicToolConfigs[tool]!,
                    api: api,
                    onInsertImage: widget.onInsertImage,
                    onInsertVideo: widget.onInsertVideo,
                    selectedImageSrc: widget.selectedImageSrc,
                  )
                else
                  _PlaceholderTab(key: ValueKey(magicTabs[i].id), tab: magicTabs[i]),
            ],
          ),
        ),
      ],
    );
  }
}

/// The tool switcher — an underline tab row (MagicTabs.jsx). More tabs than a
/// 300px column fits, so it scrolls sideways rather than wrapping.
class _MagicTabs extends StatelessWidget {
  const _MagicTabs({required this.value, required this.onChange});

  final int value;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.gray100)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < magicTabs.length; i++)
              InkWell(
                onTap: () => onChange(i),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: i == value ? AppColors.blue600 : Colors.transparent, width: 2),
                    ),
                  ),
                  child: Text(
                    magicTabs[i].label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: i == value ? c.gray900 : c.gray400,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The full-width blue Generate button (GenerationTab.jsx / MagicToolTab.jsx).
class MagicGenerateButton extends StatelessWidget {
  const MagicGenerateButton({super.key, required this.label, required this.generating, required this.onPressed});

  final String label;
  final bool generating;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FilledButton.icon(
      onPressed: onPressed,
      icon: generating
          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.gray400))
          : const Icon(LucideIcons.sparkles, size: 16),
      label: Text(generating ? 'Generating…' : label),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.blue600,
        foregroundColor: Colors.white,
        disabledBackgroundColor: c.gray200,
        disabledForegroundColor: c.gray400,
        minimumSize: const Size.fromHeight(44),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// "Created by Magic Studio" — pulsing placeholders while a batch generates,
/// then the tiles; tap one to put it on the design (ResultsGrid.jsx).
class MagicResultsGrid extends StatelessWidget {
  const MagicResultsGrid({
    super.key,
    required this.urls,
    required this.generating,
    required this.onPick,
    this.skeletons = magicGenCount,
  });

  final List<String> urls;
  final bool generating;
  final int skeletons;
  final void Function(String url) onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!generating && urls.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Created by Magic Studio',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray800),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            if (generating)
              for (var i = 0; i < skeletons; i++) const _Skeleton(),
            for (final url in urls)
              Material(
                color: c.gray50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: c.gray200),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(onTap: () => onPick(url), child: MediaImage(url, cacheWidth: 400)),
              ),
          ],
        ),
      ],
    );
  }
}

class _Skeleton extends StatefulWidget {
  const _Skeleton();

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.5, end: 1.0).animate(_pulse),
      child: DecoratedBox(
        decoration: BoxDecoration(color: context.colors.gray100, borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

/// A placeholder tab (Graphics / 3D) — port of GenerationTab.jsx +
/// useMagicGenerate.js (the PLACEHOLDER machine) + PromptBox.jsx +
/// GenerateControls.jsx. Graphics has a style picker; 3D has no controls. The
/// generators throw MagicNotConnectedError on the web, so pressing Generate
/// only explains that the pipeline isn't connected yet.
class _PlaceholderTab extends StatefulWidget {
  const _PlaceholderTab({super.key, required this.tab});

  final MagicTab tab;

  @override
  State<_PlaceholderTab> createState() => _PlaceholderTabState();
}

class _PlaceholderTabState extends State<_PlaceholderTab> {
  final _prompt = TextEditingController();
  final _random = Random();
  var _style = placeholderStyles.first;
  var _styleOpen = false;

  bool get _useStyle => widget.tab.id == 'graphics';

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  void _inspire() {
    // Vary the pick off the current value so "Inspire me" doesn't repeat itself.
    final others = placeholderInspire.where((p) => p != _prompt.text.trim()).toList();
    setState(() => _prompt.text = others[_random.nextInt(others.length)]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final words = magicWordCount(_prompt.text);
    final short = words > 0 && words < magicMinWords;
    final left = magicMinWords - words;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          'Describe what you’d like to create',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.gray800),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _prompt,
          minLines: 4,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
          style: TextStyle(fontSize: 14, color: c.gray700),
          decoration: InputDecoration(
            hintText: 'Enter $magicMinWords+ words to describe…',
            isDense: true,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _inspire,
              icon: const Icon(LucideIcons.lightbulb, size: 14),
              label: const Text('Inspire me'),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.gray600,
                side: BorderSide(color: c.gray200),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const Spacer(),
            if (short) Text('$left more word${left == 1 ? '' : 's'}', style: TextStyle(fontSize: 11, color: c.gray400)),
          ],
        ),
        if (_useStyle) ...[
          const SizedBox(height: 16),
          // GenerateControls' Styles picker, opened in place rather than as a
          // floating dropdown (no room beside a phone-width panel).
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _styleOpen = !_styleOpen),
              icon: const Icon(LucideIcons.wandSparkles, size: 14),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_style.id == 'none' ? 'Styles' : _style.label),
                  const SizedBox(width: 4),
                  const Icon(LucideIcons.chevronDown, size: 14),
                ],
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _styleOpen ? AppColors.blue600 : c.gray600,
                backgroundColor: _styleOpen ? c.blueTint : null,
                side: BorderSide(color: _styleOpen ? AppColors.blue500 : c.gray200),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                minimumSize: const Size(0, 34),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          if (_styleOpen) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.gray100),
              ),
              child: LayoutBuilder(
                builder: (context, box) => Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final s in placeholderStyles)
                      SizedBox(
                        width: (box.maxWidth - 4) / 2,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(() {
                            _style = s;
                            _styleOpen = false;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: s.id == _style.id ? c.blueTint : null,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: s.id == _style.id ? AppColors.blue600 : c.gray600,
                                    ),
                                  ),
                                ),
                                if (s.id == _style.id) Icon(LucideIcons.check, size: 14, color: AppColors.blue600),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: 16),
        MagicGenerateButton(
          label: 'Generate ${widget.tab.noun}',
          generating: false,
          onPressed: words >= magicMinWords ? () => Toast.info(notConnectedMessage(widget.tab.noun)) : null,
        ),
      ],
    );
  }
}
