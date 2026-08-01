// ============================================================
// KATIYA STATION RMS — OFFLINE READ CACHE
// Stores the last successful GET response (raw JSON) so a screen can still
// render while offline. Backed by SharedPreferences — deliberately not Isar:
// caching the raw server JSON and replaying `.fromJson` on it avoids any
// field-mapping bugs between the wire shape and a typed local schema.
// ============================================================

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache-key builders — one place so the writer (online read) and the reader
/// (offline fallback) can never drift apart.
class CacheKeys {
  static String tables(String branchId) => 'tables:$branchId';
  static String openSessions(String branchId) => 'sessions:$branchId';
  static String menuCategories(String branchId) => 'menuCategories:$branchId';
  static String menuItemsByCategory(String categoryId) => 'menuItems:cat:$categoryId';
  static String menuItemsByBranch(String branchId) => 'menuItems:branch:$branchId';
  static String offlineSession(String tableId) => 'offlineSession:$tableId';
  // Call-in / delivery orders. Cached so the till can still see (and settle)
  // what is outstanding when the internet drops — offline this list used to
  // come back empty, which reads identically to "nothing pending".
  static String onlineOrders(String branchId) => 'onlineOrders:$branchId';
  static String onlineOrderHistory(String branchId) => 'onlineOrderHistory:$branchId';

  static const String offlineSessionPrefix = 'offlineSession:';

  // A session settled while offline, keyed by sessionId — its bill is queued
  // and assigns the real invoice number on sync.
  static String billedOffline(String sessionId) => 'billedOffline:$sessionId';
  static const String billedOfflinePrefix = 'billedOffline:';

  // An order (or one of its lines) cancelled while offline. See the tombstone
  // note on OfflineCache below — these are what stop a cancelled order coming
  // back from the server before the queued cancel has landed.
  static String cancelledKot(String kotId) => 'cancelledKot:$kotId';
  static const String cancelledKotPrefix = 'cancelledKot:';

  static String cancelledItem(String itemId) => 'cancelledItem:$itemId';
  static const String cancelledItemPrefix = 'cancelledItem:';
}

class OfflineCache {
  OfflineCache._();
  static final OfflineCache instance = OfflineCache._();

  static const _prefix = 'offline_cache:';

  SharedPreferences? _prefs;
  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Store any JSON-encodable value (a List or Map) under [key].
  Future<void> put(String key, Object json) async {
    final p = await _p;
    await p.setString('$_prefix$key', jsonEncode(json));
  }

  /// Read back a previously cached value, or null if nothing/undecodable.
  Future<dynamic> get(String key) async {
    final p = await _p;
    final raw = p.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) async {
    final p = await _p;
    await p.remove('$_prefix$key');
  }

  // ── Offline sessions ─────────────────────────────────────────
  // A table opened while offline is remembered here, stored in the exact
  // server JSON shape so TableSession.fromJson works unchanged. Keyed by
  // tableId so the tables list and the per-table lookup can both find it.

  Future<void> putOfflineSession(String tableId, Map<String, dynamic> sessionJson) =>
      put(CacheKeys.offlineSession(tableId), sessionJson);

  Future<Map<String, dynamic>?> getOfflineSession(String tableId) async {
    final data = await get(CacheKeys.offlineSession(tableId));
    return data is Map<String, dynamic> ? data : null;
  }

  Future<void> removeOfflineSession(String tableId) =>
      remove(CacheKeys.offlineSession(tableId));

  /// All offline-opened sessions, as tableId → session JSON. Used to overlay
  /// "occupied" onto the cached tables list while offline.
  Future<Map<String, Map<String, dynamic>>> allOfflineSessionsByTable() async {
    final p = await _p;
    final result = <String, Map<String, dynamic>>{};
    const fullPrefix = '$_prefix${CacheKeys.offlineSessionPrefix}';
    for (final key in p.getKeys()) {
      if (!key.startsWith(fullPrefix)) continue;
      final tableId = key.substring(fullPrefix.length);
      final raw = p.getString(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) result[tableId] = decoded;
      } catch (_) {}
    }
    return result;
  }

  // ── Sessions billed offline ──────────────────────────────────
  // A session settled while offline is recorded here (by sessionId) so this
  // device frees the table right away and won't let it be re-billed. The queued
  // bill assigns the official invoice number on sync, after which this marker is
  // cleared (see SyncEngine._cleanupAfterSync).

  Future<void> putBilledOfflineSession(String sessionId) =>
      put(CacheKeys.billedOffline(sessionId), {'at': DateTime.now().toIso8601String()});

  Future<void> removeBilledOfflineSession(String sessionId) =>
      remove(CacheKeys.billedOffline(sessionId));

  /// Session ids settled offline on this device and not yet synced.
  Future<Set<String>> billedOfflineSessionIds() async {
    final p = await _p;
    final result = <String>{};
    const fullPrefix = '$_prefix${CacheKeys.billedOfflinePrefix}';
    for (final key in p.getKeys()) {
      if (key.startsWith(fullPrefix)) result.add(key.substring(fullPrefix.length));
    }
    return result;
  }

  // ── Cancelled-offline tombstones ─────────────────────────────
  //
  // A cancel used to leave NO local trace: the local copy was deleted and the
  // only record was one queued API call. So the moment a refetch beat the
  // outbox drain, the server still said "pending" and the cancelled order came
  // straight back onto the bill — and if that queued call ever failed, it came
  // back for good, silently.
  //
  // A tombstone is the missing half: the device remembers what was DELETED,
  // not just what was added, and that memory outranks the server until the
  // cancel is confirmed synced (SyncEngine._cleanupAfterSync clears it).
  //
  // Entries self-expire after [_tombstoneTtl] so a cancel that can never sync
  // eventually surfaces the truth instead of hiding an order forever.
  static const Duration _tombstoneTtl = Duration(hours: 24);

  Future<void> putCancelledKot(String kotId) =>
      put(CacheKeys.cancelledKot(kotId), {'at': DateTime.now().toIso8601String()});

  Future<void> removeCancelledKot(String kotId) =>
      remove(CacheKeys.cancelledKot(kotId));

  /// KOT ids cancelled on this device (or mirrored in from another) whose
  /// cancel has not yet reached the server.
  Future<Set<String>> cancelledKotIds() =>
      _liveTombstones(CacheKeys.cancelledKotPrefix);

  Future<void> putCancelledItem(String itemId) =>
      put(CacheKeys.cancelledItem(itemId), {'at': DateTime.now().toIso8601String()});

  Future<void> removeCancelledItem(String itemId) =>
      remove(CacheKeys.cancelledItem(itemId));

  /// KOT-item ids cancelled but not yet synced.
  Future<Set<String>> cancelledItemIds() =>
      _liveTombstones(CacheKeys.cancelledItemPrefix);

  /// Ids under [keyPrefix] that haven't aged out, sweeping expired ones away
  /// as it goes.
  Future<Set<String>> _liveTombstones(String keyPrefix) async {
    final p = await _p;
    final result = <String>{};
    final expired = <String>[];
    final fullPrefix = '$_prefix$keyPrefix';
    final cutoff = DateTime.now().subtract(_tombstoneTtl);

    for (final key in p.getKeys()) {
      if (!key.startsWith(fullPrefix)) continue;
      final id = key.substring(fullPrefix.length);
      DateTime? at;
      try {
        final raw = p.getString(key);
        if (raw != null) {
          final decoded = jsonDecode(raw);
          if (decoded is Map && decoded['at'] is String) {
            at = DateTime.tryParse(decoded['at'] as String);
          }
        }
      } catch (_) {/* treat as undated */}

      if (at != null && at.isBefore(cutoff)) {
        expired.add(key);
      } else {
        result.add(id);
      }
    }
    for (final key in expired) {
      await p.remove(key);
    }
    return result;
  }

  /// Wipe everything (called on logout alongside IsarService.clearAll()).
  Future<void> clear() async {
    final p = await _p;
    for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await p.remove(k);
    }
  }
}
