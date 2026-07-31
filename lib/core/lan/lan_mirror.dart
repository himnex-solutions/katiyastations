// ============================================================
// KATIYA STATION RMS — LAN MIRROR (platform-neutral)
//
// Turns an envelope received over the LAN into local state, and builds the
// envelopes this device publishes.
//
// THE WHOLE TRICK LIVES HERE. Every screen that matters already reads offline
// data from this device's own store: the cashier's bill goes through
// sessionBillingProvider → sessionKotsProvider, which merges server KOTs with
// OfflineStore.kotsForSession(); the tables grid overlays
// OfflineCache.allOfflineSessionsByTable(). So writing a peer's offline order
// into those exact structures makes it appear on the till, the tables grid and
// the kitchen screen with no UI changes at all.
//
// THE ONE INVARIANT: a mirror is NEVER enqueued into this device's outbox.
// The origin device remains the sole uploader of its own work. Break this and
// two devices race to create the same bill.
//
// Mirrors are self-cleaning. Both tables_provider._pendingOfflineSessions and
// ._billedOfflineSessions drop any offline record with no matching outbox op
// once the device is back online — a mirror has none by construction, so it
// evaporates exactly when the server copy becomes authoritative.
// ============================================================

import '../offline/offline_cache.dart';
import '../offline/offline_store.dart';
import 'lan_protocol.dart';

class LanMirror {
  LanMirror._();

  // ── Outgoing: build envelopes to publish ─────────────────────

  /// A table opened on this device. [sessionJson] is the server-shaped session
  /// map already written to OfflineCache, passed through verbatim so the peer
  /// stores byte-identical data and TableSession.fromJson works unchanged.
  static LanEnvelope sessionEnvelope({
    required String deviceId,
    required String branchId,
    required String tableId,
    required Map<String, dynamic> sessionJson,
  }) =>
      LanEnvelope(
        id: 'session:${sessionJson['id']}',
        branchId: branchId,
        deviceId: deviceId,
        kind: LanKind.session,
        at: DateTime.now(),
        data: {'tableId': tableId, 'session': sessionJson},
      );

  /// An order sent from this device. Carries the line items denormalized
  /// (name + unit price), so the receiving till can price the bill without
  /// needing its own menu cache to be in step.
  static LanEnvelope kotEnvelope({
    required String deviceId,
    required OfflineKot kot,
    required List<OfflineKotItem> items,
  }) =>
      LanEnvelope(
        id: 'kot:${kot.id}',
        branchId: kot.branchId,
        deviceId: deviceId,
        kind: LanKind.kot,
        at: DateTime.now(),
        data: {
          'kot': kot.toJson(),
          'items': items.map((i) => i.toJson()).toList(),
        },
      );

  /// A session settled on this device — tells every other device to stop
  /// offering that table for billing and show it free.
  static LanEnvelope billEnvelope({
    required String deviceId,
    required String branchId,
    required String sessionId,
  }) =>
      LanEnvelope(
        id: 'bill:$sessionId',
        branchId: branchId,
        deviceId: deviceId,
        kind: LanKind.bill,
        at: DateTime.now(),
        data: {'sessionId': sessionId},
      );

  /// An order voided on this device.
  static LanEnvelope kotVoidEnvelope({
    required String deviceId,
    required String branchId,
    required String kotId,
  }) =>
      LanEnvelope(
        id: 'kotvoid:$kotId',
        branchId: branchId,
        deviceId: deviceId,
        kind: LanKind.kotVoid,
        at: DateTime.now(),
        data: {'kotId': kotId},
      );

  // ── Incoming: apply an envelope locally ──────────────────────

  /// Writes [env] into this device's offline store. Returns true when local
  /// state actually changed, so the caller only invalidates providers when
  /// there is something new to show.
  ///
  /// Never throws: this runs inside the socket receive loop, and one malformed
  /// payload from a peer must not tear down LAN sync for the whole shift.
  static Future<bool> apply(LanEnvelope env) async {
    try {
      switch (env.kind) {
        case LanKind.session:
          return await _applySession(env);
        case LanKind.kot:
          return await _applyKot(env);
        case LanKind.bill:
          return await _applyBill(env);
        case LanKind.kotVoid:
          return await _applyKotVoid(env);
        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _applySession(LanEnvelope env) async {
    final tableId = env.data['tableId'] as String?;
    final session = env.data['session'];
    if (tableId == null || session is! Map) return false;
    await OfflineCache.instance
        .putOfflineSession(tableId, Map<String, dynamic>.from(session));
    return true;
  }

  static Future<bool> _applyKot(LanEnvelope env) async {
    final kotJson = env.data['kot'];
    final itemsJson = env.data['items'];
    if (kotJson is! Map || itemsJson is! List) return false;

    final kot = OfflineKot.fromJson(Map<String, dynamic>.from(kotJson));
    final items = itemsJson
        .whereType<Map>()
        .map((i) => OfflineKotItem.fromJson(Map<String, dynamic>.from(i)))
        .toList();

    // Upserts on the KOT's client UUID, so redelivery is a no-op rather than a
    // duplicate ticket on the bill.
    await OfflineStore.instance.saveOfflineKot(kot, items);
    return true;
  }

  static Future<bool> _applyBill(LanEnvelope env) async {
    final sessionId = env.data['sessionId'] as String?;
    if (sessionId == null) return false;
    // Marks the session settled on this device too, so a second till can't bill
    // it again during the same outage and the table shows free everywhere.
    await OfflineCache.instance.putBilledOfflineSession(sessionId);
    return true;
  }

  static Future<bool> _applyKotVoid(LanEnvelope env) async {
    final kotId = env.data['kotId'] as String?;
    if (kotId == null) return false;
    await OfflineStore.instance.deleteOfflineKot(kotId);
    return true;
  }
}
