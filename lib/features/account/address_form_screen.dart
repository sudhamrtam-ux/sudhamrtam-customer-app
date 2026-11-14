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

/// Loads an area's societies (Sudhamrtam's list); null without a
/// server, when the society is typed.
typedef SocietyLoader = Future<List<SocietyChoice>> Function(String areaId);

SocietyLoader? _defaultSocietyLoader() =>
    CatalogApiClient.fromEnvironment()?.fetchSocieties;

/// The society choice that means "type it".
const _notListed = '__not_listed__';

class AddressFormScreen extends StatefulWidget {
  AddressFormScreen({
    super.key,
    this.existingAddress,
    AccountSyncService? account,
    DeliveryAreaLoader? loadAreas,
    SocietyLoader? loadSocieties,
  }) : account = account ?? sudhamrtamAccount,
       loadAreas = loadAreas ?? _defaultAreaLoader(),
       loadSocieties = loadSocieties ?? _defaultSocietyLoader();

  final CustomerAddress? existingAddress;
  final AccountSyncService account;
  final DeliveryAreaLoader? loadAreas;
  final SocietyLoader? loadSocieties;

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
  final _blockController = TextEditingController();
  final _flatController = TextEditingController();
  final _typedSocietyController = TextEditingController();
  final _noteController = TextEditingController();

  /// Society, block and flat (owner decisions 2026-11-11): flat is
  /// always needed; society and block unless an independent house.
  bool _isHouse = false;
  String? _society;
  List<SocietyChoice> _societies = const [];

  /// The chosen society, when it gives the address (owner decision
  /// 2026-11-14): then only flat, block and a note are typed.
  SocietyChoice? get _societyWithAddress {
    if (_isHouse || _society == null || _society == _notListed) return null;
    for (final s in _societies) {
      if (s.id == _society && s.hasAddress) return s;
    }
    return null;
  }

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
    _isHouse = address.isHouse;
    _blockController.text = address.block ?? '';
    _flatController.text = address.flat ?? '';
    _typedSocietyController.text = address.societyOther ?? '';
    _noteController.text = address.deliveryNote ?? '';
    _society =
        address.societyId ?? (address.societyOther == null ? null : _notListed);
    // Shown until the list arrives.
    if (address.societyId != null && address.societyName != null) {
      _societies = [
        SocietyChoice(id: address.societyId!, name: address.societyName!),
      ];
    }
  }

  Future<void> _loadSocieties(String areaId) async {
    final load = widget.loadSocieties;
    if (load == null) return;
    try {
      final list = await load(areaId);
      if (!mounted || areaId != _areaId) return;
      setState(() {
        _societies = list;
        if (_society != null &&
            _society != _notListed &&
            !list.any((s) => s.id == _society)) {
          _society = null;
        }
      });
    } catch (_) {
      // Without the list the customer can still type the society.
      if (mounted && areaId == _areaId) {
        setState(() {
          _societies = const [];
          _society ??= _notListed;
        });
      }
    }
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
      if (_areaId != null) await _loadSocieties(_areaId!);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _areasLoading = false;
        _areasError = 'Could not load delivery areas.';
      });
    }
  }

  /// "A", "A and B", "A, B and C".
  static String _joinNames(List<DeliveryArea> areas) {
    final names = [for (final area in areas) area.name];
    if (names.length == 1) return names.single;
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
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
        decoration: InputDecoration(
          labelText: 'Your Area',
          // The areas come from the server, so this stays current.
          helperText: areas.isEmpty
              ? null
              : 'We currently deliver only to ${_joinNames(areas)}.',
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final area in areas)
            DropdownMenuItem(value: area.id, child: Text(area.name)),
        ],
        onChanged: _isSaving
            ? null
            : (value) {
                setState(() {
                  _areaId = value;
                  _societies = const [];
                  if (_society != _notListed) _society = null;
                });
                if (value != null) _loadSocieties(value);
              },
        validator: (value) => value == null
            ? 'Please choose your area. We deliver only to the areas listed.'
            : null,
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
    _blockController.dispose();
    _flatController.dispose();
    _typedSocietyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Independent house; society, block/tower and flat.
  Widget _buildSocietyFields() {
    String? required(String? value, String message) =>
        value == null || value.trim().isEmpty ? message : null;
    InputDecoration decoration(String label, {String? hint, String? help}) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: help,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: _brandGreen, width: 2),
          ),
        );
    // With a server the society is chosen from the list (or "Not
    // listed"); without one it is typed.
    final picks = widget.loadSocieties != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          key: const Key('houseField'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: _brandGreen,
          title: const Text('Independent house / not in a society'),
          value: _isHouse,
          onChanged: _isSaving
              ? null
              : (v) => setState(() => _isHouse = v ?? false),
        ),
        const SizedBox(height: 8),
        if (!_isHouse) ...[
          if (picks)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: DropdownButtonFormField<String>(
                key: ValueKey('societyField-$_areaId-${_societies.length}'),
                initialValue: _society,
                isExpanded: true,
                decoration: decoration(
                  'Society / Apartment',
                  help: _areaId == null
                      ? 'Choose your area first.'
                      : 'Not in the list? Choose "Not listed" and type it.',
                ),
                items: [
                  for (final s in _societies)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                  const DropdownMenuItem(
                    value: _notListed,
                    child: Text('Not listed — type it'),
                  ),
                ],
                onChanged: _isSaving || _areaId == null
                    ? null
                    : (v) => setState(() => _society = v),
                validator: (v) =>
                    v == null ? 'Please choose your society' : null,
              ),
            ),
          if (!picks || _society == _notListed)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextFormField(
                key: const Key('typedSocietyField'),
                controller: _typedSocietyController,
                enabled: !_isSaving,
                textCapitalization: TextCapitalization.words,
                decoration: decoration(
                  'Society / Apartment Name',
                  hint: 'e.g. Green Towers',
                ),
                validator: (v) => required(v, 'Please enter your society name'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextFormField(
              key: const Key('blockField'),
              controller: _blockController,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.characters,
              decoration: decoration(
                'Block / Tower',
                hint: 'e.g. B or Tower 3',
              ),
              validator: (v) => required(v, 'Please enter your block or tower'),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
            key: const Key('flatField'),
            controller: _flatController,
            enabled: !_isSaving,
            textCapitalization: TextCapitalization.characters,
            decoration: decoration(
              _isHouse ? 'House Number' : 'Flat Number',
              hint: _isHouse ? 'e.g. 7-1-45' : 'e.g. 101',
            ),
            validator: (v) => required(
              v,
              _isHouse
                  ? 'Please enter your house number'
                  : 'Please enter your flat number',
            ),
          ),
        ),
      ],
    );
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
      // A society with its own address gives the street, city and PIN.
      final place = _societyWithAddress;
      final note = _noteController.text.trim();

      final address = CustomerAddress(
        id: existing?.id ?? 'address_${now.microsecondsSinceEpoch}',
        customerId: existing?.customerId ?? _customerId,
        areaId: _areaId,
        label: _addressLabel,
        recipientName: _recipientController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        addressLine1:
            place?.addressLine1 ?? _addressLine1Controller.text.trim(),
        addressLine2:
            place != null || _addressLine2Controller.text.trim().isEmpty
            ? null
            : _addressLine2Controller.text.trim(),
        landmark: place != null ? '' : _landmarkController.text.trim(),
        city: place?.city ?? _cityController.text.trim(),
        state: place?.state ?? _stateController.text.trim(),
        postalCode: place?.postalCode ?? _postalCodeController.text.trim(),

        // Preserve saved map coordinates during editing.
        latitude: existing?.latitude,
        longitude: existing?.longitude,

        isDefault: _isDefault,

        // Keep the original creation timestamp when editing.
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,

        isHouse: _isHouse,
        societyId: _isHouse || _society == _notListed ? null : _society,
        societyName: _isHouse || _society == _notListed
            ? null
            : [
                for (final s in _societies)
                  if (s.id == _society) s.name,
              ].firstOrNull,
        societyOther:
            !_isHouse &&
                (widget.loadSocieties == null || _society == _notListed)
            ? _typedSocietyController.text.trim()
            : null,
        block: _isHouse ? null : _blockController.text.trim(),
        flat: _flatController.text.trim(),
        deliveryNote: note.isEmpty ? null : note,
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

            _buildSocietyFields(),

            if (_societyWithAddress case final place?)
              // The society gives the rest of the address.
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: InputDecorator(
                  key: const Key('societyAddress'),
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    helperText: 'Filled in from your society.',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                  child: Text(place.addressText),
                ),
              )
            else ...[
              _buildTextField(
                controller: _addressLine1Controller,
                label: 'Street / Road / Locality',
                hint: 'Street, road or colony',
                maxLines: 2,
              ),

              _buildTextField(
                controller: _addressLine2Controller,
                label: 'More Address (Optional)',
                hint: 'Anything else that helps us find you',
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
            ],

            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextFormField(
                key: const Key('deliveryNoteField'),
                controller: _noteController,
                enabled: !_isSaving,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Delivery Note (Optional)',
                  hintText: 'e.g. Leave at the door, ring twice',
                  helperText: 'Our delivery partner sees this.',
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: _brandGreen, width: 2),
                  ),
                ),
              ),
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
