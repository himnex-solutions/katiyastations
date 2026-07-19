// ============================================================
// KATIYA STATION RMS — OFFLINE STORE (native / Isar backend)
// Selected on Android / Windows / iOS / desktop, where the native Isar core
// is available. This is the ONLY library that imports the Isar schemas, so the
// 64-bit schema-hash literals in isar_schemas.g.dart stay off the web build.
// ============================================================

import 'dart:convert';

import 'package:isar/isar.dart';

// Isar's generated collections share names with the plain models
// (OfflineKot, SyncQueueItem, …), so import them behind a prefix and map
// between the two at this boundary.
import 'isar_schemas.dart' as db;
import 'isar_service.dart';
import 'offline_ids.dart';
import 'offline_store.dart'; // re-exports offline_models.dart

/// Factory referenced by the conditional import in offline_store.dart.
OfflineStore createOfflineStore() => IsarOfflineStore();

class IsarOfflineStore implements OfflineStore {
  Isar get _isar => IsarService.instance.isar;

  @override
  bool get isReady => IsarService.instance.isInitialized;

  @override
  Future<void> init() => IsarService.instance.initialize();

  // ── Outbox ───────────────────────────────────────────────────
  @override
  Future<void> enqueue({
    required String entityType,
    required String operation,
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
  }) async {
    if (!isReady) return;
    final item = db.SyncQueueItem()
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

  @override
  Future<List<SyncQueueItem>> pendingOps() async {
    if (!isReady) return [];
    final rows = await _isar.syncQueueItems
        .filter()
        .isFailedEqualTo(false)
        .sortByCreatedAt()
        .findAll();
    return rows.map(_queueToModel).toList();
  }

  @override
  Future<int> pendingCount() async {
    if (!isReady) return 0;
    return _isar.syncQueueItems.filter().isFailedEqualTo(false).count();
  }

  @override
  Future<void> deleteOp(int id) async {
    if (!isReady) return;
    await _isar.writeTxn(() => _isar.syncQueueItems.delete(id));
  }

  @override
  Future<void> saveOp(SyncQueueItem op) async {
    if (!isReady) return;
    final row = db.SyncQueueItem()
      ..id = op.id ?? Isar.autoIncrement
      ..operationId = op.operationId
      ..entityType = op.entityType
      ..operation = op.operation
      ..endpoint = op.endpoint
      ..method = op.method
      ..payload = op.payload
      ..createdAt = op.createdAt
      ..retryCount = op.retryCount
      ..isFailed = op.isFailed
      ..errorMessage = op.errorMessage;
    await _isar.writeTxn(() => _isar.syncQueueItems.put(row));
  }

  // ── Offline KOTs ─────────────────────────────────────────────
  @override
  Future<void> saveOfflineKot(OfflineKot kot, List<OfflineKotItem> items) async {
    if (!isReady) return;
    await _isar.writeTxn(() async {
      await _isar.offlineKots.put(_kotToRow(kot));
      await _isar.offlineKotItems.putAll(items.map(_itemToRow).toList());
    });
  }

  @override
  Future<List<OfflineKot>> kotsForSession(String sessionId) async {
    if (!isReady) return [];
    final rows = await _isar.offlineKots
        .filter()
        .sessionIdEqualTo(sessionId)
        .sortByCreatedAt()
        .findAll();
    return rows.map(_kotToModel).toList();
  }

  @override
  Future<List<OfflineKotItem>> itemsForKot(String kotId) async {
    if (!isReady) return [];
    final rows = await _isar.offlineKotItems
        .filter()
        .kotIdEqualTo(kotId)
        .sortByCreatedAt()
        .findAll();
    return rows.map(_itemToModel).toList();
  }

  @override
  Future<void> deleteOfflineKot(String kotId) async {
    if (!isReady) return;
    final items =
        await _isar.offlineKotItems.filter().kotIdEqualTo(kotId).findAll();
    await _isar.writeTxn(() async {
      await _isar.offlineKots.delete(db.fastHash(kotId));
      await _isar.offlineKotItems
          .deleteAll(items.map((e) => e.isarId).toList());
    });
  }

  @override
  Future<void> clearAll() => IsarService.instance.clearAll();

  // ── Mapping helpers (plain model ↔ Isar row) ─────────────────
  db.OfflineKot _kotToRow(OfflineKot k) => db.OfflineKot()
    ..id = k.id
    ..branchId = k.branchId
    ..sessionId = k.sessionId
    ..tableId = k.tableId
    ..kotNumber = k.kotNumber
    ..status = k.status
    ..waiterId = k.waiterId
    ..waiterName = k.waiterName
    ..createdAt = k.createdAt
    ..isPendingSync = k.isPendingSync
    ..syncedAt = k.syncedAt;

  OfflineKot _kotToModel(db.OfflineKot r) => OfflineKot()
    ..id = r.id
    ..branchId = r.branchId
    ..sessionId = r.sessionId
    ..tableId = r.tableId
    ..kotNumber = r.kotNumber
    ..status = r.status
    ..waiterId = r.waiterId
    ..waiterName = r.waiterName
    ..createdAt = r.createdAt
    ..isPendingSync = r.isPendingSync
    ..syncedAt = r.syncedAt;

  db.OfflineKotItem _itemToRow(OfflineKotItem i) => db.OfflineKotItem()
    ..id = i.id
    ..kotId = i.kotId
    ..menuItemId = i.menuItemId
    ..menuItemName = i.menuItemName
    ..quantity = i.quantity
    ..unitPrice = i.unitPrice
    ..notes = i.notes
    ..createdAt = i.createdAt;

  OfflineKotItem _itemToModel(db.OfflineKotItem r) => OfflineKotItem()
    ..id = r.id
    ..kotId = r.kotId
    ..menuItemId = r.menuItemId
    ..menuItemName = r.menuItemName
    ..quantity = r.quantity
    ..unitPrice = r.unitPrice
    ..notes = r.notes
    ..createdAt = r.createdAt;

  SyncQueueItem _queueToModel(db.SyncQueueItem r) => SyncQueueItem()
    ..id = r.id
    ..operationId = r.operationId
    ..entityType = r.entityType
    ..operation = r.operation
    ..endpoint = r.endpoint
    ..method = r.method
    ..payload = r.payload
    ..createdAt = r.createdAt
    ..retryCount = r.retryCount
    ..isFailed = r.isFailed
    ..errorMessage = r.errorMessage;
}
