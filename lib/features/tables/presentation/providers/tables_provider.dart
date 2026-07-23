import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/errors/app_exceptions.dart';
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
final tablesStreamProvider = FutureProvider<List<RestaurantTable>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final branchId = profile!.branchId!;
  final key = CacheKeys.tables(branchId);

  List<dynamic> rows;
  if (!ref.read(connectivityProvider)) {
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
  // yet, so without this a just-opened table would look free again.
  final offlineSessions = await OfflineCache.instance.allOfflineSessionsByTable();
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

  tables.sort((a, b) => a.tableNumber.compareTo(b.tableNumber));
  return tables;
});

// ─── Active (open) sessions for the branch ─────────────────────────────────
final activeSessionsStreamProvider = FutureProvider<List<TableSession>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final branchId = profile!.branchId!;
  final key = CacheKeys.openSessions(branchId);

  var sessions = <TableSession>[];
  List<dynamic>? cachedRows;
  if (!ref.read(connectivityProvider)) {
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
  sessions = cachedRows
      .map((r) => TableSession.fromJson(r as Map<String, dynamic>))
      .toList();

  // Include sessions opened offline that the server hasn't seen yet.
  final offlineSessions = await OfflineCache.instance.allOfflineSessionsByTable();
  if (offlineSessions.isNotEmpty) {
    final ids = sessions.map((s) => s.id).toSet();
    for (final json in offlineSessions.values) {
      final s = TableSession.fromJson(json);
      if (!ids.contains(s.id)) sessions = [...sessions, s];
    }
  }
  return sessions;
});

// ─── Session for a specific table ─────────────────────────────────────────
final tableSessionProvider =
    FutureProvider.family<TableSession?, String>((ref, tableId) async {
  // Offline: only a session opened on this device is known — return it at once
  // rather than stalling on a network call that will time out.
  if (!ref.read(connectivityProvider)) {
    final offline = await OfflineCache.instance.getOfflineSession(tableId);
    return offline != null ? TableSession.fromJson(offline) : null;
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
        return TableSession.fromJson(response.data as Map<String, dynamic>);
      } on NetworkException {
        // Dropped mid-request — open it offline instead.
      } catch (e) {
        state = AsyncValue.error(e.toString(), StackTrace.current);
        return null;
      }
    }

    return _openSessionOffline(tableId, sessionId, guestCount);
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
      await ApiClient.instance.post(ApiConstants.closeSession(sessionId));
      _invalidateAll(tableId);
      state = const AsyncValue.data(null);
      return null;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return e.toString();
    }
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
  Future<bool> holdSession(String sessionId, {String? reason}) async {
    state = const AsyncValue.loading();
    try {
      await ApiClient.instance.post(
        ApiConstants.holdSession(sessionId),
        data: {if (reason != null) 'reason': reason},
      );
      _ref.invalidate(activeSessionsStreamProvider);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  Future<bool> unholdSession(String sessionId) async {
    state = const AsyncValue.loading();
    try {
      await ApiClient.instance.post(ApiConstants.unholdSession(sessionId));
      _ref.invalidate(activeSessionsStreamProvider);
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
      await ApiClient.instance.patch(
        ApiConstants.updateKotItemQuantity(kotItemId),
        data: {'quantity': newQuantity},
      );

      if (sessionId != null) {
        _ref.invalidate(sessionKotsProvider(sessionId));
      }
      _ref.invalidate(activeSessionsStreamProvider);
      _ref.invalidate(dashboardSessionsProvider);
      return true;
    } catch (e) {
      return false;
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
