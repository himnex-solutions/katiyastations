// ============================================================
// KATIYA STATION RMS — LIVE PRINTER STATUS
// Keeps a running answer to "is this device's thermal printer reachable?".
//
// This cannot ride the Socket.IO channel like the rest of the app's realtime:
// the printer is attached to *this* device, and the server has no idea it
// exists. So the status is polled, and re-probed immediately whenever the
// saved printer config changes.
// ============================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'printer_config.dart';
import 'thermal_printer.dart';

/// Bluetooth is the odd one out: probing it means running a discovery scan,
/// which spins the radio for several seconds. Poll it far less often than a
/// TCP connect or a USB device enumeration, both of which are near-free.
const Duration _scanPollInterval = Duration(seconds: 30);
const Duration _cheapPollInterval = Duration(seconds: 10);

class PrinterStatusNotifier extends StateNotifier<PrinterProbe> {
  final Ref _ref;
  Timer? _timer;
  bool _probing = false;

  PrinterStatusNotifier(this._ref) : super(PrinterProbe.checking()) {
    _ref.listen<PrinterConfig>(
      printerConfigProvider,
      (_, __) => _restart(),
      fireImmediately: true,
    );
  }

  /// Re-probes now, out of band with the poll timer. Wired to the "Re-check"
  /// button so a cashier who just plugged the printer back in doesn't have to
  /// wait out the interval.
  Future<void> refresh() => _probe();

  void _restart() {
    _timer?.cancel();
    _timer = null;
    unawaited(_probeThenSchedule());
  }

  Future<void> _probeThenSchedule() async {
    await _probe();
    // Nothing to poll for when no printer is saved, or when this platform
    // (web) or transport (Bluetooth on Windows) can't be probed at all.
    if (!mounted || !state.isPollable) return;

    final interval = state.kind == PrinterKind.bluetooth
        ? _scanPollInterval
        : _cheapPollInterval;
    _timer = Timer.periodic(interval, (_) => _probe());
  }

  Future<void> _probe() async {
    // A Bluetooth scan can outlast the poll interval; never stack two.
    if (_probing) return;
    _probing = true;
    try {
      final result = await thermalPrinter.probe(_ref.read(printerConfigProvider));
      if (mounted) state = result;
    } catch (e) {
      if (mounted) {
        state = PrinterProbe(
          state: PrinterLinkState.unreachable,
          checkedAt: DateTime.now(),
          detail: 'Could not check the printer: $e',
        );
      }
    } finally {
      _probing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// autoDispose so the poll (and any Bluetooth scanning) stops as soon as no
/// screen is showing the status.
final printerStatusProvider =
    StateNotifierProvider.autoDispose<PrinterStatusNotifier, PrinterProbe>(
  (ref) => PrinterStatusNotifier(ref),
);
