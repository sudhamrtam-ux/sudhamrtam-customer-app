import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

import 'package:sudhamrtam_customer_app/features/account/profile_photo.dart';
import 'package:sudhamrtam_customer_app/services/profile_photo_api_client.dart';

/// A real 1×1 PNG, so the avatar can draw it.
final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class FakePhotoServer {
  Uint8List? stored;
  bool down = false;
  final requests = <String>[];

  late final client = MockClient((request) async {
    requests.add(request.method);
    if (down) throw http.ClientException('down');
    if (request.headers['authorization'] != 'Bearer tok') {
      return http.Response('{"error":"UNAUTHORIZED"}', 401);
    }
    switch (request.method) {
      case 'GET':
        return stored == null
            ? http.Response('{"error":"NO_PHOTO"}', 404)
            : http.Response.bytes(
                stored!,
                200,
                headers: {'content-type': 'image/png'},
              );
      case 'PUT':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        stored = base64Decode(body['image_base64'] as String);
        return http.Response('{"photo":{}}', 200);
      case 'DELETE':
        stored = null;
        return http.Response('{"photo":null}', 200);
    }
    return http.Response('{}', 404);
  });
}

void main() {
  late FakePhotoServer server;
  late ProfilePhoto photo;
  String? token;

  setUp(() {
    server = FakePhotoServer();
    token = 'tok';
    photo = ProfilePhoto(
      api: ProfilePhotoApiClient(
        baseUrl: 'https://api.test',
        token: () => token,
        httpClient: server.client,
      ),
    );
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: ProfilePhotoAvatar(photo: photo)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('choose a photo: saved to the account, then shown', (
    tester,
  ) async {
    ImageSource? asked;
    pickProfilePhoto = (source) async {
      asked = source;
      return tinyPng;
    };
    await photo.refresh();
    expect(photo.bytes, isNull);
    await show(tester);
    expect(find.byIcon(Icons.person), findsOneWidget);

    await tester.tap(find.byKey(const Key('profilePhoto')));
    await tester.pumpAndSettle();
    expect(find.text('Remove photo'), findsNothing);
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    expect(asked, ImageSource.gallery);
    expect(server.stored, tinyPng);
    expect(photo.bytes, tinyPng);
    expect(find.text('Photo saved.'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsNothing);

    // Remove it.
    await tester.tap(find.byKey(const Key('profilePhoto')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    expect(server.stored, isNull);
    expect(photo.bytes, isNull);
    expect(find.text('Photo removed.'), findsOneWidget);
  });

  testWidgets('a photo saved before is loaded; offline keeps nothing new', (
    tester,
  ) async {
    server.stored = tinyPng;
    await photo.refresh();
    expect(photo.bytes, tinyPng);

    pickProfilePhoto = (source) async => tinyPng;
    server.down = true;
    await show(tester);
    await tester.tap(find.byKey(const Key('profilePhoto')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not reach Sudhamrtam'), findsOneWidget);
    // Still the photo from before.
    expect(photo.bytes, tinyPng);
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    pickProfilePhoto = (source) async => null;
    await show(tester);
    await tester.tap(find.byKey(const Key('profilePhoto')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    expect(server.requests, isNot(contains('PUT')));
  });

  testWidgets('signed out: no photo and nothing to tap', (tester) async {
    token = null;
    await photo.refresh();
    await show(tester);
    expect(photo.bytes, isNull);
    expect(find.byKey(const Key('profilePhoto')), findsNothing);
    expect(server.requests, isEmpty);
  });
}
