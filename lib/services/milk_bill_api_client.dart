import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'order_api_client.dart' show PaymentSession;

/// A milk bill request failed. [code] is the server's stable code
/// when it refused (ALREADY_PAID, BILL_CANCELLED, PAYMENT_IN_PROGRESS,
/// PAYMENT_NOT_OFFERED...), null for connection problems.
class MilkBillException implements Exception {
  final String message;
  final String? code;

  /// The customer must sign in (again).
  final bool unauthorized;

  const MilkBillException(this.message, {this.code, this.unauthorized = false});

  bool get isAlreadyPaid => code == 'ALREADY_PAID';

  @override
  String toString() => message;
}

/// One milk per bill: its litres and amount for the month.
class MilkBillMilk {
  final String productName;
  final int quantityMl;
  final int amountPaise;

  const MilkBillMilk({
    required this.productName,
    required this.quantityMl,
    required this.amountPaise,
  });

  factory MilkBillMilk.fromJson(Map<String, dynamic> json) => MilkBillMilk(
    productName: json['product_name'] as String,
    quantityMl: json['quantity_ml'] as int,
    amountPaise: json['amount_paise'] as int,
  );
}

/// One delivery on a bill.
class MilkBillLine {
  final String deliveryDate;
  final String shift;
  final String productName;
  final int quantityMl;
  final int unitPricePaise;
  final int amountPaise;

  const MilkBillLine({
    required this.deliveryDate,
    required this.shift,
    required this.productName,
    required this.quantityMl,
    required this.unitPricePaise,
    required this.amountPaise,
  });

  factory MilkBillLine.fromJson(Map<String, dynamic> json) => MilkBillLine(
    deliveryDate: json['delivery_date'] as String,
    shift: json['shift'] as String,
    productName: json['product_name'] as String,
    quantityMl: json['quantity_ml'] as int,
    unitPricePaise: json['unit_price_paise'] as int,
    amountPaise: json['amount_paise'] as int,
  );
}

/// A monthly bill for the milk delivered. Only the server decides
/// whether it is paid.
class MilkBill {
  final String id;

  /// "2026-10".
  final String month;

  /// issued (waiting for payment), paid or cancelled.
  final String status;
  final int totalPaise;
  final String? dueDate;

  /// online or cash, once paid.
  final String? paymentMethod;
  final bool overdue;
  final List<MilkBillMilk> milk;
  final List<MilkBillLine> lines;

  const MilkBill({
    required this.id,
    required this.month,
    required this.status,
    required this.totalPaise,
    required this.dueDate,
    required this.paymentMethod,
    required this.overdue,
    required this.milk,
    required this.lines,
  });

  bool get isPaid => status == 'paid';
  bool get isUnpaid => status == 'issued';

  factory MilkBill.fromJson(Map<String, dynamic> json) => MilkBill(
    id: json['id'] as String,
    month: json['month'] as String,
    status: json['status'] as String,
    totalPaise: json['total_paise'] as int,
    dueDate: json['due_date'] as String?,
    paymentMethod: json['payment_method'] as String?,
    overdue: json['overdue'] as bool? ?? false,
    milk: [
      for (final m in json['milk'] as List)
        MilkBillMilk.fromJson(m as Map<String, dynamic>),
    ],
    lines: [
      for (final l in json['lines'] as List? ?? const [])
        MilkBillLine.fromJson(l as Map<String, dynamic>),
    ],
  );
}

/// The Sudhamrtam server's milk bill API (`/v1/milk-bills`).
class MilkBillApiClient {
  MilkBillApiClient({
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

  /// The customer's sent and paid bills, newest first.
  Future<List<MilkBill>> fetchBills() async {
    final json = await _send('GET', 'v1/milk-bills');
    return [
      for (final bill in json['bills'] as List)
        MilkBill.fromJson(bill as Map<String, dynamic>),
    ];
  }

  /// Starts or resumes paying a bill online.
  Future<PaymentSession> startPayment(String billId) async {
    final json = await _send('POST', 'v1/milk-bills/$billId/payment');
    return PaymentSession(
      orderId: json['order_id'] as String,
      paymentSessionId: json['payment_session_id'] as String,
      environment: json['environment'] as String,
    );
  }

  /// Asks the server to check the payment with Cashfree. The answer
  /// leaves out the bill's lines.
  Future<MilkBill> checkPayment(String billId) async {
    final json = await _send('POST', 'v1/milk-bills/$billId/payment/check');
    return MilkBill.fromJson(json['bill'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _send(String method, String path) async {
    final session = token();
    if (session == null) {
      throw const MilkBillException(
        'Please sign in to see your milk bills.',
        unauthorized: true,
      );
    }

    final request = http.Request(method, _baseUri.resolve(path))
      ..headers['authorization'] = 'Bearer $session';

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      );
    } on Exception {
      throw const MilkBillException(
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
      throw const MilkBillException(
        'Please sign in again to see your milk bills.',
        unauthorized: true,
      );
    }
    final code = json?['error'] as String?;
    if (code != null) {
      throw MilkBillException(
        json?['message'] as String? ?? 'Sudhamrtam could not do this.',
        code: code,
      );
    }
    throw MilkBillException(
      'Sudhamrtam is not responding right now (error $status). '
      'Please try again.',
    );
  }
}
