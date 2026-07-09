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
        'configured': configured,
      };

  static const _prefsKey = 'thermal_printer_config';
}

// ── Persisted config provider ───────────────────────────────

class PrinterConfigNotifier extends StateNotifier<PrinterConfig> {
  PrinterConfigNotifier() : super(const PrinterConfig()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = PrinterConfig(
      kind: _kindFrom(prefs.getString('${PrinterConfig._prefsKey}.kind')),
      address: prefs.getString('${PrinterConfig._prefsKey}.address') ?? '',
      port: prefs.getInt('${PrinterConfig._prefsKey}.port') ?? 9100,
      name: prefs.getString('${PrinterConfig._prefsKey}.name') ?? '',
      vendorId: prefs.getString('${PrinterConfig._prefsKey}.vendorId') ?? '',
      productId: prefs.getString('${PrinterConfig._prefsKey}.productId') ?? '',
      isBle: prefs.getBool('${PrinterConfig._prefsKey}.isBle') ?? false,
      paperMm: prefs.getInt('${PrinterConfig._prefsKey}.paperMm') ?? 80,
      autoPrintKot: prefs.getBool('${PrinterConfig._prefsKey}.autoPrintKot') ?? false,
      configured: prefs.getBool('${PrinterConfig._prefsKey}.configured') ?? false,
    );
  }

  Future<void> save(PrinterConfig config) async {
    state = config;
    final prefs = await SharedPreferences.getInstance();
    final m = config._toMap();
    await prefs.setString('${PrinterConfig._prefsKey}.kind', m['kind'] as String);
    await prefs.setString('${PrinterConfig._prefsKey}.address', m['address'] as String);
    await prefs.setInt('${PrinterConfig._prefsKey}.port', m['port'] as int);
    await prefs.setString('${PrinterConfig._prefsKey}.name', m['name'] as String);
    await prefs.setString('${PrinterConfig._prefsKey}.vendorId', m['vendorId'] as String);
    await prefs.setString('${PrinterConfig._prefsKey}.productId', m['productId'] as String);
    await prefs.setBool('${PrinterConfig._prefsKey}.isBle', m['isBle'] as bool);
    await prefs.setInt('${PrinterConfig._prefsKey}.paperMm', m['paperMm'] as int);
    await prefs.setBool('${PrinterConfig._prefsKey}.autoPrintKot', m['autoPrintKot'] as bool);
    await prefs.setBool('${PrinterConfig._prefsKey}.configured', m['configured'] as bool);
  }

  Future<void> setAutoPrint(bool value) => save(state.copyWith(autoPrintKot: value));
}

final printerConfigProvider =
    StateNotifierProvider<PrinterConfigNotifier, PrinterConfig>((ref) => PrinterConfigNotifier());
