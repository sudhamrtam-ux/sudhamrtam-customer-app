import '../../database/order_database_service.dart';
import '../../models/customer_order.dart';
import '../../services/order_api_client.dart';

/// Where placed orders go. Configured once by main().
///
/// - With a [server]: the order is sent to Sudhamrtam first
///   (`PUT /v1/orders/{id}`, safe to repeat), and only once the
///   server has accepted it is it saved on the phone.
/// - Without one (debug builds with no API_BASE_URL): the order
///   is a test order saved on the phone only.
///
/// The durable checkout pipeline is unchanged: it calls [save]
/// through OrderSubmissionService and reuses the same order ID on
/// every retry, so the server can never receive two orders.
class OrderDestination {
  OrderDestination._();

  static OrderApiClient? server;

  static bool get sendsToServer => server != null;

  /// Saves [order] wherever orders go (see the class comment).
  static Future<void> save(CustomerOrder order) async {
    final api = server;
    if (api != null) await api.placeOrder(order);
    await OrderDatabaseService.instance.saveOrder(order);
  }

  /// Whether an unfinished order may be discarded: true only when
  /// it certainly did not reach the server. Throws
  /// [OrderApiException] when the server cannot be asked.
  static Future<bool> canDiscard(String orderId) async {
    final api = server;
    if (api == null) return true;
    return !(await api.orderExists(orderId));
  }
}
