import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';

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
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF82B440);

    return Scaffold(
      appBar: AppBar(title: const Text('Product Details')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image placeholder
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8F0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(widget.productIcon, size: 100, color: brandGreen),
              ),

              const SizedBox(height: 24),

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

              // Packaging unit
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

              const SizedBox(height: 24),

              // Product description heading
              Text(
                'About This Product',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              // Product description
              Text(
                widget.description,
                style: const TextStyle(fontSize: 15, height: 1.6),
              ),

              const SizedBox(height: 32),

              // Quantity selector heading
              Text(
                'Select Quantity',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              // Quantity controls
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: _quantity > 1
                        ? () {
                            setState(() {
                              _quantity--;
                            });
                          }
                        : null,
                    icon: const Icon(Icons.remove),
                  ),

                  const SizedBox(width: 20),

                  Text(
                    '$_quantity',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(width: 20),

                  IconButton.filled(
                    onPressed: _quantity < 10
                        ? () {
                            setState(() {
                              _quantity++;
                            });
                          }
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Add to Cart button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _addToCart,
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: const Text('Add to Cart'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

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
                      child: Text(
                        'Pure • Natural • Traditional',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
