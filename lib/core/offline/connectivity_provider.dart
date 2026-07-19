// ============================================================
// KATIYA STATION RMS — CONNECTIVITY PROVIDER
// Exposes online/offline as a Riverpod state and, on every offline→online
// transition (and once at startup), kicks the sync engine to drain the outbox.
// ============================================================

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/network_info.dart';
import 'sync_engine.dart';

/// `true` = online. Watch this to react to connectivity anywhere in the app.
final connectivityProvider =
    StateNotifierProvider<ConnectivityController, bool>((ref) => ConnectivityController(ref));

class ConnectivityController extends StateNotifier<bool> {
  final Ref _ref;
  StreamSubscription<bool>? _sub;

  // Optimistically assume online until the first real check resolves, so the
  // app never flashes an offline banner on a healthy launch.
  ConnectivityController(this._ref) : super(true) {
    _init();
  }

  Future<void> _init() async {
    try {
      state = await NetworkInfo.instance.isConnected;
    } catch (_) {
      // If the platform check fails, stay optimistic (online).
    }

    // Drain anything left over from a previous offline session at startup.
    if (state) {
      unawaited(_ref.read(syncEngineProvider).syncNow());
    }

    _sub = NetworkInfo.instance.connectivityStream.listen((online) {
      final wasOnline = state;
      if (online == wasOnline) return;
      state = online;
      // Reconnected → flush the queue.
      if (!wasOnline && online) {
        unawaited(_ref.read(syncEngineProvider).syncNow());
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
