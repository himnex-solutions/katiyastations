// ============================================================
// KATIYA STATION RMS — OFFLINE WRITE STORE (platform-selected)
// The write side of offline mode:
//  • SyncQueueItem  — the outbox of mutations waiting to reach the server
//  • OfflineKot/Item — orders taken offline, kept so the waiter can see them
// The read cache (menu/tables) lives separately in OfflineCache.
//
// This file defines the platform-neutral CONTRACT. The concrete backend is
// chosen at compile time by the conditional import below:
//   • Native (Android / Windows / iOS / desktop) → Isar   (offline_store_io.dart)
//   • Web (dart2js)                               → SharedPreferences (offline_store_web.dart)
// Isar's generated schemas contain 64-bit integer literals that dart2js cannot
// compile, so they must never be reachable from the web entrypoint — this split
// guarantees the web build never imports Isar.
// ============================================================

import 'offline_models.dart';

// The web impl is the default; native overrides it when dart:io exists.
// Keyed on `dart.library.io` (present only on native VMs) so it resolves
// correctly for both dart2js and dart2wasm web targets.
import 'offline_store_web.dart'
    if (dart.library.io) 'offline_store_io.dart' as impl;

export 'offline_models.dart';

abstract class OfflineStore {
  /// The platform-appropriate singleton (Isar on native, prefs on web).
  static final OfflineStore instance = impl.createOfflineStore();

  /// True once the backing store is ready for reads/writes.
  bool get isReady;

  /// Open/initialise the backing store. Best-effort: callers treat a failure
  /// as "offline mode unavailable", never fatal.
  Future<void> init();

  // ── Outbox ───────────────────────────────────────────────────
  /// Queue a mutation to be replayed to the server once back online.
  Future<void> enqueue({
    required String entityType, // 'session' | 'kot'
    required String operation, // 'create'
    required String endpoint,
    required String method, // 'POST' | 'PATCH' | 'DELETE'
    required Map<String, dynamic> payload,
  });

  /// Pending (not-yet-synced, not-permanently-failed) operations, oldest first.
  Future<List<SyncQueueItem>> pendingOps();

  Future<int> pendingCount();

  Future<void> deleteOp(int id);

  Future<void> saveOp(SyncQueueItem op);

  // ── Offline KOTs ─────────────────────────────────────────────
  Future<void> saveOfflineKot(OfflineKot kot, List<OfflineKotItem> items);

  Future<List<OfflineKot>> kotsForSession(String sessionId);

  Future<List<OfflineKotItem>> itemsForKot(String kotId);

  /// Drop an offline KOT once it has synced — the server copy (delivered live
  /// over the socket) is now the source of truth.
  Future<void> deleteOfflineKot(String kotId);

  /// Wipe all offline data (called on logout).
  Future<void> clearAll();
}
