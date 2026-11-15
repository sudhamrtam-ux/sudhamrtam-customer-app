import 'package:flutter/material.dart';

import '../../database/order_ref_service.dart';
import '../checkout/order_destination.dart';

/// "Order ORD-1001" when the server gave the order a short number,
/// else the long order ID (test orders, or not known yet).
String orderTitle(String orderId, String? orderRef) =>
    orderRef == null ? 'Order #$orderId' : 'Order $orderRef';

/// The order's title, reading its short number from the phone.
class OrderNumberText extends StatefulWidget {
  const OrderNumberText({
    super.key,
    required this.orderId,
    this.orderRef,
    this.style,
    this.maxLines,
  });

  final String orderId;

  /// Known already (e.g. from the server); skips the lookup.
  final String? orderRef;
  final TextStyle? style;
  final int? maxLines;

  @override
  State<OrderNumberText> createState() => _OrderNumberTextState();
}

class _OrderNumberTextState extends State<OrderNumberText> {
  String? _stored;

  @override
  void initState() {
    super.initState();
    // Only orders sent to the server have a number.
    if (widget.orderRef == null && OrderDestination.sendsToServer) _lookUp();
  }

  Future<void> _lookUp() async {
    try {
      final ref = await OrderRefService.instance.refFor(widget.orderId);
      if (mounted && ref != null) setState(() => _stored = ref);
    } catch (_) {
      // Shown with the long ID.
    }
  }

  @override
  Widget build(BuildContext context) => Text(
    orderTitle(widget.orderId, widget.orderRef ?? _stored),
    key: Key('orderNumber-${widget.orderId}'),
    maxLines: widget.maxLines,
    style: widget.style,
  );
}
