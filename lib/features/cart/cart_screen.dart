import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../models/cart_manager.dart';
import '../checkout/checkout_screen.dart';
import '../../models/combo_offer.dart';

const _brandGreen = Color(0xFF82B440);

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  Widget _summaryTile({required String label, required String value}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE1EBCF)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: _brandGreen,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sudhamrtamCart,
      builder: (context, child) {
        final items = sudhamrtamCart.items;

        if (items.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shopping_cart_outlined,
                  size: 72,
                  color: _brandGreen,
                ),
                SizedBox(height: 16),
                Text(
                  'Your cart is empty',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Add products from the Shop tab.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final hasUnpricedProducts = items.any(
          (item) => item.product.price <= 0,
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Your Cart',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${sudhamrtamCart.totalQuantity} units selected',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),

            // Live cart summary.
            Row(
              children: [
                _summaryTile(
                  label: 'Products',
                  value: '${sudhamrtamCart.uniqueItemCount}',
                ),
                const SizedBox(width: 8),
                _summaryTile(
                  label: 'Total units',
                  value: '${sudhamrtamCart.totalQuantity}',
                ),
                const SizedBox(width: 8),
                _summaryTile(
                  label: 'Subtotal',
                  value: hasUnpricedProducts
                      ? 'Pending'
                      : '₹${sudhamrtamCart.subtotal.toStringAsFixed(2)}',
                ),
              ],
            ),

            const SizedBox(height: 24),

            Text(
              'Selected Products',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Product cards.
            ...items.map(
              (item) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(item.product.icon, size: 40, color: _brandGreen),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.product.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // A combo offer lists what is in it.
                            if (isComboProductId(item.product.id)) ...[
                              const Text(
                                'Combo offer',
                                style: TextStyle(
                                  color: Color(0xFFD14A6E),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                item.product.isAvailable
                                    ? item.product.description
                                    : 'This combo offer has ended or '
                                          'changed. Please remove it.',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ] else
                              Text('Pack size: ${item.product.unit}'),
                            const SizedBox(height: 8),

                            // Quantity controls.
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Decrease quantity',
                                  onPressed: item.quantity > 1
                                      ? () {
                                          sudhamrtamCart.decreaseQuantity(
                                            item.product.id,
                                          );
                                        }
                                      : null,
                                  icon: const Icon(Icons.remove_circle_outline),
                                  color: _brandGreen,
                                  visualDensity: VisualDensity.compact,
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    '${item.quantity}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Increase quantity',
                                  onPressed:
                                      item.quantity <
                                          CartManager.maxQuantityOf(
                                            item.product,
                                          )
                                      ? () {
                                          sudhamrtamCart.increaseQuantity(
                                            item.product.id,
                                          );
                                        }
                                      : null,
                                  icon: const Icon(Icons.add_circle_outline),
                                  color: _brandGreen,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),
                            Text(
                              item.product.price > 0
                                  ? '₹${item.totalPrice.toStringAsFixed(2)}'
                                  : 'Price to be updated',
                              style: const TextStyle(
                                color: _brandGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Remove item.
                      IconButton(
                        tooltip: 'Remove product',
                        onPressed: () {
                          sudhamrtamCart.removeProduct(item.product.id);
                        },
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),

            // Pricing information.
            if (hasUnpricedProducts)
              const Text(
                'Some product prices are not yet configured. '
                'The final subtotal will appear once prices '
                'are available.',
                style: TextStyle(color: Colors.black54),
              )
            else
              Text(
                'Product subtotal: '
                '₹${sudhamrtamCart.subtotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),

            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => CheckoutScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Review Checkout'),
              style: FilledButton.styleFrom(
                backgroundColor: _brandGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        );
      },
    );
  }
}
