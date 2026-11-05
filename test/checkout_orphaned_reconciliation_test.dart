import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/checkout_startup_recovery_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  late Directory directory;
  final service = MilkDatabaseService.instance;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_orphaned_checkout_',
    );

    service.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}checkout.db',
    );

    await service.database;
  });

  tearDown(() async {
    await service.close();
    service.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  Future<void> insertCompletedReconciliation(
    Database db, {
    required String orderId,
  }) async {
    await db.insert(MilkDatabaseService.checkoutReconciliationsTable, {
      'order_id': orderId,
      'cart_snapshot': '[]',
      'reconciliation_state': 'completed',
      'created_at': '2026-11-05T09:00:00',
      'completed_at': '2026-11-05T09:01:00',
    });
  }

  Future<void> insertSavedOrder(Database db, {required String orderId}) async {
    await db.insert(MilkDatabaseService.ordersTable, {
      'id': orderId,
      'created_at': '2026-11-05T09:00:00',
      'fulfillment_method': 'pickup',
      'payment_method': 'cashOnDelivery',
      'status': 'pending',
      'delivery_address': null,
      'notes': null,
      'subtotal': 100.0,
    });
  }

  test('Orphaned completed reconciliation blocks startup', () async {
    final db = await service.database;

    await insertCompletedReconciliation(db, orderId: 'orphan-order-001');

    final result = await CheckoutStartupRecoveryService.instance
        .inspectRecoveryState();

    expect(result.status, CheckoutRecoveryStatus.requiresManualRecovery);

    expect(result.orderId, 'orphan-order-001');

    // Inspection must not delete historical records.
    final rows = await db.query(
      MilkDatabaseService.checkoutReconciliationsTable,
    );

    expect(rows.length, 1);
    expect(rows.first['reconciliation_state'], 'completed');
  });

  test('Valid completed reconciliation permits normal startup', () async {
    final db = await service.database;

    await insertSavedOrder(db, orderId: 'valid-order-001');

    await insertCompletedReconciliation(db, orderId: 'valid-order-001');

    final result = await CheckoutStartupRecoveryService.instance
        .inspectRecoveryState();

    expect(result.status, CheckoutRecoveryStatus.noPendingCheckout);

    final rows = await db.query(
      MilkDatabaseService.checkoutReconciliationsTable,
    );

    expect(rows.length, 1);
  });

  test(
    'Orphaned reconciliation remains blocked on repeated inspection',
    () async {
      final db = await service.database;

      await insertCompletedReconciliation(db, orderId: 'orphan-order-002');

      final first = await CheckoutStartupRecoveryService.instance
          .inspectRecoveryState();

      final second = await CheckoutStartupRecoveryService.instance
          .inspectRecoveryState();

      expect(first.status, CheckoutRecoveryStatus.requiresManualRecovery);

      expect(second.status, CheckoutRecoveryStatus.requiresManualRecovery);

      expect(second.orderId, first.orderId);
    },
  );
}
