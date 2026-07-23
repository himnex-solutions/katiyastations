// ============================================================
// KATIYA STATION RMS — PRINTER STATUS PILL
// Live "is the printer there?" indicator, shared by the cashier app bar and
// the Settings printer card. Tap for the full picture, a manual re-check,
// and a test slip.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';
import '../utils/date_time_utils.dart';
import '../../features/branches/presentation/providers/branch_provider.dart';
import 'printer_config.dart';
import 'printer_status.dart';
import 'thermal_printer.dart';

Color printerStatusColor(PrinterLinkState state) => switch (state) {
      PrinterLinkState.connected => AppColors.success,
      PrinterLinkState.unreachable => AppColors.error,
      PrinterLinkState.checking => AppColors.textHint,
      PrinterLinkState.notConfigured => AppColors.textHint,
      PrinterLinkState.unsupported => AppColors.warning,
    };

IconData printerStatusIcon(PrinterProbe probe) => switch (probe.kind) {
      PrinterKind.usb => Icons.usb_rounded,
      PrinterKind.bluetooth => Icons.bluetooth_rounded,
      PrinterKind.network => Icons.wifi_tethering_rounded,
      null => Icons.print_rounded,
    };

/// Compact pill for an AppBar. Shows a coloured dot, the transport, and
/// opens [showPrinterStatusSheet] on tap.
///
/// Set [compact] on narrow screens: the cashier app bar already carries two
/// stat pills, and the transport label would push it into a RenderFlex
/// overflow on a phone-width tablet.
class PrinterStatusPill extends ConsumerWidget {
  final bool compact;
  const PrinterStatusPill({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final probe = ref.watch(printerStatusProvider);
    final color = printerStatusColor(probe.state);

    return Tooltip(
      message: probe.detail.isEmpty ? probe.pillLabel : probe.detail,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showPrinterStatusSheet(context),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (probe.state == PrinterLinkState.checking)
                SizedBox(
                  width: 9,
                  height: 9,
                  child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
                )
              else
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              const SizedBox(width: 6),
              Icon(printerStatusIcon(probe), size: 14, color: color),
              if (!compact) ...[
                const SizedBox(width: 5),
                Text(
                  probe.transport.isEmpty ? probe.headline : probe.transport,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width status row for the Settings printer card. Each card passes the
/// status provider for its own printer (receipt or KOT).
class PrinterStatusBanner extends ConsumerWidget {
  final AutoDisposeStateNotifierProvider<PrinterStatusNotifier, PrinterProbe>
      statusProvider;
  const PrinterStatusBanner({super.key, required this.statusProvider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final probe = ref.watch(statusProvider);
    final color = printerStatusColor(probe.state);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(printerStatusIcon(probe), size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  probe.pillLabel,
                  style: GoogleFonts.outfit(
                      fontSize: 13, fontWeight: FontWeight.w700, color: color),
                ),
                if (probe.detail.isNotEmpty)
                  Text(
                    probe.detail,
                    style: GoogleFonts.outfit(
                        fontSize: 11.5, color: AppColors.textSecondary, height: 1.35),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Re-check now',
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: color,
            onPressed: () => ref.read(statusProvider.notifier).refresh(),
          ),
        ],
      ),
    );
  }
}

Future<void> showPrinterStatusSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _PrinterStatusSheet(),
  );
}

class _PrinterStatusSheet extends ConsumerStatefulWidget {
  const _PrinterStatusSheet();
  @override
  ConsumerState<_PrinterStatusSheet> createState() => _PrinterStatusSheetState();
}

class _PrinterStatusSheetState extends ConsumerState<_PrinterStatusSheet> {
  bool _testing = false;

  Future<void> _testPrint() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _testing = true);
    try {
      await thermalPrinter.testPrint(
        config: ref.read(printerConfigProvider),
        branch: ref.read(currentBranchProvider).valueOrNull,
      );
      messenger.showSnackBar(const SnackBar(
          content: Text('Test slip sent to the printer.'),
          backgroundColor: AppColors.success));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Test print failed: $e'),
          backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final probe = ref.watch(printerStatusProvider);
    final cfg = ref.watch(printerConfigProvider);
    final color = printerStatusColor(probe.state);
    final checked = probe.state == PrinterLinkState.checking
        ? null
        : formatTimeWithSeconds(probe.checkedAt);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(printerStatusIcon(probe), color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Printer — ${probe.pillLabel}',
                      style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
            const Divider(height: 20),
            if (probe.detail.isNotEmpty)
              Text(probe.detail,
                  style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.45)),
            if (cfg.configured) ...[
              const SizedBox(height: 12),
              _row('Connection', cfg.kindLabel),
              _row('Target', cfg.target),
              _row('Paper', '${cfg.paperMm}mm'),
              _row('Auto-print KOT', cfg.autoPrintKot ? 'On' : 'Off'),
            ],
            if (checked != null) ...[
              const SizedBox(height: 12),
              Text('Last checked at $checked',
                  style: GoogleFonts.outfit(
                      fontSize: 11, color: AppColors.textHint)),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(printerStatusProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Re-check'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (probe.isConnected && !_testing) ? _testPrint : null,
                    icon: _testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.receipt_long_rounded, size: 16),
                    label: const Text('Test print'),
                  ),
                ),
              ],
            ),
            if (thermalPrinter.supported) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    // Resolve the router before popping — afterwards this
                    // sheet's context is defunct and `context.go` would throw.
                    final router = GoRouter.of(context);
                    Navigator.pop(context);
                    router.go('/settings');
                  },
                  icon: const Icon(Icons.tune_rounded, size: 15),
                  label: Text(
                    cfg.configured ? 'Printer settings' : 'Set up a printer',
                    style: GoogleFonts.outfit(
                        fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: EdgeInsets.zero),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(label,
                  style: GoogleFonts.outfit(
                      fontSize: 12.5, color: AppColors.textHint)),
            ),
            Expanded(
              child: Text(value,
                  style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
          ],
        ),
      );
}
