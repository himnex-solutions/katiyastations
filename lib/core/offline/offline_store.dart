// ============================================================
// KATIYA STATION RMS — OFFLINE WRITE STORE (Isar)
// The write side of offline mode:
//  • SyncQueueItem  — the outbox of mutations waiting to reach the server
//  • OfflineKot/Item — orders taken offline, kept so the waiter can see them
// The read cache (menu/tables) lives separately in OfflineCache.
// ============================================================

import 'dart:convert';
import 'package:isar/isar.dart';

import 'isar_schemas.dart';
import 'isar_service.dart';
import 'offline_ids.dart';

class OfflineStore {
  OfflineStore._();
  static final OfflineStore instance = OfflineStore._();

  Isar get _isar => IsarService.instance.isar;
  bool get _ready => IsarService.instance.isInitialized;

  // ── Outbox ───────────────────────────────────────────────────
  /// Queue a mutation to be replayed to the server once back online.
  Future<void> enqueue({
    required String entityType, // 'session' | 'kot'
    required String operation, // 'create'
    required String endpoint,
    required String method, // 'POST' | 'PATCH' | 'DELETE'
    required Map<String, dynamic> payload,
  }) async {
    if (!_ready) return;
    final item = SyncQueueItem()
      ..operationId = newOfflineId()
      ..entityType = entityType
      ..operation = operation
      ..endpoint = endpoint
      ..method = method
      ..payload = jsonEncode(payload)
      ..createdAt = DateTime.now()
      ..retryCount = 0
      ..isFailed = false;
    await _isar.writeTxn(() => _isar.syncQueueItems.put(item));
  }

  /// Pending (not-yet-synced, not-permanently-failed) operations, oldest first.
  Future<List<SyncQueueItem>> pendingOps() async {
    if (!_ready) return [];
    return _isar.syncQueueItems
        .filter()
        .isFailedEqualTo(false)
        .sortByCreatedAt()
        .findAll();
  }

  Future<int> pendingCount() async {
    if (!_ready) return 0;
    return _isar.syncQueueItems.filter().isFailedEqualTo(false).count();
  }

  Future<void> deleteOp(int id) async {
    if (!_ready) return;
    await _isar.writeTxn(() => _isar.syncQueueItems.delete(id));
  }

  Future<void> saveOp(SyncQueueItem op) async {
    if (!_ready) return;
    await _isar.writeTxn(() => _isar.syncQueueItems.put(op));
  }

  // ── Offline KOTs ─────────────────────────────────────────────
  Future<void> saveOfflineKot(OfflineKot kot, List<OfflineKotItem> items) async {
    if (!_ready) return;
    await _isar.writeTxn(() async {
      await _isar.offlineKots.put(kot);
      await _isar.offlineKotItems.putAll(items);
    });
  }

  Future<List<OfflineKot>> kotsForSession(String sessionId) async {
    if (!_ready) return [];
    return _isar.offlineKots
        .filter()
        .sessionIdEqualTo(sessionId)
        .sortByCreatedAt()
        .findAll();
  }

  Future<List<OfflineKotItem>> itemsForKot(String kotId) async {
    if (!_ready) return [];
    return _isar.offlineKotItems
        .filter()
        .kotIdEqualTo(kotId)
        .sortByCreatedAt()
        .findAll();
  }

  /// Drop an offline KOT once it has synced — the server copy (delivered live
  /// over the socket) is now the source of truth.
  Future<void> deleteOfflineKot(String kotId) async {
    if (!_ready) return;
    final items = await _isar.offlineKotItems.filter().kotIdEqualTo(kotId).findAll();
    await _isar.writeTxn(() async {
      await _isar.offlineKots.delete(fastHash(kotId));
      await _isar.offlineKotItems.deleteAll(items.map((e) => e.isarId).toList());
    });
  }
}
