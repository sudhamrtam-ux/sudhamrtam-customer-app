import 'package:flutter/material.dart';

/// "₹1,250.00"
String billRupees(double amount) {
  final fixed = amount.toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  var whole = fixed.substring(0, dot);
  // Indian grouping: 1,25,000.00
  if (whole.length > 3) {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    whole = '${parts.join(',')},$last3';
  }
  return '₹$whole${fixed.substring(dot)}';
}

/// The quantity stepper with the bill next to it (owner request
/// 2026-11-15): price × quantity = amount before adding to the cart,
/// and what the cart will hold when this product is already in it.
class QuantityBill extends StatelessWidget {
  const QuantityBill({
    super.key,
    required this.quantity,
    required this.unitPrice,
    required this.unit,
    required this.inCart,
    required this.maxQuantity,
    required this.onChanged,
  });

  final int quantity;

  /// 0 or less: no price yet, so no bill.
  final double unitPrice;
  final String unit;

  /// How many are already in the cart.
  final int inCart;
  final int maxQuantity;
  final ValueChanged<int> onChanged;

  static const _green = Color(0xFF82B440);
  static const _deep = Color(0xFF4E7A1E);
  static const _line = Color(0xFFDDE8CC);

  @override
  Widget build(BuildContext context) {
    final hasPrice = unitPrice > 0;
    final amount = unitPrice * quantity;
    final after = (inCart + quantity).clamp(0, maxQuantity);
    final capped = inCart + quantity > maxQuantity;
    final small = TextStyle(
      color: Colors.black.withValues(alpha: 0.6),
      fontSize: 13.5,
    );

    return Container(
      key: const Key('quantity-bill'),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7FAF2), Color(0xFFEDF5E1)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Stepper(
                quantity: quantity,
                onMinus: quantity > 1 ? () => onChanged(quantity - 1) : null,
                onPlus: quantity < maxQuantity
                    ? () => onChanged(quantity + 1)
                    : null,
              ),
              const Spacer(),
              if (hasPrice)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Amount', style: small),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween(begin: 0.9, end: 1.0).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        billRupees(amount),
                        key: ValueKey(amount),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: _deep,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (hasPrice) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: _line),
            const SizedBox(height: 10),
            _BillRow(
              key: const Key('quantity-bill-line'),
              label:
                  '${billRupees(unitPrice)} × $quantity '
                  '${quantity == 1 ? 'pack' : 'packs'} ($unit)',
              value: billRupees(amount),
              style: small,
            ),
            if (inCart > 0) ...[
              const SizedBox(height: 6),
              _BillRow(
                label: 'Already in your cart: $inCart',
                value: billRupees(unitPrice * inCart),
                style: small,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _BillRow(
                  key: const Key('cart-after'),
                  label: 'Your cart will have $after',
                  value: billRupees(unitPrice * after),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _deep,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
            if (capped) ...[
              const SizedBox(height: 8),
              Text(
                'At most $maxQuantity of one product can be in the cart.',
                style: const TextStyle(
                  color: Color(0xFFB26A00),
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({
    super.key,
    required this.label,
    required this.value,
    required this.style,
  });

  final String label;
  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, style: style)),
      const SizedBox(width: 8),
      Text(value, style: style.copyWith(fontWeight: FontWeight.w700)),
    ],
  );
}

/// A rounded white − quantity + pill.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.onMinus,
    required this.onPlus,
  });

  final int quantity;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, VoidCallback? onPressed, String key) =>
        Material(
          color: onPressed == null
              ? const Color(0xFFEFF2EA)
              : QuantityBill._green,
          shape: const CircleBorder(),
          child: InkWell(
            key: Key(key),
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                icon,
                size: 20,
                color: onPressed == null ? Colors.black26 : Colors.white,
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: QuantityBill._deep.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.remove, onMinus, 'qty-minus'),
          SizedBox(
            width: 44,
            child: Text(
              '$quantity',
              key: const Key('qty-value'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          button(Icons.add, onPlus, 'qty-plus'),
        ],
      ),
    );
  }
}
