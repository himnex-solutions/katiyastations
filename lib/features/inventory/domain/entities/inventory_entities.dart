import 'package:equatable/equatable.dart';

class InventoryItem extends Equatable {
  final String id, branchId, name, unit;
  final double currentStock, reorderLevel;
  final double? costPerUnit;
  final String? supplierId;
  final DateTime updatedAt;

  const InventoryItem({required this.id, required this.branchId, required this.name, required this.unit,
      required this.currentStock, required this.reorderLevel, this.costPerUnit, this.supplierId, required this.updatedAt});

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
    id: j['id'] as String, branchId: j['branch_id'] as String, name: j['name'] as String, unit: j['unit'] as String,
    currentStock: (j['current_stock'] as num?)?.toDouble() ?? 0,
    reorderLevel: (j['reorder_level'] as num?)?.toDouble() ?? 0,
    costPerUnit: (j['cost_per_unit'] as num?)?.toDouble(),
    supplierId: j['supplier_id'] as String?,
    updatedAt: DateTime.parse(j['updated_at'] ?? j['created_at'] as String),
  );

  bool get isLow => currentStock <= reorderLevel && currentStock > 0;
  bool get isOut => currentStock <= 0;

  @override
  List<Object?> get props => [id, name, currentStock];
}

class BarStockItem extends Equatable {
  final String id, branchId, name, category;
  final double bottleCapacityMl, currentBottles, pegsMl;
  final double pricePerPeg;
  final DateTime updatedAt;

  const BarStockItem({required this.id, required this.branchId, required this.name, required this.category,
      required this.bottleCapacityMl, required this.currentBottles, required this.pegsMl,
      required this.pricePerPeg, required this.updatedAt});

  factory BarStockItem.fromJson(Map<String, dynamic> j) => BarStockItem(
    id: j['id'] as String, branchId: j['branch_id'] as String, name: j['name'] as String,
    category: j['category'] as String? ?? 'spirits',
    bottleCapacityMl: (j['bottle_capacity_ml'] as num?)?.toDouble() ?? 750,
    currentBottles: (j['current_bottles'] as num?)?.toDouble() ?? 0,
    pegsMl: (j['pegs_ml'] as num?)?.toDouble() ?? 30,
    pricePerPeg: (j['price_per_peg'] as num?)?.toDouble() ?? 0,
    updatedAt: DateTime.parse(j['updated_at'] ?? j['created_at'] as String),
  );

  double get totalMlRemaining => currentBottles * bottleCapacityMl;
  int get pegsRemaining => (totalMlRemaining / pegsMl).floor();

  @override
  List<Object?> get props => [id, name, currentBottles];
}
