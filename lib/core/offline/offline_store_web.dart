// ============================================================
// KATIYA STATION RMS — OFFLINE STORE (web backend)
// Selected on the Flutter Web (dart2js) build, where Isar's native core and
// its 64-bit-literal generated schemas are unavailable/uncompilable.
//
// Backed by SharedPreferences (localStorage on web) — the same dependency
// OfflineCache already uses — so offline order-taking still works in the
// browser without pulling Isar into the JavaScript bundle.
// ============================================================

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'offline_ids.dart';
import 'offline_store.dart'; // re-exports offline_models.dart

/// Factory referenced by the conditional import in offline_store.dart.
OfflineStore createOfflineStore() => WebOfflineStore();

class WebOfflineStore implements OfflineStore {
  static const _kQueue = 'offline_store:queue';
  static const _kKots = 'offline_store:kots';
  static const _kItems = 'offline_store:kotItems';
  static const _kSeq = 'offline_store:seq';

  SharedPreferences? _prefs;
  bool _ready = false;

  @override
  bool get isReady => _ready;

  @override
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _ready = true;
  }

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ── Generic list persistence ─────────────────────────────────
  Future<List<Map<String, dynamic>>> _readList(String key) async {
    final p = await _p;
    final raw = p.getString(key);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeList(String key, List<Map<String, dynamic>> rows) async {
    final p = await _p;
    await p.setString(key, jsonEncode(rows));
  }

  Future<int> _nextId() async {
    final p = await _p;
    final next = (p.getInt(_kSeq) ?? 0) + 1;
    await p.setInt(_kSeq, next);
    return next;
  }

  // ── Outbox ───────────────────────────────────────────────────
  @override
  Future<void> enqueue({
    required String entityType,
    required String operation,
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
  }) async {
    final item = SyncQueueItem()
      ..id = await _nextId()
      ..operationId = newOfflineId()
      ..entityType = entityType
      ..operation = operation
      ..endpoint = endpoint
      ..method = method
      ..payload = jsonEncode(payload)
      ..createdAt = DateTime.now()
      ..retryCount = 0
      ..isFailed = false;
    final rows = await _readList(_kQueue)..add(item.toJson());
    await _writeList(_kQueue, rows);
  }

  @override
  Future<List<SyncQueueItem>> pendingOps() async {
    final rows = await _readList(_kQueue);
    final ops = rows
        .map(SyncQueueItem.fromJson)
        .where((o) => !o.isFailed)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return ops;
  }

  @override
  Future<int> pendingCount() async {
    final rows = await _readList(_kQueue);
    return rows.map(SyncQueueItem.fromJson).where((o) => !o.isFailed).length;
  }

  @override
  Future<void> deleteOp(int id) async {
    final rows = await _readList(_kQueue)
      ..removeWhere((r) => r['id'] == id);
    await _writeList(_kQueue, rows);
  }

  @override
  Future<void> saveOp(SyncQueueItem op) async {
    op.id ??= await _nextId();
    final rows = await _readList(_kQueue);
    final idx = rows.indexWhere((r) => r['id'] == op.id);
    if (idx >= 0) {
      rows[idx] = op.toJson();
    } else {
      rows.add(op.toJson());
    }
    await _writeList(_kQueue, rows);
  }

  // ── Offline KOTs ─────────────────────────────────────────────
  @override
  Future<void> saveOfflineKot(OfflineKot kot, List<OfflineKotItem> items) async {
    final kots = await _readList(_kKots)
      ..removeWhere((r) => r['id'] == kot.id)
      ..add(kot.toJson());
    await _writeList(_kKots, kots);

    final allItems = await _readList(_kItems);
    for (final item in items) {
      allItems
        ..removeWhere((r) => r['id'] == item.id)
        ..add(item.toJson());
    }
    await _writeList(_kItems, allItems);
  }

  @override
  Future<List<OfflineKot>> kotsForSession(String sessionId) async {
    final rows = await _readList(_kKots);
    final kots = rows
        .map(OfflineKot.fromJson)
        .where((k) => k.sessionId == sessionId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return kots;
  }

  @override
  Future<List<OfflineKotItem>> itemsForKot(String kotId) async {
    final rows = await _readList(_kItems);
    final items = rows
        .map(OfflineKotItem.fromJson)
        .where((i) => i.kotId == kotId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  @override
  Future<void> deleteOfflineKot(String kotId) async {
    final kots = await _readList(_kKots)
      ..removeWhere((r) => r['id'] == kotId);
    await _writeList(_kKots, kots);

    final items = await _readList(_kItems)
      ..removeWhere((r) => r['kotId'] == kotId);
    await _writeList(_kItems, items);
  }

  @override
  Future<void> clearAll() async {
    final p = await _p;
    await p.remove(_kQueue);
    await p.remove(_kKots);
    await p.remove(_kItems);
    await p.remove(_kSeq);
  }
}
