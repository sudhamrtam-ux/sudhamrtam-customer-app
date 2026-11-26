import 'package:flutter/material.dart';

import '../../models/cart_manager.dart';
import '../../models/combo_offer.dart';
import '../shop/quantity_bill.dart' show billRupees;

/// Soft colours per occasion: background gradient and ribbon.
({List<Color> background, Color ribbon}) comboColours(String occasion) =>
    switch (occasion) {
      'festive' => (
        background: const [Color(0xFFFFF1E6), Color(0xFFFFE4EC)],
        ribbon: const Color(0xFFD14A6E),
      ),
      'inaugural' => (
        background: const [Color(0xFFF4EBFF), Color(0xFFE9F0FF)],
        ribbon: const Color(0xFF7B4FC9),
      ),
      'seasonal' => (
        background: const [Color(0xFFEAF8EE), Color(0xFFF3FBE4)],
        ribbon: const Color(0xFF5E9A2E),
      ),
      'month_end' => (
        background: const [Color(0xFFE6F4FF), Color(0xFFEEF0FF)],
        ribbon: const Color(0xFF3F7CC4),
      ),
      'year_end' => (
        background: const [Color(0xFFFFF8E1), Color(0xFFFFEFD6)],
        ribbon: const Color(0xFFC98A12),
      ),
      _ => (
        background: const [Color(0xFFF5F8F0), Color(0xFFEAF3DD)],
        ribbon: const Color(0xFF82B440),
      ),
    };

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Combo offers on Home: swipe cards under the offer line.
class ComboCards extends StatefulWidget {
  const ComboCards({
    super.key,
    required this.combos,
    required this.cart,
    this.onOpenCart,
  });

  final List<ComboOffer> combos;
  final CartManager cart;
  final VoidCallback? onOpenCart;

  @override
  State<ComboCards> createState() => _ComboCardsState();
}

class _ComboCardsState extends State<ComboCards> {
  /// One combo: the full width, lined up with the banner and the row
  /// below (owner request 2026-11-26); more: the next one peeks in.
  late final _pages = PageController(
    viewportFraction: widget.combos.length == 1 ? 1 : 0.92,
  );
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _add(ComboOffer combo) {
    final added = widget.cart.addProduct(combo.toProduct());
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added
              ? '${combo.title} added to cart'
              : widget.cart.quantityFor(combo.productId) >= combo.maxPerOrder
              ? 'At most ${combo.maxPerOrder} of this combo per order.'
              : 'The cart cannot be changed right now.',
        ),
        duration: const Duration(seconds: 2),
        action: added && widget.onOpenCart != null
            ? SnackBarAction(label: 'VIEW CART', onPressed: widget.onOpenCart!)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final combos = widget.combos;
    if (combos.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('combo-cards'),
      children: [
        SizedBox(
          // Shorter on a wide screen, where the lines do not wrap.
          height: MediaQuery.sizeOf(context).width >= 900 ? 248 : 272,
          child: PageView.builder(
            controller: _pages,
            itemCount: combos.length,
            padEnds: combos.length == 1,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => Padding(
              padding: EdgeInsets.symmetric(
                horizontal: combos.length == 1 ? 0 : 6,
                vertical: 6,
              ),
              child: _ComboCard(
                combo: combos[i],
                inCart: widget.cart.quantityFor(combos[i].productId),
                onAdd: () => _add(combos[i]),
                onRemoveOne: () =>
                    widget.cart.decreaseQuantity(combos[i].productId),
              ),
            ),
          ),
        ),
        if (combos.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < combos.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 4,
                  ),
                  width: i == _page ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? comboColours(combos[i].occasion).ribbon
                        : Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _ComboCard extends StatelessWidget {
  const _ComboCard({
    required this.combo,
    required this.inCart,
    required this.onAdd,
    required this.onRemoveOne,
  });

  final ComboOffer combo;
  final int inCart;
  final VoidCallback onAdd;
  final VoidCallback onRemoveOne;

  @override
  Widget build(BuildContext context) {
    final colours = comboColours(combo.occasion);
    final ribbon = colours.ribbon;
    final shown = combo.items.take(3).toList();
    final more = combo.items.length - shown.length;
    final ends = combo.endsOn;

    return Container(
      key: Key('combo-card-${combo.id}'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: ribbon.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Banner(
          message: combo.discountLabel,
          location: BannerLocation.topEnd,
          color: ribbon,
          textStyle: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colours.background,
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The ribbon across, with the occasion.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: ribbon,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.redeem,
                              size: 15,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              combo.occasionLabel.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(right: 40),
                        child: Text(
                          combo.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2F2A26),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final item in shown)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '•  ${item.quantity} × ${item.name} (${item.unit})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: Color(0xFF4A4540),
                            ),
                          ),
                        ),
                      if (more > 0)
                        Text(
                          '+ $more more',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: ribbon,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            // Shrinks on a narrow phone instead of
                            // wrapping out of the card.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.bottomLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    billRupees(combo.fullPaise / 100),
                                    style: const TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                      color: Colors.black45,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    billRupees(combo.pricePaise / 100),
                                    key: Key('combo-price-${combo.id}'),
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF2F2A26),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE3F1D3),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'You save ${billRupees(combo.savingsPaise / 100)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF3F6B17),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Ends ${ends.day} ${_months[ends.month - 1]}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (inCart == 0)
                                FilledButton.icon(
                                  key: Key('combo-add-${combo.id}'),
                                  onPressed: onAdd,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: ribbon,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.add_shopping_cart,
                                    size: 18,
                                  ),
                                  label: const Text('Add to cart'),
                                )
                              else
                                _InCartStepper(
                                  key: Key('combo-stepper-${combo.id}'),
                                  quantity: inCart,
                                  colour: ribbon,
                                  onMinus: onRemoveOne,
                                  onPlus: inCart < combo.maxPerOrder
                                      ? onAdd
                                      : null,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InCartStepper extends StatelessWidget {
  const _InCartStepper({
    super.key,
    required this.quantity,
    required this.colour,
    required this.onMinus,
    required this.onPlus,
  });

  final int quantity;
  final Color colour;
  final VoidCallback onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, VoidCallback? onTap, String key) => InkWell(
      key: Key(key),
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 20,
          color: onTap == null ? Colors.black26 : colour,
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.remove, onMinus, 'combo-minus'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$quantity in cart',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          button(Icons.add, onPlus, 'combo-plus'),
        ],
      ),
    );
  }
}
