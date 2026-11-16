import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../database/customer_address_database_service.dart';
import '../../database/pending_order_submission_service.dart';
import '../../models/customer_address.dart';
import '../../models/combo_offer.dart';
import '../../models/customer_order.dart';
import '../../services/order_api_client.dart';
import '../../services/phone_auth_service.dart';
import '../account/address_form_screen.dart';
import '../account/phone_login_screen.dart';
import '../orders/order_details_screen.dart';
import '../payment/payment_screen.dart';
import 'checkout_fault_injector.dart';
import 'checkout_order_session.dart';
import 'checkout_validator.dart';
import 'durable_checkout_coordinator.dart';
import 'order_destination.dart';
import 'order_preparation_service.dart';
import '../../core/widgets/page_app_bar.dart';

const _brandGreen = Color(0xFF82B440);

class CheckoutScreen extends StatefulWidget {
  CheckoutScreen({
    super.key,
    this.enableTestOrders = kDebugMode,
    bool? sendsToServer,
    this.coordinator,
    this.orderSession,
    PhoneAuthGateway? auth,
    Future<OrderRules> Function()? loadRules,
  }) : sendsToServer = sendsToServer ?? OrderDestination.sendsToServer,
       auth = auth ?? sudhamrtamAuth,
       loadRules = loadRules ?? OrderDestination.server?.fetchRules;

  /// Without a server, local test orders are allowed only in
  /// debug builds. They are saved on this phone only, are not
  /// sent to Sudhamrtam, and no payment is taken.
  final bool enableTestOrders;

  /// Orders go to the Sudhamrtam server (see OrderDestination).
  /// Then ordering is enabled in every build, for signed-in
  /// customers, with home delivery and Cash on Delivery only.
  final bool sendsToServer;

  final PhoneAuthGateway? auth;

  /// Loads the owner's order rules (minimum order, cut-off).
  final Future<OrderRules> Function()? loadRules;

  /// Optional overrides for deterministic testing.
  final DurableCheckoutCoordinator? coordinator;
  final CheckoutOrderSession? orderSession;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  static const String _customerId = 'local_customer';
  static const int _maxInstructionLength = 250;

  final _addressService = CustomerAddressDatabaseService.instance;

  final TextEditingController _deliveryInstructionsController =
      TextEditingController();

  FulfillmentMethod _fulfillmentMethod = FulfillmentMethod.delivery;

  OrderPaymentMethod _paymentMethod = OrderPaymentMethod.cashOnDelivery;

  List<CustomerAddress> _savedAddresses = [];
  String? _selectedAddressId;
  bool _addressesLoading = true;
  String? _addressError;

  /// Debug-only failure simulation for device recovery tests.
  final CheckoutFaultInjector _faultInjector = CheckoutFaultInjector();

  bool get _showFaultSimulation => kDebugMode && widget.enableTestOrders;

  late final DurableCheckoutCoordinator _coordinator =
      widget.coordinator ??
      (kDebugMode
          ? DurableCheckoutCoordinator(
              prepareCheckout: _faultInjector.prepareCheckout,
              refreshCart: _faultInjector.refreshCart,
            )
          : DurableCheckoutCoordinator());

  late final CheckoutOrderSession _orderSession =
      widget.orderSession ?? CheckoutOrderSession();

  bool _isSubmitting = false;
  String? _submissionError;

  /// Set when the server refused the order: retrying the same
  /// order cannot work, so the customer may cancel it instead.
  OrderRejectedException? _rejection;

  OrderRules? _rules;

  /// The delivery date the customer chose (owner decision
  /// 2026-11-15); null: the earliest.
  DateTime? _chosenDate;

  bool get _serverMode => widget.sendsToServer;

  bool get _ordersEnabled => _serverMode || widget.enableTestOrders;

  bool get _signedIn => widget.auth?.currentUser != null;

  /// The server takes online payments (Cashfree).
  bool get _onlineOffered =>
      _serverMode && (_rules?.offersOnlinePayment ?? false);

  /// An online order would be placed and paid on the next screen.
  bool get _paysOnline =>
      _paymentMethod == OrderPaymentMethod.online && _onlineOffered;

  CustomerAddress? get _selectedAddress {
    for (final address in _savedAddresses) {
      if (address.id == _selectedAddressId) {
        return address;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadSavedAddresses();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final load = widget.loadRules;
    if (load == null) return;
    try {
      final rules = await load();
      if (mounted) setState(() => _rules = rules);
    } catch (_) {
      // Offline: the server still checks the rules.
    }
  }

  Future<void> _signIn() async {
    final auth = widget.auth;
    if (auth == null) return;

    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => PhoneLoginScreen(auth: auth)),
    );

    if (!mounted) return;
    setState(() {});
    // Signing in replaces the phone's addresses with the account's.
    await sudhamrtamAccount.syncNow();
    if (mounted) await _loadSavedAddresses();
  }

  Future<void> _editAddress(CustomerAddress address) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => AddressFormScreen(existingAddress: address),
      ),
    );
    if (mounted) await _loadSavedAddresses();
  }

  /// Things the customer must fix before a server order can be
  /// placed, each with an optional action.
  List<({String message, String? action, VoidCallback? onAction})>
  _serverRequirements(CustomerAddress? address) {
    if (!_serverMode) return const [];

    final rules = _rules;
    final subtotal = sudhamrtamCart.subtotal;

    return [
      if (!_signedIn)
        (
          message: 'Sign in with your mobile number to place your order.',
          action: 'Sign in',
          onAction: _signIn,
        ),
      if (address != null && address.areaId == null)
        (
          message:
              'Choose the delivery area for this address so we know '
              'which route delivers to you.',
          action: 'Edit address',
          onAction: () => _editAddress(address),
        ),
      // Every address needs its spot on the map (owner decision
      // 2026-11-16), so the delivery partner can navigate there.
      if (address != null && !address.hasMapLocation)
        (
          message:
              'Mark this address on the map so our delivery partner '
              'can reach you.',
          action: 'Add location',
          onAction: () => _editAddress(address),
        ),
      if (rules != null && subtotal < rules.minimumOrderRupees)
        (
          message:
              'The minimum order for delivery is '
              '₹${rules.minimumOrderRupees.toStringAsFixed(0)}. '
              'Add ₹${(rules.minimumOrderRupees - subtotal).toStringAsFixed(2)} '
              'more to place your order.',
          action: null,
          onAction: null,
        ),
    ];
  }

  Widget _serverRequirementsCard(
    List<({String message, String? action, VoidCallback? onAction})> items,
  ) {
    return Container(
      key: const Key('serverRequirements'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD8A8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items) ...[
            Text(
              item.message,
              style: const TextStyle(fontSize: 13, color: Color(0xFF8A5200)),
            ),
            if (item.action != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _isSubmitting ? null : item.onAction,
                  child: Text(item.action!),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  /// Cancels an order the server refused, keeping the cart, so
  /// the customer can review it and check out again.
  Future<void> _cancelRejectedOrder() async {
    final order = _orderSession.currentOrder;
    final rejection = _rejection;
    if (order == null || rejection == null || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      if (!await OrderDestination.canDiscard(order.id)) {
        if (!mounted) return;
        setState(() {
          _rejection = null;
          _submissionError =
              'Sudhamrtam already has this order. Tap Retry Order to '
              'finish it.';
        });
        return;
      }

      final cancelled = await PendingOrderSubmissionService.instance
          .cancelUnsavedSubmission(order.id);

      if (!cancelled) {
        if (!mounted) return;
        setState(() {
          _submissionError =
              'The order could not be cancelled because its state '
              'changed. Please tap Retry Order.';
          _rejection = null;
        });
        return;
      }

      _orderSession.markCompleted(order.id);
      sudhamrtamCart.endCheckoutRecoveryLock();

      // New prices reach the cart through the catalog.
      if (rejection.isPriceChange) await sudhamrtamCatalog.refresh();

      // A combo that ended comes out of the cart; one whose price
      // changed stays, at its new price.
      if (rejection.isComboChange) {
        await sudhamrtamCombos.refresh();
        sudhamrtamCart.refreshProducts();
        for (final item in sudhamrtamCart.items.toList()) {
          if (isComboProductId(item.product.id) && !item.product.isAvailable) {
            sudhamrtamCart.removeProduct(item.product.id);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _rejection = null;
        _submissionError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order cancelled. Please review your cart.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submissionError =
            'The order could not be cancelled: '
            '${error is OrderApiException ? error.message : error}';
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _dateLabel(DateTime date) =>
      '${_weekdays[date.weekday - 1]}, ${date.day} ${_months[date.month - 1]}';

  /// The dates the customer may choose now (the earliest first).
  List<DateTime> _deliveryDates(OrderRules rules) =>
      rules.deliveryDatesFor(DateTime.now());

  /// The chosen date if it can still be chosen, else the earliest.
  DateTime _shownDate(OrderRules rules) {
    final dates = _deliveryDates(rules);
    final chosen = _chosenDate;
    return chosen != null && dates.contains(chosen) ? chosen : dates.first;
  }

  /// YYYY-MM-DD for the order; null for the earliest date, so the
  /// server picks it (as before dates could be chosen).
  String? _chosenDateIso() {
    final rules = _rules;
    if (rules == null || _chosenDate == null) return null;
    final dates = _deliveryDates(rules);
    final date = _shownDate(rules);
    if (date == dates.first) return null;
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _deliveryDateText(OrderRules rules) =>
      '${_dateLabel(_shownDate(rules))} (morning)';

  /// Delivery date choice: the earliest, or any later day the server
  /// allows (a calendar), on the morning run with the milk.
  Widget _buildDeliveryDate(OrderRules rules) {
    final dates = _deliveryDates(rules);
    final shown = _shownDate(rules);
    final isEarliest = shown == dates.first;
    final locked = sudhamrtamCart.isCheckoutRecoveryLocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Delivery Date'),
        const Text(
          'Delivered in the morning, with the milk.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 8),
        Material(
          color: const Color(0xFFF5F8F0),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: const Key('delivery-date-pick'),
            borderRadius: BorderRadius.circular(12),
            onTap: locked || dates.length < 2
                ? null
                : () => _pickDeliveryDate(dates, shown),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined, color: _brandGreen),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _dateLabel(shown),
                          key: const Key('delivery-date-shown'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          isEarliest ? 'Earliest delivery' : 'Your chosen date',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (dates.length > 1)
                    const Text(
                      'Change',
                      style: TextStyle(
                        color: _brandGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDeliveryDate(List<DateTime> dates, DateTime shown) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: shown,
      firstDate: dates.first,
      lastDate: dates.last,
      helpText: 'Delivery date (morning)',
      confirmText: 'Choose',
    );
    if (picked == null || !mounted) return;
    setState(
      () => _chosenDate = DateTime(picked.year, picked.month, picked.day),
    );
  }

  @override
  void dispose() {
    _deliveryInstructionsController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAddresses() async {
    if (!mounted) return;

    setState(() {
      _addressesLoading = true;
      _addressError = null;
    });

    try {
      final addresses = await _addressService.getAddressesByCustomerId(
        _customerId,
      );

      if (!mounted) return;

      String? selectedId;

      for (final address in addresses) {
        if (address.id == _selectedAddressId) {
          selectedId = address.id;
          break;
        }
      }

      if (selectedId == null) {
        for (final address in addresses) {
          if (address.isDefault) {
            selectedId = address.id;
            break;
          }
        }
      }

      if (selectedId == null && addresses.isNotEmpty) {
        selectedId = addresses.first.id;
      }

      setState(() {
        _savedAddresses = addresses;
        _selectedAddressId = selectedId;
        _addressesLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _addressError = error.toString();
        _addressesLoading = false;
      });
    }
  }

  Future<void> _addNewAddress() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (context) => AddressFormScreen()),
    );

    if (!mounted) return;

    await _loadSavedAddresses();

    if (!mounted) return;

    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery address saved successfully!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _selectAddress(CustomerAddress address) {
    setState(() {
      _selectedAddressId = address.id;
    });
  }

  /// Places (or safely retries) a local test order.
  ///
  /// The order and its ID come from [CheckoutOrderSession],
  /// so a retry never generates a new order ID.
  Future<void> _placeOrder() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _submissionError = null;
      _rejection = null;
    });

    try {
      final isDelivery = _fulfillmentMethod == FulfillmentMethod.delivery;

      final order = await _orderSession.resolveOrder(
        isRecoveryLocked: sudhamrtamCart.isCheckoutRecoveryLocked,
        prepare: () => OrderPreparationService.prepare(
          cart: sudhamrtamCart,
          fulfillmentMethod: _fulfillmentMethod,
          paymentMethod: _paymentMethod,
          deliveryAddress: isDelivery
              ? _selectedAddress?.formattedAddress
              : null,
          recipientName: isDelivery ? _selectedAddress?.recipientName : null,
          recipientPhone: isDelivery ? _selectedAddress?.phoneNumber : null,
          addressId: isDelivery ? _selectedAddress?.id : null,
          deliveryInstructions: isDelivery
              ? _deliveryInstructionsController.text
              : null,
          deliveryDate: isDelivery ? _chosenDateIso() : null,
        ),
      );

      final saved = await _coordinator.submitPreparedOrder(
        order: order,
        cart: sudhamrtamCart,
      );

      _orderSession.markCompleted(saved.id);

      if (!mounted) return;

      // Online orders are placed first, then paid.
      final paysOnline =
          _serverMode && saved.paymentMethod == OrderPaymentMethod.online;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => paysOnline
              ? PaymentScreen(order: saved)
              : OrderDetailsScreen(order: saved),
        ),
      );
    } on OrderRejectedException catch (error) {
      if (!mounted) return;

      setState(() {
        _rejection = error;
        _submissionError = error.message;
      });
    } on OrderApiException catch (error) {
      if (!mounted) return;

      setState(() {
        _submissionError = error.message;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _submissionError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _faultSimulationCard() {
    const labels = {
      CheckoutFault.none: 'No failure',
      CheckoutFault.afterPreparation: 'Fail after preparing order',
      CheckoutFault.afterOrderSaved: 'Fail after saving order',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F0FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0C7F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bug_report_outlined, color: Color(0xFF5B4B9A)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Debug: Simulate Failure',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5B4B9A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Debug builds only. Fires once on the next order. '
            'Then force-close and reopen the app to test recovery.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final fault in CheckoutFault.values)
                ChoiceChip(
                  label: Text(labels[fault]!),
                  selected: _faultInjector.armed == fault,
                  onSelected: _isSubmitting
                      ? null
                      : (_) => setState(() => _faultInjector.armed = fault),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _submissionErrorCard(String error) {
    final isProtected = sudhamrtamCart.isCheckoutRecoveryLocked;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCCC7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, color: Color(0xFFB3261E)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Order could not be completed',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB3261E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(error, style: const TextStyle(fontSize: 13)),
          if (_rejection != null) ...[
            const SizedBox(height: 8),
            const Text(
              'This order cannot be placed as it is. Cancel it to '
              'review your cart; your products stay in the cart.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('cancelRejectedOrder'),
              onPressed: _isSubmitting ? null : _cancelRejectedOrder,
              icon: const Icon(Icons.undo),
              label: Text(
                _rejection!.isComboChange
                    ? 'Remove Combo and Review Cart'
                    : 'Cancel Order and Review Cart',
              ),
            ),
          ] else if (isProtected) ...[
            const SizedBox(height: 8),
            const Text(
              'Your cart is locked to protect this order. '
              'Tap Retry to finish it. The same order will be used.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _optionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Card(
      color: selected ? const Color(0xFFF5F8F0) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? _brandGreen : Colors.black12,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: _brandGreen),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? _brandGreen : Colors.grey,
        ),
      ),
    );
  }

  Widget _buildAddressSelection() {
    if (_addressesLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(color: _brandGreen)),
        ),
      );
    }

    if (_addressError != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Unable to load saved addresses.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_addressError!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadSavedAddresses,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_savedAddresses.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(
                Icons.location_off_outlined,
                size: 48,
                color: _brandGreen,
              ),
              const SizedBox(height: 12),
              const Text(
                'No saved delivery addresses',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add a delivery address to continue with home delivery.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _addNewAddress,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add New Address'),
                style: FilledButton.styleFrom(
                  backgroundColor: _brandGreen,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._savedAddresses.map((address) {
          final selected = address.id == _selectedAddressId;

          return Card(
            color: selected ? const Color(0xFFF5F8F0) : null,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: selected ? _brandGreen : Colors.black12,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _selectAddress(address),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? _brandGreen : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  address.label,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (address.isDefault) ...[
                                const SizedBox(width: 8),
                                const Chip(
                                  label: Text('Default'),
                                  backgroundColor: Color(0xFFEAF4DB),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            address.recipientName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(address.phoneNumber),
                          const SizedBox(height: 6),
                          Text(address.formattedAddress),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),

        const SizedBox(height: 8),

        OutlinedButton.icon(
          onPressed: _addNewAddress,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Add New Address'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _brandGreen,
            side: const BorderSide(color: _brandGreen),
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryInstructions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Delivery Instructions (Optional)'),
        TextField(
          controller: _deliveryInstructionsController,
          minLines: 2,
          maxLines: 3,
          maxLength: _maxInstructionLength,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            hintText:
                'E.g. Leave the milk at the main gate '
                'or call when you arrive.',
            prefixIcon: const Icon(
              Icons.edit_note_outlined,
              color: _brandGreen,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _brandGreen, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'These instructions apply only to this checkout preview. '
          'They are not saved to your delivery address.',
          style: TextStyle(color: Colors.black54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _reviewRow({
    required String label,
    required String value,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: _brandGreen, size: 21),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinalCheckoutReview({
    required CustomerAddress? selectedAddress,
    required bool hasUnpricedProducts,
  }) {
    final isDelivery = _fulfillmentMethod == FulfillmentMethod.delivery;

    final instructions = _deliveryInstructionsController.text.trim();

    final fulfillmentText = isDelivery ? 'Home Delivery' : 'Store Pickup';

    final paymentText = _paymentMethod == OrderPaymentMethod.online
        ? (_serverMode
              ? 'Pay Online (UPI / Card / Net Banking)'
              : 'Online Payment')
        : _serverMode
        ? 'Cash on Delivery'
        : 'Cash on Delivery / Pickup';

    final rules = _rules;

    final addressText = _addressesLoading
        ? 'Loading saved addresses...'
        : _addressError != null
        ? 'Unable to load delivery address'
        : selectedAddress == null
        ? 'No delivery address selected'
        : '${selectedAddress.recipientName}\n'
              '${selectedAddress.phoneNumber}\n'
              '${selectedAddress.formattedAddress}';

    final subtotalText = hasUnpricedProducts
        ? 'Pending pricing'
        : '₹${sudhamrtamCart.subtotal.toStringAsFixed(2)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Final Checkout Review'),

        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE1EBCF)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.fact_check_outlined, color: _brandGreen),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Review Your Checkout Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                const Divider(),

                _reviewRow(
                  label: 'Fulfillment',
                  value: fulfillmentText,
                  icon: isDelivery
                      ? Icons.local_shipping_outlined
                      : Icons.storefront_outlined,
                ),

                if (isDelivery) ...[
                  const Divider(),

                  _reviewRow(
                    label: 'Deliver To',
                    value: addressText,
                    icon: Icons.location_on_outlined,
                  ),

                  const Divider(),

                  if (_serverMode && rules != null) ...[
                    _reviewRow(
                      label: 'Delivery',
                      value: _deliveryDateText(rules),
                      icon: Icons.event_outlined,
                    ),
                    const Divider(),
                  ],

                  _reviewRow(
                    label: 'Instructions',
                    value: instructions.isEmpty
                        ? 'No special instructions'
                        : instructions,
                    icon: Icons.notes_outlined,
                  ),
                ],

                const Divider(),

                _reviewRow(
                  label: 'Payment',
                  value: paymentText,
                  icon: Icons.payments_outlined,
                ),

                const Divider(),

                _reviewRow(
                  label: 'Products',
                  value: '${sudhamrtamCart.uniqueItemCount}',
                  icon: Icons.shopping_bag_outlined,
                ),

                _reviewRow(
                  label: 'Total Units',
                  value: '${sudhamrtamCart.totalQuantity}',
                  icon: Icons.inventory_2_outlined,
                ),

                const Divider(),

                _reviewRow(
                  label: 'Subtotal',
                  value: subtotalText,
                  icon: Icons.currency_rupee,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        Text(
          _serverMode
              ? 'Pay in cash when your order is delivered.'
              : widget.enableTestOrders
              ? 'Test mode: orders are saved on this phone only. '
                    'No payment is taken.'
              : 'This summary is for review only. '
                    'No order or payment will be created.',
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _validationCard(List<String> errors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD8A8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_outlined, color: Color(0xFFB26A00)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Checkout Requirements',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF8A5200),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...errors.map(
            (error) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 17,
                    color: Color(0xFFB26A00),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8A5200),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkoutStatusCard({required bool isValid}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1EBCF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: _brandGreen),
              SizedBox(width: 8),
              Text(
                'Checkout Status',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            !isValid
                ? 'Please review the checkout requirements '
                      'above. Order placement is currently '
                      'unavailable.'
                : _serverMode && _paysOnline
                ? 'Ready to place your order. You pay online on the '
                      'next screen.'
                : _serverMode
                ? 'Ready to place your order. It is sent to '
                      'Sudhamrtam and paid in cash on delivery.'
                : !widget.enableTestOrders
                ? 'Initial checkout checks passed. '
                      'Order placement remains disabled '
                      'until the remaining business and '
                      'payment requirements are verified.'
                : _paymentMethod != OrderPaymentMethod.cashOnDelivery
                ? 'Online payment is not available yet. '
                      'Choose Cash on Delivery / Pickup '
                      'to place a test order.'
                : 'Checks passed. You can place a test order. '
                      'It is saved on this phone only and is '
                      'not sent to Sudhamrtam.',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PageAppBar(title: const Text('Checkout')),
      body: AnimatedBuilder(
        animation: sudhamrtamCart,
        builder: (context, child) {
          final items = sudhamrtamCart.items;

          if (!sudhamrtamCart.isInitialized || sudhamrtamCart.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: _brandGreen),
            );
          }

          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shopping_cart_outlined,
                      size: 64,
                      color: _brandGreen,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Your cart is empty',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Please add products before checkout.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final hasUnpricedProducts = items.any(
            (item) => !item.product.price.isFinite || item.product.price <= 0,
          );

          final selectedAddress = _selectedAddress;

          final deliveryAddressForValidation =
              _addressesLoading || _addressError != null
              ? null
              : selectedAddress?.formattedAddress;

          final validation = CheckoutValidator.validate(
            cart: sudhamrtamCart,
            fulfillmentMethod: _fulfillmentMethod,
            paymentMethod: _paymentMethod,
            deliveryAddress: deliveryAddressForValidation,
          );

          final serverRequirements = _serverRequirements(selectedAddress);

          final checkoutReady =
              validation.isValid &&
              serverRequirements.isEmpty &&
              (_fulfillmentMethod == FulfillmentMethod.pickup ||
                  (!_addressesLoading &&
                      _addressError == null &&
                      selectedAddress != null));

          // A retry resubmits the original durable order,
          // so the current on-screen selections do not apply.
          final isRetry = sudhamrtamCart.isCheckoutRecoveryLocked;

          final canPlaceOrder =
              _ordersEnabled &&
              !_isSubmitting &&
              _rejection == null &&
              (!_serverMode || _signedIn) &&
              (isRetry ||
                  (checkoutReady &&
                      !sudhamrtamCart.isCheckoutLocked &&
                      (_paymentMethod == OrderPaymentMethod.cashOnDelivery ||
                          _paysOnline)));

          final placeOrderLabel = !_ordersEnabled
              ? 'Ordering unavailable in this version'
              : _serverMode
              ? (_isSubmitting
                    ? 'Placing Order...'
                    : isRetry
                    ? 'Retry Order'
                    : _paysOnline
                    ? 'Place Order & Pay'
                    : 'Place Order')
              : _isSubmitting
              ? 'Placing Test Order...'
              : isRetry
              ? 'Retry Test Order'
              : 'Place Test Order';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Review Your Order',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please review your products and preferences.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              // Shortcuts (owner request 2026-11-15): change the cart,
              // or add more products first.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('checkoutEditCart'),
                    onPressed: () => openTab(context, cartTab),
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('Edit cart'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('checkoutContinueShopping'),
                    onPressed: () => openTab(context, shopTab),
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Text('Continue shopping'),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              _sectionTitle('Order Summary'),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ...items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            children: [
                              Icon(
                                item.product.icon,
                                color: _brandGreen,
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.product.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${item.quantity} × '
                                      '${item.product.unit}',
                                      style: const TextStyle(
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                item.product.price.isFinite &&
                                        item.product.price > 0
                                    ? '₹${item.totalPrice.toStringAsFixed(2)}'
                                    : 'Pending',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Products',
                            style: TextStyle(color: Colors.black54),
                          ),
                          Text('${sudhamrtamCart.uniqueItemCount}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Units',
                            style: TextStyle(color: Colors.black54),
                          ),
                          Text('${sudhamrtamCart.totalQuantity}'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Product Subtotal',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            hasUnpricedProducts
                                ? 'Pending pricing'
                                : '₹${sudhamrtamCart.subtotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _brandGreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              _sectionTitle(_serverMode ? 'Delivery' : 'Delivery or Pickup'),

              _optionCard(
                title: 'Home Delivery',
                subtitle: 'Deliver to your selected address',
                icon: Icons.local_shipping_outlined,
                selected: _fulfillmentMethod == FulfillmentMethod.delivery,
                onTap: () {
                  setState(() {
                    _fulfillmentMethod = FulfillmentMethod.delivery;
                  });
                  _loadSavedAddresses();
                },
              ),

              // Delivery only at launch (owner decision).
              if (!_serverMode)
                _optionCard(
                  title: 'Store Pickup',
                  subtitle: 'Collect your order from Sudhamrtam',
                  icon: Icons.storefront_outlined,
                  selected: _fulfillmentMethod == FulfillmentMethod.pickup,
                  onTap: () {
                    setState(() {
                      _fulfillmentMethod = FulfillmentMethod.pickup;
                    });
                  },
                ),

              if (_fulfillmentMethod == FulfillmentMethod.delivery) ...[
                const SizedBox(height: 20),
                _sectionTitle('Select Delivery Address'),
                _buildAddressSelection(),

                if (_serverMode &&
                    _rules != null &&
                    _rules!.maxDaysAhead > 0) ...[
                  const SizedBox(height: 24),
                  _buildDeliveryDate(_rules!),
                ],

                const SizedBox(height: 24),
                _buildDeliveryInstructions(),
              ],

              const SizedBox(height: 24),
              _sectionTitle('Payment Method'),

              _optionCard(
                title: _serverMode
                    ? 'Cash on Delivery'
                    : 'Cash on Delivery / Pickup',
                subtitle: 'Pay when you receive your order',
                icon: Icons.payments_outlined,
                selected: _paymentMethod == OrderPaymentMethod.cashOnDelivery,
                onTap: () {
                  setState(() {
                    _paymentMethod = OrderPaymentMethod.cashOnDelivery;
                  });
                },
              ),

              // Online payment: offered when the server takes it
              // (Cashfree); local test orders keep the old option.
              if (!_serverMode || _onlineOffered)
                _optionCard(
                  title: _serverMode ? 'Pay Online' : 'Online Payment',
                  subtitle: _serverMode
                      ? 'UPI, cards and net banking (Cashfree)'
                      : 'UPI, cards and other online options',
                  icon: Icons.credit_card_outlined,
                  selected: _paymentMethod == OrderPaymentMethod.online,
                  onTap: () {
                    setState(() {
                      _paymentMethod = OrderPaymentMethod.online;
                    });
                  },
                ),

              const SizedBox(height: 24),

              // New read-only checkout summary.
              _buildFinalCheckoutReview(
                selectedAddress: selectedAddress,
                hasUnpricedProducts: hasUnpricedProducts,
              ),

              const SizedBox(height: 24),

              if (!validation.isValid) ...[
                _validationCard(validation.errors),
                const SizedBox(height: 24),
              ],

              if (serverRequirements.isNotEmpty && !isRetry) ...[
                _serverRequirementsCard(serverRequirements),
                const SizedBox(height: 24),
              ],

              _checkoutStatusCard(isValid: checkoutReady),

              const SizedBox(height: 24),

              if (_showFaultSimulation) ...[
                _faultSimulationCard(),
                const SizedBox(height: 24),
              ],

              if (_submissionError != null) ...[
                _submissionErrorCard(_submissionError!),
                const SizedBox(height: 24),
              ],

              FilledButton.icon(
                onPressed: canPlaceOrder ? _placeOrder : null,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        !_ordersEnabled
                            ? Icons.lock_outline
                            : isRetry
                            ? Icons.refresh
                            : Icons.check_circle_outline,
                      ),
                label: Text(placeOrderLabel),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),

              const SizedBox(height: 12),

              Text(
                _serverMode
                    ? 'Your order is sent to Sudhamrtam. '
                          'Cash on Delivery.'
                    : widget.enableTestOrders
                    ? 'Test order — saved on this phone only. '
                          'Not sent to Sudhamrtam. No payment is taken.'
                    : 'No order or payment will be created '
                          'from this preview screen.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),

              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
