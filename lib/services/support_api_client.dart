import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Sending or loading queries failed. [code] is the server's stable
/// code when it refused (TOO_MANY, INVALID_MESSAGE...), null for
/// connection problems.
class SupportException implements Exception {
  final String message;
  final String? code;

  /// The customer must sign in (again).
  final bool unauthorized;

  const SupportException(this.message, {this.code, this.unauthorized = false});

  @override
  String toString() => message;
}

/// What a query can be about, in the order shown.
const supportTopics = <String, String>{
  'order': 'An order',
  'milk_plan': 'Milk plan',
  'bill': 'Milk bill',
  'delivery': 'Delivery',
  'payment': 'Payment',
  'account': 'My account',
  'other': 'Something else',
};

/// A query the customer raised, as the server keeps it.
class SupportQuery {
  final String id;
  final String topic;
  final String message;
  final DateTime createdAt;

  /// Set once Sudhamrtam has handled it.
  final DateTime? handledAt;

  /// Sudhamrtam's reply, if any.
  final String? reply;

  const SupportQuery({
    required this.id,
    required this.topic,
    required this.message,
    required this.createdAt,
    this.handledAt,
    this.reply,
  });

  factory SupportQuery.fromJson(Map<String, dynamic> json) => SupportQuery(
    id: json['id'] as String,
    topic: json['topic'] as String,
    message: json['message'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    handledAt: json['handled_at'] == null
        ? null
        : DateTime.parse(json['handled_at'] as String),
    reply: json['reply'] as String?,
  );
}

/// A new ID per query, reused when sending is retried, so it is
/// never saved twice.
String newSupportQueryId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Help & Support queries on the server (`/v1/support-queries`).
/// Signed-in customers only, so Sudhamrtam knows who to answer.
class SupportApiClient {
  SupportApiClient({
    required String baseUrl,
    required this.token,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _http = httpClient ?? http.Client();

  final Uri _baseUri;

  /// The session token, or null when signed out.
  final String? Function() token;
  final http.Client _http;
  final Duration timeout;

  bool get isSignedIn => token() != null;

  /// Sends it; retrying with the same [id] saves it once.
  Future<SupportQuery> send(
    String id, {
    required String topic,
    required String message,
  }) async {
    final json = await _send('PUT', 'v1/support-queries/$id', {
      'topic': topic,
      'message': message,
    });
    return SupportQuery.fromJson(json['query'] as Map<String, dynamic>);
  }

  /// The customer's queries, newest first.
  Future<List<SupportQuery>> fetchMine() async {
    final json = await _send('GET', 'v1/support-queries');
    return [
      for (final q in json['queries'] as List)
        SupportQuery.fromJson(q as Map<String, dynamic>),
    ];
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final session = token();
    if (session == null) {
      throw const SupportException(
        'Please sign in to send a query.',
        unauthorized: true,
      );
    }

    final request = http.Request(method, _baseUri.resolve(path))
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
      throw const SupportException(
        'Could not reach Sudhamrtam. Check your connection and try again, '
        'or call us.',
      );
    }

    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {
      // Not JSON.
    }

    final status = response.statusCode;
    if (status == 200 && json != null) return json;
    if (status == 401) {
      throw const SupportException(
        'Please sign in again to send a query.',
        unauthorized: true,
      );
    }
    throw SupportException(
      json?['message'] as String? ??
          'Something went wrong. Please try again, or call us.',
      code: json?['error'] as String?,
    );
  }
}
