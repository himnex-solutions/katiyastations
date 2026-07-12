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

/// Returns the device's printer config, or null after explaining why this
/// device cannot print. Both refusals used to be silent: the old buttons
/// popped a green "sent to printer!" snackbar without sending a single byte.
PrinterConfig? _readyPrinter(ScaffoldMessengerState messenger, WidgetRef ref) {
  if (!thermalPrinter.supported) {
    _say(
      messenger,
      'This device cannot drive a thermal printer. Open Katiya Station on the '
      'Windows or Android device the printer is attached to.',
      AppColors.warning,
    );
    return null;
  }
  final cfg = ref.read(printerConfigProvider);
  if (!cfg.configured) {
    _say(
      messenger,
      'No printer is paired on this device yet — Settings → Thermal Printer.',
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
  final cfg = _readyPrinter(messenger, ref);
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

/// Reprints a kitchen ticket on this device's printer.
Future<void> printKotNow(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> kot,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final cfg = _readyPrinter(messenger, ref);
  if (cfg == null) return;

  try {
    await thermalPrinter.printKotTicket(config: cfg, kot: kot);
    _say(messenger, 'KOT printed to ${cfg.target}.', AppColors.success);
  } catch (e) {
    _say(messenger, 'Print failed: $e', AppColors.error);
  }
}
