// Regression: the cashier screen went completely blank the moment the
// internet dropped — no orders, no bill totals, nothing.
//
// Cause: sessionKotsProvider DELETED every local copy the server had
// confirmed, on the reasoning that the server was now authoritative and the
// local row was spent. So while online the till's Isar was continuously
// emptied, and going offline left it with no server AND no cache.
//
// Offline-first requires the opposite: the server REFRESHES a local copy that
// is always kept. These tests model that contract — what the till holds
// locally must be enough to render the bill with the network gone.

import 'package:flutter_test/flutter_test.dart';
import 'package:katiya_station_rms/core/offline/offline_models.dart';

/// Stand-in for the till's local store.
class FakeStore {
  final _kots = <String, OfflineKot>{};
  final _items = <String, List<OfflineKotItem>>{};

  void save(OfflineKot k, List<OfflineKotItem> items) {
    _kots[k.id] = k;
    _items[k.id] = items;
  }

  void delete(String id) {
    _kots.remove(id);
    _items.remove(id);
  }

  List<OfflineKot> forSession(String sessionId) =>
      _kots.values.where((k) => k.sessionId == sessionId).toList();

  List<OfflineKotItem> itemsFor(String id) => _items[id] ?? const [];
}

OfflineKot serverKot(String id, {String status = 'pending'}) => OfflineKot()
  ..id = id
  ..branchId = 'branch-1'
  ..sessionId = 'session-1'
  ..tableId = 'table-7'
  ..kotNumber = id.toUpperCase()
  ..status = status
  ..createdAt = DateTime.parse('2026-08-01T19:30:00.000')
  ..isPendingSync = false
  ..syncedAt = DateTime.parse('2026-08-01T19:30:00.000');

OfflineKot pendingKot(String id) => serverKot(id)..isPendingSync = true;

List<OfflineKotItem> lines(String kotId) => [
      OfflineKotItem()
        ..id = '$kotId-item'
        ..kotId = kotId
        ..menuItemId = 'menu-momo'
        ..menuItemName = 'Chicken Momo'
        ..quantity = 2
        ..unitPrice = 280
        ..createdAt = DateTime.parse('2026-08-01T19:30:00.000'),
    ];

/// The OLD behaviour: drop anything the server has confirmed.
void purgeConfirmed(FakeStore store, Set<String> serverIds) {
  for (final k in store.forSession('session-1')) {
    if (serverIds.contains(k.id)) store.delete(k.id);
  }
}

/// The NEW behaviour: refresh the local copy, and only drop cached rows the
/// server no longer lists — never anything still awaiting upload.
void cacheServerKots(FakeStore store, List<OfflineKot> server) {
  for (final k in server) {
    store.delete(k.id);
    store.save(k, lines(k.id));
  }
  final serverIds = server.map((k) => k.id).toSet();
  for (final k in store.forSession('session-1')) {
    if (!serverIds.contains(k.id) && !k.isPendingSync) store.delete(k.id);
  }
}

void main() {
  group('going offline', () {
    test('leaves the till with the orders it had — the reported blank screen',
        () async {
      final store = FakeStore();
      final fromServer = [serverKot('kot-1'), serverKot('kot-2')];

      // Online: the till syncs with the server.
      cacheServerKots(store, fromServer);

      // Internet drops. The server contributes nothing from here on, so
      // whatever renders has to come from the local store.
      final visibleOffline = store.forSession('session-1');

      expect(visibleOffline, hasLength(2),
          reason: 'the till must still show both orders with no network');
      expect(store.itemsFor('kot-1'), isNotEmpty,
          reason: 'and their lines, or the bill total is zero');
    });

    test('the old purge is what emptied it', () async {
      final store = FakeStore();
      cacheServerKots(store, [serverKot('kot-1'), serverKot('kot-2')]);

      // What the code used to do on every online refresh.
      purgeConfirmed(store, {'kot-1', 'kot-2'});

      expect(store.forSession('session-1'), isEmpty,
          reason: 'this is the bug: online refreshes emptied the cache, so '
              'going offline showed nothing at all');
    });
  });

  group('cache refresh', () {
    test('picks up a status change from the server', () async {
      final store = FakeStore();
      cacheServerKots(store, [serverKot('kot-1')]);
      expect(store.forSession('session-1').single.status, 'pending');

      cacheServerKots(store, [serverKot('kot-1', status: 'served')]);

      expect(store.forSession('session-1').single.status, 'served');
      expect(store.forSession('session-1'), hasLength(1),
          reason: 'refreshed in place, not duplicated');
    });

    test('drops an order the server no longer lists', () async {
      final store = FakeStore();
      cacheServerKots(store, [serverKot('kot-1'), serverKot('kot-2')]);

      // kot-2 cancelled on another device.
      cacheServerKots(store, [serverKot('kot-1')]);

      expect(store.forSession('session-1').map((k) => k.id), ['kot-1']);
    });

    test('NEVER drops an order still waiting to upload', () async {
      final store = FakeStore();
      // Taken offline on this till; the server has never heard of it.
      store.save(pendingKot('kot-offline'), lines('kot-offline'));

      cacheServerKots(store, [serverKot('kot-1')]);

      expect(store.forSession('session-1').map((k) => k.id),
          containsAll(['kot-1', 'kot-offline']),
          reason: 'an unsynced order is not stale — dropping it loses a sale');
    });

    test('an unsynced order survives repeated refreshes', () async {
      final store = FakeStore();
      store.save(pendingKot('kot-offline'), lines('kot-offline'));

      for (var i = 0; i < 5; i++) {
        cacheServerKots(store, [serverKot('kot-1')]);
      }

      expect(
          store.forSession('session-1').where((k) => k.id == 'kot-offline'),
          hasLength(1));
    });
  });
}
