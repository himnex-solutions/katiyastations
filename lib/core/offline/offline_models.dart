// ============================================================
// KATIYA STATION RMS — OFFLINE MODELS (platform-neutral)
// Plain Dart data classes shared by every platform's OfflineStore.
//
// These deliberately depend on NOTHING platform-specific (no Isar, no
// dart:io). Isar's generated schemas live behind the native store impl only,
// so the feature layer and the web build talk to these POJOs instead.
//
// Why this matters: Isar's generated `.g.dart` embeds 64-bit schema-hash
// literals (e.g. 7675659480273757682) which dart2js cannot represent, so it
// must never reach the web compiler. Keeping the shared contract on plain
// models lets the web build compile without ever importing Isar.
// ============================================================

/// A KOT (kitchen order ticket) taken while offline, awaiting sync.
class OfflineKot {
  String id = '';
  String branchId = '';
  String sessionId = '';
  String tableId = '';
  String kotNumber = '';
  String status = 'pending';
  String? waiterId;
  String? waiterName;
  DateTime createdAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool isPendingSync = false;
  DateTime syncedAt = DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, dynamic> toJson() => {
        'id': id,
        'branchId': branchId,
        'sessionId': sessionId,
        'tableId': tableId,
        'kotNumber': kotNumber,
        'status': status,
        'waiterId': waiterId,
        'waiterName': waiterName,
        'createdAt': createdAt.toIso8601String(),
        'isPendingSync': isPendingSync,
        'syncedAt': syncedAt.toIso8601String(),
      };

  static OfflineKot fromJson(Map<String, dynamic> j) => OfflineKot()
    ..id = j['id'] as String
    ..branchId = j['branchId'] as String
    ..sessionId = j['sessionId'] as String
    ..tableId = j['tableId'] as String
    ..kotNumber = j['kotNumber'] as String
    ..status = j['status'] as String
    ..waiterId = j['waiterId'] as String?
    ..waiterName = j['waiterName'] as String?
    ..createdAt = DateTime.parse(j['createdAt'] as String)
    ..isPendingSync = j['isPendingSync'] as bool? ?? false
    ..syncedAt = DateTime.parse(j['syncedAt'] as String);
}

/// A single line item on an [OfflineKot].
class OfflineKotItem {
  String id = '';
  String kotId = '';
  String menuItemId = '';
  String menuItemName = '';
  int quantity = 0;
  double unitPrice = 0;
  String? notes;
  DateTime createdAt = DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, dynamic> toJson() => {
        'id': id,
        'kotId': kotId,
        'menuItemId': menuItemId,
        'menuItemName': menuItemName,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  static OfflineKotItem fromJson(Map<String, dynamic> j) => OfflineKotItem()
    ..id = j['id'] as String
    ..kotId = j['kotId'] as String
    ..menuItemId = j['menuItemId'] as String
    ..menuItemName = j['menuItemName'] as String
    ..quantity = j['quantity'] as int
    ..unitPrice = (j['unitPrice'] as num).toDouble()
    ..notes = j['notes'] as String?
    ..createdAt = DateTime.parse(j['createdAt'] as String);
}

/// One queued mutation in the offline outbox, replayed to the server on sync.
class SyncQueueItem {
  /// Local primary key. Auto-assigned by the store (Isar autoIncrement on
  /// native, a monotonic counter on web). Null until first persisted.
  int? id;

  String operationId = '';
  String entityType = '';
  String operation = '';
  String endpoint = '';
  String method = '';
  String payload = '';
  DateTime createdAt = DateTime.fromMillisecondsSinceEpoch(0);
  int retryCount = 0;
  bool isFailed = false;
  String? errorMessage;

  Map<String, dynamic> toJson() => {
        'id': id,
        'operationId': operationId,
        'entityType': entityType,
        'operation': operation,
        'endpoint': endpoint,
        'method': method,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
        'isFailed': isFailed,
        'errorMessage': errorMessage,
      };

  static SyncQueueItem fromJson(Map<String, dynamic> j) => SyncQueueItem()
    ..id = j['id'] as int?
    ..operationId = j['operationId'] as String
    ..entityType = j['entityType'] as String
    ..operation = j['operation'] as String
    ..endpoint = j['endpoint'] as String
    ..method = j['method'] as String
    ..payload = j['payload'] as String
    ..createdAt = DateTime.parse(j['createdAt'] as String)
    ..retryCount = j['retryCount'] as int? ?? 0
    ..isFailed = j['isFailed'] as bool? ?? false
    ..errorMessage = j['errorMessage'] as String?;
}
