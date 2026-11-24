import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../core/company.dart';
import '../../models/product.dart';
import 'product_description.dart';
import 'product_image.dart';
import 'quantity_bill.dart';
import '../../core/widgets/page_app_bar.dart';
import '../../core/widgets/site_layout.dart';

class ProductDetailsScreen extends StatefulWidget {
  final String productId;
  final String productName;
  final String category;
  final IconData productIcon;
  final String description;
  final String unit;
  final double price;

  const ProductDetailsScreen({
    super.key,
    required this.productId,
    required this.productName,
    required this.category,
    required this.productIcon,
    required this.description,
    required this.unit,
    required this.price,
  });

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  int _quantity = 1;

  // Add the selected product and show an accurate message.
  void _addToCart() {
    // Resolve by ID through the catalog, so area prices and
    // server-only products (e.g. Paneer) work.
    final product = sudhamrtamCatalog.productById(widget.productId);

    if (product == null || !product.isAvailable) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${widget.productName} is not available in your delivery area.',
            ),
          ),
        );
      return;
    }

    // Check how many units are already in the cart.
    final existingItems = sudhamrtamCart.items.where(
      (item) => item.product.id == product.id,
    );

    final previousQuantity = existingItems.isEmpty
        ? 0
        : existingItems.first.quantity;

    // Add the selected quantity to the shared cart.
    // CartManager enforces the maximum quantity of 10.
    sudhamrtamCart.addProduct(product, quantity: _quantity);

    // Read the actual quantity after adding.
    final updatedItems = sudhamrtamCart.items.where(
      (item) => item.product.id == product.id,
    );

    final updatedQuantity = updatedItems.isEmpty
        ? 0
        : updatedItems.first.quantity;

    final addedQuantity = updatedQuantity - previousQuantity;

    // Build the correct confirmation message.
    String message;

    if (addedQuantity == 0) {
      message =
          'Maximum quantity of 10 reached for '
          '${widget.productName}.';
    } else if (addedQuantity < _quantity) {
      message =
          '$addedQuantity unit(s) of '
          '${widget.productName} added. '
          'Maximum quantity of 10 reached.';
    } else {
      message =
          '${widget.productName} added to cart '
          '(Quantity: $addedQuantity)';
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          action: addedQuantity > 0
              ? SnackBarAction(
                  label: 'VIEW CART',
                  onPressed: () => openTab(context, cartTab),
                )
              : null,
        ),
      );
  }

  /// Opens the same product in another size (e.g. honey 250 g).
  void _openSize(Product size) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => ProductDetailsScreen(
          productId: size.id,
          productName: size.name,
          category: size.category,
          productIcon: size.icon,
          description: size.description,
          unit: size.unit,
          price: size.price,
        ),
        transitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF82B440);
    // The same product in other sizes, smallest price first.
    final sizes =
        sudhamrtamCatalog.products
            .where((p) => p.name == widget.productName && p.isAvailable)
            .toList()
          ..sort((a, b) => a.price.compareTo(b.price));

    final wide = isWideSite(context);

    // Product photo (icon when there is none).
    final photo = Container(
      key: const Key('product-photo'),
      height: wide ? null : 300,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ProductImage(
        productId: widget.productId,
        icon: widget.productIcon,
        iconSize: 100,
        borderRadius: 20,
      ),
    );

    final details = <Widget>[
      // Product name
      Text(
        widget.productName,
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),

      const SizedBox(height: 8),

      // Product category
      Text(
        widget.category,
        style: const TextStyle(
          color: brandGreen,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),

      const SizedBox(height: 8),

      // Packaging unit, or a choice of sizes.
      if (sizes.length > 1)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final size in sizes)
              ChoiceChip(
                key: Key('size-${size.id}'),
                label: Text('${size.unit} · ₹${size.price.toStringAsFixed(0)}'),
                selected: size.id == widget.productId,
                selectedColor: const Color(0xFFE5F0D7),
                onSelected: size.id == widget.productId
                    ? null
                    : (_) => _openSize(size),
              ),
          ],
        )
      else
        Text(
          'Pack size: ${widget.unit}',
          style: const TextStyle(fontSize: 15, color: Colors.black54),
        ),

      const SizedBox(height: 12),

      // Product price
      Text(
        widget.price > 0
            ? 'Price: ₹${widget.price.toStringAsFixed(2)}'
            : 'Price to be updated',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: brandGreen,
        ),
      ),

      const SizedBox(height: 20),

      // Quantity selector heading
      Text(
        'Select Quantity',
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.bold),
      ),

      const SizedBox(height: 12),

      // Quantity with the bill next to it (owner request
      // 2026-11-15): price × quantity before adding to the cart.
      ListenableBuilder(
        listenable: sudhamrtamCart,
        builder: (context, _) {
          final price =
              sudhamrtamCatalog.productById(widget.productId)?.price ??
              widget.price;
          final inCart = sudhamrtamCart.items
              .where((item) => item.product.id == widget.productId)
              .fold(0, (sum, item) => sum + item.quantity);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              QuantityBill(
                quantity: _quantity,
                unitPrice: price,
                unit: widget.unit,
                inCart: inCart,
                maxQuantity: 10,
                onChanged: (q) => setState(() => _quantity = q),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                key: const Key('add-to-cart'),
                onPressed: _addToCart,
                icon: const Icon(Icons.shopping_cart_outlined),
                label: Text(
                  price > 0
                      ? 'Add to Cart · ${billRupees(price * _quantity)}'
                      : 'Add to Cart',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          );
        },
      ),

      const SizedBox(height: 20),

      // Next to the quantity (owner request 2026-11-15): short,
      // with Read more.
      ProductDescription(description: widget.description),

      const SizedBox(height: 20),

      // Brand values
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8F0),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          children: [
            Icon(Icons.verified_outlined, color: brandGreen),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pure • Natural • Traditional',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'FSSAI Lic. No. $sudhamrtamFssai',
                    key: Key('productFssai'),
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];

    return Scaffold(
      appBar: PageAppBar(title: const Text('Product Details')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: wide
              ? sitePagePadding(context, top: 32, bottom: 40)
              : const EdgeInsets.all(20),
          child: wide
              // A website (owner, 2026-11-24): the photo on the left,
              // everything to choose and buy on the right.
              ? Row(
                  key: const Key('product-wide'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: AspectRatio(aspectRatio: 1, child: photo),
                    ),
                    const SizedBox(width: 48),
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: details,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [photo, const SizedBox(height: 24), ...details],
                ),
        ),
      ),
    );
  }
}
