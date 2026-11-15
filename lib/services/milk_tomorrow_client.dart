import 'dart:convert';

import 'package:http/http.dart' as http;

/// One plan shift delivering on the day (`/v1/milk-plans/tomorrow`).
class TomorrowShift {
  const TomorrowShift({
    required this.planId,
    required this.productName,
    required this.shift,
    required this.usualMl,
    required this.quantityMl,
    required this.skipped,
    required this.closesAt,
    required this.open,
  });

  factory TomorrowShift.fromJson(Map<String, dynamic> json) => TomorrowShift(
    planId: json['plan_id'] as String,
    productName: json['product_name'] as String,
    shift: json['shift'] as String,
    usualMl: json['usual_ml'] as int,
    quantityMl: json['quantity_ml'] as int,
    skipped: json['skipped'] as bool,
    closesAt: DateTime.parse(json['closes_at'] as String),
    open: json['open'] as bool,
  );

  final String planId;
  final String productName;

  /// early_morning, morning or evening.
  final String shift;
  final int usualMl;
  final int quantityMl;
  final bool skipped;
  final DateTime closesAt;
  final bool open;

  bool get changed => quantityMl != usualMl;
}

class TomorrowMilk {
  const TomorrowMilk({required this.date, required this.shifts});

  factory TomorrowMilk.fromJson(Map<String, dynamic> json) => TomorrowMilk(
    date: json['date'] as String,
    shifts: [
      for (final s in json['shifts'] as List)
        TomorrowShift.fromJson(s as Map<String, dynamic>),
    ],
  );

  /// YYYY-MM-DD (India).
  final String date;
  final List<TomorrowShift> shifts;
}

class MilkTomorrowException implements Exception {
  const MilkTomorrowException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Tomorrow's milk: skip the day, or a one-day quantity per shift.
class MilkTomorrowClient {
  MilkTomorrowClient({
    required String baseUrl,
    required this.token,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final String? Function() token;
  final http.Client _http;
  final Duration timeout;

  bool get isSignedIn => token() != null;

  Future<TomorrowMilk> fetch() => _send('GET', 'v1/milk-plans/tomorrow');

  /// A one-day quantity; null goes back to the usual.
  Future<TomorrowMilk> setQuantity(
    String planId, {
    required String date,
    required String shift,
    required int? quantityMl,
  }) => _send('PUT', 'v1/milk-plans/$planId/day', {
    'date': date,
    'shift': shift,
    'quantity_ml': quantityMl,
  });

  Future<TomorrowMilk> skip(
    String planId, {
    required String date,
    required bool skip,
  }) =>
      _send('PUT', 'v1/milk-plans/$planId/skip', {'date': date, 'skip': skip});

  Future<TomorrowMilk> _send(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final request = http.Request(method, _baseUri.resolve(path))
      ..headers['authorization'] = 'Bearer ${token() ?? ''}';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      );
    } catch (_) {
      throw const MilkTomorrowException(
        'Could not reach Sudhamrtam. Check your connection and try again.',
      );
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      // Not JSON.
    }
    if (response.statusCode == 200 && json is Map<String, dynamic>) {
      return TomorrowMilk.fromJson(json);
    }
    if (json is Map && json['message'] is String) {
      throw MilkTomorrowException(json['message'] as String);
    }
    throw const MilkTomorrowException(
      'Something went wrong. Please try again.',
    );
  }
}
