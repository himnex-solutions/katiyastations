import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// The backend pages at 20 by default. 100 is the server's `@Max(100)` ceiling
/// — comfortably above what a 12-hour window can accumulate for one role.
const int _notificationPageSize = 100;

/// The bell's alert history for this user's role, newest first.
///
/// The server only ever returns alerts addressed to the caller's role, minus
/// the ones they caused themselves, minus anything older than 12 hours — the
/// server purges those on a schedule, so this list is self-limiting and never
/// grows without bound. Rows are read-only history here; nothing deletes them
/// from the client.
final notificationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
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
  rows.sort(
      (a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
  return rows;
});

/// When this device last opened the bell, as a UTC instant. Anything created
/// after it is "new" and counts toward the red badge; opening the notifications
/// screen advances it to now, which clears the badge.
///
/// Kept per-device on purpose. A notification is one shared row for a whole
/// role, so a server-side read flag would clear the badge on *every* cashier's
/// device the moment one of them looked. A local last-seen mark means each
/// device tracks what it has actually shown its own user.
class NotificationSeen extends Notifier<DateTime> {
  static const _key = 'notifications.lastSeenAtMs';

  @override
  DateTime build() {
    // SharedPreferences is async; start at the epoch (everything looks new)
    // and pull the real mark in a moment. The badge only ever over-counts for
    // that first frame, never under-counts.
    _load();
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_key);
    if (ms == null) return;
    final loaded = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    // Only ever move the mark forward, so a slow load can't clobber a
    // markAllSeen() that already ran while this was in flight.
    if (loaded.isAfter(state)) state = loaded;
  }

  /// Everything up to now has been shown — clear the badge, and remember it so
  /// a reload doesn't light the badge back up for alerts already seen.
  Future<void> markAllSeen() async {
    final now = DateTime.now().toUtc();
    if (now.isAfter(state)) state = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, now.millisecondsSinceEpoch);
  }
}

final notificationSeenProvider =
    NotifierProvider<NotificationSeen, DateTime>(NotificationSeen.new);

/// Drives the red count on every bell: how many alerts arrived since this
/// device last opened the bell. Recomputes when a new alert lands (the
/// realtime layer invalidates [notificationsProvider]) or when the seen mark
/// moves (the user opens the screen).
final unreadNotificationCountProvider = Provider<int>((ref) {
  final rows = ref.watch(notificationsProvider).valueOrNull ?? const [];
  final lastSeen = ref.watch(notificationSeenProvider);
  return rows.where((n) {
    final c = DateTime.tryParse(n['created_at'] as String? ?? '');
    return c != null && c.isAfter(lastSeen);
  }).length;
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
  final isToday =
      when.year == now.year && when.month == now.month && when.day == now.day;
  return isToday
      ? DateFormat('hh:mm a').format(when)
      : DateFormat('dd MMM, hh:mm a').format(when);
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// The seen mark as it stood when this screen opened — captured before we
  /// advance it, so the rows that arrived since the last visit can still be
  /// highlighted as "new" even though the badge is already clearing.
  late final DateTime _seenAtOpen;

  @override
  void initState() {
    super.initState();
    _seenAtOpen = ref.read(notificationSeenProvider);
    // Opening the bell = seeing everything. Do it after the first frame so the
    // badge on the way in isn't torn down mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationSeenProvider.notifier).markAllSeen();
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifsAsync = ref.watch(notificationsProvider);

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
      ),
      body: notifsAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) => rows.isEmpty
            ? Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    const Icon(Icons.notifications_none_rounded,
                        size: 64, color: AppColors.textHint),
                    const SizedBox(height: 16),
                    Text('No notifications',
                        style:
                            GoogleFonts.outfit(color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Text(
                        'Important alerts for you appear here, and clear after 12 hours.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                            fontSize: 12, color: AppColors.textHint)),
                  ]))
            : ResponsiveContent(
                child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                itemBuilder: (ctx, i) {
                  final n = rows[i];
                  final when = _localTime(n['created_at']);
                  final title = (n['title'] ?? 'Notification').toString();
                  final isAlert = title.toLowerCase().contains('stock');
                  // "New" = arrived since the last time this device opened the
                  // bell. Only these get the accent; the rest read as history.
                  final created =
                      DateTime.tryParse(n['created_at'] as String? ?? '');
                  final isNew = created != null && created.isAfter(_seenAtOpen);
                  final accent =
                      isNew ? AppColors.primary : AppColors.textSecondary;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isNew
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : AppColors.border),
                    ),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isAlert
                              ? Icons.warning_rounded
                              : Icons.info_rounded,
                          color: accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Expanded(
                                child: Text(title,
                                    style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        fontWeight: isNew
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: AppColors.textPrimary)),
                              ),
                              if (isNew)
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle),
                                ),
                            ]),
                            const SizedBox(height: 2),
                            Text(n['body'] ?? '',
                                style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                            if (when != null) ...[
                              const SizedBox(height: 4),
                              Text(_timestampLabel(when),
                                  style: GoogleFonts.outfit(
                                      fontSize: 10, color: AppColors.textHint)),
                            ],
                          ])),
                    ]),
                  ).animate().fadeIn(delay: Duration(milliseconds: i * 25));
                },
              )),
      ),
    );
  }
}
