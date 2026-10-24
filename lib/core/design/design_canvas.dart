import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import 'design_renderer.dart';
import 'js_values.dart';

/// Widget that renders the design once (async), caches the ui.Image, and displays it
/// scaled to fit the available width (keeping the canvas aspect ratio), with a neutral
/// shimmer/placeholder (context.colors.gray100) while rendering and a quiet fallback on failure.
///
/// The mobile counterpart of the web's design thumbnails, which paint the
/// layout JSON through `renderDesign.js` rather than shipping a stored PNG.
class DesignCanvas extends StatefulWidget {
  const DesignCanvas({super.key, required this.canvas, required this.elements, this.scraive = false, this.maxHeight});

  final Map<String, dynamic> canvas;
  final List<dynamic> elements;
  final bool scraive;
  final double? maxHeight;

  @override
  State<DesignCanvas> createState() => _DesignCanvasState();
}

class _DesignCanvasState extends State<DesignCanvas> with SingleTickerProviderStateMixin {
  /// The long side of the rendered bitmap. Enough for a full-width preview on
  /// a tablet without holding a poster-sized image per card in memory.
  static const _maxRenderSide = 1600.0;

  ui.Image? _image;
  bool _failed = false;

  /// Bumped per render so a slow render that finishes after a newer one
  /// started can't overwrite it.
  int _generation = 0;

  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  double get _width => orNum(widget.canvas['width'], 1080);
  double get _height => orNum(widget.canvas['height'], 1080);

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(DesignCanvas old) {
    super.didUpdateWidget(old);
    if (!identical(old.canvas, widget.canvas) ||
        !identical(old.elements, widget.elements) ||
        old.scraive != widget.scraive) {
      _render();
    }
  }

  Future<void> _render() async {
    final gen = ++_generation;
    if (_failed) setState(() => _failed = false);
    if (!_pulse.isAnimating) _pulse.repeat(reverse: true);

    final ratio = math.min(2.0, _maxRenderSide / math.max(_width, _height));
    try {
      final image = await renderDesign(widget.canvas, widget.elements, scraive: widget.scraive, pixelRatio: ratio);
      if (!mounted || gen != _generation) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
      });
      _pulse.stop();
    } catch (_) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _image?.dispose();
        _image = null;
        _failed = true;
      });
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _generation++;
    _pulse.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final aspect = _width / _height;

    return LayoutBuilder(
      builder: (context, constraints) {
        var w = constraints.maxWidth.isFinite ? constraints.maxWidth : _width;
        var h = w / aspect;
        final maxH = widget.maxHeight ?? (constraints.maxHeight.isFinite ? constraints.maxHeight : null);
        if (maxH != null && h > maxH) {
          h = maxH;
          w = h * aspect;
        }

        final Widget child;
        if (_image != null) {
          child = RawImage(image: _image, width: w, height: h, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
        } else if (_failed) {
          child = ColoredBox(
            color: colors.gray100,
            child: Center(child: Icon(LucideIcons.imageOff, size: 22, color: colors.gray400)),
          );
        } else {
          // A soft pulse rather than a moving sheen — quiet in a grid of cards.
          child = FadeTransition(
            opacity: Tween<double>(begin: 0.55, end: 1).animate(_pulse),
            child: ColoredBox(color: colors.gray100),
          );
        }

        return Center(
          child: SizedBox(width: w, height: h, child: child),
        );
      },
    );
  }
}
