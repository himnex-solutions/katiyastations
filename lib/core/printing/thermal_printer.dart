// ============================================================
// KATIYA STATION RMS — THERMAL PRINTER (facade)
// The real transport uses dart:io (Bluetooth/USB/TCP) which does NOT
// compile for web, so it lives behind a conditional import: web gets a
// no-op stub, native platforms get the real implementation. Callers only
// ever touch this web-safe interface.
// ============================================================

import 'printer_config.dart';

import 'thermal_printer_stub.dart'
    if (dart.library.io) 'thermal_printer_io.dart';

abstract class ThermalPrinter {
  /// True only on platforms that can drive an ESC/POS printer
  /// (Android / iOS / Windows) — false on web.
  bool get supported;

  /// Discovers nearby printers for a Bluetooth or USB connection.
  /// Network printers are addressed by IP directly (no scan).
  Future<List<DiscoveredPrinter>> discover(PrinterKind kind, {bool isBle = false});

  /// Prints a Kitchen Order Ticket for [kot] (item names + quantities,
  /// table number, waiter name). Accepts either the socket payload
  /// (camelCase) or a REST record (snake_case).
  Future<void> printKotTicket({
    required PrinterConfig config,
    Map<String, dynamic>? branch,
    required Map<String, dynamic> kot,
  });

  /// Sends a short "printer connected" test slip.
  Future<void> testPrint({required PrinterConfig config, Map<String, dynamic>? branch});
}

ThermalPrinter? _instance;

/// Singleton entry point. Resolves to the native or stub implementation
/// depending on the compile target (via [createThermalPrinter]).
ThermalPrinter get thermalPrinter => _instance ??= createThermalPrinter();
