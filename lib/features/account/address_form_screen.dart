import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../models/customer_address.dart';
import '../../services/account_api_client.dart';
import '../../services/account_sync_service.dart';
import '../../services/catalog_api_client.dart';

/// Loads the delivery areas for the area choice; null when this
/// build has no server.
typedef DeliveryAreaLoader = Future<List<DeliveryArea>> Function();

DeliveryAreaLoader? _defaultAreaLoader() =>
    CatalogApiClient.fromEnvironment()?.fetchAreas;

class AddressFormScreen extends StatefulWidget {
  AddressFormScreen({
    super.key,
    this.existingAddress,
    AccountSyncService? account,
    DeliveryAreaLoader? loadAreas,
  }) : account = account ?? sudhamrtamAccount,
       loadAreas = loadAreas ?? _defaultAreaLoader();

  final CustomerAddress? existingAddress;
  final AccountSyncService account;
  final DeliveryAreaLoader? loadAreas;

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  static const Color _brandGreen = Color(0xFF82B440);
  static const String _customerId = AccountSyncService.localCustomerId;

  final _formKey = GlobalKey<FormState>();

  final _recipientController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _landmarkController = TextEditingController();
  final _cityController = TextEditingController(text: 'Hyderabad');
  final _stateController = TextEditingController(text: 'Telangana');
  final _postalCodeController = TextEditingController();

  String _addressLabel = 'Home';
  bool _isDefault = false;
  bool _isSaving = false;

  // Delivery area. Required once the list of areas is known.
  String? _areaId;
  List<DeliveryArea>? _areas;
  bool _areasLoading = false;
  String? _areasError;

  bool get _isEditing => widget.existingAddress != null;

  @override
  void initState() {
    super.initState();
    _loadAreas();

    final address = widget.existingAddress;
    if (address == null) return;

    _areaId = address.areaId;

    _addressLabel = ['Home', 'Office', 'Other'].contains(address.label)
        ? address.label
        : 'Other';

    _recipientController.text = address.recipientName;
    _phoneController.text = address.phoneNumber;
    _addressLine1Controller.text = address.addressLine1;
    _addressLine2Controller.text = address.addressLine2 ?? '';
    _landmarkController.text = address.landmark;
    _cityController.text = address.city;
    _stateController.text = address.state;
    _postalCodeController.text = address.postalCode;
    _isDefault = address.isDefault;
  }

  Future<void> _loadAreas() async {
    final load = widget.loadAreas;
    if (load == null) return;

    setState(() {
      _areasLoading = true;
      _areasError = null;
    });

    try {
      final areas = await load();
      if (!mounted) return;
      setState(() {
        _areas = areas;
        _areasLoading = false;
        // Drop an area that is no longer served.
        if (_areaId != null && !areas.any((a) => a.id == _areaId)) {
          _areaId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _areasLoading = false;
        _areasError = 'Could not load delivery areas.';
      });
    }
  }

  Widget _buildAreaField() {
    final areas = _areas;

    if (widget.loadAreas == null) return const SizedBox.shrink();

    if (_areasLoading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: LinearProgressIndicator(color: _brandGreen),
      );
    }

    if (areas == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Expanded(child: Text(_areasError ?? '')),
            TextButton(onPressed: _loadAreas, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        key: const Key('areaField'),
        initialValue: _areaId,
        decoration: const InputDecoration(
          labelText: 'Delivery Area',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final area in areas)
            DropdownMenuItem(value: area.id, child: Text(area.name)),
        ],
        onChanged: _isSaving ? null : (value) => setState(() => _areaId = value),
        validator: (value) =>
            value == null ? 'Please choose your delivery area' : null,
      ),
    );
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _phoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    bool requiredField = true,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        enabled: !_isSaving,
        keyboardType: keyboardType,
        maxLines: maxLines,
        textCapitalization: keyboardType == TextInputType.text
            ? TextCapitalization.words
            : TextCapitalization.none,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: _brandGreen, width: 2),
          ),
        ),
        validator: (value) {
          final text = value?.trim() ?? '';

          if (requiredField && text.isEmpty) {
            return 'Please enter $label';
          }

          if (label == 'Mobile Number' &&
              !RegExp(r'^[6-9]\d{9}$').hasMatch(text)) {
            return 'Enter a valid 10-digit mobile number';
          }

          if (label == 'PIN Code' && !RegExp(r'^\d{6}$').hasMatch(text)) {
            return 'Enter a valid 6-digit PIN code';
          }

          return null;
        },
      ),
    );
  }

  Future<void> _saveAddress() async {
    if (_isSaving) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final now = DateTime.now();
      final existing = widget.existingAddress;

      final address = CustomerAddress(
        id: existing?.id ?? 'address_${now.microsecondsSinceEpoch}',
        customerId: existing?.customerId ?? _customerId,
        areaId: _areaId,
        label: _addressLabel,
        recipientName: _recipientController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        addressLine1: _addressLine1Controller.text.trim(),
        addressLine2: _addressLine2Controller.text.trim().isEmpty
            ? null
            : _addressLine2Controller.text.trim(),
        landmark: _landmarkController.text.trim(),
        city: _cityController.text.trim(),
        state: _stateController.text.trim(),
        postalCode: _postalCodeController.text.trim(),

        // Preserve saved map coordinates during editing.
        latitude: existing?.latitude,
        longitude: existing?.longitude,

        isDefault: _isDefault,

        // Keep the original creation timestamp when editing.
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );

      await widget.account.saveAddress(address);

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } on AccountApiException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Address not saved: ${error.message}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to save address: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Delivery Address' : 'Add Delivery Address',
        ),
        backgroundColor: _brandGreen,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Address Type',
              style: Theme.of(context).textTheme.titleMedium,
            ),

            const SizedBox(height: 12),

            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'Home',
                  label: Text('Home'),
                  icon: Icon(Icons.home_outlined),
                ),
                ButtonSegment(
                  value: 'Office',
                  label: Text('Office'),
                  icon: Icon(Icons.business_outlined),
                ),
                ButtonSegment(
                  value: 'Other',
                  label: Text('Other'),
                  icon: Icon(Icons.place_outlined),
                ),
              ],
              selected: {_addressLabel},
              onSelectionChanged: _isSaving
                  ? null
                  : (selection) {
                      setState(() {
                        _addressLabel = selection.first;
                      });
                    },
            ),

            const SizedBox(height: 24),

            _buildAreaField(),

            _buildTextField(
              controller: _recipientController,
              label: 'Recipient Name',
              hint: 'Enter recipient full name',
            ),

            _buildTextField(
              controller: _phoneController,
              label: 'Mobile Number',
              hint: 'Enter 10-digit mobile number',
              keyboardType: TextInputType.phone,
            ),

            _buildTextField(
              controller: _addressLine1Controller,
              label: 'House / Flat / Street Address',
              hint: 'House number, building and street',
              maxLines: 2,
            ),

            _buildTextField(
              controller: _addressLine2Controller,
              label: 'Apartment / Area (Optional)',
              hint: 'Apartment, colony or locality',
              requiredField: false,
            ),

            _buildTextField(
              controller: _landmarkController,
              label: 'Landmark (Optional)',
              hint: 'Nearby landmark',
              requiredField: false,
            ),

            _buildTextField(controller: _cityController, label: 'City'),

            _buildTextField(controller: _stateController, label: 'State'),

            _buildTextField(
              controller: _postalCodeController,
              label: 'PIN Code',
              hint: 'Enter 6-digit PIN code',
              keyboardType: TextInputType.number,
            ),

            SwitchListTile(
              title: const Text('Set as Default Address'),
              subtitle: const Text('Use this address for future deliveries'),
              value: _isDefault,
              activeThumbColor: _brandGreen,
              onChanged: _isSaving
                  ? null
                  : (value) {
                      setState(() {
                        _isDefault = value;
                      });
                    },
            ),

            const SizedBox(height: 16),

            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveAddress,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _isEditing ? Icons.edit_outlined : Icons.save_outlined,
                      ),
                label: Text(
                  _isSaving
                      ? 'Saving...'
                      : _isEditing
                      ? 'Update Address'
                      : 'Save Address',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _brandGreen,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
