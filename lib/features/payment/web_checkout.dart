/// Cashfree's pop-up checkout for the website. On phones it is never
/// used (`CashfreePaymentLauncher` takes the SDK's own checkout).
library;

export 'web_checkout_stub.dart'
    if (dart.library.js_interop) 'web_checkout_web.dart';
