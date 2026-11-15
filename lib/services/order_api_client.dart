import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/combo_offer.dart';
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

  /// A combo offer ended, changed price or is over its limit.
  bool get isComboChange => code == 'COMBO_CHANGED' || code == 'COMBO_LIMIT';

  @override
  String toString() => message;
}

/// A payment request the server refused, with its stable code:
/// ALREADY_PAID, PAYMENT_WINDOW_CLOSED, ORDER_CANCELLED,
/// NOT_ONLINE_PAYMENT, PAYMENT_IN_PROGRESS or PAYMENT_NOT_OFFERED.
class PaymentRejectedException implements Exception {
  final String code;
  final String message;

  const PaymentRejectedException(this.code, this.message);

  bool get isAlreadyPaid => code == 'ALREADY_PAID';

  @override
  String toString() => message;
}

/// What the app needs to open Cashfree's payment screen.
class PaymentSession {
  final String orderId;
  final String paymentSessionId;

  /// "sandbox" (test payments) or "production".
  final String environment;

  const PaymentSession({
    required this.orderId,
    required this.paymentSessionId,
    required this.environment,
  });

  bool get isSandbox => environment != 'production';
}

/// An order's payment, as the server knows it.
class OrderPaymentStatus {
  /// "online" or "cash_on_delivery".
  final String paymentMethod;

  /// due_on_delivery, awaiting_online, paid_online or not_paid.
  final String paymentStatus;

  /// The order status, e.g. "pending" or "cancelled".
  final String orderStatus;

  /// Online orders are cancelled if not paid by this time.
  final DateTime? paymentDueAt;

  /// The short order number, e.g. "SUD0000001" (null from older servers).
  final String? orderRef;

  const OrderPaymentStatus({
    required this.paymentMethod,
    required this.paymentStatus,
    required this.orderStatus,
    this.paymentDueAt,
    this.orderRef,
  });

  bool get isPaid => paymentStatus == 'paid_online';
  bool get isAwaitingPayment => paymentStatus == 'awaiting_online';
  bool get isCashOnDelivery => paymentStatus == 'due_on_delivery';
  bool get isCancelledUnpaid => paymentStatus == 'not_paid';

  factory OrderPaymentStatus.fromOrderJson(Map<String, dynamic> order) {
    final due = order['payment_due_at'] as String?;
    return OrderPaymentStatus(
      paymentMethod: order['payment_method'] as String,
      paymentStatus: order['payment_status'] as String? ?? 'due_on_delivery',
      orderStatus: order['status'] as String,
      orderRef: order['order_ref'] as String?,
      paymentDueAt: due == null ? null : DateTime.parse(due),
    );
  }
}

/// The owner's order rules, as published by the server.
class OrderRules {
  final int minimumOrderPaise;
  final int deliveryFeePaise;
  final int cutoffHourIst;

  /// The customer may choose a delivery date up to this many days
  /// after today (0: only the earliest).
  final int maxDaysAhead;

  /// e.g. ["cash_on_delivery", "online"].
  final List<String> paymentMethods;

  const OrderRules({
    required this.minimumOrderPaise,
    required this.deliveryFeePaise,
    required this.cutoffHourIst,
    this.paymentMethods = const ['cash_on_delivery'],
    this.maxDaysAhead = 0,
  });

  double get minimumOrderRupees => minimumOrderPaise / 100;

  bool get offersOnlinePayment => paymentMethods.contains('online');

  /// The delivery date for an order placed at [now] (India time):
  /// tomorrow before the cut-off, otherwise the day after.
  DateTime deliveryDateFor(DateTime now) {
    final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    final days = ist.hour < cutoffHourIst ? 1 : 2;
    return DateTime(ist.year, ist.month, ist.day + days);
  }

  /// The dates a customer may choose at [now]: the earliest, then
  /// each day up to [maxDaysAhead] days after today (India time).
  List<DateTime> deliveryDatesFor(DateTime now) {
    final earliest = deliveryDateFor(now);
    final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    final last = DateTime(ist.year, ist.month, ist.day + maxDaysAhead);
    // The earliest date is always offered.
    final latest = last.isBefore(earliest) ? earliest : last;
    return [
      for (
        var d = earliest;
        !d.isAfter(latest);
        d = DateTime(d.year, d.month, d.day + 1)
      )
        d,
    ];
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
    // Left out when not chosen, so earlier orders send the same body.
    if (order.deliveryDate != null) 'delivery_date': order.deliveryDate,
    'items': [
      for (final item in order.items)
        if (!isComboProductId(item.productId))
          {
            'product_id': item.productId,
            'quantity': item.quantity,
            'unit_price_paise': toPaise(item.unitPrice),
          },
    ],
    // Combo offers: the server checks each one and its price again.
    // Left out without combos, so earlier orders send the same body.
    if (order.items.any((i) => isComboProductId(i.productId)))
      'combos': [
        for (final item in order.items)
          if (isComboProductId(item.productId))
            {
              'combo_id': comboIdOf(item.productId),
              'quantity': item.quantity,
              'price_paise': toPaise(item.unitPrice),
            },
      ],
  };

  /// Places [order] (or confirms it was already placed); returns the
  /// server's short order number ("SUD0000001"), if it gave one.
  ///
  /// Throws [OrderRejectedException] if the server refuses it, and
  /// [OrderApiException] if it could not be confirmed.
  Future<String?> placeOrder(CustomerOrder order) async {
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

    if (response.statusCode == 200 || response.statusCode == 201) {
      try {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        final placed = json is Map ? json['order'] : null;
        final ref = placed is Map ? placed['order_ref'] : null;
        return ref is String ? ref : null;
      } catch (_) {
        return null; // Placed; the number shows later.
      }
    }
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
        maxDaysAhead: json['max_days_ahead'] as int? ?? 0,
        paymentMethods: [
          for (final method in (json['payment_methods'] as List? ?? const []))
            method as String,
        ],
      );
    } catch (_) {
      throw const OrderApiException('Could not load the order rules.');
    }
  }

  /// Starts (or resumes) paying for an online order.
  Future<PaymentSession> startPayment(String orderId) async {
    final response = await _send('POST', 'v1/orders/$orderId/payment');
    final json = _paymentJson(response);
    return PaymentSession(
      orderId: json['order_id'] as String,
      paymentSessionId: json['payment_session_id'] as String,
      environment: json['environment'] as String,
    );
  }

  /// Asks the server to check the payment with Cashfree.
  Future<OrderPaymentStatus> checkPayment(String orderId) async {
    final response = await _send('POST', 'v1/orders/$orderId/payment/check');
    return OrderPaymentStatus.fromOrderJson(
      _paymentJson(response)['order'] as Map<String, dynamic>,
    );
  }

  /// Changes an unpaid online order to Cash on Delivery.
  Future<OrderPaymentStatus> switchToCashOnDelivery(String orderId) async {
    final response = await _send(
      'POST',
      'v1/orders/$orderId/payment/cash-on-delivery',
    );
    return OrderPaymentStatus.fromOrderJson(
      _paymentJson(response)['order'] as Map<String, dynamic>,
    );
  }

  /// The order's payment as the server has it, without asking
  /// Cashfree.
  Future<OrderPaymentStatus> fetchPaymentStatus(String orderId) async {
    final response = await _send('GET', 'v1/orders/$orderId');
    return OrderPaymentStatus.fromOrderJson(
      _paymentJson(response)['order'] as Map<String, dynamic>,
    );
  }

  /// The payment status of the customer's recent orders on the
  /// server (one request), by order ID.
  Future<Map<String, OrderPaymentStatus>> fetchPaymentStatuses() async {
    final response = await _send('GET', 'v1/orders');
    final orders = _paymentJson(response)['orders'] as List? ?? const [];
    return {
      for (final order in orders.cast<Map<String, dynamic>>())
        order['id'] as String: OrderPaymentStatus.fromOrderJson(order),
    };
  }

  static Map<String, dynamic> _paymentJson(http.Response response) {
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
      throw const OrderApiException('Please sign in again to pay.');
    }

    final code = json?['error'] as String?;
    final message = json?['message'] as String?;
    if (code != null && status >= 400 && status < 500 || status == 503) {
      throw PaymentRejectedException(
        code ?? 'PAYMENT_NOT_OFFERED',
        message ?? 'Online payment is not available right now.',
      );
    }

    throw OrderApiException(
      message ??
          'The payment service did not respond (error $status). '
              'Please try again.',
    );
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
      return const OrderApiException(
        'Please sign in again to place your order.',
      );
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
