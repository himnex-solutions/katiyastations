// ============================================================
// KATIYA STATION RMS — ISAR OFFLINE SCHEMAS
// Local-first entity schemas for offline mode
// Generated with: dart run build_runner build
// ============================================================

import 'package:isar/isar.dart';

part 'isar_schemas.g.dart';

// ── Offline Menu Item ──────────────────────────────────────
@collection
class OfflineMenuItem {
  Id get isarId => fastHash(id);

  late String id;
  late String branchId;
  late String categoryId;
  late String categoryName;
  late String name;
  late double price;
  late String type; // food | drink | bar
  late bool isAvailable;
  String? description;
  String? imageUrl;
  late DateTime syncedAt;
}

// ── Offline Restaurant Table ───────────────────────────────
@collection
class OfflineTable {
  Id get isarId => fastHash(id);

  late String id;
  late String branchId;
  late String tableNumber;
  late String section;
  late int capacity;
  late String status; // available | occupied | reserved | cleaning
  String? currentSessionId;
  late DateTime syncedAt;
}

// ── Offline KOT ───────────────────────────────────────────
@collection
class OfflineKot {
  Id get isarId => fastHash(id);

  late String id;
  late String branchId;
  late String sessionId;
  late String tableId;
  late String kotNumber;
  late String status; // pending | preparing | ready | served | cancelled
  String? waiterId;
  String? waiterName;
  late DateTime createdAt;
  bool isPendingSync = false; // true = not yet sent to server
  late DateTime syncedAt;
}

// ── Offline KOT Item ──────────────────────────────────────
@collection
class OfflineKotItem {
  Id get isarId => fastHash(id);

  late String id;
  late String kotId;
  late String menuItemId;
  late String menuItemName;
  late int quantity;
  late double unitPrice;
  String? notes;
  late DateTime createdAt;
}

// ── Offline Cached Bill ────────────────────────────────────
@collection
class CachedBill {
  Id get isarId => fastHash(id);

  late String id;
  late String branchId;
  late String sessionId;
  late String billNumber;
  late double subTotal;
  late double discount;
  late double serviceCharge;
  late double vatAmount;
  late double totalAmount;
  late String paymentMethod;
  late String paymentStatus;
  late DateTime createdAt;
}

// ── Sync Queue Item ───────────────────────────────────────
// Queues mutations made while offline for syncing when reconnected
@collection
class SyncQueueItem {
  Id id = Isar.autoIncrement;

  late String operationId; // unique per mutation
  late String entityType; // kot | table | bill | etc.
  late String operation; // create | update | delete
  late String endpoint; // API endpoint path
  late String method; // POST | PATCH | DELETE
  late String payload; // JSON-encoded body
  late DateTime createdAt;
  late int retryCount;
  bool isFailed = false;
  String? errorMessage;
}

// ── Fast hash helper (maps String UUID → Isar int Id) ─────
int fastHash(String string) {
  var hash = 0xcbf29ce484222325;

  var i = 0;
  while (i < string.length) {
    final codeUnit = string.codeUnitAt(i++);
    hash ^= codeUnit >> 8;
    hash *= 0x100000001b3;
    hash ^= codeUnit & 0xFF;
    hash *= 0x100000001b3;
  }

  return hash;
}
