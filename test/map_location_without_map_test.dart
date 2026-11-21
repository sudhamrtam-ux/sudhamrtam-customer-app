import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/account/map_location_field.dart';

import 'fake_map.dart';

/// The website without a Google Maps key: no map is drawn, the
/// customer marks their home with their current location only.
void main() {
  Future<GlobalKey<FormState>> open(
    WidgetTester tester, {
    MapPoint? initial,
    CurrentLocationFinder findLocation = fakeFindLocation,
    List<MapPoint>? changes,
  }) async {
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: form,
            child: MapLocationField(
              initialValue: initial,
              findLocation: findLocation,
              mapBuilder: null,
              onChanged: (pin) => changes?.add(pin),
            ),
          ),
        ),
      ),
    );
    return form;
  }

  testWidgets('offers only the current location, never a map', (tester) async {
    final changes = <MapPoint>[];
    final form = await open(tester, changes: changes);

    expect(find.byKey(const Key('chooseOnMap')), findsNothing);
    expect(find.byKey(const Key('mapPinView')), findsNothing);
    expect(find.textContaining('use your current location'), findsOneWidget);

    // Still required.
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.textContaining('Please mark your home'), findsOneWidget);

    await tester.tap(find.byKey(const Key('useCurrentLocation')));
    await tester.pumpAndSettle();

    expect(changes, [fakeHere]);
    expect(find.byKey(const Key('mapPinView')), findsNothing);
    expect(find.byKey(const Key('mapPinSaved')), findsOneWidget);
    expect(find.textContaining('Location marked (17.5123'), findsOneWidget);
    expect(form.currentState!.validate(), isTrue);
  });

  testWidgets('shows a saved address location as text', (tester) async {
    await open(tester, initial: fakeTapped);
    expect(find.byKey(const Key('mapPinSaved')), findsOneWidget);
    expect(find.textContaining('Your home is marked'), findsOneWidget);
    expect(find.byKey(const Key('mapPinView')), findsNothing);
  });

  testWidgets('a location problem keeps the map closed', (tester) async {
    await open(
      tester,
      findLocation: () async => throw const LocationProblem('blocked'),
    );
    await tester.tap(find.byKey(const Key('useCurrentLocation')));
    await tester.pumpAndSettle();
    expect(find.text('blocked'), findsOneWidget);
    expect(find.byKey(const Key('mapPinView')), findsNothing);
  });

  testWidgets('with a map, the map is used as before', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapLocationField(
            findLocation: fakeFindLocation,
            mapBuilder: fakeMap,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('chooseOnMap')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chooseOnMap')));
    await tester.pump();
    expect(find.byKey(const Key('fakeMap')), findsOneWidget);
    expect(find.byKey(const Key('mapPinSaved')), findsNothing);
  });
}
