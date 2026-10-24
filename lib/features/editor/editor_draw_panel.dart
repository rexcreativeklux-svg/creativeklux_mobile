import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import 'design_stage.dart';
import 'editor_panels.dart';
import 'editor_sheets.dart';
import 'element_libraries/signature_sheet.dart';

/// Tools → Draw — port of the web's `panels/ToolsPanel.jsx` draw flyout plus its
/// Lines flyout. While this panel is open the stage draws instead of selecting
/// (leaving it stops drawing, as on the web).
class DrawPanel extends StatelessWidget {
  const DrawPanel({super.key, required this.tool, required this.onTool, required this.insert});

  final DrawTool tool;
  final ValueChanged<DrawTool> onTool;
  final EditorInserts insert;

  /// Per-tool defaults (TOOL_PRESETS).
  static const presets = {'pen': (6.0, 1.0), 'marker': (16.0, 1.0), 'highlighter': (24.0, 0.35), 'eraser': (20.0, 1.0)};

  static const _colors = ['#111827', '#ef4444', '#f59e0b', '#22c55e', '#8b5cf6', '#3b82f6', '#ffffff'];

  /// The Lines flyout, straight variants first (LINE_TYPES).
  static const _lines = [
    'line-solid', 'line-double', 'line-dashed', 'line-long-dash', 'line-dotted', 'line-dash-dot', //
    'line-wavy', 'line-zigzag', 'line-arrow', 'line-arrow-left', 'line-arrow-both', 'line-elbow', 'line-curved',
  ];

  DrawTool _with({String? type, String? color, double? size, double? opacity}) => DrawTool(
    type: type ?? tool.type,
    color: color ?? tool.color,
    size: size ?? tool.size,
    opacity: opacity ?? tool.opacity,
  );

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    final eraser = tool.type == 'eraser';
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        Text(
          eraser ? 'Drag over a stroke to erase it.' : 'Draw on the page with one finger · pinch to zoom.',
          style: TextStyle(fontSize: 12, color: col.gray500),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final (type, icon, label) in [
              ('pen', LucideIcons.pen, 'Pen'),
              ('marker', LucideIcons.paintbrush, 'Marker'),
              ('highlighter', LucideIcons.highlighter, 'Highlighter'),
              ('eraser', LucideIcons.eraser, 'Eraser'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _ToolChip(
                    icon: icon,
                    label: label,
                    on: tool.type == type,
                    onTap: () {
                      final (size, opacity) = presets[type]!;
                      onTool(_with(type: type, size: size, opacity: opacity));
                    },
                  ),
                ),
              ),
          ],
        ),
        if (!eraser) ...[
          const SizedBox(height: 16),
          sectionLabel(context, 'Colour'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in _colors)
                Swatch(
                  value: c,
                  size: 34,
                  selected: tool.color == c,
                  onTap: () => onTool(_with(color: c)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          sectionLabel(context, 'Weight · ${tool.size.round()}'),
          Slider(
            value: tool.size.clamp(1, 80),
            min: 1,
            max: 80,
            onChanged: (v) => onTool(_with(size: v.roundToDouble())),
          ),
          sectionLabel(context, 'Transparency · ${(tool.opacity * 100).round()}'),
          Slider(
            value: tool.opacity.clamp(0.05, 1),
            min: 0.05,
            max: 1,
            onChanged: (v) => onTool(_with(opacity: v)),
          ),
        ],
        const SizedBox(height: 10),
        // Tools → Signature (type, draw or upload one).
        OutlinedButton.icon(
          onPressed: () => showSignatureSheet(context, insert.c),
          icon: const Icon(LucideIcons.signature, size: 16),
          label: const Text('Add a signature'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
        ),
        const SizedBox(height: 14),
        sectionLabel(context, 'Lines'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in _lines)
              ActionChip(
                label: Text(key.replaceFirst('line-', '').replaceAll('-', ' ')),
                labelStyle: TextStyle(fontSize: 12, color: col.gray700),
                onPressed: () => insert.shape(key),
              ),
          ],
        ),
      ],
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.icon, required this.label, required this.on, required this.onTap});

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = on ? AppColors.blue600 : context.colors.gray600;
    return Material(
      color: on ? context.colors.blueTint : context.colors.gray50,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
