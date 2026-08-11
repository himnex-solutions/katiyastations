// ============================================================
// KATIYA STATION RMS — DELETE PAYMENT RECORDS BY DATE
//
// Shared by the manager's Payment History screen and the super admin's Danger
// Zone. Both reach the same two endpoints; only the branch differs (a manager
// is pinned to their own, the super admin picks one).
//
// The shape of this dialog is the safety feature. A date range on its own tells
// nobody what is inside it, so nothing can be deleted until the server has been
// asked what is there and the answer has been read back — bills, tax invoices,
// the money they came to, and any unpaid udhaaro that will go with them. Only
// then does typing DELETE arm the button.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../constants/api_constants.dart';
import '../constants/app_colors.dart';
import '../network/api_client.dart';

/// How far back a preset reaches. Managers clear payment history on a rhythm —
/// yesterday's mistake, last week, the month just closed — so the common spans
/// are one tap instead of two dates in a calendar.
enum PurgeSpan {
  day('1 day'),
  week('1 week'),
  month('1 month'),
  halfYear('6 months');

  const PurgeSpan(this.label);
  final String label;
}

/// One bill state the purge is holding back, and how many are in it.
class PurgeKept {
  final String status;
  final int count;
  const PurgeKept({required this.status, required this.count});

  /// Plain words for a `payment_status` value.
  String get label => switch (status) {
        'credit' => 'on credit (udhaaro)',
        'partial_paid' => 'part paid',
        'refunded' => 'refunded',
        'voided' => 'voided',
        _ => status,
      };
}

/// What the server says is inside the chosen window.
class PurgePreview {
  /// Fully-paid bills — the ones that will actually be deleted.
  final int bills;
  final int payments;
  final int taxInvoices;
  final double totalAmount;

  /// Every bill in the window, including the ones being kept.
  final int billsInRange;

  /// Why the other bills are staying.
  final List<PurgeKept> kept;

  const PurgePreview({
    required this.bills,
    required this.payments,
    required this.taxInvoices,
    required this.totalAmount,
    required this.billsInRange,
    required this.kept,
  });

  factory PurgePreview.fromJson(Map<String, dynamic> json) => PurgePreview(
        bills: (json['bills'] as num?)?.toInt() ?? 0,
        payments: (json['payments'] as num?)?.toInt() ?? 0,
        taxInvoices: (json['taxInvoices'] as num?)?.toInt() ?? 0,
        totalAmount:
            double.tryParse(json['totalAmount']?.toString() ?? '') ?? 0,
        billsInRange: (json['billsInRange'] as num?)?.toInt() ?? 0,
        kept: [
          for (final row in (json['kept'] as List? ?? const []))
            if (row is Map)
              PurgeKept(
                status: (row['status'] ?? '').toString(),
                count: (row['count'] as num?)?.toInt() ?? 0,
              ),
        ],
      );

  bool get isEmpty => bills == 0;

  int get keptCount => kept.fold(0, (sum, row) => sum + row.count);
}

/// Opens the dialog. Returns the number of bills deleted, or null if the user
/// backed out. [branchId] must be resolved by the caller — the server refuses a
/// purge that does not name exactly one branch.
Future<int?> showPurgePaymentsDialog(
  BuildContext context, {
  required String branchId,
  String? branchLabel,
}) {
  return showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _PurgePaymentsDialog(branchId: branchId, branchLabel: branchLabel),
  );
}

class _PurgePaymentsDialog extends ConsumerStatefulWidget {
  final String branchId;
  final String? branchLabel;
  const _PurgePaymentsDialog({required this.branchId, this.branchLabel});

  @override
  ConsumerState<_PurgePaymentsDialog> createState() =>
      _PurgePaymentsDialogState();
}

class _PurgePaymentsDialogState extends ConsumerState<_PurgePaymentsDialog> {
  final _confirmCtrl = TextEditingController();
  final _money = NumberFormat('#,##0.00');

  DateTimeRange? _range;

  /// The preset behind [_range], or null when the dates were picked by hand.
  /// Kept only so the chosen chip stays highlighted.
  PurgeSpan? _span;

  PurgePreview? _preview;
  String _error = '';
  bool _loadingPreview = false;
  bool _deleting = false;

  /// The window sent to the server, matching what the payment history list
  /// already does: local Nepal midnights converted to UTC, end pushed to the
  /// start of the following day so the last day is included whole.
  ///
  /// Identical arithmetic on both screens is what makes "43 bills" in the
  /// preview the same 43 bills the list was showing.
  Map<String, String> get _windowQuery => {
        'branchId': widget.branchId,
        'startDate': _range!.start.toUtc().toIso8601String(),
        'endDate':
            _range!.end.add(const Duration(days: 1)).toUtc().toIso8601String(),
      };

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// Resolves a preset to concrete dates, both ends inclusive and counted back
  /// from today. Month spans step the calendar rather than subtracting 30 days,
  /// so "1 month" from the 31st lands on the same date in the previous month
  /// the way a person reading it would expect.
  void _applySpan(PurgeSpan span) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = switch (span) {
      PurgeSpan.day => today,
      PurgeSpan.week => today.subtract(const Duration(days: 6)),
      PurgeSpan.month => DateTime(today.year, today.month - 1, today.day),
      PurgeSpan.halfYear => DateTime(today.year, today.month - 6, today.day),
    };
    _setRange(DateTimeRange(start: start, end: today), span);
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _range,
      helpText: 'Records to delete',
    );
    if (picked == null) return;
    _setRange(picked, null);
  }

  void _setRange(DateTimeRange range, PurgeSpan? span) {
    setState(() {
      _range = range;
      _span = span;
      _preview = null;
      _error = '';
      // A new window is a different set of records; the typed confirmation was
      // for the old one.
      _confirmCtrl.clear();
    });
    unawaited(_loadPreview());
  }

  Future<void> _loadPreview() async {
    if (_range == null) return;
    setState(() {
      _loadingPreview = true;
      _error = '';
    });
    try {
      final response = await ApiClient.instance.get(
        ApiConstants.paymentRecordsPurgePreview,
        queryParameters: _windowQuery,
      );
      if (!mounted) return;
      setState(() =>
          _preview = PurgePreview.fromJson(response.data as Map<String, dynamic>));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = '';
    });
    try {
      final response = await ApiClient.instance.delete(
        ApiConstants.paymentRecordsPurge,
        data: {..._windowQuery, 'confirm': 'DELETE'},
      );
      final deleted =
          ((response.data as Map<String, dynamic>?)?['deleted'] as num?)
                  ?.toInt() ??
              0;
      if (mounted) Navigator.pop(context, deleted);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _deleting = false;
        });
      }
    }
  }

  bool get _armed =>
      _preview != null &&
      !_preview!.isEmpty &&
      _confirmCtrl.text.trim() == 'DELETE' &&
      !_deleting;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Row(children: [
        const Icon(Icons.delete_forever_rounded, color: AppColors.error),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Delete payment records',
              style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700, fontSize: 17)),
        ),
      ]),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Permanently removes FULLY PAID bills and their payments over a '
                'date range. This cannot be undone — revenue reports for those '
                'days will read zero afterwards.',
                style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.45),
              ),
              const SizedBox(height: 10),
              _box(
                AppColors.success,
                Text(
                  'Never deleted: bills on credit (udhaaro), part-paid bills, '
                  'and anything refunded or voided. Orders, menu, staff and '
                  'stock are untouched, and an audit entry records what was '
                  'removed and by whom.',
                  style: GoogleFonts.outfit(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      height: 1.4),
                ),
              ),
              if (widget.branchLabel != null) ...[
                const SizedBox(height: 12),
                _line('Branch', widget.branchLabel!),
              ],
              const SizedBox(height: 16),

              Text('How far back',
                  style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final span in PurgeSpan.values)
                    ChoiceChip(
                      label: Text(span.label),
                      selected: _span == span,
                      onSelected:
                          _deleting ? null : (_) => _applySpan(span),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.date_range_rounded, size: 15),
                    label: const Text('Custom'),
                    onPressed: _deleting ? null : _pickRange,
                  ),
                ],
              ),
              if (_range != null) ...[
                const SizedBox(height: 10),
                // The resolved dates, always. A chip saying "1 month" is not a
                // statement of what is about to be deleted; these two dates are.
                _line(
                  'Deleting',
                  '${DateFormat('dd MMM yyyy').format(_range!.start)} — '
                      '${DateFormat('dd MMM yyyy').format(_range!.end)}',
                ),
              ],

              if (_loadingPreview) ...[
                const SizedBox(height: 18),
                const Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              ],

              if (_preview != null && !_loadingPreview) ...[
                const SizedBox(height: 16),
                _previewBox(_preview!),
              ],

              if (_error.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(_error,
                    style: GoogleFonts.outfit(
                        fontSize: 12, color: AppColors.error, height: 1.35)),
              ],

              // The confirmation only appears once there is something real to
              // confirm, so it can never be typed ahead of reading the numbers.
              if (_preview != null && !_preview!.isEmpty) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmCtrl,
                  autofocus: true,
                  enabled: !_deleting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Type DELETE to confirm',
                    isDense: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error, foregroundColor: Colors.white),
          onPressed: _armed ? _delete : null,
          icon: _deleting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.delete_forever_rounded, size: 16),
          label: Text(_deleting ? 'Deleting…' : 'Delete permanently'),
        ),
      ],
    );
  }

  Widget _previewBox(PurgePreview p) {
    if (p.isEmpty) {
      return _box(
        AppColors.textHint,
        Text(
          p.billsInRange == 0
              ? 'No payment records in that range — nothing to delete.'
              : 'None of the ${p.billsInRange} bill(s) in that range are fully '
                  'paid, so there is nothing to delete.',
          style: GoogleFonts.outfit(
              fontSize: 12.5, color: AppColors.textSecondary),
        ),
      );
    }

    return Column(children: [
      _box(
        AppColors.error,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('About to be deleted',
              style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error)),
          const SizedBox(height: 8),
          _line('Fully-paid bills', '${p.bills}'),
          _line('Payments', '${p.payments}'),
          _line('Revenue removed', 'NPR ${_money.format(p.totalAmount)}'),
          if (p.taxInvoices > 0) ...[
            _line('Tax invoices', '${p.taxInvoices}'),
            const SizedBox(height: 8),
            Text(
              'This range contains ${p.taxInvoices} issued tax invoice(s). '
              'Check your retention obligations before removing them.',
              style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                  height: 1.35),
            ),
          ],
        ]),
      ),
      // Spelling out what stays is what stops "40 bills in the range, 31
      // deleted" reading like something went wrong.
      if (p.kept.isNotEmpty) ...[
        const SizedBox(height: 10),
        _box(
          AppColors.success,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Kept (${p.keptCount} of ${p.billsInRange} in this range)',
                style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success)),
            const SizedBox(height: 6),
            for (final row in p.kept) _line(row.label, '${row.count}'),
          ]),
        ),
      ],
    ]);
  }

  Widget _box(Color color, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: child,
      );

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.outfit(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
          Text(value,
              style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ]),
      );
}
