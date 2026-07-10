import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// The backend pages at 20 by default. 100 is the server's `@Max(100)` ceiling
/// — comfortably above what a 12-hour window can accumulate for one role.
const int _notificationPageSize = 100;

/// The server only ever returns alerts addressed to the caller's role, minus
/// the ones they caused themselves, minus anything older than 12 hours. So
/// every row that arrives here is unread by construction — reading one deletes
/// it server-side rather than flagging it.
final notificationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.notifications,
    queryParameters: {
      'branchId': profile!.branchId!,
      'limit': _notificationPageSize,
    },
  );
  final data = response.data as Map<String, dynamic>;
  final rows = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
  rows.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
  return rows;
});

/// Drives the red count on every bell. Kept live off [notificationsProvider],
/// which the realtime layer invalidates on every `notification:new` addressed
/// to this user's role.
final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).valueOrNull?.length ?? 0;
});

/// `created_at` arrives as a UTC ISO-8601 instant. Rendering it without
/// [DateTime.toLocal] shows Kathmandu staff a clock 5h45m behind the wall.
DateTime? _localTime(Object? raw) {
  if (raw is! String) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

/// Alerts live at most 12 hours, so they either happened today or late
/// yesterday — the day only needs spelling out in the second case.
String _timestampLabel(DateTime when) {
  final now = DateTime.now();
  final isToday = when.year == now.year && when.month == now.month && when.day == now.day;
  return isToday
      ? DateFormat('hh:mm a').format(when)
      : DateFormat('dd MMM, hh:mm a').format(when);
}

/// Reading clears it. A 404 means it expired or another device on the same
/// role already cleared it — either way the list just needs to catch up.
Future<void> _dismiss(WidgetRef ref, String id) async {
  try {
    await ApiClient.instance.patch(ApiConstants.markNotificationRead(id));
  } catch (_) {
    // Swallowed on purpose: the only failure that matters here is "it's
    // already gone", and the refetch below settles the list either way.
  }
  ref.invalidate(notificationsProvider);
}

Future<void> _dismissAll(WidgetRef ref, String branchId) async {
  try {
    await ApiClient.instance.patch(
      ApiConstants.markAllRead,
      queryParameters: {'branchId': branchId},
    );
  } catch (_) {
    // As above.
  }
  ref.invalidate(notificationsProvider);
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifsAsync = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationCountProvider);
    final branchId = ref.watch(authNotifierProvider).value?.branchId;

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
              child: const Icon(Icons.notifications_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text('Notifications',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: AppColors.textPrimary)),
          ],
        ),
        actions: [
          if (unread > 0 && branchId != null)
            TextButton.icon(
              onPressed: () => _dismissAll(ref, branchId),
              icon: const Icon(Icons.done_all_rounded, size: 17),
              label: Text('Mark all read',
                  style: GoogleFonts.outfit(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: notifsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) => rows.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.notifications_none_rounded, size: 64, color: AppColors.textHint),
                const SizedBox(height: 16),
                Text('No notifications', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Text('Alerts meant for you appear here, and clear after 12 hours.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textHint)),
              ]))
            : ResponsiveContent(child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                itemBuilder: (ctx, i) {
                  final n = rows[i];
                  final id = n['id'] as String;
                  final when = _localTime(n['created_at']);
                  final title = (n['title'] ?? 'Notification').toString();
                  final isAlert = title.toLowerCase().contains('stock');

                  return GestureDetector(
                    onTap: () => _dismiss(ref, id),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isAlert ? Icons.warning_rounded : Icons.info_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(title,
                              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text(n['body'] ?? '', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                          if (when != null) ...[
                            const SizedBox(height: 4),
                            Text(_timestampLabel(when),
                                style: GoogleFonts.outfit(fontSize: 10, color: AppColors.textHint)),
                          ],
                        ])),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Mark as read',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.check_circle_outline_rounded,
                              size: 20, color: AppColors.textSecondary),
                          onPressed: () => _dismiss(ref, id),
                        ),
                      ]),
                    ),
                  ).animate().fadeIn(delay: Duration(milliseconds: i * 25));
                },
              )),
      ),
    );
  }
}
