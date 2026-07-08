import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart' hide ShimmerEffect;
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../constants/app_colors.dart';

/// A reusable skeleton card placeholder for list-based loading states.
/// Wrap with [Skeletonizer] in a ListView to get bone-shimmer animation.
class AppSkeletonCard extends StatelessWidget {
  final double height;
  final bool hasAvatar;
  final bool hasTrailing;

  const AppSkeletonCard({
    super.key,
    this.height = 72,
    this.hasAvatar = true,
    this.hasTrailing = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          if (hasAvatar) ...[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 14, width: 160, color: AppColors.surfaceVariant),
                const SizedBox(height: 6),
                Container(height: 11, width: 110, color: AppColors.surfaceVariant),
              ],
            ),
          ),
          if (hasTrailing) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(height: 14, width: 60, color: AppColors.surfaceVariant),
                const SizedBox(height: 4),
                Container(
                  height: 22,
                  width: 50,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Wraps a list of [AppSkeletonCard] with Skeletonizer shimmer during loading.
class AppSkeletonList extends StatelessWidget {
  final int itemCount;
  final bool hasAvatar;
  final bool hasTrailing;

  const AppSkeletonList({
    super.key,
    this.itemCount = 6,
    this.hasAvatar = true,
    this.hasTrailing = true,
  });

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      effect: const ShimmerEffect(
        baseColor: AppColors.surfaceVariant,
        highlightColor: AppColors.surface,
        duration: Duration(milliseconds: 1200),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: itemCount,
        itemBuilder: (_, __) => AppSkeletonCard(
          hasAvatar: hasAvatar,
          hasTrailing: hasTrailing,
        ),
      ),
    );
  }
}

/// A reusable empty state widget with optional Lottie animation.
/// Falls back to a styled icon + text if Lottie fails or no URL is provided.
class AppEmptyState extends StatelessWidget {
  final String message;
  final String? subtitle;
  final String? lottieUrl;
  final IconData? fallbackIcon;
  final Color? iconColor;
  final VoidCallback? onAction;
  final String? actionLabel;

  const AppEmptyState({
    super.key,
    required this.message,
    this.subtitle,
    this.lottieUrl,
    this.fallbackIcon,
    this.iconColor,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (lottieUrl != null)
              Lottie.network(
                lottieUrl!,
                width: 180,
                height: 180,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _buildIcon(),
              )
            else
              _buildIcon(),
            const SizedBox(height: 20),
            Text(
              message,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.2),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 250.ms),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ).animate().fadeIn(delay: 350.ms).scale(begin: const Offset(0.9, 0.9)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Icon(
      fallbackIcon ?? Icons.inbox_outlined,
      size: 72,
      color: iconColor ?? AppColors.textHint,
    ).animate().scale(duration: 400.ms, curve: Curves.elasticOut);
  }
}

/// A stat summary chip — shows label + value with a coloured border.
class AppStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const AppStatChip({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.outfit(fontSize: 12),
          children: [
            TextSpan(text: '$label: ', style: TextStyle(color: color.withValues(alpha: 0.8))),
            TextSpan(text: value, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
