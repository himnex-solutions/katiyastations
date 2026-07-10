import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

/// A reusable confirmation modal. Returns `true` when the user confirms,
/// `false` when they cancel or dismiss.
///
/// ```dart
/// final ok = await showConfirmDialog(
///   context,
///   title: 'Sign Out?',
///   message: 'You will need to sign in again to continue.',
///   confirmLabel: 'Sign Out',
///   icon: Icons.logout_rounded,
/// );
/// if (!ok) return;
/// ```
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  Color confirmColor = AppColors.error,
  IconData icon = Icons.warning_amber_rounded,
  // Fills the confirm button with a gradient instead of [confirmColor].
  // [confirmColor] still tints the title icon either way.
  Gradient? confirmGradient,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: confirmColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: confirmColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: GoogleFonts.outfit(
          fontSize: 13.5,
          color: AppColors.textSecondary,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: Text(cancelLabel,
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            // The gradient is painted by the Ink below; the button itself
            // must stay transparent for it to show through.
            backgroundColor:
                confirmGradient == null ? confirmColor : Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: EdgeInsets.zero,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Ink(
            decoration: BoxDecoration(
              color: confirmGradient == null ? confirmColor : null,
              gradient: confirmGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text(confirmLabel,
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// The one sign-out confirmation used everywhere, so the modal looks and
/// reads the same from the side rail, the "More" sheet, and Settings.
Future<bool> showSignOutDialog(BuildContext context) => showConfirmDialog(
      context,
      title: 'Sign Out?',
      message:
          'You will be signed out and need to log in again to continue.',
      confirmLabel: 'Sign Out',
      icon: Icons.logout_rounded,
      confirmColor: AppColors.gradientStart,
      confirmGradient: AppColors.brandGradient,
    );
