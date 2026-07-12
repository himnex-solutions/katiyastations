// ============================================================
// KATIYA STATION RMS — SNACKBARS
// One way to say "done", "careful", or "that failed", so a message can't end
// up unreadable.
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';

/// The app theme pairs a near-black snackbar with white text. Setting only
/// `backgroundColor` on a SnackBar — to a light [AppColors.surfaceVariant], say
/// — keeps that white text and leaves the message invisible, which is exactly
/// what happened to "KOT sent to kitchen". So the status colour rides on the
/// icon, and the surface underneath it never changes.
extension AppSnackBars on ScaffoldMessengerState {
  void showSuccess(String message) =>
      _show(message, AppColors.success, Icons.check_circle_rounded);

  void showError(String message) => _show(
        message,
        AppColors.error,
        Icons.error_outline_rounded,
        duration: const Duration(seconds: 4),
      );

  void showWarning(String message) => _show(
        message,
        AppColors.warning,
        Icons.info_outline_rounded,
        duration: const Duration(seconds: 4),
      );

  void showInfo(String message) =>
      _show(message, AppColors.info, Icons.info_outline_rounded);

  void _show(
    String message,
    Color accent,
    IconData icon, {
    Duration duration = const Duration(seconds: 3),
  }) {
    // A waiter taps quickly; without this the messages queue up and the last
    // one lands seconds after the action that caused it.
    hideCurrentSnackBar();
    showSnackBar(
      SnackBar(
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        content: Row(
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.outfit(
                  color: AppColors.surface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
