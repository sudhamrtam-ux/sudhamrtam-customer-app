import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// The website: only when `window.google.maps` exists.
bool get googleMapsLoaded {
  final google = globalContext['google'];
  if (google == null || !google.isA<JSObject>()) return false;
  return (google as JSObject)['maps'] != null;
}
