import 'package:flutter/material.dart';

import '../../models/cart_manager.dart';
import '../../models/combo_offer.dart';
import '../../services/catalog_api_client.dart' show apiBaseUrl;
import '../shop/product_image.dart' show productImageProvider;
import '../shop/quantity_bill.dart' show billRupees;
import 'offer_tile.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Cow Ghee, Honey & Curd".
String giftNames(List<String> names) => names.length < 2
    ? names.join()
    : '${names.take(names.length - 1).join(', ')} & ${names.last}';

/// The owner's picture of a combo as an image; null without one (or
/// without a server).
ImageProvider? comboPicture(ComboOffer combo) {
  final path = combo.pictureUrl;
  if (path == null || apiBaseUrl.isEmpty) return null;
  final base = Uri.parse(
    apiBaseUrl.endsWith('/') ? apiBaseUrl : '$apiBaseUrl/',
  );
  return NetworkImage(
    base.resolve(path.startsWith('/') ? path.substring(1) : path).toString(),
  );
}

/// "10% off", "12.5% off".
String offHeadline(int discountBp) {
  final value = discountBp / 100;
  final text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
  return '$text% off';
}

/// Combo offers on Home as big tiles with their gift picture (owner
/// request and decisions 2026-11-26; text offers stay in the offer
/// line). On a
/// computer [perRow] tiles share the row (the owner's choice); a phone
/// shows one (two on a tablet) and the rest swipe. More tiles than fit
/// slide in with the arrows.
class OfferTilesRow extends StatefulWidget {
  const OfferTilesRow({
    super.key,
    required this.combos,
    required this.cart,
    this.perRow = 2,
    this.onOpenCart,
  });

  final List<ComboOffer> combos;
  final int perRow;
  final CartManager cart;
  final VoidCallback? onOpenCart;

  @override
  State<OfferTilesRow> createState() => _OfferTilesRowState();
}

class _OfferTilesRowState extends State<OfferTilesRow> {
  final _scroll = ScrollController();
  static const _gap = 12.0;

  @override
  void dispose() {
    _scroll.dispose();
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

  void _slide(int direction, double step) {
    final target = (_scroll.offset + direction * step).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _comboTile(ComboOffer combo) {
    final inCart = widget.cart.quantityFor(combo.productId);
    final colour = tileColourFor(combo.occasion, combo.tileColour);
    final ends = combo.endsOn;
    return ComboTile(
      key: Key('combo-card-${combo.id}'),
      colour: colour,
      headline: offHeadline(combo.discountBp),
      title: combo.title,
      badge: combo.occasionLabel,
      chips: [
        for (final i in combo.items) '${i.quantity} × ${i.name} ${i.unit}',
      ],
      saving: combo.savingsPaise > 0
          ? 'You save ${billRupees(combo.savingsPaise / 100)}'
          : null,
      picture: comboPicture(combo),
      tag: combo.title,
      items: [
        for (final i in combo.items)
          GiftItem(
            name: i.name,
            quantity: i.quantity,
            pricePaise: i.unitPricePaise,
            image: productImageProvider(i.productId),
          ),
      ],
      price: billRupees(combo.pricePaise / 100),
      priceKey: Key('combo-price-${combo.id}'),
      fullPrice: billRupees(combo.fullPaise / 100),
      footnote: 'Ends ${ends.day} ${_months[ends.month - 1]}',
      action: inCart == 0
          ? FilledButton.icon(
              key: Key('combo-add-${combo.id}'),
              onPressed: () => _add(combo),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: colour,
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: const Text(
                'Add',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : _InCartStepper(
              key: Key('combo-stepper-${combo.id}'),
              quantity: inCart,
              colour: colour,
              onMinus: () => widget.cart.decreaseQuantity(combo.productId),
              onPlus: inCart < combo.maxPerOrder ? () => _add(combo) : null,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[for (final c in widget.combos) _comboTile(c)];
    if (tiles.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      key: const Key('combo-cards'),
      builder: (context, box) {
        final w = box.maxWidth;
        final computer = w >= 900;
        final visible = computer
            ? widget.perRow.clamp(1, 4)
            : (w >= 600 ? 2 : 1);
        // Fewer tiles than places: they share the row between them.
        final across = tiles.length < visible ? tiles.length : visible;
        var tileWidth = (w - _gap * (across - 1)) / across;
        // On a phone the next tile peeks in, so it is clear they swipe.
        if (!computer && w < 600 && tiles.length > 1) tileWidth = w * 0.84;
        final height = computer ? (across <= 2 ? 330.0 : 420.0) : 430.0;
        final overflow = tiles.length > visible;

        final list = SizedBox(
          height: height,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: tiles.length > 1
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: tiles.length,
            separatorBuilder: (_, _) => const SizedBox(width: _gap),
            itemBuilder: (_, i) => SizedBox(width: tileWidth, child: tiles[i]),
          ),
        );
        if (!computer || !overflow) return list;
        // More than fit: arrows at the sides, as on big shop sites.
        return Stack(
          alignment: Alignment.center,
          children: [
            list,
            Positioned(
              left: 4,
              child: _Arrow(
                key: const Key('offer-tiles-back'),
                icon: Icons.chevron_left,
                onTap: () => _slide(-1, tileWidth + _gap),
              ),
            ),
            Positioned(
              right: 4,
              child: _Arrow(
                key: const Key('offer-tiles-next'),
                icon: Icons.chevron_right,
                onTap: () => _slide(1, tileWidth + _gap),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.95),
    elevation: 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 64,
        child: Icon(icon, size: 30, color: const Color(0xFF2B2B2B)),
      ),
    ),
  );
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
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.remove, onMinus, 'combo-minus'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
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
