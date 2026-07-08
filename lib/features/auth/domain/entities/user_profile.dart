import 'package:equatable/equatable.dart';

class UserProfile extends Equatable {
  final String id;
  final String fullName;
  final String role;
  final String? branchId;
  final String? phone;
  final String? avatarUrl;
  final bool isActive;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.fullName,
    required this.role,
    this.branchId,
    this.phone,
    this.avatarUrl,
    required this.isActive,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      role: json['role'] as String,
      branchId: json['branch_id'] as String?,
      phone: json['phone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'role': role,
        'branch_id': branchId,
        'phone': phone,
        'avatar_url': avatarUrl,
        'is_active': isActive,
      };

  bool get isSuperAdmin => role == 'super_admin';
  bool get isBranchManager => role == 'branch_manager';
  bool get isCashier => role == 'cashier';
  bool get isWaiter => role == 'waiter';
  bool get isKitchen => role == 'kitchen';
  bool get isInventory => role == 'inventory';
  bool get isAccountant => role == 'accountant';

  bool get canViewFinancials =>
      role == 'branch_manager' || role == 'accountant';
  bool get canManageOrders =>
      role == 'branch_manager' || role == 'cashier' || role == 'waiter';
  bool get canAccessBilling =>
      role == 'branch_manager' || role == 'cashier';

  @override
  List<Object?> get props => [id, fullName, role, branchId, isActive];
}
