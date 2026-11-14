import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_notifications.dart';

/// Firebase Cloud Messaging on the phone. The Firebase project comes
/// from android/app/google-services.json (Gradle plugin).
class FirebasePushPlatform implements PushPlatform {
  FirebasePushPlatform._();

  /// Starts Firebase; throws when it cannot (then: no notifications).
  static Future<FirebasePushPlatform> start() async {
    await Firebase.initializeApp();
    return FirebasePushPlatform._();
  }

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  static PushTap _tap(RemoteMessage m) => PushTap.fromData(m.data);

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  // The classic FCM registration token, which the server's HTTP v1
  // send takes as `token`. firebase_messaging 17 prefers register()
  // and installation IDs; switch once the server sends to those.
  @override
  // ignore: deprecated_member_use
  Future<String?> getToken() => _messaging.getToken();

  @override
  // ignore: deprecated_member_use
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<PushTap> get onTap => FirebaseMessaging.onMessageOpenedApp.map(_tap);

  @override
  Future<PushTap?> initialTap() async {
    final m = await _messaging.getInitialMessage();
    return m == null ? null : _tap(m);
  }

  @override
  Stream<PushArrival> get onArrival => FirebaseMessaging.onMessage.map(
    (m) => PushArrival(
      title: m.notification?.title,
      body: m.notification?.body,
      tap: _tap(m),
    ),
  );
}
