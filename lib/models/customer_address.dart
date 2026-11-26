/// Represents a locally saved customer delivery address.
///
/// Addresses belong to the phone's local customer profile. When
/// the customer is signed in, AccountSyncService keeps them in
/// step with the server.
class CustomerAddress {
  final String id;
  final String customerId;

  /// Server delivery area ID (e.g. `nizampet`); null if unknown.
  final String? areaId;

  final String label;
  final String recipientName;
  final String phoneNumber;
  final String addressLine1;
  final String? addressLine2;
  final String landmark;
  final String city;
  final String state;
  final String postalCode;

  /// Optional Google Maps delivery location.
  final double? latitude;
  final double? longitude;

  final bool isDefault;

  /// Used on the monthly milk bill (owner decision 2026-11-26).
  final bool isBilling;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// A society from Sudhamrtam's list for the area…
  final String? societyId;

  /// …its name (kept for showing it offline)…
  final String? societyName;

  /// …or one the customer typed because it was not listed.
  final String? societyOther;

  /// Block / tower / wing.
  final String? block;

  /// Flat number; the house number for an independent house.
  final String? flat;

  /// An independent house: no society or block.
  final bool isHouse;

  /// "Leave at the door": shown to the delivery partner (v19).
  final String? deliveryNote;

  const CustomerAddress({
    required this.id,
    required this.customerId,
    this.areaId,
    required this.label,
    required this.recipientName,
    required this.phoneNumber,
    required this.addressLine1,
    this.addressLine2,
    required this.landmark,
    required this.city,
    required this.state,
    required this.postalCode,
    this.latitude,
    this.longitude,
    this.isDefault = false,
    this.isBilling = false,
    required this.createdAt,
    required this.updatedAt,
    this.societyId,
    this.societyName,
    this.societyOther,
    this.block,
    this.flat,
    this.isHouse = false,
    this.deliveryNote,
  });

  /// True when a complete coordinate pair is available.
  bool get hasMapLocation => latitude != null && longitude != null;

  /// The society to show: the listed name, or the typed one.
  String? get society => societyName ?? societyOther;

  /// Society, block or flat is missing (an address saved before
  /// they were asked for); deliveries sort by them.
  bool get needsDetails =>
      _blank(flat) ||
      (!isHouse &&
          (_blank(block) || (societyId == null && _blank(societyOther))));

  static bool _blank(String? s) => s == null || s.trim().isEmpty;

  /// "Block B", but "Tower 3" / "Wing C" as typed.
  static String blockText(String block) =>
      RegExp(
        r'^(block|tower|wing|phase)\b',
        caseSensitive: false,
      ).hasMatch(block)
      ? block
      : 'Block $block';

  /// Creates a modified copy of the address.
  ///
  /// Nullable fields use explicit clear flags so they
  /// can be removed without affecting other properties.
  CustomerAddress copyWith({
    String? areaId,
    String? label,
    String? recipientName,
    String? phoneNumber,
    String? addressLine1,
    String? addressLine2,
    bool clearAddressLine2 = false,
    String? landmark,
    String? city,
    String? state,
    String? postalCode,
    double? latitude,
    double? longitude,
    bool clearMapLocation = false,
    bool? isDefault,
    bool? isBilling,
    DateTime? updatedAt,
  }) {
    // Society, block, flat and house are set in the address form,
    // which builds a whole new address.
    return CustomerAddress(
      id: id,
      customerId: customerId,
      areaId: areaId ?? this.areaId,
      label: label ?? this.label,
      recipientName: recipientName ?? this.recipientName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: clearAddressLine2
          ? null
          : addressLine2 ?? this.addressLine2,
      landmark: landmark ?? this.landmark,
      city: city ?? this.city,
      state: state ?? this.state,
      postalCode: postalCode ?? this.postalCode,
      latitude: clearMapLocation ? null : latitude ?? this.latitude,
      longitude: clearMapLocation ? null : longitude ?? this.longitude,
      isDefault: isDefault ?? this.isDefault,
      isBilling: isBilling ?? this.isBilling,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      societyId: societyId,
      societyName: societyName,
      societyOther: societyOther,
      block: block,
      flat: flat,
      isHouse: isHouse,
      deliveryNote: deliveryNote,
    );
  }

  /// Returns the formatted address for display.
  String get formattedAddress {
    return [
      if (!_blank(flat)) '${isHouse ? 'House' : 'Flat'} ${flat!.trim()}',
      if (!isHouse && !_blank(block)) blockText(block!.trim()),
      if (!isHouse && !_blank(society)) society!.trim(),
      addressLine1,
      if (addressLine2 != null && addressLine2!.trim().isNotEmpty)
        addressLine2!,
      if (landmark.trim().isNotEmpty) landmark,
      city,
      state,
      postalCode,
    ].join(', ');
  }

  /// Converts the address into a SQLite-compatible map.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'area_id': areaId,
      'label': label,
      'recipient_name': recipientName,
      'phone_number': phoneNumber,
      'address_line_1': addressLine1,
      'address_line_2': addressLine2,
      'landmark': landmark,
      'city': city,
      'state': state,
      'postal_code': postalCode,
      'latitude': latitude,
      'longitude': longitude,
      'is_default': isDefault ? 1 : 0,
      // Only when set, so older upgrade steps that copy addresses run
      // before the v23 column exists.
      if (isBilling) 'is_billing': 1,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'society_id': societyId,
      'society_name': societyName,
      'society_other': societyOther,
      'block': block,
      'flat': flat,
      'is_house': isHouse ? 1 : 0,
      'delivery_note': deliveryNote,
    };
  }

  /// Restores a saved address from a SQLite record.
  factory CustomerAddress.fromMap(Map<String, Object?> map) {
    return CustomerAddress(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      areaId: map['area_id'] as String?,
      label: map['label'] as String,
      recipientName: map['recipient_name'] as String,
      phoneNumber: map['phone_number'] as String,
      addressLine1: map['address_line_1'] as String,
      addressLine2: map['address_line_2'] as String?,
      landmark: map['landmark'] as String,
      city: map['city'] as String,
      state: map['state'] as String,
      postalCode: map['postal_code'] as String,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      isDefault: (map['is_default'] as int) == 1,
      isBilling: (map['is_billing'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      societyId: map['society_id'] as String?,
      societyName: map['society_name'] as String?,
      societyOther: map['society_other'] as String?,
      block: map['block'] as String?,
      flat: map['flat'] as String?,
      isHouse: (map['is_house'] as int? ?? 0) == 1,
      deliveryNote: map['delivery_note'] as String?,
    );
  }
}
