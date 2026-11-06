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

/// A delivery area offered by the server.
class DeliveryArea {
  final String id;
  final String name;

  const DeliveryArea({required this.id, required this.name});
}

/// One area's catalog as returned by the server.
class AreaCatalog {
  final DeliveryArea area;
  final List<CatalogProductData> products;

  AreaCatalog({required this.area, required List<CatalogProductData> products})
    : products = List.unmodifiable(products);
}

class CatalogApiException implements Exception {
  final String message;
  const CatalogApiException(this.message);

  @override
  String toString() => 'CatalogApiException: $message';
}

/// Reads the public catalog endpoints of the backend.
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

  Future<List<DeliveryArea>> fetchAreas() async {
    final json = await _getJson(_baseUri.resolve('v1/areas'));

    final areas = json['areas'];
    if (areas is! List) {
      throw const CatalogApiException('Malformed areas response.');
    }

    return [
      for (final area in areas)
        DeliveryArea(
          id: (area as Map)['id'] as String,
          name: area['name'] as String,
        ),
    ];
  }

  Future<AreaCatalog> fetchCatalog(String areaId) async {
    final json = await _getJson(
      _baseUri
          .resolve('v1/catalog')
          .replace(queryParameters: {'area_id': areaId}),
    );

    final area = json['area'];
    final products = json['products'];

    if (area is! Map || products is! List) {
      throw const CatalogApiException('Malformed catalog response.');
    }

    if (area['id'] != areaId) {
      throw const CatalogApiException('Catalog is for a different area.');
    }

    try {
      return AreaCatalog(
        area: DeliveryArea(
          id: area['id'] as String,
          name: area['name'] as String,
        ),
        products: [
          for (final product in products)
            CatalogProductData.fromJson(
              Map<String, Object?>.from(product as Map),
            ),
        ],
      );
    } on FormatException catch (error) {
      throw CatalogApiException('Invalid product data: ${error.message}');
    } on TypeError {
      throw const CatalogApiException('Invalid product data.');
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
