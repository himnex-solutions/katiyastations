// ============================================================
// KATIYA STATION RMS — THERMAL PRINTER (native implementation)
// Real ESC/POS printing for Android / iOS / Windows over Bluetooth,
// USB or Network (TCP 9100). Builds the Kitchen Order Ticket bytes with
// esc_pos_utils_plus and sends them via flutter_pos_printer_platform.
// Only compiled where dart:io exists (see thermal_printer.dart).
// ============================================================

import 'dart:io' show Platform, Socket, SocketException;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:intl/intl.dart';

import '../utils/date_time_utils.dart';
import 'printer_config.dart';
import 'thermal_printer.dart';

ThermalPrinter createThermalPrinter() => _IoThermalPrinter();

/// Amounts on a receipt always carry both decimals, thousands separated.
final NumberFormat _money2 = NumberFormat('#,##0.00');

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
  Future<void> printBill({
    required PrinterConfig config,
    Map<String, dynamic>? branch,
    required Map<String, dynamic> bill,
    required List<Map<String, dynamic>> items,
  }) async {
    await _send(config, await _buildBillBytes(config, branch, bill, items));
  }

  @override
  Future<void> testPrint({required PrinterConfig config, Map<String, dynamic>? branch}) async {
    await _send(config, await _buildTestBytes(config, branch));
  }

  // ── live connection check ─────────────────────────────────
  //
  // Deliberately never calls PrinterManager.connect(): on Bluetooth and USB
  // that claims the device, which would fight with an in-flight KOT print.
  // Each transport gets the cheapest honest probe available.

  @override
  Future<PrinterProbe> probe(PrinterConfig cfg) async {
    final now = DateTime.now();

    if (!supported) {
      return PrinterProbe(
        state: PrinterLinkState.unsupported,
        checkedAt: now,
        detail: 'This platform cannot drive a thermal printer.',
      );
    }
    if (!cfg.configured) {
      return PrinterProbe(
        state: PrinterLinkState.notConfigured,
        checkedAt: now,
        detail: 'No printer has been set up on this device yet.',
      );
    }

    return switch (cfg.kind) {
      PrinterKind.network => _probeNetwork(cfg),
      PrinterKind.usb => _probeUsb(cfg),
      PrinterKind.bluetooth => _probeBluetooth(cfg),
    };
  }

  /// Opens a TCP connection and drops it immediately — proves the printer is
  /// listening on :port without sending a single byte of ESC/POS.
  Future<PrinterProbe> _probeNetwork(PrinterConfig cfg) async {
    try {
      final socket = await Socket.connect(
        cfg.address,
        cfg.port,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      return PrinterProbe(
        state: PrinterLinkState.connected,
        kind: cfg.kind,
        transport: 'Network · ${await _linkKind()}',
        detail: '${cfg.address}:${cfg.port}',
        checkedAt: DateTime.now(),
      );
    } on SocketException catch (e) {
      // Socket.connect surfaces a timeout as a SocketException too.
      return PrinterProbe(
        state: PrinterLinkState.unreachable,
        kind: cfg.kind,
        transport: 'Network',
        detail: '${cfg.address}:${cfg.port} — ${e.message}',
        checkedAt: DateTime.now(),
      );
    }
  }

  /// Describes how *this device* reaches the LAN. The printer itself is just
  /// an IP — nothing on the wire says whether it is cabled or wireless.
  Future<String> _linkKind() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.ethernet)) return 'Ethernet';
      if (results.contains(ConnectivityResult.wifi)) return 'Wi-Fi';
    } catch (_) {
      // Fall through to the neutral label.
    }
    return 'LAN';
  }

  Future<PrinterProbe> _probeUsb(PrinterConfig cfg) async {
    final devices = await discover(PrinterKind.usb);
    for (final device in devices) {
      if (_usbMatches(device, cfg)) {
        return PrinterProbe(
          state: PrinterLinkState.connected,
          kind: cfg.kind,
          transport: 'USB',
          detail: device.name,
          checkedAt: DateTime.now(),
        );
      }
    }
    return PrinterProbe(
      state: PrinterLinkState.unreachable,
      kind: cfg.kind,
      transport: 'USB',
      detail: devices.isEmpty
          ? 'No USB printer is attached.'
          : '“${cfg.target}” is not among the ${devices.length} attached USB device(s).',
      checkedAt: DateTime.now(),
    );
  }

  /// Android enumerates vendor/product IDs; Windows only reports a name.
  bool _usbMatches(DiscoveredPrinter device, PrinterConfig cfg) {
    final wantVendor = cfg.vendorId.trim();
    final wantProduct = cfg.productId.trim();
    if (wantVendor.isNotEmpty &&
        wantProduct.isNotEmpty &&
        device.vendorId != null &&
        device.productId != null) {
      return device.vendorId == wantVendor && device.productId == wantProduct;
    }
    final wantName = cfg.name.trim().toLowerCase();
    return wantName.isNotEmpty && device.name.trim().toLowerCase() == wantName;
  }

  Future<PrinterProbe> _probeBluetooth(PrinterConfig cfg) async {
    // PrinterManager routes Bluetooth to the BT connector only on Android and
    // iOS; on Windows it falls through to the TCP connector and throws on the
    // input cast. Report that honestly instead of showing "not reachable".
    if (!Platform.isAndroid && !Platform.isIOS) {
      return PrinterProbe(
        state: PrinterLinkState.unsupported,
        kind: cfg.kind,
        transport: 'Bluetooth',
        detail: 'Bluetooth printing is only supported on Android and iOS.',
        checkedAt: DateTime.now(),
      );
    }

    final devices = await discover(PrinterKind.bluetooth, isBle: cfg.isBle);
    final wantAddress = cfg.address.trim().toLowerCase();
    for (final device in devices) {
      if (device.address?.trim().toLowerCase() == wantAddress) {
        return PrinterProbe(
          state: PrinterLinkState.connected,
          kind: cfg.kind,
          transport: 'Bluetooth',
          detail: device.name.isEmpty ? cfg.address : device.name,
          checkedAt: DateTime.now(),
        );
      }
    }
    return PrinterProbe(
      state: PrinterLinkState.unreachable,
      kind: cfg.kind,
      transport: 'Bluetooth',
      detail: 'Printer ${cfg.address} did not answer the scan. '
          'Check it is powered on and in range.',
      checkedAt: DateTime.now(),
    );
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

  /// Same, for money and quantities. Prisma sends Decimal as a string.
  double _n(Map m, String camel, String snake) {
    final raw = m[camel] ?? m[snake];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

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
    final when = DateTime.tryParse(createdRaw?.toString() ?? '') ?? DateTime.now();
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
    b += g.text('Time : ${formatDateTime(when)}');
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

  /// Two-column money line: label left, amount right-aligned to the paper edge.
  List<int> _money(Generator g, String label, double value, {bool bold = false}) =>
      g.row([
        PosColumn(text: label, width: 7, styles: PosStyles(bold: bold)),
        PosColumn(
          text: _money2.format(value),
          width: 5,
          styles: PosStyles(align: PosAlign.right, bold: bold),
        ),
      ]);

  Future<List<int>> _buildBillBytes(
    PrinterConfig cfg,
    Map<String, dynamic>? branch,
    Map<String, dynamic> bill,
    List<Map<String, dynamic>> items,
  ) async {
    final g = Generator(_paper(cfg), await _profile());
    var b = <int>[];

    final invoiceNo = _f(bill, 'invoiceNumber', 'invoice_number');
    final billNo = _f(bill, 'billNumber', 'bill_number');
    final table = _f(bill, 'tableNumber', 'table_number');
    final session = _f(bill, 'sessionNumber', 'session_number');
    final cashier = _f(bill, 'cashierName', 'cashier_name');
    final customer = _f(bill, 'customerName', 'customer_name');
    final method = _f(bill, 'paymentMethod', 'payment_method').toUpperCase();

    final createdRaw = bill['createdAt'] ?? bill['created_at'];
    final when = DateTime.tryParse(createdRaw?.toString() ?? '') ?? DateTime.now();

    final subtotal = _n(bill, 'subTotal', 'sub_total');
    final discount = _n(bill, 'discount', 'discount');
    final service = _n(bill, 'serviceCharge', 'service_charge');
    final vat = _n(bill, 'vatAmount', 'vat_amount');
    final total = _n(bill, 'totalAmount', 'total_amount');
    final paid = _n(bill, 'amountPaid', 'amount_paid');
    final change = _n(bill, 'changeAmount', 'change_amount');

    // An invoice number only exists once the bill has been settled. Before
    // that this is a draft the guest is handed to check, and saying so keeps
    // it from being mistaken for a tax receipt.
    final isInvoice = invoiceNo.isNotEmpty;

    b += g.text(_branchName(branch),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    if (branch?['address'] != null) {
      b += g.text(branch!['address'].toString(), styles: const PosStyles(align: PosAlign.center));
    }
    if (branch?['phone'] != null) {
      b += g.text('Tel: ${branch!['phone']}', styles: const PosStyles(align: PosAlign.center));
    }
    b += g.text(isInvoice ? 'TAX INVOICE' : 'BILL (not a tax invoice)',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.hr(ch: '=');

    if (isInvoice) b += g.text('Invoice No: $invoiceNo', styles: const PosStyles(bold: true));
    if (billNo.isNotEmpty) b += g.text('Bill No   : $billNo');
    if (table.isNotEmpty) b += g.text('Table     : $table');
    if (session.isNotEmpty) b += g.text('Session   : $session');
    b += g.text('Date      : ${formatDateTime(when)}');
    if (cashier.isNotEmpty) b += g.text('Cashier   : $cashier');
    if (customer.isNotEmpty) b += g.text('Customer  : $customer');
    b += g.hr();

    for (final item in items) {
      final name = _f(item, 'menuItemName', 'menu_item_name');
      final label = name.isNotEmpty ? name : _f(item, 'name', 'name');
      if (label.isEmpty) continue;
      final qty = _n(item, 'quantity', 'quantity').toInt();
      final unit = _n(item, 'unitPrice', 'unit_price');
      b += g.row([
        PosColumn(text: '$label x$qty', width: 8),
        PosColumn(text: _money2.format(unit * qty), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    b += g.hr();
    b += _money(g, 'Subtotal', subtotal);
    if (discount > 0) b += _money(g, 'Discount', -discount);
    if (service > 0) b += _money(g, 'Service Charge', service);
    if (vat > 0) b += _money(g, 'VAT', vat);
    b += g.hr();
    b += g.row([
      PosColumn(text: 'TOTAL', width: 6, styles: const PosStyles(bold: true, height: PosTextSize.size2)),
      PosColumn(
        text: 'NPR ${_money2.format(total)}',
        width: 6,
        styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2),
      ),
    ]);

    if (isInvoice) {
      b += g.hr();
      if (method.isNotEmpty) b += g.text('Paid by   : $method');
      if (paid > 0) b += _money(g, 'Amount Paid', paid);
      if (change > 0) b += _money(g, 'Change', change);
    }

    b += g.feed(1);
    b += g.text(isInvoice ? 'Thank you! Please visit again.' : 'Please check before paying.',
        styles: const PosStyles(align: PosAlign.center));
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
    b += g.text('Time      : ${formatDateTime(DateTime.now())}');
    b += g.hr();
    b += g.text('If you can read this, printing works!', styles: const PosStyles(align: PosAlign.center));
    b += g.feed(2);
    b += g.cut();
    return b;
  }
}
