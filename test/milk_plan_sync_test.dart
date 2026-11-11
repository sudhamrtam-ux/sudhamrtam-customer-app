import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sudhamrtam_customer_app/database/milk_database_service.dart';
import 'package:sudhamrtam_customer_app/database/milk_subscription_repository.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription_manager.dart';
import 'package:sudhamrtam_customer_app/services/milk_plan_api_client.dart';
import 'package:sudhamrtam_customer_app/services/milk_plan_sync_service.dart';
import 'package:sudhamrtam_customer_app/services/phone_auth_service.dart';

final start = DateTime(2026, 11, 8);

MilkShiftSchedule shift(MilkDeliveryShift s, int ml) => MilkShiftSchedule(
  shift: s,
  quantityMl: ml,
  frequency: MilkDeliveryFrequency.daily,
  startDate: start,
);

MilkShiftSchedule morning(int ml) => shift(MilkDeliveryShift.morning, ml);
MilkShiftSchedule evening(int ml) => shift(MilkDeliveryShift.evening, ml);

MilkSubscription plan(
  String id,
  List<MilkShiftSchedule> shifts, {
  String productId = 'buffalo_milk',
  MilkSubscriptionStatus status = MilkSubscriptionStatus.active,
}) => MilkSubscription(
  id: id,
  productId: productId,
  shiftSchedules: shifts,
  quantity: 1,
  frequency: MilkDeliveryFrequency.daily,
  startDate: start,
  status: status,
);

/// "id status shift:ml,..." per plan.
List<String> summary(Iterable<MilkSubscription> plans) => [
  for (final p in plans)
    '${p.id} ${p.status.name} '
        '${p.shiftSchedules.map((s) => '${s.shift.name}:${s.quantityMl}').join(',')}',
];

/// The server, in memory, with the same rules as the real one.
class FakeServer implements MilkPlanRemote {
  final plans = <String, MilkSubscription>{};
  bool offline = false;
  final calls = <String>[];

  @override
  Future<List<MilkSubscription>> fetchPlans() async {
    calls.add('fetch');
    if (offline) throw const MilkPlanSyncException('No internet connection.');
    return plans.values.toList();
  }

  @override
  Future<List<MilkSubscription>> applyChanges(
    List<MilkSubscription> saves,
    List<String> cancelIds,
  ) async {
    calls.add(
      'apply ${saves.map((p) => p.id).join(',')}/${cancelIds.join(',')}',
    );
    if (offline) throw const MilkPlanSyncException('No internet connection.');

    final result = Map.of(plans);
    for (final id in cancelIds) {
      final p = result[id];
      if (p != null) {
        result[id] = p.copyWith(status: MilkSubscriptionStatus.cancelled);
      }
    }
    for (final p in saves) {
      result[p.id] = p;
    }

    final seen = <String>{};
    for (final p in result.values) {
      if (p.status == MilkSubscriptionStatus.cancelled) continue;
      for (final s in p.shiftSchedules) {
        if (!seen.add('${p.productId}:${s.shift.name}')) {
          throw const MilkPlanSyncException(
            'Another plan already delivers this milk in this shift.',
            code: 'SHIFT_ALREADY_PLANNED',
          );
        }
      }
    }
    plans
      ..clear()
      ..addAll(result);
    return plans.values.toList();
  }
}

class FakeAuth implements PhoneAuthGateway {
  final _changes = StreamController<AuthUser?>.broadcast();
  AuthUser? user;

  void signIn() {
    user = const AuthUser(uid: 'c1', phoneNumber: '+919999900001');
    _changes.add(user);
  }

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> authStateChanges() => _changes.stream;

  @override
  Future<PhoneCodeRequest> requestCode(String p, {int? resendToken}) =>
      throw UnimplementedError();

  @override
  Future<AuthUser> confirmCode(String v, String c) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {
    user = null;
    _changes.add(null);
  }
}

/// Waits (in real time: SQLite runs on another thread) until
/// [done], for up to about 5 seconds.
Future<void> eventually(bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: 'condition not reached in time');
}

void main() {
  group('server format', () {
    test('a plan survives the trip to the server and back', () {
      final original = MilkSubscription(
        id: 'p1',
        productId: 'cow_milk',
        shiftSchedules: [
          MilkShiftSchedule(
            shift: MilkDeliveryShift.morning,
            quantityMl: 1500,
            frequency: MilkDeliveryFrequency.selectedDays,
            selectedWeekdays: const [4, 1],
            startDate: DateTime(2026, 11, 8),
            endDate: DateTime(2026, 12, 31),
          ),
          MilkShiftSchedule(
            shift: MilkDeliveryShift.evening,
            quantityMl: 500,
            frequency: MilkDeliveryFrequency.randomDays,
            selectedRandomDates: [DateTime(2026, 11, 9)],
            startDate: DateTime(2026, 11, 9),
          ),
        ],
        quantity: 1,
        frequency: MilkDeliveryFrequency.selectedDays,
        startDate: DateTime(2026, 11, 8),
        status: MilkSubscriptionStatus.paused,
      );

      final json = MilkPlanApiClient.planToJson(original);
      expect(json['shifts'], [
        {
          'shift': 'morning',
          'quantity_ml': 1500,
          'frequency': 'selected_days',
          'weekdays': [1, 4],
          'dates': <String>[],
          'start_date': '2026-11-08',
          'end_date': '2026-12-31',
        },
        {
          'shift': 'evening',
          'quantity_ml': 500,
          'frequency': 'random_days',
          'weekdays': <int>[],
          'dates': ['2026-11-09'],
          'start_date': '2026-11-09',
          'end_date': null,
        },
      ]);

      final back = MilkPlanApiClient.planFromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(back.status, MilkSubscriptionStatus.paused);
      expect(back.shiftSchedules.first.selectedWeekdays, [1, 4]);
      expect(back.shiftSchedules.last.selectedRandomDates, [
        DateTime(2026, 11, 9),
      ]);
      expect(back.shiftSchedules.first.endDate, DateTime(2026, 12, 31));
    });

    test('vacation: the return date goes to the server only when paused', () {
      final away = plan(
        'p5',
        [morning(500)],
        status: MilkSubscriptionStatus.paused,
      ).copyWith(resumeOn: DateTime(2026, 11, 20));
      expect(MilkPlanApiClient.planToJson(away)['resume_on'], '2026-11-20');
      expect(
        MilkPlanApiClient.planToJson(
          away.copyWith(status: MilkSubscriptionStatus.active),
        )['resume_on'],
        isNull,
      );
      final back = MilkPlanApiClient.planFromJson(
        MilkPlanApiClient.planToJson(away),
      );
      expect(back.resumeOn, DateTime(2026, 11, 20));
      expect(back.isOnVacation(DateTime(2026, 11, 19, 23)), isTrue);
      expect(back.isOnVacation(DateTime(2026, 11, 20, 1)), isFalse);
    });

    test('a cancelled plan from the server keeps its cancel date', () {
      final back = MilkPlanApiClient.planFromJson({
        ...MilkPlanApiClient.planToJson(
          plan('p3', [morning(500)], status: MilkSubscriptionStatus.cancelled),
        ),
        'cancelled_at': '2026-11-10T04:00:00.000Z',
      });
      expect(back.cancelledAt, DateTime.utc(2026, 11, 10, 4).toLocal());
      expect(
        MilkPlanApiClient.planFromJson(
          MilkPlanApiClient.planToJson(plan('p4', [morning(500)])),
        ).cancelledAt,
        isNull,
      );
    });

    test('early morning is "early_morning" on the server', () {
      final json = MilkPlanApiClient.planToJson(
        plan('p2', [shift(MilkDeliveryShift.earlyMorning, 1000), morning(500)]),
      );
      expect((json['shifts'] as List).map((s) => s['shift']), [
        'early_morning',
        'morning',
      ]);
      final back = MilkPlanApiClient.planFromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(back.shiftSchedules.map((s) => s.shift), [
        MilkDeliveryShift.earlyMorning,
        MilkDeliveryShift.morning,
      ]);
    });

    test('refusals keep their code; outages say nothing changed', () async {
      Future<MilkPlanSyncException> failure(MockClient client) async {
        final api = MilkPlanApiClient(
          baseUrl: 'http://api.test',
          token: () => 'tok',
          httpClient: client,
        );
        try {
          await api.fetchPlans();
        } on MilkPlanSyncException catch (error) {
          return error;
        }
        fail('expected a failure');
      }

      final refused = await failure(
        MockClient(
          (_) async => http.Response(
            '{"error":"SHIFT_ALREADY_PLANNED","message":"Taken."}',
            409,
          ),
        ),
      );
      expect(refused.code, 'SHIFT_ALREADY_PLANNED');

      final expired = await failure(
        MockClient((_) async => http.Response('{}', 401)),
      );
      expect(expired.unauthorized, isTrue);

      final offline = await failure(
        MockClient((_) async => throw const SocketException('offline')),
      );
      expect(offline.message, contains('not changed'));
    });
  });

  group('signed in', () {
    late Directory directory;
    late FakeServer server;

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sudhamrtam_sync_');
      MilkDatabaseService.instance.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}${Platform.pathSeparator}sync.db',
      );
      server = FakeServer();
    });

    tearDown(() async {
      await MilkDatabaseService.instance.close();
      MilkDatabaseService.instance.resetTestingConfiguration();
      await directory.delete(recursive: true);
    });

    Future<List<String>> onPhone() async =>
        summary(await MilkSubscriptionRepository().loadSubscriptions());

    test('a change goes to the server first, then the phone', () async {
      final manager = MilkSubscriptionManager()..remote = server;

      expect(await manager.addSubscription(plan('a', [morning(1000)])), isTrue);

      expect(summary(server.plans.values), ['a active morning:1000']);
      expect(await onPhone(), ['a active morning:1000']);
      expect(summary(manager.subscriptions), ['a active morning:1000']);
    });

    test('offline: nothing changes anywhere', () async {
      final manager = MilkSubscriptionManager()..remote = server;
      await manager.addSubscription(plan('a', [morning(1000)]));

      server.offline = true;
      await expectLater(
        manager.pauseSubscription('a'),
        throwsA(isA<MilkPlanSyncException>()),
      );

      expect(summary(manager.subscriptions), ['a active morning:1000']);
      expect(await onPhone(), ['a active morning:1000']);
    });

    test('a refused change leaves the phone as it was', () async {
      server.plans['x'] = plan('x', [morning(1000)]);
      final manager = MilkSubscriptionManager()..remote = server;
      await manager.syncWithServer();

      // The phone thinks evening is free; the server disagrees.
      server.plans['y'] = plan('y', [evening(500)]);
      await expectLater(
        manager.addSubscription(plan('z', [evening(500)])),
        throwsA(
          isA<MilkPlanSyncException>().having(
            (e) => e.code,
            'code',
            'SHIFT_ALREADY_PLANNED',
          ),
        ),
      );
      expect(summary(manager.subscriptions), ['x active morning:1000']);
    });

    test('phone-only plans are uploaded; the account wins per shift', () async {
      // On the phone (made before signing in), oldest first.
      final repository = MilkSubscriptionRepository();
      await repository.saveSubscription(plan('p1', [morning(1000)]));
      await repository.saveSubscription(plan('p2', [morning(500)]));
      await repository.saveSubscription(
        plan('p3', [evening(500)], productId: 'cow_milk'),
      );
      await repository.saveSubscription(
        plan('gone', [evening(1000)], status: MilkSubscriptionStatus.cancelled),
      );
      // The account already has a Cow Milk evening plan.
      server.plans['s1'] = plan('s1', [evening(1000)], productId: 'cow_milk');

      final manager = MilkSubscriptionManager();
      await manager.restoreSavedSubscriptions();
      manager.remote = server;

      final leftOut = await manager.syncWithServer();

      // p2 duplicates p1's morning; p3 duplicates the account's
      // evening: both left out, quantities never added.
      expect(leftOut, 2);
      expect(summary(server.plans.values), [
        's1 active evening:1000',
        'p1 active morning:1000',
      ]);
      expect(await onPhone(), unorderedEquals(summary(server.plans.values)));
    });

    test('plans made offline are uploaded before the next change', () async {
      final repository = MilkSubscriptionRepository();
      await repository.saveSubscription(plan('offline', [morning(1000)]));

      final manager = MilkSubscriptionManager();
      await manager.restoreSavedSubscriptions();
      manager.remote = server; // signed in, not synced yet

      await manager.addSubscription(plan('new', [evening(500)]));

      expect(server.calls.first, 'fetch');
      expect(summary(server.plans.values), [
        'offline active morning:1000',
        'new active evening:500',
      ]);
    });

    test('loading saved plans after a mirror does not fail', () async {
      server.plans['s'] = plan('s', [morning(1000)]);
      final manager = MilkSubscriptionManager()..remote = server;
      await manager.syncWithServer();

      expect(await manager.restoreSavedSubscriptions(), 0);
      expect(summary(manager.subscriptions), ['s active morning:1000']);
    });

    test('sign-out removes the plans from the phone only', () async {
      final auth = FakeAuth();
      final manager = MilkSubscriptionManager();
      final sync = MilkPlanSyncService(
        manager: manager,
        api: server,
        auth: auth,
      )..attach();

      auth.signIn();
      await eventually(() => manager.remote != null);
      await manager.addSubscription(plan('a', [morning(1000)]));
      expect(await onPhone(), ['a active morning:1000']);

      await auth.signOut();
      await eventually(() => manager.subscriptions.isEmpty);

      expect(await onPhone(), isEmpty);
      expect(manager.remote, isNull);
      expect(summary(server.plans.values), ['a active morning:1000']);
      sync.dispose();
    });

    test('a phone that was never signed in keeps its plans', () async {
      final auth = FakeAuth();
      final manager = MilkSubscriptionManager();
      await manager.addSubscription(plan('a', [morning(1000)]));

      final sync = MilkPlanSyncService(
        manager: manager,
        api: server,
        auth: auth,
      )..attach();
      await auth.signOut(); // e.g. an expired session at start-up
      await pumpEventQueue();

      expect(await onPhone(), ['a active morning:1000']);
      sync.dispose();
    });

    test('the sync explains plans that were left out', () async {
      final repository = MilkSubscriptionRepository();
      await repository.saveSubscription(plan('p', [morning(500)]));
      server.plans['s'] = plan('s', [morning(1000)]);

      final auth = FakeAuth()
        ..user = const AuthUser(uid: 'c1', phoneNumber: '+919999900001');
      final manager = MilkSubscriptionManager();
      final sync = MilkPlanSyncService(
        manager: manager,
        api: server,
        auth: auth,
      )..attach();
      // Signing in syncs once by itself.
      await eventually(() => sync.message != null);

      expect(
        sync.message,
        contains('1 delivery from this phone was not added'),
      );
      expect(summary(manager.subscriptions), ['s active morning:1000']);
      sync.dispose();
    });
  });
}
