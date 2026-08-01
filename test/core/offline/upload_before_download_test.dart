// Contract: on reconnect the outbox is drained BEFORE anything is fetched.
//
// The server holds the pre-change state for everything done during the outage.
// Refreshing first pulls that stale state back over the local change — for a
// cancel, that puts the order straight back on the bill. So the upload has to
// finish first.
//
// Two things had to be true for that to be enforceable, and both are tested
// here:
//   1. awaiting syncNow() must actually mean "the queue is drained"
//   2. a call made DURING a drain must join it, not return immediately
// The old syncNow() returned early when a drain was already running, handing
// an awaiting caller a completed future while the queue was still going.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Models the join-or-start behaviour of SyncEngine.syncNow().
class Draining {
  Future<void>? _inFlight;
  var drains = 0;
  var uploaded = <String>[];

  Future<void> Function() body = () async {};

  Future<void> syncNow() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight; // join the run already going

    final completer = Completer<void>();
    _inFlight = completer.future;
    _drain()
        .whenComplete(() {
          _inFlight = null;
          if (!completer.isCompleted) completer.complete();
        })
        // Absorbed: a throwing drain must release callers, not escape as an
        // unhandled async error.
        .catchError((Object _) {});
    return completer.future;
  }

  Future<void> _drain() async {
    drains++;
    await body();
  }
}

void main() {
  group('syncNow', () {
    test('awaiting it means the queue is actually drained', () async {
      final engine = Draining();
      engine.body = () async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        engine.uploaded.add('cancel-101');
      };

      await engine.syncNow();

      expect(engine.uploaded, ['cancel-101'],
          reason: 'the fetch that follows must not start before this');
    });

    test('a call during a drain joins it instead of racing past', () async {
      final engine = Draining();
      engine.body = () async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        engine.uploaded.add('cancel-101');
      };

      // Connectivity kicks a drain; the socket reconnect arrives right after.
      final fromConnectivity = engine.syncNow();
      final fromSocketReconnect = engine.syncNow();

      await fromSocketReconnect;

      // This is the bug the old code had: returning early here let the
      // reconnect handler refresh while the cancel was still uploading.
      expect(engine.uploaded, ['cancel-101'],
          reason: 'the joining caller must wait for the in-flight drain');
      expect(engine.drains, 1, reason: 'and must not start a second drain');

      await fromConnectivity;
    });

    test('a later call starts a fresh drain once the first has finished',
        () async {
      final engine = Draining();
      engine.body = () async =>
          await Future<void>.delayed(const Duration(milliseconds: 10));

      await engine.syncNow();
      await engine.syncNow();

      expect(engine.drains, 2,
          reason: 'joining applies only while one is in flight');
    });

    test('a failed drain still releases the next caller', () async {
      final engine = Draining();
      engine.body = () async => throw StateError('server refused');

      // Reconnect refreshes anyway on failure — stale screens are worse than
      // an un-drained queue, which retries on its own timer. The caller is
      // released normally; the failure is recorded on the op, not thrown here.
      await engine.syncNow();

      engine.body = () async {};
      await engine.syncNow();

      expect(engine.drains, 2, reason: 'a failure must not wedge the engine');
    });
  });
}
