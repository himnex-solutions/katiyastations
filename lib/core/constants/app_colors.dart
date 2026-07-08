import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary Brand Colors — Deep Crimson Red
  static const Color primary = Color(0xFFC0392B);        // Rich crimson
  static const Color primaryLight = Color(0xFFE74C3C);   // Vivid red
  static const Color primaryDark = Color(0xFF922B21);    // Deep burgundy
  static const Color onPrimary = Color(0xFFFFFFFF);      // White on red

  // Background Colors — Premium White
  static const Color background = Color(0xFFF5F5F5);     // Soft off-white
  static const Color surface = Color(0xFFFFFFFF);        // Pure white
  static const Color surfaceVariant = Color(0xFFF0F0F0); // Light gray
  static const Color card = Color(0xFFFFFFFF);           // White card

  // Text Colors — Dark hierarchy on white
  static const Color textPrimary = Color(0xFF1A1A1A);    // Near-black
  static const Color textSecondary = Color(0xFF6B6B6B);  // Medium gray
  static const Color textOnPrimary = Color(0xFFFFFFFF);  // White on red
  static const Color textHint = Color(0xFFABABAB);       // Light gray hint

  // Status Colors
  static const Color success = Color(0xFF27AE60);        // Emerald green
  static const Color error = Color(0xFFDC3545);          // Alert red, distinct from brand red
  static const Color warning = Color(0xFFF39C12);        // Amber
  static const Color info = Color(0xFF2980B9);           // Blue

  // Table Status Colors
  static const Color tableAvailable = Color(0xFF27AE60);
  static const Color tableOccupied = Color(0xFFC0392B);
  static const Color tableReserved = Color(0xFFF39C12);
  static const Color tableCleaning = Color(0xFF2980B9);

  // Divider / Border — Subtle on white
  static const Color divider = Color(0xFFEEEEEE);
  static const Color border = Color(0xFFE2E2E2);

  // Gradient colors
  static const Color gradientStart = Color(0xFFC0392B);
  static const Color gradientEnd = Color(0xFF7B241C);

  // Role Colors
  static const Color roleManager = Color(0xFFC0392B);
  static const Color roleCashier = Color(0xFF2980B9);
  static const Color roleWaiter = Color(0xFF27AE60);
  static const Color roleKitchen = Color(0xFFE67E22);
  static const Color roleInventory = Color(0xFF8E44AD);
}
