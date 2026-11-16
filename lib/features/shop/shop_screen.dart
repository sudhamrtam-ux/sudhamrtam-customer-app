import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../models/catalog_repository.dart';
import '../../models/product.dart';
import 'product_details_screen.dart';
import 'product_image.dart';

const _green = Color(0xFF82B440);

class ShopScreen extends StatelessWidget {
  const ShopScreen({
    super.key,
    this.catalog,
    this.category,
    this.onCategoryChanged,
  });

  /// Optional override for tests; defaults to the app catalog.
  final CatalogRepository? catalog;

  /// Shows only this category (null: all products).
  final String? category;

  /// Called when the customer picks a category chip. Without it
  /// the chips are hidden.
  final ValueChanged<String?>? onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final repository = catalog ?? sudhamrtamCatalog;

    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) {
        final allProducts = repository.products;
        final categories = <String>{
          for (final product in allProducts) product.category,
        }.toList();
        // A category that no longer exists falls back to all.
        final selected = categories.contains(category) ? category : null;
        // One card per product; its sizes are chosen on its page.
        final products = productsByName(
          selected == null
              ? allProducts
              : allProducts.where((p) => p.category == selected).toList(),
        );

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
                if (onCategoryChanged != null && categories.length > 1) ...[
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final option in <String?>[null, ...categories])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              key: Key('shopCategory_${option ?? 'all'}'),
                              label: Text(option ?? 'All'),
                              selected: option == selected,
                              selectedColor: _green.withValues(alpha: 0.25),
                              onSelected: (_) => onCategoryChanged!(option),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
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
                          childAspectRatio: 0.68,
                        ),
                    itemBuilder: (context, index) =>
                        _ProductCard(sizes: products[index]),
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
  const _ProductCard({required this.sizes});

  /// The product in each of its sizes (often just one).
  final List<Product> sizes;

  /// The size shown and opened: the cheapest one on sale.
  Product get product {
    final onSale = sizes.where((p) => p.isAvailable).toList()
      ..sort((a, b) => a.price.compareTo(b.price));
    return onSale.firstOrNull ?? sizes.first;
  }

  @override
  Widget build(BuildContext context) {
    final product = this.product;
    final available = product.isAvailable;
    final sizesOnSale = sizes.where((p) => p.isAvailable).length;
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
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Opacity(
                  // Unavailable products look faded.
                  opacity: available ? 1 : 0.4,
                  child: ProductImage(
                    productId: product.id,
                    icon: product.icon,
                    iconColor: color,
                  ),
                ),
              ),
              const SizedBox(height: 8),
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
                !available
                    ? 'Not available'
                    : sizesOnSale > 1
                    ? 'From ₹${product.price.toStringAsFixed(0)}'
                    : '₹${product.price.toStringAsFixed(0)} / ${product.unit}',
                style: TextStyle(fontWeight: FontWeight.w600, color: color),
              ),
              if (sizesOnSale > 1)
                Text(
                  '$sizesOnSale sizes',
                  key: Key('sizes-${product.id}'),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
