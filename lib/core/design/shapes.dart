import 'dart:math' as math;

/// Port of the web's `(lib)/design/shapes.js` (plus `textTemplateShapes.js`,
/// `frames.js` and `borderDash.js`) — the shape library the renderer draws.
///
/// Each shape is normalized to a viewBox and stretched to fill its element box
/// (preserveAspectRatio "none", Canva behaviour). `kind: stroke` shapes are lines
/// whose colour comes from the element's `fill`.
class ShapeDef {
  const ShapeDef(
    this.viewBox, {
    this.path,
    this.kind = 'fill',
    this.strokeW,
    this.dash,
    this.cap,
    this.bendable = false,
    this.shaftYs,
  });

  final List<double> viewBox;
  final String? path;
  final String kind;
  final double? strokeW;
  final List<double>? dash;
  final String? cap;
  final bool bendable;
  final List<double>? shaftYs;
}

const _sq = [100.0, 100.0];
const _line = [100.0, 12.0];

const Map<String, ShapeDef> _base = {
  // ── Basic ── (rect / rounded / circle / triangle have no path: primitives)
  'rect': ShapeDef(_sq),
  'rounded': ShapeDef(_sq),
  'circle': ShapeDef(_sq),
  'triangle': ShapeDef(_sq),
  'diamond': ShapeDef(_sq, path: 'M50 4 L96 50 L50 96 L4 50 Z'),
  'right-triangle': ShapeDef(_sq, path: 'M8 92 L8 8 L92 92 Z'),
  'semicircle': ShapeDef([100, 50], path: 'M2 48 A48 48 0 0 1 98 48 Z'),
  'arch': ShapeDef(_sq, path: 'M8 96 V44 A42 42 0 0 1 92 44 V96 Z'),
  'quarter-circle': ShapeDef(_sq, path: 'M8 92 V8 A84 84 0 0 1 92 92 Z'),
  'parallelogram': ShapeDef([100, 60], path: 'M26 6 H98 L74 54 H2 Z'),
  'trapezoid': ShapeDef([100, 60], path: 'M28 6 H72 L96 54 H4 Z'),
  'cross': ShapeDef(_sq, path: 'M38 4 H62 V38 H96 V62 H62 V96 H38 V62 H4 V38 H38 Z'),
  'chevron': ShapeDef([100, 70], path: 'M4 4 H58 L96 35 L58 66 H4 L40 35 Z'),
  'triangle-down': ShapeDef(_sq, path: 'M4 8 H96 L50 92 Z'),
  'parallelogram-left': ShapeDef([100, 60], path: 'M2 6 H74 L98 54 H26 Z'),
  'trapezoid-down': ShapeDef([100, 60], path: 'M4 6 H96 L72 54 H28 Z'),
  'tab': ShapeDef(_sq, path: 'M6 96 V32 Q6 6 30 6 H70 Q94 6 94 32 V96 Z'),
  'kite': ShapeDef(_sq, path: 'M50 4 L88 42 L50 96 L12 42 Z'),
  'l-shape': ShapeDef(_sq, path: 'M8 8 H40 V68 H92 V92 H8 Z'),

  // ── Lines ──
  'line-solid': ShapeDef(_line, path: 'M0 6 H100', kind: 'stroke', strokeW: 3, bendable: true, shaftYs: [6]),
  'line-double': ShapeDef(
    _line,
    path: 'M0 3 H100 M0 9 H100',
    kind: 'stroke',
    strokeW: 2,
    bendable: true,
    shaftYs: [3, 9],
  ),
  'line-dashed': ShapeDef(
    _line,
    path: 'M0 6 H100',
    kind: 'stroke',
    strokeW: 3,
    dash: [12, 8],
    bendable: true,
    shaftYs: [6],
  ),
  'line-long-dash': ShapeDef(
    _line,
    path: 'M0 6 H100',
    kind: 'stroke',
    strokeW: 3,
    dash: [20, 10],
    bendable: true,
    shaftYs: [6],
  ),
  'line-dotted': ShapeDef(
    _line,
    path: 'M0 6 H100',
    kind: 'stroke',
    strokeW: 3,
    dash: [0.5, 8],
    cap: 'round',
    bendable: true,
    shaftYs: [6],
  ),
  'line-dash-dot': ShapeDef(
    _line,
    path: 'M0 6 H100',
    kind: 'stroke',
    strokeW: 3,
    dash: [14, 7, 0.5, 7],
    cap: 'round',
    bendable: true,
    shaftYs: [6],
  ),
  'line-wavy': ShapeDef(
    _line,
    path: 'M2 6 Q8 1 14 6 T26 6 T38 6 T50 6 T62 6 T74 6 T86 6 T98 6',
    kind: 'stroke',
    strokeW: 3,
    cap: 'round',
  ),
  'line-zigzag': ShapeDef(
    _line,
    path: 'M2 6 L10 2 L18 10 L26 2 L34 10 L42 2 L50 10 L58 2 L66 10 L74 2 L82 10 L90 2 L98 6',
    kind: 'stroke',
    strokeW: 3,
    cap: 'round',
  ),
  'line-arrow': ShapeDef(_line, path: 'M2 6 H90 M90 6 L82 2.5 M90 6 L82 9.5', kind: 'stroke', strokeW: 3, cap: 'round'),
  'line-arrow-left': ShapeDef(
    _line,
    path: 'M98 6 H10 M10 6 L18 2.5 M10 6 L18 9.5',
    kind: 'stroke',
    strokeW: 3,
    cap: 'round',
  ),
  'line-arrow-both': ShapeDef(
    _line,
    path: 'M10 6 H90 M90 6 L82 2.5 M90 6 L82 9.5 M10 6 L18 2.5 M10 6 L18 9.5',
    kind: 'stroke',
    strokeW: 3,
    cap: 'round',
  ),
  'line-curved': ShapeDef(
    _line,
    path: 'M0 6 H100',
    kind: 'stroke',
    strokeW: 3,
    cap: 'round',
    bendable: true,
    shaftYs: [6],
  ),
  'line-elbow': ShapeDef(_sq, path: 'M12 12 V70 A18 18 0 0 0 30 88 H88', kind: 'stroke', strokeW: 4, cap: 'round'),

  // ── Polygons ──
  'pentagon': ShapeDef(_sq, path: 'M50 4 L94 37 L77 92 L23 92 L6 37 Z'),
  'hexagon': ShapeDef(_sq, path: 'M50 4 L90 27 L90 73 L50 96 L10 73 L10 27 Z'),
  'heptagon': ShapeDef(
    _sq,
    path: 'M50 4 L85.96 21.32 L94.85 60.24 L69.97 91.44 L30.03 91.44 L5.15 60.24 L14.04 21.32 Z',
  ),
  'octagon': ShapeDef(_sq, path: 'M31 4 H69 L96 31 V69 L69 96 H31 L4 69 V31 Z'),
  'hexagon-flat': ShapeDef(_sq, path: 'M27 8 H73 L96 50 L73 92 H27 L4 50 Z'),

  // ── Stars ──
  'star4': ShapeDef(_sq, path: 'M50 4 L60 40 L96 50 L60 60 L50 96 L40 60 L4 50 L40 40 Z'),
  'star5': ShapeDef(
    _sq,
    path: 'M50 4 L61.8 38.2 L98 38.2 L68.8 59.5 L79.6 94 L50 72.4 L20.4 94 L31.2 59.5 L2 38.2 L38.2 38.2 Z',
  ),
  'star6': ShapeDef(
    _sq,
    path: 'M50 4 L60 32.7 L89.8 27 L70 50 L89.8 73 L60 67.3 L50 96 L40 67.3 L10.2 73 L30 50 L10.2 27 L40 32.7 Z',
  ),
  'star8': ShapeDef(
    _sq,
    path:
        'M50 4 L58.4 29.7 L82.5 17.5 L70.3 41.6 L96 50 L70.3 58.4 L82.5 82.5 L58.4 70.3 L50 96 L41.6 70.3 '
        'L17.5 82.5 L29.7 58.4 L4 50 L29.7 41.6 L17.5 17.5 L41.6 29.7 Z',
  ),
  'sparkle': ShapeDef(_sq, path: 'M50 6 C54 30 70 46 94 50 C70 54 54 70 50 94 C46 70 30 54 6 50 C30 46 46 30 50 6 Z'),

  // ── Arrows ──
  'arrow-right': ShapeDef([100, 70], path: 'M2 22 H58 V4 L98 35 L58 66 V48 H2 Z'),
  'arrow-left': ShapeDef([100, 70], path: 'M98 22 H42 V4 L2 35 L42 66 V48 H98 Z'),
  'arrow-up': ShapeDef([70, 100], path: 'M22 98 V42 H4 L35 2 L66 42 H48 V98 Z'),
  'arrow-down': ShapeDef([70, 100], path: 'M22 2 V58 H4 L35 98 L66 58 H48 V2 Z'),
  'arrow-double-h': ShapeDef([100, 60], path: 'M4 30 L28 8 V20 H72 V8 L96 30 L72 52 V40 H28 V52 Z'),
  'arrow-up-down': ShapeDef([60, 100], path: 'M30 4 L52 28 H40 V72 H52 L30 96 L8 72 H20 V28 H8 Z'),
  'chevron-right': ShapeDef([100, 70], path: 'M4 4 L40 4 L76 35 L40 66 L4 66 L40 35 Z'),
  'arrow-pentagon': ShapeDef([100, 70], path: 'M2 6 H66 L98 35 L66 64 H2 Z'),
  'arrow-ribbon': ShapeDef([100, 60], path: 'M2 6 H74 L98 30 L74 54 H2 L20 30 Z'),
  'arrow-double-chevron': ShapeDef([
    100,
    70,
  ], path: 'M2 6 H34 L58 35 L34 64 H2 L26 35 Z M42 6 H74 L98 35 L74 64 H42 L66 35 Z'),
  'arrow-notched': ShapeDef([100, 60], path: 'M2 6 H70 L98 30 L70 54 H2 Z'),

  // ── Speech bubbles ──
  'bubble': ShapeDef(
    [100, 90],
    path: 'M12 8 H88 A8 8 0 0 1 96 16 V60 A8 8 0 0 1 88 68 H44 L28 86 L31 68 H12 A8 8 0 0 1 4 60 V16 A8 8 0 0 1 12 8 Z',
  ),
  'bubble-round': ShapeDef([
    100,
    90,
  ], path: 'M50 6 C22 6 4 22 4 42 C4 60 20 75 44 77 L40 90 L60 76 C80 72 96 58 96 42 C96 22 78 6 50 6 Z'),
  'bubble-square': ShapeDef([100, 90], path: 'M6 6 H94 V60 H34 L14 84 L18 60 H6 Z'),
  'bubble-tail-right': ShapeDef(
    [100, 90],
    path: 'M12 8 H88 A8 8 0 0 1 96 16 V60 A8 8 0 0 1 88 68 H72 L72 86 L56 68 H12 A8 8 0 0 1 4 60 V16 A8 8 0 0 1 12 8 Z',
  ),

  // ── Clouds ──
  'cloud': ShapeDef([
    100,
    70,
  ], path: 'M26 64 C10 64 4 52 12 44 C6 34 16 22 28 26 C32 12 54 10 60 24 C74 16 90 26 86 40 C98 42 98 62 82 64 Z'),
  'cloud2': ShapeDef([
    100,
    64,
  ], path: 'M24 60 C8 60 2 46 14 40 C8 28 22 18 32 24 C36 8 62 8 66 26 C82 20 96 32 88 46 C98 50 92 62 78 60 Z'),

  // ── Hearts ──
  'heart': ShapeDef(
    [100, 90],
    path:
        'M50 86 C18 62 4 44 4 26 C4 12 16 4 28 8 C38 11 46 20 50 28 C54 20 62 11 72 8 C84 4 96 12 96 26 '
        'C96 44 82 62 50 86 Z',
  ),

  // ── Banners ──
  'bookmark': ShapeDef([70, 100], path: 'M12 6 H58 V94 L35 74 L12 94 Z'),
  'ribbon': ShapeDef([100, 44], path: 'M6 6 H94 L82 22 L94 38 H6 L18 22 Z'),
  'banner-flag': ShapeDef([100, 58], path: 'M8 6 H92 V42 L50 58 L8 42 Z'),

  // ── Teardrops ──
  'teardrop': ShapeDef([80, 100], path: 'M40 4 C40 4 74 44 74 64 A34 34 0 1 1 6 64 C6 44 40 4 40 4 Z'),

  // ── Flowchart ──
  'stadium': ShapeDef([100, 56], path: 'M28 4 H72 A24 24 0 0 1 72 52 H28 A24 24 0 0 1 28 4 Z'),
  'cylinder': ShapeDef(_sq, path: 'M10 16 C10 8 90 8 90 16 V84 C90 92 10 92 10 84 Z'),
  'document': ShapeDef([100, 90], path: 'M8 8 H92 V72 C78 86 64 60 50 72 C36 84 22 60 8 72 Z'),

  // ── Organic ──
  'blob': ShapeDef(
    _sq,
    path: 'M54 8 C74 6 92 24 88 44 C85 60 96 74 78 86 C60 98 34 92 20 74 C8 58 12 32 28 18 C36 12 44 9 54 8 Z',
  ),
  'blob2': ShapeDef(
    _sq,
    path: 'M50 6 C72 6 94 20 92 44 C90 64 80 78 60 88 C42 96 20 90 12 70 C4 50 10 26 28 14 C36 9 42 6 50 6 Z',
  ),
  'blob3': ShapeDef(
    _sq,
    path: 'M60 8 C82 12 96 32 90 52 C86 68 94 84 74 90 C56 96 34 94 20 78 C6 62 8 36 24 22 C36 12 46 6 60 8 Z',
  ),
};

/// Text-template ornaments (`textTemplateShapes.js`) — hidden from the web's
/// panel but drawn like any library shape.
const Map<String, String> _textTemplatePaths = {
  'tt-pill': 'M25,0 L75,0 C88.8,0 100,22.4 100,50 C100,77.6 88.8,100 75,100 L25,100 C11.2,100 0,77.6 0,50 C0,22.4 11.2,0 25,0 Z',
  'tt-arch': 'M0,100 L0,50 C0,22.4 22.4,0 50,0 C77.6,0 100,22.4 100,50 L100,100 Z',
  'tt-sparkle': 'M50,0 C55,35 65,45 100,50 C65,55 55,65 50,100 C45,65 35,55 0,50 C35,45 45,35 50,0 Z',
  'tt-crown': 'M2,22 L24,52 L50,6 L76,52 L98,22 L92,90 C92,95 89,97 84,97 L16,97 C11,97 8,95 8,90 Z',
  'tt-diamond': 'M50,0 L100,50 L50,100 L0,50 Z',
  'tt-key':
      'M31,50 C31,66.57 24.28,80 16,80 C7.72,80 1,66.57 1,50 C1,33.43 7.72,20 16,20 C24.28,20 31,33.43 31,50 Z '
      'M22,50 C22,43.37 19.31,38 16,38 C12.69,38 10,43.37 10,50 C10,56.63 12.69,62 16,62 C19.31,62 22,56.63 22,50 Z '
      'M28,42 L99,42 L99,58 L90,58 L90,82 L80,82 L80,58 L70,58 L70,76 L60,76 L60,58 L28,58 Z',
  'tt-starburst':
      'M50,0 L57.41,12.73 L69.13,3.81 L71.11,18.4 L85.36,14.64 L81.6,28.89 L96.19,30.87 L87.27,42.59 L100,50 '
      'L87.27,57.41 L96.19,69.13 L81.6,71.11 L85.36,85.36 L71.11,81.6 L69.13,96.19 L57.41,87.27 L50,100 '
      'L42.59,87.27 L30.87,96.19 L28.89,81.6 L14.64,85.36 L18.4,71.11 L3.81,69.13 L12.73,57.41 L0,50 '
      'L12.73,42.59 L3.81,30.87 L18.4,28.89 L14.64,14.64 L28.89,18.4 L30.87,3.81 L42.59,12.73 Z',
  'tt-banner-swallowtail': 'M0,0 L100,0 L85,50 L100,100 L0,100 L15,50 Z',
  'tt-square-star-12':
      'M50,0 L64.24,-3.13 L75,6.7 L88.89,11.11 L93.3,25 L103.13,35.76 L100,50 L103.13,64.24 L93.3,75 '
      'L88.89,88.89 L75,93.3 L64.24,103.13 L50,100 L35.76,103.13 L25,93.3 L11.11,88.89 L6.7,75 L-3.13,64.24 '
      'L0,50 L-3.13,35.76 L6.7,25 L11.11,11.11 L25,6.7 L35.76,-3.13 Z',
  'tt-arrow-pentagon': 'M0,0 L75,0 L100,50 L75,100 L0,100 Z',
  'tt-star10':
      'M50,0 L62.36,11.96 L79.39,9.55 L82.36,26.49 L97.55,34.55 L90,50 L97.55,65.45 L82.36,73.51 L79.39,90.45 '
      'L62.36,88.04 L50,100 L37.64,88.04 L20.61,90.45 L17.64,73.51 L2.45,65.45 L10,50 L2.45,34.55 L17.64,26.49 '
      'L20.61,9.55 L37.64,11.96 Z',
  'tt-teardrop-leaf': 'M0,100 C0,45 45,0 100,0 C100,55 55,100 0,100 Z',
  'tt-flowchart-preparation': 'M15,0 L85,0 L100,50 L85,100 L15,100 L0,50 Z',
  'tt-speech-bubble-oval':
      'M50,0 C78,0 100,17 100,38 C100,58 78,75 50,75 L34,75 L18,100 L24,74 C10,67 0,53 0,38 C0,17 22,0 50,0 Z',
  'tt-house': 'M50,4 L98,42 L86,42 L86,96 L14,96 L14,42 L2,42 Z',
  'tt-banner-pennant': 'M0,0 L100,50 L0,100 Z',
  'tt-rocket':
      'M50,2 C66,14 74,32 74,52 L74,70 L92,86 L92,96 L62,86 L62,96 L38,96 L38,86 L8,96 L8,86 L26,70 L26,52 '
      'C26,32 34,14 50,2 Z',
  'tt-speech-bubble-tail-right':
      'M8,0 L92,0 C96,0 100,5 100,11 L100,66 C100,72 96,77 92,77 L78,77 L82,100 L60,77 L8,77 C4,77 0,72 0,66 '
      'L0,11 C0,5 4,0 8,0 Z',
  'tt-semicircle': 'M0,100 C0,44.8 22.4,0 50,0 C77.6,0 100,44.8 100,100 Z',
  'tt-airplane':
      'M50,2 C56,2 58,10 58,20 L58,34 L98,58 L98,66 L58,56 L58,76 L70,86 L70,92 L50,86 L30,92 L30,86 L42,76 '
      'L42,56 L2,66 L2,58 L42,34 L42,20 C42,10 44,2 50,2 Z',
  'tt-sailboat': 'M52,5 L52,62 L92,62 Z M46,16 L46,62 L12,62 Z M4,70 L96,70 L82,95 L18,95 Z',
  'tt-ui-pin':
      'M50,0 C22,0 0,21 0,48 C0,75 30,83 50,100 C70,83 100,75 100,48 C100,21 78,0 50,0 Z '
      'M68,44 C68,36.27 59.94,30 50,30 C40.06,30 32,36.27 32,44 C32,51.73 40.06,58 50,58 C59.94,58 68,51.73 68,44 Z',
  'tt-mountain': 'M0,100 L30,24 L47,56 L66,6 L100,100 Z',
  'tt-flower':
      'M50,40.9 C61.21,24.89 59.9,3.54 50,0 C40.1,3.54 38.79,24.89 50,40.9 Z '
      'M57.88,45.45 C77.35,47.16 95.18,35.35 93.3,25 C85.28,18.2 66.14,27.73 57.88,45.45 Z '
      'M57.88,54.55 C66.14,72.27 85.28,81.8 93.3,75 C95.18,64.65 77.35,52.84 57.88,54.55 Z '
      'M50,59.1 C38.79,75.11 40.1,96.46 50,100 C59.9,96.46 61.21,75.11 50,59.1 Z '
      'M42.12,54.55 C22.65,52.84 4.82,64.65 6.7,75 C14.72,81.8 33.86,72.27 42.12,54.55 Z '
      'M42.12,45.45 C33.86,27.73 14.72,18.2 6.7,25 C4.82,35.35 22.65,47.16 42.12,45.45 Z '
      'M63,50 C63,57.18 57.18,63 50,63 C42.82,63 37,57.18 37,50 C37,42.82 42.82,37 50,37 C57.18,37 63,42.82 63,50 Z',
  'tt-trapezoid': 'M25,0 L75,0 L100,100 L0,100 Z',
  'tt-tree': 'M50,2 L78,34 L66,34 L88,60 L74,60 L96,84 L56,84 L56,98 L44,98 L44,84 L4,84 L26,60 L12,60 L34,34 L22,34 Z',
  'tt-blob-3': 'M50,2 C75,2 100,20 100,45 C100,72 80,100 52,100 C24,100 0,82 0,55 C0,26 22,2 50,2 Z',
  'tt-heart-sharp': 'M50,100 L5,44 C0,26 10,4 28,4 C38,4 45,11 50,20 C55,11 62,4 72,4 C90,4 100,26 95,44 Z',
  'tt-cross': 'M35,0 L65,0 L65,35 L100,35 L100,65 L65,65 L65,100 L35,100 L35,65 L0,65 L0,35 L35,35 Z',
};

// Spiky starbursts and scalloped seals are computed, as on the web.
String _spikePath(int points, double outer, double inner) {
  const start = -math.pi / 2;
  final step = math.pi / points;
  final d = StringBuffer();
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? outer : inner;
    final a = start + i * step;
    d.write('${i == 0 ? 'M' : 'L'}${(50 + r * math.cos(a)).toStringAsFixed(2)} ');
    d.write('${(50 + r * math.sin(a)).toStringAsFixed(2)} ');
  }
  return '${d}Z';
}

String _scallopPath(int bumps, double r) {
  const start = -math.pi / 2;
  final step = math.pi * 2 / bumps;
  String pt(int i) =>
      '${(50 + r * math.cos(start + i * step)).toStringAsFixed(2)} '
      '${(50 + r * math.sin(start + i * step)).toStringAsFixed(2)}';
  final arcR = (r * math.sin(step / 2)).toStringAsFixed(2);
  final d = StringBuffer('M${pt(0)} ');
  for (var i = 1; i <= bumps; i++) {
    d.write('A$arcR $arcR 0 0 1 ${pt(i)} ');
  }
  return '${d}Z';
}

/// The whole library: base shapes, generated badges and text-template ornaments.
final Map<String, ShapeDef> shapes = {
  ..._base,
  'burst6': ShapeDef(_sq, path: _spikePath(6, 48, 28)),
  'burst8': ShapeDef(_sq, path: _spikePath(8, 48, 32)),
  'burst10': ShapeDef(_sq, path: _spikePath(10, 48, 35)),
  'burst12': ShapeDef(_sq, path: _spikePath(12, 48, 38)),
  'burst16': ShapeDef(_sq, path: _spikePath(16, 48, 40)),
  'burst24': ShapeDef(_sq, path: _spikePath(24, 48, 43)),
  'seal10': ShapeDef(_sq, path: _scallopPath(10, 40)),
  'seal12': ShapeDef(_sq, path: _scallopPath(12, 41)),
  'seal16': ShapeDef(_sq, path: _scallopPath(16, 42)),
  for (final e in _textTemplatePaths.entries) e.key: ShapeDef(_sq, path: e.value),
};

/// Keys drawn as primitives (box / ellipse / triangle), not via an SVG path.
const Set<String> primitiveShapes = {'rect', 'circle', 'triangle'};

/// The shaft path for a line at a given bend (viewBox units).
String lineShaftPath(String key, [double bendVB = 0]) {
  final def = shapes[key];
  if (def == null) return '';
  if (!def.bendable || bendVB == 0) return def.path ?? '';
  final ys = def.shaftYs ?? const [6.0];
  return ys.map((y) => 'M0 $y Q50 ${(y - bendVB).toStringAsFixed(2)} 100 $y').join(' ');
}

/// A shape outline's dash array (`strokeDash` name → lengths scaled by width).
/// Empty means solid.
List<double> dashArrayFor(Object? name, Object? width) {
  // `Number(width) || 1`: missing, zero and junk all mean 1.
  final n = width is num ? width.toDouble() : double.tryParse('$width');
  final ww = (n == null || n == 0 || n.isNaN) ? 1.0 : n;
  if (name == 'dashed') return [math.max(2, ww * 3), math.max(2, ww * 2)];
  if (name == 'dotted') return [math.max(1, ww), math.max(2, ww * 1.6)];
  return const [];
}

/// Media border dash (`borderDash.js`). [] means solid.
List<double> borderDashArray(Object? style, double w) {
  final u = math.max(1.0, w);
  if (style == 'long') return [u * 4, u * 2];
  if (style == 'dashed') return [u * 1.8, u * 1.5];
  // A zero-length dash with round caps is a dot the width of the line.
  if (style == 'dotted') return [0, u * 2];
  return const [];
}

/// Frame masks (`frames.js`): a key → (viewBox, path). Unknown keys fall back
/// to the first frame, as on the web.
(List<double>, String) frameGeo(Object? key) {
  const primitives = {
    'frame-square': 'M0 0 H100 V100 H0 Z',
    'frame-rounded':
        'M16 0 H84 A16 16 0 0 1 100 16 V84 A16 16 0 0 1 84 100 H16 A16 16 0 0 1 0 84 V16 A16 16 0 0 1 16 0 Z',
    'frame-circle': 'M50 0 A50 50 0 1 1 50 100 A50 50 0 1 1 50 0 Z',
    'frame-triangle': 'M50 2 L98 98 L2 98 Z',
  };
  const fromShapes = ['heart', 'star5', 'pentagon', 'hexagon', 'diamond', 'teardrop', 'arch', 'blob'];
  if (key is String) {
    if (primitives.containsKey(key)) return (_sq, primitives[key]!);
    if (key.startsWith('frame-') && fromShapes.contains(key.substring(6))) {
      final def = shapes[key.substring(6)]!;
      return (def.viewBox, def.path!);
    }
  }
  return (_sq, primitives['frame-square']!);
}
