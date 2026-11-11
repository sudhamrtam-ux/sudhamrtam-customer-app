import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A profile photo request failed.
class ProfilePhotoException implements Exception {
  const ProfilePhotoException(this.message, {this.unauthorized = false});

  final String message;

  /// The customer must sign in (again).
  final bool unauthorized;

  @override
  String toString() => message;
}

/// The customer's profile photo on the server (`/v1/me/photo`).
class ProfilePhotoApiClient {
  ProfilePhotoApiClient({
    required String baseUrl,
    required this.token,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  }) : _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _http = httpClient ?? http.Client();

  final Uri _baseUri;

  /// The session token, or null when signed out.
  final String? Function() token;
  final http.Client _http;
  final Duration timeout;

  bool get isSignedIn => token() != null;

  /// The photo, or null if there is none.
  Future<Uint8List?> fetch() async {
    final response = await _send('GET');
    if (response.statusCode == 404) return null;
    return response.bodyBytes;
  }

  /// Saves [bytes] (a JPEG or PNG) as the photo.
  Future<void> upload(Uint8List bytes) async {
    await _send('PUT', body: {'image_base64': base64Encode(bytes)});
  }

  Future<void> remove() async {
    await _send('DELETE');
  }

  Future<http.Response> _send(String method, {Object? body}) async {
    final session = token();
    if (session == null) {
      throw const ProfilePhotoException(
        'Please sign in to add a photo.',
        unauthorized: true,
      );
    }
    final request = http.Request(method, _baseUri.resolve('v1/me/photo'))
      ..headers['authorization'] = 'Bearer $session';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      );
    } on Exception {
      throw const ProfilePhotoException(
        'Could not reach Sudhamrtam. Check your connection and try again.',
      );
    }

    final status = response.statusCode;
    if (status == 200 || (status == 404 && method == 'GET')) return response;
    if (status == 401) {
      throw const ProfilePhotoException(
        'Please sign in again.',
        unauthorized: true,
      );
    }
    String? message;
    try {
      message =
          (jsonDecode(utf8.decode(response.bodyBytes))
                  as Map<String, dynamic>)['message']
              as String?;
    } catch (_) {
      // Not JSON.
    }
    throw ProfilePhotoException(
      message ?? 'Sudhamrtam could not save the photo (error $status).',
    );
  }
}
