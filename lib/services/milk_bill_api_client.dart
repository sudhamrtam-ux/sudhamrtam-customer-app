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
    this.measure = 'litre',
    this.unitLabel,
  });

  /// 'pack': [quantityMl] counts packs of [unitLabel] (step 5).
  final String measure;
  final String? unitLabel;

  bool get isPack => measure == 'pack';

  /// "1.50 L" or "2 × 500 g".
  String get amountText => isPack
      ? '$quantityMl × ${unitLabel ?? 'pack'}'
      : '${(quantityMl / 1000).toStringAsFixed(2)} L';

  factory MilkBillMilk.fromJson(Map<String, dynamic> json) => MilkBillMilk(
    measure: json['measure'] as String? ?? 'litre',
    unitLabel: json['unit_label'] as String?,
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
    this.measure = 'litre',
    this.unitLabel,
  });

  /// 'pack': [quantityMl] counts packs of [unitLabel] (step 5).
  final String measure;
  final String? unitLabel;

  bool get isPack => measure == 'pack';

  /// "1.50 L" or "2 × 500 g".
  String get amountText => isPack
      ? '$quantityMl × ${unitLabel ?? 'pack'}'
      : '${(quantityMl / 1000).toStringAsFixed(2)} L';

  factory MilkBillLine.fromJson(Map<String, dynamic> json) => MilkBillLine(
    measure: json['measure'] as String? ?? 'litre',
    unitLabel: json['unit_label'] as String?,
    deliveryDate: json['delivery_date'] as String,
    shift: json['shift'] as String,
    productName: json['product_name'] as String,
    quantityMl: json['quantity_ml'] as int,
    unitPricePaise: json['unit_price_paise'] as int,
    amountPaise: json['amount_paise'] as int,
  );
}

/// An extra item Sudhamrtam delivered on a phone order (curd, honey,
/// oils, extra milk), charged on the month's milk bill.
class MilkBillItem {
  final String deliveryDate;
  final String shift;
  final String productName;
  final String unitLabel;
  final int quantity;
  final int unitPricePaise;
  final int amountPaise;

  const MilkBillItem({
    required this.deliveryDate,
    required this.shift,
    required this.productName,
    required this.unitLabel,
    required this.quantity,
    required this.unitPricePaise,
    required this.amountPaise,
  });

  factory MilkBillItem.fromJson(Map<String, dynamic> json) => MilkBillItem(
    deliveryDate: json['delivery_date'] as String,
    shift: json['shift'] as String,
    productName: json['product_name'] as String,
    unitLabel: json['unit_label'] as String,
    quantity: json['quantity'] as int,
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

  /// What is paid: actual amount − discount + GST.
  final int totalPaise;

  /// Actual amount: the delivered milk at its price.
  final int subtotalPaise;
  final int discountPaise;

  /// Set when the discount is a percentage (basis points, 10% = 1000).
  final int? discountPercentBp;
  final int gstPaise;
  final String? dueDate;

  /// online or cash, once paid.
  final String? paymentMethod;
  final bool overdue;
  final List<MilkBillMilk> milk;
  final List<MilkBillLine> lines;

  /// Extra items delivered on phone orders.
  final List<MilkBillItem> items;

  /// A bill made before the month ended (moving out): the last day
  /// billed.
  final String? periodEnd;

  const MilkBill({
    required this.id,
    required this.month,
    required this.status,
    required this.totalPaise,
    int? subtotalPaise,
    this.discountPaise = 0,
    this.discountPercentBp,
    this.gstPaise = 0,
    required this.dueDate,
    required this.paymentMethod,
    required this.overdue,
    required this.milk,
    required this.lines,
    this.items = const [],
    this.periodEnd,
  }) : subtotalPaise = subtotalPaise ?? totalPaise;

  bool get isPaid => status == 'paid';
  bool get isUnpaid => status == 'issued';

  factory MilkBill.fromJson(Map<String, dynamic> json) => MilkBill(
    id: json['id'] as String,
    month: json['month'] as String,
    status: json['status'] as String,
    totalPaise: json['total_paise'] as int,
    subtotalPaise: json['subtotal_paise'] as int?,
    discountPaise: json['discount_paise'] as int? ?? 0,
    discountPercentBp: json['discount_percent_bp'] as int?,
    gstPaise: json['gst_paise'] as int? ?? 0,
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
    items: [
      for (final i in json['items'] as List? ?? const [])
        MilkBillItem.fromJson(i as Map<String, dynamic>),
    ],
    periodEnd: json['period_end'] as String?,
  );
}

/// One milk in one delivery.
class MilkDeliveryItem {
  final String productName;
  final int quantityMl;

  /// Per litre, as the bill charges it; null if the milk has no price.
  final int? unitPricePaise;

  /// Charged only when delivered.
  final int amountPaise;

  const MilkDeliveryItem({
    required this.productName,
    required this.quantityMl,
    required this.unitPricePaise,
    required this.amountPaise,
    this.measure = 'litre',
    this.unitLabel,
  });

  /// 'pack': [quantityMl] counts packs of [unitLabel] (step 5).
  final String measure;
  final String? unitLabel;

  bool get isPack => measure == 'pack';

  /// "1.50 L" or "2 × 500 g".
  String get amountText => isPack
      ? '$quantityMl × ${unitLabel ?? 'pack'}'
      : '${(quantityMl / 1000).toStringAsFixed(2)} L';

  factory MilkDeliveryItem.fromJson(Map<String, dynamic> json) =>
      MilkDeliveryItem(
        measure: json['measure'] as String? ?? 'litre',
        unitLabel: json['unit_label'] as String?,
        productName: json['name'] as String,
        quantityMl: json['quantity_ml'] as int,
        unitPricePaise: json['unit_price_paise'] as int?,
        amountPaise: json['amount_paise'] as int,
      );
}

/// One delivery (one date and shift) in the customer's milk history.
class MilkDelivery {
  /// "2026-11-08".
  final String date;

  /// early_morning, morning or evening.
  final String shift;

  /// delivered, not_delivered, paused (the plan was paused), or null
  /// while not marked yet (today).
  final String? outcome;
  final String? reason;
  final List<MilkDeliveryItem> items;

  const MilkDelivery({
    required this.date,
    required this.shift,
    required this.outcome,
    required this.reason,
    required this.items,
  });

  bool get isDelivered => outcome == 'delivered';
  bool get isMissed => outcome == 'not_delivered';
  bool get isPaused => outcome == 'paused';

  /// Litres products only, in ml.
  int get quantityMl =>
      items.fold(0, (sum, i) => sum + (i.isPack ? 0 : i.quantityMl));

  /// Packs of pack products.
  int get packs =>
      items.fold(0, (sum, i) => sum + (i.isPack ? i.quantityMl : 0));
  int get amountPaise => items.fold(0, (sum, i) => sum + i.amountPaise);

  factory MilkDelivery.fromJson(Map<String, dynamic> json) => MilkDelivery(
    date: json['date'] as String,
    shift: json['shift'] as String,
    outcome: json['outcome'] as String?,
    reason: json['reason'] as String?,
    items: [
      for (final item in json['items'] as List)
        MilkDeliveryItem.fromJson(item as Map<String, dynamic>),
    ],
  );
}

/// A month of milk deliveries, before the bill too.
class MilkDeliveryMonth {
  /// "2026-11".
  final String month;
  final List<MilkDelivery> deliveries;
  final int deliveredCount;
  final int missedCount;
  final int pausedCount;
  final int notMarkedCount;
  final int deliveredMl;

  /// What delivered milk comes to; the bill is final.
  final int amountPaise;

  /// The month's bill once sent.
  final String? billId;
  final int? billTotalPaise;

  const MilkDeliveryMonth({
    required this.month,
    required this.deliveries,
    required this.deliveredCount,
    required this.missedCount,
    required this.pausedCount,
    required this.notMarkedCount,
    required this.deliveredMl,
    required this.amountPaise,
    required this.billId,
    required this.billTotalPaise,
  });

  /// The deliveries on [date] ("2026-11-08"), early morning first.
  List<MilkDelivery> on(String date) => [
    for (final d in deliveries)
      if (d.date == date) d,
  ];

  /// The rates charged this month, per litre (usually one).
  Set<int> get rates => {
    for (final d in deliveries)
      if (d.isDelivered)
        for (final i in d.items)
          if (i.unitPricePaise != null && !i.isPack) i.unitPricePaise!,
  };

  factory MilkDeliveryMonth.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'] as Map<String, dynamic>;
    final bill = json['bill'] as Map<String, dynamic>?;
    return MilkDeliveryMonth(
      month: json['month'] as String,
      deliveries: [
        for (final d in json['deliveries'] as List)
          MilkDelivery.fromJson(d as Map<String, dynamic>),
      ],
      deliveredCount: totals['delivered'] as int,
      missedCount: totals['not_delivered'] as int,
      pausedCount: totals['paused'] as int? ?? 0,
      notMarkedCount: totals['not_marked'] as int,
      deliveredMl: totals['delivered_ml'] as int,
      amountPaise: totals['amount_paise'] as int,
      billId: bill?['id'] as String?,
      billTotalPaise: bill?['total_paise'] as int?,
    );
  }
}

/// Settle bill and close subscription (owner request 2026-11-26):
/// what closing means now, and the latest closing.
class SubscriptionClosing {
  const SubscriptionClosing({
    required this.status,
    required this.lastDeliveryDate,
    this.billIds = const [],
  });

  /// 'waiting' (final bill not made yet), 'billed' or 'nothing_to_bill'.
  final String status;
  final String lastDeliveryDate;
  final List<String> billIds;

  bool get isWaiting => status == 'waiting';

  factory SubscriptionClosing.fromJson(Map<String, dynamic> json) =>
      SubscriptionClosing(
        status: json['status'] as String,
        lastDeliveryDate: json['last_delivery_date'] as String,
        billIds: [
          for (final id in json['bill_ids'] as List? ?? []) id as String,
        ],
      );
}

/// An issued bill not paid yet, as the closing card lists it.
class UnpaidBill {
  const UnpaidBill({
    required this.id,
    required this.month,
    required this.totalPaise,
  });

  final String id;

  /// "2026-11".
  final String month;
  final int totalPaise;

  factory UnpaidBill.fromJson(Map<String, dynamic> json) => UnpaidBill(
    id: json['id'] as String,
    month: json['month'] as String,
    totalPaise: json['total_paise'] as int,
  );
}

class ClosingInfo {
  const ClosingInfo({
    this.closing,
    required this.openPlans,
    required this.canClose,
    required this.lastDeliveryDate,
    this.unpaidBills = const [],
    required this.unpaidPaise,
    required this.soFarPaise,
    required this.totalPaise,
  });

  final SubscriptionClosing? closing;
  final int openPlans;
  final bool canClose;

  /// The last delivery day if the customer closes now.
  final String lastDeliveryDate;

  /// Issued bills not paid yet, oldest first.
  final List<UnpaidBill> unpaidBills;
  final int unpaidPaise;

  /// Delivered, not billed yet (an estimate).
  final int soFarPaise;
  final int totalPaise;

  factory ClosingInfo.fromJson(Map<String, dynamic> json) => ClosingInfo(
    closing: json['closing'] == null
        ? null
        : SubscriptionClosing.fromJson(json['closing'] as Map<String, dynamic>),
    openPlans: json['open_plans'] as int,
    canClose: json['can_close'] as bool,
    lastDeliveryDate: json['last_delivery_date'] as String,
    unpaidBills: [
      for (final b in (json['unpaid_bills'] as List?) ?? const [])
        UnpaidBill.fromJson(b as Map<String, dynamic>),
    ],
    unpaidPaise: json['unpaid_paise'] as int,
    soFarPaise: json['so_far_paise'] as int,
    totalPaise: json['total_paise'] as int,
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

  /// The milk delivered (or missed) in [month] ("2026-11"), day by day.
  Future<MilkDeliveryMonth> fetchDeliveries(String month) async {
    final json = await _send('GET', 'v1/milk-deliveries?month=$month');
    return MilkDeliveryMonth.fromJson(json);
  }

  /// Everything the printed bill shows (a sent or paid bill).
  Future<Map<String, dynamic>> fetchPrint(String billId) =>
      _send('GET', 'v1/milk-bills/$billId/print');

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

  /// What "Settle bill and close subscription" means now.
  Future<ClosingInfo> fetchClosing() async =>
      ClosingInfo.fromJson(await _send('GET', 'v1/milk-plans/closing'));

  /// Stops every milk subscription; the final bill comes the morning
  /// after the last delivery. The account stays.
  Future<ClosingInfo> closeSubscription() async =>
      ClosingInfo.fromJson(await _send('POST', 'v1/milk-plans/close'));

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
