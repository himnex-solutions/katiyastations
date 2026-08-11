// End-to-end tests for LAN sync over real localhost sockets.
//
// These drive two live NativeLanSync instances — an actual HttpServer and an
// actual WebSocket — because the failure this feature exists to prevent (a
// waiter's offline order never reaching the till) is a transport failure. A
// test with the transport mocked out would not have caught it.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:katiya_station_rms/core/lan/lan_config.dart';
import 'package:katiya_station_rms/core/lan/lan_mirror.dart';
import 'package:katiya_station_rms/core/lan/lan_protocol.dart';
import 'package:katiya_station_rms/core/lan/lan_sync_io.dart';
import 'package:katiya_station_rms/core/offline/offline_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _branch = 'branch-katiya-1';

/// Overrides nothing, so HttpClient() falls through to the real dart:io one —
/// used to undo the test binding's stub for the probe test below.
class _RealHttpOverrides extends HttpOverrides {}

/// A free ephemeral port, so a developer running the real app on 8787 doesn't
/// collide with the test suite.
Future<int> freePort() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return port;
}

LanConfig hubConfig(int port) =>
    LanConfig(enabled: true, isHub: true, port: port, deviceId: 'cashier-pc');

LanConfig clientConfig(int port, {String deviceId = 'waiter-tablet'}) => LanConfig(
      enabled: true,
      isHub: false,
      manualHost: '127.0.0.1',
      port: port,
      deviceId: deviceId,
    );

/// An order exactly as the offline path stores it before publishing.
LanEnvelope momoOrder({
  String kotId = 'kot-uuid-1',
  String deviceId = 'waiter-tablet',
}) {
  final now = DateTime.now();
  final kot = OfflineKot()
    ..id = kotId
    ..branchId = _branch
    ..sessionId = 'session-uuid-1'
    ..tableId = 'table-7'
    ..kotNumber = 'OFF-3F9A'
    ..status = 'pending'
    ..waiterName = 'Bikash'
    ..createdAt = now
    ..isPendingSync = true
    ..syncedAt = now;

  final items = [
    OfflineKotItem()
      ..id = 'item-1'
      ..kotId = kotId
      ..menuItemId = 'menu-momo'
      ..menuItemName = 'Chicken Momo'
      ..quantity = 2
      ..unitPrice = 280
      ..createdAt = now,
  ];

  return LanMirror.kotEnvelope(deviceId: deviceId, kot: kot, items: items);
}

/// A kitchen ticket a waiter's tablet hands to the hub, which owns the printer.
LanEnvelope printJob({
  String kotId = 'kot-uuid-1',
  String deviceId = 'waiter-tablet',
}) =>
    LanMirror.printJobEnvelope(
      deviceId: deviceId,
      branchId: _branch,
      role: LanPrintRole.kitchen,
      jobId: kotId,
      ticket: {
        'kotNumber': 'OFF-3F9A',
        'tableNumber': '7',
        'items': [
          {'name': 'Chicken Momo', 'quantity': 2}
        ],
      },
    );

/// Waits for [check] to hold, polling rather than sleeping a fixed time so the
/// tests stay fast on a quick machine and reliable on a slow one.
Future<void> waitFor(
  bool Function() check, {
  Duration timeout = const Duration(seconds: 10),
  String describe = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('Timed out waiting for $describe');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NativeLanSync hub;
  late NativeLanSync client;
  late int port;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    port = await freePort();
    hub = NativeLanSync();
    client = NativeLanSync();
  });

  tearDown(() async {
    await client.stop();
    await hub.stop();
  });

  Future<void> startPair() async {
    await hub.start(config: hubConfig(port), branchId: _branch);
    await client.start(config: clientConfig(port), branchId: _branch);
    await waitFor(() => client.status.role == LanRole.client,
        describe: 'client to reach the hub');
  }

  test('hub comes up and a client connects to it', () async {
    await startPair();

    expect(hub.status.role, LanRole.hub);
    expect(client.status.address, '127.0.0.1:$port');
    await waitFor(() => hub.status.peerCount == 1, describe: 'hub to count the peer');
  });

  test('an order published by a waiter reaches the hub', () async {
    await startPair();

    final arrived = hub.applied.first;
    client.publish(momoOrder());

    final env = await arrived.timeout(const Duration(seconds: 10));
    expect(env.kind, LanKind.kot);
    expect(env.deviceId, 'waiter-tablet');
    expect((env.data['kot'] as Map)['kotNumber'], 'OFF-3F9A');
    expect((env.data['items'] as List).single['menuItemName'], 'Chicken Momo');
    // Sequenced on arrival, which is what lets a reconnecting device catch up.
    expect(env.seq, greaterThan(0));
  });

  test('the same order published twice is mirrored only once', () async {
    await startPair();

    final seen = <LanEnvelope>[];
    final sub = hub.applied.listen(seen.add);

    // Same envelope id both times — this is what a resend after a Wi-Fi blip
    // looks like, and it must not become two tickets on the bill.
    client.publish(momoOrder());
    client.publish(momoOrder());

    await waitFor(() => seen.isNotEmpty, describe: 'the order to arrive');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await sub.cancel();

    expect(seen, hasLength(1));
  });

  test('an order reaches a second waiter device, but is not echoed back to '
      'the device that sent it', () async {
    await startPair();

    final other = NativeLanSync();
    addTearDown(other.stop);
    await other.start(
      config: clientConfig(port, deviceId: 'waiter-tablet-2'),
      branchId: _branch,
    );
    await waitFor(() => other.status.role == LanRole.client,
        describe: 'the second waiter to connect');

    final onOther = <LanEnvelope>[];
    final onSender = <LanEnvelope>[];
    final subOther = other.applied.listen(onOther.add);
    final subSender = client.applied.listen(onSender.add);

    client.publish(momoOrder());

    await waitFor(() => onOther.isNotEmpty, describe: 'fan-out to the second device');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await subOther.cancel();
    await subSender.cancel();

    expect(onOther.single.data['kot'], isNotNull);
    expect(onSender, isEmpty, reason: 'the origin already has this order locally');
  });

  test('a print job reaches the hub and no other device', () async {
    await startPair();

    final other = NativeLanSync();
    addTearDown(other.stop);
    await other.start(
      config: clientConfig(port, deviceId: 'waiter-tablet-2'),
      branchId: _branch,
    );
    await waitFor(() => other.status.role == LanRole.client,
        describe: 'the second waiter to connect');

    final onHub = <LanEnvelope>[];
    final onOther = <LanEnvelope>[];
    final subHub = hub.applied.listen(onHub.add);
    final subOther = other.applied.listen(onOther.add);

    client.publish(printJob());

    await waitFor(() => onHub.isNotEmpty, describe: 'the ticket to reach the hub');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await subHub.cancel();
    await subOther.cancel();

    expect(onHub.single.kind, LanKind.printJob);
    expect(onHub.single.data['role'], LanPrintRole.kitchen);
    // The hub owns the printers. Fanning a ticket out to the other tablets
    // would have every device that can print put the same order on paper.
    expect(onOther, isEmpty,
        reason: 'a print job is addressed to the hub alone');
  });

  test('a tablet that reconnects does not have its old tickets reprinted',
      () async {
    await startPair();

    final onHub = <LanEnvelope>[];
    final sub = hub.applied.listen(onHub.add);

    client.publish(printJob());
    await waitFor(() => onHub.isNotEmpty, describe: 'the ticket to reach the hub');

    // The waiter's tablet drops off and comes back — it re-sends everything it
    // published in the last few minutes, because a frame lost mid-blip is
    // never acknowledged by anyone. The kitchen must not cook it twice.
    await client.stop();
    await client.start(config: clientConfig(port), branchId: _branch);
    await waitFor(() => client.status.role == LanRole.client,
        describe: 'the waiter to reconnect');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await sub.cancel();

    expect(onHub, hasLength(1));
  });

  test('a device that was away catches up on what it missed', () async {
    await startPair();

    // Waiter A is connected; waiter B is not running yet.
    final sawFirst = client.applied.first;
    final away = NativeLanSync();
    addTearDown(away.stop);

    // Something happens while B is away.
    final other = NativeLanSync();
    addTearDown(other.stop);
    await other.start(
      config: clientConfig(port, deviceId: 'waiter-tablet-2'),
      branchId: _branch,
    );
    await waitFor(() => other.status.role == LanRole.client,
        describe: 'the second waiter to connect');
    other.publish(momoOrder(kotId: 'kot-uuid-2', deviceId: 'waiter-tablet-2'));
    await sawFirst.timeout(const Duration(seconds: 10));

    // B starts up now and must be told about the order it never saw — this is
    // the app being restarted mid-outage.
    final caughtUp = away.applied.first;
    await away.start(
      config: clientConfig(port, deviceId: 'waiter-tablet-3'),
      branchId: _branch,
    );

    final env = await caughtUp.timeout(const Duration(seconds: 10));
    expect((env.data['kot'] as Map)['id'], 'kot-uuid-2');
  });

  group('connection stability', () {
    // Context: the link was dropping and re-establishing itself on its own.
    // lanSyncProvider re-ran on every auth refresh, each run re-entered
    // start(), and a stale socket's close handler then cleared the live one.
    //
    // HONEST SCOPE: these do NOT reproduce that race. Verified by reverting
    // all three guards (start serialisation, _connecting in _isRunning, the
    // socket-identity check in _onClientClosed) — every test below still
    // passed. On loopback the connect window is sub-millisecond, so a rebuild
    // can't land inside it; the real bug needs a slow LAN connect (discovery
    // takes up to 2s) plus an auth rebuild arriving during it. Reproducing
    // that reliably would need a delay seam injected into production code.
    //
    // What these DO pin down is that the guards didn't break normal
    // operation: a repeat start() is a no-op, a real config change still
    // reconnects, and the link still carries orders after heavy churn.

    test('repeated start() with unchanged settings leaves the link alone',
        () async {
      await startPair();
      await waitFor(() => hub.status.peerCount == 1, describe: 'the peer to register');

      for (var i = 0; i < 10; i++) {
        await client.start(config: clientConfig(port), branchId: _branch);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(client.status.role, LanRole.client);
      expect(hub.status.peerCount, 1, reason: 'no duplicate connections');
    });

    test('start() calls fired concurrently settle on one connection', () async {
      await hub.start(config: hubConfig(port), branchId: _branch);

      // All at once, without awaiting in between — the interleaving that used
      // to open several sockets at the same time.
      await Future.wait(List.generate(
        5,
        (_) => client.start(config: clientConfig(port), branchId: _branch),
      ));

      await waitFor(() => client.status.role == LanRole.client,
          describe: 'the client to connect');
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(hub.status.peerCount, 1);
      expect(client.status.role, LanRole.client);
    });

    test('the link stays up and usable through repeated restarts', () async {
      await startPair();

      // Sample continuously: a flap shows up as a trip through searching.
      final roles = <LanRole>{};
      final ticker = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => roles.add(client.status.role),
      );

      for (var i = 0; i < 5; i++) {
        await client.start(config: clientConfig(port), branchId: _branch);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      ticker.cancel();

      expect(roles, {LanRole.client}, reason: 'never dropped to searching');

      // And it still actually carries an order afterwards.
      final arrived = hub.applied.first;
      client.publish(momoOrder(kotId: 'kot-after-churn'));
      final env = await arrived.timeout(const Duration(seconds: 10));
      expect((env.data['kot'] as Map)['id'], 'kot-after-churn');
    });

    test('a genuine config change still reconnects', () async {
      await startPair();

      // Changing the hub address must NOT be swallowed by the no-op guard.
      final moved = await freePort();
      await client.start(
        config: LanConfig(
          enabled: true,
          isHub: false,
          manualHost: '127.0.0.1',
          port: moved,
          deviceId: 'waiter-tablet',
        ),
        branchId: _branch,
      );

      expect(client.status.address, isNot('127.0.0.1:$port'));
      await waitFor(() => hub.status.peerCount == 0,
          describe: 'the old hub to see the peer leave');
    });
  });

  test('a hub refuses a device from a different branch', () async {
    await hub.start(config: hubConfig(port), branchId: _branch);

    final stranger = NativeLanSync();
    addTearDown(stranger.stop);
    await stranger.start(
      config: clientConfig(port, deviceId: 'other-branch-device'),
      branchId: 'branch-somewhere-else',
    );

    // It should never settle into a connected state.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(stranger.status.role, isNot(LanRole.client));
    expect(hub.status.peerCount, 0);
  });

  test('probe reports success against a live hub and failure against nothing',
      () async {
    await hub.start(config: hubConfig(port), branchId: _branch);
    await client.start(config: clientConfig(port), branchId: _branch);

    // TestWidgetsFlutterBinding installs a global HttpOverrides that answers
    // every request with a stub 400 and makes no real connection. probe() is
    // the one path here that speaks plain HTTP, so give it back a real client
    // for the duration — otherwise this asserts on the harness, not the code.
    await HttpOverrides.runWithHttpOverrides(() async {
      expect(await client.probe('127.0.0.1', port), isNull);

      final dead = await freePort();
      expect(await client.probe('127.0.0.1', dead), isNotNull);
    }, _RealHttpOverrides());
  });

  test('publishing with no hub reachable does not throw, and the order is '
      'delivered once the hub appears', () async {
    // The waiter must be able to send an order whether or not the till is up.
    await client.start(config: clientConfig(port), branchId: _branch);
    expect(client.status.role, isNot(LanRole.client));

    client.publish(momoOrder());

    // Till comes back on.
    await hub.start(config: hubConfig(port), branchId: _branch);

    final arrived = hub.applied.first;
    await waitFor(() => client.status.role == LanRole.client,
        timeout: const Duration(seconds: 30),
        describe: 'the client to find the hub that just started');

    final env = await arrived.timeout(const Duration(seconds: 10));
    expect((env.data['kot'] as Map)['kotNumber'], 'OFF-3F9A');
  });
}
