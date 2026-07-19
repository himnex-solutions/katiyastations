// ============================================================
// KATIYA STATION RMS — OFFLINE / SYNC BANNER
// A thin status strip shown under the app bar when the device is offline or
// still has orders waiting to upload. Hidden entirely when online & synced.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';
import '../offline/connectivity_provider.dart';
import '../offline/sync_engine.dart';

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectivityProvider);
    final pending = ref.watch(pendingSyncProvider);

    // Nothing to say: online and everything already uploaded.
    if (online && pending == 0) return const SizedBox.shrink();

    final Color color;
    final IconData icon;
    final String text;

    if (!online) {
      color = const Color(0xFFF57C00); // amber — working offline
      icon = Icons.cloud_off_rounded;
      text = pending > 0
          ? 'Offline — $pending order${pending == 1 ? '' : 's'} saved, will sync when reconnected'
          : 'Offline — new orders are saved on this device and sync automatically';
    } else {
      color = AppColors.info; // blue — reconnected, uploading
      icon = Icons.cloud_sync_rounded;
      text = 'Syncing $pending order${pending == 1 ? '' : 's'}…';
    }

    return Material(
      color: color.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
