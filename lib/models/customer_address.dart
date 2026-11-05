/// Represents a locally saved customer delivery address.
///
/// Addresses belong to a local customer profile.
/// Authentication and server synchronization will be
/// integrated in a later milestone.
class CustomerAddress {
  final String id;
  final String customerId;
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
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomerAddress({
    required this.id,
    required this.customerId,
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
    required this.createdAt,
    required this.updatedAt,
  });

  /// True when a complete coordinate pair is available.
  bool get hasMapLocation => latitude != null && longitude != null;

  /// Creates a modified copy of the address.
  ///
  /// Nullable fields use explicit clear flags so they
  /// can be removed without affecting other properties.
  CustomerAddress copyWith({
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
    DateTime? updatedAt,
  }) {
    return CustomerAddress(
      id: id,
      customerId: customerId,
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
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Returns the formatted address for display.
  String get formattedAddress {
    return [
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
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Restores a saved address from a SQLite record.
  factory CustomerAddress.fromMap(Map<String, Object?> map) {
    return CustomerAddress(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
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
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
