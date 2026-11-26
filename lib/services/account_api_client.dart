import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/customer_address.dart';

/// A problem talking to the account API, with a message fit to
/// show the customer.
class AccountApiException implements Exception {
  final String message;

  /// The server rejected the session: the customer must sign in again.
  final bool unauthorized;

  /// The server refused the data (e.g. an invalid PIN code), so
  /// retrying the same request will not help.
  final bool rejected;

  const AccountApiException(
    this.message, {
    this.unauthorized = false,
    this.rejected = false,
  });

  @override
  String toString() => message;
}

/// The signed-in customer's profile on the server.
class ServerProfile {
  final String id;
  final String phoneE164;
  final String? fullName;
  final String? email;

  /// Sudhamrtam's Reg No (e.g. SM-1002), given when the first milk
  /// plan is approved; the same number is on every bill.
  final String? regNo;

  const ServerProfile({
    required this.id,
    required this.phoneE164,
    this.fullName,
    this.email,
    this.regNo,
  });

  factory ServerProfile.fromJson(Map<String, Object?> json) => ServerProfile(
    id: json['id'] as String,
    phoneE164: json['phone_e164'] as String,
    fullName: json['full_name'] as String?,
    email: json['email'] as String?,
    regNo: json['reg_no'] as String?,
  );
}

/// Converts between app addresses and the API's JSON.
///
/// The app keeps 10-digit phone numbers; the API uses +91….
class AddressJson {
  static Map<String, Object?> toJson(CustomerAddress address) => {
    'area_id': address.areaId,
    'label': address.label,
    'recipient_name': address.recipientName,
    'phone': address.phoneNumber,
    'address_line1': address.addressLine1,
    'address_line2': address.addressLine2,
    'landmark': address.landmark,
    'city': address.city,
    'state': address.state,
    'postal_code': address.postalCode,
    'latitude': address.latitude,
    'longitude': address.longitude,
    'is_default': address.isDefault,
    'society_id': address.societyId,
    'society_other': address.societyOther,
    'block': address.block,
    'flat': address.flat,
    'is_house': address.isHouse,
    'delivery_note': address.deliveryNote,
  };

  static CustomerAddress fromJson(
    Map<String, Object?> json, {
    required String customerId,
  }) {
    final phone = json['phone_e164'] as String;

    return CustomerAddress(
      id: json['id'] as String,
      customerId: customerId,
      areaId: json['area_id'] as String?,
      label: json['label'] as String,
      recipientName: json['recipient_name'] as String,
      phoneNumber: phone.startsWith('+91') ? phone.substring(3) : phone,
      addressLine1: json['address_line1'] as String,
      addressLine2: json['address_line2'] as String?,
      landmark: (json['landmark'] as String?) ?? '',
      city: json['city'] as String,
      state: json['state'] as String,
      postalCode: json['postal_code'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      isDefault: json['is_default'] as bool,
      isBilling: json['is_billing'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      societyId: json['society_id'] as String?,
      societyName: json['society_name'] as String?,
      societyOther: json['society_other'] as String?,
      block: json['block'] as String?,
      flat: json['flat'] as String?,
      isHouse: json['is_house'] as bool? ?? false,
      deliveryNote: json['delivery_note'] as String?,
    );
  }
}

/// Signed-in calls for the profile and saved addresses.
class AccountApiClient {
  AccountApiClient({
    required String baseUrl,
    required this._token,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final String? Function() _token;
  final http.Client _http;
  final Duration timeout;

  Future<ServerProfile> getProfile() async {
    final json = await _send('GET', 'v1/me');
    return ServerProfile.fromJson(_map(json['customer']));
  }

  /// Changes only the fields given; an empty string clears one.
  Future<ServerProfile> updateProfile({String? fullName, String? email}) async {
    final json = await _send('PATCH', 'v1/me', {
      'full_name': ?fullName,
      'email': ?email,
    });
    return ServerProfile.fromJson(_map(json['customer']));
  }

  Future<List<CustomerAddress>> listAddresses({
    required String localCustomerId,
  }) async {
    final json = await _send('GET', 'v1/addresses');
    final list = json['addresses'];
    if (list is! List) {
      throw const AccountApiException('Unexpected reply from the server.');
    }
    return [
      for (final item in list)
        AddressJson.fromJson(_map(item), customerId: localCustomerId),
    ];
  }

  /// Creates or replaces the address with this ID.
  Future<CustomerAddress> putAddress(CustomerAddress address) async {
    final json = await _send(
      'PUT',
      'v1/addresses/${Uri.encodeComponent(address.id)}',
      AddressJson.toJson(address),
    );
    return AddressJson.fromJson(
      _map(json['address']),
      customerId: address.customerId,
    );
  }

  /// Deletes the address; an address already gone counts as deleted.
  Future<void> deleteAddress(String addressId) async {
    await _send(
      'DELETE',
      'v1/addresses/${Uri.encodeComponent(addressId)}',
      null,
      const {404},
    );
  }

  /// Marks (or unmarks) the address used on milk bills.
  Future<void> setBillingAddress(String addressId, bool on) async {
    await _send(
      on ? 'POST' : 'DELETE',
      'v1/addresses/${Uri.encodeComponent(addressId)}/billing',
    );
  }

  Future<void> setDefaultAddress(String addressId) async {
    await _send(
      'POST',
      'v1/addresses/${Uri.encodeComponent(addressId)}/default',
    );
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is Map) return Map<String, Object?>.from(value);
    throw const AccountApiException('Unexpected reply from the server.');
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path, [
    Map<String, Object?>? body,
    Set<int> alsoOk = const {},
  ]) async {
    final token = _token();
    if (token == null) {
      throw const AccountApiException(
        'Please sign in again.',
        unauthorized: true,
      );
    }

    final request = http.Request(method, _baseUri.resolve(path))
      ..headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw const AccountApiException(
        'The server did not respond. Please try again.',
      );
    } catch (_) {
      throw const AccountApiException(
        'No internet connection. Please check and try again.',
      );
    }

    final status = response.statusCode;
    if (status == 204 || alsoOk.contains(status)) return const {};

    Map<String, Object?>? json;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) json = Map<String, Object?>.from(decoded);
    } on FormatException {
      json = null;
    }

    if (status == 200 && json != null) return json;

    final message = json?['message'];
    throw AccountApiException(
      message is String && message.isNotEmpty
          ? message
          : 'Could not save to your account (server error $status).',
      unauthorized: status == 401,
      rejected: status == 400 || status == 404 || status == 422,
    );
  }
}
