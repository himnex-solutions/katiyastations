// ============================================================
// KATIYA STATION RMS — MANUAL PRINT ACTIONS
// One place where a "Print Now" button actually reaches the printer.
// Every path reports what really happened: this device can't print, no
// printer is paired, the printer didn't answer, or the slip went out.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../../features/branches/presentation/providers/branch_provider.dart';
import '../../features/orders/domain/entities/order_entities.dart';
import 'printer_config.dart';
import 'thermal_printer.dart';

// The messenger is captured before the print await and used after it, so the
// snackbar survives the dialog that launched it being popped.
void _say(ScaffoldMessengerState messenger, String message, Color color) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      duration: const Duration(seconds: 4),
    ));
}

/// Validates [cfg] for a manual print, or returns null after explaining why
/// this device cannot print. Both refusals used to be silent: the old buttons
/// popped a green "sent to printer!" snackbar without sending a single byte.
///
/// [what] names the printer role in the "not set up" message ("receipt
/// printer" / "KOT printer") so the cashier knows which one to configure.
PrinterConfig? _readyPrinter(
  ScaffoldMessengerState messenger,
  PrinterConfig cfg, {
  required String what,
}) {
  if (!thermalPrinter.supported) {
    _say(
      messenger,
      'This device cannot drive a thermal printer. Open Katiya Station on the '
      'Windows or Android device the printer is attached to.',
      AppColors.warning,
    );
    return null;
  }
  if (!cfg.configured) {
    _say(
      messenger,
      'No $what is set up on this device yet — Settings → Thermal Printer.',
      AppColors.warning,
    );
    return null;
  }
  return cfg;
}

/// Prints a bill or a settled tax invoice on this device's printer.
Future<void> printBillNow(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> bill,
  required List<Map<String, dynamic>> items,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final cfg = _readyPrinter(messenger, ref.read(receiptPrinterConfigProvider),
      what: 'receipt printer');
  if (cfg == null) return;
  final branch = ref.read(currentBranchProvider).valueOrNull;

  try {
    await thermalPrinter.printBill(
      config: cfg,
      branch: branch,
      bill: bill,
      items: items,
    );
    _say(messenger, 'Printed to ${cfg.target}.', AppColors.success);
  } catch (e) {
    _say(messenger, 'Print failed: $e', AppColors.error);
  }
}

/// Reprints a kitchen ticket on this device's KOT (kitchen) printer.
Future<void> printKotNow(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> kot,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final cfg = _readyPrinter(messenger, ref.read(kotPrinterConfigProvider),
      what: 'KOT printer');
  if (cfg == null) return;

  try {
    await thermalPrinter.printKotTicket(config: cfg, kot: kot);
    _say(messenger, 'KOT printed to ${cfg.target}.', AppColors.success);
  } catch (e) {
    _say(messenger, 'Print failed: $e', AppColors.error);
  }
}

/// Prints [kot] straight to this device's kitchen (KOT) printer over the LAN,
/// the moment a waiter taps "Send KOT to Kitchen". It's a direct socket to the
/// printer's IP, so it needs no internet.
///
/// A silent no-op when this device has no KOT printer set up, when auto-print
/// is off, or on web. Throws when the printer is configured but the send fails
/// (off, out of paper, wrong IP) so the caller can tell the waiter.
Future<void> autoPrintKotToKitchen(
  WidgetRef ref, {
  required Kot kot,
  String? tableNumber,
}) async {
  if (!thermalPrinter.supported) return;
  final cfg = ref.read(kotPrinterConfigProvider);
  if (!cfg.configured || !cfg.autoPrintKot) return;

  // Only kitchen (food) items belong on the kitchen ticket; bar/drink items are
  // printed at the cashier's bar printer instead. Skip if there's no food.
  final foodItems = kot.items.where((i) => !i.isBar).toList();
  if (foodItems.isEmpty) return;

  await thermalPrinter.printKotTicket(
    config: cfg,
    kot: _kotPayload(kot, tableNumber, foodItems),
  );
}

/// Prints the BAR & DRINK items of [kot] straight to this device's receipt
/// printer over the LAN, the moment a waiter sends the order — a direct socket
/// to the printer's IP, so it needs no internet (same model as the kitchen
/// print). The receipt printer is the cashier's LAN printer.
///
/// No-op when this device has no receipt printer set up, "auto-print bar
/// orders" is off, the order has no bar/drink items, or on web. Throws when the
/// printer is configured but unreachable so the caller can tell the waiter.
Future<void> autoPrintBarToCashier(
  WidgetRef ref, {
  required Kot kot,
  String? tableNumber,
}) async {
  if (!thermalPrinter.supported) return;
  final cfg = ref.read(receiptPrinterConfigProvider);
  if (!cfg.configured || !cfg.autoPrintBarKot) return;

  final barItems = kot.items.where((i) => i.isBar).toList();
  if (barItems.isEmpty) return;

  await thermalPrinter.printKotTicket(
    config: cfg,
    kot: _kotPayload(kot, tableNumber, barItems, title: 'BAR'),
  );
}

/// Shapes a [Kot] and an explicit [items] subset into the map
/// [ThermalPrinter.printKotTicket] reads. Mirrors the socket `kot:new` payload
/// (camelCase, `items[].name/quantity/note`). [title] prints a banner line
/// (e.g. "BAR") so a split ticket is unmistakable at the pass.
Map<String, dynamic> _kotPayload(
  Kot kot,
  String? tableNumber,
  List<KotItem> items, {
  String? title,
}) =>
    {
      'kotNumber': kot.kotNumber,
      'tableNumber': tableNumber ?? kot.tableNumber ?? '',
      'createdAt': kot.createdAt.toIso8601String(),
      if (title != null) 'title': title,
      if (kot.notes != null && kot.notes!.isNotEmpty) 'notes': kot.notes,
      'items': [
        for (final i in items)
          {
            'name': i.menuItemName,
            'quantity': i.quantity,
            if (i.notes != null && i.notes!.isNotEmpty) 'note': i.notes,
            'status': i.status,
          },
      ],
    };
