import 'dart:convert';

/// One saved design (`GET /creative-designs`), normalised the way the web's
/// `normalizeDesign()` (creatives/DesignDetailsPanel.jsx) does it.
class Design {
  Design._({
    required this.id,
    required this.raw,
    required this.name,
    required this.type,
    required this.category,
    required this.createdAt,
    required this.favorite,
    required this.score,
    required this.copy,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.canvasSpec,
    required this.elements,
    required this.thumbnail,
    required this.image,
  });

  /// `{width, height, background}` — for painting the design when it has no thumbnail.
  final Map<String, dynamic> canvasSpec;

  /// Layout elements (app format — saved designs are already converted from Scraive).
  final List<dynamic> elements;

  int get elementCount => elements.length;

  final int id;
  final Map<String, dynamic> raw;
  String name;

  /// The SUB-type (poster, flyer, card, banner…) — raw `sub_type || type`.
  final String type;

  /// The top-level type (ads, social…) — raw `type`.
  final String category;
  final DateTime? createdAt;
  bool favorite;
  final num score;

  /// Generated copy (headline, tagline, body, cta, …).
  Map<String, dynamic> copy;
  final num canvasWidth;
  final num canvasHeight;

  /// Server-rendered preview (CDN URL), written on every save.
  final String? thumbnail;

  /// `image_url || thumbnail` — for image-only designs.
  final String? image;

  String? get tagline => (copy['tagline'] as String?)?.trim().isEmpty ?? true ? null : copy['tagline'] as String;

  /// Best image to show: thumbnail first, then the image URL.
  String? get previewUrl => _http(thumbnail) ?? _http(image);

  static String? _http(String? s) => s != null && s.startsWith('http') ? s : null;

  static Design? tryParse(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final id = int.tryParse('${json['id']}');
    if (id == null) return null;

    Map<String, dynamic> copy = {};
    final rawCopy = json['copy'];
    if (rawCopy is Map) {
      copy = Map<String, dynamic>.from(rawCopy);
    } else if (rawCopy is String && rawCopy.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCopy);
        copy = decoded is Map ? Map<String, dynamic>.from(decoded) : {'body': rawCopy};
      } catch (_) {
        copy = {'body': rawCopy};
      }
    }

    dynamic canvas = json['canvas'];
    if (canvas is String) {
      try {
        canvas = jsonDecode(canvas);
      } catch (_) {
        canvas = null;
      }
    }
    num w = 800, h = 450;
    var spec = <String, dynamic>{'width': 800, 'height': 450, 'background': '#ffffff'};
    var elements = const <dynamic>[];
    if (canvas is Map) {
      final s = canvas['canvas'] is Map ? canvas['canvas'] as Map : canvas;
      w = num.tryParse('${s['width']}') ?? w;
      h = num.tryParse('${s['height']}') ?? h;
      spec = {...Map<String, dynamic>.from(s), 'width': w, 'height': h};
      if (canvas['elements'] is List) elements = canvas['elements'] as List;
    }

    String? str(dynamic v) => v == null || '$v'.isEmpty ? null : '$v';
    final thumbnail = str(json['thumbnail']);

    return Design._(
      id: id,
      raw: json,
      name: str(json['name']) ?? 'Untitled Design',
      type: str(json['sub_type']) ?? str(json['type']) ?? 'image',
      category: str(json['type']) ?? 'ads',
      createdAt: DateTime.tryParse('${json['created_at']}'),
      favorite: '${json['fav'] ?? json['favorite']}' == '1' || json['fav'] == true,
      score: num.tryParse('${json['score'] ?? 0}') ?? 0,
      copy: copy,
      canvasWidth: w,
      canvasHeight: h,
      canvasSpec: spec,
      elements: elements,
      thumbnail: thumbnail,
      image: str(json['image_url']) ?? thumbnail,
    );
  }
}
