import 'dart:convert';

import 'package:http/http.dart' as http;

/// A text offer as a Home tile (owner request 2026-11-26).
class TextOffer {
  const TextOffer({required this.id, required this.message, this.tileColour});

  final String id;
  final String message;

  /// '#RRGGBB'; null = the usual green.
  final String? tileColour;
}

/// Today's text offers and how many tiles share the Home row on a
/// computer (the owner's choice, 1-4).
class OfferTiles {
  const OfferTiles({this.offers = const [], this.perRow = 2});

  final List<TextOffer> offers;
  final int perRow;
}

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
  Future<List<String>> fetchOffers() async => [
    for (final o in (await fetchTiles()).offers) o.message,
  ];

  /// The offers as tiles, with the owner's tiles-per-row (2 from an
  /// older server).
  Future<OfferTiles> fetchTiles() async {
    final response = await _http
        .get(_baseUri.resolve('v1/offers'))
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException('Offers: HTTP ${response.statusCode}');
    }
    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return OfferTiles(
      offers: [
        for (final offer in json['offers'] as List)
          if ((offer as Map<String, dynamic>)['message'] case final String m
              when m.trim().isNotEmpty)
            TextOffer(
              id: offer['id'] as String? ?? m,
              message: m.trim(),
              tileColour: offer['tile_colour'] as String?,
            ),
      ],
      perRow: ((json['offer_tiles'] as int?) ?? 2).clamp(1, 4),
    );
  }
}
