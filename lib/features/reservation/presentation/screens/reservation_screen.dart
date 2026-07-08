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

final reservationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.reservations,
    queryParameters: {'branchId': profile!.branchId!},
  );
  final data = response.data as Map<String, dynamic>;
  return List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
});

class ReservationScreen extends ConsumerStatefulWidget {
  const ReservationScreen({super.key});
  @override
  ConsumerState<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends ConsumerState<ReservationScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final resAsync = ref.watch(reservationsProvider);
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
              child: const Icon(Icons.event_available,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Reservations',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppColors.textPrimary)),
            ),
          ],
        ),
        actions: [
          TextButton.icon(icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New Reservation'), onPressed: () => _showAddDialog(context)),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 48, color: AppColors.surface,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: ['all', 'pending', 'confirmed', 'arrived', 'completed', 'cancelled', 'no_show'].map((s) => GestureDetector(
                onTap: () => setState(() => _filter = s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: _filter == s ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _filter == s ? AppColors.primary : AppColors.border),
                  ),
                  alignment: Alignment.center,
                  child: Text(s == 'no_show' ? 'No Show' : s.replaceAll('_', ' ').toUpperCase().substring(0, 1) + s.replaceAll('_', ' ').substring(1),
                      style: GoogleFonts.outfit(fontSize: 12, color: _filter == s ? AppColors.primary : AppColors.textSecondary)),
                ),
              )).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: resAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (rows) {
                final filtered = _filter == 'all' ? rows : rows.where((r) => r['status'] == _filter).toList();
                if (filtered.isEmpty) {
                  return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.event_seat_outlined, size: 64, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  Text('No reservations found', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: () => _showAddDialog(context), child: const Text('Add Reservation')),
                ]));
                }
                return ResponsiveContent(child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final r = filtered[i];
                    final status = r['status'] as String;
                    final color = _statusColor(status);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.2))),
                      child: Row(children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.event_seat_rounded, color: color, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r['customer_name'] ?? 'Guest', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          Text('${r['guest_count'] ?? 1} guests • ${r['customer_phone'] ?? '—'}', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                          Text(r['reservation_time'] ?? '', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.primary)),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(status.toUpperCase(), style: GoogleFonts.outfit(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(height: 6),
                          if (status == 'pending' || status == 'confirmed')
                            PopupMenuButton<String>(
                              child: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary, size: 18),
                              onSelected: (s) => _updateStatus(r['id'] as String, s),
                              itemBuilder: (_) => ['confirmed', 'arrived', 'completed', 'cancelled', 'no_show'].map((s) =>
                                  PopupMenuItem(value: s, child: Text(s.toUpperCase()))).toList(),
                            ),
                        ]),
                      ]),
                    ).animate().fadeIn(delay: Duration(milliseconds: i * 25));
                  },
                ));
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed': return AppColors.success;
      case 'arrived': return AppColors.info;
      case 'completed': return AppColors.primary;
      case 'cancelled': case 'no_show': return AppColors.error;
      default: return AppColors.warning;
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    await ApiClient.instance.patch(
      ApiConstants.updateReservationStatus(id),
      data: {'status': status},
    );
    ref.invalidate(reservationsProvider);
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final guestsCtrl = TextEditingController(text: '2');
    final notesCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(hours: 2));

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('New Reservation'),
      content: StatefulBuilder(builder: (ctx, set) => SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Customer Name *')),
        const SizedBox(height: 12),
        TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number')),
        const SizedBox(height: 12),
        TextField(controller: guestsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number of Guests')),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () async {
            final picked = await showDateTimePicker(context, selectedDate);
            if (picked != null) set(() => selectedDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.calendar_today_rounded, color: AppColors.primary, size: 18),
              const SizedBox(width: 10),
              Text(DateFormat('dd MMM yyyy, HH:mm').format(selectedDate), style: GoogleFonts.outfit(color: AppColors.textPrimary)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Special Notes'), maxLines: 2),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () async {
          final profile = ref.read(authNotifierProvider).value;
          await ApiClient.instance.post(
            ApiConstants.reservations,
            data: {
              'branchId': profile?.branchId,
              'customerName': nameCtrl.text.trim(),
              'customerPhone': phoneCtrl.text.trim().isEmpty ? '' : phoneCtrl.text.trim(),
              'guestCount': int.tryParse(guestsCtrl.text) ?? 2,
              'reservationTime': selectedDate.toIso8601String(),
              'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
            },
          );
          ref.invalidate(reservationsProvider);
          if (context.mounted) Navigator.pop(ctx);
        }, child: const Text('Book')),
      ],
    ));
  }

  Future<DateTime?> showDateTimePicker(BuildContext context, DateTime initial) async {
    final date = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}
