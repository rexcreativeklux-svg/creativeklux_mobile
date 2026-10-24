/// The Frames library — port of the list half of the web's
/// `(lib)/design/frames.js` (FRAMES). The geometry itself (`frameGeo`) already
/// lives in shapes.dart, where the renderer reads it; this is the ordered
/// (key, label) list the panel offers.
library;

const frameLibrary = [
  ('frame-square', 'Square'),
  ('frame-rounded', 'Rounded'),
  ('frame-circle', 'Circle'),
  ('frame-triangle', 'Triangle'),
  ('frame-heart', 'Heart'),
  ('frame-star5', 'Star'),
  ('frame-pentagon', 'Pentagon'),
  ('frame-hexagon', 'Hexagon'),
  ('frame-diamond', 'Diamond'),
  ('frame-teardrop', 'Teardrop'),
  ('frame-arch', 'Arch'),
  ('frame-blob', 'Blob'),
];

/// `isFrame`: true when an element key names a frame.
bool isFrameKey(Object? key) => key is String && key.startsWith('frame-');
