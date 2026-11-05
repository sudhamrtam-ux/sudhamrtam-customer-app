/// Represents the locally stored Sudhamrtam customer profile.
///
/// Phone numbers stored here are not considered verified.
/// OTP authentication will be integrated separately.
class CustomerProfile {
  final String id;
  final String fullName;
  final String? phoneNumber;
  final String? email;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomerProfile({
    required this.id,
    required this.fullName,
    this.phoneNumber,
    this.email,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates a modified copy of the profile.
  CustomerProfile copyWith({
    String? fullName,
    String? phoneNumber,
    String? email,
    DateTime? updatedAt,
  }) {
    return CustomerProfile(
      id: id,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Converts this profile into a SQLite-compatible map.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'email': email,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Restores a customer profile from SQLite.
  factory CustomerProfile.fromMap(Map<String, Object?> map) {
    return CustomerProfile(
      id: map['id'] as String,
      fullName: map['full_name'] as String,
      phoneNumber: map['phone_number'] as String?,
      email: map['email'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
