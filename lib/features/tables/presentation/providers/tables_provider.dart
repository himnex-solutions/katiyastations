import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/lan/lan_config.dart';
import '../../../../core/lan/lan_mirror.dart';
import '../../../../core/lan/lan_sync.dart';
import '../../../../core/offline/connectivity_provider.dart';
import '../../../../core/offline/offline_cache.dart';
import '../../../../core/offline/offline_store.dart';
import '../../../../core/offline/offline_ids.dart';
import '../../../../core/offline/sync_engine.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/table_entities.dart';
import '../../../orders/presentation/providers/order_provider.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';

// ─── All tables (by branch) ────────────────────────────────────────────────
// Cached on success for offline viewing. While offline, cached tables are
// shown with any table opened offline overlaid as "occupied".
/// Offline-opened sessions that are STILL genuinely awaiting sync.
///
/// When online the server is authoritative: an offline session whose "open" is
/// no longer sitting in the sync outbox has already synced (and may since have
/// been billed and the table freed). Its local copy is then stale — keeping it
/// would re-mark a freed table "occupied" or resurrect a closed session, but
/// only on the device that still holds the stale entry. That's exactly the
/// "some screens show occupied, some available after settle" glitch. So prune
/// those against the outbox. Offline, keep them all (the server can't be asked).
Future<Map<String, Map<String, dynamic>>> _pendingOfflineSessions(bool online) async {
  final all = await OfflineCache.instance.allOfflineSessionsByTable();
  if (all.isEmpty || !online) return all;

  final ops = await OfflineStore.instance.pendingOps();
  final pendingIds = <String>{};
  for (final op in ops) {
    if (op.entityType != 'session') continue;
    try {
      final id = (jsonDecode(op.payload) as Map)['id'] as String?;
      if (id != null) pendingIds.add(id);
    } catch (_) {/* skip a malformed op */}
  }

  final live = <String, Map<String, dynamic>>{};
  for (final entry in all.entries) {
    final sid = entry.value['id'] as String?;
    if (sid != null && pendingIds.contains(sid)) {
      live[entry.key] = entry.value;
    } else {
      // Synced already (or the open permanently failed) — drop the stale copy.
      await OfflineCache.instance.removeOfflineSession(entry.key);
    }
  }
  return live;
}

/// Session ids settled offline on this device that are still awaiting sync.
/// When online, prune any whose bill op has already synced (no longer in the
/// outbox) — the server has since billed and freed the table, so the local
/// marker is stale. Offline, keep them all.
Future<Set<String>> _billedOfflineSessions(bool online) async {
  final ids = await OfflineCache.instance.billedOfflineSessionIds();
  if (ids.isEmpty || !online) return ids;

  final ops = await OfflineStore.instance.pendingOps();
  final pendingBillSessions = <String>{};
  for (final op in ops) {
    if (op.entityType != 'bill') continue;
    final m = RegExp(r'/sessions/([^/]+)/generate').firstMatch(op.endpoint);
    if (m != null) pendingBillSessions.add(m.group(1)!);
  }

  final live = <String>{};
  for (final sid in ids) {
    if (pendingBillSessions.contains(sid)) {
      live.add(sid);
    } else {
      await OfflineCache.instance.removeBilledOfflineSession(sid);
    }
  }
  return live;
}

/// Sessions CLOSED offline on this device and still awaiting sync. Pruned
/// against the outbox when online, exactly like [_billedOfflineSessions] —
/// once the close has synced the server frees the table itself.
Future<Set<String>> _closedOfflineSessions(bool online) async {
  final ids = await OfflineCache.instance.closedOfflineSessionIds();
  if (ids.isEmpty || !online) return ids;

  final ops = await OfflineStore.instance.pendingOps();
  final pending = <String>{};
  for (final op in ops) {
    if (op.entityType != 'session_close') continue;
    final m = RegExp(r'/sessions/([^/]+)/close').firstMatch(op.endpoint);
    if (m != null) pending.add(m.group(1)!);
  }

  final live = <String>{};
  for (final sid in ids) {
    if (pending.contains(sid)) {
      live.add(sid);
    } else {
      await OfflineCache.instance.removeClosedOfflineSession(sid);
    }
  }
  return live;
}

/// Hold states set offline and still awaiting sync, as sessionId → onHold.
/// Pruned against the outbox when online.
Future<Map<String, bool>> _heldOfflineSessions(bool online) async {
  final held = await OfflineCache.instance.heldOfflineSessions();
  if (held.isEmpty || !online) return held;

  final ops = await OfflineStore.instance.pendingOps();
  final pending = <String>{};
  for (final op in ops) {
    if (op.entityType != 'session_hold') continue;
    final m = RegExp(r'/sessions/([^/]+)/(un)?hold').firstMatch(op.endpoint);
    if (m != null) pending.add(m.group(1)!);
  }

  final live = <String, bool>{};
  for (final entry in held.entries) {
    if (pending.contains(entry.key)) {
      live[entry.key] = entry.value;
    } else {
      await OfflineCache.instance.removeHeldOfflineSession(entry.key);
    }
  }
  return live;
}

/// Sessions no longer occupying their table on this device — settled offline
/// or closed offline. Both free the table until the server is told.
Future<Set<String>> _freedOfflineSessions(bool online) async => {
      ...await _billedOfflineSessions(online),
      ...await _closedOfflineSessions(online),
    };

final tablesStreamProvider = FutureProvider<List<RestaurantTable>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final branchId = profile!.branchId!;
  final key = CacheKeys.tables(branchId);
  final online = ref.read(connectivityProvider);

  List<dynamic> rows;
  if (!online) {
    // Offline: serve the cached tables instantly instead of waiting for a
    // network call to time out first.
    final cached = await OfflineCache.instance.get(key);
    rows = cached is List ? cached : const <dynamic>[];
  } else {
    try {
      final response = await ApiClient.instance.get(
        ApiConstants.tables,
        queryParameters: {'branchId': branchId},
      );
      rows = response.data as List<dynamic>;
      await OfflineCache.instance.put(key, rows);
    } on NetworkException {
      final cached = await OfflineCache.instance.get(key);
      if (cached is! List) rethrow;
      rows = cached;
    }
  }

  var tables =
      rows.map((r) => RestaurantTable.fromJson(r as Map<String, dynamic>)).toList();

  // Overlay tables opened offline — their occupied state isn't on the server
  // yet, so without this a just-opened table would look free again. Only
  // still-pending offline sessions are overlaid; synced/stale ones are pruned
  // (see _pendingOfflineSessions) so a freed table can't stay stuck "occupied".
  final offlineSessions = await _pendingOfflineSessions(online);
  if (offlineSessions.isNotEmpty) {
    tables = tables.map((t) {
      final s = offlineSessions[t.id];
      if (s != null && t.status == TableStatus.available) {
        return t.copyWith(
          status: TableStatus.occupied,
          currentSessionId: s['id'] as String?,
        );
      }
      return t;
    }).toList();
  }

  // Free tables settled or closed OFFLINE on this device. The server still
  // shows them occupied until the queued bill/close syncs, so overlay them
  // free here — this is what lets the cashier settle or free a table offline
  // without it lingering "occupied" or being billable twice on this device.
  final freedOffline = await _freedOfflineSessions(online);
  if (freedOffline.isNotEmpty) {
    tables = tables.map((t) {
      final sid = t.currentSessionId;
      if (sid != null && freedOffline.contains(sid)) {
        return t.copyWith(status: TableStatus.available);
      }
      return t;
    }).toList();
  }

  tables.sort((a, b) => a.tableNumber.compareTo(b.tableNumber));
  return tables;
});

// ─── Active (open) sessions for the branch ─────────────────────────────────
final activeSessionsStreamProvider = FutureProvider<List<TableSession>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final branchId = profile!.branchId!;
  final key = CacheKeys.openSessions(branchId);
  final online = ref.read(connectivityProvider);

  var sessions = <TableSession>[];
  List<dynamic>? cachedRows;
  if (!online) {
    // Offline: read the cache straight away, no network round-trip.
    final cached = await OfflineCache.instance.get(key);
    cachedRows = cached is List ? cached : const <dynamic>[];
  } else {
    try {
      final response = await ApiClient.instance.get(
        ApiConstants.sessions,
        queryParameters: {'branchId': branchId, 'status': 'open'},
      );
      cachedRows = response.data as List<dynamic>;
      await OfflineCache.instance.put(key, cachedRows);
    } on NetworkException {
      final cached = await OfflineCache.instance.get(key);
      cachedRows = cached is List ? cached : const <dynamic>[];
    }
  }
  // Holds set offline — the server still reports the old value until the
  // queued hold/unhold syncs, so without this a waiter's hold appears to do
  // nothing until the connection returns. Overlaid on the raw row (the same
  // way offline sessions are) because TableSession has no copyWith.
  final heldOffline = await _heldOfflineSessions(online);
  Map<String, dynamic> withHold(Map<String, dynamic> json) {
    final onHold = heldOffline[json['id']];
    if (onHold == null) return json;
    return {...json, 'on_hold': onHold};
  }

  sessions = cachedRows
      .map((r) => TableSession.fromJson(withHold(r as Map<String, dynamic>)))
      .toList();

  // Include sessions opened offline that the server hasn't seen yet — but only
  // ones still pending sync, so a billed/closed session can't be resurrected as
  // "active" from a stale local copy (see _pendingOfflineSessions).
  final offlineSessions = await _pendingOfflineSessions(online);
  if (offlineSessions.isNotEmpty) {
    final ids = sessions.map((s) => s.id).toSet();
    for (final json in offlineSessions.values) {
      final s = TableSession.fromJson(withHold(json));
      if (!ids.contains(s.id)) sessions = [...sessions, s];
    }
  }

  // Drop sessions settled or closed offline on this device — the bill/close is
  // queued, so they're no longer active here even though the server hasn't
  // been told yet.
  final freedOffline = await _freedOfflineSessions(online);
  if (freedOffline.isNotEmpty) {
    sessions = sessions.where((s) => !freedOffline.contains(s.id)).toList();
  }

  return sessions;
});

// ─── Session for a specific table ─────────────────────────────────────────
final tableSessionProvider =
    FutureProvider.family<TableSession?, String>((ref, tableId) async {
  // Offline: resolve the session from local data instead of stalling on a
  // network call that will time out.
  if (!ref.read(connectivityProvider)) {
    // 1) A session opened offline on THIS device.
    final offline = await OfflineCache.instance.getOfflineSession(tableId);
    if (offline != null) return TableSession.fromJson(offline);
    // 2) A server session cached from the last online load — without this, an
    //    occupied table (opened on the server) couldn't be entered while
    //    offline because its session was invisible here.
    final branchId = ref.read(authNotifierProvider).value?.branchId;
    if (branchId != null) {
      final cached = await OfflineCache.instance.get(CacheKeys.openSessions(branchId));
      if (cached is List) {
        for (final r in cached) {
          if (r is Map && r['table_id'] == tableId) {
            return TableSession.fromJson(Map<String, dynamic>.from(r));
          }
        }
      }
    }
    return null;
  }
  try {
    final response =
        await ApiClient.instance.get(ApiConstants.currentSession(tableId));
    // The backend sends a body-less response (no Content-Type) when there's
    // no current session, which Dio decodes as an empty string rather than
    // null — so check the type, not just `== null`.
    final data = response.data;
    if (data is Map<String, dynamic>) return TableSession.fromJson(data);
    // No server session — but there may be one opened offline on this device.
    final offline = await OfflineCache.instance.getOfflineSession(tableId);
    return offline != null ? TableSession.fromJson(offline) : null;
  } on NetworkException {
    final offline = await OfflineCache.instance.getOfflineSession(tableId);
    return offline != null ? TableSession.fromJson(offline) : null;
  }
});

// ─── Reservations ───────────────────────────────────────────────────────────
// Backs the Reservations tab on the tables screen. `/reservations` is
// paginated — it answers `{ data: [...], meta: {...} }`, not a bare array —
// so the envelope has to come off before the rows can be mapped. Reading it
// as a List blew up with a TypeError the moment the tab was opened.
final reservationsStreamProvider = FutureProvider<List<TableReservation>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];

  final response = await ApiClient.instance.get(
    ApiConstants.reservations,
    // Without this the server's default page of 20 silently truncates a busy
    // evening's bookings. 100 is its `@Max(100)` ceiling.
    queryParameters: {'branchId': profile!.branchId!, 'limit': '100'},
  );
  final data = response.data as Map<String, dynamic>;
  final rows = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
  return rows.map(TableReservation.fromJson).toList()
    ..sort((a, b) => a.reservationTime.compareTo(b.reservationTime));
});

// ─── Table Notifier ────────────────────────────────────────────────────────
class TableNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  TableNotifier(this._ref) : super(const AsyncValue.data(null));

  String? get _branchId => _ref.read(authNotifierProvider).value?.branchId;

  void _invalidateAll(String tableId) {
    _ref.invalidate(tablesStreamProvider);
    _ref.invalidate(tableSessionProvider(tableId));
    _ref.invalidate(activeSessionsStreamProvider);
    _ref.invalidate(dashboardSessionsProvider);
  }

  // ── Open Session ────────────────────────────────────────────────────────
  Future<TableSession?> openSession(String tableId,
      {int guestCount = 1, String? notes}) async {
    state = const AsyncValue.loading();
    // Client-generated id, reused offline so a replay is idempotent server-side.
    final sessionId = newOfflineId();

    if (_ref.read(connectivityProvider)) {
      try {
        final response = await ApiClient.instance.post(
          ApiConstants.openSession(tableId),
          data: {'id': sessionId, 'guestCount': guestCount},
        );
        _invalidateAll(tableId);
        state = const AsyncValue.data(null);
        final sessionJson = response.data as Map<String, dynamic>;
        // Mirror over the LAN as well, for devices that can't hear the cloud
        // socket right now — a till that can't see the table open can't take
        // the orders that follow it.
        _publishSession(tableId, sessionJson);
        return TableSession.fromJson(sessionJson);
      } on NetworkException {
        // Dropped mid-request — open it offline instead.
      } catch (e) {
        state = AsyncValue.error(e.toString(), StackTrace.current);
        return null;
      }
    }

    return _openSessionOffline(tableId, sessionId, guestCount);
  }

  /// Tells the other devices on the LAN that this table is now open, passing
  /// the session JSON through verbatim so they store exactly what we did.
  /// Fire-and-forget — no hub, no problem.
  void _publishSession(String tableId, Map<String, dynamic> sessionJson) {
    final branchId = sessionJson['branch_id'] as String? ??
        _ref.read(authNotifierProvider).value?.branchId ??
        '';
    if (branchId.isEmpty) return;
    LanSync.instance.publish(LanMirror.sessionEnvelope(
      deviceId: _ref.read(lanConfigProvider).deviceId,
      branchId: branchId,
      tableId: tableId,
      sessionJson: sessionJson,
    ));
  }

  /// Opens a table locally and queues the "open" for upload — used when the
  /// device is offline. Returns a session with a provisional number so the
  /// waiter can start taking orders straight away.
  Future<TableSession?> _openSessionOffline(
      String tableId, String sessionId, int guestCount) async {
    final profile = _ref.read(authNotifierProvider).value;
    final now = DateTime.now();
    // Stored in the exact server JSON shape so TableSession.fromJson works and
    // the tables list / per-table lookup can both read it back.
    final sessionJson = <String, dynamic>{
      'id': sessionId,
      'table_id': tableId,
      'branch_id': profile?.branchId ?? '',
      'session_number': provisionalNumber(sessionId),
      'status': 'open',
      'waiter_id': profile?.id,
      'waiter_name': profile?.fullName,
      'guest_count': guestCount,
      'total_amount': 0,
      'opened_at': now.toIso8601String(),
      'bill_requested': false,
      'on_hold': false,
    };

    await OfflineCache.instance.putOfflineSession(tableId, sessionJson);
    _publishSession(tableId, sessionJson);
    await OfflineStore.instance.enqueue(
      entityType: 'session',
      operation: 'create',
      endpoint: ApiConstants.openSession(tableId),
      method: 'POST',
      payload: {'id': sessionId, 'guestCount': guestCount},
    );
    await _ref.read(pendingSyncProvider.notifier).refresh();

    _invalidateAll(tableId);
    state = const AsyncValue.data(null);
    return TableSession.fromJson(sessionJson);
  }

  // ── Request Bill ────────────────────────────────────────────────────────
  /// Returns null when the request went through, otherwise the reason it was
  /// refused — the server rejects a bill for food the kitchen hasn't served,
  /// and that message names how many orders are still out.
  Future<String?> requestBill(String tableId, String sessionId) async {
    state = const AsyncValue.loading();
    try {
      await ApiClient.instance.post(ApiConstants.requestBill(tableId));
      _invalidateAll(tableId);
      state = const AsyncValue.data(null);
      return null;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return e.toString();
    }
  }

  // ── Close Session / Free Table ──────────────────────────────────────────
  /// Returns null when the table was freed, otherwise the reason it was
  /// refused. The server rejects closing a table that still has orders on it,
  /// and that message tells the waiter to request the bill instead — so it has
  /// to reach the snackbar rather than being flattened into a bool.
  Future<String?> closeSession(String tableId, String sessionId) async {
    state = const AsyncValue.loading();
    try {
      // A table opened offline that never reached the server: nothing to
      // close. Drop the queued "open" and the local copy — sending a close for
      // a session the server has never heard of would only 404.
      if (await _dropUnsyncedOpenSession(tableId, sessionId)) {
        _invalidateAll(tableId);
        await _ref.read(pendingSyncProvider.notifier).refresh();
        state = const AsyncValue.data(null);
        return null;
      }

      if (_ref.read(connectivityProvider)) {
        try {
          await ApiClient.instance.post(ApiConstants.closeSession(sessionId));
          _invalidateAll(tableId);
          state = const AsyncValue.data(null);
          return null;
        } on NetworkException {
          // Dropped mid-request — queue it below rather than lose the close.
        }
      }

      await _closeSessionOffline(tableId, sessionId);
      state = const AsyncValue.data(null);
      return null;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return e.toString();
    }
  }

  /// Frees the table locally and queues the close for replay. The server still
  /// shows it occupied until this syncs, so the marker is what keeps the table
  /// usable in the meantime.
  Future<void> _closeSessionOffline(String tableId, String sessionId) async {
    await OfflineStore.instance.enqueue(
      entityType: 'session_close',
      operation: 'close',
      endpoint: ApiConstants.closeSession(sessionId),
      method: 'POST',
      payload: const {},
    );
    await OfflineCache.instance.putClosedOfflineSession(sessionId);
    await _ref.read(pendingSyncProvider.notifier).refresh();
    _invalidateAll(tableId);
  }

  /// Removes a still-queued "open" for [sessionId] plus its local copy.
  /// Returns true when this was such a session.
  Future<bool> _dropUnsyncedOpenSession(String tableId, String sessionId) async {
    final ops = await OfflineStore.instance.pendingOps();
    for (final op in ops) {
      if (op.entityType != 'session' || op.id == null) continue;
      try {
        final data = jsonDecode(op.payload) as Map<String, dynamic>;
        if (data['id'] != sessionId) continue;
        await OfflineStore.instance.deleteOp(op.id!);
        await OfflineCache.instance.removeOfflineSession(tableId);
        return true;
      } catch (_) {/* skip a malformed queued op */}
    }
    return false;
  }

  // ── Add Table ───────────────────────────────────────────────────────────
  Future<bool> addTable({
    required String tableNumber,
    required String section,
    required int capacity,
    String? description,
  }) async {
    state = const AsyncValue.loading();
    try {
      if (_branchId == null) {
        throw Exception('Branch ID not found. Cannot add table.');
      }
      await ApiClient.instance.post(
        ApiConstants.tables,
        data: {
          'branchId': _branchId,
          'tableNumber': tableNumber,
          'section': section,
          'capacity': capacity,
          if (description != null && description.isNotEmpty)
            'description': description,
        },
      );
      _ref.invalidate(tablesStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Edit Table ──────────────────────────────────────────────────────────
  Future<bool> editTable({
    required String tableId,
    required String tableNumber,
    required String section,
    required int capacity,
    String? description,
  }) async {
    state = const AsyncValue.loading();
    try {
      final current = await ApiClient.instance.get(ApiConstants.tableById(tableId));
      final currentData = current.data as Map<String, dynamic>;
      final status = currentData['status'] as String? ?? 'available';
      final hasSession = currentData['current_session_id'] != null;
      if (status == 'occupied' || status == 'ready_for_billing' || hasSession) {
        throw Exception('Cannot edit table: it is occupied or has an active session.');
      }

      await ApiClient.instance.patch(
        ApiConstants.tableById(tableId),
        data: {
          'tableNumber': tableNumber,
          'section': section,
          'capacity': capacity,
          if (description != null) 'description': description,
        },
      );
      _ref.invalidate(tablesStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Delete Table ────────────────────────────────────────────────────────
  Future<bool> deleteTable(String tableId) async {
    state = const AsyncValue.loading();
    try {
      final current = await ApiClient.instance.get(ApiConstants.tableById(tableId));
      final currentData = current.data as Map<String, dynamic>;
      final status = currentData['status'] as String? ?? 'available';
      final hasSession = currentData['current_session_id'] != null;
      if (status == 'occupied' || status == 'ready_for_billing' || hasSession) {
        throw Exception('Cannot delete table: it is occupied or has an active session.');
      }

      await ApiClient.instance.delete(ApiConstants.tableById(tableId));
      _ref.invalidate(tablesStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Enable / Disable Table ──────────────────────────────────────────────
  Future<bool> setTableEnabled(String tableId, bool enabled) async {
    state = const AsyncValue.loading();
    try {
      if (!enabled) {
        final current = await ApiClient.instance.get(ApiConstants.tableById(tableId));
        final currentData = current.data as Map<String, dynamic>;
        final status = currentData['status'] as String? ?? 'available';
        final hasSession = currentData['current_session_id'] != null;
        if (status == 'occupied' || status == 'ready_for_billing' || hasSession) {
          throw Exception('Cannot disable table: it is occupied or has an active session.');
        }
      }

      await ApiClient.instance.patch(
        ApiConstants.tableById(tableId),
        data: {
          'isEnabled': enabled,
          'status': enabled ? 'available' : 'closed',
        },
      );
      _ref.invalidate(tablesStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Transfer Session (move to another table) ────────────────────────────
  Future<bool> transferSession({
    required String fromTableId,
    required String toTableId,
    required String sessionId,
  }) async {
    state = const AsyncValue.loading();
    try {
      await ApiClient.instance.post(
        ApiConstants.transferSession(fromTableId),
        data: {'toTableId': toTableId},
      );

      _ref.invalidate(tablesStreamProvider);
      _ref.invalidate(tableSessionProvider(fromTableId));
      _ref.invalidate(tableSessionProvider(toTableId));
      _ref.invalidate(activeSessionsStreamProvider);
      _ref.invalidate(dashboardSessionsProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Hold / Unhold Session ───────────────────────────────────────────────
  Future<bool> holdSession(String sessionId, {String? reason}) =>
      _setHold(sessionId, true, reason: reason);

  Future<bool> unholdSession(String sessionId) => _setHold(sessionId, false);

  /// Puts a session on or off hold, offline-first: the intended state is
  /// recorded locally (so the screens show it at once and it survives an
  /// outage) and the call is queued when the server can't be reached.
  Future<bool> _setHold(String sessionId, bool onHold, {String? reason}) async {
    state = const AsyncValue.loading();
    final endpoint = onHold
        ? ApiConstants.holdSession(sessionId)
        : ApiConstants.unholdSession(sessionId);
    final payload = <String, dynamic>{
      if (onHold && reason != null) 'reason': reason,
    };
    try {
      if (_ref.read(connectivityProvider)) {
        try {
          await ApiClient.instance.post(endpoint, data: payload);
          _ref.invalidate(activeSessionsStreamProvider);
          state = const AsyncValue.data(null);
          return true;
        } on NetworkException {
          // Dropped mid-request — queue it rather than silently do nothing.
        }
      }

      await OfflineStore.instance.enqueue(
        entityType: 'session_hold',
        operation: onHold ? 'hold' : 'unhold',
        endpoint: endpoint,
        method: 'POST',
        payload: payload,
      );
      // Remember the INTENDED state, so the session shows as held (or not)
      // even though the server still reports the old value.
      await OfflineCache.instance.putHeldOfflineSession(sessionId, onHold);
      await _ref.read(pendingSyncProvider.notifier).refresh();
      _ref.invalidate(activeSessionsStreamProvider);
      _ref.invalidate(tablesStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Merge Sessions (merge fromTable session into toTable session) ─────────
  Future<bool> mergeSessions({
    required String fromTableId,
    required String toTableId,
    required String fromSessionId,
    required String toSessionId,
  }) async {
    state = const AsyncValue.loading();
    try {
      await ApiClient.instance.post(
        ApiConstants.mergeSession(fromSessionId),
        data: {'intoSessionId': toSessionId},
      );

      _ref.invalidate(tablesStreamProvider);
      _ref.invalidate(tableSessionProvider(fromTableId));
      _ref.invalidate(tableSessionProvider(toTableId));
      _ref.invalidate(activeSessionsStreamProvider);
      _ref.invalidate(dashboardSessionsProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Split Session (move selected KOTs to a new session on another table) ─
  Future<bool> splitSession({
    required String fromTableId,
    required String toTableId,
    required String fromSessionId,
    required List<String> kotIdsToMove,
    int guestCount = 1,
  }) async {
    state = const AsyncValue.loading();
    try {
      await ApiClient.instance.post(
        ApiConstants.splitSession(fromSessionId),
        data: {
          'toTableId': toTableId,
          'kotIds': kotIdsToMove,
          'guestCount': guestCount,
        },
      );

      _ref.invalidate(tablesStreamProvider);
      _ref.invalidate(tableSessionProvider(fromTableId));
      _ref.invalidate(tableSessionProvider(toTableId));
      _ref.invalidate(activeSessionsStreamProvider);
      _ref.invalidate(dashboardSessionsProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Edit KOT Item (update quantity or cancel item) ────────────────────────
  Future<bool> updateKotItem(String kotItemId, int newQuantity, {String? sessionId}) async {
    try {
      // Write the new quantity into the local copy first, so the bill is right
      // straight away and stays right if the connection goes. Without this an
      // offline edit was simply lost — the API call threw and nothing else
      // recorded it.
      await _applyLocalQuantity(sessionId, kotItemId, newQuantity);

      if (_ref.read(connectivityProvider)) {
        try {
          await ApiClient.instance.patch(
            ApiConstants.updateKotItemQuantity(kotItemId),
            data: {'quantity': newQuantity},
          );
          _invalidateAfterItemEdit(sessionId);
          return true;
        } on NetworkException {
          // Dropped mid-request — queue it below.
        }
      }

      await OfflineStore.instance.enqueue(
        entityType: 'kot_item_quantity',
        operation: 'update',
        endpoint: ApiConstants.updateKotItemQuantity(kotItemId),
        method: 'PATCH',
        payload: {'quantity': newQuantity},
      );
      await _ref.read(pendingSyncProvider.notifier).refresh();
      _invalidateAfterItemEdit(sessionId);
      return true;
    } catch (e) {
      return false;
    }
  }

  void _invalidateAfterItemEdit(String? sessionId) {
    // sessionBillingProvider watches sessionKotsProvider, so the till's bill
    // recomputes off this one invalidation.
    if (sessionId != null) _ref.invalidate(sessionKotsProvider(sessionId));
    _ref.invalidate(activeSessionsStreamProvider);
    _ref.invalidate(dashboardSessionsProvider);
  }

  /// Updates the cached copy of one order line's quantity.
  Future<void> _applyLocalQuantity(
      String? sessionId, String kotItemId, int quantity) async {
    if (sessionId == null) return;
    final kots = await OfflineStore.instance.kotsForSession(sessionId);
    for (final k in kots) {
      final items = await OfflineStore.instance.itemsForKot(k.id);
      final target = items.indexWhere((i) => i.id == kotItemId);
      if (target < 0) continue;
      items[target].quantity = quantity;
      // delete + save: saveOfflineKot upserts the items it is handed, which is
      // enough here, but going through delete keeps one code path for
      // rewriting a cached order.
      await OfflineStore.instance.deleteOfflineKot(k.id);
      await OfflineStore.instance.saveOfflineKot(k, items);
      return;
    }
  }

  // ── Update table status ─────────────────────────────────────────────────
  Future<void> updateTableStatus(String tableId, String status) async {
    await ApiClient.instance.patch(
      ApiConstants.tableById(tableId),
      data: {'status': status},
    );
    _invalidateAll(tableId);
  }
}

final tableNotifierProvider =
    StateNotifierProvider<TableNotifier, AsyncValue<void>>(
  (ref) => TableNotifier(ref),
);

// ─── Reservation Notifier ──────────────────────────────────────────────────
class ReservationNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  ReservationNotifier(this._ref) : super(const AsyncValue.data(null));

  String? get _branchId => _ref.read(authNotifierProvider).value?.branchId;

  Future<bool> addReservation({
    required String customerName,
    String? customerPhone,
    required int guestCount,
    required DateTime reservationTime,
    String? tableId,
    String? notes,
  }) async {
    state = const AsyncValue.loading();
    try {
      await ApiClient.instance.post(
        ApiConstants.reservations,
        data: {
          'branchId': _branchId,
          'customerName': customerName,
          'customerPhone': customerPhone ?? '',
          'guestCount': guestCount,
          'reservationTime': reservationTime.toIso8601String(),
          if (tableId != null) 'tableId': tableId,
          if (notes != null) 'notes': notes,
        },
      );
      _ref.invalidate(reservationsStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  Future<bool> updateReservation({
    required String id,
    required String customerName,
    String? customerPhone,
    required int guestCount,
    required DateTime reservationTime,
    String? tableId,
    String? notes,
    String? status,
  }) async {
    state = const AsyncValue.loading();
    try {
      await ApiClient.instance.patch(
        ApiConstants.reservationById(id),
        data: {
          'customerName': customerName,
          'customerPhone': customerPhone,
          'guestCount': guestCount,
          'reservationTime': reservationTime.toIso8601String(),
          if (tableId != null) 'tableId': tableId,
          if (notes != null) 'notes': notes,
          if (status != null) 'status': status,
        },
      );
      _ref.invalidate(reservationsStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  Future<bool> cancelReservation(String id) async {
    state = const AsyncValue.loading();
    try {
      await ApiClient.instance.patch(
        ApiConstants.updateReservationStatus(id),
        data: {'status': 'cancelled'},
      );
      _ref.invalidate(reservationsStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  Future<bool> markNoShow(String id) async {
    state = const AsyncValue.loading();
    try {
      await ApiClient.instance.patch(
        ApiConstants.updateReservationStatus(id),
        data: {'status': 'no_show'},
      );
      _ref.invalidate(reservationsStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }
}

final reservationNotifierProvider =
    StateNotifierProvider<ReservationNotifier, AsyncValue<void>>(
  (ref) => ReservationNotifier(ref),
);
