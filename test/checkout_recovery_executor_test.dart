import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/atomic_checkout_preparation_service.dart';
import 'package:sudhamrtam_customer_app/database/checkout_recovery_executor.dart';
import 'package:sudhamrtam_customer_app/database/checkout_reconciliation_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late Database db;

  final databaseService = MilkDatabaseService.instance;
  final preparationService = AtomicCheckoutPreparationService.instance;
  final recoveryExecutor = CheckoutRecoveryExecutor.instance;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'sudhamrtam_recovery_executor_',
    );

    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath:
          '${directory.path}${Platform.pathSeparator}recovery_executor.db',
    );

    db = await databaseService.database;
  });

  tearDown(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  CustomerOrder makeOrder(String id) {
    return CustomerOrder(
      id: id,
      createdAt: DateTime.utc(2026, 11, 5),
      fulfillmentMethod: FulfillmentMethod.pickup,
      paymentMethod: OrderPaymentMethod.cashOnDelivery,
      items: const [
        OrderItem(
          productId: 'buffalo_milk',
          productName: 'Buffalo Milk',
          unit: 'L',
          quantity: 2,
          unitPrice: 80,
        ),
      ],
    );
  }

  Future<void> seedCart({int quantity = 2}) async {
    await db.insert(MilkDatabaseService.cartItemsTable, {
      'product_id': 'buffalo_milk',
      'quantity': quantity,
    });
  }

  Future<void> saveOrder(CustomerOrder order) async {
    await db.transaction((txn) async {
      await txn.insert(MilkDatabaseService.ordersTable, order.toMap());

      for (final item in order.items) {
        await txn.insert(MilkDatabaseService.orderItemsTable, {
          'order_id': order.id,
          ...item.toMap(),
        });
      }
    });
  }

  Future<int> countRows(String table) async {
    final rows = await db.query(table);
    return rows.length;
  }

  test('no pending checkout allows normal startup', () async {
    final result = await recoveryExecutor.recoverAtStartup();

    expect(result.status, CheckoutRecoveryExecutionStatus.noRecoveryNeeded);

    expect(result.canContinueNormalStartup, isTrue);
  });

  test('unsaved prepared order remains untouched', () async {
    final order = makeOrder('recovery-unsaved');

    await seedCart();
    await preparationService.prepareCheckout(order);

    final result = await recoveryExecutor.recoverAtStartup();

    expect(result.status, CheckoutRecoveryExecutionStatus.awaitingSubmission);

    expect(result.canContinueNormalStartup, isFalse);

    expect(
      await countRows(MilkDatabaseService.pendingOrderSubmissionsTable),
      1,
    );

    expect(
      await countRows(MilkDatabaseService.checkoutReconciliationsTable),
      1,
    );

    expect(await countRows(MilkDatabaseService.cartItemsTable), 1);
  });

  test('saved order is reconciled and cleaned up', () async {
    final order = makeOrder('recovery-success');

    await seedCart();
    await preparationService.prepareCheckout(order);
    await saveOrder(order);

    final result = await recoveryExecutor.recoverAtStartup();

    expect(result.status, CheckoutRecoveryExecutionStatus.recovered);

    expect(result.canContinueNormalStartup, isTrue);

    expect(await countRows(MilkDatabaseService.cartItemsTable), 0);

    expect(
      await countRows(MilkDatabaseService.pendingOrderSubmissionsTable),
      0,
    );

    final reconciliation = await db.query(
      MilkDatabaseService.checkoutReconciliationsTable,
      where: 'order_id = ?',
      whereArgs: [order.id],
    );

    expect(reconciliation.length, 1);
    expect(reconciliation.first['reconciliation_state'], 'completed');

    expect(await countRows(MilkDatabaseService.ordersTable), 1);
  });

  test('recovery can be repeated safely', () async {
    final order = makeOrder('recovery-repeat');

    await seedCart();
    await preparationService.prepareCheckout(order);
    await saveOrder(order);

    final first = await recoveryExecutor.recoverAtStartup();
    final second = await recoveryExecutor.recoverAtStartup();

    expect(first.status, CheckoutRecoveryExecutionStatus.recovered);

    expect(second.status, CheckoutRecoveryExecutionStatus.noRecoveryNeeded);

    expect(await countRows(MilkDatabaseService.cartItemsTable), 0);

    expect(await countRows(MilkDatabaseService.ordersTable), 1);
  });

  test('changed cart blocks recovery without data loss', () async {
    final order = makeOrder('recovery-cart-conflict');

    await seedCart();
    await preparationService.prepareCheckout(order);
    await saveOrder(order);

    await db.update(
      MilkDatabaseService.cartItemsTable,
      {'quantity': 3},
      where: 'product_id = ?',
      whereArgs: ['buffalo_milk'],
    );

    final result = await recoveryExecutor.recoverAtStartup();

    expect(result.status, CheckoutRecoveryExecutionStatus.blocked);

    expect(result.canContinueNormalStartup, isFalse);

    final cart = await db.query(MilkDatabaseService.cartItemsTable);

    expect(cart.length, 1);
    expect(cart.first['quantity'], 3);

    expect(
      await countRows(MilkDatabaseService.pendingOrderSubmissionsTable),
      1,
    );

    final reconciliation = await db.query(
      MilkDatabaseService.checkoutReconciliationsTable,
      where: 'order_id = ?',
      whereArgs: [order.id],
    );

    expect(reconciliation.first['reconciliation_state'], 'pending');
  });

  test('incomplete records block recovery', () async {
    final order = makeOrder('recovery-incomplete');

    await seedCart();
    await preparationService.prepareCheckout(order);

    await db.delete(
      MilkDatabaseService.checkoutReconciliationsTable,
      where: 'order_id = ?',
      whereArgs: [order.id],
    );

    final result = await recoveryExecutor.recoverAtStartup();

    expect(result.status, CheckoutRecoveryExecutionStatus.blocked);

    expect(result.canContinueNormalStartup, isFalse);

    expect(
      await countRows(MilkDatabaseService.pendingOrderSubmissionsTable),
      1,
    );

    expect(await countRows(MilkDatabaseService.cartItemsTable), 1);
  });

  test('completed reconciliation only needs pending cleanup', () async {
    final order = makeOrder('recovery-cleanup');

    await seedCart();
    await preparationService.prepareCheckout(order);
    await saveOrder(order);

    await CheckoutReconciliationService.instance.reconcileSavedOrder(order.id);

    expect(
      await countRows(MilkDatabaseService.pendingOrderSubmissionsTable),
      1,
    );

    final result = await recoveryExecutor.recoverAtStartup();

    expect(result.status, CheckoutRecoveryExecutionStatus.recovered);

    expect(
      await countRows(MilkDatabaseService.pendingOrderSubmissionsTable),
      0,
    );

    expect(await countRows(MilkDatabaseService.cartItemsTable), 0);
  });

  test('failed pending cleanup blocks startup and remains retryable', () async {
    final order = makeOrder('recovery-cleanup-failure');

    await seedCart();
    await preparationService.prepareCheckout(order);
    await saveOrder(order);

    // Reconcile the saved order first, leaving pending cleanup.
    await CheckoutReconciliationService.instance.reconcileSavedOrder(order.id);

    // Simulate a SQLite failure during pending-submission deletion.
    await db.execute('''
    CREATE TRIGGER reject_pending_cleanup
    BEFORE DELETE ON ${MilkDatabaseService.pendingOrderSubmissionsTable}
    BEGIN
      SELECT RAISE(
        ABORT,
        'Simulated pending cleanup failure'
      );
    END
  ''');

    final failedResult = await recoveryExecutor.recoverAtStartup();

    expect(failedResult.status, CheckoutRecoveryExecutionStatus.blocked);
    expect(failedResult.canContinueNormalStartup, isFalse);

    // The saved order must still exist.
    expect(await countRows(MilkDatabaseService.ordersTable), 1);

    // Reconciliation must remain completed.
    final reconciliations = await db.query(
      MilkDatabaseService.checkoutReconciliationsTable,
      where: 'order_id = ?',
      whereArgs: [order.id],
    );

    expect(reconciliations.length, 1);
    expect(reconciliations.first['reconciliation_state'], 'completed');

    // The cart must remain empty, not be restored.
    expect(await countRows(MilkDatabaseService.cartItemsTable), 0);

    // The pending record remains available for a later retry.
    expect(
      await countRows(MilkDatabaseService.pendingOrderSubmissionsTable),
      1,
    );

    // Remove the simulated failure and retry.
    await db.execute('DROP TRIGGER reject_pending_cleanup');

    final retryResult = await recoveryExecutor.recoverAtStartup();

    expect(retryResult.status, CheckoutRecoveryExecutionStatus.recovered);
    expect(retryResult.canContinueNormalStartup, isTrue);

    expect(
      await countRows(MilkDatabaseService.pendingOrderSubmissionsTable),
      0,
    );

    expect(await countRows(MilkDatabaseService.cartItemsTable), 0);

    expect(await countRows(MilkDatabaseService.ordersTable), 1);
  });
}
