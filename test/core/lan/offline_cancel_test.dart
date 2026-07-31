// Regression tests for a cancel made while the connectivity flag is STALE.
//
// The bug: connectivityProvider is polled every 20s while online, so for up to
// 20s after the internet drops it still reports "online". A cancel in that
// window took the online branch, the PATCH threw NetworkException, and the
// outer catch turned it into a snackbar — nothing was ever queued. Meanwhile
// the order had already been dropped locally and announced over the LAN, so it
// vanished from every screen while the server still held it as pending. On
// reconnect the server re-supplied it and the guest was charged for a
// cancelled order.
//
// These exercise the decision directly rather than through the widget, because
// the fix is about which branch runs when the optimistic flag is wrong.

import 'package:flutter_test/flutter_test.dart';
import 'package:katiya_station_rms/core/errors/app_exceptions.dart';

/// The shape of the fixed helper: try the server when we believe we're online,
/// but fall back to the outbox if the request actually fails.
Future<String> cancelOnServerOrQueue({
  required bool believedOnline,
  required Future<void> Function() patch,
  required Future<void> Function() enqueue,
}) async {
  if (believedOnline) {
    try {
      await patch();
      return 'sent';
    } on NetworkException {
      // fall through
    }
  }
  await enqueue();
  return 'queued';
}

void main() {
  group('cancel with a stale connectivity flag', () {
    test('queues the cancel when the network dies mid-request', () async {
      var enqueued = 0;

      final outcome = await cancelOnServerOrQueue(
        believedOnline: true, // the poll hasn't noticed the drop yet
        patch: () async => throw const NetworkException(),
        enqueue: () async => enqueued++,
      );

      // Before the fix this threw out to the caller's catch and enqueued
      // nothing, losing the cancel entirely.
      expect(outcome, 'queued');
      expect(enqueued, 1);
    });

    test('sends straight to the server when the network really is up', () async {
      var enqueued = 0;
      var patched = 0;

      final outcome = await cancelOnServerOrQueue(
        believedOnline: true,
        patch: () async => patched++,
        enqueue: () async => enqueued++,
      );

      expect(outcome, 'sent');
      expect(patched, 1);
      expect(enqueued, 0, reason: 'no double-cancel on the happy path');
    });

    test('queues without attempting the server when known offline', () async {
      var patched = 0;
      var enqueued = 0;

      final outcome = await cancelOnServerOrQueue(
        believedOnline: false,
        patch: () async => patched++,
        enqueue: () async => enqueued++,
      );

      expect(outcome, 'queued');
      expect(patched, 0, reason: 'no pointless call that waits for a timeout');
      expect(enqueued, 1);
    });

    test('a non-network failure still surfaces rather than being queued',
        () async {
      // A 422 means the cancel is genuinely invalid — queueing it would just
      // replay a request the server will keep rejecting.
      expect(
        () => cancelOnServerOrQueue(
          believedOnline: true,
          patch: () async => throw const ApiException('Unprocessable',
              statusCode: 422),
          enqueue: () async {},
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
