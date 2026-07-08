import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart' hide ShimmerEffect;
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/widgets/thermal_receipt.dart';
import '../providers/kitchen_provider.dart';
import '../../../orders/domain/entities/order_entities.dart';
import '../../../orders/presentation/providers/order_provider.dart';
import '../../../branches/presentation/providers/branch_provider.dart';

class KitchenScreen extends ConsumerWidget {
  const KitchenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kotsAsync = ref.watch(kitchenKotsProvider);
    // Pre-warm branch info so it's already loaded by the time a KOT ticket
    // needs to print it.
    ref.watch(currentBranchProvider);
    final isMobile = context.isMobile;

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
              child: const Icon(Icons.soup_kitchen,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Kitchen Display System',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppColors.textPrimary)),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: kotsAsync.when(
              data: (kots) => Text(
                '${kots.length} Active KOTs',
                style: GoogleFonts.outfit(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              error: (_, __) => const SizedBox(),
            ),
          ),
        ],
      ),
      body: kotsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
        data: (kots) {
          if (kots.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Lottie.network(
                    'https://assets9.lottiefiles.com/packages/lf20_touohxv0.json',
                    width: 220,
                    height: 220,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 80,
                      color: AppColors.success,
                    ),
                  ),
                  Text(
                    'All caught up!',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2),
                  const SizedBox(height: 8),
                  Text(
                    'No pending kitchen orders',
                    style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 15),
                  ).animate().fadeIn(delay: 350.ms),
                ],
              ),
            );
          }

          final pending = kots.where((k) => k.isPending).toList();
          final preparing = kots.where((k) => k.isPreparing).toList();
          final ready = kots.where((k) => k.isReady).toList();

          // Mobile: TabBar layout to avoid crushing 3 columns
          if (isMobile) {
            return _KitchenTabView(
              pending: pending,
              preparing: preparing,
              ready: ready,
              ref: ref,
            );
          }

          // Tablet/Desktop: 3-column Kanban
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KanbanColumn(
                title: 'Pending',
                icon: Icons.hourglass_empty_rounded,
                color: AppColors.warning,
                kots: pending,
                nextStatus: 'preparing',
                nextLabel: 'Start Preparing',
                ref: ref,
              ),
              _KanbanColumn(
                title: 'Preparing',
                icon: Icons.whatshot_rounded,
                color: AppColors.info,
                kots: preparing,
                nextStatus: 'ready',
                nextLabel: 'Mark Ready',
                ref: ref,
              ),
              _KanbanColumn(
                title: 'Ready to Serve',
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
                kots: ready,
                nextStatus: 'served',
                nextLabel: 'Mark Served',
                ref: ref,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Mobile: Tab-based layout
// ═══════════════════════════════════════════════════════════════════════════
class _KitchenTabView extends StatefulWidget {
  final List<Kot> pending;
  final List<Kot> preparing;
  final List<Kot> ready;
  final WidgetRef ref;

  const _KitchenTabView({
    required this.pending,
    required this.preparing,
    required this.ready,
    required this.ref,
  });

  @override
  State<_KitchenTabView> createState() => _KitchenTabViewState();
}

class _KitchenTabViewState extends State<_KitchenTabView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _badge(int count, Color color) => count == 0
      ? const SizedBox.shrink()
      : Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.outfit(
                fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
          ),
        );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
            unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w400, fontSize: 13),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.hourglass_empty_rounded, size: 16),
                    const SizedBox(width: 4),
                    const Text('Pending'),
                    _badge(widget.pending.length, AppColors.warning),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.whatshot_rounded, size: 16),
                    const SizedBox(width: 4),
                    const Text('Preparing'),
                    _badge(widget.preparing.length, AppColors.info),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 16),
                    const SizedBox(width: 4),
                    const Text('Ready'),
                    _badge(widget.ready.length, AppColors.success),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _KotList(kots: widget.pending, nextStatus: 'preparing', nextLabel: 'Start Preparing', color: AppColors.warning, ref: widget.ref),
              _KotList(kots: widget.preparing, nextStatus: 'ready', nextLabel: 'Mark Ready', color: AppColors.info, ref: widget.ref),
              _KotList(kots: widget.ready, nextStatus: 'served', nextLabel: 'Mark Served', color: AppColors.success, ref: widget.ref),
            ],
          ),
        ),
      ],
    );
  }
}

class _KotList extends StatelessWidget {
  final List<Kot> kots;
  final String nextStatus;
  final String nextLabel;
  final Color color;
  final WidgetRef ref;

  const _KotList({
    required this.kots,
    required this.nextStatus,
    required this.nextLabel,
    required this.color,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    if (kots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 52, color: color.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('No orders here', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: kots.length,
      itemBuilder: (ctx, i) => _KotCard(
        kot: kots[i],
        nextStatus: nextStatus,
        nextLabel: nextLabel,
        color: color,
        ref: ref,
      ).animate().fadeIn(delay: Duration(milliseconds: i * 50)).slideY(begin: 0.1),
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Kot> kots;
  final String nextStatus;
  final String nextLabel;
  final WidgetRef ref;

  const _KanbanColumn({
    required this.title,
    required this.icon,
    required this.color,
    required this.kots,
    required this.nextStatus,
    required this.nextLabel,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(title,
                      style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(kots.length.toString(),
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: kots.length,
                itemBuilder: (ctx, i) => _KotCard(
                  kot: kots[i],
                  nextStatus: nextStatus,
                  nextLabel: nextLabel,
                  color: color,
                  ref: ref,
                ).animate().fadeIn(delay: Duration(milliseconds: i * 50)).slideX(begin: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KotCard extends ConsumerWidget {
  final Kot kot;
  final String nextStatus;
  final String nextLabel;
  final Color color;
  final WidgetRef ref;

  const _KotCard({
    required this.kot,
    required this.nextStatus,
    required this.nextLabel,
    required this.color,
    required this.ref,
  });

  String _elapsedLabel() {
    final mins = kot.elapsed.inMinutes;
    if (mins < 1) return 'Just now';
    return '${mins}m ago';
  }

  Color _elapsedColor() {
    final mins = kot.elapsed.inMinutes;
    if (mins < 10) return AppColors.success;
    if (mins < 20) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(kotItemsProvider(kot.id));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Text(kot.kotNumber,
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(width: 8),
                const Icon(Icons.table_restaurant_rounded, size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 3),
                Expanded(child: Text(
                    kot.tableNumber != null ? 'Table ${kot.tableNumber}' : 'Table —',
                    style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _elapsedColor().withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_elapsedLabel(),
                      style: GoogleFonts.outfit(fontSize: 10, color: _elapsedColor(), fontWeight: FontWeight.w600)),
                ),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.print_rounded, size: 16, color: AppColors.textSecondary),
                    tooltip: 'Print KOT',
                    onPressed: () {
                      final items = itemsAsync.value ?? const <KotItem>[];
                      _printKot(context, ref, items);
                    },
                  ),
                ),
              ],
            ),
          ),
          // Items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: itemsAsync.when(
              loading: () => Skeletonizer(
                enabled: true,
                effect: const ShimmerEffect(
                  baseColor: AppColors.surfaceVariant,
                  highlightColor: AppColors.surface,
                ),
                child: Column(
                  children: List.generate(3, (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Container(width: 24, height: 24, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(6))),
                      const SizedBox(width: 8),
                      Container(height: 13, width: 120, color: AppColors.surfaceVariant),
                    ]),
                  )),
                ),
              ),
              error: (e, _) => const Text('Error loading items', style: TextStyle(color: AppColors.error, fontSize: 12)),
              data: (items) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text('×${item.quantity}',
                            style: GoogleFonts.outfit(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item.menuItemName,
                          style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary))),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ),
          if (kot.notes != null && kot.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('📝 ${kot.notes}',
                    style: GoogleFonts.outfit(fontSize: 11, color: AppColors.warning)),
              ),
            ),
          // Action button
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  ref.read(kitchenNotifierProvider.notifier)
                      .updateKotStatus(kot.id, nextStatus);
                  ref.invalidate(sessionKotsProvider(kot.sessionId));
                },
                child: Text(nextLabel, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  PRINT KOT — kitchen ticket, no prices, real branch name.
  // ─────────────────────────────────────────────────────────
  void _printKot(BuildContext context, WidgetRef ref, List<KotItem> items) {
    final branch = ref.read(currentBranchProvider).value;
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(kot.createdAt);

    showThermalPrintDialog(
      context,
      title: 'KOT Print Preview',
      onPrint: () => showPrintSentSnackbar(context, label: 'KOT sent to kitchen printer!'),
      receipt: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          receiptBranchHeader(branch),
          receiptDivider(),
          const SizedBox(height: 4),
          Text('KITCHEN ORDER TICKET',
              textAlign: TextAlign.center, style: receiptStyle(fontSize: 12, weight: FontWeight.bold)),
          const SizedBox(height: 4),
          receiptRow('KOT No:', kot.kotNumber, weight: FontWeight.bold),
          receiptRow('Table:', kot.tableNumber ?? '—'),
          receiptRow('Waiter:', kot.waiterName ?? '—'),
          receiptRow('Time:', dateStr),
          const SizedBox(height: 4),
          receiptDivider(),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Text('No items', textAlign: TextAlign.center, style: receiptStyle())
          else
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${item.quantity} x ${item.menuItemName}',
                          style: receiptStyle(fontSize: 13, weight: FontWeight.bold)),
                      if (item.notes != null && item.notes!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 14),
                          child: Text('- ${item.notes}', style: receiptStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                )),
          if (kot.notes != null && kot.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            receiptDivider(),
            const SizedBox(height: 4),
            Text('Note: ${kot.notes}', style: receiptStyle(fontSize: 11)),
          ],
        ],
      ),
    );
  }
}
