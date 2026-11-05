import '../database/checkout_recovery_executor.dart';

typedef StartupRecoveryCallback =
    Future<CheckoutRecoveryExecutionResult> Function();

typedef StartupCartInitializationCallback = Future<void> Function();

/// Coordinates checkout recovery and cart initialization.
///
/// Recovery must succeed before the customer cart can be initialized.
///
/// Dependencies are injected through callbacks so startup behavior
/// can be tested without accessing the production database.
class CheckoutStartupController {
  final StartupRecoveryCallback _recover;
  final StartupCartInitializationCallback _initializeCart;

  bool _isBusy = false;
  bool _isReady = false;
  bool _recoveryAuthorized = false;

  CheckoutRecoveryExecutionResult? _lastResult;

  /// Uses initializing formals to assign the private fields directly.
  ///
  /// This resolves the prefer_initializing_formals lint warnings.
  // ignore: prefer_initializing_formals
  CheckoutStartupController({
    required StartupRecoveryCallback recover,
    required StartupCartInitializationCallback initializeCart,
  }) : _recover = recover, // ignore: prefer_initializing_formals
       _initializeCart = initializeCart; // ignore: prefer_initializing_formals

  bool get isBusy => _isBusy;

  bool get isReady => _isReady;

  CheckoutRecoveryExecutionResult? get lastResult => _lastResult;

  /// Performs the initial startup sequence.
  ///
  /// The cart is initialized only after recovery succeeds.
  Future<CheckoutRecoveryExecutionResult> start() async {
    if (_isBusy) {
      throw StateError('Startup is already in progress.');
    }

    if (_isReady) {
      return _lastResult ??
          const CheckoutRecoveryExecutionResult(
            status: CheckoutRecoveryExecutionStatus.noRecoveryNeeded,
            orderId: null,
            message: 'Startup already completed.',
          );
    }

    _isBusy = true;

    try {
      final result = await _runRecovery();

      if (!result.canContinueNormalStartup) {
        return result;
      }

      return await _initializeAfterRecovery();
    } finally {
      _isBusy = false;
    }
  }

  /// Retries checkout recovery after a blocked startup.
  ///
  /// Cart initialization is deliberately separate.
  /// The recovery gate calls completeStartup() only after
  /// a successful recovery result.
  Future<CheckoutRecoveryExecutionResult> retryRecovery() async {
    if (_isBusy) {
      throw StateError('Startup operation is already in progress.');
    }

    if (_isReady) {
      throw StateError('Startup has already completed.');
    }

    _isBusy = true;

    try {
      return await _runRecovery();
    } finally {
      _isBusy = false;
    }
  }

  /// Completes startup by initializing the customer cart.
  ///
  /// This operation is permitted only after recovery
  /// has returned a safe result.
  Future<void> completeStartup() async {
    if (_isBusy) {
      throw StateError('Startup operation is already in progress.');
    }

    if (_isReady) {
      return;
    }

    if (!_recoveryAuthorized) {
      throw StateError(
        'Cart initialization is blocked until checkout recovery succeeds.',
      );
    }

    _isBusy = true;

    try {
      final result = await _initializeAfterRecovery();

      if (!result.canContinueNormalStartup) {
        throw StateError(result.message);
      }
    } finally {
      _isBusy = false;
    }
  }

  /// Executes recovery and records whether startup is safe.
  Future<CheckoutRecoveryExecutionResult> _runRecovery() async {
    // A new inspection invalidates any previous authorization.
    _recoveryAuthorized = false;

    try {
      final result = await _recover();

      _lastResult = result;

      _recoveryAuthorized = result.canContinueNormalStartup;

      return result;
    } catch (error) {
      final result = CheckoutRecoveryExecutionResult(
        status: CheckoutRecoveryExecutionStatus.blocked,
        orderId: null,
        message: 'Startup recovery failed: $error',
      );

      _lastResult = result;

      return result;
    }
  }

  /// Initializes the cart after successful recovery.
  ///
  /// A failed initialization leaves the application blocked.
  Future<CheckoutRecoveryExecutionResult> _initializeAfterRecovery() async {
    if (!_recoveryAuthorized) {
      throw StateError('Cannot initialize cart before successful recovery.');
    }

    try {
      await _initializeCart();

      _isReady = true;

      return _lastResult ??
          const CheckoutRecoveryExecutionResult(
            status: CheckoutRecoveryExecutionStatus.noRecoveryNeeded,
            orderId: null,
            message: 'Startup completed.',
          );
    } catch (error) {
      _isReady = false;
      _recoveryAuthorized = false;

      final result = CheckoutRecoveryExecutionResult(
        status: CheckoutRecoveryExecutionStatus.blocked,
        orderId: _lastResult?.orderId,
        message: 'Shopping cart initialization failed: $error',
      );

      _lastResult = result;

      return result;
    }
  }
}
