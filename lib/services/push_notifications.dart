import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Phone notifications (owner decision 2026-11-14): a message the
/// owner sends pops up on the phone. After sign-in the app asks for
/// permission and gives the server this phone's Firebase token;
/// before sign-out it takes it back.

/// What a notification carries (the server's `data`).
class PushTap {
  final String type;
  final String? id;

  const PushTap({required this.type, this.id});

  factory PushTap.fromData(Map<String, dynamic> data) =>
      PushTap(type: data['type'] as String? ?? '', id: data['id'] as String?);
}

/// A notification that arrived while the app was open.
class PushArrival {
  final String? title;
  final String? body;
  final PushTap tap;

  const PushArrival({this.title, this.body, required this.tap});
}

/// The phone's notification system (Firebase on Android); a fake in
/// tests.
abstract class PushPlatform {
  /// Asks to show notifications (Android 13+ shows a dialog once).
  Future<bool> requestPermission();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;

  /// A notification was tapped while the app was in the background.
  Stream<PushTap> get onTap;

  /// The notification that opened the app from closed, if any.
  Future<PushTap?> initialTap();

  /// Arrived while the app was in front (Android shows nothing then).
  Stream<PushArrival> get onArrival;
}

/// `/v1/push-token`: register and remove this phone.
class PushApiClient {
  PushApiClient({
    required String baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  }) : _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final http.Client _http;
  final Duration timeout;

  Map<String, String> _headers(String session) => {
    'authorization': 'Bearer $session',
    'content-type': 'application/json',
  };

  Future<bool> register(String session, String pushToken) async {
    final response = await _http
        .put(
          _baseUri.resolve('v1/push-token'),
          headers: _headers(session),
          body: jsonEncode({'token': pushToken, 'platform': 'android'}),
        )
        .timeout(timeout);
    return response.statusCode == 204;
  }

  Future<void> remove(String session, String pushToken) async {
    await _http
        .post(
          _baseUri.resolve('v1/push-token/remove'),
          headers: _headers(session),
          body: jsonEncode({'token': pushToken}),
        )
        .timeout(timeout);
  }
}

/// Keeps the server told which phone to notify, and passes taps and
/// arrivals to the app.
class PushNotifications {
  PushNotifications({
    required this.platform,
    required this.api,
    required this.session,
  });

  final PushPlatform platform;
  final PushApiClient api;

  /// The signed-in session token; null when signed out.
  final String? Function() session;

  final _taps = StreamController<PushTap>.broadcast();
  final _arrivals = StreamController<PushArrival>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// The token the server has for this phone, if registered.
  String? registeredToken;

  /// Notifications tapped (open the right page).
  Stream<PushTap> get taps => _taps.stream;

  /// Notifications that arrived while the app was open.
  Stream<PushArrival> get arrivals => _arrivals.stream;

  /// Starts: registers on every sign-in ([authChanges] fires with
  /// non-null on sign-in) and when Firebase changes the token.
  void attach(Stream<Object?> authChanges) {
    if (_subscriptions.isNotEmpty) return;
    _subscriptions
      ..add(
        authChanges.listen((user) {
          if (user != null) unawaited(register());
        }),
      )
      ..add(platform.onTokenRefresh.listen((t) => unawaited(register(t))))
      ..add(platform.onTap.listen(_taps.add))
      ..add(platform.onArrival.listen(_arrivals.add));
    unawaited(register());
  }

  /// The notification that opened the app, once the app can show it.
  Future<PushTap?> initialTap() => platform.initialTap();

  /// Asks for permission and gives the server this phone's token.
  /// Never throws: notifications are a bonus.
  Future<void> register([String? newToken]) async {
    final session = this.session();
    if (session == null) return;
    try {
      await platform.requestPermission();
      final token = newToken ?? await platform.getToken();
      if (token == null) return;
      if (await api.register(session, token)) registeredToken = token;
    } catch (error) {
      debugPrint('Phone notifications not set up: $error');
    }
  }

  /// Before signing out (while the session still works): this phone
  /// gets no more of this customer's notifications.
  Future<void> unregister(String session) async {
    final token = registeredToken;
    if (token == null) return;
    registeredToken = null;
    try {
      await api.remove(session, token);
    } catch (error) {
      debugPrint('Notification token not removed: $error');
    }
  }

  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _taps.close();
    _arrivals.close();
  }
}
