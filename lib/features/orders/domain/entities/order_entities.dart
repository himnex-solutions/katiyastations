import 'package:equatable/equatable.dart';

class Kot extends Equatable {
  final String id;
  final String branchId;
  final String sessionId;
  final String tableId;
  final String? tableNumber;
  final String kotNumber;
  final String status; // pending | preparing | ready | served | cancelled
  final String? waiterId;
  final String? waiterName;
  final List<KotItem> items;
  final DateTime createdAt;
  final DateTime? servedAt;
  final String? notes;
  final int printCount;
  final DateTime? lastPrintedAt;

  const Kot({
    required this.id,
    required this.branchId,
    required this.sessionId,
    required this.tableId,
    this.tableNumber,
    required this.kotNumber,
    required this.status,
    this.waiterId,
    this.waiterName,
    required this.items,
    required this.createdAt,
    this.servedAt,
    this.notes,
    this.printCount = 0,
    this.lastPrintedAt,
  });

  factory Kot.fromJson(Map<String, dynamic> json) {
    final rawItems = json['kot_items'] ?? json['items'] ?? [];
    return Kot(
      id: json['id'] as String,
      branchId: json['branch_id'] as String,
      sessionId: json['session_id'] as String,
      tableId: json['table_id'] as String,
      tableNumber: json['table_number'] as String?,
      kotNumber: json['kot_number'] as String,
      status: json['status'] as String? ?? 'pending',
      waiterId: json['waiter_id'] as String?,
      waiterName: json['waiter_name'] as String?,
      items: (rawItems as List).map((i) => KotItem.fromJson(i as Map<String, dynamic>)).toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
      servedAt: json['served_at'] != null ? DateTime.parse(json['served_at'] as String) : null,
      notes: json['notes'] as String?,
      printCount: json['print_count'] as int? ?? 0,
      lastPrintedAt: json['last_printed_at'] != null ? DateTime.parse(json['last_printed_at'] as String) : null,
    );
  }

  bool get isPending => status == 'pending';
  bool get isPreparing => status == 'preparing';
  bool get isReady => status == 'ready';
  bool get isServed => status == 'served';
  bool get isCancelled => status == 'cancelled';

  Duration get elapsed => DateTime.now().difference(createdAt);

  @override
  List<Object?> get props => [id, kotNumber, status, sessionId];
}

class KotItem extends Equatable {
  final String id;
  final String kotId;
  final String menuItemId;
  final String menuItemName;
  final int quantity;
  final double unitPrice;
  final String? notes;
  final String status; // pending | preparing | ready | served | cancelled | returned

  const KotItem({
    required this.id,
    required this.kotId,
    required this.menuItemId,
    required this.menuItemName,
    required this.quantity,
    this.unitPrice = 0.0,
    this.notes,
    this.status = 'pending',
  });

  factory KotItem.fromJson(Map<String, dynamic> json) {
    return KotItem(
      id: json['id'] as String,
      kotId: json['kot_id'] as String,
      menuItemId: json['menu_item_id'] as String,
      menuItemName: json['name'] as String? ?? json['menu_item_name'] as String? ?? json['menu_item']?['name'] ?? '',
      quantity: json['quantity'] as int,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      notes: json['note'] as String? ?? json['notes'] as String?,
      status: json['status'] as String? ?? 'pending',
    );
  }

  bool get isPending => status == 'pending';
  bool get isServed => status == 'served';
  bool get isCancelled => status == 'cancelled';
  bool get isReturned => status == 'returned';

  @override
  List<Object?> get props => [id, kotId, menuItemId, quantity, unitPrice, status];
}

class KotWithItems extends Equatable {
  final String id;
  final String branchId;
  final String sessionId;
  final String tableId;
  final String kotNumber;
  final String status;
  final String? waiterId;
  final String? waiterName;
  final List<Map<String, dynamic>> items;
  final DateTime createdAt;
  final String? notes;

  const KotWithItems({
    required this.id,
    required this.branchId,
    required this.sessionId,
    required this.tableId,
    required this.kotNumber,
    required this.status,
    this.waiterId,
    this.waiterName,
    required this.items,
    required this.createdAt,
    this.notes,
  });

  @override
  List<Object?> get props => [id, kotNumber, status, sessionId, items];
}

