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
  Timer? _poll;

  // Reachability re-verification cadence. An interface staying "connected"
  // while its router silently loses (or regains) internet fires no connectivity
  // event, so a poll is the only thing that notices that transition. Poll FAST
  // while offline so the internet returning is caught within seconds and the
  // outbox drains almost immediately; poll slowly while online, where real
  // traffic already flips us offline the instant a call fails.
  static const Duration _pollWhenOffline = Duration(seconds: 4);
  static const Duration _pollWhenOnline = Duration(seconds: 20);

  // Optimistically assume online until the first real check resolves, so the
  // app never flashes an offline banner on a healthy launch.
  ConnectivityController(this._ref) : super(true) {
    // The HTTP layer flips us the instant real traffic succeeds or a connection
    // fails — no waiting for the poll when the app is actively making calls.
    NetworkInfo.instance.onObserved = _apply;
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

    _sub = NetworkInfo.instance.connectivityStream.listen(_apply);
    _schedulePoll();
  }

  /// One-shot self-rescheduling poll, so the interval can follow the current
  /// online/offline state (fast when offline, slow when online).
  void _schedulePoll() {
    _poll?.cancel();
    _poll = Timer(state ? _pollWhenOnline : _pollWhenOffline, () async {
      try {
        _apply(await NetworkInfo.instance.isConnected);
      } catch (_) {
        // Leave the last known state on a probe failure.
      }
      if (mounted) _schedulePoll();
    });
  }

  /// Applies a fresh online/offline reading, and flushes the outbox on every
  /// offline→online transition. No-ops when the state is unchanged so repeated
  /// readings from the poll, the stream and the HTTP layer don't thrash.
  void _apply(bool online) {
    final wasOnline = state;
    if (online == wasOnline) return;
    state = online;
    if (!wasOnline && online) {
      // Back online → drain the outbox to the server right away so every other
      // device sees the offline orders within moments.
      unawaited(_ref.read(syncEngineProvider).syncNow());
    }
    // Adopt the new cadence at once (e.g. switch to fast polling on going
    // offline) instead of waiting out the interval already scheduled.
    _schedulePoll();
  }

  @override
  void dispose() {
    NetworkInfo.instance.onObserved = null;
    _poll?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
