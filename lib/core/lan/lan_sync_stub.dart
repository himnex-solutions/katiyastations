// ============================================================
// KATIYA STATION RMS — LAN SYNC (web / unsupported platform)
// Inert implementation selected by the conditional import in lan_sync.dart
// wherever dart:io is absent.
//
// A browser cannot host a server socket, and a page served over https is
// blocked by mixed-content rules from calling http://192.168.x.x — so web
// devices stay cloud-only. Everything here no-ops rather than throwing, so
// call sites need no platform checks.
// ============================================================

import 'lan_config.dart';
import 'lan_sync.dart';

/// Factory referenced by the conditional import in lan_sync.dart.
LanSync createLanSync() => const _NoopLanSync();

class _NoopLanSync implements LanSync {
  const _NoopLanSync();

  @override
  LanStatus get status => const LanStatus(
        role: LanRole.unsupported,
        detail: 'Local hub sync needs the Windows or Android app.',
      );

  @override
  Stream<LanStatus> get statusStream => const Stream.empty();

  @override
  Stream<LanEnvelope> get applied => const Stream.empty();

  @override
  Future<void> start({required LanConfig config, required String branchId}) async {}

  @override
  Future<void> stop() async {}

  @override
  void publish(LanEnvelope envelope) {}

  @override
  Future<String?> probe(String host, int port) async =>
      'Not supported in the browser.';
}
