import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final loyaltyCustomersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.customers,
    queryParameters: {'branchId': profile!.branchId!},
  );
  final data = response.data as Map<String, dynamic>;
  final list = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
  list.sort((a, b) => ((b['loyalty_points'] as num?) ?? 0)
      .compareTo((a['loyalty_points'] as num?) ?? 0));
  return list;
});

final loyaltyHistoryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, customerId) async {
  final response = await ApiClient.instance.get(ApiConstants.loyaltyHistory(customerId));
  final list = List<Map<String, dynamic>>.from(response.data as List? ?? []);
  return list.take(30).toList();
});

class LoyaltyScreen extends ConsumerStatefulWidget {
  const LoyaltyScreen({super.key});
  @override
  ConsumerState<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends ConsumerState<LoyaltyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0');
    final customersAsync = ref.watch(loyaltyCustomersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.star,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Loyalty Program',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppColors.textPrimary)),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [Tab(text: 'Members'), Tab(text: 'Transactions')],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.card_giftcard_rounded, size: 18),
            label: const Text('Redeem Points'),
            onPressed: () => _showRedeemDialog(context),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          // ── Members Tab ──
          Column(
            children: [
              _ProgramSummaryBanner(customersAsync: customersAsync),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search by name or phone...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                ),
              ),
              Expanded(
                child: customersAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (customers) {
                    final filtered = _search.isEmpty
                        ? customers
                        : customers.where((c) {
                            final name = (c['name'] as String? ?? '').toLowerCase();
                            final phone = (c['phone'] as String? ?? '').toLowerCase();
                            return name.contains(_search) || phone.contains(_search);
                          }).toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.stars_rounded, size: 64, color: AppColors.textHint),
                            const SizedBox(height: 16),
                            Text('No loyalty members found',
                                style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                          ],
                        ),
                      );
                    }

                    return ResponsiveContent(child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final c = filtered[i];
                        final points = (c['loyalty_points'] as num?)?.toInt() ?? 0;
                        final tier = _tier(points);
                        return _LoyaltyMemberCard(
                          customer: c,
                          points: points,
                          tier: tier,
                          fmt: fmt,
                          onViewHistory: () => _showHistory(context, c),
                          onAwardPoints: () => _showAwardDialog(context, c),
                        ).animate().fadeIn(delay: Duration(milliseconds: i * 30));
                      },
                    ));
                  },
                ),
              ),
            ],
          ),

          // ── Transactions Tab ──
          _RecentTransactionsTab(),
        ],
      ),
    );
  }

  String _tier(int points) {
    if (points >= 5000) return '🏆 Gold';
    if (points >= 2000) return '🥈 Silver';
    if (points >= 500) return '🥉 Bronze';
    return '⭐ Basic';
  }

  void _showHistory(BuildContext context, Map<String, dynamic> customer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CustomerHistorySheet(customer: customer),
    );
  }

  void _showAwardDialog(BuildContext context, Map<String, dynamic> customer) {
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Award Points — ${customer['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rule: NPR 100 = 1 Point',
              style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Purchase Amount (NPR)',
                prefixText: 'NPR ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text) ?? 0;
              final earned = (amount / 100).floor();
              if (earned <= 0) return;
              await _earnPoints(customer['id'] as String, earned, amount);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$earned points awarded to ${customer['name']}!'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            child: const Text('Award Points'),
          ),
        ],
      ),
    );
  }

  void _showRedeemDialog(BuildContext context) {
    final phoneCtrl = TextEditingController();
    final pointsCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redeem Loyalty Points'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Customer Phone'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pointsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Points to Redeem'),
            ),
            const SizedBox(height: 8),
            Text('100 Points = NPR 100 discount',
                style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final phone = phoneCtrl.text.trim();
              final points = int.tryParse(pointsCtrl.text) ?? 0;
              if (phone.isEmpty || points <= 0) return;

              Map<String, dynamic> data;
              try {
                final response = await ApiClient.instance
                    .get(ApiConstants.customerByPhone(phone));
                data = response.data as Map<String, dynamic>;
              } catch (_) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Customer not found')),
                  );
                }
                return;
              }

              final currentPoints = (data['loyalty_points'] as num?)?.toInt() ?? 0;
              if (points > currentPoints) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text('Insufficient points. Available: $currentPoints'),
                        backgroundColor: AppColors.error),
                  );
                }
                return;
              }

              await _redeemPoints(data['id'] as String, points);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$points points redeemed! Discount: NPR $points'),
                    backgroundColor: AppColors.success,
                  ),
                );
                // Stream auto-updates; no need to invalidate
              }
            },
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
  }

  Future<void> _earnPoints(String customerId, int points, double purchaseAmount) async {
    await ApiClient.instance.post(
      ApiConstants.earnPoints(customerId),
      data: {'points': points, 'purchaseAmount': purchaseAmount},
    );
    ref.invalidate(loyaltyCustomersProvider);
    ref.invalidate(loyaltyHistoryProvider(customerId));
  }

  Future<void> _redeemPoints(String customerId, int points) async {
    await ApiClient.instance.post(
      ApiConstants.redeemPoints(customerId),
      data: {'points': points},
    );
    ref.invalidate(loyaltyCustomersProvider);
    ref.invalidate(loyaltyHistoryProvider(customerId));
  }
}

// ── Summary Banner ──
class _ProgramSummaryBanner extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> customersAsync;
  const _ProgramSummaryBanner({required this.customersAsync});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: customersAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => const SizedBox(),
        data: (customers) {
          final totalMembers = customers.length;
          final totalPoints = customers.fold<int>(
              0, (s, c) => s + ((c['loyalty_points'] as num?)?.toInt() ?? 0));
          final gold = customers.where((c) =>
              ((c['loyalty_points'] as num?)?.toInt() ?? 0) >= 5000).length;

          return Row(
            children: [
              const Icon(Icons.stars_rounded, color: Colors.white, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Loyalty Program',
                        style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    Text('$totalMembers members • $gold Gold tier',
                        style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.85))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(fmt.format(totalPoints),
                      style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  Text('total points',
                      style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.85))),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Member Card ──
class _LoyaltyMemberCard extends StatelessWidget {
  final Map<String, dynamic> customer;
  final int points;
  final String tier;
  final NumberFormat fmt;
  final VoidCallback onViewHistory;
  final VoidCallback onAwardPoints;

  const _LoyaltyMemberCard({
    required this.customer,
    required this.points,
    required this.tier,
    required this.fmt,
    required this.onViewHistory,
    required this.onAwardPoints,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              (customer['name'] as String? ?? 'G').substring(0, 1).toUpperCase(),
              style: GoogleFonts.outfit(
                  fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customer['name'] as String? ?? 'Unknown',
                    style: GoogleFonts.outfit(
                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(customer['phone'] as String? ?? '—',
                    style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(tier,
                    style: GoogleFonts.outfit(fontSize: 12, color: AppColors.primary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmt.format(points),
                  style: GoogleFonts.outfit(
                      fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
              Text('pts',
                  style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Row(
                children: [
                  GestureDetector(
                    onTap: onViewHistory,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('History',
                          style: GoogleFonts.outfit(
                              fontSize: 10, color: AppColors.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onAwardPoints,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('Award',
                          style: GoogleFonts.outfit(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Customer History Sheet ──
class _CustomerHistorySheet extends ConsumerWidget {
  final Map<String, dynamic> customer;
  const _CustomerHistorySheet({required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(loyaltyHistoryProvider(customer['id'] as String));
    final fmt = NumberFormat('#,##0');
    final points = (customer['loyalty_points'] as num?)?.toInt() ?? 0;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Column(
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customer['name'] as String? ?? 'Customer',
                          style: GoogleFonts.outfit(
                              fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      Text('${fmt.format(points)} points available',
                          style: GoogleFonts.outfit(
                              fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: historyAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (txns) {
                if (txns.isEmpty) {
                  return Center(
                    child: Text('No transaction history',
                        style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                  );
                }
                return ListView.builder(
                  controller: ctrl,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: txns.length,
                  itemBuilder: (_, i) {
                    final t = txns[i];
                    final isEarn = t['type'] == 'earn';
                    final pts = (t['points'] as num?)?.toInt() ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: (isEarn ? AppColors.success : AppColors.warning)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isEarn ? Icons.add_circle_rounded : Icons.remove_circle_rounded,
                              color: isEarn ? AppColors.success : AppColors.warning,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t['notes'] as String? ?? (isEarn ? 'Points earned' : 'Points redeemed'),
                                    style: GoogleFonts.outfit(
                                        fontSize: 13, color: AppColors.textPrimary)),
                                Text(
                                    t['created_at'] != null
                                        ? DateFormat('dd MMM yyyy').format(
                                            DateTime.parse(t['created_at'] as String))
                                        : '',
                                    style: GoogleFonts.outfit(
                                        fontSize: 11, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          Text(
                            '${isEarn ? '+' : '-'}$pts pts',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isEarn ? AppColors.success : AppColors.warning,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recent Transactions Tab ──
final _recentLoyaltyTxnsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.loyaltyRecent,
    queryParameters: {'branchId': profile!.branchId!, 'limit': '50'},
  );
  return List<Map<String, dynamic>>.from(response.data as List? ?? []);
});

class _RecentTransactionsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnsAsync = ref.watch(_recentLoyaltyTxnsProvider);
    return txnsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (txns) {
        if (txns.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.history_rounded, size: 64, color: AppColors.textHint),
                const SizedBox(height: 16),
                Text('No loyalty transactions yet',
                    style: GoogleFonts.outfit(color: AppColors.textSecondary)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: txns.length,
          itemBuilder: (_, i) {
            final t = txns[i];
            final isEarn = t['type'] == 'earn';
            final pts = (t['points'] as num?)?.toInt() ?? 0;
            // customer name from joined data or fallback
            final customerName =
                (t['customer'] as Map<String, dynamic>?)?['name'] as String?
                ?? t['customer_name'] as String?
                ?? '—';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border)),
              child: Row(
                children: [
                  Icon(
                    isEarn ? Icons.add_circle_rounded : Icons.redeem_rounded,
                    color: isEarn ? AppColors.success : AppColors.warning,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(customerName,
                            style: GoogleFonts.outfit(
                                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        Text(isEarn ? 'Points Earned' : 'Points Redeemed',
                            style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Text(
                    '${isEarn ? '+' : '-'}$pts',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isEarn ? AppColors.success : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: Duration(milliseconds: i * 20));
          },
        );
      },
    );
  }
}
