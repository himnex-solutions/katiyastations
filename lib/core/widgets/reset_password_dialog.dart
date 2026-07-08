import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import '../constants/api_constants.dart';
import '../network/api_client.dart';

/// Admin-style password reset (no current password required) — used by
/// both the Super Admin portal (any user) and the branch Manager's Users
/// screen (own-branch users only; enforced server-side too).
Future<void> showResetPasswordDialog(
  BuildContext context, {
  required String userId,
  required String userName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final passCtrl = TextEditingController();
  bool obscure = true;
  bool submitting = false;
  String? error;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.lock_reset_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Reset Password',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Set a new password for $userName. They will be signed out of all devices.',
                style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
            const SizedBox(height: 16),
            TextField(
              controller: passCtrl,
              obscureText: obscure,
              decoration: InputDecoration(
                labelText: 'New Password *',
                helperText: 'Minimum 8 characters',
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                  onPressed: () => setS(() => obscure = !obscure),
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: submitting
                ? null
                : () async {
                    if (passCtrl.text.trim().length < 8) {
                      setS(() => error = 'Password must be at least 8 characters');
                      return;
                    }
                    setS(() { submitting = true; error = null; });
                    try {
                      await ApiClient.instance.patch(
                        ApiConstants.resetUserPassword(userId),
                        data: {'newPassword': passCtrl.text.trim()},
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      messenger.showSnackBar(SnackBar(
                        content: Text('Password reset for $userName.'),
                        backgroundColor: AppColors.success,
                      ));
                    } catch (e) {
                      setS(() { submitting = false; error = 'Error: $e'; });
                    }
                  },
            child: submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Reset Password'),
          ),
        ],
      ),
    ),
  );
}
