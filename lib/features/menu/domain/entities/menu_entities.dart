import 'package:equatable/equatable.dart';

class MenuCategory extends Equatable {
  final String id;
  final String branchId;
  final String name;
  final String type; // food | drink | bar
  final int sortOrder;
  final bool isActive;

  const MenuCategory({
    required this.id,
    required this.branchId,
    required this.name,
    required this.type,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory MenuCategory.fromJson(Map<String, dynamic> json) {
    return MenuCategory(
      id: json['id'] as String,
      branchId: json['branch_id'] as String,
      name: json['name'] as String,
      type: json['type'] as String? ?? 'food',
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [id, name, type, isActive];
}

class MenuItem extends Equatable {
  final String id;
  final String branchId;
  final String categoryId;
  final String name;
  final double price;
  final double? costPrice;
  final double taxRate;
  final String? description;
  final String? imageUrl;
  final bool isAvailable;
  final String type; // food | drink | bar

  const MenuItem({
    required this.id,
    required this.branchId,
    required this.categoryId,
    required this.name,
    required this.price,
    this.costPrice,
    this.taxRate = 0.13,
    this.description,
    this.imageUrl,
    this.isAvailable = true,
    this.type = 'food',
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'] as String,
      branchId: json['branch_id'] as String,
      categoryId: json['category_id'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      costPrice: (json['cost_price'] as num?)?.toDouble(),
      taxRate: (json['tax_rate'] as num?)?.toDouble() ?? 0.13,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      isAvailable: json['is_available'] as bool? ?? true,
      type: json['type'] as String? ?? 'food',
    );
  }

  @override
  List<Object?> get props => [id, name, price, isAvailable, categoryId];
}
