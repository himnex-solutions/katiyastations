import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_time_utils.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/offline/connectivity_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:katiya_station_rms/features/cashier/domain/entities/bill_entities.dart';
import '../../../../core/widgets/notification_bell.dart';

final billsStreamProvider =
    FutureProvider.family<List<Bill>, DateTimeRange?>((ref, range) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  // Payment history lives on the server; offline, return empty instantly
  // instead of hanging on a call that will time out.
  if (!ref.read(connectivityProvider)) return const [];
  final response = await ApiClient.instance.get(
    ApiConstants.paymentHistory,
    queryParameters: {'branchId': profile!.branchId!, 'limit': '100'},
  );
  final data = response.data as Map<String, dynamic>;
  final rows = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
  return rows.map((r) => Bill.fromJson(r)).where((b) {
    if (range == null) return true;
    return b.createdAt.isAfter(range.start) &&
        b.createdAt.isBefore(range.end.add(const Duration(days: 1)));
  }).toList();
});

class PaymentHistoryScreen extends ConsumerStatefulWidget {
  const PaymentHistoryScreen({super.key});
  @override
  ConsumerState<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends ConsumerState<PaymentHistoryScreen> {
  DateTimeRange? _range;
  String _search = '';
  String _methodFilter = 'all';
  final fmt = NumberFormat('#,##0.00');

  @override
  Widget build(BuildContext context) {
    final billsAsync = ref.watch(billsStreamProvider(_range));
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
              child: const Icon(Icons.receipt_long,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Payment History',
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
          TextButton.icon(
            icon: const Icon(Icons.date_range_rounded, size: 16),
            label: Text(_range == null ? 'All Time' : '${DateFormat('dd MMM').format(_range!.start)} – ${DateFormat('dd MMM').format(_range!.end)}'),
            onPressed: _pickRange,
          ),
          if (_range != null)
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _range = null)),
          const NotificationBell(),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(hintText: 'Search invoice / customer...', prefixIcon: Icon(Icons.search, size: 18), isDense: true),
                    onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _methodFilter,
                  dropdownColor: AppColors.surface,
                  style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 13),
                  underline: const SizedBox(),
                  onChanged: (v) => setState(() => _methodFilter = v!),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Methods')),
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'card', child: Text('Card')),
                    DropdownMenuItem(value: 'esewa', child: Text('eSewa')),
                    DropdownMenuItem(value: 'khalti', child: Text('Khalti')),
                    DropdownMenuItem(value: 'fonepay', child: Text('FonePay')),
                    DropdownMenuItem(value: 'credit', child: Text('Credit')),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          billsAsync.when(
            loading: () => const SizedBox(height: 80, child: LinearProgressIndicator()),
            error: (_, __) => const SizedBox(),
            data: (bills) {
              final f = _filter(bills);
              final revenue = f.where((b) => b.paymentStatus == 'paid').fold(0.0, (s, b) => s + b.totalAmount);
              final credit = f.where((b) => b.paymentStatus == 'credit').fold(0.0, (s, b) => s + b.totalAmount);
              return Container(
                color: AppColors.surface,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  _SCard('Revenue', 'NPR ${fmt.format(revenue)}', AppColors.success),
                  const SizedBox(width: 10),
                  _SCard('Credit', 'NPR ${fmt.format(credit)}', AppColors.warning),
                  const SizedBox(width: 10),
                  _SCard('Transactions', '${f.length}', AppColors.info),
                ]),
              );
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: billsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
              data: (bills) {
                final f = _filter(bills);
                if (f.isEmpty) return Center(child: Text('No payments found', style: GoogleFonts.outfit(color: AppColors.textSecondary)));
                final role = ref.watch(authNotifierProvider).value?.role;
                final canRefund = role == 'branch_manager' || role == 'accountant';
                return ResponsiveContent(child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: f.length,
                  itemBuilder: (ctx, i) {
                    final bill = f[i];
                    final reversible = canRefund &&
                        bill.paymentStatus != 'refunded' &&
                        bill.paymentStatus != 'voided';
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: reversible ? () => _showRefundSheet(bill) : null,
                      child: _PaymentCard(bill: bill, fmt: fmt),
                    ).animate().fadeIn(delay: Duration(milliseconds: i * 25));
                  },
                ));
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Bill> _filter(List<Bill> bills) => bills.where((b) {
    final s = _search.isEmpty || b.invoiceNumber.toLowerCase().contains(_search) || (b.customerName?.toLowerCase().contains(_search) ?? false);
    final m = _methodFilter == 'all' || b.paymentMethod == _methodFilter;
    return s && m;
  }).toList();

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime.now(), initialDateRange: _range);
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _showRefundSheet(Bill bill) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _RefundSheet(bill: bill, fmt: fmt),
    );
    if (result == true) {
      ref.invalidate(billsStreamProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bill reversed & stock restored'), backgroundColor: AppColors.success),
        );
      }
    }
  }
}

/// Manager-only sheet to void (raised in error) or refund (money returned) a
/// settled bill. Requires a reason; the backend reverses money, credit and the
/// stock deducted at order time.
class _RefundSheet extends ConsumerStatefulWidget {
  final Bill bill;
  final NumberFormat fmt;
  const _RefundSheet({required this.bill, required this.fmt});
  @override
  ConsumerState<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends ConsumerState<_RefundSheet> {
  String _type = 'refund';
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason.text.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a reason (min 3 characters)'), backgroundColor: AppColors.error),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiClient.instance.post(
        ApiConstants.refundBill(widget.bill.id),
        data: {'type': _type, 'reason': _reason.text.trim()},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.undo_rounded, color: AppColors.error, size: 20),
          const SizedBox(width: 8),
          Text('Void / Refund Bill', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ]),
        const SizedBox(height: 4),
        Text('${widget.bill.invoiceNumber} • NPR ${widget.fmt.format(widget.bill.totalAmount)} • ${widget.bill.paymentMethod.toUpperCase()}',
            style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'refund', label: Text('Refund'), icon: Icon(Icons.payments_outlined, size: 16)),
            ButtonSegment(value: 'void', label: Text('Void'), icon: Icon(Icons.block_flipped, size: 16)),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        const SizedBox(height: 8),
        Text(
          _type == 'refund'
              ? 'Money is returned to the customer. Ingredients & bar pegs are restored.'
              : 'Bill was raised in error. Money, credit & stock are all reversed.',
          style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _reason,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Reason *',
            hintText: 'e.g. wrong table billed, customer complaint...',
            isDense: true,
          ),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_type == 'refund' ? 'Confirm Refund' : 'Confirm Void'),
          )),
        ]),
      ]),
    );
  }
}

class _SCard extends StatelessWidget {
  final String label, value; final Color color;
  const _SCard(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.outfit(fontSize: 11, color: color)),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ]),
    ));
  }
}

class _PaymentCard extends StatelessWidget {
  final Bill bill; final NumberFormat fmt;
  const _PaymentCard({required this.bill, required this.fmt});

  Color get _sc {
    switch (bill.paymentStatus) {
      case 'paid': return AppColors.success;
      case 'credit': return AppColors.warning;
      case 'refunded': return AppColors.error;
      case 'voided': return AppColors.error;
      default: return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: _sc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.receipt_rounded, color: _sc, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(bill.invoiceNumber, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          Text('${bill.customerName ?? 'Walk-in'} • ${bill.paymentMethod.toUpperCase()} • ${formatShortDateTime(bill.createdAt)}',
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('NPR ${fmt.format(bill.totalAmount)}', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          Container(
            margin: const EdgeInsets.only(top: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: _sc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(bill.paymentStatus.toUpperCase(), style: GoogleFonts.outfit(fontSize: 10, color: _sc, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}
