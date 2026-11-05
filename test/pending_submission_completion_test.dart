import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/pending_order_submission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
  });

  test('Pending submission completes only after reconciliation', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_pending_completion_',
    );

    final databasePath =
        '${directory.path}${Platform.pathSeparator}completion.db';

    final databaseService = MilkDatabaseService.instance;
    final pendingService = PendingOrderSubmissionService.instance;

    var configured = false;

    const orderId = 'completion-test-order';
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      databaseService.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      configured = true;

      final db = await databaseService.database;

      // Create a pending submission.
      await db.insert(MilkDatabaseService.pendingOrderSubmissionsTable, {
        'order_id': orderId,
        'created_at': now,
        'order_payload': '{}',
        'submission_state': 'prepared',
        'updated_at': now,
      });

      // Cannot complete without a saved order.
      await expectLater(
        pendingService.completeReconciledSubmission(orderId),
        throwsA(isA<StateError>()),
      );

      expect(await pendingService.getSubmissionState(orderId), 'prepared');

      // Create a valid saved order header for this test.
      await db.insert(MilkDatabaseService.ordersTable, {
        'id': orderId,
        'created_at': now,
        'fulfillment_method': 'pickup',
        'payment_method': 'cashOnDelivery',
        'status': 'pending',
        'delivery_address': null,
        'notes': null,
        'subtotal': 100.0,
      });

      // Cannot complete without a reconciliation record.
      await expectLater(
        pendingService.completeReconciledSubmission(orderId),
        throwsA(isA<StateError>()),
      );

      // Add a reconciliation record that is still pending.
      await db.insert(MilkDatabaseService.checkoutReconciliationsTable, {
        'order_id': orderId,
        'cart_snapshot': '{"buffalo_milk":1}',
        'reconciliation_state': 'pending',
        'created_at': now,
        'completed_at': null,
      });

      await expectLater(
        pendingService.completeReconciledSubmission(orderId),
        throwsA(isA<StateError>()),
      );

      expect(await pendingService.getSubmissionState(orderId), 'prepared');

      // Mark reconciliation completed.
      await db.update(
        MilkDatabaseService.checkoutReconciliationsTable,
        {'reconciliation_state': 'completed', 'completed_at': now},
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      // Pending submission may now be removed.
      final completed = await pendingService.completeReconciledSubmission(
        orderId,
      );

      expect(completed, isTrue);
      expect(await pendingService.getSubmissionState(orderId), isNull);

      // Repeating completion must not delete anything else.
      final repeated = await pendingService.completeReconciledSubmission(
        orderId,
      );

      expect(repeated, isFalse);

      // The saved order and reconciliation remain intact.
      final orderRows = await db.query(
        MilkDatabaseService.ordersTable,
        where: 'id = ?',
        whereArgs: [orderId],
      );

      expect(orderRows.length, 1);

      final reconciliationRows = await db.query(
        MilkDatabaseService.checkoutReconciliationsTable,
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      expect(reconciliationRows.length, 1);
      expect(reconciliationRows.first['reconciliation_state'], 'completed');

      final integrity = await db.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first, 'ok');
    } finally {
      if (configured) {
        await databaseService.close();
        databaseService.resetTestingConfiguration();
      }

      await directory.delete(recursive: true);
    }
  });
}
