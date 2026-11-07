import 'dart:async';

/// The signed-in customer, as far as the app needs to know.
class AuthUser {
  final String uid;
  final String? phoneNumber;

  const AuthUser({required this.uid, this.phoneNumber});
}

/// Result of asking for an OTP.
sealed class PhoneCodeRequest {
  const PhoneCodeRequest();
}

/// The OTP was sent; the customer must type it.
class PhoneCodeSent extends PhoneCodeRequest {
  final String verificationId;
  final int? resendToken;

  const PhoneCodeSent(this.verificationId, this.resendToken);
}

/// The customer was signed in without typing a code (not used
/// by the backend login today; kept for future providers).
class PhoneAutoVerified extends PhoneCodeRequest {
  final AuthUser user;

  const PhoneAutoVerified(this.user);
}

/// A login problem, with a message fit to show the customer.
class PhoneAuthException implements Exception {
  final String message;
  const PhoneAuthException(this.message);

  @override
  String toString() => message;
}

/// Phone-number login. Screens depend on this interface, so
/// they can be tested with a fake. The real implementation is
/// ApiPhoneAuthGateway (the Sudhamrtam backend sends the code).
abstract class PhoneAuthGateway {
  AuthUser? get currentUser;

  Stream<AuthUser?> authStateChanges();

  /// Sends an OTP to [phoneE164] (e.g. +919999900001).
  /// [PhoneCodeSent.verificationId] identifies that code.
  Future<PhoneCodeRequest> requestCode(String phoneE164, {int? resendToken});

  Future<AuthUser> confirmCode(String verificationId, String smsCode);

  Future<void> signOut();
}

/// Normalises an Indian mobile number to E.164 (+91XXXXXXXXXX).
///
/// Accepts 10 digits, optionally with spaces, dashes, a leading
/// 0, or a +91/91 prefix. Returns null if it is not a valid
/// Indian mobile number (must start with 6–9).
String? normaliseIndianMobile(String input) {
  var digits = input.replaceAll(RegExp(r'[\s\-()]'), '');

  if (digits.startsWith('+91')) {
    digits = digits.substring(3);
  } else if (digits.length == 12 && digits.startsWith('91')) {
    digits = digits.substring(2);
  } else if (digits.length == 11 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }

  if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) return null;

  return '+91$digits';
}
