import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../tables/presentation/providers/tables_provider.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../payment_history/presentation/screens/payment_history_screen.dart';
import '../../../branches/presentation/providers/branch_provider.dart';
import '../../../../core/widgets/thermal_receipt.dart';

// Session billing data provider (KOTs + aggregated items for this session)
// Public (no leading underscore) so realtime_sync.dart can invalidate it
// when a KOT is added/updated on this session from another device.
final sessionBillingProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, sessionId) async {
  if (sessionId.isEmpty) return {'items': [], 'subtotal': 0.0, 'kots': []};

  final response =
      await ApiClient.instance.get(ApiConstants.kotsBySession(sessionId));
  final kots = (response.data as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((k) => k['status'] != 'cancelled')
      .toList();

  final List<Map<String, dynamic>> allItems = [];
  for (final kot in kots) {
    final items = (kot['items'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((i) => i['status'] != 'cancelled');
    allItems.addAll(items);
  }

  final Map<String, Map<String, dynamic>> aggregated = {};
  for (final item in allItems) {
    final key = item['menu_item_id'] as String;
    if (aggregated.containsKey(key)) {
      aggregated[key]!['quantity'] =
          (aggregated[key]!['quantity'] as int) + (item['quantity'] as int);
    } else {
      aggregated[key] = {
        'menu_item_id': item['menu_item_id'],
        'menu_item_name': item['menu_item_name'] ?? item['name'],
        'quantity': item['quantity'],
        'unit_price': item['unit_price'],
      };
    }
  }

  double subtotal = 0;
  for (final item in aggregated.values) {
    subtotal += ((item['unit_price'] as num?)?.toDouble() ?? 0) *
        (item['quantity'] as int);
  }

  return {
    'items': aggregated.values.toList(),
    'subtotal': subtotal,
    'kots': kots,
  };
});

// Design constants local to the cashier workspace — kept in one place so the
// whole screen reads as one considered system rather than ad-hoc numbers.
class _CashierUi {
  _CashierUi._();
  static const double cardRadius = 20;
  static const Color canvas = Color(0xFFF1F2F6);
  static const Color subtleFill = Color(0xFFF7F8FA);
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x05121212), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0C121212), blurRadius: 24, offset: Offset(0, 10)),
  ];
  static const List<BoxShadow> heroShadow = [
    BoxShadow(color: Color(0x33C0392B), blurRadius: 24, offset: Offset(0, 10)),
  ];
  static List<BoxShadow> tintShadow(Color c) => [
        BoxShadow(
            color: c.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 5)),
      ];
}

class CashierScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String tableId;

  const CashierScreen(
      {super.key, required this.sessionId, required this.tableId});

  @override
  ConsumerState<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends ConsumerState<CashierScreen>
    with SingleTickerProviderStateMixin {
  String _paymentMethod = AppConstants.paymentCash;
  double _discount = 0;
  bool _applyServiceCharge = false;
  final bool _applyVat = false;
  final _amountCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _tableSearchCtrl = TextEditingController();
  String _tableSearch = '';
  String _tableFilter = 'all'; // all | billReady
  bool _processing = false;
  String? _customerName;
  String? _customerPhone;

  String? _selectedSessionId;
  String? _selectedTableId;

  late AnimationController _pulseController;

  final fmt = NumberFormat('#,##0.00');
  final fmt0 = NumberFormat('#,##0');

  // Payment method configs
  static const _paymentMethods = [
    {
      'label': 'Cash',
      'value': 'cash',
      'icon': Icons.payments_rounded,
      'color': Color(0xFF27AE60)
    },
    {
      'label': 'Card',
      'value': 'card',
      'icon': Icons.credit_card_rounded,
      'color': Color(0xFF2980B9)
    },
    {
      'label': 'eSewa',
      'value': 'esewa',
      'icon': Icons.phone_android_rounded,
      'color': Color(0xFF60BB46),
      'asset': 'assets/icons/esewa.png'
    },
    {
      'label': 'Khalti',
      'value': 'khalti',
      'icon': Icons.account_balance_wallet_rounded,
      'color': Color(0xFF5C2D91),
      'asset': 'assets/icons/khalti.png'
    },
    {
      'label': 'FonePay',
      'value': 'fonepay',
      'icon': Icons.qr_code_scanner_rounded,
      'color': Color(0xFFE67E22),
      'asset': 'assets/icons/fonepay.png'
    },
    {
      'label': 'Credit',
      'value': 'credit',
      'icon': Icons.receipt_long_rounded,
      'color': Color(0xFFF39C12)
    },
  ];

  @override
  void initState() {
    super.initState();
    _selectedSessionId = widget.sessionId.isEmpty ? null : widget.sessionId;
    _selectedTableId = widget.tableId.isEmpty ? null : widget.tableId;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant CashierScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessionId != oldWidget.sessionId ||
        widget.tableId != oldWidget.tableId) {
      if (widget.sessionId.isNotEmpty) {
        _selectedSessionId = widget.sessionId;
        _selectedTableId = widget.tableId;
      }
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _discountCtrl.dispose();
    _tableSearchCtrl.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).value;
    final tablesAsync = ref.watch(tablesStreamProvider);
    // Pre-warm branch info (name/address/phone) so it's already loaded by
    // the time a receipt or KOT ticket needs to print it.
    ref.watch(currentBranchProvider);
    final isMobile = context.isMobile;

    final Widget workspace =
        _selectedSessionId == null || _selectedSessionId!.isEmpty
            ? _noSessionView(context, isMobile: isMobile)
            : ref.watch(sessionBillingProvider(_selectedSessionId!)).when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (data) =>
                      _buildBillingView(data, profile, isMobile: isMobile),
                );

    if (isMobile) {
      return Scaffold(
        backgroundColor: _CashierUi.canvas,
        appBar: _buildAppBar(tablesAsync, showDrawerIcon: true),
        drawer: Drawer(
          width: 300,
          child: SafeArea(child: _buildTablesSidebar(tablesAsync)),
        ),
        body: workspace,
      );
    }

    return Scaffold(
      backgroundColor: _CashierUi.canvas,
      appBar: _buildAppBar(tablesAsync),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTablesSidebar(tablesAsync),
          Expanded(child: workspace),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  APP BAR — simple heading + live clock, matching the
  //  pattern used across the other role screens.
  // ─────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(AsyncValue tablesAsync,
      {bool showDrawerIcon = false}) {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 72,
      automaticallyImplyLeading: false,
      leading: showDrawerIcon
          ? Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded,
                    color: AppColors.textPrimary),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                tooltip: 'Select Table',
              ),
            )
          : null,
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
            child: const Icon(Icons.point_of_sale,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Cashier Station',
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppColors.textPrimary)),
              Text(
                DateFormat('EEEE, dd MMM yyyy · HH:mm').format(DateTime.now()),
                style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
      actions: [
        tablesAsync.when(
          loading: () => const SizedBox(),
          error: (_, __) => const SizedBox(),
          data: (tables) {
            final occupied = (tables as List)
                .where((t) => t.isOccupied || t.isReadyForBilling)
                .length;
            final billReady = tables.where((t) => t.billRequested).length;
            return Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  _AppBarStatPill(
                    icon: Icons.table_bar_rounded,
                    label: '$occupied active',
                    color: AppColors.info,
                  ),
                  if (billReady > 0) ...[
                    const SizedBox(width: 8),
                    _AppBarStatPill(
                      icon: Icons.notifications_active_rounded,
                      label: '$billReady awaiting',
                      color: AppColors.warning,
                      pulse: true,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.border),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  LEFT SIDEBAR
  // ─────────────────────────────────────────────────────────
  Widget _buildTablesSidebar(AsyncValue tablesAsync) {
    return Container(
      width: 280,
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.table_restaurant_rounded,
                      color: AppColors.primary, size: 16),
                ),
                const SizedBox(width: 10),
                Text(
                  'Active Tables',
                  style: GoogleFonts.outfit(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.1,
                  ),
                ),
                const Spacer(),
                tablesAsync.when(
                  loading: () => const SizedBox(),
                  error: (_, __) => const SizedBox(),
                  data: (tables) {
                    final count = (tables as List)
                        .where((t) => t.isOccupied || t.isReadyForBilling)
                        .length;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$count',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: TextField(
              controller: _tableSearchCtrl,
              onChanged: (v) =>
                  setState(() => _tableSearch = v.trim().toLowerCase()),
              style: GoogleFonts.outfit(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search table or section',
                hintStyle: GoogleFonts.outfit(
                    fontSize: 12.5, color: AppColors.textHint),
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                filled: true,
                fillColor: _CashierUi.subtleFill,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.4),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: tablesAsync.when(
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
              data: (tables) {
                final all = (tables as List)
                    .where((t) => t.isOccupied || t.isReadyForBilling);
                final billReadyCount = all.where((t) => t.billRequested).length;
                return Row(
                  children: [
                    Expanded(
                      child: _FilterChip(
                        label: 'All',
                        count: all.length,
                        selected: _tableFilter == 'all',
                        color: AppColors.info,
                        onTap: () => setState(() => _tableFilter = 'all'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FilterChip(
                        label: 'Awaiting Bill',
                        count: billReadyCount,
                        selected: _tableFilter == 'billReady',
                        color: AppColors.warning,
                        onTap: () => setState(() => _tableFilter = 'billReady'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Container(height: 1, color: AppColors.border),
          Expanded(
            child: tablesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (tables) {
                var occupied = (tables as List)
                    .where((t) => t.isOccupied || t.isReadyForBilling)
                    .toList();
                if (_tableFilter == 'billReady') {
                  occupied = occupied.where((t) => t.billRequested).toList();
                }
                if (_tableSearch.isNotEmpty) {
                  occupied = occupied
                      .where((t) =>
                          '${t.tableNumber}'
                              .toLowerCase()
                              .contains(_tableSearch) ||
                          (t.section as String)
                              .toLowerCase()
                              .contains(_tableSearch))
                      .toList();
                }
                if (occupied.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _tableSearch.isEmpty
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.search_off_rounded,
                              size: 32,
                              color: AppColors.success,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _tableSearch.isEmpty
                                ? 'All tables free'
                                : 'No matching tables',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _tableSearch.isEmpty
                                ? 'No occupied tables right now'
                                : 'Try a different search term',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                                fontSize: 11, color: AppColors.textHint),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  itemCount: occupied.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final t = occupied[i];
                    final isSelected = t.id == _selectedTableId;
                    final isReq = t.billRequested;

                    final accent = isSelected
                        ? AppColors.primary
                        : (isReq ? AppColors.warning : AppColors.info);

                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedTableId = t.id;
                          _selectedSessionId = t.currentSessionId;
                        });
                        if (context.isMobile) Navigator.of(ctx).pop();
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? const LinearGradient(
                                  colors: [
                                    AppColors.gradientStart,
                                    AppColors.gradientEnd
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: isSelected
                              ? null
                              : (isReq
                                  ? AppColors.warning.withValues(alpha: 0.06)
                                  : AppColors.surface),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? Colors.transparent
                                : (isReq
                                    ? AppColors.warning.withValues(alpha: 0.3)
                                    : AppColors.border),
                          ),
                          boxShadow: isSelected
                              ? _CashierUi.tintShadow(AppColors.primary)
                              : null,
                        ),
                        child: Row(
                          children: [
                            // Accent bar
                            Container(
                              width: 4,
                              height: 54,
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white : accent,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(14),
                                  bottomLeft: Radius.circular(14),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 11, vertical: 10),
                                child: Row(
                                  children: [
                                    // Table icon
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white
                                                .withValues(alpha: 0.18)
                                            : accent.withValues(alpha: 0.13),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${t.tableNumber}',
                                        style: GoogleFonts.outfit(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: isSelected
                                              ? Colors.white
                                              : accent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 11),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Table ${t.tableNumber}',
                                            style: GoogleFonts.outfit(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: isSelected
                                                  ? Colors.white
                                                  : AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Icon(Icons.place_rounded,
                                                  size: 10,
                                                  color: isSelected
                                                      ? Colors.white.withValues(
                                                          alpha: 0.7)
                                                      : AppColors.textHint),
                                              const SizedBox(width: 2),
                                              Flexible(
                                                child: Text(
                                                  t.section,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GoogleFonts.outfit(
                                                      fontSize: 10.5,
                                                      color: isSelected
                                                          ? Colors.white
                                                              .withValues(
                                                                  alpha: 0.7)
                                                          : AppColors.textHint,
                                                      fontWeight:
                                                          FontWeight.w500),
                                                ),
                                              ),
                                              if (t.capacity > 0) ...[
                                                const SizedBox(width: 6),
                                                Icon(Icons.people_alt_rounded,
                                                    size: 10,
                                                    color: isSelected
                                                        ? Colors.white
                                                            .withValues(
                                                                alpha: 0.7)
                                                        : AppColors.textHint),
                                                const SizedBox(width: 2),
                                                Text(
                                                  '${t.capacity}',
                                                  style: GoogleFonts.outfit(
                                                      fontSize: 10.5,
                                                      color: isSelected
                                                          ? Colors.white
                                                              .withValues(
                                                                  alpha: 0.7)
                                                          : AppColors.textHint,
                                                      fontWeight:
                                                          FontWeight.w500),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isReq)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.warning
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                                Icons.receipt_long_rounded,
                                                size: 10,
                                                color: AppColors.warning),
                                            const SizedBox(width: 3),
                                            Text(
                                              'BILL',
                                              style: GoogleFonts.outfit(
                                                fontSize: 8.5,
                                                color: AppColors.warning,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                          .animate(
                                              onPlay: (c) =>
                                                  c.repeat(reverse: true))
                                          .fade(duration: 600.ms, begin: 0.55)
                                    else if (isSelected)
                                      const Icon(Icons.chevron_right_rounded,
                                          size: 18, color: Colors.white),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
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

  // ─────────────────────────────────────────────────────────
  //  NO SESSION VIEW
  // ─────────────────────────────────────────────────────────
  Widget _noSessionView(BuildContext context, {bool isMobile = false}) {
    final billsAsync = ref.watch(dashboardBillsProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            billsAsync.when(
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
              data: (bills) {
                final revenue = bills.fold<double>(
                    0,
                    (sum, b) =>
                        sum + ((b['total_amount'] as num?)?.toDouble() ?? 0));
                return Padding(
                  padding: const EdgeInsets.only(bottom: 26),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TodayStatCard(
                        icon: Icons.payments_rounded,
                        label: "Today's Sales",
                        value: 'NPR ${fmt0.format(revenue)}',
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 12),
                      _TodayStatCard(
                        icon: Icons.receipt_long_rounded,
                        label: 'Bills Settled',
                        value: '${bills.length}',
                        color: AppColors.info,
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.15);
              },
            ),
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.10),
                    AppColors.primary.withValues(alpha: 0.03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.point_of_sale_rounded,
                size: 52,
                color: AppColors.primary,
              ),
            ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 22),
            Text(
              'Ready to bill',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.3),
            const SizedBox(height: 8),
            Text(
              isMobile
                  ? 'Tap the ☰ menu icon to select an active table.'
                  : 'Choose an occupied table from the sidebar\nto load the billing workspace.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  fontSize: 14, color: AppColors.textSecondary, height: 1.6),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.info.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_rounded,
                      size: 18, color: AppColors.info),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tables flagged "BILL" have already requested their check.',
                      style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 260.ms),
            if (isMobile) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.table_restaurant_rounded, size: 18),
                label: const Text('Select Table'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ).animate().fadeIn(delay: 320.ms),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  BILLING VIEW
  // ─────────────────────────────────────────────────────────
  Widget _buildBillingView(Map<String, dynamic> data, dynamic profile,
      {bool isMobile = false}) {
    final items = data['items'] as List<Map<String, dynamic>>;
    final subtotal = data['subtotal'] as double;
    final serviceCharge = _applyServiceCharge ? subtotal * 0.1 : 0.0;
    final afterService = subtotal + serviceCharge - _discount;
    final vat = _applyVat ? afterService * 0.13 : 0.0;
    final total = afterService + vat;
    final amountPaid = double.tryParse(_amountCtrl.text) ?? 0;
    final change = amountPaid - total;

    // Mobile: single column scroll
    if (isMobile) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSessionContextBar(data),
            const SizedBox(height: 14),
            _buildOrderCard(items, subtotal),
            const SizedBox(height: 14),
            _buildPaymentPanel(subtotal, serviceCharge, vat, total, amountPaid,
                change, items, data, profile,
                mobileMode: true),
            const SizedBox(height: 24),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Centre columns (Customer · Items · Adjustments) ─────────
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Session context bar ─────────────────────────────
                _buildSessionContextBar(data),
                const SizedBox(height: 16),
                // ── Invoice-style order card ────────────────────────
                _buildOrderCard(items, subtotal),
              ],
            ),
          ),
        ),
        // ── Right payment panel ─────────────────────────────────────
        _buildPaymentPanel(subtotal, serviceCharge, vat, total, amountPaid,
            change, items, data, profile),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  //  SESSION CONTEXT BAR — dark hero strip that anchors the
  //  workspace: which table is being billed, where it is, and
  //  whether the guest has already asked for the check.
  // ─────────────────────────────────────────────────────────
  Widget _buildSessionContextBar(Map<String, dynamic> data) {
    final tables = ref.watch(tablesStreamProvider).value ?? [];
    final table = tables.where((t) => t.id == _selectedTableId).firstOrNull;
    final kotCount = (data['kots'] as List? ?? []).length;
    final billRequested = table?.billRequested ?? false;

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_CashierUi.cardRadius),
        border: Border.all(color: AppColors.border),
        boxShadow: _CashierUi.cardShadow,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -22,
            top: -26,
            child: Icon(Icons.table_bar_rounded,
                size: 110, color: AppColors.primary.withValues(alpha: 0.05)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.gradientStart, AppColors.gradientEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    table != null ? table.tableNumber : '—',
                    style: GoogleFonts.outfit(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        table != null
                            ? 'Table ${table.tableNumber}'
                            : 'Active Session',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (table != null) ...[
                            const Icon(Icons.place_rounded,
                                size: 11, color: AppColors.textHint),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                table.section,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          const Icon(Icons.restaurant_menu_rounded,
                              size: 11, color: AppColors.textHint),
                          const SizedBox(width: 3),
                          Text(
                            '$kotCount KOT${kotCount == 1 ? '' : 's'}',
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (billRequested)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long_rounded,
                            size: 12, color: Color(0xFFFFC46B)),
                        const SizedBox(width: 5),
                        Text(
                          'BILL REQUESTED',
                          style: GoogleFonts.outfit(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: const Color(0xFFFFC46B),
                          ),
                        ),
                      ],
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .fade(duration: 800.ms, begin: 0.6)
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        )
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .fade(duration: 900.ms, begin: 0.35),
                        const SizedBox(width: 6),
                        Text(
                          'LIVE',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.06);
  }

  // ─────────────────────────────────────────────────────────
  //  ORDER CARD — one invoice-style document: guest, items and
  //  adjustments live together the way they do on a real bill.
  // ─────────────────────────────────────────────────────────
  Widget _buildOrderCard(List<Map<String, dynamic>> items, double subtotal) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_CashierUi.cardRadius),
        border: Border.all(color: AppColors.border),
        boxShadow: _CashierUi.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: _customerSection(),
          ),
          Container(height: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: _itemsSection(items, subtotal),
          ),
          Container(height: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: _adjustmentsSection(subtotal),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, {Widget? trailing}) {
    return Row(
      children: [
        Text(
          text,
          style: GoogleFonts.outfit(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textHint,
            letterSpacing: 1.0,
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  //  GUEST SECTION
  // ─────────────────────────────────────────────────────────
  Widget _customerSection() {
    final hasCustomer = _customerName != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(
          'GUEST',
          trailing: TextButton.icon(
            icon: Icon(
              hasCustomer ? Icons.edit_rounded : Icons.person_add_alt_1_rounded,
              size: 14,
            ),
            label: Text(hasCustomer ? 'Change' : 'Assign'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              textStyle:
                  GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
            onPressed: _showCustomerPicker,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // Avatar
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: hasCustomer
                    ? const LinearGradient(
                        colors: [Color(0xFF2980B9), Color(0xFF1F618D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: hasCustomer ? null : _CashierUi.subtleFill,
                shape: BoxShape.circle,
                border:
                    hasCustomer ? null : Border.all(color: AppColors.border),
              ),
              child: Center(
                child: hasCustomer
                    ? Text(
                        (_customerName ?? 'W')[0].toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.person_outline_rounded,
                        size: 22, color: AppColors.textHint),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _customerName ?? 'Walk-in Customer',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (_customerPhone != null) ...[
                        const Icon(Icons.phone_rounded,
                            size: 12, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Text(
                          _customerPhone!,
                          style: GoogleFonts.outfit(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ] else
                        Text(
                          'No contact information',
                          style: GoogleFonts.outfit(
                              fontSize: 12, color: AppColors.textHint),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  //  ORDER ITEMS SECTION
  // ─────────────────────────────────────────────────────────
  Widget _itemsSection(List<Map<String, dynamic>> items, double subtotal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(
          'ORDER ITEMS',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF8E44AD).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${items.length} item${items.length == 1 ? '' : 's'}',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF8E44AD),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        items.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox_rounded,
                          size: 28,
                          color: AppColors.textHint.withValues(alpha: 0.6)),
                      const SizedBox(height: 8),
                      Text(
                        'No items in this order yet',
                        style: GoogleFonts.outfit(
                            fontSize: 13, color: AppColors.textHint),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'ITEM',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textHint,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        Text(
                          'QTY',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textHint,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 90,
                          child: Text(
                            'AMOUNT',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textHint,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1, color: AppColors.border),
                  const SizedBox(height: 4),
                  ...items.asMap().entries.map((entry) {
                    final i = entry.key;
                    final item = entry.value;
                    final itemTotal =
                        ((item['unit_price'] as num?)?.toDouble() ?? 0) *
                            (item['quantity'] as int);
                    final unitPrice =
                        (item['unit_price'] as num?)?.toDouble() ?? 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: i == items.length - 1
                            ? null
                            : const Border(
                                bottom: BorderSide(color: AppColors.divider)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          children: [
                            // Index bubble
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: const Color(0xFF8E44AD)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${i + 1}',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF8E44AD),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (item['menu_item_name'] ??
                                        item['name'] ??
                                        'Unknown Item') as String,
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    'NPR ${fmt.format(unitPrice)} each',
                                    style: GoogleFonts.outfit(
                                        fontSize: 11,
                                        color: AppColors.textHint),
                                  ),
                                ],
                              ),
                            ),
                            // Qty badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '×${item['quantity']}',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 90,
                              child: Text(
                                'NPR ${fmt.format(itemTotal)}',
                                textAlign: TextAlign.right,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                  Container(height: 1, color: AppColors.border),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Subtotal',
                        style: GoogleFonts.outfit(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        'NPR ${fmt.format(subtotal)}',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  //  ADJUSTMENTS SECTION
  // ─────────────────────────────────────────────────────────
  Widget _adjustmentsSection(double subtotal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('ADJUSTMENTS & CHARGES'),
        const SizedBox(height: 14),
        Column(
          children: [
            // Service charge toggle
            _buildToggleRow(
              icon: Icons.room_service_rounded,
              label: 'Service Charge',
              sublabel: '10% of subtotal',
              value: _applyServiceCharge,
              valueLabel: _applyServiceCharge
                  ? '+ NPR ${fmt.format(subtotal * 0.1)}'
                  : 'Off',
              valueColor:
                  _applyServiceCharge ? AppColors.warning : AppColors.textHint,
              onChanged: (v) => setState(() => _applyServiceCharge = v),
            ),
            // VAT toggle removed
            const SizedBox(height: 12),
            Container(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            // Discount field
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_offer_rounded,
                      size: 16, color: AppColors.success),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Discount',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Flat discount in NPR',
                        style: GoogleFonts.outfit(
                            fontSize: 11, color: AppColors.textHint),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _discountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      prefixText: 'NPR ',
                      prefixStyle: GoogleFonts.outfit(
                          fontSize: 12, color: AppColors.textHint),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: AppColors.success, width: 1.5),
                      ),
                      filled: true,
                      fillColor: AppColors.success.withValues(alpha: 0.04),
                    ),
                    onChanged: (v) =>
                        setState(() => _discount = double.tryParse(v) ?? 0),
                  ),
                ),
              ],
            ),
            if (subtotal > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox(width: 47),
                  ...[5, 10, 15, 20].map((pct) {
                    final amt =
                        double.parse((subtotal * pct / 100).toStringAsFixed(2));
                    final isActive =
                        (_discount - amt).abs() < 0.01 && _discount > 0;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _discount = amt;
                          _discountCtrl.text = amt.toStringAsFixed(2);
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.success.withValues(alpha: 0.12)
                                : _CashierUi.subtleFill,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isActive
                                  ? AppColors.success.withValues(alpha: 0.5)
                                  : AppColors.border,
                            ),
                          ),
                          child: Text(
                            '$pct%',
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isActive
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String label,
    required String sublabel,
    required bool value,
    required String valueLabel,
    required Color valueColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: valueColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: valueColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                sublabel,
                style:
                    GoogleFonts.outfit(fontSize: 11, color: AppColors.textHint),
              ),
            ],
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: valueColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            valueLabel,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: valueColor,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  //  PAYMENT PANEL (right side)
  // ─────────────────────────────────────────────────────────
  Widget _buildPaymentPanel(
    double subtotal,
    double serviceCharge,
    double vat,
    double total,
    double amountPaid,
    double change,
    List items,
    Map<String, dynamic> data,
    dynamic profile, {
    bool mobileMode = false,
  }) {
    final containerDecoration = mobileMode
        ? BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(_CashierUi.cardRadius),
            border: Border.all(color: AppColors.border),
            boxShadow: _CashierUi.cardShadow,
          )
        : const BoxDecoration(
            color: AppColors.surface,
            border: Border(left: BorderSide(color: AppColors.border)),
          );

    // ── Header ─────────────────────────────────────────
    final header = Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 15),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: AppColors.primary, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bill Summary',
                  style: GoogleFonts.outfit(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.1,
                  ),
                ),
                Text(
                  '${items.length} item${items.length == 1 ? '' : 's'} · ready to settle',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // ── Scrollable body ──────────────────────────────────
    final scrollBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Total — the one number that matters, promoted to the very
        // top of the panel so it's the first thing the cashier sees.
        Container(
          width: double.infinity,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.gradientStart, AppColors.gradientEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: _CashierUi.heroShadow,
          ),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                top: -18,
                child: Icon(Icons.receipt_long_rounded,
                    size: 100, color: Colors.white.withValues(alpha: 0.08)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL DUE',
                          style: GoogleFonts.outfit(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.85),
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Incl. all charges & discounts',
                          style: GoogleFonts.outfit(
                            fontSize: 10.5,
                            color: Colors.white.withValues(alpha: 0.65),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'NPR ${fmt.format(total)}',
                      style: GoogleFonts.outfit(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ).animate().scale(
              duration: 260.ms,
              curve: Curves.easeOutBack,
              begin: const Offset(0.97, 0.97),
            ),

        const SizedBox(height: 14),

        // Bill breakdown card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _CashierUi.subtleFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _PremiumBillRow(
                label: 'Subtotal',
                value: 'NPR ${fmt.format(subtotal)}',
              ),
              if (_applyServiceCharge) ...[
                const SizedBox(height: 9),
                _PremiumBillRow(
                  label: 'Service Charge (10%)',
                  value: '+ NPR ${fmt.format(serviceCharge)}',
                  valueColor: AppColors.warning,
                ),
              ],
              if (_discount > 0) ...[
                const SizedBox(height: 9),
                _PremiumBillRow(
                  label: 'Discount',
                  value: '- NPR ${fmt.format(_discount)}',
                  valueColor: AppColors.success,
                ),
              ],
              if (_applyVat) ...[
                const SizedBox(height: 9),
                _PremiumBillRow(
                  label: 'VAT (13%)',
                  value: '+ NPR ${fmt.format(vat)}',
                  valueColor: const Color(0xFF2980B9),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Payment method label
        Text(
          'PAYMENT METHOD',
          style: GoogleFonts.outfit(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.textHint,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        // Payment method grid
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 9,
          crossAxisSpacing: 9,
          childAspectRatio: 1.18,
          children: _paymentMethods.map((pm) {
            final isSelected = _paymentMethod == pm['value'];
            final pmColor = pm['color'] as Color;
            return GestureDetector(
              onTap: () =>
                  setState(() => _paymentMethod = pm['value'] as String),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 150),
                scale: isSelected ? 1.0 : 0.97,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(
                            colors: [
                              pmColor,
                              Color.lerp(pmColor, Colors.black, 0.22)!,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isSelected ? null : _CashierUi.subtleFill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? Colors.transparent : AppColors.border,
                    ),
                    boxShadow:
                        isSelected ? _CashierUi.tintShadow(pmColor) : null,
                  ),
                  child: Stack(
                    children: [
                      if (isSelected)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: Icon(Icons.check_circle_rounded,
                              size: 13, color: Colors.white),
                        ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.18)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(9),
                                border: isSelected
                                    ? null
                                    : Border.all(color: AppColors.border),
                              ),
                              alignment: Alignment.center,
                              child: pm['asset'] != null
                                  ? Image.asset(
                                      pm['asset'] as String,
                                      width: 18,
                                      height: 18,
                                      errorBuilder: (_, __, ___) => Icon(
                                        pm['icon'] as IconData,
                                        size: 15,
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.textSecondary,
                                      ),
                                    )
                                  : Icon(
                                      pm['icon'] as IconData,
                                      size: 15,
                                      color: isSelected
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                    ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              pm['label'] as String,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 11.5,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        // Cash amount input
        if (_paymentMethod == 'cash') ...[
          const SizedBox(height: 18),
          Text(
            'AMOUNT RECEIVED',
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.textHint,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.outfit(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              prefixText: 'NPR  ',
              prefixStyle: GoogleFonts.outfit(
                fontSize: 14,
                color: AppColors.textHint,
              ),
              hintText: '0.00',
              hintStyle: GoogleFonts.outfit(
                fontSize: 18,
                color: AppColors.textHint,
                fontWeight: FontWeight.w700,
              ),
              filled: true,
              fillColor: _CashierUi.subtleFill,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          // Quick cash suggestions — exact amount plus the next
          // couple of round denominations, so the cashier rarely
          // has to type the number by hand.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickCashOptions(total).map((amt) {
              final isExact = (amt - total).abs() < 0.005;
              return GestureDetector(
                onTap: () => setState(() => _amountCtrl.text =
                    amt.toStringAsFixed(amt % 1 == 0 ? 0 : 2)),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isExact
                        ? AppColors.success.withValues(alpha: 0.08)
                        : _CashierUi.subtleFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isExact
                          ? AppColors.success.withValues(alpha: 0.4)
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    isExact ? 'Exact' : fmt0.format(amt),
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color:
                          isExact ? AppColors.success : AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          // Change display
          if (amountPaid > 0) ...[
            const SizedBox(height: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: change >= 0
                    ? AppColors.success.withValues(alpha: 0.08)
                    : AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: change >= 0
                      ? AppColors.success.withValues(alpha: 0.3)
                      : AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        change >= 0
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        size: 14,
                        color:
                            change >= 0 ? AppColors.success : AppColors.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        change >= 0 ? 'Change Due' : 'Amount Short',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              change >= 0 ? AppColors.success : AppColors.error,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'NPR ${fmt.format(change.abs())}',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: change >= 0 ? AppColors.success : AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],

        if (_paymentMethod == 'credit') ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This will create a credit (Udhaaro) record for NPR ${fmt.format(total)}.',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: AppColors.warning,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    // ── Action buttons footer ────────────────────────────
    final footer = Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          // Settle bill button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: _processing
                    ? null
                    : const LinearGradient(
                        colors: [
                          AppColors.gradientStart,
                          AppColors.gradientEnd
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: _processing
                    ? AppColors.primary.withValues(alpha: 0.6)
                    : null,
                borderRadius: BorderRadius.circular(14),
                boxShadow: _processing
                    ? null
                    : [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.32),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _processing
                    ? null
                    : () => _settleBill(total, subtotal, serviceCharge, vat,
                        profile, items, data),
                child: _processing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _paymentMethod == 'credit'
                                ? Icons.receipt_long_rounded
                                : Icons.check_circle_rounded,
                            size: 19,
                          ),
                          const SizedBox(width: 9),
                          Text(
                            _paymentMethod == 'credit'
                                ? 'Record Credit (Udhaaro)'
                                : 'Settle Bill  ·  NPR ${fmt.format(total)}',
                            style: GoogleFonts.outfit(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Print bill button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                backgroundColor: _CashierUi.subtleFill,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => _printBill(total, items, data),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.print_rounded, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Print Bill',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    // Mobile renders the panel as a card inside the page scroll; desktop
    // pins it as a full-height column with its own internal scroll.
    if (mobileMode) {
      return Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: containerDecoration,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            Padding(
              padding: const EdgeInsets.all(18),
              child: scrollBody,
            ),
            footer,
          ],
        ),
      );
    }

    return Container(
      width: 372,
      decoration: containerDecoration,
      child: Column(
        children: [
          header,
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: scrollBody,
            ),
          ),
          footer,
        ],
      ),
    );
  }

  /// Exact total plus the next couple of clean round-number denominations
  /// above it, so a cashier can tap instead of typing for the common case.
  List<double> _quickCashOptions(double total) {
    if (total <= 0) return const [];
    final options = <double>{total};
    const steps = [50.0, 100.0, 500.0, 1000.0];
    for (final step in steps) {
      final rounded = (total / step).ceil() * step;
      if (rounded > total) options.add(rounded);
      if (options.length >= 4) break;
    }
    final sorted = options.toList()..sort();
    return sorted.take(4).toList();
  }

  // ─────────────────────────────────────────────────────────
  //  SETTLE BILL
  // ─────────────────────────────────────────────────────────
  Future<void> _settleBill(
      double total,
      double subtotal,
      double serviceCharge,
      double vat,
      dynamic profile,
      List items,
      Map<String, dynamic> data) async {
    if (_selectedSessionId == null || _selectedTableId == null) return;
    setState(() => _processing = true);
    try {
      final amountPaid = _paymentMethod == 'cash'
          ? (double.tryParse(_amountCtrl.text) ?? total)
          : total;

      final response = await ApiClient.instance.post(
        ApiConstants.generateBill(_selectedSessionId!),
        data: {
          'discount': _discount,
          'paymentMethod': _paymentMethod,
          'amountPaid': amountPaid,
          if (_customerName != null) 'customerName': _customerName,
          if (_customerPhone != null) 'customerPhone': _customerPhone,
          'applyServiceCharge': _applyServiceCharge,
          'applyVat': _applyVat,
        },
      );
      final bill = response.data as Map<String, dynamic>;
      final invoiceNum = bill['invoice_number'] as String? ?? '';

      ref.invalidate(tablesStreamProvider);
      ref.invalidate(tableSessionProvider(_selectedTableId!));
      ref.invalidate(dashboardBillsProvider);
      ref.invalidate(dashboardCreditProvider);
      ref.invalidate(dashboardSessionsProvider);
      ref.invalidate(billsStreamProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Bill settled! Invoice: $invoiceNum',
                  style: GoogleFonts.outfit(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );

        // Show the real, final receipt (actual invoice/bill number,
        // payment method, amount paid, change) right after settling —
        // this is the one that matters, the pre-settle "Print Bill"
        // button is only ever a preview since no invoice exists yet.
        _printReceipt(bill, items);

        setState(() {
          _selectedSessionId = null;
          _selectedTableId = null;
          _customerName = null;
          _customerPhone = null;
          _discount = 0;
          _discountCtrl.text = '0';
          _amountCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
            content: Text('Error: $e',
                style: GoogleFonts.outfit(color: Colors.white)),
          ),
        );
      }
    }
    if (mounted) setState(() => _processing = false);
  }

  // ─────────────────────────────────────────────────────────
  //  PRINT BILL (pre-settle preview — no invoice number yet)
  // ─────────────────────────────────────────────────────────
  void _printBill(double total, List items, Map<String, dynamic> data) {
    final subtotal = data['subtotal'] as double;
    final serviceCharge = _applyServiceCharge ? subtotal * 0.1 : 0.0;
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    final tables = ref.read(tablesStreamProvider).value ?? [];
    final selectedTable =
        tables.where((t) => t.id == _selectedTableId).firstOrNull;
    final tableNumber = selectedTable?.tableNumber ?? 'N/A';

    final sessions = ref.read(activeSessionsStreamProvider).value ?? [];
    final selectedSession =
        sessions.where((s) => s.id == _selectedSessionId).firstOrNull;
    final sessionNumber = selectedSession?.sessionNumber ??
        (_selectedSessionId != null
            ? _selectedSessionId!.substring(0, 8)
            : 'N/A');

    final branch = ref.read(currentBranchProvider).value;

    showThermalPrintDialog(
      context,
      title: 'Thermal Print Preview',
      onPrint: () => showPrintSentSnackbar(context),
      receipt: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          receiptBranchHeader(branch),
          receiptDivider(),
          const SizedBox(height: 4),
          receiptRow('Date:', dateStr),
          receiptRow('Table:', tableNumber),
          receiptRow('Session:', sessionNumber),
          if (_customerName != null) receiptRow('Customer:', _customerName!),
          const SizedBox(height: 4),
          receiptDivider(),
          const SizedBox(height: 4),
          ...items.map((item) {
            final name = item['menu_item_name'] as String;
            final qty = item['quantity'] as int;
            final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
            return receiptRow('$name x$qty', fmt.format(price * qty),
                fontSize: 12);
          }),
          const SizedBox(height: 4),
          receiptDivider(),
          const SizedBox(height: 4),
          receiptRow('Subtotal:', fmt.format(subtotal)),
          if (_applyServiceCharge)
            receiptRow('Service (10%):', fmt.format(serviceCharge)),
          if (_discount > 0)
            receiptRow('Discount:', '-${fmt.format(_discount)}'),
          const SizedBox(height: 4),
          receiptDivider(),
          const SizedBox(height: 4),
          receiptRow('TOTAL:', 'NPR ${fmt.format(total)}',
              fontSize: 14, weight: FontWeight.bold),
          const SizedBox(height: 8),
          Text('*** PREVIEW — not a valid receipt ***',
              textAlign: TextAlign.center, style: receiptStyle(fontSize: 9)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  PRINT RECEIPT — the real, final receipt after a bill is settled,
  //  built from the backend's actual invoice/bill numbers and totals.
  // ─────────────────────────────────────────────────────────
  void _printReceipt(Map<String, dynamic> bill, List items) {
    final branch = ref.read(currentBranchProvider).value;
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(
        DateTime.tryParse(bill['created_at'] as String? ?? '') ??
            DateTime.now());

    final subtotal = (bill['sub_total'] as num?)?.toDouble() ?? 0;
    final discount = (bill['discount'] as num?)?.toDouble() ?? 0;
    final serviceCharge = (bill['service_charge'] as num?)?.toDouble() ?? 0;
    final vatAmount = (bill['vat_amount'] as num?)?.toDouble() ?? 0;
    final totalAmount = (bill['total_amount'] as num?)?.toDouble() ?? 0;
    final amountPaid = (bill['amount_paid'] as num?)?.toDouble() ?? 0;
    final changeAmount = (bill['change_amount'] as num?)?.toDouble() ?? 0;
    final paymentMethod =
        (bill['payment_method'] as String? ?? '').toUpperCase();
    final customerName = bill['customer_name'] as String?;
    final cashierName = bill['cashier_name'] as String?;

    showThermalPrintDialog(
      context,
      title: 'Receipt',
      onPrint: () => showPrintSentSnackbar(context,
          label: 'Receipt sent to thermal printer!'),
      receipt: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          receiptBranchHeader(branch),
          receiptDivider(),
          const SizedBox(height: 4),
          receiptRow('Invoice No:', bill['invoice_number'] as String? ?? '—',
              weight: FontWeight.bold),
          receiptRow('Bill No:', bill['bill_number'] as String? ?? '—'),
          receiptRow('Date:', dateStr),
          if (cashierName != null) receiptRow('Cashier:', cashierName),
          if (customerName != null) receiptRow('Customer:', customerName),
          const SizedBox(height: 4),
          receiptDivider(),
          const SizedBox(height: 4),
          ...items.map((item) {
            final name = item['menu_item_name'] as String;
            final qty = item['quantity'] as int;
            final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
            return receiptRow('$name x$qty', fmt.format(price * qty),
                fontSize: 12);
          }),
          const SizedBox(height: 4),
          receiptDivider(),
          const SizedBox(height: 4),
          receiptRow('Subtotal:', fmt.format(subtotal)),
          if (serviceCharge > 0)
            receiptRow('Service Charge:', fmt.format(serviceCharge)),
          if (discount > 0) receiptRow('Discount:', '-${fmt.format(discount)}'),
          if (vatAmount > 0) receiptRow('VAT:', fmt.format(vatAmount)),
          const SizedBox(height: 4),
          receiptDivider(),
          const SizedBox(height: 4),
          receiptRow('TOTAL:', 'NPR ${fmt.format(totalAmount)}',
              fontSize: 14, weight: FontWeight.bold),
          const SizedBox(height: 4),
          receiptRow('Payment Method:', paymentMethod),
          receiptRow('Amount Paid:', fmt.format(amountPaid)),
          if (changeAmount > 0) receiptRow('Change:', fmt.format(changeAmount)),
          const SizedBox(height: 8),
          Text('Thank you for dining with us!',
              textAlign: TextAlign.center, style: receiptStyle()),
          Text('Powered by Katiya Station RMS',
              textAlign: TextAlign.center, style: receiptStyle(fontSize: 9)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  CUSTOMER PICKER DIALOG
  // ─────────────────────────────────────────────────────────
  void _showCustomerPicker() async {
    final nameCtrl = TextEditingController(text: _customerName ?? '');
    final phoneCtrl = TextEditingController(text: _customerPhone ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF5FB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person_rounded,
                  color: Color(0xFF2980B9), size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'Customer Information',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Customer Name',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: const Icon(Icons.phone_rounded),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              setState(() {
                _customerName =
                    nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim();
                _customerPhone = phoneCtrl.text.trim().isEmpty
                    ? null
                    : phoneCtrl.text.trim();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _TodayStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _TodayStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: _CashierUi.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 10.5,
              color: AppColors.textHint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected ? color.withValues(alpha: 0.1) : _CashierUi.subtleFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color:
                  selected ? color.withValues(alpha: 0.4) : AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? color : AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color:
                    selected ? color.withValues(alpha: 0.18) : AppColors.border,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.outfit(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? color : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBarStatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool pulse;

  const _AppBarStatPill({
    required this.icon,
    required this.label,
    required this.color,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
    if (!pulse) return pill;
    return pill
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fade(duration: 700.ms, begin: 0.55);
  }
}

class _PremiumBillRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _PremiumBillRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 13,
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
