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
import '../../../suppliers/presentation/screens/supplier_screen.dart' show suppliersProvider;

final purchasesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.purchases,
    queryParameters: {'branchId': profile!.branchId!, 'limit': '100'},
  );
  final data = response.data as Map<String, dynamic>;
  return List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
});

/// Supplier name for a purchase row — prefers the linked Supplier record,
/// falling back to the denormalized name stored on the purchase itself.
String _supplierNameOf(Map<String, dynamic> p) {
  final linked = (p['supplier'] as Map<String, dynamic>?)?['name'] as String?;
  final denorm = p['supplier_name'] as String?;
  return linked ?? denorm ?? 'Unknown Supplier';
}

class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key});
  @override
  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends ConsumerState<PurchaseScreen> {
  final fmt = NumberFormat('#,##0.00');

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(purchasesProvider);
    final purchases = purchasesAsync.value ?? [];
    final totalSpend = purchases.fold<double>(0, (s, p) => s + ((p['total_amount'] as num?)?.toDouble() ?? 0));

    // Today's spend, so the manager sees the same "that day purchase" figure
    // that rolls up into the daily report.
    final todayStart = DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
    final todaySpend = purchases.where((p) {
      final dt = DateTime.tryParse(p['created_at'] as String? ?? '');
      return dt != null && !dt.isBefore(todayStart);
    }).fold<double>(0, (s, p) => s + ((p['total_amount'] as num?)?.toDouble() ?? 0));

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
              child: const Icon(Icons.shopping_cart,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Purchase Management',
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
          TextButton.icon(icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New Purchase'), onPressed: () => _showAddDialog(context)),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.surface, padding: const EdgeInsets.all(16),
            child: Row(children: [
              _SC("Today's Purchases", 'NPR ${fmt.format(todaySpend)}', AppColors.primary),
              const SizedBox(width: 12),
              _SC('Total Spent', 'NPR ${fmt.format(totalSpend)}', AppColors.error),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: purchasesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
            data: (_) => purchases.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.shopping_cart_outlined, size: 64, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  Text('No purchases recorded', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: () => _showAddDialog(context), child: const Text('Record Purchase')),
                ]))
              : ResponsiveContent(child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: purchases.length,
                  itemBuilder: (ctx, i) {
                    final p = purchases[i];
                    // Backend stores created_at in UTC (ISO ...Z); convert to
                    // the device's local zone so the time reads correctly.
                    final createdAt = DateTime.tryParse(p['created_at'] as String? ?? '')?.toLocal();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                      child: Row(children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.receipt_long_rounded, color: AppColors.info, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_supplierNameOf(p), style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          Text((p['notes'] as String?)?.isNotEmpty == true ? p['notes'] as String : 'Purchase order',
                              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('NPR ${fmt.format((p['total_amount'] as num?)?.toDouble() ?? 0)}', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          if (createdAt != null) ...[
                            Text(DateFormat('dd MMM yyyy').format(createdAt),
                                style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary)),
                            Text(DateFormat('hh:mm a').format(createdAt),
                                style: GoogleFonts.outfit(fontSize: 10, color: AppColors.textHint)),
                          ],
                        ]),
                      ]),
                    ).animate().fadeIn(delay: Duration(milliseconds: i * 25));
                  },
                )),
          )),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final profile = ref.read(authNotifierProvider).value;
    if (profile?.branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still loading your session — try again in a moment.')),
      );
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddPurchaseDialog(branchId: profile!.branchId!),
    );
    if (saved == true) ref.invalidate(purchasesProvider);
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  RECORD PURCHASE DIALOG
//  Supplier is picked from the branch's Supplier records (auto-loaded);
//  the record is saved with the exact server date & time and broadcast
//  live via the `purchase:created` socket event.
// ═══════════════════════════════════════════════════════════════════════
class _AddPurchaseDialog extends ConsumerStatefulWidget {
  final String branchId;
  const _AddPurchaseDialog({required this.branchId});

  @override
  ConsumerState<_AddPurchaseDialog> createState() => _AddPurchaseDialogState();
}

class _AddPurchaseDialogState extends ConsumerState<_AddPurchaseDialog> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  Map<String, dynamic>? _supplier;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (_supplier == null) {
      setState(() => _error = 'Please select a supplier');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid total amount');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ApiClient.instance.post(
        ApiConstants.purchases,
        data: {
          'branchId': widget.branchId,
          'supplierId': _supplier!['id'],
          // Denormalized so the list/report still shows a name even if the
          // supplier record is later renamed or removed.
          'supplierName': _supplier!['name'],
          'totalAmount': amount,
          if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersProvider);

    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.receipt_long_rounded, color: AppColors.primary),
        const SizedBox(width: 10),
        Text('Record Purchase', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
      ]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            suppliersAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
              error: (e, _) => Text('Could not load suppliers: $e', style: const TextStyle(color: AppColors.error, fontSize: 12)),
              data: (suppliers) {
                if (suppliers.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'No suppliers found. Add a supplier in the Suppliers section first, then record the purchase here.',
                      style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                    ),
                  );
                }
                return DropdownButtonFormField<String>(
                  initialValue: _supplier?['id'] as String?,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Supplier *'),
                  hint: const Text('Select a supplier'),
                  items: suppliers
                      .map((s) => DropdownMenuItem<String>(
                            value: s['id'] as String,
                            child: Text(s['name'] as String? ?? 'Unnamed', overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setState(
                    () => _supplier = suppliers.firstWhere((s) => s['id'] == v),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Total Amount (NPR) *', prefixText: 'NPR '),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _SC extends StatelessWidget {
  final String l, v; final Color c;
  const _SC(this.l, this.v, this.c);
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l, style: GoogleFonts.outfit(fontSize: 11, color: c)),
      Text(v, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
    ]),
  ));
}
