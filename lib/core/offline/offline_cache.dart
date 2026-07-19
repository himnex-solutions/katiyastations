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

  static const String offlineSessionPrefix = 'offlineSession:';
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

  /// Wipe everything (called on logout alongside IsarService.clearAll()).
  Future<void> clear() async {
    final p = await _p;
    for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await p.remove(k);
    }
  }
}
