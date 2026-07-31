// ============================================================
// KATIYA STATION RMS — LAN SYNC LIFECYCLE
// Keeps LanSync running for the whole authenticated session and turns every
// mirrored envelope into provider invalidations, so a waiter's offline order
// lands on the cashier's till without anyone pulling to refresh.
//
// Watched once from AppShell, exactly like realtimeSyncProvider — this is the
// LAN twin of that Socket.IO bridge, for when there is no internet to carry it.
// ============================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/cashier/presentation/screens/cashier_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/kitchen/presentation/providers/kitchen_provider.dart';
import '../../features/orders/presentation/providers/order_provider.dart';
import '../../features/tables/presentation/providers/tables_provider.dart';
import 'lan_config.dart';
import 'lan_sync.dart';

/// Live LAN status for the Settings card.
final lanStatusProvider = StreamProvider<LanStatus>((ref) async* {
  yield LanSync.instance.status;
  yield* LanSync.instance.statusStream;
});

/// Watched once from [AppShell] so LAN sync stays up for the whole session.
/// Holds no data of its own — it starts the transport and invalidates the
/// providers a mirrored envelope affects.
final lanSyncProvider = Provider<void>((ref) {
  final config = ref.watch(lanConfigProvider);
  final branchId = ref.watch(authNotifierProvider).value?.branchId ?? '';

  // A mirrored order arrives already written to this device's offline store, so
  // these just need re-reading. Debounced because a device reconnecting gets
  // its whole catch-up backlog in one burst, and rebuilding the cashier grid
  // once per ticket would be visible.
  Timer? debounce;
  void scheduleRefresh() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), () {
      // Tables + sessions: a table opened on another device shows occupied,
      // and one billed there shows free.
      ref.invalidate(tablesStreamProvider);
      ref.invalidate(activeSessionsStreamProvider);
      ref.invalidate(tableSessionProvider); // whole family
      // Orders: the till's bill and the kitchen queue.
      ref.invalidate(sessionKotsProvider); // whole family
      ref.invalidate(sessionBillingProvider); // whole family
      ref.invalidate(kitchenKotsProvider);
      // Dashboard tiles.
      ref.invalidate(dashboardSessionsProvider);
      ref.invalidate(dashboardKotsProvider);
    });
  }

  final sub = LanSync.instance.applied.listen((_) => scheduleRefresh());

  unawaited(LanSync.instance.start(config: config, branchId: branchId));

  ref.onDispose(() {
    debounce?.cancel();
    sub.cancel();
  });
});
