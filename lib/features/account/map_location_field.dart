import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A spot on the map: where the delivery partner should go.
@immutable
class MapPoint {
  const MapPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is MapPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// Why the phone's location could not be read, and how to fix it.
class LocationProblem implements Exception {
  const LocationProblem(this.message, {this.fix, this.fixLabel});

  final String message;
  final Future<void> Function()? fix;
  final String? fixLabel;

  @override
  String toString() => message;
}

/// Reads where the phone is now; throws [LocationProblem].
typedef CurrentLocationFinder = Future<MapPoint> Function();

/// Draws the map: [pin] is null until the customer marks a spot;
/// [onMoved] is called when they tap the map or drag the pin.
typedef MapPinBuilder = Widget Function(
  BuildContext context,
  MapPoint? pin,
  ValueChanged<MapPoint> onMoved,
);

/// Where the map starts before a spot is marked (Hyderabad).
const MapPoint mapStartPoint = MapPoint(17.4933, 78.3915);

/// The phone's GPS, asking for permission first. On the website: the
/// browser's location, which asks the customer itself.
Future<MapPoint> findCurrentLocation() async {
  if (kIsWeb) return _findBrowserLocation();
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationProblem(
      'Location is off on this phone. Turn it on, then try again, '
      'or tap the map at your home.',
      fix: _openLocationSettings,
      fixLabel: 'Turn on',
    );
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    throw const LocationProblem(
      'Sudhamrtam may not use your location. Allow it in Settings, '
      'or tap the map at your home.',
      fix: _openAppSettings,
      fixLabel: 'Settings',
    );
  }
  if (permission == LocationPermission.denied) {
    throw const LocationProblem(
      'Without your location, please tap the map at your home.',
    );
  }
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return MapPoint(position.latitude, position.longitude);
  } catch (_) {
    throw const LocationProblem(
      'Could not find your location. Please try again outside or near '
      'a window, or tap the map at your home.',
    );
  }
}

/// The website: the browser asks for permission; there is no settings
/// page to open, so the messages say where to allow it.
Future<MapPoint> _findBrowserLocation() async {
  const blocked = LocationProblem(
    'Your browser did not share your location. Allow location for this '
    'site (the icon next to the web address), then try again.',
  );
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw blocked;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return MapPoint(position.latitude, position.longitude);
  } on LocationProblem {
    rethrow;
  } catch (_) {
    throw const LocationProblem(
      'Could not find your location. Please try again from home, with '
      "your phone's or computer's location turned on.",
    );
  }
}

Future<void> _openLocationSettings() async {
  await Geolocator.openLocationSettings();
}

Future<void> _openAppSettings() async {
  await Geolocator.openAppSettings();
}

/// The Google map with one draggable pin.
Widget googleMapPin(
  BuildContext context,
  MapPoint? pin,
  ValueChanged<MapPoint> onMoved,
) => _GoogleMapPin(pin: pin, onMoved: onMoved);

class _GoogleMapPin extends StatefulWidget {
  const _GoogleMapPin({required this.pin, required this.onMoved});

  final MapPoint? pin;
  final ValueChanged<MapPoint> onMoved;

  @override
  State<_GoogleMapPin> createState() => _GoogleMapPinState();
}

class _GoogleMapPinState extends State<_GoogleMapPin> {
  GoogleMapController? _controller;
  double _zoomNow = 18;

  static LatLng _latLng(MapPoint p) => LatLng(p.latitude, p.longitude);

  @override
  void didUpdateWidget(_GoogleMapPin old) {
    super.didUpdateWidget(old);
    // The pin jumped (e.g. "Use my current location"): follow it.
    final pin = widget.pin;
    if (pin != null && old.pin != pin) {
      _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(
          _latLng(pin),
          old.pin == null ? 18 : _zoomNow,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pin = widget.pin;
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _latLng(pin ?? mapStartPoint),
        zoom: pin == null ? 12 : 18,
      ),
      onMapCreated: (controller) => _controller = controller,
      onCameraMove: (camera) => _zoomNow = camera.zoom,
      onTap: (spot) => widget.onMoved(MapPoint(spot.latitude, spot.longitude)),
      markers: {
        if (pin != null)
          Marker(
            markerId: const MarkerId('home'),
            position: _latLng(pin),
            draggable: true,
            onDragEnd: (spot) =>
                widget.onMoved(MapPoint(spot.latitude, spot.longitude)),
          ),
      },
      mapToolbarEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true,
      // The map pans inside the scrolling form.
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
    );
  }
}

/// Address form: the spot on the map (owner decision 2026-11-16: every
/// address needs one, so the delivery partner can navigate to it).
/// [mapBuilder] null: no map can be drawn (the website without a Maps
/// key); the customer then uses their current location only.
class MapLocationField extends FormField<MapPoint> {
  MapLocationField({
    super.key,
    super.initialValue,
    required ValueChanged<MapPoint> onChanged,
    required CurrentLocationFinder findLocation,
    required MapPinBuilder? mapBuilder,
    super.enabled,
  }) : super(
         validator: (pin) => pin == null
             ? 'Please mark your home on the map, so our delivery '
                   'partner can reach you.'
             : null,
         builder: (field) => _MapLocationBody(
           field: field,
           onChanged: onChanged,
           findLocation: findLocation,
           mapBuilder: mapBuilder,
         ),
       );
}

class _MapLocationBody extends StatefulWidget {
  const _MapLocationBody({
    required this.field,
    required this.onChanged,
    required this.findLocation,
    required this.mapBuilder,
  });

  final FormFieldState<MapPoint> field;
  final ValueChanged<MapPoint> onChanged;
  final CurrentLocationFinder findLocation;
  final MapPinBuilder? mapBuilder;

  @override
  State<_MapLocationBody> createState() => _MapLocationBodyState();
}

class _MapLocationBodyState extends State<_MapLocationBody> {
  bool _finding = false;
  bool _showMap = false;

  void _move(MapPoint pin) {
    widget.field.didChange(pin);
    widget.onChanged(pin);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _finding = true);
    try {
      final here = await widget.findLocation();
      if (!mounted) return;
      _move(here);
      setState(() => _showMap = true);
    } on LocationProblem catch (problem) {
      if (!mounted) return;
      setState(() => _showMap = true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(problem.message),
            behavior: SnackBarBehavior.floating,
            action: problem.fix == null
                ? null
                : SnackBarAction(
                    label: problem.fixLabel ?? 'Fix',
                    onPressed: problem.fix!,
                  ),
          ),
        );
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final field = widget.field;
    final pin = field.value;
    final enabled = field.widget.enabled;
    final mapBuilder = widget.mapBuilder;
    final showMap = mapBuilder != null && (pin != null || _showMap);

    return InputDecorator(
      key: const Key('mapLocationField'),
      decoration: InputDecoration(
        labelText: 'Location on Map',
        errorText: field.errorText,
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            mapBuilder == null
                ? (pin == null
                      ? 'So our delivery partner can reach you, please '
                            'use your current location while you are at '
                            'home.'
                      : 'Your home is marked. At home now? Update it '
                            'with your current location.')
                : pin == null
                ? 'Mark your home on the map so our delivery partner '
                      'can reach you. At home now? Use your current '
                      'location.'
                : 'Drag the pin, or tap the map, to put it at your gate.',
            style: theme.textTheme.bodyMedium,
          ),
          if (mapBuilder == null && pin != null) ...[
            const SizedBox(height: 8),
            Row(
              key: const Key('mapPinSaved'),
              children: [
                Icon(Icons.location_on, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Location marked '
                    '(${pin.latitude.toStringAsFixed(5)}, '
                    '${pin.longitude.toStringAsFixed(5)})',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (showMap) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                key: const Key('mapPinView'),
                height: 260,
                child: mapBuilder(context, pin, enabled ? _move : (_) {}),
              ),
            ),
            if (pin == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Tap the map at your home.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const Key('useCurrentLocation'),
                onPressed: !enabled || _finding ? null : _useCurrentLocation,
                icon: _finding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(
                  _finding ? 'Finding you…' : 'Use my current location',
                ),
              ),
              if (!showMap && mapBuilder != null)
                OutlinedButton.icon(
                  key: const Key('chooseOnMap'),
                  onPressed: enabled
                      ? () => setState(() => _showMap = true)
                      : null,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Choose on map'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
