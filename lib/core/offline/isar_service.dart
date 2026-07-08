// ============================================================
// KATIYA STATION RMS — ISAR OFFLINE DATABASE SERVICE
// Local-first storage for offline mode support
// ============================================================

import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'isar_schemas.dart';

class IsarService {
  IsarService._();
  static final IsarService instance = IsarService._();

  Isar? _isar;
  bool _initialized = false;

  Isar get isar {
    assert(_initialized, 'IsarService must be initialized before use.');
    return _isar!;
  }

  bool get isInitialized => _initialized;

  // ── Initialize ─────────────────────────────────────────────
  Future<void> initialize() async {
    if (_initialized) return;

    final dir = await getApplicationDocumentsDirectory();

    _isar = await Isar.open(
      [
        // Offline schemas
        OfflineMenuItemSchema,
        OfflineTableSchema,
        OfflineKotSchema,
        OfflineKotItemSchema,
        SyncQueueItemSchema,
        CachedBillSchema,
      ],
      directory: dir.path,
      name: 'katiya_station_offline',
      inspector: false, // set to true during dev for Isar Inspector
    );

    _initialized = true;
  }

  // ── Clear all offline data (on logout) ────────────────────
  Future<void> clearAll() async {
    if (!_initialized) return;
    await _isar!.writeTxn(() => _isar!.clear());
  }

  // ── Close (app dispose) ────────────────────────────────────
  Future<void> close() async {
    if (_isar?.isOpen ?? false) {
      await _isar!.close();
    }
    _initialized = false;
  }
}
