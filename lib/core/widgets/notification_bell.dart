import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';

/// Bell + red unread count, meant to sit last in an [AppBar.actions] list so it
/// lands in the top-right corner of every screen. Reads
/// [unreadNotificationCountProvider], which the realtime layer refreshes on
/// each `notification:new`, so the badge appears without a reload.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: IconButton(
        tooltip: 'Notifications',
        onPressed: () => context.go('/notifications'),
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread',
              style: GoogleFonts.outfit(
                  fontSize: 10, fontWeight: FontWeight.w700)),
          backgroundColor: AppColors.error,
          textColor: Colors.white,
          child: const Icon(Icons.notifications_outlined,
              color: AppColors.textSecondary, size: 22),
        ),
      ),
    );
  }
}
