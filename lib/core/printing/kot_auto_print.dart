// ============================================================
// KATIYA STATION RMS — KOT AUTO-PRINT (print station)
// Watched for the whole authenticated session (from AppShell). When a
// waiter sends a KOT, the backend emits `kot:new`; any device set up as a
// print station (a configured printer + "auto-print" on — typically the
// kitchen tablet/PC) instantly prints the ticket. Web devices no-op.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_messenger.dart';
import '../constants/app_colors.dart';
import '../network/socket_client.dart';
import 'kot_print_queue.dart';
import 'printer_config.dart';
import 'thermal_printer.dart';

final kotAutoPrintProvider = Provider<void>((ref) {
  // Nothing to print on unsupported platforms (e.g. web).
  if (!thermalPrinter.supported) return;

  // Three waiters can hit Send in the same second. The queue prints their
  // tickets one after another, in the order the backend accepted them, instead
  // of firing overlapping prints at one printer.
  final queue = KotPrintQueue(
    printKot: (kot) async {
      // Re-read at print time: the config can change while a ticket waits.
      final cfg = ref.read(printerConfigProvider);
      if (!cfg.autoPrintKot || !cfg.configured) return;
      await thermalPrinter.printKotTicket(config: cfg, kot: kot);
    },
    // A failed auto-print must never crash the floor app — the kitchen still
    // sees the ticket on screen and can reprint from there. But it must not be
    // silent either: a printer that is off or out of paper would otherwise drop
    // tickets with nobody any the wiser.
    onError: _warnPrintFailed,
  );

  final sub = SocketClient.instance.onKotNew().listen((data) {
    final cfg = ref.read(printerConfigProvider);
    if (!cfg.autoPrintKot || !cfg.configured) return;
    queue.add(Map<String, dynamic>.from(data));
  });

  ref.onDispose(sub.cancel);
});

void _warnPrintFailed(dynamic kot, Object error) {
  final kotNo = (kot is Map ? kot['kotNumber'] ?? kot['kot_number'] : null) ?? '';
  final label = kotNo.toString().isEmpty ? 'A KOT' : 'KOT $kotNo';

  scaffoldMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      content: Row(children: [
        const Icon(Icons.print_disabled_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$label did not print: $error',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    ));
}
