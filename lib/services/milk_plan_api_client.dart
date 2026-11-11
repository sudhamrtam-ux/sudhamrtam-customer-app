import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/milk_subscription.dart';

/// A milk plan change could not be saved on the server. Nothing
/// was changed on the phone either.
class MilkPlanSyncException implements Exception {
  final String message;

  /// Stable server code for a refused change (e.g.
  /// `SHIFT_ALREADY_PLANNED`); null for connection problems.
  final String? code;

  /// The session is no longer valid: sign in again.
  final bool unauthorized;

  const MilkPlanSyncException(
    this.message, {
    this.code,
    this.unauthorized = false,
  });

  @override
  String toString() => message;
}

/// Where milk plans are saved first while signed in.
abstract class MilkPlanRemote {
  /// All the customer's plans, including cancelled ones.
  Future<List<MilkSubscription>> fetchPlans();

  /// Saves and cancels plans in one step; returns all plans after.
  Future<List<MilkSubscription>> applyChanges(
    List<MilkSubscription> saves,
    List<String> cancelIds,
  );
}

/// The Sudhamrtam server's milk plan API (`/v1/milk-plans`).
class MilkPlanApiClient implements MilkPlanRemote {
  MilkPlanApiClient({
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

  static const _frequencies = {
    MilkDeliveryFrequency.daily: 'daily',
    MilkDeliveryFrequency.alternateDays: 'alternate_days',
    MilkDeliveryFrequency.selectedDays: 'selected_days',
    MilkDeliveryFrequency.randomDays: 'random_days',
  };

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime _parseDate(String value) {
    final parts = value.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  /// The server's form of [plan].
  static Map<String, Object?> planToJson(MilkSubscription plan) => {
    'id': plan.id,
    'product_id': plan.productId,
    'status': plan.status.name,
    'resume_on':
        plan.status == MilkSubscriptionStatus.paused && plan.resumeOn != null
        ? _date(plan.resumeOn!)
        : null,
    // Days already past are left out (the server drops them anyway).
    'vacation_dates': [
      for (final d in plan.vacationDaysFrom(DateTime.now())) _date(d),
    ],
    'shifts': [
      for (final shift in plan.shiftSchedules)
        {
          'shift': shift.shift.apiName,
          'quantity_ml': shift.quantityMl,
          'frequency': _frequencies[shift.frequency],
          'weekdays': shift.frequency == MilkDeliveryFrequency.selectedDays
              ? ([...shift.selectedWeekdays]..sort())
              : <int>[],
          'dates': shift.frequency == MilkDeliveryFrequency.randomDays
              ? ([for (final d in shift.selectedRandomDates) _date(d)]..sort())
              : <String>[],
          'start_date': _date(shift.startDate),
          'end_date': shift.endDate == null ? null : _date(shift.endDate!),
        },
    ],
  };

  /// A plan as the server sends it.
  static MilkSubscription planFromJson(Map<String, dynamic> json) {
    final shifts = [
      for (final s in (json['shifts'] as List).cast<Map<String, dynamic>>())
        MilkShiftSchedule(
          shift: MilkDeliveryShift.fromApi(s['shift'] as String),
          quantityMl: s['quantity_ml'] as int,
          frequency: _frequencies.entries
              .firstWhere((e) => e.value == s['frequency'])
              .key,
          selectedWeekdays: List<int>.unmodifiable(
            (s['weekdays'] as List? ?? const []).cast<int>(),
          ),
          selectedRandomDates: List<DateTime>.unmodifiable([
            for (final d in (s['dates'] as List? ?? const []).cast<String>())
              _parseDate(d),
          ]),
          startDate: _parseDate(s['start_date'] as String),
          endDate: s['end_date'] == null
              ? null
              : _parseDate(s['end_date'] as String),
        ),
    ];
    final first = shifts.first;
    final start = shifts
        .map((s) => s.startDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);

    // The legacy single-schedule fields are filled the same way
    // MilkSubscriptionRepository fills them.
    return MilkSubscription(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      shiftSchedules: List.unmodifiable(shifts),
      quantity: 1,
      frequency: first.frequency,
      selectedWeekdays: first.selectedWeekdays,
      selectedRandomDates: first.selectedRandomDates,
      startDate: start,
      status: MilkSubscriptionStatus.values.byName(json['status'] as String),
      cancelledAt: json['cancelled_at'] == null
          ? null
          : DateTime.parse(json['cancelled_at'] as String).toLocal(),
      resumeOn: json['resume_on'] == null
          ? null
          : _parseDate(json['resume_on'] as String),
      vacationDates: List<DateTime>.unmodifiable(
        [
          for (final d
              in (json['vacation_dates'] as List? ?? const []).cast<String>())
            _parseDate(d),
        ]..sort(),
      ),
      approval: json['approval'] as String?,
      rejectReason: json['reject_reason'] as String?,
    );
  }

  @override
  Future<List<MilkSubscription>> fetchPlans() async {
    final response = await _send('GET', 'v1/milk-plans');
    return _plans(response);
  }

  @override
  Future<List<MilkSubscription>> applyChanges(
    List<MilkSubscription> saves,
    List<String> cancelIds,
  ) async {
    final response = await _send(
      'POST',
      'v1/milk-plans/changes',
      body: {
        'saves': [for (final plan in saves) planToJson(plan)],
        'cancel_ids': cancelIds,
      },
    );
    return _plans(response);
  }

  List<MilkSubscription> _plans(http.Response response) {
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {
      // Not JSON.
    }

    final status = response.statusCode;
    if (status == 200 && json != null) {
      return [
        for (final plan in (json['plans'] as List).cast<Map<String, dynamic>>())
          planFromJson(plan),
      ];
    }
    if (status == 401) {
      throw const MilkPlanSyncException(
        'Please sign in again to change your milk plan.',
        unauthorized: true,
      );
    }
    final code = json?['error'] as String?;
    if (status >= 400 && status < 500 && code != null) {
      throw MilkPlanSyncException(
        json?['message'] as String? ?? 'Sudhamrtam could not save this plan.',
        code: code,
      );
    }
    throw MilkPlanSyncException(
      'Sudhamrtam could not save your milk plan right now (error $status). '
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
      throw const MilkPlanSyncException(
        'Please sign in to change your milk plan.',
        unauthorized: true,
      );
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
      throw const MilkPlanSyncException(
        'Sudhamrtam did not respond. Your milk plan was not changed; '
        'please try again.',
      );
    } catch (_) {
      throw const MilkPlanSyncException(
        'No internet connection. Your milk plan was not changed; '
        'please try again.',
      );
    }
  }
}
