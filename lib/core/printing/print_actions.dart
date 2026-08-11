// ============================================================
// KATIYA STATION RMS — MANUAL PRINT ACTIONS
// One place where a "Print Now" button actually reaches the printer.
// Every path reports what really happened: this device can't print, no
// printer is paired, the printer didn't answer, or the slip went out.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../lan/lan_config.dart';
import '../lan/lan_mirror.dart';
import '../lan/lan_sync.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
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

/// Reprints a kitchen ticket — on the hub's printer when this device has one to
/// delegate to, otherwise on its own.
Future<void> printKotNow(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> kot,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  if (_delegatesPrinting(ref)) {
    final lan = ref.read(lanConfigProvider);
    final label = (kot['kotNumber'] ?? kot['kot_number'] ?? '').toString();
    LanSync.instance.publish(LanMirror.printJobEnvelope(
      deviceId: lan.deviceId,
      branchId: ref.read(authNotifierProvider).value?.branchId ?? '',
      role: LanPrintRole.kitchen,
      // Unique per press. A reprint is something staff are entitled to ask for
      // twice, so it must NOT dedup against the earlier one — while still
      // covering a resend of this same press after a Wi-Fi blip.
      jobId: 'reprint:${DateTime.now().microsecondsSinceEpoch}',
      ticket: kot,
    ));
    _say(
      messenger,
      label.isEmpty
          ? 'Sent to the kitchen printer at the counter.'
          : 'KOT $label sent to the kitchen printer at the counter.',
      AppColors.success,
    );
    return;
  }

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

/// True when this device should hand its tickets to the local hub rather than
/// print them itself — i.e. it is a waiter's tablet with a hub answering.
///
/// The hub (the cashier PC) owns both printers. A thermal print server holds
/// one TCP session, so a floor of tablets each opening their own connection is
/// what took the printers off the network mid-service.
bool _delegatesPrinting(WidgetRef ref) {
  final lan = ref.read(lanConfigProvider);
  return lan.enabled &&
      !lan.isHub &&
      LanSync.instance.status.role == LanRole.client;
}

/// Puts [ticket] on paper: published to the hub when there is one, printed here
/// when there isn't (this device IS the hub, LAN sync is off, or the hub is
/// down mid-service).
///
/// Deliberately one or the other and never both. A published job is buffered
/// and re-sent when the link returns, so also printing locally would put the
/// same order on paper twice.
///
/// [jobId] is the dedup key — see [LanMirror.printJobEnvelope]. Stable for a
/// ticket that must print exactly once; unique per press for a manual reprint,
/// which the cashier is entitled to repeat.
Future<void> _printTicket(
  WidgetRef ref, {
  required String role,
  required String jobId,
  required Map<String, dynamic> ticket,
  required PrinterConfig localConfig,
}) async {
  if (_delegatesPrinting(ref)) {
    final lan = ref.read(lanConfigProvider);
    LanSync.instance.publish(LanMirror.printJobEnvelope(
      deviceId: lan.deviceId,
      branchId: ref.read(authNotifierProvider).value?.branchId ?? '',
      role: role,
      jobId: jobId,
      ticket: ticket,
    ));
    return;
  }

  // Web and other platforms that cannot drive a printer stay silent — there is
  // nothing the person holding the device could do about it.
  if (!thermalPrinter.supported) return;

  // But a device that CAN print, with no hub answering and no printer of its
  // own, has nowhere to send this ticket. Saying so is the whole point: the
  // waiter walks away believing the kitchen has the order, and the silent
  // return this replaces is how a table waits an hour for food nobody is
  // cooking.
  if (!localConfig.configured) {
    throw StateError(
      'Nowhere to print this ticket: the counter PC is not reachable and no '
      'printer is set up on this device.',
    );
  }

  await thermalPrinter.printKotTicket(config: localConfig, kot: ticket);
}

/// Sends [kot]'s food items to the kitchen printer the moment a waiter taps
/// "Send KOT to Kitchen" — over the LAN either way, so it needs no internet.
///
/// A silent no-op when the order has no food, or when this device prints
/// locally and has auto-print switched off.
///
/// Throws on the local path when the send fails (printer off, out of paper,
/// wrong IP) AND when there is nowhere to print at all, so the caller can tell
/// the waiter either way. Delegating never throws: the hub owns delivery from
/// there, retries, and reports a ticket it could not print.
Future<void> autoPrintKotToKitchen(
  WidgetRef ref, {
  required Kot kot,
  String? tableNumber,
}) async {
  // "Auto-print KOT" answers "does THIS device drive a kitchen printer by
  // itself", so it governs the local path only.
  //
  // It cannot govern the delegated one: a tablet that hands its tickets to the
  // hub has no printer, Settings greys the switch out because there is nothing
  // to configure, and the saved value therefore stays false forever. Gating on
  // it meant a tablet without a printer printed nothing at all — the exact
  // setup this feature exists to support.
  final cfg = ref.read(kotPrinterConfigProvider);
  final delegates = _delegatesPrinting(ref);
  if (!delegates && !cfg.autoPrintKot) return;

  // Only kitchen (food) items belong on the kitchen ticket; bar/drink items are
  // printed at the cashier's bar printer instead. Skip if there's no food.
  final foodItems = kot.items.where((i) => !i.isBar).toList();
  if (foodItems.isEmpty) return;

  await _printTicket(
    ref,
    role: LanPrintRole.kitchen,
    jobId: kot.id,
    ticket: _kotPayload(kot, tableNumber, foodItems),
    localConfig: cfg,
  );
}

/// Sends the BAR & DRINK items of [kot] to the receipt printer at the counter
/// the moment a waiter sends the order — same model as the kitchen print, and
/// equally independent of the internet.
///
/// No-op when the order has no bar/drink items, or when this device prints
/// locally and "auto-print bar orders" is off. Throws on the local path — see
/// [autoPrintKotToKitchen].
Future<void> autoPrintBarToCashier(
  WidgetRef ref, {
  required Kot kot,
  String? tableNumber,
}) async {
  // Local path only, for the same reason as the kitchen toggle above.
  final cfg = ref.read(receiptPrinterConfigProvider);
  if (!_delegatesPrinting(ref) && !cfg.autoPrintBarKot) return;

  final barItems = kot.items.where((i) => i.isBar).toList();
  if (barItems.isEmpty) return;

  await _printTicket(
    ref,
    role: LanPrintRole.receipt,
    // Distinct from the kitchen half of the same order, which is a separate
    // ticket on a separate printer and must not dedup against it.
    jobId: '${kot.id}:bar',
    ticket: _kotPayload(kot, tableNumber, barItems, title: 'BAR'),
    localConfig: cfg,
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
  String? orderType,
  String? customerName,
  String? customerPhone,
}) =>
    {
      'kotNumber': kot.kotNumber,
      'tableNumber': tableNumber ?? kot.tableNumber ?? '',
      'createdAt': kot.createdAt.toIso8601String(),
      if (title != null) 'title': title,
      if (orderType != null) 'orderType': orderType,
      if (customerName != null) 'customerName': customerName,
      if (customerPhone != null) 'customerPhone': customerPhone,
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

/// Prints an ORDER CANCELLED slip for [kot] to the station(s) that made it —
/// food to the kitchen printer, bar/drink to the cashier's receipt printer —
/// so staff physically know to stop, carrying the SAME table number and KOT
/// number for tracking, plus the cancellation [reason].
///
/// Cashier-driven (like [printOnlineOrderTickets]): it prints to whichever of
/// the two printers this device has configured and does NOT depend on the
/// auto-print toggles. No-op on web / when neither printer is set up. Never
/// throws — a cancel must succeed even if the slip can't print; failures are
/// swallowed so the caller's success path (the void itself) is unaffected.
///
/// [items] are the order's line maps as held on the cashier screen
/// (`name`/`quantity`/`note`/`type`) — pass the pre-cancel list so the lines
/// still render (the ticket builder skips items already marked cancelled).
Future<void> printCancellationTickets(
  WidgetRef ref, {
  required String kotNumber,
  required String tableNumber,
  required String reason,
  required List<Map<String, dynamic>> items,
  String? cancelledBy,
}) async {
  bool isBar(Map<String, dynamic> i) {
    final t = (i['type'] as String?) ?? 'food';
    return t == 'bar' || t == 'drink';
  }

  Map<String, dynamic> slip(List<Map<String, dynamic>> lines, {String? title}) => {
        'kotNumber': kotNumber,
        'tableNumber': tableNumber,
        'createdAt': DateTime.now().toIso8601String(),
        'title': title == null ? 'ORDER CANCELLED' : 'CANCELLED - $title',
        // Reason + who voided it ride on the ticket's NOTE line.
        'notes': [
          'Reason: $reason',
          if (cancelledBy != null && cancelledBy.isNotEmpty) 'Voided by: $cancelledBy',
        ].join('  |  '),
        // Strip any per-item status so the builder doesn't skip a line that was
        // just flipped to 'cancelled' — we WANT to show what got voided.
        'items': [
          for (final i in lines)
            {
              'name': i['name'] ?? i['menu_item_name'],
              'quantity': i['quantity'],
              if ((i['note'] ?? i['notes']) != null) 'note': i['note'] ?? i['notes'],
            },
        ],
      };

  final foodItems = items.where((i) => !isBar(i)).toList();
  final barItems = items.where(isBar).toList();

  if (foodItems.isNotEmpty) {
    try {
      await _printTicket(
        ref,
        role: LanPrintRole.kitchen,
        jobId: 'cancel:$kotNumber',
        ticket: slip(foodItems),
        localConfig: ref.read(kotPrinterConfigProvider),
      );
    } catch (_) {/* a cancel must not fail because the printer is offline */}
  }

  if (barItems.isNotEmpty) {
    try {
      await _printTicket(
        ref,
        role: LanPrintRole.receipt,
        jobId: 'cancel:$kotNumber:bar',
        ticket: slip(barItems, title: 'BAR'),
        localConfig: ref.read(receiptPrinterConfigProvider),
      );
    } catch (_) {/* swallow — see above */}
  }
}

/// Prints an ONLINE (call-in / delivery) order's tickets: food to the kitchen
/// printer and bar/drink to the cashier's receipt printer, both headed
/// "ONLINE ORDER" with the customer's name. The cashier drives this, so it
/// prints to whichever of the two printers this device has configured (it does
/// not require the auto-print toggles). No-op on web.
Future<void> printOnlineOrderTickets(
  WidgetRef ref, {
  required Kot kot,
  required String customerName,
  String? customerPhone,
}) async {
  if (!thermalPrinter.supported) return;

  final foodItems = kot.items.where((i) => !i.isBar).toList();
  final barItems = kot.items.where((i) => i.isBar).toList();

  final kitchenCfg = ref.read(kotPrinterConfigProvider);
  if (kitchenCfg.configured && foodItems.isNotEmpty) {
    await thermalPrinter.printKotTicket(
      config: kitchenCfg,
      kot: _kotPayload(kot, '', foodItems,
          orderType: 'online', customerName: customerName, customerPhone: customerPhone),
    );
  }

  final barCfg = ref.read(receiptPrinterConfigProvider);
  if (barCfg.configured && barItems.isNotEmpty) {
    await thermalPrinter.printKotTicket(
      config: barCfg,
      kot: _kotPayload(kot, '', barItems,
          title: 'BAR', orderType: 'online', customerName: customerName, customerPhone: customerPhone),
    );
  }
}
