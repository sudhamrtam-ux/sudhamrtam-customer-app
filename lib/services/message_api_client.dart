import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Loading messages failed. [unauthorized]: the customer must sign
/// in (again); otherwise a connection or server problem.
class MessageException implements Exception {
  final String message;
  final bool unauthorized;

  const MessageException(this.message, {this.unauthorized = false});

  @override
  String toString() => message;
}

/// A message Sudhamrtam sent to every customer.
class CustomerMessage {
  final String id;
  final String title;
  final String body;
  final DateTime sentAt;

  /// The server's time text, sent back unchanged to mark it read.
  final String sentAtText;
  final bool unread;

  const CustomerMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.sentAt,
    required this.sentAtText,
    required this.unread,
  });

  factory CustomerMessage.fromJson(Map<String, dynamic> json) =>
      CustomerMessage(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        sentAt: DateTime.parse(json['sent_at'] as String),
        sentAtText: json['sent_at'] as String,
        unread: json['unread'] as bool,
      );

  CustomerMessage asRead() => CustomerMessage(
    id: id,
    title: title,
    body: body,
    sentAt: sentAt,
    sentAtText: sentAtText,
    unread: false,
  );
}

/// Messages from Sudhamrtam (`/v1/messages`), for signed-in customers.
class MessageApiClient {
  MessageApiClient({
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

  /// Newest first, with how many are unread.
  Future<({int unreadCount, List<CustomerMessage> messages})>
  fetchMessages() async {
    final json = await _send('GET', 'v1/messages');
    return (
      unreadCount: json['unread_count'] as int,
      messages: [
        for (final m in json['messages'] as List)
          CustomerMessage.fromJson(m as Map<String, dynamic>),
      ],
    );
  }

  /// Marks everything sent up to [upTo] (the newest shown) as read.
  Future<int> markRead(String upTo) async {
    final json = await _send('POST', 'v1/messages/read', {'up_to': upTo});
    return json['unread_count'] as int;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final session = token();
    if (session == null) {
      throw const MessageException(
        'Please sign in to see messages from Sudhamrtam.',
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
      throw const MessageException(
        'Could not reach Sudhamrtam. Check your connection and try again.',
      );
    }
    if (response.statusCode == 401) {
      throw const MessageException(
        'Please sign in again to see messages from Sudhamrtam.',
        unauthorized: true,
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Not JSON.
    }
    throw MessageException(
      'Sudhamrtam could not load messages right now '
      '(${response.statusCode}). Please try again.',
    );
  }
}
