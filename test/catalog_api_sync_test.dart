import 'dart:async';
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

const nizampet = DeliveryArea(id: 'nizampet', name: 'Nizampet');
const praneeth = DeliveryArea(
  id: 'praneeth_pranav_flora',
  name: 'Praneeth Pranav Flora',
);

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

/// Server catalogs per area, editable by each test.
final serverCatalogs = <String, List<Map<String, Object?>>>{};

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

MockClient fakeServer({Future<void> Function(String areaId)? beforeCatalog}) {
  return MockClient((request) async {
    switch (request.url.path) {
      case '/v1/areas':
        return json({
          'areas': [
            {'id': nizampet.id, 'name': nizampet.name},
            {'id': praneeth.id, 'name': praneeth.name},
          ],
        });
      case '/v1/catalog':
        final areaId = request.url.queryParameters['area_id']!;
        await beforeCatalog?.call(areaId);
        final products = serverCatalogs[areaId];
        if (products == null) return json({'error': 'AREA_NOT_FOUND'}, 404);
        final name = areaId == nizampet.id ? nizampet.name : praneeth.name;
        return json({
          'area': {'id': areaId, 'name': name},
          'products': products,
        });
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
    serverCatalogs
      ..clear()
      ..addAll({
        nizampet.id: [
          product('buffalo_milk', 8500),
          product('cow_milk', 9000),
          product('paneer', 80000),
        ],
        praneeth.id: [
          product('buffalo_milk', 9000),
          product('cow_milk', 8500),
          product('coconut_oil', 70000),
        ],
      });

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
    test('Parses areas and an area catalog', () async {
      final api = CatalogApiClient(
        baseUrl: 'http://test.local',
        httpClient: fakeServer(),
      );

      final areas = await api.fetchAreas();
      expect(areas.map((a) => a.id), [nizampet.id, praneeth.id]);

      final catalog = await api.fetchCatalog(nizampet.id);
      expect(catalog.area.name, 'Nizampet');
      expect(catalog.products.map((p) => p.pricePaise), [8500, 9000, 80000]);
    });

    test('Turns server problems into CatalogApiException', () async {
      Future<void> expectFailure(http.Client client) async {
        final api = CatalogApiClient(
          baseUrl: 'http://test.local',
          httpClient: client,
        );
        await expectLater(
          api.fetchCatalog(nizampet.id),
          throwsA(isA<CatalogApiException>()),
        );
      }

      await expectFailure(MockClient((_) async => json({}, 500)));
      await expectFailure(
        MockClient((_) async => http.Response('<html>', 200)),
      );
      await expectFailure(MockClient((_) async => json({'products': []})));
      await expectFailure(
        MockClient(
          (_) async => json({
            'area': {'id': 'other_area', 'name': 'Other'},
            'products': [],
          }),
        ),
      );
      await expectFailure(
        MockClient(
          (_) async => json({
            'area': {'id': nizampet.id, 'name': nizampet.name},
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
    test('Selecting an area fetches, caches and applies its catalog', () async {
      final repository = repositoryWith(fakeServer());
      await repository.initialize();

      expect(await repository.selectArea(nizampet), isTrue);

      expect(repository.source, CatalogSource.server);
      expect(repository.selectedAreaName, 'Nizampet');
      expect(repository.productById('cow_milk')?.price, 90.0);

      final cached = await CatalogCacheService.instance.loadCatalog(
        nizampet.id,
      );
      expect(cached!.products, hasLength(3));
      expect(
        await CatalogCacheService.instance.getSelectedAreaId(),
        nizampet.id,
      );
    });

    test('A failed refresh keeps the cached catalog', () async {
      await repositoryWith(fakeServer()).selectArea(nizampet);

      final offline = repositoryWith(
        MockClient((_) async => throw const SocketException('offline')),
      );
      await offline.initialize();

      expect(await offline.refresh(), isFalse);
      expect(offline.source, CatalogSource.cached);
      expect(offline.productById('cow_milk')?.price, 90.0);
      expect(offline.lastRefreshError, isA<CatalogApiException>());
    });

    test('A late response for a previous area is not applied', () async {
      final nizampetRequested = Completer<void>();
      final release = Completer<void>();

      final repository = repositoryWith(
        fakeServer(
          beforeCatalog: (areaId) async {
            if (areaId == nizampet.id) {
              nizampetRequested.complete();
              await release.future;
            }
          },
        ),
      );
      await repository.initialize();

      final slowNizampet = repository.selectArea(nizampet);
      await nizampetRequested.future;

      // The customer switches area before Nizampet responds.
      final switchToPraneeth = repository.selectArea(praneeth);
      release.complete();

      // The stale Nizampet result is not applied...
      expect(await slowNizampet, isFalse);
      // ...and the Praneeth selection fetched its own catalog.
      expect(await switchToPraneeth, isTrue);

      expect(repository.selectedAreaId, praneeth.id);
      expect(repository.productById('coconut_oil')?.isAvailable, isTrue);
      // Paneer was seen in Nizampet's catalog: known, but unavailable here.
      expect(repository.productById('paneer')?.isAvailable, isFalse);
    });

    test('A superseded selection does not override a newer one', () async {
      final repository = repositoryWith(fakeServer());
      await repository.initialize();

      // Both areas cached, so selectArea applies a cached copy.
      await repository.selectArea(nizampet);
      await repository.selectArea(praneeth);

      final first = repository.selectArea(nizampet);
      final second = repository.selectArea(praneeth);

      expect(await first, isFalse);
      expect(await second, isTrue);
      expect(repository.selectedAreaId, praneeth.id);
      expect(
        await CatalogCacheService.instance.getSelectedAreaId(),
        praneeth.id,
      );
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
      await repository.selectArea(nizampet);

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

      serverCatalogs[nizampet.id] = [
        product('cow_milk', 9500),
        product('paneer', 80000),
      ];
      await repository.refresh();

      expect(priceOf(cart, 'cow_milk'), 95.0);
      expect(cart.totalQuantity, 3);

      await cart.waitForPendingSaves();
      cart.dispose();
    });

    test('Switching area keeps items but marks unsold ones', () async {
      final (repository, cart) = await setUpCart();

      await repository.selectArea(praneeth);

      expect(priceOf(cart, 'cow_milk'), 85.0);
      expect(availableOf(cart, 'paneer'), isFalse);
      expect(cart.items, hasLength(2));

      await cart.waitForPendingSaves();
      cart.dispose();
    });

    test('Price changes wait until checkout locks are released', () async {
      final (repository, cart) = await setUpCart();

      cart.beginCheckoutRecoveryLock();

      serverCatalogs[nizampet.id] = [
        product('cow_milk', 9900),
        product('paneer', 80000),
      ];
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
