// ============================================================
// KATIYA STATION RMS — THERMAL PRINTER (native implementation)
// Real ESC/POS printing for Android / iOS / Windows over Bluetooth,
// USB or Network (TCP 9100). Builds the Kitchen Order Ticket bytes with
// esc_pos_utils_plus and sends them via flutter_pos_printer_platform.
// Only compiled where dart:io exists (see thermal_printer.dart).
// ============================================================

import 'dart:async' show TimeoutException;
import 'dart:io' show Platform, Socket, SocketException;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:intl/intl.dart';

import '../utils/date_time_utils.dart';
import 'kot_ticket.dart';
import 'printer_config.dart';
import 'thermal_printer.dart';

ThermalPrinter createThermalPrinter() => _IoThermalPrinter();

/// Amounts on a receipt always carry both decimals, thousands separated.
final NumberFormat _money2 = NumberFormat('#,##0.00');

// ── network transport budgets ───────────────────────────────
//
// A print is a foreground action a waiter is stood waiting on, so every step is
// bounded: it is far better to say "that didn't print" in a few seconds than to
// freeze the Send button on a printer that is switched off.

/// Opening the connection. A printer on the same LAN answers in milliseconds;
/// anything past this is off, unplugged, or on the wrong IP.
const Duration _kTcpConnectTimeout = Duration(seconds: 5);

/// Getting the ticket onto the wire.
const Duration _kTcpWriteTimeout = Duration(seconds: 10);

/// Best-effort graceful close after the bytes are away. Bounded because some
/// print servers never close their own end, and a print must not stall on it.
const Duration _kTcpCloseGrace = Duration(seconds: 2);

/// Connect budget for a status probe. Shorter than a real print: this one is
/// answering a question, not delivering an order.
const Duration _kProbeTimeout = Duration(seconds: 2);

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
    required Map<String, dynamic> kot,
  }) async {
    await _send(config, await buildKotBytes(config, kot, profile: await _profile()));
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
  ///
  /// The slot is handed back before anything else runs. A cheap ESC/POS print
  /// server has one session, so holding it even for the length of a
  /// connectivity lookup is time the kitchen ticket behind us cannot connect.
  Future<PrinterProbe> _probeNetwork(PrinterConfig cfg) async {
    Socket? socket;
    try {
      socket = await Socket.connect(cfg.address, cfg.port, timeout: _kProbeTimeout);
    } on SocketException catch (e) {
      // Socket.connect surfaces a timeout as a SocketException too.
      return PrinterProbe(
        state: PrinterLinkState.unreachable,
        kind: cfg.kind,
        transport: 'Network',
        detail: '${cfg.address}:${cfg.port} — ${e.message}',
        checkedAt: DateTime.now(),
      );
    } finally {
      socket?.destroy();
    }

    return PrinterProbe(
      state: PrinterLinkState.connected,
      kind: cfg.kind,
      transport: 'Network · ${await _linkKind()}',
      detail: '${cfg.address}:${cfg.port}',
      checkedAt: DateTime.now(),
    );
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
    // Network printers get their own socket handling — see [_sendOverTcp].
    if (cfg.kind == PrinterKind.network) return _sendOverTcp(cfg, bytes);

    final type = _type(cfg.kind);
    final connected = await _manager.connect(type: type, model: _model(cfg));
    if (!connected) {
      throw Exception('Could not connect to the printer (${cfg.target})');
    }
    // USB and Bluetooth stay connected on purpose: the plugin's connect()
    // claims the device, and re-claiming it per ticket fights an in-flight
    // print. Their send() still reports whether the bytes were taken, and that
    // answer used to be thrown away — a printer that was out of paper or
    // asleep reported a successful print to the waiter.
    if (!await _manager.send(type: type, bytes: bytes)) {
      throw Exception(
          'The printer (${cfg.target}) did not accept the ticket. Check it is '
          'on, has paper, and is still connected.');
    }
  }

  /// Writes [bytes] to a network printer over a connection opened for this one
  /// ticket and always handed back, whatever happens.
  ///
  /// This deliberately bypasses PrinterManager's TCP connector, which cannot be
  /// used safely: it keeps a single socket on a process-wide singleton, its
  /// `disconnect()` is a no-op (the `destroy()` is commented out upstream), and
  /// it only closes the socket on the success path. So every failed write left
  /// a connection open that nothing would ever reclaim — and since these print
  /// servers have one session slot, a handful of failures took the printer off
  /// the network until someone power-cycled it.
  Future<void> _sendOverTcp(PrinterConfig cfg, List<int> bytes) async {
    Socket? socket;
    try {
      socket = await Socket.connect(cfg.address, cfg.port, timeout: _kTcpConnectTimeout);

      // Nothing is expected back, but an un-listened socket turns a reset from
      // the printer into an unhandled async error, and unread bytes sitting in
      // the receive buffer at close time make the OS tear the connection down
      // abortively — which truncates the tail of the ticket. Drain and ignore.
      socket.listen((_) {}, onError: (Object _) {}, cancelOnError: false);

      socket.add(bytes);
      await socket.flush().timeout(_kTcpWriteTimeout);

      // Half-close so the printer sees a clean end of job. Best effort: flush()
      // already put the ticket on the wire, so a printer that never closes its
      // own end must not hold up the next order.
      try {
        await socket.close().timeout(_kTcpCloseGrace, onTimeout: () => null);
      } catch (_) {
        // Already delivered — a messy teardown is not a failed print.
      }
    } on SocketException catch (e) {
      throw Exception(
          'Could not reach the printer at ${cfg.target} — ${e.message}');
    } on TimeoutException {
      throw Exception(
          'The printer at ${cfg.target} took the connection but stopped '
          'reading. The ticket may have printed only in part.');
    } finally {
      // The one line the plugin was missing. Runs on every path, including the
      // failures, so a bad print costs nothing that isn't given straight back.
      socket?.destroy();
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


  /// Centered, bold heading (restaurant name / title) that wraps on word
  /// boundaries, so a long name like "KATIYA STATION RESTAURANT & BAR" prints
  /// on tidy centered lines instead of being chopped mid-word by the printer.
  /// [big] doubles the size, where only half as many columns fit per line.
  List<int> _centeredHeading(Generator g, PrinterConfig cfg, String text, {bool big = false}) {
    final cols = big ? paperCols(cfg) ~/ 2 : paperCols(cfg);
    final styles = PosStyles(
      align: PosAlign.center,
      bold: true,
      height: big ? PosTextSize.size2 : PosTextSize.size1,
      width: big ? PosTextSize.size2 : PosTextSize.size1,
    );
    var out = <int>[];
    for (final line in wrapForPaper(text, cols)) {
      out += g.text(line, styles: styles);
    }
    return out;
  }

  /// Centered normal-width text (address, tagline) that also wraps to the paper.
  List<int> _centeredLines(Generator g, PrinterConfig cfg, String text) {
    var out = <int>[];
    for (final line in wrapForPaper(text, paperCols(cfg))) {
      out += g.text(line, styles: const PosStyles(align: PosAlign.center));
    }
    return out;
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
    final customerPhone = _f(bill, 'customerPhone', 'customer_phone');
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

    b += _centeredHeading(g, cfg, _branchName(branch), big: true);
    if (branch?['address'] != null) {
      b += _centeredLines(g, cfg, branch!['address'].toString());
    }
    if (branch?['phone'] != null) {
      b += _centeredLines(g, cfg, 'Tel: ${branch!['phone']}');
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
    if (customerPhone.isNotEmpty) b += g.text('Contact   : $customerPhone');
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
    b += _centeredHeading(g, cfg, _branchName(branch), big: true);
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
