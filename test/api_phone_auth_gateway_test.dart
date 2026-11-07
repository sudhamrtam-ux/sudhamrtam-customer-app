import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudhamrtam_customer_app/services/api_phone_auth_gateway.dart';
import 'package:sudhamrtam_customer_app/services/phone_auth_service.dart';

class MemorySessionStore implements SessionStore {
  StoredSession? saved;
  bool failWrites = false;

  @override
  Future<StoredSession?> read() async => saved;

  @override
  Future<void> write(StoredSession session) async {
    if (failWrites) throw Exception('keystore unavailable');
    saved = session;
  }

  @override
  Future<void> clear() async => saved = null;
}

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late MemorySessionStore store;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) handler;

  ApiPhoneAuthGateway gateway() => ApiPhoneAuthGateway(
    baseUrl: 'http://api.test',
    store: store,
    httpClient: MockClient((request) {
      requests.add(request);
      return handler(request);
    }),
  );

  setUp(() {
    store = MemorySessionStore();
    requests = [];
    handler = (_) async => jsonResponse({}, 500);
  });

  const customer = {
    'id': 'c-1',
    'phone_e164': '+919999900001',
    'full_name': null,
    'email': null,
  };

  test('requests a code and signs in with it', () async {
    handler = (request) async => switch (request.url.path) {
      '/v1/auth/otp/request' => jsonResponse({
        'challenge_id': 'ch-1',
        'expires_in_seconds': 300,
        'resend_after_seconds': 30,
      }),
      '/v1/auth/otp/verify' => jsonResponse({
        'token': 'tok-1',
        'customer': customer,
      }),
      _ => jsonResponse({}, 404),
    };

    final auth = gateway();
    final changes = <AuthUser?>[];
    auth.authStateChanges().listen(changes.add);

    final sent = await auth.requestCode('+919999900001');
    expect(sent, isA<PhoneCodeSent>());
    expect((sent as PhoneCodeSent).verificationId, 'ch-1');
    expect(jsonDecode(requests[0].body), {'phone': '+919999900001'});

    final user = await auth.confirmCode('ch-1', '123456');
    expect(jsonDecode(requests[1].body), {
      'challenge_id': 'ch-1',
      'code': '123456',
    });
    expect(user.phoneNumber, '+919999900001');
    expect(auth.currentUser?.uid, 'c-1');
    expect(auth.sessionToken, 'tok-1');
    expect(store.saved?.token, 'tok-1');

    await Future<void>.delayed(Duration.zero);
    expect(changes.single?.uid, 'c-1');
  });

  test('shows the server message on an error', () async {
    handler = (_) async => jsonResponse({
      'error': 'INVALID_CODE',
      'message': 'The code is incorrect.',
      'attempts_left': 4,
    }, 400);

    await expectLater(
      gateway().confirmCode('ch-1', '000000'),
      throwsA(
        isA<PhoneAuthException>().having(
          (e) => e.message,
          'message',
          'The code is incorrect.',
        ),
      ),
    );
    expect(store.saved, isNull);
  });

  test('reports a missing connection plainly', () async {
    handler = (_) async => throw const SocketException('offline');

    await expectLater(
      gateway().requestCode('+919999900001'),
      throwsA(
        isA<PhoneAuthException>().having(
          (e) => e.message,
          'message',
          contains('No internet'),
        ),
      ),
    );
  });

  test('is not signed in if the login cannot be saved', () async {
    store.failWrites = true;
    handler = (_) async => jsonResponse({'token': 't', 'customer': customer});

    final auth = gateway();
    await expectLater(
      auth.confirmCode('ch-1', '123456'),
      throwsA(isA<PhoneAuthException>()),
    );
    expect(auth.currentUser, isNull);
  });

  test('restores a saved login without the network', () async {
    store.saved = const StoredSession(
      token: 'tok-1',
      customerId: 'c-1',
      phoneE164: '+919999900001',
    );

    final auth = gateway();
    await auth.restore();

    expect(auth.currentUser?.phoneNumber, '+919999900001');
    expect(requests, isEmpty);
  });

  test('a session the server rejects is signed out', () async {
    store.saved = const StoredSession(
      token: 'old',
      customerId: 'c-1',
      phoneE164: '+919999900001',
    );
    handler = (_) async => jsonResponse({'error': 'UNAUTHORIZED'}, 401);

    final auth = gateway();
    await auth.restore();
    await auth.checkSession();

    expect(requests.single.headers['authorization'], 'Bearer old');
    expect(auth.currentUser, isNull);
    expect(store.saved, isNull);
  });

  test('an offline session check keeps the login', () async {
    store.saved = const StoredSession(
      token: 'tok-1',
      customerId: 'c-1',
      phoneE164: '+919999900001',
    );
    handler = (_) async => throw const SocketException('offline');

    final auth = gateway();
    await auth.restore();
    await auth.checkSession();

    expect(auth.currentUser, isNotNull);
    expect(store.saved, isNotNull);
  });

  test('sign out clears the phone even if the server is unreachable', () async {
    store.saved = const StoredSession(
      token: 'tok-1',
      customerId: 'c-1',
      phoneE164: '+919999900001',
    );
    handler = (_) async => throw const SocketException('offline');

    final auth = gateway();
    await auth.restore();
    await auth.signOut();

    expect(requests.single.url.path, '/v1/auth/logout');
    expect(auth.currentUser, isNull);
    expect(store.saved, isNull);
  });
}
