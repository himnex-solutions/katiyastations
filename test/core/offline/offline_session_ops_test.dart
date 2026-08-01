// Close Session / Hold Session / Update Quantity, offline.
//
// These three were bare API calls: offline the request threw, nothing was
// queued, and nothing local recorded the change — so the action simply never
// happened. A waiter freed a table and it stayed occupied; a quantity edit
// reverted; a hold did nothing.
//
// Each now writes local state immediately AND queues the call, and the local
// state outranks the server until the queued call is confirmed synced.

import 'package:flutter_test/flutter_test.dart';
import 'package:katiya_station_rms/core/offline/offline_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors _closedOfflineSessions / _heldOfflineSessions: when online, a
/// marker with no matching queued op has synced and is dropped; offline every
/// marker is kept, because the server can't be asked.
Future<Set<String>> liveClosed(bool online, Set<String> queuedSessionIds) async {
  final ids = await OfflineCache.instance.closedOfflineSessionIds();
  if (ids.isEmpty || !online) return ids;
  final live = <String>{};
  for (final sid in ids) {
    if (queuedSessionIds.contains(sid)) {
      live.add(sid);
    } else {
      await OfflineCache.instance.removeClosedOfflineSession(sid);
    }
  }
  return live;
}

Future<Map<String, bool>> liveHeld(
    bool online, Set<String> queuedSessionIds) async {
  final held = await OfflineCache.instance.heldOfflineSessions();
  if (held.isEmpty || !online) return held;
  final live = <String, bool>{};
  for (final e in held.entries) {
    if (queuedSessionIds.contains(e.key)) {
      live[e.key] = e.value;
    } else {
      await OfflineCache.instance.removeHeldOfflineSession(e.key);
    }
  }
  return live;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OfflineCache.instance.clear();
  });

  group('close session offline', () {
    test('frees the table while the close is still queued', () async {
      await OfflineCache.instance.putClosedOfflineSession('session-1');

      // Offline: keep it — the table must read as free straight away.
      expect(await liveClosed(false, {}), {'session-1'});

      // Back online with the close still in the outbox: still free.
      expect(await liveClosed(true, {'session-1'}), {'session-1'});
    });

    test('hands the table back to the server once the close has synced',
        () async {
      await OfflineCache.instance.putClosedOfflineSession('session-1');

      // Op gone from the outbox = it synced, so the server has freed it too.
      expect(await liveClosed(true, {}), isEmpty);
      expect(await OfflineCache.instance.closedOfflineSessionIds(), isEmpty,
          reason: 'the spent marker is swept, not left to accumulate');
    });

    test('tracks several closed tables independently', () async {
      await OfflineCache.instance.putClosedOfflineSession('session-1');
      await OfflineCache.instance.putClosedOfflineSession('session-2');

      expect(await liveClosed(true, {'session-2'}), {'session-2'});
    });
  });

  group('hold session offline', () {
    test('records the INTENDED state, both on and off', () async {
      await OfflineCache.instance.putHeldOfflineSession('session-1', true);
      expect(await liveHeld(false, {}), {'session-1': true});

      // Taking it off hold offline must also be remembered — otherwise the
      // unhold is invisible and the table stays stuck on hold.
      await OfflineCache.instance.putHeldOfflineSession('session-1', false);
      expect(await liveHeld(false, {}), {'session-1': false});
    });

    test('overrides what the server still reports while queued', () async {
      await OfflineCache.instance.putHeldOfflineSession('session-1', true);

      final held = await liveHeld(true, {'session-1'});
      // The server row still says on_hold=false; the local value wins.
      final serverRow = {'id': 'session-1', 'on_hold': false};
      final merged = {...serverRow, 'on_hold': held['session-1']};

      expect(merged['on_hold'], true);
    });

    test('stops overriding once the hold has synced', () async {
      await OfflineCache.instance.putHeldOfflineSession('session-1', true);

      expect(await liveHeld(true, {}), isEmpty,
          reason: 'server is authoritative again once it has been told');
    });
  });

  group('logout', () {
    test('clears close and hold markers with the rest of the cache', () async {
      await OfflineCache.instance.putClosedOfflineSession('session-1');
      await OfflineCache.instance.putHeldOfflineSession('session-2', true);

      await OfflineCache.instance.clear();

      expect(await OfflineCache.instance.closedOfflineSessionIds(), isEmpty);
      expect(await OfflineCache.instance.heldOfflineSessions(), isEmpty);
    });
  });
}
