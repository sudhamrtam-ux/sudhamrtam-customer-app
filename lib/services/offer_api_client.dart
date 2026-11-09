import 'dart:convert';

import 'package:http/http.dart' as http;

/// Reads today's offer texts (`GET /v1/offers`) for the scrolling
/// line on the Home tab. No sign-in needed. The owner and managers
/// write them in the staff app.
class OfferApiClient {
  OfferApiClient({
    required String baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final http.Client _http;
  final Duration timeout;

  /// The offers running today, in order. Throws when the server
  /// cannot be reached or answers with an error.
  Future<List<String>> fetchOffers() async {
    final response = await _http
        .get(_baseUri.resolve('v1/offers'))
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException('Offers: HTTP ${response.statusCode}');
    }
    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final offer in json['offers'] as List)
        if ((offer as Map<String, dynamic>)['message'] case final String m
            when m.trim().isNotEmpty)
          m.trim(),
    ];
  }
}
