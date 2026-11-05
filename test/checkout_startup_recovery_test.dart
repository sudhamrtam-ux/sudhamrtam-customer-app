import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/checkout_startup_recovery_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late Database db;

  final databaseService = MilkDatabaseService.instance;
  final recoveryService = CheckoutStartupRecoveryService.instance;

  const orderId = 'startup-recovery-test-order';
  final now = DateTime.utc(2026, 11, 5).toIso8601String();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_startup_recovery_',
    );

    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath:
          '${directory.path}${Platform.pathSeparator}startup_recovery.db',
    );

    db = await databaseService.database;
  });

  tearDown(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  Future<void> seedPendingSubmission() async {
    await db.insert(MilkDatabaseService.pendingOrderSubmissionsTable, {
      'order_id': orderId,
      'created_at': now,
      'order_payload': '{}',
      'submission_state': 'prepared',
      'updated_at': now,
    });
  }

  Future<void> seedReconciliation({String state = 'pending'}) async {
    await db.insert(MilkDatabaseService.checkoutReconciliationsTable, {
      'order_id': orderId,
      'cart_snapshot': '{"buffalo_milk":2}',
      'reconciliation_state': state,
      'created_at': now,
      'completed_at': state == 'completed' ? now : null,
    });
  }

  Future<void> seedSavedOrder() async {
    await db.insert(MilkDatabaseService.ordersTable, {
      'id': orderId,
      'created_at': now,
      'fulfillment_method': 'pickup',
      'payment_method': 'cashOnDelivery',
      'status': 'pending',
      'delivery_address': null,
      'notes': null,
      'subtotal': 160.0,
    });
  }

  test('no records means no pending checkout', () async {
    final result = await recoveryService.inspectRecoveryState();

    expect(result.status, CheckoutRecoveryStatus.noPendingCheckout);
    expect(result.orderId, isNull);
    expect(result.hasUnresolvedCheckout, isFalse);
  });

  test('prepared order without saved order awaits submission', () async {
    await seedPendingSubmission();
    await seedReconciliation();

    final result = await recoveryService.inspectRecoveryState();

    expect(result.status, CheckoutRecoveryStatus.awaitingOrderSubmission);
    expect(result.orderId, orderId);
    expect(result.hasUnresolvedCheckout, isTrue);
  });

  test('saved order awaiting reconciliation is detected', () async {
    await seedPendingSubmission();
    await seedReconciliation();
    await seedSavedOrder();

    final result = await recoveryService.inspectRecoveryState();

    expect(result.status, CheckoutRecoveryStatus.needsCartReconciliation);
    expect(result.orderId, orderId);
  });

  test('completed reconciliation awaiting cleanup is detected', () async {
    await seedPendingSubmission();
    await seedReconciliation(state: 'completed');
    await seedSavedOrder();

    final result = await recoveryService.inspectRecoveryState();

    expect(result.status, CheckoutRecoveryStatus.needsPendingCleanup);
    expect(result.orderId, orderId);
  });

  test('missing reconciliation requires manual recovery', () async {
    await seedPendingSubmission();

    final result = await recoveryService.inspectRecoveryState();

    expect(result.status, CheckoutRecoveryStatus.requiresManualRecovery);
    expect(result.orderId, orderId);
  });

  test('orphaned pending reconciliation requires manual recovery', () async {
    await seedReconciliation();

    final result = await recoveryService.inspectRecoveryState();

    expect(result.status, CheckoutRecoveryStatus.requiresManualRecovery);
    expect(result.hasUnresolvedCheckout, isTrue);
  });
}
