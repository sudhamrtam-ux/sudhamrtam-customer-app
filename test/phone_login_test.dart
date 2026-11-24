import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/account/account_screen.dart';
import 'package:sudhamrtam_customer_app/features/account/phone_login_screen.dart';
import 'package:sudhamrtam_customer_app/services/phone_auth_service.dart';

/// In-memory login that accepts code 123456.
class FakePhoneAuth implements PhoneAuthGateway {
  final _changes = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;

  final List<String> requestedNumbers = [];
  PhoneAuthException? failNextRequest;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> authStateChanges() => _changes.stream;

  @override
  Future<PhoneCodeRequest> requestCode(
    String phoneE164, {
    int? resendToken,
  }) async {
    requestedNumbers.add(phoneE164);
    final failure = failNextRequest;
    if (failure != null) {
      failNextRequest = null;
      throw failure;
    }
    return const PhoneCodeSent('verification-1', 7);
  }

  @override
  Future<AuthUser> confirmCode(String verificationId, String smsCode) async {
    if (smsCode != '123456') {
      throw const PhoneAuthException('The code is incorrect.');
    }
    _user = AuthUser(uid: 'uid-1', phoneNumber: requestedNumbers.last);
    _changes.add(_user);
    return _user!;
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _changes.add(null);
  }
}

void main() {
  group('normaliseIndianMobile', () {
    test('accepts common Indian formats', () {
      for (final input in [
        '9999900001',
        '99999 00001',
        '+91 99999 00001',
        '919999900001',
        '09999900001',
        '99999-00001',
      ]) {
        expect(normaliseIndianMobile(input), '+919999900001', reason: input);
      }
    });

    test('rejects invalid numbers', () {
      for (final input in ['', '12345', '5999900001', '99999000011', 'abc']) {
        expect(normaliseIndianMobile(input), isNull, reason: input);
      }
    });
  });

  group('Phone login', () {
    late FakePhoneAuth auth;

    setUp(() => auth = FakePhoneAuth());

    testWidgets('Account lists the policy pages, refunds and contact too', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AccountScreen(auth: auth)),
        ),
      );
      await tester.pump();
      for (final title in [
        'Privacy Policy',
        'Terms of Use',
        'Refunds and Cancellations',
        'Contact us',
      ]) {
        await tester.scrollUntilVisible(find.text(title), 200);
        expect(find.text(title), findsOneWidget);
      }
    });

    Future<void> openLogin(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AccountScreen(auth: auth)),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Sign in with phone'));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneLoginScreen), findsOneWidget);
    }

    testWidgets('Signs in with a number and the correct code', (tester) async {
      await openLogin(tester);

      await tester.enterText(
        find.byKey(const Key('phoneField')),
        '99999 00001',
      );
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      expect(auth.requestedNumbers, ['+919999900001']);
      expect(find.text('We sent a 6-digit code to +919999900001.'), findsOne);

      await tester.enterText(find.byKey(const Key('codeField')), '123456');
      await tester.tap(find.text('Verify and sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(PhoneLoginScreen), findsNothing);
      expect(find.text('Signed in as +919999900001'), findsOneWidget);
    });

    testWidgets('A wrong code shows an error and stays on the screen', (
      tester,
    ) async {
      await openLogin(tester);

      await tester.enterText(find.byKey(const Key('phoneField')), '9999900001');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('codeField')), '000000');
      await tester.tap(find.text('Verify and sign in'));
      await tester.pumpAndSettle();

      expect(find.text('The code is incorrect.'), findsOneWidget);
      expect(find.byType(PhoneLoginScreen), findsOneWidget);
    });

    testWidgets('An invalid number is rejected before contacting Firebase', (
      tester,
    ) async {
      await openLogin(tester);

      await tester.enterText(find.byKey(const Key('phoneField')), '12345');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      expect(auth.requestedNumbers, isEmpty);
      expect(
        find.text('Enter a valid 10-digit Indian mobile number.'),
        findsOneWidget,
      );
    });

    testWidgets('A send failure is shown to the customer', (tester) async {
      auth.failNextRequest = const PhoneAuthException(
        'Too many attempts. Please wait a while and try again.',
      );

      await openLogin(tester);

      await tester.enterText(find.byKey(const Key('phoneField')), '9999900001');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Too many attempts'), findsOneWidget);
      expect(find.byKey(const Key('phoneField')), findsOneWidget);
    });

    testWidgets('Sign out returns to the sign-in option', (tester) async {
      await openLogin(tester);

      await tester.enterText(find.byKey(const Key('phoneField')), '9999900001');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('codeField')), '123456');
      await tester.tap(find.text('Verify and sign in'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in with phone'), findsOneWidget);
    });
  });
}
