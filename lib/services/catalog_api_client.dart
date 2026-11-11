import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/catalog_cache_service.dart';

/// Base URL of the Sudhamrtam API, set at build time:
///
///   flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3000
///
/// Empty (the default, including release builds) means the
/// app does not contact any server.
const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

/// A delivery area served by Sudhamrtam (e.g. Nizampet).
class DeliveryArea {
  final String id;
  final String name;

  const DeliveryArea({required this.id, required this.name});
}

class CatalogApiException implements Exception {
  final String message;
  const CatalogApiException(this.message);

  @override
  String toString() => 'CatalogApiException: $message';
}

/// Reads the public catalog endpoint of the backend.
///
/// Every customer sees the same products at the same prices
/// (owner decision, 6 November 2026), so there is no area.
class CatalogApiClient {
  CatalogApiClient({
    required String baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  }) : _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final http.Client _http;
  final Duration timeout;

  /// Returns a client for [apiBaseUrl], or null when no
  /// server is configured for this build.
  static CatalogApiClient? fromEnvironment() {
    return apiBaseUrl.isEmpty ? null : CatalogApiClient(baseUrl: apiBaseUrl);
  }

  Future<List<CatalogProductData>> fetchCatalog() async {
    final json = await _getJson(_baseUri.resolve('v1/catalog'));

    final products = json['products'];

    if (products is! List) {
      throw const CatalogApiException('Malformed catalog response.');
    }

    try {
      return [
        for (final product in products)
          CatalogProductData.fromJson(
            Map<String, Object?>.from(product as Map),
          ),
      ];
    } on FormatException catch (error) {
      throw CatalogApiException('Invalid product data: ${error.message}');
    } on TypeError {
      throw const CatalogApiException('Invalid product data.');
    }
  }

  /// Delivery areas, for choosing an address's area.
  Future<List<DeliveryArea>> fetchAreas() async {
    final json = await _getJson(_baseUri.resolve('v1/areas'));
    final areas = json['areas'];

    if (areas is! List) {
      throw const CatalogApiException('Malformed areas response.');
    }

    try {
      return [
        for (final area in areas)
          DeliveryArea(
            id: (area as Map)['id'] as String,
            name: area['name'] as String,
          ),
      ];
    } on TypeError {
      throw const CatalogApiException('Invalid area data.');
    }
  }

  /// An area's societies (Sudhamrtam's list), for the address form.
  Future<List<DeliveryArea>> fetchSocieties(String areaId) async {
    final json = await _getJson(
      _baseUri.resolve('v1/areas/${Uri.encodeComponent(areaId)}/societies'),
    );
    final societies = json['societies'];
    if (societies is! List) {
      throw const CatalogApiException('Malformed societies response.');
    }
    try {
      return [
        for (final s in societies)
          DeliveryArea(
            id: (s as Map)['id'] as String,
            name: s['name'] as String,
          ),
      ];
    } on TypeError {
      throw const CatalogApiException('Invalid society data.');
    }
  }

  Future<Map<String, Object?>> _getJson(Uri uri) async {
    final http.Response response;

    try {
      response = await _http.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const CatalogApiException('The server did not respond in time.');
    } catch (error) {
      throw CatalogApiException('Could not reach the server: $error');
    }

    if (response.statusCode != 200) {
      throw CatalogApiException('Server returned ${response.statusCode}.');
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } on FormatException {
      // Fall through.
    }

    throw const CatalogApiException('Server response was not valid JSON.');
  }
}
