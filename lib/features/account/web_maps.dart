/// Whether the Google map can be drawn. Always on phones; on the
/// website only when the page loaded the Maps JavaScript API (the
/// build adds it when `web/maps-key.txt` exists, see
/// `tool/build_web.py`).
library;

export 'web_maps_stub.dart' if (dart.library.js_interop) 'web_maps_web.dart';
