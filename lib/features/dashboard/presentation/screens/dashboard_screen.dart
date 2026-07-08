import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../tables/presentation/providers/tables_provider.dart';
import '../../../kitchen/presentation/providers/kitchen_provider.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';

// ── Dashboard stat providers ──
final dashboardBillsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final response = await ApiClient.instance.get(
    ApiConstants.bills,
    queryParameters: {'branchId': profile!.branchId!, 'limit': '100'},
  );
  final data = response.data as Map<String, dynamic>;
  final rows = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
  return rows.where((b) => (b['created_at'] as String? ?? '').startsWith(today)).toList();
});

final dashboardExpensesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final response = await ApiClient.instance.get(
    ApiConstants.expenses,
    queryParameters: {'branchId': profile!.branchId!, 'limit': '100'},
  );
  final data = response.data as Map<String, dynamic>;
  final rows = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
  return rows.where((e) => (e['created_at'] as String? ?? '').startsWith(today)).toList();
});

final dashboardKotsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.kots,
    queryParameters: {'branchId': profile!.branchId!, 'status': 'pending', 'limit': '100'},
  );
  final rows = response.data as List<dynamic>;
  return List<Map<String, dynamic>>.from(rows);
});

final dashboardCreditProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.credits,
    queryParameters: {'branchId': profile!.branchId!, 'limit': '100'},
  );
  final data = response.data as Map<String, dynamic>;
  final rows = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
  return rows.where((c) => c['status'] != 'paid').toList();
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(authNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (profile) {
          if (profile == null) return const SizedBox();
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                backgroundColor: AppColors.surface,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Good ${_greeting()}, ${profile.fullName.split(' ').first}!',
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text(DateFormat('EEEE, dd MMM yyyy').format(DateTime.now()),
                        style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
                actions: [
                  Consumer(builder: (context, ref, _) {
                    final unread = ref.watch(unreadNotificationCountProvider);
                    return IconButton(
                      tooltip: 'Notifications',
                      icon: Badge(
                        isLabelVisible: unread > 0,
                        label: Text(unread > 99 ? '99+' : '$unread'),
                        backgroundColor: AppColors.error,
                        textColor: Colors.white,
                        child: const Icon(Icons.notifications_outlined, color: AppColors.textSecondary),
                      ),
                      onPressed: () => context.go('/notifications'),
                    );
                  }),
                  const SizedBox(width: 8),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Manager dashboard
                      if (profile.isBranchManager) ...[
                        const _SectionHeader('Today\'s Overview'),
                        const SizedBox(height: 16),
                        const _ManagerStatsGrid(),
                        const SizedBox(height: 24),
                        const _SectionHeader('Live Orders'),
                        const SizedBox(height: 16),
                        const _LiveOrdersSection(),
                        const SizedBox(height: 24),
                        const _SectionHeader('Quick Actions'),
                        const SizedBox(height: 16),
                        _QuickActionsGrid(role: profile.role),
                      ]
                      // Cashier dashboard
                      else if (profile.isCashier) ...[
                        const _SectionHeader('Overview'),
                        const SizedBox(height: 16),
                        const _CashierStatsGrid(),
                        const SizedBox(height: 24),
                        const _SectionHeader('Live Orders & Bill Requests'),
                        const SizedBox(height: 16),
                        const _LiveOrdersSection(showBillAction: true),
                        const SizedBox(height: 24),
                        const _SectionHeader('Quick Actions'),
                        const SizedBox(height: 16),
                        _QuickActionsGrid(role: profile.role),
                      ]
                      // Waiter dashboard
                      else if (profile.isWaiter) ...[
                        const _SectionHeader('My Tables'),
                        const SizedBox(height: 16),
                        _WaiterQuickNav(),
                      ]
                      // Kitchen dashboard
                      else if (profile.isKitchen) ...[
                        const _SectionHeader('Kitchen Orders'),
                        const SizedBox(height: 16),
                        _KitchenQuickNav(),
                      ]
                      else ...[
                        const _SectionHeader('Welcome'),
                        const SizedBox(height: 16),
                        _QuickActionsGrid(role: profile.role),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary));
  }
}

class _ManagerStatsGrid extends ConsumerWidget {
  const _ManagerStatsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billsAsync = ref.watch(dashboardBillsProvider);
    final expensesAsync = ref.watch(dashboardExpensesProvider);
    final kotsAsync = ref.watch(dashboardKotsProvider);
    final creditAsync = ref.watch(dashboardCreditProvider);

    final fmt = NumberFormat('#,##0.00');

    double todaySales = 0;
    double expenses = 0;
    int pendingKots = 0;
    double creditOutstanding = 0;

    billsAsync.whenData((bills) {
      todaySales = bills
          .where((b) => b['payment_status'] == 'paid')
          .fold(0.0, (s, b) => s + ((b['total_amount'] as num?)?.toDouble() ?? 0));
    });
    expensesAsync.whenData((expList) {
      expenses = expList.fold(0.0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
    });
    kotsAsync.whenData((kots) {
      pendingKots = kots.length;
    });
    creditAsync.whenData((credits) {
      creditOutstanding = credits.fold(0.0, (s, c) =>
          s + (((c['credit_amount'] as num?)?.toDouble() ?? 0) -
               ((c['paid_amount'] as num?)?.toDouble() ?? 0)));
    });

    final isLoading = billsAsync.isLoading || expensesAsync.isLoading ||
        kotsAsync.isLoading || creditAsync.isLoading;

    return AnimatedOpacity(
      opacity: isLoading ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Builder(
        builder: (context) {
          final cols = context.responsiveValue<int>(mobile: 2, tablet: 2, desktop: 4);
          final ratio = context.responsiveValue<double>(mobile: 1.6, tablet: 1.8, desktop: 2.2);
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: ratio,
            children: [
              _StatCard('Today\'s Sales', 'NPR ${fmt.format(todaySales)}', Icons.trending_up_rounded, AppColors.success),
              _StatCard('Today\'s Expenses', 'NPR ${fmt.format(expenses)}', Icons.money_off_rounded, AppColors.error),
              _StatCard('Pending KOTs', pendingKots.toString(), Icons.receipt_outlined, AppColors.warning),
              _StatCard('Credit Outstanding', 'NPR ${fmt.format(creditOutstanding)}', Icons.account_balance_wallet_rounded, AppColors.info),
            ].animate(interval: 80.ms).fadeIn().slideY(begin: 0.2),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 18),
          ),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value,
                        maxLines: 1,
                        style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.2)),
                  ),
                ),
                const SizedBox(height: 1),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                        fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  final String role;
  const _QuickActionsGrid({required this.role});

  @override
  Widget build(BuildContext context) {
    final actions = _getActions(role, context);
    final maxExtent = context.responsiveValue<double>(
      mobile: 140,
      tablet: 160,
      desktop: 180,
    );
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: actions.length,
      itemBuilder: (context, i) => _ActionCard(
        icon: actions[i]['icon'] as IconData,
        label: actions[i]['label'] as String,
        color: actions[i]['color'] as Color,
        onTap: actions[i]['onTap'] as VoidCallback,
      ),
    );
  }

  List<Map<String, dynamic>> _getActions(String role, BuildContext context) {
    switch (role) {
      case AppConstants.roleBranchManager:
        return [
          {'icon': Icons.table_restaurant_rounded, 'label': 'Tables', 'color': AppColors.success, 'onTap': () => context.go('/tables')},
          {'icon': Icons.receipt_long_rounded, 'label': 'Payments', 'color': AppColors.info, 'onTap': () => context.go('/payment-history')},
          {'icon': Icons.restaurant_menu_rounded, 'label': 'Menu', 'color': AppColors.primary, 'onTap': () => context.go('/menu')},
          {'icon': Icons.inventory_2_rounded, 'label': 'Inventory', 'color': AppColors.roleInventory, 'onTap': () => context.go('/inventory')},
          {'icon': Icons.bar_chart_rounded, 'label': 'Reports', 'color': AppColors.warning, 'onTap': () => context.go('/reports')},
          {'icon': Icons.people_rounded, 'label': 'Staff', 'color': AppColors.roleKitchen, 'onTap': () => context.go('/staff')},
          {'icon': Icons.account_balance_wallet_rounded, 'label': 'Credit', 'color': AppColors.error, 'onTap': () => context.go('/credit')},
        ];
      case AppConstants.roleCashier:
        return [
          {'icon': Icons.table_restaurant_rounded, 'label': 'Tables', 'color': AppColors.success, 'onTap': () => context.go('/tables')},
          {'icon': Icons.point_of_sale_rounded, 'label': 'Cashier', 'color': AppColors.primary, 'onTap': () => context.go('/cashier')},
          {'icon': Icons.receipt_long_rounded, 'label': 'Payments', 'color': AppColors.info, 'onTap': () => context.go('/payment-history')},
          {'icon': Icons.event_seat_rounded, 'label': 'Reservations', 'color': AppColors.roleCashier, 'onTap': () => context.go('/reservations')},
          {'icon': Icons.people_rounded, 'label': 'Customers', 'color': AppColors.roleManager, 'onTap': () => context.go('/customers')},
          {'icon': Icons.account_balance_wallet_rounded, 'label': 'Credit', 'color': AppColors.error, 'onTap': () => context.go('/credit')},
        ];
      default:
        return [
          {'icon': Icons.table_restaurant_rounded, 'label': 'Tables', 'color': AppColors.success, 'onTap': () => context.go('/tables')},
          {'icon': Icons.kitchen_rounded, 'label': 'Kitchen', 'color': AppColors.roleKitchen, 'onTap': () => context.go('/kitchen')},
        ];
    }
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 10),
            Text(label,
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _WaiterQuickNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.table_restaurant_rounded),
          label: const Text('View Tables & Take Orders'),
          onPressed: () => context.go('/tables'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.fingerprint_rounded),
          label: const Text('Mark Attendance'),
          onPressed: () => context.go('/attendance'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
        ),
      ],
    );
  }
}

class _KitchenQuickNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.kitchen_rounded),
      label: const Text('Open Kitchen Display'),
      onPressed: () => context.go('/kitchen'),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
      ),
    );
  }
}

// ── Cashier Overview Widgets ──

final dashboardSessionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.sessions,
    queryParameters: {'branchId': profile!.branchId!, 'status': 'open'},
  );
  final rows = response.data as List<dynamic>;
  return List<Map<String, dynamic>>.from(rows);
});

class _CashierStatsGrid extends ConsumerWidget {
  const _CashierStatsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billsAsync = ref.watch(dashboardBillsProvider);
    final tablesAsync = ref.watch(tablesStreamProvider);
    
    final fmt = NumberFormat('#,##0.00');
    double todaySales = 0;
    int occupiedTables = 0;
    int billRequests = 0;

    billsAsync.whenData((bills) {
      todaySales = bills
          .where((b) => b['payment_status'] == 'paid')
          .fold(0.0, (s, b) => s + ((b['total_amount'] as num?)?.toDouble() ?? 0));
    });

    tablesAsync.whenData((tables) {
      occupiedTables = tables.where((t) => t.isOccupied).length;
      billRequests = tables.where((t) => t.billRequested).length;
    });

    final isLoading = billsAsync.isLoading || tablesAsync.isLoading;

    return AnimatedOpacity(
      opacity: isLoading ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Builder(
        builder: (context) {
          final cols = context.responsiveValue<int>(mobile: 1, tablet: 3, desktop: 3);
          final ratio = context.responsiveValue<double>(mobile: 3.0, tablet: 2.2, desktop: 2.4);
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: ratio,
            children: [
              _StatCard('Today\'s Sales', 'NPR ${fmt.format(todaySales)}', Icons.point_of_sale_rounded, AppColors.success),
              _StatCard('Active Tables', occupiedTables.toString(), Icons.table_restaurant_rounded, AppColors.info),
              _StatCard(
                'Bill Requests',
                billRequests.toString(),
                Icons.receipt_long_rounded,
                billRequests > 0 ? AppColors.warning : AppColors.textHint,
              ),
            ].animate(interval: 80.ms).fadeIn().slideY(begin: 0.2),
          );
        },
      ),
    );
  }
}

/// Shows every occupied / ready-for-billing table with its waiter, live
/// KOT status breakdown (pending/preparing/ready), running subtotal, and
/// elapsed time — so managers and cashiers can see at a glance which
/// orders are in flight and not yet billed. Updates live via the sockets
/// wired through [tablesStreamProvider], [dashboardSessionsProvider] and
/// [kitchenKotsProvider] (all invalidated by realtimeSyncProvider).
class _LiveOrdersSection extends ConsumerWidget {
  final bool showBillAction;
  const _LiveOrdersSection({this.showBillAction = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablesAsync = ref.watch(tablesStreamProvider);
    final sessionsAsync = ref.watch(dashboardSessionsProvider);
    final kotsAsync = ref.watch(kitchenKotsProvider);
    final fmt = NumberFormat('#,##0');

    return tablesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Text('Error: $e', style: const TextStyle(color: AppColors.error)),
      data: (tables) {
        final live = tables.where((t) => t.isOccupied || t.isReadyForBilling).toList();
        if (live.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textHint),
                const SizedBox(height: 12),
                Text('No live orders right now',
                    style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14)),
              ],
            ),
          );
        }

        final sessions = sessionsAsync.value ?? [];
        final kots = kotsAsync.value ?? [];

        return Column(
          children: live.map((table) {
            final session = sessions.where((s) => s['id'] == table.currentSessionId).firstOrNull;
            final tableKots = kots.where((k) => k.tableId == table.id).toList();
            final pending = tableKots.where((k) => k.isPending).length;
            final preparing = tableKots.where((k) => k.isPreparing).length;
            final ready = tableKots.where((k) => k.isReady).length;
            final subtotal = (session?['total_amount'] as num?)?.toDouble() ?? 0.0;
            final waiterName = session?['waiter_name'] as String? ?? '—';
            final openedAt = session?['opened_at'] != null
                ? DateTime.tryParse(session!['opened_at'] as String)
                : null;
            final elapsedMins = openedAt != null ? DateTime.now().difference(openedAt).inMinutes : null;
            final isBillRequested = table.billRequested;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isBillRequested ? AppColors.warning : AppColors.border,
                  width: isBillRequested ? 1.5 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(table.tableNumber,
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Table ${table.tableNumber}',
                                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            if (isBillRequested) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('BILL REQUESTED',
                                    style: GoogleFonts.outfit(fontSize: 9, color: AppColors.warning, fontWeight: FontWeight.w700)),
                              ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(duration: 600.ms),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Waiter: $waiterName${elapsedMins != null ? ' • ${elapsedMins}m ago' : ''}',
                          style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (pending > 0) _kotChip('$pending Pending', AppColors.warning),
                            if (preparing > 0) _kotChip('$preparing Preparing', AppColors.info),
                            if (ready > 0) _kotChip('$ready Ready', AppColors.success),
                            if (pending == 0 && preparing == 0 && ready == 0)
                              _kotChip('No active KOTs', AppColors.textHint),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('NPR ${fmt.format(subtotal)}',
                          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary)),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 28,
                        child: showBillAction
                            ? ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isBillRequested ? AppColors.warning : AppColors.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => context.go(
                                    '/cashier?sessionId=${table.currentSessionId ?? ''}&tableId=${table.id}'),
                                child: Text(
                                  isBillRequested ? 'PRINT & SETTLE' : 'BILL / SETTLE',
                                  style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                              )
                            : OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => context.go('/tables'),
                                child: Text('VIEW',
                                    style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 250.ms);
          }).toList(),
        );
      },
    );
  }

  Widget _kotChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: GoogleFonts.outfit(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
      );
}
