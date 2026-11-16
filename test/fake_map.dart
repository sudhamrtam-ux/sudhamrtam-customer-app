import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/account/map_location_field.dart';

/// Where the fake GPS says the phone is.
const fakeHere = MapPoint(17.512345, 78.389123);

/// Where tapping the fake map puts the pin.
const fakeTapped = MapPoint(17.5, 78.4);

/// The fake GPS: always [fakeHere].
Future<MapPoint> fakeFindLocation() async => fakeHere;

/// A stand-in for the Google map (it cannot draw in tests): shows the
/// pin as text; tapping it moves the pin to [fakeTapped].
Widget fakeMap(
  BuildContext context,
  MapPoint? pin,
  ValueChanged<MapPoint> onMoved,
) => GestureDetector(
  key: const Key('fakeMap'),
  onTap: () => onMoved(fakeTapped),
  child: ColoredBox(
    color: Colors.green,
    child: Center(
      child: Text(
        pin == null ? 'no pin' : 'pin ${pin.latitude},${pin.longitude}',
      ),
    ),
  ),
);

/// Marks the spot with "Use my current location".
Future<void> useCurrentLocation(WidgetTester tester) async {
  final button = find.byKey(const Key('useCurrentLocation'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}
