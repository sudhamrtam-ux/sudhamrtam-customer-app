// Runs in a browser only:
//   flutter test --platform chrome test/web/web_checkout_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/payment/payment_launcher.dart';
import 'package:sudhamrtam_customer_app/features/payment/web_checkout_web.dart';
import 'package:sudhamrtam_customer_app/services/order_api_client.dart';

/// A stand-in for Cashfree.js v3 on the page: records what it was
/// given and resolves checkout() with [result].
class FakeCashfree {
  FakeCashfree(Map<String, Object?>? result) {
    final checkout = ((JSAny? options) {
      checkoutOptions = (options as JSObject?)?.dartify() as Map?;
      return Future<JSAny?>.value(result?.jsify()).toJS;
    }).toJS;
    globalContext['Cashfree'] = ((JSAny? config) {
      initOptions = (config as JSObject?)?.dartify() as Map?;
      final instance = JSObject();
      instance['checkout'] = checkout;
      return instance;
    }).toJS;
  }

  Map? initOptions;
  Map? checkoutOptions;
}

const sandbox = PaymentSession(
  orderId: 'order_1',
  paymentSessionId: 'session_abc',
  environment: 'sandbox',
);

void main() {
  tearDown(() => globalContext.delete('Cashfree'.toJS));

  test('opens the pop-up checkout with the session', () async {
    final fake = FakeCashfree({
      'paymentDetails': {'paymentMessage': 'Payment finished'},
    });
    final result = await launchWebCheckout(sandbox);
    expect(result, isA<PaymentLaunchFinished>());
    expect(fake.initOptions, {'mode': 'sandbox'});
    expect(fake.checkoutOptions, {
      'paymentSessionId': 'session_abc',
      'redirectTarget': '_modal',
    });
  });

  test('production sessions use production mode', () async {
    final fake = FakeCashfree({'paymentDetails': {}});
    await launchWebCheckout(
      const PaymentSession(
        orderId: 'o',
        paymentSessionId: 's',
        environment: 'production',
      ),
    );
    expect(fake.initOptions, {'mode': 'production'});
  });

  test('closing the pop-up is not a payment', () async {
    FakeCashfree({
      'error': {'message': 'Popup closed by user'},
    });
    final result = await launchWebCheckout(sandbox);
    expect(result, isA<PaymentLaunchFailed>());
    expect((result as PaymentLaunchFailed).message, 'Popup closed by user');
  });

  test('an in-app browser redirect is checked with the server', () async {
    FakeCashfree({'redirect': true});
    expect(await launchWebCheckout(sandbox), isA<PaymentLaunchFinished>());
  });

  test('no answer at all is not a payment', () async {
    FakeCashfree(null);
    final result = await launchWebCheckout(sandbox);
    expect(result, isA<PaymentLaunchFailed>());
    expect(
      (result as PaymentLaunchFailed).message,
      'The payment was not completed.',
    );
  });

  test('the launcher uses the pop-up on the website', () async {
    final fake = FakeCashfree({'paymentDetails': {}});
    final result = await CashfreePaymentLauncher().launch(sandbox);
    expect(result, isA<PaymentLaunchFinished>());
    expect(fake.checkoutOptions?['redirectTarget'], '_modal');
  });
}
