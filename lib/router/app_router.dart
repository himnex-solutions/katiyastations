import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../core/widgets/app_shell.dart';

// Feature screens
import '../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../features/tables/presentation/screens/tables_screen.dart';
import '../features/orders/presentation/screens/order_screen.dart';
import '../features/kitchen/presentation/screens/kitchen_screen.dart';
import '../features/cashier/presentation/screens/cashier_screen.dart';
import '../features/payment_history/presentation/screens/payment_history_screen.dart';
import '../features/menu/presentation/screens/menu_management_screen.dart';
import '../features/inventory/presentation/screens/inventory_screen.dart';
import '../features/bar/presentation/screens/bar_screen.dart';
import '../features/purchase/presentation/screens/purchase_screen.dart';
import '../features/expense/presentation/screens/expense_screen.dart';
import '../features/credit/presentation/screens/credit_screen.dart';
import '../features/reservation/presentation/screens/reservation_screen.dart';
import '../features/customers/presentation/screens/customers_screen.dart';
import '../features/staff/presentation/screens/staff_screen.dart';
import '../features/users/presentation/screens/users_screen.dart';
import '../features/attendance/presentation/screens/attendance_screen.dart';
import '../features/reports/presentation/screens/reports_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/notifications/presentation/screens/notifications_screen.dart';
import '../features/loyalty/presentation/screens/loyalty_screen.dart';
import '../features/suppliers/presentation/screens/supplier_screen.dart';
import '../features/branches/presentation/screens/branch_management_screen.dart';
import '../features/shift_closing/presentation/screens/shift_closing_screen.dart';
import '../features/audit_logs/presentation/screens/audit_log_screen.dart';
import '../features/super_admin/presentation/screens/super_admin_portal.dart';

// Nav items model
class NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String path;
  final List<String> allowedRoles;

  const NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.path,
    this.allowedRoles = const [],
  });
}

const List<NavItem> allNavItems = [
  NavItem(label: 'Super Admin', icon: Icons.verified_user, activeIcon: Icons.verified_user, path: '/super-admin',
      allowedRoles: ['super_admin']),
  NavItem(label: 'Dashboard', icon: Icons.dashboard, activeIcon: Icons.dashboard_outlined, path: '/dashboard',
      allowedRoles: ['branch_manager', 'cashier', 'waiter', 'kitchen', 'inventory', 'accountant']),
  NavItem(label: 'Tables', icon: Icons.grid_view, activeIcon: Icons.grid_view, path: '/tables',
      allowedRoles: ['branch_manager', 'cashier', 'waiter']),
  NavItem(label: 'Kitchen', icon: Icons.soup_kitchen, activeIcon: Icons.soup_kitchen, path: '/kitchen',
      allowedRoles: ['branch_manager', 'cashier', 'kitchen']),
  NavItem(label: 'Cashier', icon: Icons.point_of_sale, activeIcon: Icons.point_of_sale, path: '/cashier',
      allowedRoles: ['cashier']),
  NavItem(label: 'Payments', icon: Icons.receipt_long, activeIcon: Icons.receipt_long, path: '/payment-history',
      allowedRoles: ['branch_manager', 'cashier', 'accountant']),
  NavItem(label: 'Menu', icon: Icons.restaurant_menu, activeIcon: Icons.restaurant_menu, path: '/menu',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Inventory', icon: Icons.inventory_2, activeIcon: Icons.inventory_2, path: '/inventory',
      allowedRoles: ['branch_manager', 'inventory']),
  NavItem(label: 'Bar', icon: Icons.wine_bar, activeIcon: Icons.wine_bar, path: '/bar',
      allowedRoles: ['inventory']),
  NavItem(label: 'Purchases', icon: Icons.shopping_cart, activeIcon: Icons.shopping_cart, path: '/purchases',
      allowedRoles: ['branch_manager', 'inventory']),
  NavItem(label: 'Expenses', icon: Icons.payments, activeIcon: Icons.payments, path: '/expenses',
      allowedRoles: ['branch_manager', 'accountant']),
  NavItem(label: 'Credit', icon: Icons.credit_card, activeIcon: Icons.credit_card, path: '/credit',
      allowedRoles: ['branch_manager', 'cashier', 'accountant']),
  NavItem(label: 'Reservations', icon: Icons.event_available, activeIcon: Icons.event_available, path: '/reservations',
      allowedRoles: ['cashier']),
  NavItem(label: 'Customers', icon: Icons.people, activeIcon: Icons.people, path: '/customers',
      allowedRoles: ['cashier']),
  NavItem(label: 'Staff', icon: Icons.badge, activeIcon: Icons.badge, path: '/staff',
      allowedRoles: ['branch_manager']),
  NavItem(label: 'Users', icon: Icons.manage_accounts, activeIcon: Icons.manage_accounts, path: '/users',
      allowedRoles: ['branch_manager']),
  NavItem(label: 'Attendance', icon: Icons.fingerprint, activeIcon: Icons.fingerprint, path: '/attendance',
      allowedRoles: ['cashier', 'waiter', 'kitchen', 'inventory']),
  NavItem(label: 'Reports', icon: Icons.bar_chart, activeIcon: Icons.bar_chart, path: '/reports',
      allowedRoles: ['branch_manager', 'accountant', 'cashier']),
  NavItem(label: 'Settings', icon: Icons.settings, activeIcon: Icons.settings_outlined, path: '/settings',
      allowedRoles: ['super_admin', 'branch_manager']),
  NavItem(label: 'Loyalty', icon: Icons.star, activeIcon: Icons.star, path: '/loyalty',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Suppliers', icon: Icons.local_shipping, activeIcon: Icons.local_shipping, path: '/suppliers',
      allowedRoles: ['branch_manager', 'inventory']),
  NavItem(label: 'Branches', icon: Icons.store, activeIcon: Icons.store, path: '/branches',
      allowedRoles: ['super_admin', 'branch_manager']),
  NavItem(label: 'Shift Close', icon: Icons.lock, activeIcon: Icons.lock, path: '/shift-closing',
      allowedRoles: ['branch_manager', 'cashier']),
  NavItem(label: 'Audit Logs', icon: Icons.history, activeIcon: Icons.history, path: '/audit-logs',
      allowedRoles: ['super_admin', 'branch_manager']),
];

List<NavItem> getNavItemsForRole(String? role) {
  if (role == null) return [];
  return allNavItems.where((item) => item.allowedRoles.contains(role)).toList();
}

/// Bridges a Riverpod [StateNotifier] stream to go_router's
/// [Listenable]-based refresh mechanism, so the redirect callback re-runs
/// on auth changes without the [GoRouter] instance itself being rebuilt
/// (rebuilding it would reset navigation back to [initialLocation] and
/// blow away whatever page the user was on).
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // Only watch the notifier (a stable instance for the provider's
  // lifetime), not its state — otherwise every auth state change would
  // rebuild this whole provider and hand MaterialApp.router a brand-new
  // GoRouter, resetting navigation to initialLocation on every login,
  // logout, or session-restore tick.
  final authNotifier = ref.watch(authNotifierProvider.notifier);
  final refresh = GoRouterRefreshStream(authNotifier.stream);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      // Use valueOrNull, not value: AsyncValue.value rethrows when the
      // state is AsyncError (e.g. a failed login), which would blow up
      // inside GoRouter's redirect/notification dispatch.
      final isLoggedIn = authState.valueOrNull != null;
      final isLoginPage = state.matchedLocation == '/login';
      final isSplash = state.matchedLocation == '/';

      if (isSplash) return null;

      // Session is still being resolved (app just started, or a hard
      // refresh landed on a deep route). Hold position instead of
      // bouncing to /login — once it resolves, this redirect re-runs
      // via refreshListenable and either lets the user stay put (if
      // still logged in) or sends them to /login (if not).
      if (authState.isLoading) return null;

      if (!isLoggedIn && !isLoginPage) return '/login';
      if (isLoggedIn) {
        final role = authState.valueOrNull?.role;
        if (isLoginPage) {
          return role == 'super_admin' ? '/super-admin' : '/dashboard';
        }
        if (state.matchedLocation == '/dashboard' && role == 'super_admin') {
          return '/super-admin';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (ctx, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (ctx, _) => const LoginScreen()),
      ShellRoute(
        builder: (ctx, state, child) => AppShell(currentPath: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/super-admin', builder: (ctx, _) => const SuperAdminPortal()),
          GoRoute(path: '/dashboard', builder: (ctx, _) => const DashboardScreen()),
          GoRoute(path: '/tables', builder: (ctx, _) => const TablesScreen()),
          GoRoute(
            path: '/tables/:tableId/order',
            builder: (ctx, state) => OrderScreen(
              tableId: state.pathParameters['tableId']!,
              sessionId: state.uri.queryParameters['sessionId'] ?? '',
            ),
          ),
          GoRoute(path: '/kitchen', builder: (ctx, _) => const KitchenScreen()),
          GoRoute(
            path: '/cashier',
            builder: (ctx, state) => CashierScreen(
              sessionId: state.uri.queryParameters['sessionId'] ?? '',
              tableId: state.uri.queryParameters['tableId'] ?? '',
            ),
          ),
          GoRoute(path: '/payment-history', builder: (ctx, _) => const PaymentHistoryScreen()),
          GoRoute(path: '/menu', builder: (ctx, _) => const MenuManagementScreen()),
          GoRoute(path: '/inventory', builder: (ctx, _) => const InventoryScreen()),
          GoRoute(path: '/bar', builder: (ctx, _) => const BarScreen()),
          GoRoute(path: '/purchases', builder: (ctx, _) => const PurchaseScreen()),
          GoRoute(path: '/expenses', builder: (ctx, _) => const ExpenseScreen()),
          GoRoute(path: '/credit', builder: (ctx, _) => const CreditScreen()),
          GoRoute(path: '/reservations', builder: (ctx, _) => const ReservationScreen()),
          GoRoute(path: '/customers', builder: (ctx, _) => const CustomersScreen()),
          GoRoute(path: '/staff', builder: (ctx, _) => const StaffScreen()),
          GoRoute(path: '/users', builder: (ctx, _) => const UsersScreen()),
          GoRoute(path: '/attendance', builder: (ctx, _) => const AttendanceScreen()),
          GoRoute(path: '/reports', builder: (ctx, _) => const ReportsScreen()),
          GoRoute(path: '/settings', builder: (ctx, _) => const SettingsScreen()),
          GoRoute(path: '/notifications', builder: (ctx, _) => const NotificationsScreen()),
          GoRoute(path: '/loyalty', builder: (ctx, _) => const LoyaltyScreen()),
          GoRoute(path: '/suppliers', builder: (ctx, _) => const SupplierScreen()),
          GoRoute(path: '/branches', builder: (ctx, _) => const BranchManagementScreen()),
          GoRoute(path: '/shift-closing', builder: (ctx, _) => const ShiftClosingScreen()),
          GoRoute(path: '/audit-logs', builder: (ctx, _) => const AuditLogScreen()),
        ],
      ),
    ],
    errorBuilder: (ctx, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.error}')),
    ),
  );
});
