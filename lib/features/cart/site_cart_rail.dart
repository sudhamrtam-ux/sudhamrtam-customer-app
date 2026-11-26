import 'package:flutter/material.dart';

import '../../models/cart_item.dart';
import '../../models/cart_manager.dart';
import '../shop/product_image.dart';

const _dark = Color(0xFF2F4A14);
const _green = Color(0xFF82B440);
const _line = Color(0xFFE3EAD6);

/// Width of the website's cart panel.
const siteCartRailWidth = 210.0;

/// The website's cart panel on the right (owner request 2026-11-26, like
/// a big online shop's): the subtotal, Go to Cart, and each item with
/// its picture, price and − / + (a bin at one). Shown by the shell only
/// while the cart has something in it.
class SiteCartRail extends StatelessWidget {
  const SiteCartRail({super.key, required this.cart, required this.onOpenCart});

  final CartManager cart;
  final VoidCallback onOpenCart;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        final items = cart.items;
        return Container(
          key: const Key('site-cart-rail'),
          width: siteCartRailWidth,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(left: BorderSide(color: _line)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Column(
                  children: [
                    const Text(
                      'Subtotal',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${cart.subtotal.toStringAsFixed(2)}',
                      key: const Key('site-cart-subtotal'),
                      style: const TextStyle(
                        color: _dark,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${cart.totalQuantity} '
                      '${cart.totalQuantity == 1 ? 'item' : 'items'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('site-cart-go'),
                        onPressed: onOpenCart,
                        style: FilledButton.styleFrom(
                          backgroundColor: _green,
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          'Go to Cart',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _line),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, indent: 14, endIndent: 14),
                  itemBuilder: (context, index) => _item(items[index]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _item(CartItem item) {
    final locked = cart.isCheckoutLocked;
    final one = item.quantity == 1;
    return Padding(
      key: Key('site-cart-item-${item.productId}'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        children: [
          SizedBox(
            height: 96,
            width: double.infinity,
            child: ProductImage(
              productId: item.productId,
              icon: item.product.icon,
              iconSize: 36,
              borderRadius: 10,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${item.product.name} · ${item.product.unit}',
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5),
          ),
          Text(
            '₹${item.totalPrice.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: _green, width: 2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('site-cart-less-${item.productId}'),
                  tooltip: one ? 'Remove' : 'Remove one',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: locked
                      ? null
                      : () => cart.decreaseQuantity(item.productId),
                  icon: Icon(one ? Icons.delete_outline : Icons.remove),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${item.quantity}',
                    key: Key('site-cart-qty-${item.productId}'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  key: Key('site-cart-more-${item.productId}'),
                  tooltip: 'Add one',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed:
                      locked ||
                          item.quantity >=
                              CartManager.maxQuantityOf(item.product)
                      ? null
                      : () => cart.increaseQuantity(item.productId),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
