// ============================================================
// KATIYA STATION RMS — KOT AUTO-PRINT (print station)
// Watched for the whole authenticated session (from AppShell). When a
// waiter sends a KOT, the backend emits `kot:new`; any device set up as a
// print station (a configured printer + "auto-print" on — typically the
// kitchen tablet/PC) instantly prints the ticket. Web devices no-op.
// ============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/socket_client.dart';
import '../../features/branches/presentation/providers/branch_provider.dart';
import 'printer_config.dart';
import 'thermal_printer.dart';

final kotAutoPrintProvider = Provider<void>((ref) {
  // Nothing to print on unsupported platforms (e.g. web).
  if (!thermalPrinter.supported) return;

  final sub = SocketClient.instance.onKotNew().listen((data) async {
    final cfg = ref.read(printerConfigProvider);
    if (!cfg.autoPrintKot || !cfg.configured) return;

    final branch = ref.read(currentBranchProvider).valueOrNull;
    try {
      await thermalPrinter.printKotTicket(
        config: cfg,
        branch: branch,
        kot: Map<String, dynamic>.from(data),
      );
    } catch (_) {
      // A failed auto-print must never crash the floor app — the kitchen
      // still sees the ticket on screen and can reprint from there.
    }
  });

  ref.onDispose(sub.cancel);
});
