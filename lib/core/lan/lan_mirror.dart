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

import 'dart:convert';

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

  /// A single line voided off an order on this device. [sessionId] travels
  /// with it because the offline store is only indexed by session.
  /// [menuItemId] locates the line in a locally-stored offline copy;
  /// [itemId] is the server's row id, which is what a tombstone is keyed on so
  /// the line can also be suppressed from server data.
  static LanEnvelope kotItemVoidEnvelope({
    required String deviceId,
    required String branchId,
    required String sessionId,
    required String kotId,
    required String menuItemId,
    String? itemId,
  }) =>
      LanEnvelope(
        id: 'kotitemvoid:$kotId:$menuItemId',
        branchId: branchId,
        deviceId: deviceId,
        kind: LanKind.kotItemVoid,
        at: DateTime.now(),
        data: {
          'sessionId': sessionId,
          'kotId': kotId,
          'menuItemId': menuItemId,
          if (itemId != null) 'itemId': itemId,
        },
      );

  /// A ticket for the hub to print, from a device that does not own a printer.
  ///
  /// [jobId] must be stable for the ticket it describes and unique across
  /// tickets — it is the only thing standing between a resend after a Wi-Fi
  /// blip and the kitchen cooking the same order twice. Key it on the KOT's id
  /// plus what the slip is for, never on a timestamp.
  static LanEnvelope printJobEnvelope({
    required String deviceId,
    required String branchId,
    required String role,
    required String jobId,
    required Map<String, dynamic> ticket,
  }) =>
      LanEnvelope(
        id: 'print:$role:$jobId',
        branchId: branchId,
        deviceId: deviceId,
        kind: LanKind.printJob,
        at: DateTime.now(),
        data: {'role': role, 'ticket': ticket},
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
        case LanKind.kotItemVoid:
          return await _applyKotItemVoid(env);
        case LanKind.printJob:
          // Nothing to store — a print job is an instruction, not state.
          // Returning true is what puts it on the `applied` stream, where the
          // hub's print station picks it up (see lan_print_station.dart). On a
          // device that is not the hub nothing is listening, and the hub never
          // forwards these anyway.
          return true;
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

    // Never resurrect something already cancelled here. Delivery is
    // at-least-once, so this order can arrive again — a peer resends anything
    // published in the last few minutes on reconnect, and a hub restart clears
    // the dedup set that would otherwise have absorbed it.
    final cancelled = await OfflineCache.instance.cancelledKotIds();
    if (cancelled.contains(kot.id)) return false;
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
    // If THIS device is the one that took the order and it hasn't uploaded
    // yet, drop the queued create as well. Otherwise the void applies here but
    // the create still syncs on reconnect, and the cancelled order comes back
    // from the server — the cancel and the create racing each other through
    // two independent outboxes.
    await _dropQueuedCreate(kotId);
    await OfflineStore.instance.deleteOfflineKot(kotId);
    // Hold the same tombstone the cancelling device holds, so this device also
    // refuses to show the order if the server reports it still pending before
    // that device's queued cancel has landed.
    await OfflineCache.instance.putCancelledKot(kotId);
    return true;
  }

  /// Removes a not-yet-uploaded `kot` create from this device's outbox, so a
  /// voided order never reaches the server at all. No-op when the order was
  /// never queued here (a mirror, or an order that synced online).
  static Future<void> _dropQueuedCreate(String kotId) async {
    final ops = await OfflineStore.instance.pendingOps();
    for (final op in ops) {
      if (op.entityType != 'kot' || op.operation != 'create' || op.id == null) {
        continue;
      }
      try {
        final data = jsonDecode(op.payload) as Map<String, dynamic>;
        if (data['id'] == kotId) {
          await OfflineStore.instance.deleteOp(op.id!);
          return;
        }
      } catch (_) {/* skip a malformed queued op */}
    }
  }

  /// Trims one line out of a not-yet-uploaded `kot` create, so a line voided
  /// elsewhere isn't re-added when this device's order finally uploads. Drops
  /// the whole op if that was the last line.
  static Future<bool> _trimQueuedCreate(String kotId, String menuItemId) async {
    final ops = await OfflineStore.instance.pendingOps();
    for (final op in ops) {
      if (op.entityType != 'kot' || op.operation != 'create' || op.id == null) {
        continue;
      }
      try {
        final data = jsonDecode(op.payload) as Map<String, dynamic>;
        if (data['id'] != kotId) continue;
        final items =
            (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final remaining =
            items.where((i) => i['menuItemId'] != menuItemId).toList();
        if (remaining.isEmpty) {
          await OfflineStore.instance.deleteOp(op.id!);
        } else {
          data['items'] = remaining;
          op.payload = jsonEncode(data);
          await OfflineStore.instance.saveOp(op);
        }
        return true;
      } catch (_) {/* skip a malformed queued op */}
    }
    return false;
  }

  static Future<bool> _applyKotItemVoid(LanEnvelope env) async {
    final sessionId = env.data['sessionId'] as String?;
    final kotId = env.data['kotId'] as String?;
    final menuItemId = env.data['menuItemId'] as String?;
    if (sessionId == null || kotId == null || menuItemId == null) return false;
    // Same reasoning as _applyKotVoid: if this device still has the order
    // queued, the voided line has to come out of the payload too, and a
    // tombstone keeps the server from re-supplying it in the meantime.
    final itemId = env.data['itemId'] as String?;
    if (itemId != null) await OfflineCache.instance.putCancelledItem(itemId);
    final trimmedQueue = await _trimQueuedCreate(kotId, menuItemId);
    final trimmedLocal = await dropItemLocally(
      sessionId: sessionId,
      kotId: kotId,
      menuItemId: menuItemId,
    );
    return trimmedQueue || trimmedLocal || itemId != null;
  }

  // ── Local void helpers ───────────────────────────────────────
  // Shared with the cashier screen, which needs the same edit when it voids a
  // LAN-mirrored order: a mirror carries no outbox op, so the existing
  // outbox-driven void path finds nothing and leaves the line on the bill.

  /// Removes one menu item from a locally-stored offline KOT. Voids the whole
  /// KOT when it was the last line. Returns false if no local copy exists —
  /// meaning it is a server-side order to cancel through the API instead.
  static Future<bool> dropItemLocally({
    required String sessionId,
    required String kotId,
    required String menuItemId,
  }) async {
    final kots = await OfflineStore.instance.kotsForSession(sessionId);
    OfflineKot? stored;
    for (final k in kots) {
      if (k.id == kotId) {
        stored = k;
        break;
      }
    }
    if (stored == null) return false;

    final items = await OfflineStore.instance.itemsForKot(kotId);
    final remaining = items.where((i) => i.menuItemId != menuItemId).toList();

    // delete + re-save is what actually drops the row: saveOfflineKot upserts
    // the items it is given and leaves any others in place.
    await OfflineStore.instance.deleteOfflineKot(kotId);
    if (remaining.isNotEmpty) {
      await OfflineStore.instance.saveOfflineKot(stored, remaining);
    }
    return true;
  }

  /// Drops a locally-stored offline KOT outright. Returns false when there was
  /// no local copy to drop.
  static Future<bool> dropKotLocally({
    required String sessionId,
    required String kotId,
  }) async {
    final kots = await OfflineStore.instance.kotsForSession(sessionId);
    if (!kots.any((k) => k.id == kotId)) return false;
    await OfflineStore.instance.deleteOfflineKot(kotId);
    return true;
  }
}
