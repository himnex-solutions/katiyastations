// ============================================================
// KATIYA STATION RMS — THERMAL PRINTER (native implementation)
// Real ESC/POS printing for Android / iOS / Windows over Bluetooth,
// USB or Network (TCP 9100). Builds the Kitchen Order Ticket bytes with
// esc_pos_utils_plus and sends them via flutter_pos_printer_platform.
// Only compiled where dart:io exists (see thermal_printer.dart).
// ============================================================

import 'dart:io' show Platform;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:intl/intl.dart';

import 'printer_config.dart';
import 'thermal_printer.dart';

ThermalPrinter createThermalPrinter() => _IoThermalPrinter();

class _IoThermalPrinter implements ThermalPrinter {
  final _manager = PrinterManager.instance;
  CapabilityProfile? _profileCache;

  @override
  bool get supported => Platform.isAndroid || Platform.isIOS || Platform.isWindows;

  PrinterType _type(PrinterKind kind) => switch (kind) {
        PrinterKind.bluetooth => PrinterType.bluetooth,
        PrinterKind.usb => PrinterType.usb,
        PrinterKind.network => PrinterType.network,
      };

  BasePrinterInput _model(PrinterConfig cfg) => switch (cfg.kind) {
        PrinterKind.bluetooth => BluetoothPrinterInput(
            address: cfg.address,
            name: cfg.name.isEmpty ? null : cfg.name,
            isBle: cfg.isBle,
          ),
        PrinterKind.usb => UsbPrinterInput(
            name: cfg.name.isEmpty ? null : cfg.name,
            vendorId: cfg.vendorId.isEmpty ? null : cfg.vendorId,
            productId: cfg.productId.isEmpty ? null : cfg.productId,
          ),
        PrinterKind.network => TcpPrinterInput(ipAddress: cfg.address, port: cfg.port),
      };

  @override
  Future<List<DiscoveredPrinter>> discover(PrinterKind kind, {bool isBle = false}) async {
    if (kind == PrinterKind.network) return const []; // addressed by IP, no scan
    try {
      final devices = await _manager.discovery(type: _type(kind), isBle: isBle).toList();
      return devices
          .map((d) => DiscoveredPrinter(
                name: d.name,
                address: d.address,
                vendorId: d.vendorId,
                productId: d.productId,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> printKotTicket({
    required PrinterConfig config,
    Map<String, dynamic>? branch,
    required Map<String, dynamic> kot,
  }) async {
    await _send(config, await _buildKotBytes(config, branch, kot));
  }

  @override
  Future<void> testPrint({required PrinterConfig config, Map<String, dynamic>? branch}) async {
    await _send(config, await _buildTestBytes(config, branch));
  }

  // ── transport ─────────────────────────────────────────────
  Future<void> _send(PrinterConfig cfg, List<int> bytes) async {
    final type = _type(cfg.kind);
    final connected = await _manager.connect(type: type, model: _model(cfg));
    if (!connected) {
      throw Exception('Could not connect to the printer (${cfg.target})');
    }
    await _manager.send(type: type, bytes: bytes);
    // Network sockets are one-shot; close so the next print reconnects cleanly.
    if (type == PrinterType.network) {
      await _manager.disconnect(type: type);
    }
  }

  // ── ticket building ───────────────────────────────────────
  Future<CapabilityProfile> _profile() async => _profileCache ??= await CapabilityProfile.load();
  PaperSize _paper(PrinterConfig cfg) => cfg.paperMm == 58 ? PaperSize.mm58 : PaperSize.mm80;

  /// Reads a field by camelCase (socket payload) or snake_case (REST record).
  String _f(Map m, String camel, String snake) => (m[camel] ?? m[snake] ?? '').toString().trim();

  String _branchName(Map<String, dynamic>? branch) {
    final n = (branch?['name'] as String?)?.trim();
    return (n != null && n.isNotEmpty ? n : 'KATIYA STATION').toUpperCase();
  }

  Future<List<int>> _buildKotBytes(PrinterConfig cfg, Map<String, dynamic>? branch, Map<String, dynamic> kot) async {
    final g = Generator(_paper(cfg), await _profile());
    var b = <int>[];

    final table = _f(kot, 'tableNumber', 'table_number');
    final kotNo = _f(kot, 'kotNumber', 'kot_number');
    final waiter = _f(kot, 'waiterName', 'waiter_name');
    final createdRaw = kot['createdAt'] ?? kot['created_at'];
    final when = DateTime.tryParse(createdRaw?.toString() ?? '')?.toLocal() ?? DateTime.now();
    final items = (kot['items'] as List?) ?? const [];

    b += g.text(_branchName(branch),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    b += g.text('KITCHEN ORDER — KOT', styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.hr(ch: '=');

    if (table.isNotEmpty) {
      b += g.text('TABLE  $table',
          styles: const PosStyles(bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    }
    if (kotNo.isNotEmpty) b += g.text('KOT #: $kotNo');
    if (waiter.isNotEmpty) b += g.text('Waiter: $waiter');
    b += g.text('Time : ${DateFormat('dd MMM yyyy, hh:mm a').format(when)}');
    b += g.hr();

    var totalQty = 0;
    for (final raw in items) {
      if (raw is! Map) continue;
      if ((raw['status'] as String?) == 'cancelled') continue;
      final name = (raw['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;
      final qty = (raw['quantity'] as num?)?.toInt() ?? 1;
      totalQty += qty;
      b += g.text('$qty x $name', styles: const PosStyles(bold: true, height: PosTextSize.size2));
      final note = (raw['note'] as String?)?.trim();
      if (note != null && note.isNotEmpty) b += g.text('    >> $note');
    }

    b += g.hr();
    b += g.text('Total items: $totalQty', styles: const PosStyles(bold: true, align: PosAlign.right));
    b += g.feed(2);
    b += g.cut();
    return b;
  }

  Future<List<int>> _buildTestBytes(PrinterConfig cfg, Map<String, dynamic>? branch) async {
    final g = Generator(_paper(cfg), await _profile());
    var b = <int>[];
    b += g.text(_branchName(branch),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    b += g.text('Printer Test', styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.hr();
    b += g.text('Connection: ${cfg.kindLabel}');
    b += g.text('Target    : ${cfg.target}');
    b += g.text('Paper     : ${cfg.paperMm}mm');
    b += g.text('Time      : ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}');
    b += g.hr();
    b += g.text('If you can read this, printing works!', styles: const PosStyles(align: PosAlign.center));
    b += g.feed(2);
    b += g.cut();
    return b;
  }
}
