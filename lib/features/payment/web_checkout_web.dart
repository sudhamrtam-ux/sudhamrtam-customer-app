import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../../services/order_api_client.dart';
import 'payment_launcher.dart';

/// Cashfree.js v3 (https://www.cashfree.com/docs/payments/online/web/redirect).
const _sdkUrl = 'https://sdk.cashfree.com/js/v3/cashfree.js';

Future<void>? _sdk;

/// Adds Cashfree.js to the page once; a failed load is tried again
/// next time.
Future<void> _loadSdk() {
  if (globalContext.has('Cashfree')) return Future.value();
  return _sdk ??= () {
    final loaded = Completer<void>();
    final document = globalContext['document'] as JSObject;
    final script = document.callMethod<JSObject>(
      'createElement'.toJS,
      'script'.toJS,
    );
    script['src'] = _sdkUrl.toJS;
    script['onload'] = ((JSAny? _) {
      if (!loaded.isCompleted) loaded.complete();
    }).toJS;
    script['onerror'] = ((JSAny? _) {
      _sdk = null;
      if (!loaded.isCompleted) {
        loaded.completeError(StateError('Cashfree could not be reached.'));
      }
    }).toJS;
    (document['head'] as JSObject).callMethod<JSAny?>(
      'appendChild'.toJS,
      script,
    );
    return loaded.future;
  }();
}

/// The website: Cashfree's checkout opens as a pop-up over the page
/// (`redirectTarget: "_modal"`), so the website stays open and gets
/// the result. Whatever it says, only the server's check decides
/// whether the order or bill is paid.
Future<PaymentLaunchResult> launchWebCheckout(PaymentSession session) async {
  try {
    await _loadSdk();
    final cashfree = globalContext.callMethod<JSObject>(
      'Cashfree'.toJS,
      {'mode': session.isSandbox ? 'sandbox' : 'production'}.jsify(),
    );
    final result = await cashfree
        .callMethod<JSPromise<JSObject?>>(
          'checkout'.toJS,
          {
            'paymentSessionId': session.paymentSessionId,
            'redirectTarget': '_modal',
          }.jsify(),
        )
        .toDart;

    // Payment finished, paid or not: the server's check tells which.
    if (result != null && _isSet(result['paymentDetails'])) {
      return const PaymentLaunchFinished();
    }
    // Only in in-app browsers: Cashfree continues on its own page;
    // the check shows the result when the customer comes back.
    if (result != null && _isSet(result['redirect'])) {
      return const PaymentLaunchFinished();
    }
    // The customer closed the pop-up, or the payment failed.
    final error = result?['error'];
    final message = error != null && error.isA<JSObject>()
        ? (error as JSObject)['message']
        : null;
    return PaymentLaunchFailed(
      message != null && message.isA<JSString>()
          ? (message as JSString).toDart
          : 'The payment was not completed.',
    );
  } catch (error) {
    return PaymentLaunchFailed('The payment screen could not open: $error');
  }
}

bool _isSet(JSAny? value) =>
    value != null && !(value.isA<JSBoolean>() && !(value as JSBoolean).toDart);
