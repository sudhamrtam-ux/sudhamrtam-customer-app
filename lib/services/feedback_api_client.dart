import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Sending feedback failed. [code] is the server's stable code when
/// it refused (TOO_MANY, INVALID_MESSAGE...), null for connection
/// problems.
class FeedbackException implements Exception {
  final String message;
  final String? code;

  /// The customer must sign in (again).
  final bool unauthorized;

  const FeedbackException(this.message, {this.code, this.unauthorized = false});

  @override
  String toString() => message;
}

/// The topics a customer can choose, in the order shown.
const feedbackTopics = <String, String>{
  'milk': 'Milk',
  'products': 'Products',
  'delivery': 'Delivery',
  'app': 'App',
  'other': 'Other',
};

/// Feedback the customer sent, as the server keeps it.
class SentFeedback {
  final String id;
  final int rating;
  final String topic;
  final String message;
  final DateTime createdAt;

  /// Set once Sudhamrtam has handled it.
  final DateTime? handledAt;

  /// Sudhamrtam's reply, if any.
  final String? handledNote;

  const SentFeedback({
    required this.id,
    required this.rating,
    required this.topic,
    required this.message,
    required this.createdAt,
    required this.handledAt,
    required this.handledNote,
  });

  factory SentFeedback.fromJson(Map<String, dynamic> json) => SentFeedback(
    id: json['id'] as String,
    rating: json['rating'] as int,
    topic: json['topic'] as String,
    message: json['message'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    handledAt: json['handled_at'] == null
        ? null
        : DateTime.parse(json['handled_at'] as String),
    handledNote: json['handled_note'] as String?,
  );
}

/// A new ID per piece of feedback, reused when sending is retried,
/// so it is never saved twice.
String newFeedbackId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Customer feedback on the server (`/v1/feedback`). Signed-in
/// customers only, so Sudhamrtam knows who to reply to.
class FeedbackApiClient {
  FeedbackApiClient({
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
  Future<SentFeedback> send(
    String id, {
    required int rating,
    required String topic,
    required String message,
  }) async {
    final json = await _send('PUT', 'v1/feedback/$id', {
      'rating': rating,
      'topic': topic,
      'message': message,
    });
    return SentFeedback.fromJson(json['feedback'] as Map<String, dynamic>);
  }

  /// The customer's feedback, newest first.
  Future<List<SentFeedback>> fetchMine() async {
    final json = await _send('GET', 'v1/feedback');
    return [
      for (final f in json['feedback'] as List)
        SentFeedback.fromJson(f as Map<String, dynamic>),
    ];
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final session = token();
    if (session == null) {
      throw const FeedbackException(
        'Please sign in to send feedback.',
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
      throw const FeedbackException(
        'Could not reach Sudhamrtam. Check your connection and try again.',
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
      throw const FeedbackException(
        'Please sign in again to send feedback.',
        unauthorized: true,
      );
    }
    final code = json?['error'] as String?;
    if (code != null) {
      throw FeedbackException(
        json?['message'] as String? ?? 'Sudhamrtam could not take this.',
        code: code,
      );
    }
    throw FeedbackException(
      'Sudhamrtam could not take this right now ($status). Please try again.',
    );
  }
}
