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

  /// ORDER_HAS_QUERY: the order's conversation, to write in instead.
  final String? queryId;

  const SupportException(
    this.message, {
    this.code,
    this.unauthorized = false,
    this.queryId,
  });

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

  /// e.g. "Q-1001": quoted when talking to Sudhamrtam about it. Null
  /// only from a server older than query numbers.
  final String? ref;
  final String topic;
  final String message;
  final DateTime createdAt;

  /// Set once Sudhamrtam has handled it.
  final DateTime? handledAt;

  /// Sudhamrtam's latest reply, if any.
  final String? reply;

  /// The order it is about (one conversation per order).
  final String? orderId;

  /// e.g. "SUD0000020".
  final String? orderRef;

  /// The latest message.
  final DateTime lastMessageAt;

  /// Sudhamrtam wrote last.
  final bool lastFromSudhamrtam;

  /// A reply the customer has not opened yet.
  final bool unread;

  SupportQuery({
    required this.id,
    this.ref,
    required this.topic,
    required this.message,
    required this.createdAt,
    this.handledAt,
    this.reply,
    this.orderId,
    this.orderRef,
    DateTime? lastMessageAt,
    this.lastFromSudhamrtam = false,
    this.unread = false,
  }) : lastMessageAt = lastMessageAt ?? createdAt;

  /// Resolved by Sudhamrtam; writing again reopens it.
  bool get isResolved => handledAt != null;

  factory SupportQuery.fromJson(Map<String, dynamic> json) => SupportQuery(
    id: json['id'] as String,
    ref: json['ref'] as String?,
    topic: json['topic'] as String,
    message: json['message'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    handledAt: json['handled_at'] == null
        ? null
        : DateTime.parse(json['handled_at'] as String),
    reply: json['reply'] as String?,
    orderId: json['order_id'] as String?,
    orderRef: json['order_ref'] as String?,
    lastMessageAt: json['last_message_at'] == null
        ? null
        : DateTime.parse(json['last_message_at'] as String),
    lastFromSudhamrtam: json['last_from'] == 'staff',
    unread: json['unread'] as bool? ?? false,
  );
}

/// One message in a conversation.
class SupportMessage {
  final String id;

  /// Written by Sudhamrtam (else by the customer).
  final bool fromSudhamrtam;
  final String body;
  final DateTime createdAt;

  const SupportMessage({
    required this.id,
    required this.fromSudhamrtam,
    required this.body,
    required this.createdAt,
  });

  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
    id: json['id'] as String,
    fromSudhamrtam: json['from'] == 'staff',
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

/// The order a conversation is about, as the server has it.
class SupportOrder {
  final String id;
  final String orderRef;

  /// pending, delivered, not_delivered, cancelled...
  final String status;
  final String paymentStatus;
  final String deliveryDate;
  final int totalPaise;

  /// "2 × Curd (1 kg)".
  final List<String> items;

  const SupportOrder({
    required this.id,
    required this.orderRef,
    required this.status,
    required this.paymentStatus,
    required this.deliveryDate,
    required this.totalPaise,
    required this.items,
  });

  factory SupportOrder.fromJson(Map<String, dynamic> json) => SupportOrder(
    id: json['id'] as String,
    orderRef: json['order_ref'] as String,
    status: json['status'] as String,
    paymentStatus: json['payment_status'] as String,
    deliveryDate: json['delivery_date'] as String,
    totalPaise: (json['total_paise'] as num).toInt(),
    items: [
      for (final i in (json['items'] as List).cast<Map<String, dynamic>>())
        '${i['quantity']} × ${i['product_name']} (${i['unit_label']})',
    ],
  );
}

/// A query with all its messages and its order.
class SupportConversation {
  final SupportQuery query;
  final List<SupportMessage> messages;
  final SupportOrder? order;

  const SupportConversation({
    required this.query,
    required this.messages,
    this.order,
  });

  factory SupportConversation.fromJson(Map<String, dynamic> json) =>
      SupportConversation(
        query: SupportQuery.fromJson(json['query'] as Map<String, dynamic>),
        messages: [
          for (final m in json['messages'] as List)
            SupportMessage.fromJson(m as Map<String, dynamic>),
        ],
        order: json['order'] == null
            ? null
            : SupportOrder.fromJson(json['order'] as Map<String, dynamic>),
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

  /// Sends it; retrying with the same [id] saves it once. With
  /// [orderId] it is that order's conversation; when the order has one
  /// already, a [SupportException] with code ORDER_HAS_QUERY gives its
  /// [SupportException.queryId].
  Future<SupportQuery> send(
    String id, {
    required String topic,
    required String message,
    String? orderId,
  }) async {
    final json = await _send('PUT', 'v1/support-queries/$id', {
      'topic': topic,
      'message': message,
      'order_id': ?orderId,
    });
    return SupportQuery.fromJson(json['query'] as Map<String, dynamic>);
  }

  /// One conversation; opening it marks Sudhamrtam's replies read.
  Future<SupportConversation> fetchConversation(String id) async =>
      SupportConversation.fromJson(
        await _send('GET', 'v1/support-queries/$id'),
      );

  /// Writes in a conversation (reopens a resolved one); retrying with
  /// the same [messageId] saves it once.
  Future<SupportConversation> sendMessage(
    String id,
    String messageId,
    String body,
  ) async => SupportConversation.fromJson(
    await _send('PUT', 'v1/support-queries/$id/messages/$messageId', {
      'body': body,
    }),
  );

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
      queryId: json?['query_id'] as String?,
    );
  }
}
