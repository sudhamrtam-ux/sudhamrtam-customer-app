import 'package:flutter/foundation.dart';

/// Phones have Google Maps. The Windows desktop app (2026-11-25) has
/// no map: addresses use the current location, as on the website
/// without a Maps key.
bool get googleMapsLoaded =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;
