import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../database/customer_address_database_service.dart';
import '../../models/customer_address.dart';
import '../../models/customer_order.dart';
import '../account/address_form_screen.dart';
import '../orders/order_details_screen.dart';
import 'checkout_fault_injector.dart';
import 'checkout_order_session.dart';
import 'checkout_validator.dart';
import 'durable_checkout_coordinator.dart';
import 'order_preparation_service.dart';

const _brandGreen = Color(0xFF82B440);

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    this.enableTestOrders = kDebugMode,
    this.coordinator,
    this.orderSession,
  });

  /// Local test orders are allowed only in debug builds
  /// until checkout safety has been signed off.
  ///
  /// Test orders are saved on this phone only. They are
  /// not sent to Sudhamrtam and no payment is taken.
  final bool enableTestOrders;

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
      MaterialPageRoute<bool>(builder: (context) => const AddressFormScreen()),
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
          deliveryInstructions: isDelivery
              ? _deliveryInstructionsController.text
              : null,
        ),
      );

      final saved = await _coordinator.submitPreparedOrder(
        order: order,
        cart: sudhamrtamCart,
      );

      _orderSession.markCompleted(saved.id);

      if (!mounted) return;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => OrderDetailsScreen(order: saved),
        ),
      );
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
          if (isProtected) ...[
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

    final paymentText = _paymentMethod == OrderPaymentMethod.cashOnDelivery
        ? 'Cash on Delivery / Pickup'
        : 'Online Payment';

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
          widget.enableTestOrders
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
      appBar: AppBar(title: const Text('Checkout')),
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

          final checkoutReady =
              validation.isValid &&
              (_fulfillmentMethod == FulfillmentMethod.pickup ||
                  (!_addressesLoading &&
                      _addressError == null &&
                      selectedAddress != null));

          // A retry resubmits the original durable order,
          // so the current on-screen selections do not apply.
          final isRetry = sudhamrtamCart.isCheckoutRecoveryLocked;

          final canPlaceOrder =
              widget.enableTestOrders &&
              !_isSubmitting &&
              (isRetry ||
                  (checkoutReady &&
                      !sudhamrtamCart.isCheckoutLocked &&
                      _paymentMethod == OrderPaymentMethod.cashOnDelivery));

          final placeOrderLabel = !widget.enableTestOrders
              ? 'Place Order — Coming Soon'
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
              _sectionTitle('Delivery or Pickup'),

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

                const SizedBox(height: 24),
                _buildDeliveryInstructions(),
              ],

              const SizedBox(height: 24),
              _sectionTitle('Payment Method'),

              _optionCard(
                title: 'Cash on Delivery / Pickup',
                subtitle: 'Pay when you receive your order',
                icon: Icons.payments_outlined,
                selected: _paymentMethod == OrderPaymentMethod.cashOnDelivery,
                onTap: () {
                  setState(() {
                    _paymentMethod = OrderPaymentMethod.cashOnDelivery;
                  });
                },
              ),

              _optionCard(
                title: 'Online Payment',
                subtitle: 'UPI, cards and other online options',
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
                        !widget.enableTestOrders
                            ? Icons.lock_outline
                            : isRetry
                            ? Icons.refresh
                            : Icons.check_circle_outline,
                      ),
                label: Text(placeOrderLabel),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: _brandGreen,
                  foregroundColor: Colors.white,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                widget.enableTestOrders
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
