import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/checkout/checkout_fault_injector.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

CustomerOrder testOrder() {
  return CustomerOrder(
    id: 'fault-order',
    createdAt: DateTime.utc(2026, 11, 6),
    items: const [
      OrderItem(
        productId: 'cow_milk',
        productName: 'Cow Milk',
        unit: '1 L',
        quantity: 1,
        unitPrice: 85,
      ),
    ],
    fulfillmentMethod: FulfillmentMethod.pickup,
    paymentMethod: OrderPaymentMethod.cashOnDelivery,
  );
}

void main() {
  late List<String> calls;
  late CheckoutFaultInjector injector;
  late CartManager cart;

  setUp(() {
    calls = [];
    cart = CartManager();
    injector = CheckoutFaultInjector(
      prepareCheckout: (order) async => calls.add('prepare:${order.id}'),
      refreshCart: (_) async => calls.add('refresh'),
    );
  });

  tearDown(() => cart.dispose());

  test('No fault passes both stages through unchanged', () async {
    await injector.prepareCheckout(testOrder());
    await injector.refreshCart(cart);

    expect(calls, ['prepare:fault-order', 'refresh']);
  });

  test(
    'After-preparation fault runs real preparation, then fails once',
    () async {
      injector.armed = CheckoutFault.afterPreparation;

      await expectLater(
        injector.prepareCheckout(testOrder()),
        throwsStateError,
      );

      // Preparation itself ran, as it would before a crash.
      expect(calls, ['prepare:fault-order']);
      expect(injector.armed, CheckoutFault.none);

      // A retry behaves normally.
      await injector.prepareCheckout(testOrder());
      expect(calls, ['prepare:fault-order', 'prepare:fault-order']);
    },
  );

  test('After-save fault skips the cart refresh once', () async {
    injector.armed = CheckoutFault.afterOrderSaved;

    // Preparation is not affected by this fault.
    await injector.prepareCheckout(testOrder());

    await expectLater(injector.refreshCart(cart), throwsStateError);
    expect(calls, ['prepare:fault-order']);
    expect(injector.armed, CheckoutFault.none);

    await injector.refreshCart(cart);
    expect(calls, ['prepare:fault-order', 'refresh']);
  });
}
