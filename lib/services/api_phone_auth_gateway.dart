import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'phone_auth_service.dart';

/// A saved login: the backend's session token and who it is for.
class StoredSession {
  final String token;
  final String customerId;
  final String phoneE164;

  const StoredSession({
    required this.token,
    required this.customerId,
    required this.phoneE164,
  });
}

/// Where the login token is kept between app starts.
abstract class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

/// Keeps the session in Android's encrypted storage (Keystore).
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'session_token';
  static const _customerKey = 'session_customer_id';
  static const _phoneKey = 'session_phone';

  @override
  Future<StoredSession?> read() async {
    final token = await _storage.read(key: _tokenKey);
    final customerId = await _storage.read(key: _customerKey);
    final phone = await _storage.read(key: _phoneKey);

    if (token == null || customerId == null || phone == null) return null;

    return StoredSession(
      token: token,
      customerId: customerId,
      phoneE164: phone,
    );
  }

  @override
  Future<void> write(StoredSession session) async {
    await _storage.write(key: _tokenKey, value: session.token);
    await _storage.write(key: _customerKey, value: session.customerId);
    await _storage.write(key: _phoneKey, value: session.phoneE164);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _customerKey);
    await _storage.delete(key: _phoneKey);
  }
}

/// Phone login through the Sudhamrtam backend.
///
/// The backend generates the code, delivers it (WhatsApp/SMS via
/// MSG91; printed in the server log in development) and returns a
/// session token once the code is correct.
class ApiPhoneAuthGateway implements PhoneAuthGateway {
  ApiPhoneAuthGateway({
    required String baseUrl,
    required this._store,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final SessionStore _store;
  final http.Client _http;
  final Duration timeout;

  final _changes = StreamController<AuthUser?>.broadcast();
  StoredSession? _session;

  /// The saved token, for signed-in API calls (null if signed out).
  String? get sessionToken => _session?.token;

  /// Loads the saved login. Works offline: the session is trusted
  /// until the server says it is no longer valid ([checkSession]).
  Future<void> restore() async {
    _session = await _store.read();
  }

  /// Asks the server whether the saved session is still valid and
  /// signs out locally if it is not. Network problems are ignored.
  Future<void> checkSession() async {
    final session = _session;
    if (session == null) return;

    try {
      final response = await _http
          .get(
            _baseUri.resolve('v1/me'),
            headers: {'authorization': 'Bearer ${session.token}'},
          )
          .timeout(timeout);

      if (response.statusCode == 401 && identical(_session, session)) {
        await _clearLocal();
      }
    } catch (error) {
      debugPrint('Session check skipped: $error');
    }
  }

  static AuthUser? _toUser(StoredSession? session) => session == null
      ? null
      : AuthUser(uid: session.customerId, phoneNumber: session.phoneE164);

  @override
  AuthUser? get currentUser => _toUser(_session);

  @override
  Stream<AuthUser?> authStateChanges() => _changes.stream;

  @override
  Future<PhoneCodeRequest> requestCode(
    String phoneE164, {
    int? resendToken,
  }) async {
    final json = await _post('v1/auth/otp/request', {'phone': phoneE164});
    final challengeId = json['challenge_id'];

    if (challengeId is! String) {
      throw const PhoneAuthException('Unexpected reply from the server.');
    }

    return PhoneCodeSent(challengeId, null);
  }

  @override
  Future<AuthUser> confirmCode(String verificationId, String smsCode) async {
    final json = await _post('v1/auth/otp/verify', {
      'challenge_id': verificationId,
      'code': smsCode,
    });

    final token = json['token'];
    final customer = json['customer'];

    if (token is! String ||
        customer is! Map ||
        customer['id'] is! String ||
        customer['phone_e164'] is! String) {
      throw const PhoneAuthException('Unexpected reply from the server.');
    }

    final session = StoredSession(
      token: token,
      customerId: customer['id'] as String,
      phoneE164: customer['phone_e164'] as String,
    );

    try {
      await _store.write(session);
    } catch (_) {
      throw const PhoneAuthException(
        'Could not save your login on this phone.',
      );
    }

    _session = session;
    final user = _toUser(session)!;
    _changes.add(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    final session = _session;
    await _clearLocal();

    if (session == null) return;

    // Best effort: the phone is signed out even if this fails.
    try {
      await _http
          .post(
            _baseUri.resolve('v1/auth/logout'),
            headers: {'authorization': 'Bearer ${session.token}'},
          )
          .timeout(timeout);
    } catch (error) {
      debugPrint('Server logout skipped: $error');
    }
  }

  Future<void> _clearLocal() async {
    _session = null;
    await _store.clear();
    _changes.add(null);
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final http.Response response;

    try {
      response = await _http
          .post(
            _baseUri.resolve(path),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const PhoneAuthException(
        'The server did not respond. Please try again.',
      );
    } catch (_) {
      throw const PhoneAuthException(
        'No internet connection. Please check and try again.',
      );
    }

    Map<String, Object?>? json;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) json = Map<String, Object?>.from(decoded);
    } on FormatException {
      json = null;
    }

    if (response.statusCode == 200 && json != null) return json;

    // The server's messages are written for customers.
    final message = json?['message'];
    throw PhoneAuthException(
      message is String && message.isNotEmpty
          ? message
          : 'Login failed (server error ${response.statusCode}).',
    );
  }
}
