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
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'printer_config.dart';
import 'thermal_printer.dart';

/// Bluetooth is the odd one out: probing it means running a discovery scan,
/// which spins the radio for several seconds.
const Duration _scanPollInterval = Duration(seconds: 60);

/// A network or USB probe is cheap for *this* device but not for the printer:
/// a TCP probe costs one of the very few session slots an ESC/POS print server
/// has. This used to be 10 seconds, which across a floor of tablets kept those
/// slots permanently occupied and made the printers unreachable mid-service.
/// Slow enough to leave the printer alone, quick enough that a cashier who
/// plugs one back in sees it — and there is a "Re-check" button for impatience.
const Duration _cheapPollInterval = Duration(seconds: 60);

/// Added to each notifier's interval, drawn once per notifier. Several devices
/// showing a printer card at the same time otherwise settle into lockstep and
/// hit the printer on the same second, every minute.
const int _maxJitterMs = 5000;

class PrinterStatusNotifier extends StateNotifier<PrinterProbe> {
  final Ref _ref;
  final StateNotifierProvider<PrinterConfigNotifier, PrinterConfig> _configProvider;
  Timer? _timer;
  bool _probing = false;

  /// Bumped by every [_restart]. A `_probeThenSchedule` from an earlier
  /// generation finds its number stale and declines to install its timer.
  ///
  /// Without this the poll rate silently multiplies: `_restart` cancels the
  /// timer and then *awaits* a probe before installing the next one, so two
  /// restarts landing together — the config's async load finishing while a save
  /// arrives — each install a `Timer.periodic`, and the later assignment
  /// orphans the earlier one. The orphan keeps polling for the life of the app
  /// and isn't cancelled by [dispose], which only knows about `_timer`.
  int _generation = 0;

  final int _jitterMs = Random().nextInt(_maxJitterMs);

  PrinterStatusNotifier(this._ref, this._configProvider)
      : super(PrinterProbe.checking()) {
    _ref.listen<PrinterConfig>(
      _configProvider,
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
    unawaited(_probeThenSchedule(++_generation));
  }

  Future<void> _probeThenSchedule(int generation) async {
    await _probe();
    // Nothing to poll for when no printer is saved, or when this platform
    // (web) or transport (Bluetooth on Windows) can't be probed at all.
    if (!mounted || !state.isPollable) return;
    // A newer restart has taken over while this probe was in flight; it owns
    // the timer now.
    if (generation != _generation) return;

    final interval = state.kind == PrinterKind.bluetooth
        ? _scanPollInterval
        : _cheapPollInterval;
    _timer?.cancel();
    _timer = Timer.periodic(
      interval + Duration(milliseconds: _jitterMs),
      (_) => _probe(),
    );
  }

  Future<void> _probe() async {
    // A Bluetooth scan can outlast the poll interval; never stack two.
    if (_probing) return;
    _probing = true;
    try {
      final result = await thermalPrinter.probe(_ref.read(_configProvider));
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
///
/// Tracks the receipt printer — the till's primary printer, shown in the
/// cashier app bar. Aliased as [printerStatusProvider] for existing callers.
final receiptPrinterStatusProvider =
    StateNotifierProvider.autoDispose<PrinterStatusNotifier, PrinterProbe>(
  (ref) => PrinterStatusNotifier(ref, receiptPrinterConfigProvider),
);

/// Live reachability of this device's kitchen (KOT) printer.
final kotPrinterStatusProvider =
    StateNotifierProvider.autoDispose<PrinterStatusNotifier, PrinterProbe>(
  (ref) => PrinterStatusNotifier(ref, kotPrinterConfigProvider),
);

final printerStatusProvider = receiptPrinterStatusProvider;
