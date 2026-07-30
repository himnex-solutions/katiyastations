// ============================================================
// KATIYA STATION RMS — OFFLINE SYNC ENGINE
// Drains the SyncQueueItem outbox to the server, oldest first, when a
// connection is available. Each queued create carries a client UUID, so the
// server treats a replay as idempotent — a flaky connection can never create
// a duplicate order.
// ============================================================

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/app_exceptions.dart';
import '../network/api_client.dart';
import 'offline_cache.dart';
import 'offline_store.dart'; // provides OfflineStore + SyncQueueItem

// Providers whose data is refreshed after a drain — and on every reconnect —
// so synced orders/tables/bills appear immediately without a logout/login (the
// socket also pushes them, this covers the gap while catching up).
import '../../features/tables/presentation/providers/tables_provider.dart';
import '../../features/orders/presentation/providers/order_provider.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/kitchen/presentation/providers/kitchen_provider.dart';
import '../../features/payment_history/presentation/screens/payment_history_screen.dart';
import '../../features/cashier/presentation/screens/online_orders_screen.dart';

enum _Replay { ok, transient, permanentFail }

final syncEngineProvider = Provider<SyncEngine>((ref) => SyncEngine(ref));

/// Live count of not-yet-synced operations, for the offline banner/badge.
final pendingSyncProvider =
    StateNotifierProvider<PendingSyncController, int>((ref) => PendingSyncController());

class PendingSyncController extends StateNotifier<int> {
  PendingSyncController() : super(0) {
    refresh();
  }

  Future<void> refresh() async {
    state = await OfflineStore.instance.pendingCount();
  }
}

class SyncEngine {
  final Ref _ref;
  bool _running = false;

  SyncEngine(this._ref);

  /// Replay every pending operation, oldest first. Safe to call repeatedly and
  /// concurrently — a second call while one is running is a no-op.
  Future<void> syncNow() async {
    if (_running || !OfflineStore.instance.isReady) return;
    _running = true;
    try {
      final ops = await OfflineStore.instance.pendingOps();
      for (final op in ops) {
        final result = await _replay(op);
        if (result == _Replay.ok) {
          await _cleanupAfterSync(op);
          await OfflineStore.instance.deleteOp(op.id!);
        } else if (result == _Replay.permanentFail) {
          op.isFailed = true;
          await OfflineStore.instance.saveOp(op);
        } else {
          // Transient (offline again / server down / token refreshing) — stop
          // here and retry the rest on the next connectivity event.
          await OfflineStore.instance.saveOp(op);
          break;
        }
      }
    } finally {
      _running = false;
    }
    // Always refresh — not only when something was uploaded. Coming back online
    // after merely *viewing* screens offline still needs the latest server data
    // pulled in (other devices may have changed tables/bills/orders meanwhile),
    // which is the "stale until I log out and back in" case.
    _refreshProviders();
    await _ref.read(pendingSyncProvider.notifier).refresh();
  }

  Future<_Replay> _replay(SyncQueueItem op) async {
    try {
      final data = jsonDecode(op.payload) as Map<String, dynamic>;
      switch (op.method) {
        case 'POST':
          await ApiClient.instance.post(op.endpoint, data: data);
          break;
        case 'PATCH':
          await ApiClient.instance.patch(op.endpoint, data: data);
          break;
        case 'DELETE':
          await ApiClient.instance.delete(op.endpoint, data: data);
          break;
        default:
          op.errorMessage = 'Unsupported method ${op.method}';
          return _Replay.permanentFail;
      }
      return _Replay.ok;
    } on NetworkException {
      return _Replay.transient; // still offline — try again later
    } on ServerException {
      return _Replay.transient; // 5xx — server hiccup, retry
    } on AuthException {
      return _Replay.transient; // token refresh in flight; retry after
    } on ApiException catch (e) {
      if (e.isServerError) return _Replay.transient;
      // 404 / 409 / 422 etc. — replaying won't fix it (e.g. table already
      // taken). Park it as failed so it doesn't block the rest of the queue.
      op.errorMessage = e.message;
      op.retryCount += 1;
      return _Replay.permanentFail;
    } on AppException catch (e) {
      // Validation / permission — permanent.
      op.errorMessage = e.message;
      op.retryCount += 1;
      if (e is UnknownException && op.retryCount < 5) return _Replay.transient;
      return _Replay.permanentFail;
    } catch (e) {
      op.errorMessage = e.toString();
      op.retryCount += 1;
      return op.retryCount < 5 ? _Replay.transient : _Replay.permanentFail;
    }
  }

  /// After a create syncs, drop the local placeholder — the server copy is now
  /// authoritative and arrives live over the socket.
  Future<void> _cleanupAfterSync(SyncQueueItem op) async {
    final data = jsonDecode(op.payload) as Map<String, dynamic>;
    if (op.entityType == 'kot') {
      final id = data['id'] as String?;
      if (id != null) await OfflineStore.instance.deleteOfflineKot(id);
    } else if (op.entityType == 'session') {
      final tableId = _tableIdFromOpenEndpoint(op.endpoint);
      if (tableId != null) await OfflineCache.instance.removeOfflineSession(tableId);
    } else if (op.entityType == 'bill') {
      // The offline bill just synced — the server has billed the session and
      // freed the table (and assigned the official invoice number), so drop the
      // local "billed offline" marker; server truth now stands.
      final sessionId = _sessionIdFromBillEndpoint(op.endpoint);
      if (sessionId != null) {
        await OfflineCache.instance.removeBilledOfflineSession(sessionId);
      }
    }
  }

  String? _tableIdFromOpenEndpoint(String endpoint) {
    // Endpoint shape: '/tables/<tableId>/open'
    final match = RegExp(r'/tables/([^/]+)/open').firstMatch(endpoint);
    return match?.group(1);
  }

  String? _sessionIdFromBillEndpoint(String endpoint) {
    // Endpoint shape: '/billing/sessions/<sessionId>/generate'
    final match = RegExp(r'/sessions/([^/]+)/generate').firstMatch(endpoint);
    return match?.group(1);
  }

  void _refreshProviders() {
    // Waiter / tables + orders
    _ref.invalidate(tablesStreamProvider);
    _ref.invalidate(activeSessionsStreamProvider);
    _ref.invalidate(tableSessionProvider); // whole family
    _ref.invalidate(sessionKotsProvider); // whole family
    // Kitchen
    _ref.invalidate(kitchenKotsProvider);
    // Dashboard + cashier (sales, credit, bills, online orders)
    _ref.invalidate(dashboardSessionsProvider);
    _ref.invalidate(dashboardKotsProvider);
    _ref.invalidate(dashboardBillsProvider);
    _ref.invalidate(dashboardCreditProvider);
    _ref.invalidate(billsStreamProvider); // payment history (whole family)
    _ref.invalidate(onlineOrdersProvider);
    // Reference data that another device may have changed while we were offline
    // — most importantly menu prices, so an offline-cached price can't linger.
    _ref.invalidate(menuCategoriesProvider); // whole family
    _ref.invalidate(menuItemsProvider); // whole family
    _ref.invalidate(allMenuItemsProvider); // whole family
    _ref.invalidate(reservationsStreamProvider);
  }
}
