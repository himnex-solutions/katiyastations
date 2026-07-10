// ============================================================
// KATIYA STATION RMS — THERMAL PRINTER (web / unsupported stub)
// Selected on platforms without dart:io (web). Thermal printing needs a
// real device, so every call is a safe no-op and [supported] is false.
// ============================================================

import 'printer_config.dart';
import 'thermal_printer.dart';

ThermalPrinter createThermalPrinter() => _StubThermalPrinter();

class _StubThermalPrinter implements ThermalPrinter {
  @override
  bool get supported => false;

  @override
  Future<List<DiscoveredPrinter>> discover(PrinterKind kind, {bool isBle = false}) async => const [];

  @override
  Future<void> printKotTicket({
    required PrinterConfig config,
    Map<String, dynamic>? branch,
    required Map<String, dynamic> kot,
  }) async {
    throw UnsupportedError('Thermal printing is not available on this platform');
  }

  @override
  Future<void> printBill({
    required PrinterConfig config,
    Map<String, dynamic>? branch,
    required Map<String, dynamic> bill,
    required List<Map<String, dynamic>> items,
  }) async {
    throw UnsupportedError('Thermal printing is not available on this platform');
  }

  @override
  Future<void> testPrint({required PrinterConfig config, Map<String, dynamic>? branch}) async {
    throw UnsupportedError('Thermal printing is not available on this platform');
  }

  /// A browser can neither open a raw TCP socket nor enumerate USB devices,
  /// so there is nothing to probe — say so rather than show a false negative.
  @override
  Future<PrinterProbe> probe(PrinterConfig config) async => PrinterProbe(
        state: PrinterLinkState.unsupported,
        checkedAt: DateTime.now(),
        detail: 'The web app cannot reach a thermal printer. '
            'Open Katiya Station on the Windows or Android device instead.',
      );
}
