import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/catalog_cache_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/features/checkout/checkout_validator.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/catalog_repository.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/product_catalog.dart';

CatalogProductData item(
  String id,
  int pricePaise, {
  String category = 'Fresh Dairy',
  String unit = '1 L',
  bool available = true,
}) {
  return CatalogProductData(
    id: id,
    name: id,
    category: category,
    description: '',
    unitLabel: unit,
    pricePaise: pricePaise,
    isAvailable: available,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  final databaseService = MilkDatabaseService.instance;
  final cache = CatalogCacheService.instance;

  late Directory directory;
  late Database db;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sudhamrtam_catalog_');

    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}catalog.db',
    );

    db = await databaseService.database;
  });

  tearDown(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  Future<void> cacheNizampet() async {
    await cache.saveCatalog(
      CachedCatalog(
        areaId: 'nizampet',
        areaName: 'Nizampet',
        fetchedAt: DateTime.utc(2026, 11, 6, 9),
        products: [
          item('buffalo_milk', 8500),
          item('cow_milk', 9000),
          item('paneer', 80000, unit: '1 kg'),
        ],
      ),
    );
    await cache.setSelectedAreaId('nizampet');
  }

  group('CatalogCacheService', () {
    test('Round-trips a catalog with exact paise', () async {
      await cacheNizampet();

      final loaded = await cache.loadCatalog('nizampet');

      expect(loaded!.areaName, 'Nizampet');
      expect(loaded.products.map((p) => p.pricePaise), [8500, 9000, 80000]);
      expect(await cache.loadCatalog('unknown_area'), isNull);
      expect(await cache.getSelectedAreaId(), 'nizampet');
    });

    test('Saving an area again replaces its catalog', () async {
      await cacheNizampet();

      await cache.saveCatalog(
        CachedCatalog(
          areaId: 'nizampet',
          areaName: 'Nizampet',
          fetchedAt: DateTime.utc(2026, 11, 7),
          products: [item('cow_milk', 9500)],
        ),
      );

      final loaded = await cache.loadCatalog('nizampet');
      expect(loaded!.products.single.pricePaise, 9500);
      expect((await cache.loadAllCatalogs()), hasLength(1));
    });

    test('Rejects products without a positive price', () {
      expect(
        () => CatalogProductData.fromJson({
          'id': 'cow_milk',
          'name': 'Cow Milk',
          'category': 'Fresh Dairy',
          'unit_label': '1 L',
          'price_paise': 0,
        }),
        throwsFormatException,
      );
    });
  });

  group('CatalogRepository', () {
    test('Uses the built-in catalog when nothing is cached', () async {
      final repository = CatalogRepository();
      await repository.initialize();

      expect(repository.source, CatalogSource.builtIn);
      expect(repository.products, ProductCatalog.products);
      expect(repository.productById('cow_milk')?.price, 85.0);
    });

    test('Uses the cached catalog of the selected area', () async {
      await cacheNizampet();

      final repository = CatalogRepository();
      await repository.initialize();

      expect(repository.source, CatalogSource.cached);
      expect(repository.selectedAreaName, 'Nizampet');
      expect(repository.products.map((p) => p.id), [
        'buffalo_milk',
        'cow_milk',
        'paneer',
      ]);
      expect(repository.productById('cow_milk')?.price, 90.0);
      expect(repository.productById('paneer')?.isAvailable, isTrue);
    });

    test('Known products not sold in the area are unavailable', () async {
      await cacheNizampet();

      final repository = CatalogRepository();
      await repository.initialize();

      final coconut = repository.productById('coconut_oil');
      expect(coconut, isNotNull);
      expect(coconut!.isAvailable, isFalse);

      expect(repository.productById('never_seen'), isNull);
    });

    test('Falls back to built-in when the cache cannot be read', () async {
      await db.execute('DROP TABLE ${MilkDatabaseService.catalogCacheTable}');

      final repository = CatalogRepository();
      await repository.initialize();

      expect(repository.source, CatalogSource.builtIn);
      expect(repository.products, ProductCatalog.products);
    });
  });

  group('Cart with catalog lookup', () {
    test('Saved items outside the area are kept but block checkout', () async {
      await cacheNizampet();

      await db.insert(MilkDatabaseService.cartItemsTable, {
        'product_id': 'cow_milk',
        'quantity': 2,
      });
      await db.insert(MilkDatabaseService.cartItemsTable, {
        'product_id': 'coconut_oil',
        'quantity': 1,
      });
      await db.insert(MilkDatabaseService.cartItemsTable, {
        'product_id': 'retired_product',
        'quantity': 1,
      });

      final repository = CatalogRepository();
      await repository.initialize();

      final cart = CartManager(productLookup: repository.productById);
      await cart.initialize();

      // Nothing is silently dropped.
      expect(cart.items.map((i) => i.product.id).toSet(), {
        'cow_milk',
        'coconut_oil',
        'retired_product',
      });

      // Area price applies to available products.
      expect(
        cart.items.firstWhere((i) => i.product.id == 'cow_milk').product.price,
        90.0,
      );

      // Unavailable products cannot be increased...
      expect(cart.increaseQuantity('coconut_oil'), isFalse);
      // ...but can be removed.
      expect(cart.updateQuantity('retired_product', 0), isTrue);

      final validation = CheckoutValidator.validate(
        cart: cart,
        fulfillmentMethod: FulfillmentMethod.pickup,
        paymentMethod: OrderPaymentMethod.cashOnDelivery,
      );

      expect(validation.isValid, isFalse);
      expect(
        validation.errors.single,
        contains('not available in your delivery area'),
      );

      await cart.waitForPendingSaves();
      cart.dispose();
    });

    test('Unavailable products cannot be added', () async {
      await cacheNizampet();

      final repository = CatalogRepository();
      await repository.initialize();

      final cart = CartManager(productLookup: repository.productById);
      await cart.initialize();

      expect(cart.addProduct(repository.productById('coconut_oil')!), isFalse);
      expect(cart.addProduct(repository.productById('paneer')!), isTrue);

      await cart.waitForPendingSaves();
      cart.dispose();
    });
  });
}
