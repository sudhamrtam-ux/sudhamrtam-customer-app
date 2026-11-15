import 'dart:convert';

import 'package:http/http.dart' as http;

/// Whether the account can be deleted now, and if not, why.
class DeletionCheck {
  const DeletionCheck({
    required this.canDelete,
    this.message,
    this.unpaidPaise = 0,
  });

  factory DeletionCheck.fromJson(Map<String, dynamic> json) => DeletionCheck(
    canDelete: json['can_delete'] as bool,
    message: json['message'] as String?,
    unpaidPaise:
        ((json['unpaid_bills_paise'] as num?) ?? 0).toInt() +
        ((json['unbilled_paise'] as num?) ?? 0).toInt(),
  );

  final bool canDelete;

  /// The reason, in the customer's words, when it cannot.
  final String? message;

  /// Bills not paid plus milk not billed yet.
  final int unpaidPaise;
}

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message, {this.notSettled = false});

  final String message;

  /// Something is owed or still to be delivered (not a connection
  /// problem).
  final bool notSettled;

  @override
  String toString() => message;
}

/// Delete my account (`/v1/me/deletion-check`, `/v1/me/delete`).
class AccountDeletionClient {
  AccountDeletionClient({
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

  static const _offline =
      'Could not reach Sudhamrtam. Check your connection and try again.';

  Map<String, String> _headers() => {
    'authorization': 'Bearer ${token() ?? ''}',
    'content-type': 'application/json',
  };

  Future<DeletionCheck> check() async {
    final http.Response response;
    try {
      response = await _http
          .get(_baseUri.resolve('v1/me/deletion-check'), headers: _headers())
          .timeout(timeout);
    } catch (_) {
      throw const AccountDeletionException(_offline);
    }
    if (response.statusCode != 200) {
      throw AccountDeletionException(_messageOf(response));
    }
    return DeletionCheck.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Deletes the account. Throws [AccountDeletionException] when it
  /// was not deleted.
  Future<void> delete() async {
    final http.Response response;
    try {
      response = await _http
          .post(
            _baseUri.resolve('v1/me/delete'),
            headers: _headers(),
            body: jsonEncode({'confirm': 'DELETE'}),
          )
          .timeout(timeout);
    } catch (_) {
      throw const AccountDeletionException(_offline);
    }
    if (response.statusCode == 204) return;
    throw AccountDeletionException(
      _messageOf(response),
      notSettled: response.statusCode == 409,
    );
  }

  static String _messageOf(http.Response response) {
    if (response.statusCode == 401) return 'Please sign in again.';
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is Map && json['message'] is String) {
        return json['message'] as String;
      }
    } catch (_) {
      // Not JSON.
    }
    return 'Something went wrong. Please try again, or call us.';
  }
}
