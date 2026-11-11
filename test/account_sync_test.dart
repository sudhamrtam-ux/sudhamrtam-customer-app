import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/customer_address_database_service.dart';
import 'package:sudhamrtam_customer_app/database/customer_profile_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/models/customer_address.dart';
import 'package:sudhamrtam_customer_app/models/customer_profile.dart';
import 'package:sudhamrtam_customer_app/services/account_api_client.dart';
import 'package:sudhamrtam_customer_app/services/account_sync_service.dart';
import 'package:sudhamrtam_customer_app/services/phone_auth_service.dart';

const local = AccountSyncService.localCustomerId;

/// In-memory stand-in for the backend's profile and address API.
class FakeServer {
  String? fullName;
  String? email;
  String? regNo;
  final Map<String, Map<String, Object?>> addresses = {};

  bool offline = false;
  bool sessionEnded = false;
  final Set<String> rejectIds = {};
  final List<String> calls = [];

  Map<String, Object?> get customer => {
    'id': 'cust-1',
    'phone_e164': '+919999900001',
    'full_name': fullName,
    'email': email,
    'reg_no': regNo,
  };

  void addAddress(String id, {bool isDefault = false, String label = 'Home'}) {
    addresses[id] = {
      'id': id,
      'area_id': 'nizampet',
      'label': label,
      'recipient_name': 'Server Person',
      'phone_e164': '+919876543210',
      'address_line1': 'Server street',
      'address_line2': null,
      'landmark': '',
      'city': 'Hyderabad',
      'state': 'Telangana',
      'postal_code': '500090',
      'latitude': null,
      'longitude': null,
      'is_default': isDefault,
      'created_at': '2026-11-01T00:00:00.000Z',
      'updated_at': '2026-11-01T00:00:00.000Z',
    };
  }

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  Future<http.Response> handle(http.Request request) async {
    if (offline) throw const SocketException('offline');
    if (sessionEnded) {
      return _json({'error': 'UNAUTHORIZED', 'message': 'Sign in'}, 401);
    }

    final path = request.url.path;
    calls.add('${request.method} $path');
    final body = request.body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(request.body) as Map<String, Object?>;

    if (path == '/v1/me' && request.method == 'GET') {
      return _json({'customer': customer});
    }
    if (path == '/v1/me' && request.method == 'PATCH') {
      if (body.containsKey('full_name')) fullName = body['full_name'] as String?;
      if (body.containsKey('email')) {
        final value = body['email'] as String?;
        email = (value == null || value.isEmpty) ? null : value;
      }
      return _json({'customer': customer});
    }
    if (path == '/v1/addresses') {
      return _json({'addresses': addresses.values.toList()});
    }

    final match = RegExp(r'^/v1/addresses/([^/]+)(/default)?$').firstMatch(path);
    final id = match?.group(1);
    if (id == null) return _json({}, 404);

    if (match!.group(2) != null) {
      if (!addresses.containsKey(id)) return _json({}, 404);
      for (final a in addresses.values) {
        a['is_default'] = a['id'] == id;
      }
      return _json({'address': addresses[id]});
    }
    if (request.method == 'DELETE') {
      return addresses.remove(id) == null
          ? _json({}, 404)
          : http.Response('', 204);
    }
    if (request.method == 'PUT') {
      if (rejectIds.contains(id)) {
        return _json({'error': 'INVALID_ADDRESS', 'message': 'Bad PIN'}, 422);
      }
      if (body['is_default'] == true) {
        for (final a in addresses.values) {
          a['is_default'] = false;
        }
      }
      final phone = body['phone'] as String;
      addresses[id] = {
        ...body,
        'id': id,
        'phone_e164': '+91$phone',
        'landmark': body['landmark'] ?? '',
        'created_at': '2026-11-07T00:00:00.000Z',
        'updated_at': '2026-11-07T00:00:00.000Z',
      }..remove('phone');
      return _json({'address': addresses[id]});
    }
    return _json({}, 404);
  }
}

class FakeAuth implements PhoneAuthGateway {
  final _changes = StreamController<AuthUser?>.broadcast();
  AuthUser? user;

  void signIn() {
    user = const AuthUser(uid: 'cust-1', phoneNumber: '+919999900001');
    _changes.add(user);
  }

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> authStateChanges() => _changes.stream;

  @override
  Future<void> signOut() async {
    user = null;
    _changes.add(null);
  }

  @override
  Future<PhoneCodeRequest> requestCode(String p, {int? resendToken}) =>
      throw UnimplementedError();

  @override
  Future<AuthUser> confirmCode(String v, String c) =>
      throw UnimplementedError();
}

CustomerAddress phoneAddress(String id, {bool isDefault = false}) {
  final now = DateTime(2026, 11, 1);
  return CustomerAddress(
    id: id,
    customerId: local,
    label: 'Home',
    recipientName: 'Phone Person',
    phoneNumber: '9876543210',
    addressLine1: 'Phone street',
    landmark: '',
    city: 'Hyderabad',
    state: 'Telangana',
    postalCode: '500090',
    isDefault: isDefault,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late Directory directory;
  late FakeServer server;
  late FakeAuth auth;
  late AccountSyncService sync;

  final addresses = CustomerAddressDatabaseService.instance;
  final profiles = CustomerProfileDatabaseService.instance;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sudhamrtam_sync_');
    MilkDatabaseService.instance.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}${Platform.pathSeparator}sync.db',
    );

    server = FakeServer();
    auth = FakeAuth();
    sync = AccountSyncService(
      api: AccountApiClient(
        baseUrl: 'http://api.test',
        token: () => auth.user == null ? null : 'tok',
        httpClient: MockClient(server.handle),
      ),
      auth: auth,
    );
  });

  tearDown(() async {
    sync.dispose();
    await MilkDatabaseService.instance.close();
    MilkDatabaseService.instance.resetTestingConfiguration();
    await directory.delete(recursive: true);
  });

  Future<void> savePhoneProfile(String name, {String? email}) =>
      profiles.saveProfile(
        CustomerProfile(
          id: local,
          fullName: name,
          email: email,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );

  Future<List<String>> phoneAddressIds() async => [
    for (final a in await addresses.getAddressesByCustomerId(local)) a.id,
  ];

  test('signed out: changes stay on the phone', () async {
    await sync.saveProfile(fullName: 'Asha', phoneNumber: '9876543210');
    await sync.saveAddress(phoneAddress('a1', isDefault: true));

    expect(server.calls, isEmpty);
    expect(await phoneAddressIds(), ['a1']);
    expect((await profiles.getProfileById(local))?.phoneNumber, '9876543210');
  });

  test('first sign-in uploads the phone data, then mirrors the server', () async {
    await savePhoneProfile('Asha', email: 'asha@example.com');
    await addresses.saveAddress(phoneAddress('phone_1', isDefault: true));
    server.addAddress('server_1');

    auth.signIn();
    await sync.syncNow();

    expect(sync.lastSyncError, isNull);
    expect(server.fullName, 'Asha');
    expect(server.email, 'asha@example.com');
    expect(server.addresses.keys, containsAll(['server_1', 'phone_1']));
    expect(await phoneAddressIds(), containsAll(['server_1', 'phone_1']));

    final profile = await profiles.getProfileById(local);
    expect(profile?.phoneNumber, '9999900001');
  });

  test('the server profile wins over the phone', () async {
    await savePhoneProfile('Phone name');
    server.fullName = 'Account name';

    auth.signIn();
    await sync.syncNow();

    expect(server.fullName, 'Account name');
    expect((await profiles.getProfileById(local))?.fullName, 'Account name');
  });

  test('the server default stays the default', () async {
    await savePhoneProfile('Asha');
    await addresses.saveAddress(phoneAddress('phone_1', isDefault: true));
    server.addAddress('server_1', isDefault: true);

    auth.signIn();
    await sync.syncNow();

    final defaults = [
      for (final a in await addresses.getAddressesByCustomerId(local))
        if (a.isDefault) a.id,
    ];
    expect(defaults, ['server_1']);
  });

  test('an address the server rejects is kept on the phone', () async {
    await savePhoneProfile('Asha');
    await addresses.saveAddress(phoneAddress('bad_1'));
    server.rejectIds.add('bad_1');

    auth.signIn();
    await sync.syncNow();
    expect(await phoneAddressIds(), ['bad_1']);

    // Later refreshes keep it too, until it is fixed.
    await sync.syncNow();
    expect(await phoneAddressIds(), ['bad_1']);

    // Fixing it uploads it.
    server.rejectIds.clear();
    await sync.saveAddress(phoneAddress('bad_1'));
    expect(server.addresses.keys, ['bad_1']);
  });

  test('offline first sync changes nothing and reports the problem', () async {
    await savePhoneProfile('Asha');
    await addresses.saveAddress(phoneAddress('phone_1'));
    server.offline = true;

    auth.signIn();
    await sync.syncNow();

    expect(sync.lastSyncError, contains('No internet'));
    expect(await phoneAddressIds(), ['phone_1']);

    // Next time it uploads.
    server.offline = false;
    await sync.syncNow();
    expect(server.addresses.keys, ['phone_1']);
  });

  test('signed in: changes go to the server, then the phone', () async {
    auth.signIn();
    await sync.syncNow();

    await sync.saveAddress(phoneAddress('a1', isDefault: true));
    await sync.saveAddress(phoneAddress('a2'));
    expect(server.addresses.keys, ['a1', 'a2']);

    await sync.setDefaultAddress('a2');
    expect(server.addresses['a2']!['is_default'], isTrue);
    expect((await addresses.getDefaultAddress(local))?.id, 'a2');

    await sync.deleteAddress('a1');
    expect(server.addresses.keys, ['a2']);
    expect(await phoneAddressIds(), ['a2']);

    await sync.saveProfile(fullName: 'Asha Rao', email: 'a@b.in');
    expect(server.fullName, 'Asha Rao');
    expect((await profiles.getProfileById(local))?.email, 'a@b.in');
  });

  test('signed in and offline: a change fails and nothing changes', () async {
    auth.signIn();
    await sync.syncNow();
    server.offline = true;

    await expectLater(
      sync.saveAddress(phoneAddress('a1')),
      throwsA(isA<AccountApiException>()),
    );
    expect(await phoneAddressIds(), isEmpty);
  });

  test('an address deleted elsewhere is not brought back', () async {
    await savePhoneProfile('Asha');
    await addresses.saveAddress(phoneAddress('a1'));
    auth.signIn();
    await sync.syncNow();
    expect(server.addresses.keys, ['a1']);

    server.addresses.remove('a1'); // deleted on another phone
    await sync.syncNow();

    expect(server.addresses, isEmpty);
    expect(await phoneAddressIds(), isEmpty);
  });

  test('sign-out removes the account data from the phone', () async {
    sync.attach();
    auth.signIn();
    await sync.syncNow();
    await sync.saveAddress(phoneAddress('a1'));

    await auth.signOut();
    await sync.syncNow(); // waits for queued work

    expect(await phoneAddressIds(), isEmpty);
    expect(await profiles.getProfileById(local), isNull);
    expect(server.addresses.keys, ['a1']);
  });

  test("the Reg No: none until approved, then the server's", () async {
    expect(await sync.refreshRegNo(), isNull); // signed out
    sync.attach();
    auth.signIn();
    await sync.syncNow();
    expect(await sync.regNo(), isNull);

    // Sudhamrtam approves the first plan after the last sync.
    server.regNo = 'SM-1002';
    expect(await sync.regNo(), isNull);
    expect(await sync.refreshRegNo(), 'SM-1002', reason: 'fresh');
    expect(await sync.regNo(), 'SM-1002', reason: 'saved');

    // Offline: the saved one.
    server.offline = true;
    expect(await sync.refreshRegNo(), 'SM-1002', reason: 'offline');
    server.offline = false;

    await auth.signOut();
    await sync.syncNow();
    expect(await sync.regNo(), isNull);
  });

  test('an ended session signs the customer out', () async {
    auth.signIn();
    server.sessionEnded = true;

    await sync.syncNow();

    expect(auth.currentUser, isNull);
  });

  test('v9 to v10 upgrade keeps addresses and adds an empty area', () async {
    await MilkDatabaseService.instance.close();
    MilkDatabaseService.instance.resetTestingConfiguration();

    final path = '${directory.path}${Platform.pathSeparator}v9.db';
    final v9 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 9,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE customer_addresses (
              id TEXT PRIMARY KEY,
              customer_id TEXT NOT NULL,
              label TEXT NOT NULL,
              recipient_name TEXT NOT NULL,
              phone_number TEXT NOT NULL,
              address_line_1 TEXT NOT NULL,
              address_line_2 TEXT,
              landmark TEXT NOT NULL,
              city TEXT NOT NULL,
              state TEXT NOT NULL,
              postal_code TEXT NOT NULL,
              latitude REAL,
              longitude REAL,
              is_default INTEGER NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          // A v9 address row: none of the later columns.
          final row = phoneAddress('old_1').toMap()
            ..removeWhere(
              (key, _) => const {
                'area_id',
                'society_id',
                'society_name',
                'society_other',
                'block',
                'flat',
                'is_house',
              }.contains(key),
            );
          await db.insert('customer_addresses', row);
        },
      ),
    );
    await v9.close();

    MilkDatabaseService.instance.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: path,
    );

    final address = await addresses.getAddressById('old_1');
    expect(address?.recipientName, 'Phone Person');
    expect(address?.areaId, isNull);

    final db = await MilkDatabaseService.instance.database;
    final version = await db.rawQuery('PRAGMA user_version');
    expect(version.first.values.first, MilkDatabaseService.databaseVersion);
  });
}
