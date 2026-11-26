import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/milk_bills/bill_pdf.dart';
import 'package:sudhamrtam_customer_app/features/orders/order_details_screen.dart';
import 'package:sudhamrtam_customer_app/features/orders/order_receipt_pdf.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

/// The order receipt PDF (owner request 2026-11-26).
void main() {
  CustomerOrder order() => CustomerOrder(
    id: 'a' * 32,
    createdAt: DateTime(2026, 11, 26, 7, 9),
    deliveryDate: '2026-11-27',
    items: const [
      OrderItem(
        productId: 'curd',
        productName: 'Curd',
        unit: '500 g',
        quantity: 2,
        unitPrice: 60,
      ),
      OrderItem(
        productId: 'ghee',
        productName: 'Cow Ghee',
        unit: '250 g',
        quantity: 1,
        unitPrice: 250,
      ),
    ],
    fulfillmentMethod: FulfillmentMethod.delivery,
    paymentMethod: OrderPaymentMethod.cashOnDelivery,
    deliveryAddress: 'Flat 101, Green Towers, Hyderabad (sample)',
    recipientName: 'Asha (sample)',
    recipientPhone: '9876543210',
    billingAddressId: 'office',
    billingName: 'Asha Enterprises (sample)',
    billingPhone: '9876543210',
    billingAddress: 'Plot 7, Industrial Estate, Hyderabad (sample)',
  );

  test('builds an A4 PDF', () async {
    final bytes = await buildOrderReceiptPdf(
      order(),
      orderRef: 'SUD0000027',
      payment: 'Cash on Delivery',
      status: 'Delivery pending',
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // A copy to look at when ZZ_RECEIPT is set.
    final out = Platform.environment['ZZ_RECEIPT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });

  testWidgets('Order Details: Receipt makes and shares the PDF', (
    tester,
  ) async {
    final shared = <String>[];
    final original = outputBillPdf;
    outputBillPdf =
        (Uint8List bytes, String name, {required bool share}) async {
          expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
          shared.add('$name share=$share');
        };
    addTearDown(() => outputBillPdf = original);

    await tester.pumpWidget(
      MaterialApp(home: OrderDetailsScreen(order: order())),
    );
    await tester.tap(find.byKey(const Key('order-receipt')));
    for (var i = 0; i < 20 && shared.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(shared, ['Sudhamrtam receipt ${'a' * 32} share=true']);
  });
}
