import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudhamrtam_customer_app/services/push_notifications.dart';

class FakePlatform implements PushPlatform {
  bool asked = false;
  String? token = 'phone-token-1';
  final refresh = StreamController<String>();
  final taps = StreamController<PushTap>();
  final arrivals = StreamController<PushArrival>();
  PushTap? opening;

  @override
  Future<bool> requestPermission() async => asked = true;
  @override
  Future<String?> getToken() async => token;
  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Stream<PushTap> get onTap => taps.stream;
  @override
  Future<PushTap?> initialTap() async => opening;
  @override
  Stream<PushArrival> get onArrival => arrivals.stream;
}

void main() {
  late FakePlatform platform;
  late List<String> calls;
  late String? session;
  late StreamController<Object?> auth;
  late PushNotifications push;
  var status = 204;

  setUp(() {
    platform = FakePlatform();
    calls = [];
    session = null;
    status = 204;
    auth = StreamController<Object?>();
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      calls.add(
        '${request.method} ${request.url.path} ${body['token']} '
        '${request.headers['authorization']}',
      );
      return http.Response('', status);
    });
    push = PushNotifications(
      platform: platform,
      api: PushApiClient(baseUrl: 'https://api.test', httpClient: client),
      session: () => session,
    );
  });

  tearDown(() => push.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('registers after sign-in and when the token changes', () async {
    push.attach(auth.stream);
    await settle();
    // Signed out: nothing asked, nothing sent.
    expect(platform.asked, isFalse);
    expect(calls, isEmpty);

    session = 'sess-1';
    auth.add('user');
    await settle();
    expect(platform.asked, isTrue);
    expect(calls, ['PUT /v1/push-token phone-token-1 Bearer sess-1']);
    expect(push.registeredToken, 'phone-token-1');

    platform.refresh.add('phone-token-2');
    await settle();
    expect(calls.last, 'PUT /v1/push-token phone-token-2 Bearer sess-1');

    // Sign-out: the server forgets this phone (session still valid).
    await push.unregister('sess-1');
    expect(
      calls.last,
      'POST /v1/push-token/remove phone-token-2 Bearer sess-1',
    );
    expect(push.registeredToken, isNull);
    // Nothing registered: nothing to remove.
    await push.unregister('sess-1');
    expect(calls, hasLength(3));
  });

  test('a refused or failed registration never throws', () async {
    session = 'sess-1';
    status = 401;
    await push.register();
    expect(push.registeredToken, isNull);
    platform.token = null;
    await push.register();
    expect(calls, hasLength(1));
  });

  test('taps and arrivals reach the app', () async {
    push.attach(auth.stream);
    final taps = <String>[];
    final arrivals = <String>[];
    push.taps.listen((t) => taps.add('${t.type} ${t.id}'));
    push.arrivals.listen((a) => arrivals.add('${a.title} ${a.tap.type}'));
    platform.taps.add(PushTap.fromData({'type': 'message', 'id': 'm1'}));
    platform.arrivals.add(
      const PushArrival(
        title: 'Paneer is back',
        tap: PushTap(type: 'message', id: 'm2'),
      ),
    );
    await settle();
    expect(taps, ['message m1']);
    expect(arrivals, ['Paneer is back message']);
    platform.opening = const PushTap(type: 'message', id: 'm3');
    expect((await push.initialTap())!.id, 'm3');
  });
}
