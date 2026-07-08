import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/printing/printer_config.dart';
import '../../../../core/printing/thermal_printer.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../branches/presentation/providers/branch_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.settings,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text('Settings',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: AppColors.textPrimary)),
          ],
        ),
      ),
      body: ResponsiveContent(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader('Branch Details'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.store_rounded, color: AppColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppConstants.restaurantName, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Text('Branch ID: ${profile?.branchId ?? "Default Branch"}', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                ])),
              ]),
            ),
            const SizedBox(height: 24),
            const _SectionHeader('Thermal Printer (KOT / Receipts)'),
            const SizedBox(height: 12),
            const _PrinterSettingsCard(),
            const SizedBox(height: 24),
            const _SectionHeader('System Info'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: const Column(children: [
                _InfoRow('App Version', '1.0.0'),
                Divider(),
                _InfoRow('Local Cache Status', 'Ready'),
              ]),
            ),
          ],
        ),
      )),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  PRINTER SETTINGS CARD — per-device thermal printer setup
// ═══════════════════════════════════════════════════════════════════════
class _PrinterSettingsCard extends ConsumerStatefulWidget {
  const _PrinterSettingsCard();
  @override
  ConsumerState<_PrinterSettingsCard> createState() => _PrinterSettingsCardState();
}

class _PrinterSettingsCardState extends ConsumerState<_PrinterSettingsCard> {
  bool _testing = false;

  Future<void> _openSetup() async {
    final current = ref.read(printerConfigProvider);
    final result = await showModalBottomSheet<PrinterConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PrinterSetupSheet(initial: current),
    );
    if (result != null) {
      await ref.read(printerConfigProvider.notifier).save(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printer saved.'), backgroundColor: AppColors.success),
        );
      }
    }
  }

  Future<void> _testPrint() async {
    final cfg = ref.read(printerConfigProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _testing = true);
    try {
      await thermalPrinter.testPrint(
        config: cfg,
        branch: ref.read(currentBranchProvider).valueOrNull,
      );
      messenger.showSnackBar(const SnackBar(content: Text('Test slip sent to the printer.'), backgroundColor: AppColors.success));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Test print failed: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(printerConfigProvider);
    final supported = thermalPrinter.supported;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        if (!supported)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Thermal printing runs on the kitchen device (Android / Windows). Open the app there to connect a printer — the web app can’t drive one.',
                  style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                ),
              ),
            ]),
          ),
        if (!supported) const SizedBox(height: 14),

        // Current printer summary
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: (cfg.configured ? AppColors.success : AppColors.textHint).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.print_rounded, color: cfg.configured ? AppColors.success : AppColors.textHint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cfg.configured ? (cfg.name.isNotEmpty ? cfg.name : cfg.kindLabel) : 'No printer set up',
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text(cfg.configured ? '${cfg.kindLabel} · ${cfg.target} · ${cfg.paperMm}mm' : 'Tap “Set up” to connect a thermal printer',
                  style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: supported ? _openSetup : null,
              icon: const Icon(Icons.settings_rounded, size: 16),
              label: Text(cfg.configured ? 'Change' : 'Set up'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: (supported && cfg.configured && !_testing) ? _testPrint : null,
              icon: _testing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.receipt_long_rounded, size: 16),
              label: const Text('Test print'),
            ),
          ),
        ]),
        const Divider(height: 28),

        // Auto-print toggle — this makes the device a KOT print station.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: AppColors.primary,
          value: cfg.autoPrintKot,
          onChanged: (supported && cfg.configured)
              ? (v) => ref.read(printerConfigProvider.notifier).setAutoPrint(v)
              : null,
          title: Text('Auto-print KOT on this device',
              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          subtitle: Text(
            'When on, every KOT a waiter sends prints here instantly. Turn this on for the kitchen station only.',
            style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary, height: 1.3),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  PRINTER SETUP SHEET — pick connection + device, paper size
// ═══════════════════════════════════════════════════════════════════════
class _PrinterSetupSheet extends StatefulWidget {
  final PrinterConfig initial;
  const _PrinterSetupSheet({required this.initial});
  @override
  State<_PrinterSetupSheet> createState() => _PrinterSetupSheetState();
}

class _PrinterSetupSheetState extends State<_PrinterSetupSheet> {
  late PrinterKind _kind = widget.initial.kind;
  late int _paperMm = widget.initial.paperMm;
  late bool _isBle = widget.initial.isBle;
  late final _nameCtrl = TextEditingController(text: widget.initial.name);
  late final _addressCtrl = TextEditingController(text: widget.initial.address);
  late final _portCtrl = TextEditingController(text: widget.initial.port.toString());
  String _vendorId = '';
  String _productId = '';

  bool _scanning = false;
  List<DiscoveredPrinter> _devices = [];

  @override
  void initState() {
    super.initState();
    _vendorId = widget.initial.vendorId;
    _productId = widget.initial.productId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _devices = [];
    });
    final found = await thermalPrinter.discover(_kind, isBle: _isBle);
    if (!mounted) return;
    setState(() {
      _devices = found;
      _scanning = false;
    });
  }

  void _pick(DiscoveredPrinter d) {
    setState(() {
      _nameCtrl.text = d.name;
      if (d.address != null) _addressCtrl.text = d.address!;
      _vendorId = d.vendorId ?? '';
      _productId = d.productId ?? '';
    });
  }

  void _save() {
    final isNetwork = _kind == PrinterKind.network;
    final address = _addressCtrl.text.trim();
    if (_kind == PrinterKind.bluetooth && address.isEmpty) {
      _err('Scan and pick a Bluetooth printer first');
      return;
    }
    if (isNetwork && address.isEmpty) {
      _err('Enter the printer IP address');
      return;
    }
    if (_kind == PrinterKind.usb && _nameCtrl.text.trim().isEmpty && _vendorId.isEmpty) {
      _err('Scan and pick a USB printer first');
      return;
    }
    Navigator.pop(
      context,
      widget.initial.copyWith(
        kind: _kind,
        address: address,
        port: int.tryParse(_portCtrl.text.trim()) ?? 9100,
        name: _nameCtrl.text.trim(),
        vendorId: _vendorId,
        productId: _productId,
        isBle: _isBle,
        paperMm: _paperMm,
        configured: true,
      ),
    );
  }

  void _err(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );

  @override
  Widget build(BuildContext context) {
    final isNetwork = _kind == PrinterKind.network;
    final canScan = _kind == PrinterKind.bluetooth || _kind == PrinterKind.usb;

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text('Connect Thermal Printer', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 16),

            Text('Connection', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final k in PrinterKind.values)
                ChoiceChip(
                  label: Text(switch (k) {
                    PrinterKind.bluetooth => 'Bluetooth',
                    PrinterKind.usb => 'USB',
                    PrinterKind.network => 'Network',
                  }),
                  selected: _kind == k,
                  onSelected: (_) => setState(() {
                    _kind = k;
                    _devices = [];
                  }),
                ),
            ]),
            Text(
              _kind == PrinterKind.network ? 'Online — TCP/IP over WiFi or LAN' : 'Offline — direct local connection',
              style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textHint),
            ),
            const SizedBox(height: 16),

            if (_kind == PrinterKind.bluetooth) ...[
              Row(children: [
                Text('Use BLE (Bluetooth LE)', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textPrimary)),
                const Spacer(),
                Switch(value: _isBle, activeThumbColor: AppColors.primary, onChanged: (v) => setState(() => _isBle = v)),
              ]),
            ],

            if (isNetwork) ...[
              TextField(
                controller: _addressCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Printer IP Address', hintText: '192.168.1.100'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Port', hintText: '9100'),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: canScan && !_scanning ? _scan : null,
                  icon: _scanning
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search_rounded, size: 16),
                  label: Text(_scanning ? 'Scanning…' : 'Scan for printers'),
                ),
              ),
              const SizedBox(height: 8),
              if (_devices.isNotEmpty)
                ..._devices.map((d) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.print_rounded, size: 20, color: AppColors.primary),
                      title: Text(d.name.isEmpty ? '(unnamed)' : d.name, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary)),
                      subtitle: Text(d.address ?? [d.vendorId, d.productId].where((e) => e != null).join(':'),
                          style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary)),
                      trailing: _addressCtrl.text == (d.address ?? '') && d.address != null
                          ? const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20)
                          : null,
                      onTap: () => _pick(d),
                    )),
              if (_nameCtrl.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Selected: ${_nameCtrl.text}', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w600)),
                ),
            ],

            const SizedBox(height: 16),
            Text('Paper width', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final mm in [58, 80])
                ChoiceChip(
                  label: Text('${mm}mm'),
                  selected: _paperMm == mm,
                  onSelected: (_) => setState(() => _paperMm = mm),
                ),
            ]),

            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(onPressed: _save, child: const Text('Save Printer'))),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Text(title, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary, letterSpacing: 0.5));
}

class _InfoRow extends StatelessWidget {
  final String l, v;
  const _InfoRow(this.l, this.v);
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(l, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary)),
      Text(v, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
    ],
  );
}
