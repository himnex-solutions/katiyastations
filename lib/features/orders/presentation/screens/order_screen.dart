import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/order_provider.dart';
import '../../domain/entities/order_entities.dart';
import '../../../menu/domain/entities/menu_entities.dart';

import '../../../tables/presentation/providers/tables_provider.dart';

class OrderScreen extends ConsumerStatefulWidget {
  final String tableId;
  final String sessionId;

  const OrderScreen({super.key, required this.tableId, required this.sessionId});

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen>
    with TickerProviderStateMixin {
  String? _selectedCategoryId;
  final fmt = NumberFormat('#,##0.00');
  // 0 = Cart, 1 = KOT History
  late final TabController _rightPanelTab;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _rightPanelTab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _rightPanelTab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).value;
    final cart = ref.watch(orderNotifierProvider);
    final cartNotifier = ref.read(orderNotifierProvider.notifier);
    final categoriesAsync = profile?.branchId != null
        ? ref.watch(menuCategoriesProvider(profile!.branchId!))
        : const AsyncValue.data(<MenuCategory>[]);

    final subtotal = cartNotifier.subtotal;
    const tax = 0.0;
    final total = subtotal;

    // Watch this table's session for hold status
    final sessionsAsync = ref.watch(activeSessionsStreamProvider);
    final currentSession = sessionsAsync.value?.where((s) => s.id == widget.sessionId).firstOrNull;
    final isOnHold = currentSession?.onHold ?? false;

    final isMobile = context.isMobile;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/tables'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ref.watch(tablesStreamProvider).when(
              data: (tables) {
                final t = tables.where((t) => t.id == widget.tableId).firstOrNull;
                return Text(t != null ? 'Table ${t.tableNumber}' : 'Take Order');
              },
              loading: () => const Text('Take Order'),
              error: (_, __) => const Text('Take Order'),
            ),
            Text('Session: ${widget.sessionId.substring(0, 8)}...',
                style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          // ── Hold / Unhold button ────────────────────────────────────────
          if (profile?.isWaiter == true && widget.sessionId.isNotEmpty)
            Tooltip(
              message: isOnHold ? 'Resume Order' : 'Hold Order',
              child: IconButton(
                icon: Icon(
                  isOnHold ? Icons.play_circle_rounded : Icons.pause_circle_rounded,
                  color: isOnHold ? AppColors.warning : AppColors.textSecondary,
                ),
                onPressed: () => _handleHoldToggle(isOnHold),
              ),
            ),
          // ── KOT History icon (mobile only) ──────────────────────────────
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.receipt_rounded),
              tooltip: 'KOT History',
              onPressed: () => _showKotHistorySheet(context),
            ),
          // ── Request Bill / Bill Status / Settle ─────────────────────────
          if (widget.sessionId.isNotEmpty) ...[
            ref.watch(tablesStreamProvider).when(
              data: (tables) {
                final currentTable = tables.where((t) => t.id == widget.tableId).firstOrNull;
                final isBillRequested = currentTable?.billRequested ?? false;
                if (profile?.isWaiter == true) {
                  if (isBillRequested) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_outline_rounded, size: 14, color: AppColors.warning),
                          const SizedBox(width: 6),
                          Text('Bill Requested',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.warning,
                              )),
                        ],
                      ),
                    );
                  } else {
                    return TextButton.icon(
                      icon: const Icon(Icons.receipt_long_rounded, size: 16, color: AppColors.warning),
                      label: Text('Request Bill', style: GoogleFonts.outfit(color: AppColors.warning)),
                      onPressed: _handleRequestBill,
                      style: TextButton.styleFrom(foregroundColor: AppColors.warning),
                    );
                  }
                } else if (profile?.isCashier == true || profile?.isBranchManager == true) {
                  return TextButton.icon(
                    icon: const Icon(Icons.receipt_long_rounded, size: 16),
                    label: const Text('Settle Bill'),
                    onPressed: () => context.go('/cashier?sessionId=${widget.sessionId}&tableId=${widget.tableId}'),
                  );
                }
                return const SizedBox();
              },
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      // ── Mobile layout: full-screen menu + FAB cart button ───────────────
      body: isMobile
          ? _buildMobileMenuBody(
              cart: cart,
              cartNotifier: cartNotifier,
              categoriesAsync: categoriesAsync,
              isOnHold: isOnHold,
              profile: profile,
              subtotal: subtotal,
              total: total,
            )
          : _buildDesktopBody(
              cart: cart,
              cartNotifier: cartNotifier,
              categoriesAsync: categoriesAsync,
              isOnHold: isOnHold,
              subtotal: subtotal,
              tax: tax,
              total: total,
              profile: profile,
            ),
      // ── Cart FAB (mobile only) ───────────────────────────────────────────
      floatingActionButton: isMobile
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: () => _showCartSheet(context, cart, cartNotifier, subtotal, total, profile),
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.shopping_cart_rounded),
                  if (cart.isNotEmpty)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${cart.length}',
                          style: GoogleFonts.outfit(
                              fontSize: 9,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
              label: Text(
                cart.isEmpty
                    ? 'Cart'
                    : 'NPR ${fmt.format(total)}',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            )
          : null,
    );
  }

  /// Mobile: full-screen menu browser
  Widget _buildMobileMenuBody({
    required List<CartItem> cart,
    required OrderNotifier cartNotifier,
    required AsyncValue categoriesAsync,
    required bool isOnHold,
    required dynamic profile,
    required double subtotal,
    required double total,
  }) {
    final isSearching = _searchQuery.trim().isNotEmpty;
    return Column(
      children: [
        if (isOnHold)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.warning.withValues(alpha: 0.15),
            child: Row(
              children: [
                const Icon(Icons.pause_circle_filled_rounded, color: AppColors.warning, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Order is on HOLD — tap Resume to continue',
                      style: GoogleFonts.outfit(
                          color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                TextButton(
                  onPressed: () => _handleHoldToggle(true),
                  child: const Text('Resume', style: TextStyle(color: AppColors.warning)),
                ),
              ],
            ),
          ).animate().slideY(begin: -0.5, duration: 300.ms),
        _buildMenuSearchBar(),
        Expanded(
          child: categoriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error loading menu: $e',
                  style: const TextStyle(color: AppColors.error)),
            ),
            data: (categories) {
              if (_selectedCategoryId == null && categories.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _selectedCategoryId = categories.first.id);
                });
              }
              return Column(
                children: [
                  if (!isSearching) _buildCategoryTabBar(categories),
                  if (!isSearching) const Divider(height: 1),
                  Expanded(
                    child: isSearching
                        ? _MenuSearchResultsGrid(
                            branchId: profile?.branchId ?? '',
                            query: _searchQuery,
                            categories: categories,
                            onAdd: (item) => cartNotifier.addItem(item),
                            cart: cart,
                          )
                        : (_selectedCategoryId == null
                            ? const Center(
                                child: Text('Select a category',
                                    style: TextStyle(color: AppColors.textSecondary)))
                            : _MenuItemsGrid(
                                categoryId: _selectedCategoryId!,
                                onAdd: (item) => cartNotifier.addItem(item),
                                cart: cart,
                              )),
                  ),
                ],
              );
            },
          ),
        ),
        // Bottom padding for FAB
        const SizedBox(height: 80),
      ],
    );
  }

  /// Search bar for filtering the menu by name, price, or category
  Widget _buildMenuSearchBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: TextField(
        controller: _searchCtrl,
        style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search menu by name, price or category',
          hintStyle: GoogleFonts.outfit(fontSize: 13, color: AppColors.textHint),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          filled: true,
          fillColor: AppColors.surfaceVariant,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
          ),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  /// Horizontal scrolling category chip bar
  Widget _buildCategoryTabBar(List<MenuCategory> categories) {
    return Container(
      height: 56,
      color: AppColors.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: categories.length,
        itemBuilder: (ctx, i) {
          final cat = categories[i];
          final isSelected = cat.id == _selectedCategoryId;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategoryId = cat.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(cat.name,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: isSelected ? AppColors.onPrimary : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  )),
            ),
          );
        },
      ),
    );
  }

  /// Desktop/Tablet: side-by-side split layout
  Widget _buildDesktopBody({
    required List<CartItem> cart,
    required OrderNotifier cartNotifier,
    required AsyncValue categoriesAsync,
    required bool isOnHold,
    required double subtotal,
    required double tax,
    required double total,
    required dynamic profile,
  }) {
    final isSearching = _searchQuery.trim().isNotEmpty;
    return Row(
      children: [
        // ── Left: Menu browser ──────────────────────────────────────────
        Expanded(
          flex: 7,
          child: Column(
            children: [
              // Hold banner
              if (isOnHold)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppColors.warning.withValues(alpha: 0.15),
                  child: Row(
                    children: [
                      const Icon(Icons.pause_circle_filled_rounded,
                          color: AppColors.warning, size: 18),
                      const SizedBox(width: 8),
                      Text('Order is on HOLD — tap Resume to continue',
                          style: GoogleFonts.outfit(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _handleHoldToggle(true),
                        child: const Text('Resume',
                            style: TextStyle(color: AppColors.warning)),
                      ),
                    ],
                  ),
                ).animate().slideY(begin: -0.5, duration: 300.ms),
              _buildMenuSearchBar(),
              Expanded(
                child: categoriesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error loading menu: $e',
                        style: const TextStyle(color: AppColors.error)),
                  ),
                  data: (categories) {
                    if (_selectedCategoryId == null && categories.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() => _selectedCategoryId = categories.first.id);
                        }
                      });
                    }
                    return Column(
                      children: [
                        if (!isSearching) _buildCategoryTabBar(categories),
                        if (!isSearching) const Divider(height: 1),
                        Expanded(
                          child: isSearching
                              ? _MenuSearchResultsGrid(
                                  branchId: profile?.branchId ?? '',
                                  query: _searchQuery,
                                  categories: categories,
                                  onAdd: (item) => cartNotifier.addItem(item),
                                  cart: cart,
                                )
                              : (_selectedCategoryId == null
                                  ? const Center(
                                      child: Text('Select a category',
                                          style: TextStyle(color: AppColors.textSecondary)))
                                  : _MenuItemsGrid(
                                      categoryId: _selectedCategoryId!,
                                      onAdd: (item) => cartNotifier.addItem(item),
                                      cart: cart,
                                    )),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // ── Right: Cart + KOT History ───────────────────────────────────
        Container(
          width: 320,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(left: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            children: [
              // Tab bar: Cart | KOT History
              Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: TabBar(
                  controller: _rightPanelTab,
                  labelStyle:
                      GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
                  unselectedLabelStyle:
                      GoogleFonts.outfit(fontWeight: FontWeight.w400, fontSize: 13),
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shopping_cart_rounded, size: 16),
                          const SizedBox(width: 6),
                          const Text('Cart'),
                          if (cart.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('${cart.length}',
                                  style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_rounded, size: 16),
                          SizedBox(width: 6),
                          Text('KOT History'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Tab view
              Expanded(
                child: TabBarView(
                  controller: _rightPanelTab,
                  children: [
                    // ── Cart Tab ──────────────────────────────────────
                    _CartTab(
                      cart: cart,
                      cartNotifier: cartNotifier,
                      fmt: fmt,
                      subtotal: subtotal,
                      tax: tax,
                      total: total,
                      onSendKot: () => _sendKot(profile),
                    ),
                    // ── KOT History Tab ───────────────────────────────
                    _KotHistoryTab(
                      sessionId: widget.sessionId,
                      tableId: widget.tableId,
                      fmt: fmt,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Show cart as a DraggableScrollableSheet on mobile
  void _showCartSheet(
    BuildContext context,
    List<CartItem> cart,
    OrderNotifier cartNotifier,
    double subtotal,
    double total,
    dynamic profile,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text('Cart',
                        style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    if (cart.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('${cart.length}',
                            style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                    const Spacer(),
                    if (cart.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          cartNotifier.clearCart();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Clear All',
                            style: TextStyle(
                                color: AppColors.error, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: cart.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_shopping_cart_rounded,
                                size: 48, color: AppColors.textHint),
                            const SizedBox(height: 12),
                            Text('Add items from the menu',
                                style: GoogleFonts.outfit(
                                    color: AppColors.textHint, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        itemCount: cart.length,
                        itemBuilder: (ctx, i) => _CartItemTile(
                          cartItem: cart[i],
                          onIncrease: () =>
                              cartNotifier.increaseQty(cart[i].item.id),
                          onDecrease: () =>
                              cartNotifier.decreaseQty(cart[i].item.id),
                          onRemove: () =>
                              cartNotifier.removeItem(cart[i].item.id),
                          fmt: fmt,
                        ).animate().fadeIn(
                            delay: Duration(milliseconds: i * 30)),
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Column(
                  children: [
                    _SummaryRow('Subtotal', 'NPR ${fmt.format(subtotal)}'),
                    const Divider(height: 16),
                    _SummaryRow('Total', 'NPR ${fmt.format(total)}',
                        isBold: true),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('Send KOT to Kitchen'),
                        onPressed: cart.isEmpty
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _sendKot(profile);
                              },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Show KOT history as bottom sheet on mobile
  void _showKotHistorySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text('KOT History',
                        style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _KotHistoryTab(
                  sessionId: widget.sessionId,
                  tableId: widget.tableId,
                  fmt: fmt,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleHoldToggle(bool isCurrentlyOnHold) async {
    final messenger = ScaffoldMessenger.of(context);
    if (isCurrentlyOnHold) {
      final ok = await ref.read(tableNotifierProvider.notifier).unholdSession(widget.sessionId);
      if (ok && mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Order resumed!'),
          backgroundColor: AppColors.success,
        ));
      }
    } else {
      // Show reason dialog
      String? reason;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Hold Order', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Enter a reason for holding this order (optional):',
                    style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. Guests stepped out...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  reason = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
                  Navigator.pop(ctx);
                },
                child: const Text('Hold'),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      final ok = await ref
          .read(tableNotifierProvider.notifier)
          .holdSession(widget.sessionId, reason: reason);
      if (ok && mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Order placed on hold'),
          backgroundColor: AppColors.warning,
        ));
      }
    }
  }

  Future<void> _handleRequestBill() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final success = await ref
          .read(tableNotifierProvider.notifier)
          .requestBill(widget.tableId, widget.sessionId);
      if (success && mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.warning),
                SizedBox(width: 10),
                Text('Bill request sent to cashier!'),
              ],
            ),
            backgroundColor: AppColors.surfaceVariant,
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error requesting bill: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _sendKot(dynamic profile) async {
    if (profile == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final kot = await ref.read(orderNotifierProvider.notifier).sendKot(
            sessionId: widget.sessionId,
            tableId: widget.tableId,
            branchId: profile.branchId ?? '',
          );
      if (kot != null && mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success),
                const SizedBox(width: 10),
                Text('${kot.kotNumber} sent to kitchen!'),
              ],
            ),
            backgroundColor: AppColors.surfaceVariant,
          ),
        );
        // Switch to KOT History tab so they can see/edit it
        _rightPanelTab.animateTo(1);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error sending KOT: $e'), backgroundColor: AppColors.error),
      );
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Cart Tab
// ════════════════════════════════════════════════════════════════════════════
class _CartTab extends StatelessWidget {
  final List<CartItem> cart;
  final OrderNotifier cartNotifier;
  final NumberFormat fmt;
  final double subtotal;
  final double tax;
  final double total;
  final VoidCallback onSendKot;

  const _CartTab({
    required this.cart,
    required this.cartNotifier,
    required this.fmt,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.onSendKot,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // List header
        if (cart.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              children: [
                Text('${cart.length} item(s)',
                    style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                const Spacer(),
                TextButton(
                  onPressed: () => cartNotifier.clearCart(),
                  child: const Text('Clear All', style: TextStyle(color: AppColors.error, fontSize: 12)),
                ),
              ],
            ),
          ),
        // Cart items
        Expanded(
          child: cart.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_shopping_cart_rounded, size: 48, color: AppColors.textHint),
                      const SizedBox(height: 12),
                      Text('Add items from the menu',
                          style: GoogleFonts.outfit(color: AppColors.textHint, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: cart.length,
                  itemBuilder: (ctx, i) => _CartItemTile(
                    cartItem: cart[i],
                    onIncrease: () => cartNotifier.increaseQty(cart[i].item.id),
                    onDecrease: () => cartNotifier.decreaseQty(cart[i].item.id),
                    onRemove: () => cartNotifier.removeItem(cart[i].item.id),
                    fmt: fmt,
                  ).animate().fadeIn(delay: Duration(milliseconds: i * 30)),
                ),
        ),
        // Totals + Send KOT button
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
          child: Column(
            children: [
              _SummaryRow('Subtotal', 'NPR ${fmt.format(subtotal)}'),
              const Divider(height: 16),
              _SummaryRow('Total', 'NPR ${fmt.format(total)}', isBold: true),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Send KOT to Kitchen'),
                  onPressed: cart.isEmpty ? null : onSendKot,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// KOT History Tab — shows all sent KOTs with their items and allows editing
// ════════════════════════════════════════════════════════════════════════════
class _KotHistoryTab extends ConsumerWidget {
  final String sessionId;
  final String tableId;
  final NumberFormat fmt;

  const _KotHistoryTab({
    required this.sessionId,
    required this.tableId,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kotsAsync = ref.watch(sessionKotsProvider(sessionId));

    return kotsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
      data: (kots) {
        if (kots.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.receipt_long_rounded, size: 48, color: AppColors.textHint),
                const SizedBox(height: 12),
                Text('No KOTs sent yet', style: GoogleFonts.outfit(color: AppColors.textHint, fontSize: 13)),
                const SizedBox(height: 6),
                Text('Add items to cart and send a KOT',
                    style: GoogleFonts.outfit(color: AppColors.textHint, fontSize: 11)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: kots.length,
          itemBuilder: (ctx, i) {
            final kot = kots[i];
            return _KotHistoryCard(kot: kot, fmt: fmt)
                .animate()
                .fadeIn(delay: Duration(milliseconds: i * 50));
          },
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Single KOT card in History tab
// ════════════════════════════════════════════════════════════════════════════
class _KotHistoryCard extends ConsumerStatefulWidget {
  final KotWithItems kot;
  final NumberFormat fmt;
  const _KotHistoryCard({required this.kot, required this.fmt});

  @override
  ConsumerState<_KotHistoryCard> createState() => _KotHistoryCardState();
}

class _KotHistoryCardState extends ConsumerState<_KotHistoryCard> {
  bool _expanded = false;

  Color get _statusColor {
    switch (widget.kot.status) {
      case 'pending':
        return AppColors.warning;
      case 'preparing':
        return AppColors.info;
      case 'ready':
        return AppColors.success;
      case 'served':
        return AppColors.textSecondary;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.textHint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt;
    final activeItems = widget.kot.items.where((i) => i['status'] != 'cancelled').toList();
    final kotTotal = activeItems.fold<double>(
      0,
      (sum, i) =>
          sum +
          ((i['quantity'] as num).toDouble() *
              ((i['unit_price'] as num?)?.toDouble() ?? 0.0)),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────────
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.kot.status.toUpperCase(),
                      style: GoogleFonts.outfit(
                        fontSize: 9,
                        color: _statusColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.kot.kotNumber,
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  Text(
                    'NPR ${fmt.format(kotTotal)}',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          // ── Items (expandable) ──────────────────────────────────────────
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                const Divider(height: 1, color: AppColors.border),
                ...widget.kot.items.map((item) {
                  final isCancelled = item['status'] == 'cancelled';
                  final qty = (item['quantity'] as num).toInt();
                  final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                  final itemName = item['menu_item_name'] as String? ?? 'Item';
                  final itemId = item['id'] as String;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        // Cancel / Cancelled indicator
                        if (isCancelled)
                          const Icon(Icons.cancel_rounded, size: 14, color: AppColors.error)
                        else
                          const SizedBox(width: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            itemName,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: isCancelled ? AppColors.textHint : AppColors.textPrimary,
                              decoration: isCancelled ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        // Quantity editor (only for non-cancelled items)
                        if (!isCancelled) ...[
                          _QtyButton(
                            icon: Icons.remove,
                            onTap: () => _editQty(itemId, qty - 1),
                          ),
                          SizedBox(
                            width: 24,
                            child: Text(
                              '$qty',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ),
                          _QtyButton(
                            icon: Icons.add,
                            onTap: () => _editQty(itemId, qty + 1),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'NPR ${fmt.format(qty * unitPrice)}',
                            style: GoogleFonts.outfit(fontSize: 11, color: AppColors.primary),
                          ),
                        ] else
                          Text('Cancelled', style: GoogleFonts.outfit(fontSize: 10, color: AppColors.error)),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Future<void> _editQty(String kotItemId, int newQty) async {
    final messenger = ScaffoldMessenger.of(context);
    if (newQty < 0) return;
    // Confirm if cancelling (qty = 0)
    if (newQty == 0) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Remove Item?',
        message: 'This will cancel this item from the KOT.',
        confirmLabel: 'Cancel Item',
        cancelLabel: 'Keep',
        icon: Icons.remove_shopping_cart_outlined,
      );
      if (!confirmed) return;
    }

    final ok = await ref.read(tableNotifierProvider.notifier).updateKotItem(kotItemId, newQty);
    if (!ok && mounted) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Failed to update item'),
        backgroundColor: AppColors.error,
      ));
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Small qty +/- button
// ════════════════════════════════════════════════════════════════════════════
class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 12, color: AppColors.textSecondary),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Menu Items Grid
// ════════════════════════════════════════════════════════════════════════════
class _MenuItemsGrid extends ConsumerWidget {
  final String categoryId;
  final void Function(MenuItem) onAdd;
  final List<CartItem> cart;

  const _MenuItemsGrid({required this.categoryId, required this.onAdd, required this.cart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(menuItemsProvider(categoryId));
    final fmt = NumberFormat('#,##0');

    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
      data: (items) => items.isEmpty
          ? const Center(child: Text('No items in this category', style: TextStyle(color: AppColors.textSecondary)))
          : _MenuItemsGridView(items: items, cart: cart, onAdd: onAdd, fmt: fmt),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Menu Search Results Grid — filters across every category by name/price/category
// ════════════════════════════════════════════════════════════════════════════
class _MenuSearchResultsGrid extends ConsumerWidget {
  final String branchId;
  final String query;
  final List<MenuCategory> categories;
  final void Function(MenuItem) onAdd;
  final List<CartItem> cart;

  const _MenuSearchResultsGrid({
    required this.branchId,
    required this.query,
    required this.categories,
    required this.onAdd,
    required this.cart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(allMenuItemsProvider(branchId));
    final fmt = NumberFormat('#,##0');
    final q = query.trim().toLowerCase();

    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
      data: (items) {
        final catNameById = {for (final c in categories) c.id: c.name.toLowerCase()};
        final filtered = items.where((item) {
          final nameMatch = item.name.toLowerCase().contains(q);
          final categoryMatch = (catNameById[item.categoryId] ?? '').contains(q);
          final priceMatch =
              item.price.toStringAsFixed(0).contains(q) || item.price.toStringAsFixed(2).contains(q);
          return nameMatch || categoryMatch || priceMatch;
        }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.search_off_rounded, size: 44, color: AppColors.textHint),
                const SizedBox(height: 12),
                Text('No items match "$query"',
                    style: GoogleFonts.outfit(color: AppColors.textHint, fontSize: 13)),
              ],
            ),
          );
        }
        return _MenuItemsGridView(items: filtered, cart: cart, onAdd: onAdd, fmt: fmt);
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Shared grid layout for a resolved list of menu items
// ════════════════════════════════════════════════════════════════════════════
class _MenuItemsGridView extends StatelessWidget {
  final List<MenuItem> items;
  final List<CartItem> cart;
  final void Function(MenuItem) onAdd;
  final NumberFormat fmt;

  const _MenuItemsGridView({required this.items, required this.cart, required this.onAdd, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: context.responsiveValue(mobile: 168, tablet: 190, desktop: 210),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.74,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        final inCart = cart.where((c) => c.item.id == item.id).toList();
        final qty = inCart.isNotEmpty ? inCart.first.quantity : 0;
        return _MenuItemCardTile(item: item, qty: qty, fmt: fmt, onTap: () => onAdd(item))
            .animate()
            .fadeIn(delay: Duration(milliseconds: i * 30))
            .scale(begin: const Offset(0.9, 0.9));
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Single menu item card (image on top, name + price below)
// ════════════════════════════════════════════════════════════════════════════
class _MenuItemCardTile extends StatelessWidget {
  final MenuItem item;
  final int qty;
  final NumberFormat fmt;
  final VoidCallback onTap;

  const _MenuItemCardTile({required this.item, required this.qty, required this.fmt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: qty > 0 ? AppColors.primary.withValues(alpha: 0.06) : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: qty > 0 ? AppColors.primary : AppColors.border,
            width: qty > 0 ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  hasImage
                      ? Image.network(
                          item.imageUrl!,
                          fit: BoxFit.cover,
                          loadingBuilder: (ctx, child, progress) {
                            if (progress == null) return child;
                            return const _ImageLoadingPlaceholder();
                          },
                          errorBuilder: (_, __, ___) => const _MenuImagePlaceholder(),
                        )
                      : const _MenuImagePlaceholder(),
                  if (qty > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(qty.toString(),
                            style: GoogleFonts.outfit(
                                fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                          fontSize: 13, fontWeight: FontWeight.w600, height: 1.2, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text('NPR ${fmt.format(item.price)}',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Menu image placeholder / loading states — shared professional fallback
// ════════════════════════════════════════════════════════════════════════════
class _MenuImagePlaceholder extends StatelessWidget {
  const _MenuImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.10), AppColors.primary.withValues(alpha: 0.03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.restaurant_rounded, color: AppColors.primary, size: 28),
      ),
    );
  }
}

class _ImageLoadingPlaceholder extends StatelessWidget {
  const _ImageLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceVariant,
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Cart Item Tile
// ════════════════════════════════════════════════════════════════════════════
class _CartItemTile extends StatelessWidget {
  final CartItem cartItem;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;
  final NumberFormat fmt;

  const _CartItemTile({
    required this.cartItem,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cartItem.item.name,
                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                Text('NPR ${fmt.format(cartItem.total)}',
                    style: GoogleFonts.outfit(fontSize: 12, color: AppColors.primary)),
              ],
            ),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: onDecrease,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.remove, size: 14, color: AppColors.textSecondary),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(cartItem.quantity.toString(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              GestureDetector(
                onTap: onIncrease,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.add, size: 14, color: AppColors.onPrimary),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.close, size: 16, color: AppColors.error),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Summary Row
// ════════════════════════════════════════════════════════════════════════════
class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _SummaryRow(this.label, this.value, {this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.outfit(
              fontSize: isBold ? 15 : 13,
              color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
            )),
        Text(value,
            style: GoogleFonts.outfit(
              fontSize: isBold ? 16 : 13,
              color: isBold ? AppColors.primary : AppColors.textSecondary,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            )),
      ],
    );
  }
}
