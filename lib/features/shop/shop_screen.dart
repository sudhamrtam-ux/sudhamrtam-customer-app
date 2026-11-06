import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../models/catalog_repository.dart';
import '../../models/product.dart';
import 'product_details_screen.dart';

const _green = Color(0xFF82B440);

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key, this.catalog});

  /// Optional override for tests; defaults to the app catalog.
  final CatalogRepository? catalog;

  @override
  Widget build(BuildContext context) {
    final repository = catalog ?? sudhamrtamCatalog;

    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) {
        final products = repository.products;

        return SafeArea(
          child: RefreshIndicator(
            color: _green,
            onRefresh: repository.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Our Products',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Discover pure dairy and naturally crafted farm products.',
                ),
                if (repository.canUseServer)
                  _CatalogStatus(repository: repository),
                const SizedBox(height: 20),
                if (products.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No products are available yet.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: products.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                    itemBuilder: (context, index) =>
                        _ProductCard(product: products[index]),
                  ),
                const SizedBox(height: 20),
                const Center(
                  child: Text(
                    'Pure • Natural • Traditional',
                    style: TextStyle(
                      color: _green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =====================================================
// CATALOG STATUS
// =====================================================

class _CatalogStatus extends StatelessWidget {
  const _CatalogStatus({required this.repository});

  final CatalogRepository repository;

  @override
  Widget build(BuildContext context) {
    final String? text;

    if (repository.isRefreshing) {
      text = 'Updating prices…';
    } else if (repository.lastRefreshError != null) {
      text = repository.source == CatalogSource.cached
          ? 'Could not reach the server. Showing saved prices.'
          : 'Could not reach the server. Showing standard prices.';
    } else {
      text = null;
    }

    if (text == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
    );
  }
}

// =====================================================
// PRODUCT CARD
// =====================================================

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final available = product.isAvailable;
    final color = available ? _green : Colors.grey;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailsScreen(
              productId: product.id,
              productName: product.name,
              category: product.category,
              productIcon: product.icon,
              description: product.description,
              unit: product.unit,
              price: product.price,
            ),
          ),
        );
      },
      child: Card(
        color: available ? const Color(0xFFF5F8F0) : const Color(0xFFF2F2F2),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE1EBCF)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(product.icon, size: 42, color: color),
              const SizedBox(height: 12),
              Text(
                product.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                product.category,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 6),
              Text(
                available
                    ? '₹${product.price.toStringAsFixed(0)} / ${product.unit}'
                    : 'Not available',
                style: TextStyle(fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
