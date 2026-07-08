// ============================================================
// KATIYA STATION RMS — REALTIME SYNC
// Single chokepoint that listens to Socket.IO events pushed by the
// backend (RealtimeService) and invalidates the Riverpod providers that
// read the affected data. Every screen watching one of those providers
// rebuilds with fresh data automatically — no manual pull-to-refresh or
// page reload required.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'socket_client.dart';
import '../app_messenger.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/tables/presentation/providers/tables_provider.dart';
import '../../features/orders/presentation/providers/order_provider.dart';
import '../../features/kitchen/presentation/providers/kitchen_provider.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/payment_history/presentation/screens/payment_history_screen.dart';
import '../../features/credit/presentation/screens/credit_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/inventory/presentation/screens/inventory_screen.dart';
import '../../features/cashier/presentation/screens/cashier_screen.dart';
import '../../features/users/presentation/screens/users_screen.dart';
import '../../features/purchase/presentation/screens/purchase_screen.dart';

/// Watched once from [AppShell] so it stays alive for the whole
/// authenticated session. Do not watch this from individual screens —
/// it holds no data of its own, it only triggers invalidations as a
/// side effect of live socket events.
final realtimeSyncProvider = Provider<void>((ref) {
  final subscriptions = <StreamSubscription<dynamic>>[];
  final socket = SocketClient.instance;

  void invalidateKots() {
    ref.invalidate(kitchenKotsProvider);
    ref.invalidate(sessionKotsProvider);
    ref.invalidate(sessionBillingProvider);
    ref.invalidate(dashboardKotsProvider);
    ref.invalidate(activeSessionsStreamProvider);
    ref.invalidate(dashboardSessionsProvider);
  }

  void invalidateTablesAndSessions() {
    ref.invalidate(tablesStreamProvider);
    ref.invalidate(activeSessionsStreamProvider);
    ref.invalidate(tableSessionProvider);
    ref.invalidate(dashboardSessionsProvider);
    ref.invalidate(sessionBillingProvider);
  }

  void invalidateBilling() {
    ref.invalidate(dashboardBillsProvider);
    ref.invalidate(billsStreamProvider);
    ref.invalidate(dashboardCreditProvider);
    ref.invalidate(creditProvider);
    invalidateTablesAndSessions();
  }

  subscriptions.addAll([
    socket.onKotNew().listen((_) => invalidateKots()),
    socket.onKotUpdated().listen((_) => invalidateKots()),
    socket.onKotStatusChanged().listen((_) => invalidateKots()),
    socket.onOrderItemCancelled().listen((_) => invalidateKots()),
    socket.onTableStatusChanged().listen((_) => invalidateTablesAndSessions()),
    socket.onSessionOpened().listen((_) => invalidateTablesAndSessions()),
    socket.onSessionClosed().listen((_) => invalidateTablesAndSessions()),
    socket.onTableTransferred().listen((_) => invalidateTablesAndSessions()),
    socket.onWaiterAssigned().listen((_) => invalidateTablesAndSessions()),
    socket.onBillGenerated().listen((_) => invalidateBilling()),
    socket.on(SocketEvents.billPaid).listen((_) => invalidateBilling()),
    socket.onNotification().listen((_) => ref.invalidate(notificationsProvider)),
    socket.onLowStock().listen((data) {
      ref.invalidate(inventoryProvider);
      ref.invalidate(notificationsProvider);
      _showLowStockToast(ref, data);
    }),
    // Branch user account added / edited / blocked / deleted elsewhere.
    socket.onUserChanged().listen((_) => ref.invalidate(branchUsersProvider)),
    // Purchase recorded — refresh the purchase list and the daily report.
    socket.onPurchaseCreated().listen((_) => ref.invalidate(purchasesProvider)),
  ]);

  ref.onDispose(() {
    for (final sub in subscriptions) {
      sub.cancel();
    }
  });
});

/// Pops a floating alert for the roles that act on stock (manager, cashier,
/// inventory, accountant) whenever an item drops to/below its reorder level —
/// shown app-wide via the global messenger, regardless of the current screen.
void _showLowStockToast(Ref ref, Map<String, dynamic> data) {
  const audience = {'branch_manager', 'cashier', 'inventory', 'accountant'};
  final role = ref.read(authNotifierProvider).value?.role;
  if (role == null || !audience.contains(role)) return;

  final name = (data['name'] ?? data['item_name'] ?? 'An item').toString();
  final rawQty = data['currentStock'] ?? data['current_stock'];
  final qty = rawQty is num ? rawQty : num.tryParse('$rawQty');
  final isOut = qty != null && qty <= 0;
  final message = isOut
      ? 'Out of stock: $name'
      : 'Low stock: $name${qty != null ? ' (${qty % 1 == 0 ? qty.toInt() : qty} left)' : ''}';

  scaffoldMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: isOut ? const Color(0xFFD32F2F) : const Color(0xFFF57C00),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      content: Row(children: [
        Icon(isOut ? Icons.error_rounded : Icons.warning_amber_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
      ]),
    ));
}
