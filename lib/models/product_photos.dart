import '../services/catalog_api_client.dart' show apiBaseUrl;

/// The owner's product photos on the server, by product ID (owner
/// decision 2026-11-15): full addresses, set from the catalog. A
/// product without one shows the photo built into the app.
Map<String, String> productPhotoUrls = const {};

/// The other sizes of each product, by product ID (e.g. Paneer 200 g:
/// Paneer 1 kg): a size without a photo of its own shows theirs.
Map<String, List<String>> productOtherSizes = const {};

/// Takes the catalog's photo links (`/v1/products/{id}/photo?v=…`).
void setProductPhotoUrls(Map<String, String> paths) {
  if (apiBaseUrl.isEmpty) {
    productPhotoUrls = const {};
    return;
  }
  final base = Uri.parse(
    apiBaseUrl.endsWith('/') ? apiBaseUrl : '$apiBaseUrl/',
  );
  productPhotoUrls = {
    for (final e in paths.entries)
      e.key: base
          .resolve(e.value.startsWith('/') ? e.value.substring(1) : e.value)
          .toString(),
  };
}
