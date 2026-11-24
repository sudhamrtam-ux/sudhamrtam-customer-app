import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../core/widgets/page_app_bar.dart';
import '../../core/widgets/site_layout.dart';
import '../../models/cart_item.dart';
import '../../models/cart_manager.dart';
import '../../models/combo_offer.dart';
import '../checkout/checkout_screen.dart';
import '../shop/product_image.dart';

const _green = Color(0xFF82B440);
const _dark = Color(0xFF2F4A14);
const _line = Color(0xFFE3EAD6);

String _rupees(double amount) => '₹${amount.toStringAsFixed(2)}';

/// The cart on a wide screen (owner, 2026-11-24, like a shop website):
/// the items in a panel on the left, one row each, and the subtotal
/// with Proceed to Checkout in a box on the right that stays in view
/// while the items scroll.
class WideCart extends StatelessWidget {
  const WideCart({super.key, required this.items});

  final List<CartItem> items;

  @override
  Widget build(BuildContext context) {
    final unpriced = items.any((item) => item.product.price <= 0);
    final count = sudhamrtamCart.totalQuantity;
    final subtotal = unpriced
        ? 'Price pending'
        : _rupees(sudhamrtamCart.subtotal);
    final itemsLabel = '$count ${count == 1 ? 'item' : 'items'}';
    final padding = sitePagePadding(context, top: 24, bottom: 24);

    return Padding(
      padding: EdgeInsets.only(left: padding.left, right: padding.right),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The items.
          Expanded(
            child: ListView(
              key: const Key('wide-cart-items'),
              padding: EdgeInsets.only(top: padding.top, bottom: 24),
              children: [
                _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shopping Cart',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        itemsLabel,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Price',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                      const Divider(color: _line, height: 12),
                      for (final item in items) _ItemRow(item: item),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text.rich(
                          TextSpan(
                            text: 'Subtotal ($itemsLabel): ',
                            children: [
                              TextSpan(
                                text: subtotal,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),

          // The summary, always in view.
          SizedBox(
            width: 330,
            child: Padding(
              padding: EdgeInsets.only(top: padding.top),
              child: _Panel(
                key: const Key('wide-cart-summary'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: 'Subtotal ($itemsLabel): ',
                        children: [
                          TextSpan(
                            text: subtotal,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _dark,
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose the delivery date, address and payment at '
                      'checkout. Orders placed by 9 PM are delivered the '
                      'next morning.',
                      style: TextStyle(color: Colors.black54, height: 1.4),
                    ),
                    if (unpriced) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Some prices are not set yet; the total appears at '
                        'checkout.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('wide-cart-checkout'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => CheckoutScreen(),
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text('Proceed to Checkout'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('wide-cart-continue'),
                      onPressed: () => tabRequests.value = 1,
                      style: TextButton.styleFrom(foregroundColor: _dark),
                      child: const Text('Continue shopping'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _line),
    ),
    child: child,
  );
}

/// One product in the cart: photo, name and pack, quantity, price.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    final id = product.id;
    final combo = isComboProductId(id);
    final canIncrease = item.quantity < CartManager.maxQuantityOf(product);

    return Container(
      key: Key('wide-cart-item-$id'),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 110,
            child: ProductImage(
              key: Key('cart-photo-$id'),
              productId: id,
              icon: product.icon,
              iconSize: 56,
              borderRadius: 8,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                if (combo) ...[
                  const Text(
                    'Combo offer',
                    style: TextStyle(
                      color: Color(0xFFD14A6E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    product.isAvailable
                        ? product.description
                        : 'This combo offer has ended or changed. Please '
                              'remove it.',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ] else
                  Text(
                    'Pack size: ${product.unit}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // − / bin, quantity, +
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: _green, width: 2),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: item.quantity > 1
                                ? 'Decrease quantity'
                                : 'Remove product',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => item.quantity > 1
                                ? sudhamrtamCart.decreaseQuantity(id)
                                : sudhamrtamCart.removeProduct(id),
                            icon: Icon(
                              item.quantity > 1
                                  ? Icons.remove
                                  : Icons.delete_outline,
                              size: 20,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
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
                            visualDensity: VisualDensity.compact,
                            onPressed: canIncrease
                                ? () => sudhamrtamCart.increaseQuantity(id)
                                : null,
                            icon: const Icon(Icons.add, size: 20),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(width: 1, height: 18, color: _line),
                    TextButton(
                      key: Key('wide-cart-delete-$id'),
                      onPressed: () => sudhamrtamCart.removeProduct(id),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF3F6B17),
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                product.price > 0 ? _rupees(item.totalPrice) : 'Price pending',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (product.price > 0 && item.quantity > 1)
                Text(
                  '${_rupees(product.price)} each',
                  style: const TextStyle(color: Colors.black54),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
