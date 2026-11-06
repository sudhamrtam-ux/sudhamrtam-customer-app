import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/catalog_cache_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/catalog_repository.dart';
import 'package:sudhamrtam_customer_app/services/catalog_api_client.dart';

Map<String, Object?> product(String id, int paise, {bool available = true}) => {
  'id': id,
  'name': id,
  'category': 'Fresh Dairy',
  'description': '',
  'unit_label': '1 L',
  'image_path': null,
  'price_paise': paise,
  'is_available': available,
};

/// The server's catalog, editable by each test.
var serverProducts = <Map<String, Object?>>[];
var catalogRequests = 0;

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

MockClient fakeServer() {
  return MockClient((request) async {
    if (request.url.path == '/v1/catalog') {
      catalogRequests++;
      return json({'products': serverProducts});
    }
    return json({'error': 'NOT_FOUND'}, 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  final databaseService = MilkDatabaseService.instance;

  late Directory directory;
  late Database db;

  setUp(() async {
    serverProducts = [
      product('buffalo_milk', 9000),
      product('cow_milk', 9000),
      product('paneer', 80000),
    ];
    catalogRequests = 0;

    directory = await Directory.systemTemp.createTemp('sudhamrtam_sync_');
    databaseService.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}sync.db',
    );
    db = await databaseService.database;
  });

  tearDown(() async {
    await databaseService.close();
    databaseService.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  CatalogRepository repositoryWith(http.Client client) {
    return CatalogRepository(
      api: CatalogApiClient(baseUrl: 'http://test.local', httpClient: client),
    );
  }

  group('CatalogApiClient', () {
    test('Parses the catalog', () async {
      final api = CatalogApiClient(
        baseUrl: 'http://test.local',
        httpClient: fakeServer(),
      );

      final products = await api.fetchCatalog();
      expect(products.map((p) => p.pricePaise), [9000, 9000, 80000]);
    });

    test('Turns server problems into CatalogApiException', () async {
      Future<void> expectFailure(http.Client client) async {
        final api = CatalogApiClient(
          baseUrl: 'http://test.local',
          httpClient: client,
        );
        await expectLater(
          api.fetchCatalog(),
          throwsA(isA<CatalogApiException>()),
        );
      }

      await expectFailure(MockClient((_) async => json({}, 500)));
      await expectFailure(
        MockClient((_) async => http.Response('<html>', 200)),
      );
      await expectFailure(MockClient((_) async => json({'items': []})));
      await expectFailure(
        MockClient(
          (_) async => json({
            'products': [product('cow_milk', 0)],
          }),
        ),
      );
      await expectFailure(
        MockClient((_) async => throw const SocketException('offline')),
      );
    });
  });

  group('CatalogRepository sync', () {
    test('Refresh fetches, caches and applies the catalog', () async {
      final repository = repositoryWith(fakeServer());
      await repository.initialize();

      expect(await repository.refresh(), isTrue);

      expect(repository.source, CatalogSource.server);
      expect(repository.products.map((p) => p.id), [
        'buffalo_milk',
        'cow_milk',
        'paneer',
      ]);

      final cached = await CatalogCacheService.instance.loadCatalog(
        CatalogRepository.cacheKey,
      );
      expect(cached!.products, hasLength(3));
    });

    test('The next start uses the saved catalog without a server', () async {
      await repositoryWith(fakeServer()).refresh();

      final offline = repositoryWith(
        MockClient((_) async => throw const SocketException('offline')),
      );
      await offline.initialize();

      expect(offline.source, CatalogSource.cached);
      expect(await offline.refresh(), isFalse);
      expect(offline.source, CatalogSource.cached);
      expect(offline.productById('paneer')?.price, 800.0);
      expect(offline.lastRefreshError, isA<CatalogApiException>());
    });

    test('Concurrent refreshes share one request', () async {
      final repository = repositoryWith(fakeServer());
      await repository.initialize();

      final results = await Future.wait([
        repository.refresh(),
        repository.refresh(),
      ]);

      expect(results, [isTrue, isTrue]);
      expect(catalogRequests, 1);
    });

    test('Without a server, refresh does nothing', () async {
      final repository = CatalogRepository();
      await repository.initialize();

      expect(repository.canUseServer, isFalse);
      expect(await repository.refresh(), isFalse);
      expect(repository.source, CatalogSource.builtIn);
    });
  });

  group('Cart follows the catalog', () {
    Future<(CatalogRepository, CartManager)> setUpCart() async {
      await db.insert(MilkDatabaseService.cartItemsTable, {
        'product_id': 'cow_milk',
        'quantity': 2,
      });
      await db.insert(MilkDatabaseService.cartItemsTable, {
        'product_id': 'paneer',
        'quantity': 1,
      });

      final repository = repositoryWith(fakeServer());
      await repository.initialize();
      await repository.refresh();

      final cart = CartManager(productLookup: repository.productById);
      await cart.initialize();
      repository.addListener(cart.refreshProducts);

      return (repository, cart);
    }

    double priceOf(CartManager cart, String id) =>
        cart.items.firstWhere((i) => i.product.id == id).product.price;

    bool availableOf(CartManager cart, String id) =>
        cart.items.firstWhere((i) => i.product.id == id).product.isAvailable;

    test('Server price changes update cart prices', () async {
      final (repository, cart) = await setUpCart();
      expect(priceOf(cart, 'cow_milk'), 90.0);

      serverProducts = [product('cow_milk', 9500), product('paneer', 80000)];
      await repository.refresh();

      expect(priceOf(cart, 'cow_milk'), 95.0);
      expect(cart.totalQuantity, 3);

      await cart.waitForPendingSaves();
      cart.dispose();
    });

    test(
      'A product the server stops selling stays, marked unavailable',
      () async {
        final (repository, cart) = await setUpCart();

        serverProducts = [product('cow_milk', 9000)];
        await repository.refresh();

        expect(availableOf(cart, 'paneer'), isFalse);
        expect(cart.items, hasLength(2));

        await cart.waitForPendingSaves();
        cart.dispose();
      },
    );

    test('Price changes wait until checkout locks are released', () async {
      final (repository, cart) = await setUpCart();

      cart.beginCheckoutRecoveryLock();

      serverProducts = [product('cow_milk', 9900), product('paneer', 80000)];
      await repository.refresh();

      // Unchanged while a checkout may be in progress.
      expect(priceOf(cart, 'cow_milk'), 90.0);

      cart.endCheckoutRecoveryLock();

      expect(priceOf(cart, 'cow_milk'), 99.0);

      await cart.waitForPendingSaves();
      cart.dispose();
    });
  });
}
