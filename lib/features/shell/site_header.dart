import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../core/widgets/site_layout.dart';
import '../account/customer_name.dart';
import '../messages/messages_screen.dart';
import '../shop/product_image.dart';

/// The website's header: the brand, the main pages, messages, account
/// and the cart with its count and total.
class SiteHeader extends StatelessWidget {
  const SiteHeader({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  /// The page shown (0 Home, 1 Shop, 2 Milk Plans, 3 Cart, 4 Account);
  /// null on a page opened from one of them.
  final int? selectedIndex;
  final ValueChanged<int> onSelect;

  static const _dark = Color(0xFF2F4A14);
  static const _green = Color(0xFF82B440);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final side = ((width - siteContentWidth) / 2).clamp(32.0, double.infinity);

    Widget link(String label, int index) {
      final selected = selectedIndex == index;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextButton(
          key: Key('site-nav-$index'),
          onPressed: () => onSelect(index),
          style: TextButton.styleFrom(
            foregroundColor: selected ? _dark : Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            shape: const RoundedRectangleBorder(),
          ),
          child: Container(
            padding: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? _green : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.white,
      child: Container(
        height: 72,
        padding: EdgeInsets.symmetric(horizontal: side),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE3EAD6))),
        ),
        child: Row(
          children: [
            InkWell(
              key: const Key('site-brand'),
              onTap: () => onSelect(0),
              child: Row(
                children: [
                  ClipOval(
                    child: Image.asset(
                      sudhamrtamLogoAsset,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sudhamrtam',
                        style: TextStyle(
                          color: _dark,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Pure by Nature',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 40),
            link('Home', 0),
            link('Shop', 1),
            link('Subscriptions', 2),
            const Spacer(),
            const MessagesBell(),
            const SizedBox(width: 4),
            // The customer's name when signed in (owner, 2026-11-24).
            SignedInName(
              builder: (context, user, name) => TextButton.icon(
                key: const Key('site-account'),
                onPressed: () => onSelect(4),
                style: TextButton.styleFrom(
                  foregroundColor: selectedIndex == 4 ? _dark : Colors.black87,
                ),
                icon: const Icon(Icons.person_outline),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    user != null && name != null ? name : 'Account',
                    key: const Key('site-account-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ListenableBuilder(
              listenable: sudhamrtamCart,
              builder: (context, _) {
                final count = sudhamrtamCart.totalQuantity;
                return FilledButton.icon(
                  key: const Key('site-cart'),
                  onPressed: () => onSelect(3),
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                  icon: Badge(
                    isLabelVisible: count > 0,
                    backgroundColor: _dark,
                    label: Text(count > 99 ? '99+' : '$count'),
                    child: const Icon(Icons.shopping_cart_outlined),
                  ),
                  label: Text(
                    count == 0
                        ? 'Cart'
                        : 'Cart · ₹${sudhamrtamCart.subtotal.toStringAsFixed(0)}',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
