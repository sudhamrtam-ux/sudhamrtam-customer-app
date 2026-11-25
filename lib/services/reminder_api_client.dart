import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The evening reminder switch (owner decision 2026-11-25): at 8 PM a
/// phone notification about tomorrow's deliveries
/// (`GET|PUT /v1/me/reminders`).
class ReminderApiClient {
  ReminderApiClient({
    required String baseUrl,
    required this.token,
    http.Client? httpClient,
  }) : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _http = httpClient ?? http.Client();

  final Uri _base;
  final String? Function() token;
  final http.Client _http;

  /// Whether the evening reminder is on; null when it cannot be read
  /// (signed out or no connection).
  Future<bool?> evening() async {
    final response = await _send('GET', null);
    return response == null ? null : response['evening'] as bool?;
  }

  /// Switches it; returns the server's value, null when not saved.
  Future<bool?> setEvening(bool on) async {
    final response = await _send('PUT', {'evening': on});
    return response == null ? null : response['evening'] as bool?;
  }

  Future<Map<String, dynamic>?> _send(
    String method,
    Map<String, Object?>? body,
  ) async {
    final t = token();
    if (t == null) return null;
    final request = http.Request(method, _base.resolve('v1/me/reminders'))
      ..headers['authorization'] = 'Bearer $t';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(seconds: 20)),
      );
      if (response.statusCode != 200) return null;
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
