import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/api/cftheme/cftheme.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';

import '../../services/order_api_client.dart';
import 'web_checkout.dart';

/// How the payment screen closed. This is never proof of payment:
/// only the server's check (with Cashfree) decides that.
sealed class PaymentLaunchResult {
  const PaymentLaunchResult();
}

/// The payment screen reported success; verify with the server.
class PaymentLaunchFinished extends PaymentLaunchResult {
  const PaymentLaunchFinished();
}

/// The payment failed or the customer closed the screen.
class PaymentLaunchFailed extends PaymentLaunchResult {
  final String message;
  const PaymentLaunchFailed(this.message);
}

/// Opens a payment provider's payment screen.
abstract class PaymentLauncher {
  Future<PaymentLaunchResult> launch(PaymentSession session);
}

/// Cashfree's web checkout (UPI apps, cards, net banking). On the
/// website: Cashfree's pop-up checkout over the page (the SDK's own
/// web checkout would leave the website).
class CashfreePaymentLauncher implements PaymentLauncher {
  @override
  Future<PaymentLaunchResult> launch(PaymentSession session) {
    if (kIsWeb) return launchWebCheckout(session);
    if (!onlinePaymentWorksHere) {
      // The Windows app has no Cashfree checkout.
      return Future.value(
        const PaymentLaunchFailed(
          'Online payment works in the Sudhamrtam phone app and on '
          'sudhamrtam.in. Please pay there, or pay the staff in cash.',
        ),
      );
    }
    final completer = Completer<PaymentLaunchResult>();

    try {
      final cfSession = CFSessionBuilder()
          .setEnvironment(
            session.isSandbox
                ? CFEnvironment.SANDBOX
                : CFEnvironment.PRODUCTION,
          )
          .setOrderId(session.orderId)
          .setPaymentSessionId(session.paymentSessionId)
          .build();

      final theme = CFThemeBuilder()
          .setNavigationBarBackgroundColorColor('#82B440')
          .setNavigationBarTextColor('#FFFFFF')
          .setButtonBackgroundColor('#82B440')
          .build();

      final payment = CFWebCheckoutPaymentBuilder()
          .setSession(cfSession)
          .setTheme(theme)
          .build();

      final gateway = CFPaymentGatewayService();
      gateway.setCallback(
        (String orderId) {
          if (!completer.isCompleted) {
            completer.complete(const PaymentLaunchFinished());
          }
        },
        (CFErrorResponse error, String orderId) {
          if (!completer.isCompleted) {
            completer.complete(
              PaymentLaunchFailed(
                error.getMessage() ?? 'The payment was not completed.',
              ),
            );
          }
        },
      );
      gateway.doPayment(payment);
    } catch (error) {
      if (!completer.isCompleted) {
        completer.complete(
          PaymentLaunchFailed('The payment screen could not open: $error'),
        );
      }
    }

    return completer.future;
  }
}
