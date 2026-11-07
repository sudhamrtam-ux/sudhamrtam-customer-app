import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/customer_order.dart';

/// The order could not be sent or confirmed (no connection, a
/// server problem, or the customer must sign in again). Retrying
/// the same order later is safe.
class OrderApiException implements Exception {
  final String message;
  const OrderApiException(this.message);

  @override
  String toString() => message;
}

/// The server refused this order (for example a price changed or
/// the total is below the minimum). Sending the same order again
/// will not help: the customer must cancel it and check out again.
class OrderRejectedException implements Exception {
  /// Stable code from the server, e.g. `PRICE_CHANGED`.
  final String code;
  final String message;

  const OrderRejectedException(this.code, this.message);

  bool get isPriceChange => code == 'PRICE_CHANGED';

  @override
  String toString() => message;
}

/// The owner's order rules, as published by the server.
class OrderRules {
  final int minimumOrderPaise;
  final int deliveryFeePaise;
  final int cutoffHourIst;

  const OrderRules({
    required this.minimumOrderPaise,
    required this.deliveryFeePaise,
    required this.cutoffHourIst,
  });

  double get minimumOrderRupees => minimumOrderPaise / 100;

  /// The delivery date for an order placed at [now] (India time):
  /// tomorrow before the cut-off, otherwise the day after.
  DateTime deliveryDateFor(DateTime now) {
    final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    final days = ist.hour < cutoffHourIst ? 1 : 2;
    return DateTime(ist.year, ist.month, ist.day + days);
  }
}

/// Sends orders to the Sudhamrtam server.
///
/// `PUT /v1/orders/{id}` is idempotent: sending the same order
/// (same ID, same content) again returns the order already
/// placed, so a retry can never create a second order.
class OrderApiClient {
  OrderApiClient({
    required String baseUrl,
    required this._token,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final String? Function() _token;
  final http.Client _http;
  final Duration timeout;

  /// Rupees (as shown in the app) to whole paise.
  static int toPaise(double rupees) => (rupees * 100).round();

  /// The request body for [order]. Built only from the order
  /// snapshot, so a retry sends exactly the same request.
  static Map<String, Object?> requestBody(CustomerOrder order) => {
    'client_created_at': order.createdAt.toUtc().toIso8601String(),
    'fulfillment': switch (order.fulfillmentMethod) {
      FulfillmentMethod.delivery => 'delivery',
      FulfillmentMethod.pickup => 'pickup',
    },
    'payment_method': switch (order.paymentMethod) {
      OrderPaymentMethod.cashOnDelivery => 'cash_on_delivery',
      OrderPaymentMethod.online => 'online',
    },
    'address_id': order.addressId,
    'recipient_name': order.recipientName,
    'recipient_phone': order.recipientPhone,
    'notes': order.notes,
    'items': [
      for (final item in order.items)
        {
          'product_id': item.productId,
          'quantity': item.quantity,
          'unit_price_paise': toPaise(item.unitPrice),
        },
    ],
  };

  /// Places [order] (or confirms it was already placed).
  ///
  /// Throws [OrderRejectedException] if the server refuses it, and
  /// [OrderApiException] if it could not be confirmed.
  Future<void> placeOrder(CustomerOrder order) async {
    if (order.addressId == null) {
      throw const OrderRejectedException(
        'ADDRESS_NOT_FOUND',
        'Please choose one of your saved delivery addresses.',
      );
    }

    final response = await _send(
      'PUT',
      'v1/orders/${order.id}',
      body: requestBody(order),
    );

    if (response.statusCode == 200 || response.statusCode == 201) return;
    throw _failure(response);
  }

  /// Whether the server has this order. Throws
  /// [OrderApiException] when that cannot be checked.
  Future<bool> orderExists(String orderId) async {
    final response = await _send('GET', 'v1/orders/$orderId');

    if (response.statusCode == 200) return true;
    if (response.statusCode == 404) return false;

    final failure = _failure(response);
    throw failure is OrderApiException
        ? failure
        : OrderApiException('Could not check the order: $failure');
  }

  /// The owner's order rules (public, no sign-in needed).
  Future<OrderRules> fetchRules() async {
    final http.Response response;
    try {
      response = await _http
          .get(_baseUri.resolve('v1/order-rules'))
          .timeout(timeout);
    } catch (_) {
      throw const OrderApiException('Could not load the order rules.');
    }

    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      return OrderRules(
        minimumOrderPaise: json['minimum_order_paise'] as int,
        deliveryFeePaise: json['delivery_fee_paise'] as int,
        cutoffHourIst: json['cutoff_hour_ist'] as int,
      );
    } catch (_) {
      throw const OrderApiException('Could not load the order rules.');
    }
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final token = _token();
    if (token == null) {
      throw const OrderApiException('Please sign in to place your order.');
    }

    final request = http.Request(method, _baseUri.resolve(path))
      ..headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    try {
      return await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw const OrderApiException(
        'Sudhamrtam did not respond. Your order is kept; please try again.',
      );
    } catch (_) {
      throw const OrderApiException(
        'No internet connection. Your order is kept; please try again.',
      );
    }
  }

  static Exception _failure(http.Response response) {
    String? code;
    String? message;
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is Map) {
        code = json['error'] as String?;
        message = json['message'] as String?;
      }
    } catch (_) {
      // Not JSON.
    }

    final status = response.statusCode;

    if (status == 401) {
      return const OrderApiException('Please sign in again to place your order.');
    }

    // 400/409/422: the server refused this exact order.
    if (status == 400 || status == 409 || status == 422) {
      return OrderRejectedException(
        code ?? 'INVALID_ORDER',
        message ?? 'Sudhamrtam could not accept this order.',
      );
    }

    return OrderApiException(
      'Sudhamrtam could not take the order right now (error $status). '
      'Your order is kept; please try again.',
    );
  }
}
