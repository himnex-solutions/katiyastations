// Regression for: an order cancelled offline reappears when the internet
// returns.
//
//   Internet ON  — waiter sends Order #101, server saves it, cashier sees it.
//   Internet OFF — cashier cancels #101. Gone from the bill everywhere.
//   Internet ON  — cashier refetches. The server still has #101 as active
//                  because the cancel hasn't landed, so it comes BACK.
//
// The device recorded what was ADDED offline but never what was DELETED, so
// server data won unopposed on the next read. A tombstone is that missing
// record, and it outranks the server until the cancel is confirmed synced.

import 'package:flutter_test/flutter_test.dart';
import 'package:katiya_station_rms/core/offline/offline_cache.dart';
import 'package:katiya_station_rms/features/orders/domain/entities/order_entities.dart';
import 'package:katiya_station_rms/features/orders/presentation/providers/order_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

KotWithItems kot(String id, String number, List<Map<String, dynamic>> items) =>
    KotWithItems(
      id: id,
      branchId: 'branch-1',
      sessionId: 'session-1',
      tableId: 'table-7',
      kotNumber: number,
      status: 'pending', // server hasn't been told about the cancel yet
      items: items,
      createdAt: DateTime.parse('2026-07-31T19:30:00.000'),
    );

/// The rows the cashier refetches from the server on reconnect.
List<KotWithItems> serverSays() => [
      kot('kot-101', '#101', [
        {'id': 'item-a', 'name': 'Chicken Momo', 'quantity': 2, 'unit_price': 280.0},
        {'id': 'item-b', 'name': 'Coke', 'quantity': 1, 'unit_price': 90.0},
      ]),
      kot('kot-102', '#102', [
        {'id': 'item-c', 'name': 'Fried Rice', 'quantity': 1, 'unit_price': 350.0},
      ]),
    ];

/// Exercises the REAL filter used by sessionKotsProvider.
Future<List<KotWithItems>> applyTombstones(List<KotWithItems> kots) =>
    applyCancelTombstones(kots);

double billTotal(List<KotWithItems> kots) {
  var total = 0.0;
  for (final k in kots) {
    for (final i in k.items) {
      total += (i['unit_price'] as double) * (i['quantity'] as int);
    }
  }
  return total;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OfflineCache.instance.clear();
  });

  group('an order cancelled offline', () {
    test('does NOT come back when the server is refetched', () async {
      // Sanity: before the cancel, the server's #101 is on the bill.
      expect((await applyTombstones(serverSays())).map((k) => k.id),
          containsAll(['kot-101', 'kot-102']));

      // Internet OFF — cashier cancels #101.
      await OfflineCache.instance.putCancelledKot('kot-101');

      // Internet ON — refetch. The server STILL says #101 is pending.
      final visible = await applyTombstones(serverSays());

      expect(visible.map((k) => k.id), ['kot-102'],
          reason: 'the cancelled order must stay gone');
      expect(billTotal(visible), 350.0,
          reason: 'and must not be charged to the guest');
    });

    test('comes back only once the cancel has actually reached the server',
        () async {
      await OfflineCache.instance.putCancelledKot('kot-101');
      expect((await applyTombstones(serverSays())).length, 1);

      // SyncEngine._cleanupAfterSync clears the tombstone after the queued
      // PATCH succeeds. From then on the server is authoritative again — and
      // its copy now reads 'cancelled', so nothing reappears in practice.
      await OfflineCache.instance.removeCancelledKot('kot-101');

      expect((await applyTombstones(serverSays())).length, 2,
          reason: 'the tombstone must not outlive the cancel it represents');
    });

    test('survives repeated refetches while the cancel is still queued',
        () async {
      await OfflineCache.instance.putCancelledKot('kot-101');
      for (var i = 0; i < 5; i++) {
        expect((await applyTombstones(serverSays())).map((k) => k.id),
            ['kot-102']);
      }
    });
  });

  group('a single line cancelled offline', () {
    test('is removed from the order the server sends back', () async {
      await OfflineCache.instance.putCancelledItem('item-b'); // the Coke

      final visible = await applyTombstones(serverSays());
      final order101 = visible.firstWhere((k) => k.id == 'kot-101');

      expect(order101.items.map((i) => i['id']), ['item-a']);
      expect(billTotal(visible), 280.0 * 2 + 350.0,
          reason: 'the cancelled line must drop off the total');
    });

    test('drops the whole order when it was the last live line', () async {
      await OfflineCache.instance.putCancelledItem('item-c');

      final visible = await applyTombstones(serverSays());
      expect(visible.map((k) => k.id), ['kot-101']);
    });
  });

  group('tombstone bookkeeping', () {
    test('several cancels are tracked independently', () async {
      await OfflineCache.instance.putCancelledKot('kot-101');
      await OfflineCache.instance.putCancelledKot('kot-102');
      expect(await OfflineCache.instance.cancelledKotIds(),
          {'kot-101', 'kot-102'});

      await OfflineCache.instance.removeCancelledKot('kot-101');
      expect(await OfflineCache.instance.cancelledKotIds(), {'kot-102'});
    });

    test('a stale tombstone expires so it cannot hide an order forever',
        () async {
      // A cancel that can never sync must eventually surface the truth rather
      // than suppressing a live order indefinitely.
      SharedPreferences.setMockInitialValues({
        'offline_cache:cancelledKot:kot-101':
            '{"at":"2020-01-01T10:00:00.000"}',
      });

      expect(await OfflineCache.instance.cancelledKotIds(), isEmpty);
      expect((await applyTombstones(serverSays())).length, 2);
    });

    test('a fresh tombstone is kept', () async {
      await OfflineCache.instance.putCancelledKot('kot-101');
      expect(await OfflineCache.instance.cancelledKotIds(), {'kot-101'});
    });

    test('logout clears tombstones along with the rest of the cache', () async {
      await OfflineCache.instance.putCancelledKot('kot-101');
      await OfflineCache.instance.putCancelledItem('item-b');

      await OfflineCache.instance.clear();

      expect(await OfflineCache.instance.cancelledKotIds(), isEmpty);
      expect(await OfflineCache.instance.cancelledItemIds(), isEmpty);
    });
  });
}
