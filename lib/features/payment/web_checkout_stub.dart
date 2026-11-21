import '../../services/order_api_client.dart';
import 'payment_launcher.dart';

/// Phones: never called.
Future<PaymentLaunchResult> launchWebCheckout(PaymentSession session) =>
    throw UnsupportedError('The web checkout runs only on the website.');
