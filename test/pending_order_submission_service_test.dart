import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/pending_order_submission_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

// ==========================================
// TEST ORDER FACTORY
// ==========================================

CustomerOrder createTestOrder(String id) {
  return CustomerOrder(
    id: id,
    createdAt: DateTime.utc(2026, 11, 5, 8, 0),
    items: [
      const OrderItem(
        productId: 'buffalo_milk',
        productName: 'Buffalo Milk',
        unit: '1 L',
        quantity: 2,
        unitPrice: 100,
      ),
      const OrderItem(
        productId: 'cow_milk',
        productName: 'Cow Milk',
        unit: '1 L',
        quantity: 1,
        unitPrice: 80,
      ),
    ],
    fulfillmentMethod: FulfillmentMethod.delivery,
    paymentMethod: OrderPaymentMethod.cashOnDelivery,
    deliveryAddress: 'Kukatpally, Hyderabad',
    notes: 'Leave at the gate',
  );
}

// ==========================================
// AUTOMATED SQLITE TESTS
// ==========================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();

  final databaseService = MilkDatabaseService.instance;
  final pendingService = PendingOrderSubmissionService.instance;

  late Directory testDirectory;

  setUpAll(() async {
    testDirectory = await Directory.systemTemp.createTemp(
      'sudhamrtam_pending_orders_',
    );

    final databasePath =
        '${testDirectory.path}${Platform.pathSeparator}pending_test.db';

    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );

    await databaseService.database;
  });

  tearDownAll(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await testDirectory.delete(recursive: true);
  });

  group('Sudhamrtam Pending Order Recovery', () {
    test('Saves and recovers a prepared order', () async {
      final original = createTestOrder('PENDING-001');

      await pendingService.savePreparedOrder(original);

      final recovered = await pendingService.getPendingOrder();

      expect(recovered, isNotNull);
      expect(recovered!.id, original.id);
      expect(recovered.items.length, 2);
      expect(recovered.totalQuantity, 3);
      expect(recovered.subtotal, 280.0);
      expect(recovered.deliveryAddress, 'Kukatpally, Hyderabad');
      expect(recovered.notes, 'Leave at the gate');

      expect(
        await pendingService.getSubmissionState(original.id),
        PendingOrderSubmissionService.prepared,
      );
    });

    test('Allows saving the same prepared order again', () async {
      final order = createTestOrder('PENDING-001');

      await pendingService.savePreparedOrder(order);

      final db = await databaseService.database;

      final rows = await db.query(
        MilkDatabaseService.pendingOrderSubmissionsTable,
      );

      expect(rows.length, 1);
    });

    test('Rejects a different order while one is pending', () async {
      await expectLater(
        pendingService.savePreparedOrder(createTestOrder('PENDING-002')),
        throwsStateError,
      );

      final recovered = await pendingService.getPendingOrder();

      expect(recovered!.id, 'PENDING-001');
    });

    test('Marks a pending order as uncertain', () async {
      await pendingService.markUncertain('PENDING-001');

      expect(
        await pendingService.getSubmissionState('PENDING-001'),
        PendingOrderSubmissionService.uncertain,
      );
    });

    test('Rejects marking an unknown order as uncertain', () async {
      await expectLater(
        pendingService.markUncertain('UNKNOWN-ORDER'),
        throwsStateError,
      );
    });

    test('Recovers the pending order after database reopening', () async {
      await databaseService.close();

      final reopened = await pendingService.getPendingOrder();

      expect(reopened, isNotNull);
      expect(reopened!.id, 'PENDING-001');

      expect(
        await pendingService.getSubmissionState('PENDING-001'),
        PendingOrderSubmissionService.uncertain,
      );
    });

    test('Deletes a resolved pending order', () async {
      await pendingService.deletePendingOrder('PENDING-001');

      expect(await pendingService.getPendingOrder(), isNull);
      expect(await pendingService.getSubmissionState('PENDING-001'), isNull);
    });

    test('Allows a new order after the previous one is resolved', () async {
      final order = createTestOrder('PENDING-003');

      await pendingService.savePreparedOrder(order);

      final recovered = await pendingService.getPendingOrder();

      expect(recovered!.id, order.id);

      await pendingService.deletePendingOrder(order.id);
    });
  });
}
