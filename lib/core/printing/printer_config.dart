// ============================================================
// KATIYA STATION RMS — THERMAL PRINTER CONFIG
// Web-safe: holds the saved printer setup for THIS device and the
// "auto-print KOT" flag, persisted in SharedPreferences. Imports no
// native printer/dart:io code so it compiles on web too.
// ============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How this device reaches the thermal printer.
///   bluetooth / usb → local, works with no internet ("offline")
///   network         → TCP/IP over WiFi/LAN ("online")
enum PrinterKind { bluetooth, usb, network }

PrinterKind _kindFrom(String? s) =>
    PrinterKind.values.firstWhere((k) => k.name == s, orElse: () => PrinterKind.network);

/// A printer found by a discovery scan (Bluetooth / USB).
class DiscoveredPrinter {
  final String name;
  final String? address;
  final String? vendorId;
  final String? productId;
  const DiscoveredPrinter({required this.name, this.address, this.vendorId, this.productId});
}

/// Outcome of a live connectivity check against the configured printer.
enum PrinterLinkState {
  /// First probe hasn't returned yet.
  checking,

  /// Reachable right now.
  connected,

  /// Configured, but the printer did not answer.
  unreachable,

  /// No printer saved on this device yet.
  notConfigured,

  /// This platform (web) or this transport (Bluetooth on Windows) can't be probed.
  unsupported,
}

/// A point-in-time answer to "is the printer there?".
///
/// [transport] is what the user sees — "USB", "Bluetooth", "Network · Wi-Fi".
/// It is resolved at probe time rather than read off the config, because the
/// network case depends on how *this device* currently reaches the LAN.
class PrinterProbe {
  final PrinterLinkState state;
  final PrinterKind? kind;
  final String transport;
  final String detail;
  final DateTime checkedAt;

  const PrinterProbe({
    required this.state,
    required this.checkedAt,
    this.kind,
    this.transport = '',
    this.detail = '',
  });

  PrinterProbe.checking()
      : state = PrinterLinkState.checking,
        kind = null,
        transport = '',
        detail = 'Checking printer…',
        checkedAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isConnected => state == PrinterLinkState.connected;

  /// Whether a repeated poll is worth running. There is nothing to re-check
  /// when no printer is saved, or when the platform can't reach one at all.
  bool get isPollable =>
      state != PrinterLinkState.notConfigured && state != PrinterLinkState.unsupported;

  String get headline => switch (state) {
        PrinterLinkState.checking => 'Checking…',
        PrinterLinkState.connected => 'Connected',
        PrinterLinkState.unreachable => 'Not reachable',
        PrinterLinkState.notConfigured => 'No printer',
        PrinterLinkState.unsupported => 'Unavailable',
      };

  /// Short label for the status pill: "Connected · USB".
  String get pillLabel =>
      transport.isEmpty ? headline : '$headline · $transport';
}

class PrinterConfig {
  final PrinterKind kind;
  final String address; // BT MAC / TCP host
  final int port; // TCP
  final String name;
  final String vendorId; // USB
  final String productId; // USB
  final bool isBle;
  final int paperMm; // 58 or 80
  final bool autoPrintKot;
  /// Receipt printer only: auto-print the bar/drink items of every KOT here
  /// (the cashier's "bar station" — see bar_auto_print.dart).
  final bool autoPrintBarKot;
  final bool configured;

  const PrinterConfig({
    this.kind = PrinterKind.network,
    this.address = '',
    this.port = 9100,
    this.name = '',
    this.vendorId = '',
    this.productId = '',
    this.isBle = false,
    this.paperMm = 80,
    this.autoPrintKot = false,
    this.autoPrintBarKot = false,
    this.configured = false,
  });

  PrinterConfig copyWith({
    PrinterKind? kind,
    String? address,
    int? port,
    String? name,
    String? vendorId,
    String? productId,
    bool? isBle,
    int? paperMm,
    bool? autoPrintKot,
    bool? autoPrintBarKot,
    bool? configured,
  }) {
    return PrinterConfig(
      kind: kind ?? this.kind,
      address: address ?? this.address,
      port: port ?? this.port,
      name: name ?? this.name,
      vendorId: vendorId ?? this.vendorId,
      productId: productId ?? this.productId,
      isBle: isBle ?? this.isBle,
      paperMm: paperMm ?? this.paperMm,
      autoPrintKot: autoPrintKot ?? this.autoPrintKot,
      autoPrintBarKot: autoPrintBarKot ?? this.autoPrintBarKot,
      configured: configured ?? this.configured,
    );
  }

  String get kindLabel => switch (kind) {
        PrinterKind.bluetooth => 'Bluetooth',
        PrinterKind.usb => 'USB',
        PrinterKind.network => 'Network (LAN/WiFi)',
      };

  String get target => switch (kind) {
        PrinterKind.network => '$address:$port',
        PrinterKind.usb => name.isNotEmpty ? name : 'USB device',
        PrinterKind.bluetooth => name.isNotEmpty ? '$name ($address)' : address,
      };

  Map<String, Object> _toMap() => {
        'kind': kind.name,
        'address': address,
        'port': port,
        'name': name,
        'vendorId': vendorId,
        'productId': productId,
        'isBle': isBle,
        'paperMm': paperMm,
        'autoPrintKot': autoPrintKot,
        'autoPrintBarKot': autoPrintBarKot,
        'configured': configured,
      };
}

// ── Persisted config provider ───────────────────────────────

/// Stores one printer's setup in SharedPreferences under [_key]. A device can
/// hold two of these at once — the receipt printer at the till and the KOT
/// printer in the kitchen — each in its own namespace.
class PrinterConfigNotifier extends StateNotifier<PrinterConfig> {
  PrinterConfigNotifier(this._key) : super(const PrinterConfig()) {
    _load();
  }

  final String _key;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = PrinterConfig(
      kind: _kindFrom(prefs.getString('$_key.kind')),
      address: prefs.getString('$_key.address') ?? '',
      port: prefs.getInt('$_key.port') ?? 9100,
      name: prefs.getString('$_key.name') ?? '',
      vendorId: prefs.getString('$_key.vendorId') ?? '',
      productId: prefs.getString('$_key.productId') ?? '',
      isBle: prefs.getBool('$_key.isBle') ?? false,
      paperMm: prefs.getInt('$_key.paperMm') ?? 80,
      autoPrintKot: prefs.getBool('$_key.autoPrintKot') ?? false,
      autoPrintBarKot: prefs.getBool('$_key.autoPrintBarKot') ?? false,
      configured: prefs.getBool('$_key.configured') ?? false,
    );
  }

  Future<void> save(PrinterConfig config) async {
    state = config;
    final prefs = await SharedPreferences.getInstance();
    final m = config._toMap();
    await prefs.setString('$_key.kind', m['kind'] as String);
    await prefs.setString('$_key.address', m['address'] as String);
    await prefs.setInt('$_key.port', m['port'] as int);
    await prefs.setString('$_key.name', m['name'] as String);
    await prefs.setString('$_key.vendorId', m['vendorId'] as String);
    await prefs.setString('$_key.productId', m['productId'] as String);
    await prefs.setBool('$_key.isBle', m['isBle'] as bool);
    await prefs.setInt('$_key.paperMm', m['paperMm'] as int);
    await prefs.setBool('$_key.autoPrintKot', m['autoPrintKot'] as bool);
    await prefs.setBool('$_key.autoPrintBarKot', m['autoPrintBarKot'] as bool);
    await prefs.setBool('$_key.configured', m['configured'] as bool);
  }

  Future<void> setAutoPrint(bool value) => save(state.copyWith(autoPrintKot: value));
  Future<void> setAutoPrintBar(bool value) => save(state.copyWith(autoPrintBarKot: value));
}

/// The till's receipt / bill printer — typically a USB printer at the cashier.
/// Keeps the original prefs key so any printer already set up carries over.
final receiptPrinterConfigProvider =
    StateNotifierProvider<PrinterConfigNotifier, PrinterConfig>(
        (ref) => PrinterConfigNotifier('thermal_printer_config'));

/// The kitchen's KOT printer — typically a LAN/network printer with no device
/// attached. When [PrinterConfig.autoPrintKot] is on, the ticket prints the
/// instant a waiter taps "Send KOT to Kitchen", straight over the LAN with no
/// internet round-trip.
final kotPrinterConfigProvider =
    StateNotifierProvider<PrinterConfigNotifier, PrinterConfig>(
        (ref) => PrinterConfigNotifier('kot_printer_config'));

/// Backwards-compatible alias. The receipt printer is the device's primary
/// printer, so existing bill and status code keeps working unchanged.
final printerConfigProvider = receiptPrinterConfigProvider;
