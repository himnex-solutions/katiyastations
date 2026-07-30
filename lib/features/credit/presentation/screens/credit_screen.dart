import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import 'package:katiya_station_rms/features/cashier/domain/entities/bill_entities.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../../core/widgets/notification_bell.dart';

final creditProvider = FutureProvider<List<CreditRecord>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final branchId = profile!.branchId!;

  // `/credits` is paginated and defaults to 20 rows. Sending no limit once
  // capped this list at 20 accounts — so an older/other account never loaded and
  // the search below couldn't find what was never fetched. Walk every page (100
  // is the backend's @Max) so search covers ALL credit accounts.
  final all = <CreditRecord>[];
  var page = 1;
  while (true) {
    final response = await ApiClient.instance.get(
      ApiConstants.credits,
      queryParameters: {'branchId': branchId, 'page': '$page', 'limit': '100'},
    );
    final data = response.data as Map<String, dynamic>;
    final rows = (data['data'] as List?) ?? const [];
    all.addAll(
      rows.map((r) => CreditRecord.fromJson(r as Map<String, dynamic>)),
    );
    // Stop on a short page — independent of the server's meta/totalPages.
    if (rows.length < 100) break;
    page++;
  }
  return all;
});

class CreditScreen extends ConsumerStatefulWidget {
  const CreditScreen({super.key});
  @override
  ConsumerState<CreditScreen> createState() => _CreditScreenState();
}

class _CreditScreenState extends ConsumerState<CreditScreen> {
  String _statusFilter = 'all';
  String _search = '';
  final _searchCtrl = TextEditingController();
  final fmt = NumberFormat('#,##0.00');

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final creditsAsync = ref.watch(creditProvider);

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
              child: const Icon(Icons.credit_card,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Credit (Udhaaro) Management',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppColors.textPrimary)),
            ),
          ],
        ),
        actions: const [
          NotificationBell(),
        ],
      ),
      body: Column(
        children: [
          creditsAsync.when(
            loading: () => const SizedBox(height: 80, child: LinearProgressIndicator()),
            error: (_, __) => const SizedBox(),
            data: (credits) {
              final outstanding = credits.where((c) => c.status != 'paid').fold<double>(0, (s, c) => s + c.outstanding);
              final overdue = credits.where((c) => c.isOverdue).length;
              return Container(
                color: AppColors.surface, padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(children: [
                      _SC('Outstanding', 'NPR ${fmt.format(outstanding)}', AppColors.error),
                      const SizedBox(width: 12),
                      _SC('Overdue', '$overdue accounts', AppColors.warning),
                      const SizedBox(width: 12),
                      _SC('Total Accounts', '${credits.length}', AppColors.info),
                    ]),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: ['all', 'pending', 'partial_paid', 'paid', 'overdue'].map((s) => GestureDetector(
                      onTap: () => setState(() => _statusFilter = s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _statusFilter == s ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _statusFilter == s ? AppColors.primary : AppColors.border),
                        ),
                        child: Text(s == 'all' ? 'All' : s.replaceAll('_', ' ').toUpperCase(),
                            style: GoogleFonts.outfit(fontSize: 11, color: _statusFilter == s ? AppColors.primary : AppColors.textSecondary)),
                      ),
                    )).toList()),
                    ),
                  ],
                ),
              );
            },
          ),
          // Search by customer name or phone across every credit account.
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search by name or phone number',
                hintStyle: GoogleFonts.outfit(fontSize: 13, color: AppColors.textHint),
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textSecondary),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
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
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: creditsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (credits) {
                var filtered = _statusFilter == 'all' ? credits : credits.where((c) => _statusFilter == 'overdue' ? c.isOverdue : c.status == _statusFilter).toList();
                if (_search.isNotEmpty) {
                  filtered = filtered.where((c) =>
                      c.customerName.toLowerCase().contains(_search) ||
                      (c.customerPhone ?? '').toLowerCase().contains(_search)).toList();
                }
                if (filtered.isEmpty) {
                  return Center(
                      child: Text(_search.isEmpty ? 'No credit records' : 'No match for "$_search"',
                          style: GoogleFonts.outfit(color: AppColors.textSecondary)));
                }
                return ResponsiveContent(child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) => _CreditCard(credit: filtered[i], fmt: fmt, ref: ref).animate().fadeIn(delay: Duration(milliseconds: i * 25)),
                ));
              },
            ),
          ),
        ],
      ),
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
      Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 11, color: c)),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(v, maxLines: 1, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ),
    ]),
  ));
}

class _CreditCard extends StatelessWidget {
  final CreditRecord credit; final NumberFormat fmt; final WidgetRef ref;
  const _CreditCard({required this.credit, required this.fmt, required this.ref});

  Color get _sc {
    if (credit.isOverdue) return AppColors.error;
    if (credit.status == 'paid') return AppColors.success;
    if (credit.status == 'partial_paid') return AppColors.warning;
    return AppColors.info;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _sc.withValues(alpha: 0.2))),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: _sc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.person_rounded, color: AppColors.textSecondary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(credit.customerName, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                if (credit.customerPhone != null)
                  Text(credit.customerPhone!, style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('NPR ${fmt.format(credit.outstanding)}', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: _sc)),
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: _sc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(credit.isOverdue ? 'OVERDUE' : credit.status.toUpperCase(),
                      style: GoogleFonts.outfit(fontSize: 10, color: _sc, fontWeight: FontWeight.w600)),
                ),
              ]),
            ]),
          ),
          if (credit.status != 'paid')
            Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
              child: Row(children: [
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.payment_rounded, size: 16, color: AppColors.success),
                    label: Text('Collect Payment', style: GoogleFonts.outfit(color: AppColors.success, fontSize: 13)),
                    onPressed: () => _showCollectDialog(context),
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  void _showCollectDialog(BuildContext context) {
    final amountCtrl = TextEditingController(text: credit.outstanding.toStringAsFixed(2));
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Collect Payment'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Outstanding: NPR ${NumberFormat('#,##0.00').format(credit.outstanding)}',
            style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount Collected')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () async {
          final collected = double.tryParse(amountCtrl.text) ?? 0;
          await ApiClient.instance.post(
            ApiConstants.settleCredit(credit.id),
            data: {'amount': collected},
          );
          ref.invalidate(creditProvider);
          ref.invalidate(dashboardCreditProvider);
          if (context.mounted) Navigator.pop(ctx);
        }, child: const Text('Confirm')),
      ],
    ));
  }
}
