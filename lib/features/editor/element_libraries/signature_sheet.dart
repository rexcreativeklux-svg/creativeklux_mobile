import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/api/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import '../design_editor_controller.dart';
import '../editor_sheets.dart';
import 'element_inserts.dart';
import 'element_sheets.dart';

/// Tools → Signature — port of the web's `panels/tools/signature/`
/// (SignatureFlyout → SignatureCreateView with its Text · Draw · Upload tabs).
///
/// The web's saved-signature list is always empty (useSignatures has no
/// endpoint yet), so the sheet opens straight on Create; the "Save signature"
/// switch is shown disabled with the web's own note. What lands on the page
/// follows insertSignature.js: typed → a TEXT element in a script face; drawn
/// or uploaded → an IMAGE element.
Future<void> showSignatureSheet(BuildContext context, DesignEditorController c, {VoidCallback? onInserted}) =>
    elementSheet(
      context,
      title: 'Create signature',
      heightFactor: 0.85,
      // The sheet's own drag would steal vertical pen strokes.
      enableDrag: false,
      body: (_) => _SignatureCreate(c: c, onInserted: onInserted),
    );

/// signatureFonts.js — the script faces from the editor's font list.
const signatureFonts = [
  'Great Vibes', 'Sacramento', 'Dancing Script', 'Satisfy', //
  'Caveat', 'Pacifico', 'Lobster', 'Permanent Marker',
];

/// SignatureColorPicker presets. The web adds the browser's free colour
/// picker; the app has none, so a few more inks stand in for it.
const _inks = ['#111827', '#1d4ed8', '#000000', '#dc2626', '#047857', '#7c3aed'];

Color _hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));

/// One pen stroke: points in surface pixels, its own colour and weight
/// (captured per stroke, so changing the ink mid-drawing does the expected thing).
class SignatureStroke {
  SignatureStroke(this.color, this.width) : points = [];
  final Color color;
  final double width;
  final List<Offset> points;
}

/// signatureDraw.js `renderStroke`: smoothed through the midpoints of
/// consecutive points; a single tap is a dot.
void paintSignatureStrokes(Canvas c, List<SignatureStroke> strokes, [Offset shift = Offset.zero]) {
  for (final s in strokes) {
    if (s.points.isEmpty) continue;
    final pts = [for (final p in s.points) p + shift];
    if (pts.length == 1) {
      c.drawCircle(pts.first, s.width / 2, Paint()..color = s.color);
      continue;
    }
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = (pts[i] + pts[i + 1]) / 2;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }
}

/// `strokesToTrimmedDataURL`: the ink cropped to its bounds (padded by the
/// fattest stroke so round caps aren't clipped), at [scale]× for crispness, as
/// a transparent PNG. Null when nothing is drawn.
Future<(Uint8List, int, int)?> signatureToPng(List<SignatureStroke> strokes, {double scale = 2}) async {
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  var maxW = 0.0;
  for (final s in strokes) {
    maxW = math.max(maxW, s.width);
    for (final p in s.points) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
  }
  if (!minX.isFinite) return null;
  final w = math.max(1.0, maxX - minX + maxW * 2);
  final h = math.max(1.0, maxY - minY + maxW * 2);
  final pw = (w * scale).ceil(), ph = (h * scale).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);
  paintSignatureStrokes(canvas, strokes, Offset(maxW - minX, maxW - minY));
  final picture = recorder.endRecording();
  final image = await picture.toImage(pw, ph);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    return (data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), pw, ph);
  } finally {
    image.dispose();
  }
}

TextStyle _script(String family, double size, Color color) {
  try {
    return GoogleFonts.getFont(family, fontSize: size, color: color);
  } catch (_) {
    return TextStyle(fontSize: size, color: color);
  }
}

class _SignatureCreate extends StatefulWidget {
  const _SignatureCreate({required this.c, this.onInserted});
  final DesignEditorController c;
  final VoidCallback? onInserted;
  @override
  State<_SignatureCreate> createState() => _SignatureCreateState();
}

class _SignatureCreateState extends State<_SignatureCreate> {
  // useSignatureDraft: ONE draft across the tabs, so switching keeps it.
  var _tab = 'text';
  final _name = TextEditingController();
  var _font = signatureFonts.first;
  var _color = _inks.first;
  final _strokes = <SignatureStroke>[];
  var _strokeWidth = 4.0;
  XFile? _file;
  Uint8List? _fileBytes;
  var _busy = false;

  DesignEditorController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _ready => switch (_tab) {
    'text' => _name.text.trim().isNotEmpty,
    'draw' => _strokes.isNotEmpty,
    _ => _fileBytes != null,
  };

  /// Upload a picture; on failure fall back to a data URL (what the web
  /// always inserts for a drawn signature) so the signature still lands.
  Future<String> _hosted(Uint8List bytes, String name, String mime) async {
    try {
      final url = await context.read<AuthController>().brandApi.uploadImage(bytes, name);
      if (url == null) throw AppException('The upload returned no file URL.');
      return url;
    } catch (_) {
      Toast.warning("Couldn't upload the signature — it's embedded in the design instead.");
      return 'data:$mime;base64,${base64Encode(bytes)}';
    }
  }

  Future<void> _add() async {
    if (!_ready || _busy) return;
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      if (_tab == 'text') {
        insertSignatureText(c, name: _name.text.trim(), fontFamily: cssFontFamily(_font), color: _color);
      } else if (_tab == 'draw') {
        final png = await signatureToPng(_strokes);
        if (png == null) return;
        final src = await _hosted(png.$1, 'signature.png', 'image/png');
        await insertSignatureImage(c, src, naturalSize: (png.$2.toDouble(), png.$3.toDouble()));
      } else {
        final src = await _hosted(_fileBytes!, _file!.name, _file!.mimeType ?? 'image/png');
        await insertSignatureImage(c, src);
      }
      widget.onInserted?.call();
      nav.pop();
    } catch (err) {
      Toast.error(toUserMessage(err, "Couldn't add the signature."));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        // SignatureTabs — underline tabs.
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: col.gray100)),
          ),
          child: Row(
            children: [
              for (final (id, label) in const [('text', 'Text'), ('draw', 'Draw'), ('upload', 'Upload')])
                InkWell(
                  onTap: () => setState(() => _tab = id),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
                    margin: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: _tab == id ? AppColors.blue600 : Colors.transparent, width: 2),
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: _tab == id ? AppColors.blue600 : col.gray500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...switch (_tab) {
          'text' => _textTab(context),
          'draw' => _drawTab(context),
          _ => _uploadTab(context),
        },
        const SizedBox(height: 14),
        // SaveSignatureToggle — honest about there being nowhere to save yet.
        Row(
          children: [
            const Switch(value: false, onChanged: null),
            const SizedBox(width: 6),
            Text('Save signature', style: TextStyle(fontSize: 13.5, color: col.gray700)),
          ],
        ),
        Text(
          'Saving isn’t available yet — it’ll still be added to your design.',
          style: TextStyle(fontSize: 11, color: col.gray400),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _ready && !_busy ? _add : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blue600,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Add signature', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _inkPicker() => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final ink in _inks) Swatch(value: ink, selected: _color == ink, onTap: () => setState(() => _color = ink)),
    ],
  );

  // ── Text (SignatureTextTab + SignaturePreview) ──

  List<Widget> _textTab(BuildContext context) {
    final col = context.colors;
    return [
      Container(
        height: 96,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: col.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: col.gray200),
        ),
        child: _name.text.trim().isEmpty
            ? Text('Your signature appears here', style: TextStyle(fontSize: 12, color: col.gray400))
            : Text(_name.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: _script(_font, 32, _hex(_color))),
      ),
      const SizedBox(height: 14),
      sectionLabel(context, 'Full name'),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          hintText: 'Type your name',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      const SizedBox(height: 14),
      sectionLabel(context, 'Font'),
      SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: signatureFonts.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final f = signatureFonts[i];
            final on = f == _font;
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _font = f),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? col.blueTint : null,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: on ? AppColors.blue500 : col.gray200),
                ),
                child: Text(f, style: _script(f, 17, col.gray800)),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 14),
      sectionLabel(context, 'Colour'),
      _inkPicker(),
    ];
  }

  // ── Draw (SignatureDrawTab + SignatureDrawCanvas) ──

  List<Widget> _drawTab(BuildContext context) {
    final col = context.colors;
    return [
      _SignaturePad(strokes: _strokes, color: _hex(_color), width: _strokeWidth, onChanged: () => setState(() {})),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _strokes.isEmpty ? null : () => setState(() => _strokes.removeLast()),
              icon: const Icon(LucideIcons.undo2, size: 15),
              label: const Text('Undo'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear),
              child: const Text('Clear'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      sectionLabel(context, 'Weight'),
      Row(
        children: [
          Expanded(
            child: Slider(
              value: _strokeWidth,
              min: 1,
              max: 20,
              divisions: 19,
              onChanged: (v) => setState(() => _strokeWidth = v),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              '${_strokeWidth.round()}',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12.5, color: col.gray600),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      sectionLabel(context, 'Colour'),
      _inkPicker(),
    ];
  }

  // ── Upload (SignatureUploadTab) ──

  Future<void> _pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (mounted) {
      setState(() {
        _file = f;
        _fileBytes = bytes;
      });
    }
  }

  List<Widget> _uploadTab(BuildContext context) {
    final col = context.colors;
    if (_fileBytes != null) {
      return [
        Container(
          height: 140,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: col.gray50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: col.gray200),
          ),
          child: Stack(
            children: [
              Center(child: Image.memory(_fileBytes!, fit: BoxFit.contain)),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton.filled(
                  tooltip: 'Remove',
                  iconSize: 14,
                  style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                  onPressed: () => setState(() {
                    _file = null;
                    _fileBytes = null;
                  }),
                  icon: const Icon(LucideIcons.x),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _file!.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: col.gray400),
        ),
      ];
    }
    return [
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _pick,
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: col.gray300),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.cloudUpload, size: 28, color: col.gray400),
              const SizedBox(height: 6),
              Text('Upload a signature image', style: TextStyle(fontSize: 13.5, color: col.gray500)),
              Text('PNG with transparency works best', style: TextStyle(fontSize: 10.5, color: col.gray400)),
            ],
          ),
        ),
      ),
    ];
  }
}

/// The surface you sign on. Pointer events come through a raw Listener and an
/// eager recogniser claims the gesture arena on touch-down, so neither the
/// sheet's list nor anything else scrolls while you write.
class _SignaturePad extends StatefulWidget {
  const _SignaturePad({required this.strokes, required this.color, required this.width, required this.onChanged});
  final List<SignatureStroke> strokes;
  final Color color;
  final double width;
  final VoidCallback onChanged;

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  SignatureStroke? _active;
  int? _pointer;

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _active = SignatureStroke(widget.color, widget.width)..points.add(e.localPosition);
    setState(() {});
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    setState(() => _active?.points.add(e.localPosition));
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final s = _active;
    _active = null;
    if (s != null && s.points.isNotEmpty) widget.strokes.add(s);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    final empty = widget.strokes.isEmpty && _active == null;
    return Container(
      height: 170,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // The ink colours are dark, so the pad stays white even in dark mode
        // — it's a piece of paper, like the canvas it lands on.
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.gray200),
      ),
      child: RawGestureDetector(
        gestures: {
          EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            EagerGestureRecognizer.new,
            (_) {},
          ),
        },
        child: Listener(
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          child: CustomPaint(
            painter: _PadPainter([...widget.strokes, ?_active]),
            child: Center(
              child: empty
                  ? const Text('Draw your signature here', style: TextStyle(fontSize: 13.5, color: Color(0xFF9CA3AF)))
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.strokes);
  final List<SignatureStroke> strokes;
  @override
  void paint(Canvas canvas, Size size) => paintSignatureStrokes(canvas, strokes);
  // Strokes grow in place, so always repaint (the list is rebuilt per frame).
  @override
  bool shouldRepaint(covariant _PadPainter old) => true;
}
