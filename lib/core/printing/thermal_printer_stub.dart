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
  Future<void> testPrint({required PrinterConfig config, Map<String, dynamic>? branch}) async {
    throw UnsupportedError('Thermal printing is not available on this platform');
  }
}
