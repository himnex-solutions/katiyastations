import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class ShiftClosingScreen extends ConsumerStatefulWidget {
  const ShiftClosingScreen({super.key});
  @override
  ConsumerState<ShiftClosingScreen> createState() => _ShiftClosingScreenState();
}

class _ShiftClosingScreenState extends ConsumerState<ShiftClosingScreen> {
  bool _loading = true;
  bool _submitting = false;
  Map<String, dynamic>? _summary;

  final _fmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    _loadTodaySummary();
  }

  Future<void> _loadTodaySummary() async {
    setState(() => _loading = true);
    final profile = ref.read(authNotifierProvider).value;
    if (profile?.branchId == null) {
      setState(() => _loading = false);
      return;
    }

    final response = await ApiClient.instance.get(
      ApiConstants.shiftTodaySummary,
      queryParameters: {'branchId': profile!.branchId!},
    );
    final s = response.data as Map<String, dynamic>;

    setState(() {
      _summary = {
        'cash': (s['cash'] as num?)?.toDouble() ?? 0,
        'card': (s['card'] as num?)?.toDouble() ?? 0,
        'esewa': (s['esewa'] as num?)?.toDouble() ?? 0,
        'khalti': (s['khalti'] as num?)?.toDouble() ?? 0,
        'fonepay': (s['fonepay'] as num?)?.toDouble() ?? 0,
        'credit': (s['credit'] as num?)?.toDouble() ?? 0,
        'refund': (s['refund'] as num?)?.toDouble() ?? 0,
        'total_revenue': (s['total_revenue'] as num?)?.toDouble() ?? 0,
        'total_vat': (s['total_vat'] as num?)?.toDouble() ?? 0,
        'total_discount': (s['total_discount'] as num?)?.toDouble() ?? 0,
        'total_service_charge': (s['total_service_charge'] as num?)?.toDouble() ?? 0,
        'bill_count': (s['bill_count'] as num?)?.toInt() ?? 0,
        'net_revenue': (s['net_revenue'] as num?)?.toDouble() ?? 0,
      };
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).value;

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
              child: const Icon(Icons.lock,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Shift Closing',
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
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh'),
            onPressed: _loadTodaySummary,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _summary == null
              ? const Center(child: Text('Unable to load summary'))
              : ResponsiveContent(
                  alignment: Alignment.topLeft,
                  child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date Banner
                      _DateBanner(),
                      const SizedBox(height: 20),

                      // Revenue Overview
                      const _SectionHeader('Revenue Overview'),
                      const SizedBox(height: 12),
                      _OverviewCards(summary: _summary!, fmt: _fmt),
                      const SizedBox(height: 20),

                      // Payment Method Breakdown
                      const _SectionHeader('Payment Breakdown'),
                      const SizedBox(height: 12),
                      _PaymentBreakdown(summary: _summary!, fmt: _fmt),
                      const SizedBox(height: 20),

                      // Deductions
                      const _SectionHeader('Adjustments'),
                      const SizedBox(height: 12),
                      _AdjustmentSection(summary: _summary!, fmt: _fmt),
                      const SizedBox(height: 32),

                      // Submit Button
                      if (profile?.isBranchManager == true ||
                          profile?.isCashier == true)
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            icon: _submitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: AppColors.onPrimary))
                                : const Icon(Icons.lock_clock_rounded),
                            label: const Text('Close Shift & Generate Report'),
                            onPressed: _submitting
                                ? null
                                : () => _closeShift(context, profile),
                          ),
                        ).animate().fadeIn(),
                    ],
                  ),
                )),
    );
  }

  Future<void> _closeShift(BuildContext context, dynamic profile) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Close Shift',
      message:
          'This will record the shift closing for today. The cashier summary will be saved. Continue?',
      confirmLabel: 'Close Shift',
      confirmColor: AppColors.primary,
      icon: Icons.lock_clock_rounded,
    );

    if (!confirmed) return;
    setState(() => _submitting = true);

    try {
      final profileBranchId = profile?.branchId;
      await ApiClient.instance.post(
        ApiConstants.shiftClosing,
        data: {
          'branchId': profileBranchId,
          'cashierName': profile?.fullName,
          'date': DateTime.now().toIso8601String().substring(0, 10),
          'cashTotal': _summary!['cash'],
          'cardTotal': _summary!['card'],
          'esewaTotal': _summary!['esewa'],
          'khaltiTotal': _summary!['khalti'],
          'fonepayTotal': _summary!['fonepay'],
          'creditTotal': _summary!['credit'],
          'refundTotal': _summary!['refund'],
          'totalRevenue': _summary!['total_revenue'],
          'netRevenue': _summary!['net_revenue'],
          'totalVat': _summary!['total_vat'],
          'totalDiscount': _summary!['total_discount'],
          'totalServiceCharge': _summary!['total_service_charge'],
          'billCount': _summary!['bill_count'],
        },
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shift closed successfully! Awaiting manager approval.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }

    setState(() => _submitting = false);
  }
}

class _DateBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Today\'s Shift',
                  style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.85))),
              Text(DateFormat('EEEE, dd MMMM yyyy').format(now),
                  style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewCards extends StatelessWidget {
  final Map<String, dynamic> summary;
  final NumberFormat fmt;
  const _OverviewCards({required this.summary, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: context.responsiveValue(mobile: 2, tablet: 3, desktop: 4),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2,
      children: [
        _StatCard('Total Bills', '${summary['bill_count']}', Icons.receipt_long_rounded, AppColors.info),
        _StatCard('Gross Revenue', 'NPR ${fmt.format(summary['total_revenue'])}',
            Icons.trending_up_rounded, AppColors.success),
        _StatCard('Total Refunds', 'NPR ${fmt.format(summary['refund'])}',
            Icons.undo_rounded, AppColors.error),
        _StatCard('Net Revenue', 'NPR ${fmt.format(summary['net_revenue'])}',
            Icons.account_balance_rounded, AppColors.primary),
      ],
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: GoogleFonts.outfit(
                        fontSize: 11, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(value,
                    style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentBreakdown extends StatelessWidget {
  final Map<String, dynamic> summary;
  final NumberFormat fmt;
  const _PaymentBreakdown({required this.summary, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final methods = <(String, String, IconData, Color, String?)>[
      ('Cash', 'cash', Icons.money_rounded, AppColors.success, null),
      ('Card', 'card', Icons.credit_card_rounded, AppColors.info, null),
      ('eSewa', 'esewa', Icons.phone_android_rounded, const Color(0xFF60BB46), 'assets/icons/esewa.png'),
      ('Khalti', 'khalti', Icons.account_balance_wallet_rounded, const Color(0xFF5C2D91), 'assets/icons/khalti.png'),
      ('FonePay', 'fonepay', Icons.qr_code_scanner_rounded, AppColors.warning, 'assets/icons/fonepay.png'),
      ('Credit', 'credit', Icons.receipt_long_rounded, AppColors.error, null),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: methods.asMap().entries.map((entry) {
          final i = entry.key;
          final (label, key, icon, color, asset) = entry.value;
          final amount = (summary[key] as num?)?.toDouble() ?? 0;
          return Column(
            children: [
              if (i > 0) const Divider(height: 1),
              ListTile(
                dense: true,
                leading: asset != null
                    ? Image.asset(
                        asset,
                        width: 22,
                        height: 22,
                        errorBuilder: (_, __, ___) =>
                            Icon(icon, color: color, size: 20),
                      )
                    : Icon(icon, color: color, size: 20),
                title: Text(label,
                    style: GoogleFonts.outfit(
                        fontSize: 13, color: AppColors.textPrimary)),
                trailing: Text(
                  'NPR ${fmt.format(amount)}',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: amount > 0 ? color : AppColors.textHint,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _AdjustmentSection extends StatelessWidget {
  final Map<String, dynamic> summary;
  final NumberFormat fmt;
  const _AdjustmentSection({required this.summary, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _AdjRow('Total VAT Collected', summary['total_vat'] as double, AppColors.info, fmt),
          const Divider(height: 1),
          _AdjRow('Total Discounts', summary['total_discount'] as double, AppColors.warning, fmt),
          const Divider(height: 1),
          _AdjRow('Service Charges', summary['total_service_charge'] as double, AppColors.success, fmt),
        ],
      ),
    );
  }
}

class _AdjRow extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final NumberFormat fmt;
  const _AdjRow(this.label, this.amount, this.color, this.fmt);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label,
          style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary)),
      trailing: Text('NPR ${fmt.format(amount)}',
          style: GoogleFonts.outfit(
              fontSize: 13, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.5));
  }
}
