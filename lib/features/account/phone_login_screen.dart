import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/phone_auth_service.dart';

const _green = Color(0xFF82B440);

/// Two-step phone login: enter number, then the OTP.
///
/// Pops with `true` once the customer is signed in.
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key, required this.auth});

  final PhoneAuthGateway auth;

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  StreamSubscription<AuthUser?>? _authSubscription;

  String? _phoneE164;
  PhoneCodeSent? _codeSent;
  bool _busy = false;
  String? _error;
  bool _finished = false;

  @override
  void initState() {
    super.initState();

    // Closes the screen however the sign-in completes.
    _authSubscription = widget.auth.authStateChanges().listen((user) {
      if (user != null) _finish();
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    Navigator.of(context).pop(true);
  }

  Future<void> _requestCode({bool resend = false}) async {
    final phone = resend
        ? _phoneE164
        : normaliseIndianMobile(_phoneController.text);

    if (phone == null) {
      setState(() => _error = 'Enter a valid 10-digit Indian mobile number.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await widget.auth.requestCode(
        phone,
        resendToken: resend ? _codeSent?.resendToken : null,
      );

      if (!mounted) return;

      switch (result) {
        case PhoneAutoVerified():
          _finish();
        case PhoneCodeSent():
          setState(() {
            _phoneE164 = phone;
            _codeSent = result;
            _codeController.clear();
          });
      }
    } on PhoneAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCode() async {
    final codeSent = _codeSent;
    final code = _codeController.text.trim();

    if (codeSent == null) return;

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.auth.confirmCode(codeSent.verificationId, code);
      _finish();
    } on PhoneAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeNumber() {
    setState(() {
      _codeSent = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enteringCode = _codeSent != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.phone_iphone, size: 64, color: _green),
            const SizedBox(height: 16),
            Text(
              enteringCode ? 'Enter the code' : 'Sign in with your phone',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              enteringCode
                  ? 'We sent a 6-digit code to $_phoneE164.'
                  : 'We will send you a one-time code.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 24),
            if (!enteringCode)
              TextField(
                key: const Key('phoneField'),
                controller: _phoneController,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\s+\-]')),
                  LengthLimitingTextInputFormatter(16),
                ],
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  prefixText: '+91 ',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _requestCode(),
              )
            else
              TextField(
                key: const Key('codeField'),
                controller: _codeController,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: '6-digit code',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _confirmCode(),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy
                  ? null
                  : (enteringCode ? _confirmCode : _requestCode),
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(enteringCode ? 'Verify and sign in' : 'Send code'),
            ),
            if (enteringCode) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _busy ? null : _changeNumber,
                    child: const Text('Change number'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _requestCode(resend: true),
                    child: const Text('Resend code'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
