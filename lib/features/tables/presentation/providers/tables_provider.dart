import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/table_entities.dart';
import '../../../orders/presentation/providers/order_provider.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';

// ─── All tables (by branch) ────────────────────────────────────────────────
final tablesStreamProvider = FutureProvider<List<RestaurantTable>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];

  final response = await ApiClient.instance.get(
    ApiConstants.tables,
    queryParameters: {'branchId': profile!.branchId!},
  );
  final rows = response.data as List<dynamic>;
  return rows
      .map((r) => RestaurantTable.fromJson(r as Map<String, dynamic>))
      .toList()
    ..sort((a, b) => a.tableNumber.compareTo(b.tableNumber));
});

// ─── Active (open) sessions for the branch ─────────────────────────────────
final activeSessionsStreamProvider = FutureProvider<List<TableSession>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];

  final response = await ApiClient.instance.get(
    ApiConstants.sessions,
    queryParameters: {'branchId': profile!.branchId!, 'status': 'open'},
  );
  final rows = response.data as List<dynamic>;
  return rows
      .map((r) => TableSession.fromJson(r as Map<String, dynamic>))
      .toList();
});

// ─── Session for a specific table ─────────────────────────────────────────
final tableSessionProvider =
    FutureProvider.family<TableSession?, String>((ref, tableId) async {
  final response =
      await ApiClient.instance.get(ApiConstants.currentSession(tableId));
  // The backend sends a body-less response (no Content-Type) when there's
  // no current session, which Dio decodes as an empty string rather than
  // null — so check the type, not just `== null`.
  final data = response.data;
  if (data is! Map<String, dynamic>) return null;
  return TableSession.fromJson(data);
});

// ─── Reservations ───────────────────────────────────────────────────────────
final reservationsStreamProvider = FutureProvider<List<TableReservation>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];

  final response = await ApiClient.instance.get(
    ApiConstants.reservations,
    queryParameters: {'branchId': profile!.branchId!},
  );
  final rows = response.data as List<dynamic>;
  return rows
      .map((r) => TableReservation.fromJson(r as Map<String, dynamic>))
      .toList()
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
    try {
      final response = await ApiClient.instance.post(
        ApiConstants.openSession(tableId),
        data: {'guestCount': guestCount},
      );
      _invalidateAll(tableId);
      state = const AsyncValue.data(null);
      return TableSession.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return null;
    }
  }

  // ── Request Bill ────────────────────────────────────────────────────────
  Future<bool> requestBill(String tableId, String sessionId) async {
    state = const AsyncValue.loading();
    try {
      await ApiClient.instance.post(ApiConstants.requestBill(tableId));
      _invalidateAll(tableId);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  // ── Close Session / Free Table ──────────────────────────────────────────
  Future<bool> closeSession(String tableId, String sessionId) async {
    state = const AsyncValue.loading();
    try {
      await ApiClient.instance.post(ApiConstants.closeSession(sessionId));
      _invalidateAll(tableId);
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
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
