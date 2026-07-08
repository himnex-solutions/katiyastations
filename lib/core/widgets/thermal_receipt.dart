// ============================================================
// KATIYA STATION RMS — THERMAL RECEIPT / TICKET CHROME
// Shared print-preview dialog styling used by both the cashier's bill
// receipt and the kitchen's KOT ticket, so the two stay visually
// consistent instead of duplicating markup.
// ============================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

/// Wraps [receipt] in the standard "Thermal Print Preview" dialog chrome
/// (title bar, bordered ticket area, Cancel / Print Now actions).
void showThermalPrintDialog(
  BuildContext context, {
  required String title,
  required Widget receipt,
  required VoidCallback onPrint,
}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.transparent,
      contentPadding: EdgeInsets.zero,
      insetPadding: const EdgeInsets.all(16),
      content: Container(
        // Cap at 400 on wide screens but never exceed the actual viewport
        // width — a fixed 400 would overflow horizontally on a phone
        // (~360-390 logical px wide).
        width: math.min(400, MediaQuery.sizeOf(ctx).width - 32),
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: GoogleFonts.outfit(
                        fontSize: 15, fontWeight: FontWeight.w700, color: Colors.grey[800])),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: receipt,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.print_rounded, size: 16),
                  label: const Text('Print Now'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    onPrint();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

TextStyle receiptStyle({double fontSize = 11, FontWeight weight = FontWeight.normal}) =>
    GoogleFonts.courierPrime(fontSize: fontSize, fontWeight: weight, color: Colors.black);

Widget receiptDivider() => Text(
      '- - - - - - - - - - - - - - - - - - - - -',
      textAlign: TextAlign.center,
      style: receiptStyle(),
    );

Widget receiptRow(String label, String value, {FontWeight weight = FontWeight.normal, double fontSize = 11}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: receiptStyle(fontSize: fontSize, weight: weight)),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.right,
              style: receiptStyle(fontSize: fontSize, weight: weight)),
        ),
      ],
    ),
  );
}

/// Branch identity block shown at the top of every printed document —
/// real branch name/address/phone (from [currentBranchProvider]), never
/// hardcoded placeholder text. Fields that aren't set on the branch are
/// simply omitted rather than printing "null" or empty lines.
Widget receiptBranchHeader(Map<String, dynamic>? branch, {String fallbackName = 'KATIYA STATION'}) {
  final name = (branch?['name'] as String?)?.trim();
  final city = (branch?['city'] as String?)?.trim();
  final address = (branch?['address'] as String?)?.trim();
  final phone = (branch?['phone'] as String?)?.trim();
  final addressLine = [address, city].where((s) => s != null && s.isNotEmpty).join(', ');

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text((name != null && name.isNotEmpty ? name : fallbackName).toUpperCase(),
          textAlign: TextAlign.center, style: receiptStyle(fontSize: 18, weight: FontWeight.bold)),
      if (addressLine.isNotEmpty)
        Text(addressLine, textAlign: TextAlign.center, style: receiptStyle()),
      if (phone != null && phone.isNotEmpty)
        Text('Phone: $phone', textAlign: TextAlign.center, style: receiptStyle()),
    ],
  );
}

void showPrintSentSnackbar(BuildContext context, {String label = 'Print command sent to thermal printer!'}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      content: Row(
        children: [
          const Icon(Icons.print_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
  );
}
