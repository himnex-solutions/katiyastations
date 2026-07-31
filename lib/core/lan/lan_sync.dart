// ============================================================
// KATIYA STATION RMS — LAN SYNC (platform-selected)
//
// The device-to-device channel that keeps the cashier's till in step with the
// waiters' tablets while the internet is down. Defines the platform-neutral
// CONTRACT; the concrete backend is chosen at compile time:
//   • Native (Android / Windows / iOS / desktop) → dart:io HttpServer +
//     WebSocket + UDP discovery         (lan_sync_io.dart)
//   • Web (dart2js / dart2wasm)         → inert no-op (lan_sync_stub.dart)
//
// Web can't take part at all: a browser can't listen on a socket, and a page
// served over https is blocked from calling a plain-http LAN address. Same
// conditional-import shape as offline_store.dart, for the same reason — the
// unsupported implementation must never be reachable from the web entrypoint.
// ============================================================

import 'lan_config.dart';
import 'lan_protocol.dart';

// The stub is the default; native overrides it wherever dart:io exists.
import 'lan_sync_stub.dart' if (dart.library.io) 'lan_sync_io.dart' as impl;

export 'lan_protocol.dart';

abstract class LanSync {
  /// The platform-appropriate singleton.
  static final LanSync instance = impl.createLanSync();

  /// Current role/address/counters, for the Settings card.
  LanStatus get status;

  /// Fires whenever [status] changes.
  Stream<LanStatus> get statusStream;

  /// Envelopes received from a peer and already applied to this device's
  /// offline store. Listen to invalidate the providers the mirror affects —
  /// the data is on disk by the time it arrives here.
  Stream<LanEnvelope> get applied;

  /// Brings LAN sync up (or reconfigures it) for [branchId]. Safe to call
  /// repeatedly; an unchanged config is a no-op. Best-effort throughout — a
  /// blocked port or a hostile firewall must degrade to today's behaviour, not
  /// break the POS.
  Future<void> start({required LanConfig config, required String branchId});

  /// Tears everything down (logout, or the switch being turned off).
  Future<void> stop();

  /// Replicates a mutation to every other device. Fire-and-forget: it never
  /// throws and never blocks the caller, because it sits directly in the path
  /// of sending an order. When the link is down the envelope is buffered and
  /// flushed on reconnect.
  void publish(LanEnvelope envelope);

  /// One-shot probe of a hub address, for the "Test connection" button.
  /// Returns null on success, or a human-readable reason it failed.
  Future<String?> probe(String host, int port);
}
