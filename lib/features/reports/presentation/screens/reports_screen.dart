// ============================================================
// KATIYA STATION RMS — REPORTS & EXPORT
// Manager / Accountant see a full financial report; Cashier sees a
// sales & collections report. Both can print or download a professional
// PDF / Excel for Daily, Weekly, Monthly or Yearly periods. Totals come
// from the server-side aggregate (/reports/summary) so they stay accurate
// for any range regardless of transaction volume.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../branches/presentation/providers/branch_provider.dart';
import '../../../purchase/presentation/screens/purchase_screen.dart' show purchasesProvider;
import '../report_export.dart';

const _timeframes = ['Daily', 'Weekly', 'Monthly', 'Yearly'];

const _roleLabels = {
  'branch_manager': 'Manager',
  'accountant': 'Accountant',
  'cashier': 'Cashier',
};

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final _fmt = NumberFormat('#,##0.00');
  String _timeframe = 'Daily';
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  (DateTime, DateTime) _range() {
    final now = DateTime.now();
    switch (_timeframe) {
      case 'Weekly':
        return (now.subtract(const Duration(days: 7)), now);
      case 'Monthly':
        return (DateTime(now.year, now.month, 1), now);
      case 'Yearly':
        return (DateTime(now.year, 1, 1), now);
      case 'Daily':
      default:
        return (DateTime(now.year, now.month, now.day), now);
    }
  }

  Future<void> _load() async {
    final profile = ref.read(authNotifierProvider).value;
    if (profile?.branchId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final (start, end) = _range();
    try {
      final res = await ApiClient.instance.get(
        ApiConstants.reportSummary,
        queryParameters: {
          'branchId': profile!.branchId!,
          'from': start.toUtc().toIso8601String(),
          'to': end.toUtc().toIso8601String(),
        },
      );
      final summary = res.data as Map<String, dynamic>;

      // Recent bills in range for the export's detail table (best-effort).
      List<Map<String, dynamic>> txns = [];
      try {
        final billsRes = await ApiClient.instance.get(
          ApiConstants.bills,
          queryParameters: {'branchId': profile.branchId!, 'limit': '100'},
        );
        final data = billsRes.data as Map<String, dynamic>;
        txns = List<Map<String, dynamic>>.from(data['data'] as List? ?? []).where((b) {
          final dt = DateTime.tryParse(b['created_at'] as String? ?? '');
          return dt != null && !dt.isBefore(start) && !dt.isAfter(end);
        }).toList();
      } catch (_) {
        // Detail table is optional; summary totals still stand.
      }

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _transactions = txns;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  double _d(String key) => (_summary?[key] as num?)?.toDouble() ?? 0;
  int _i(String key) => (_summary?[key] as num?)?.toInt() ?? 0;
  bool get _includesFinancials => _summary?['includes_financials'] == true;

  ReportData _buildReportData() {
    final (start, end) = _range();
    final profile = ref.read(authNotifierProvider).value;
    final branch = ref.read(currentBranchProvider).valueOrNull;
    final roleLabel = _roleLabels[profile?.role] ?? 'Staff';

    final sales = _d('sales');
    final netProfit = _d('net_profit');

    final byMethod = ((_summary?['by_payment_method'] as List?) ?? [])
        .map((e) => ReportPaymentRow(
              (e['payment_method'] as String?) ?? '—',
              (e['count'] as num?)?.toInt() ?? 0,
              (e['total_amount'] as num?)?.toDouble() ?? 0,
            ))
        .toList();

    return ReportData(
      title: _includesFinancials ? 'Financial Report' : 'Sales Report',
      branchName: (branch?['name'] as String?) ?? 'Branch',
      generatedBy: '${profile?.fullName ?? 'User'} ($roleLabel)',
      timeframe: _timeframe,
      rangeStart: start,
      rangeEnd: end,
      summary: [
        ReportMetric('Gross Sales', _d('gross_sales')),
        ReportMetric('Collected (Paid)', sales),
        ReportMetric('Outstanding Credit', _d('credit')),
        ReportMetric('Discounts Given', _d('discount')),
        if (_includesFinancials) ReportMetric('Expenses', _d('expenses')),
        if (_includesFinancials) ReportMetric('Purchases', _d('purchases')),
        if (_includesFinancials) ReportMetric('Net Profit', netProfit),
        ReportMetric('Total Invoices', _i('bill_count').toDouble(), isCount: true),
      ],
      paymentBreakdown: byMethod,
      transactions: _transactions,
      highlightLabel: _includesFinancials ? 'Net Profit' : 'Total Collected',
      highlightValue: _includesFinancials ? netProfit : sales,
    );
  }

  Future<void> _export(Future<void> Function(ReportData) action, String label) async {
    if (_summary == null || _exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(_buildReportData());
    } on ExportNotice catch (n) {
      // Expected fallback (e.g. print → PDF download); inform, don't alarm.
      messenger.showSnackBar(
        SnackBar(content: Text(n.message), backgroundColor: AppColors.info),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('$label failed: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authNotifierProvider).value?.role;
    // Keep a manager/accountant's report live when a purchase is recorded
    // elsewhere (cashiers have no purchase access, so skip the listen).
    if (role == 'branch_manager' || role == 'accountant') {
      ref.listen(purchasesProvider, (_, __) {
        if (mounted && !_loading) _load();
      });
    }

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
              child: const Icon(Icons.bar_chart,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Reports & Analytics',
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
          DropdownButton<String>(
            value: _timeframe,
            dropdownColor: AppColors.surface,
            style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 13),
            underline: const SizedBox(),
            onChanged: (v) {
              if (v == null || v == _timeframe) return;
              setState(() => _timeframe = v);
              _load();
            },
            items: _timeframes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                      const SizedBox(height: 12),
                      Text('Could not load report', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _load, child: const Text('Retry')),
                    ]),
                  ),
                )
              : _buildReport(),
    );
  }

  Widget _buildReport() {
    final sales = _d('sales');
    final credit = _d('credit');
    final gross = _d('gross_sales');
    final netProfit = _d('net_profit');
    final profitColor = netProfit >= 0 ? AppColors.success : AppColors.error;
    final byMethod = (_summary?['by_payment_method'] as List?) ?? [];

    return ResponsiveContent(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ExportBar(
            exporting: _exporting,
            onPrint: () => _export(printReport, 'Print'),
            onPdf: () => _export(downloadReportPdf, 'PDF export'),
            onExcel: () => _export(downloadReportExcel, 'Excel export'),
          ),
          const SizedBox(height: 20),
          Text('Performance Summary ($_timeframe)',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(_rangeText(), style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Row(children: [
            _ReportSummaryCard('Gross Sales', 'NPR ${_fmt.format(gross)}', Icons.show_chart_rounded, AppColors.success),
            const SizedBox(width: 12),
            _ReportSummaryCard('Collected', 'NPR ${_fmt.format(sales)}', Icons.payments_rounded, AppColors.info),
            const SizedBox(width: 12),
            _ReportSummaryCard('Outstanding Credit', 'NPR ${_fmt.format(credit)}', Icons.assignment_late_rounded, AppColors.warning),
          ]),
          const SizedBox(height: 12),
          if (_includesFinancials)
            Row(children: [
              _ReportSummaryCard('Expenses', 'NPR ${_fmt.format(_d('expenses'))}', Icons.money_off_rounded, AppColors.error),
              const SizedBox(width: 12),
              _ReportSummaryCard('Purchases', 'NPR ${_fmt.format(_d('purchases'))}', Icons.shopping_cart_rounded, AppColors.info),
              const SizedBox(width: 12),
              _ReportSummaryCard('Net Profit', 'NPR ${_fmt.format(netProfit)}', Icons.account_balance_wallet_rounded, profitColor),
            ])
          else
            Row(children: [
              _ReportSummaryCard('Total Invoices', '${_i('bill_count')}', Icons.description_rounded, AppColors.info),
              const SizedBox(width: 12),
              _ReportSummaryCard('Discounts', 'NPR ${_fmt.format(_d('discount'))}', Icons.local_offer_rounded, AppColors.warning),
              const SizedBox(width: 12),
              const Spacer(),
            ]),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_includesFinancials ? 'Financial Breakdown' : 'Sales Breakdown',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 20),
                _BreakdownRow('Sales Collected', sales, AppColors.success),
                const SizedBox(height: 12),
                _BreakdownRow('Outstanding Credit', credit, AppColors.warning),
                if (_includesFinancials) ...[
                  const SizedBox(height: 12),
                  _BreakdownRow('Total Expenses', _d('expenses'), AppColors.error),
                  const SizedBox(height: 12),
                  _BreakdownRow('Total Purchases', _d('purchases'), AppColors.info),
                  const Divider(height: 32),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Estimated Net Profit',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                    Text('NPR ${_fmt.format(netProfit)}',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16, color: profitColor)),
                  ]),
                ],
              ],
            ),
          ),
          if (byMethod.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment Breakdown',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 16),
                  ...byMethod.map((m) {
                    final method = (m['payment_method'] as String?) ?? '—';
                    final amount = (m['total_amount'] as num?)?.toDouble() ?? 0;
                    final count = (m['count'] as num?)?.toInt() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('${_pretty(method)}  ·  $count txns',
                            style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary)),
                        Text('NPR ${_fmt.format(amount)}',
                            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      ]),
                    );
                  }),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    ));
  }

  String _rangeText() {
    final (start, end) = _range();
    final f = DateFormat('dd MMM yyyy');
    return '${f.format(start)} – ${f.format(end)}';
  }

  String _pretty(String raw) => raw.isEmpty
      ? '—'
      : raw.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

// ── Export action bar ───────────────────────────────────────
class _ExportBar extends StatelessWidget {
  final bool exporting;
  final VoidCallback onPrint;
  final VoidCallback onPdf;
  final VoidCallback onExcel;
  const _ExportBar({
    required this.exporting,
    required this.onPrint,
    required this.onPdf,
    required this.onExcel,
  });

  @override
  Widget build(BuildContext context) {
    final label = Text(
      exporting ? 'Preparing document…' : 'Export or print this report',
      style: GoogleFonts.outfit(
          fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
    );
    final leadingIcon = Icon(
        exporting ? Icons.hourglass_top_rounded : Icons.download_rounded,
        size: 20,
        color: AppColors.primary);
    const btnPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 10);
    final printBtn = OutlinedButton.icon(
      onPressed: exporting ? null : onPrint,
      style: OutlinedButton.styleFrom(padding: btnPadding),
      icon: const Icon(Icons.print_rounded, size: 16),
      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Print')),
    );
    final pdfBtn = ElevatedButton.icon(
      onPressed: exporting ? null : onPdf,
      style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white, padding: btnPadding),
      icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('PDF')),
    );
    final excelBtn = ElevatedButton.icon(
      onPressed: exporting ? null : onExcel,
      style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white, padding: btnPadding),
      icon: const Icon(Icons.table_chart_rounded, size: 16),
      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Excel')),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      // On narrow screens the label goes on top and the three buttons share
      // one row below (each Expanded) so they always fit together.
      child: context.isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  leadingIcon,
                  const SizedBox(width: 10),
                  Expanded(child: label),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: printBtn),
                  const SizedBox(width: 8),
                  Expanded(child: pdfBtn),
                  const SizedBox(width: 8),
                  Expanded(child: excelBtn),
                ]),
              ],
            )
          : Row(children: [
              leadingIcon,
              const SizedBox(width: 10),
              Expanded(child: label),
              Wrap(spacing: 8, children: [printBtn, pdfBtn, excelBtn]),
            ]),
    );
  }
}

class _ReportSummaryCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _ReportSummaryCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            ]),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  maxLines: 1,
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final double val;
  final Color color;
  const _BreakdownRow(this.label, this.val, this.color);

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 10),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary)),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Text('NPR ${fmt.format(val)}', style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
