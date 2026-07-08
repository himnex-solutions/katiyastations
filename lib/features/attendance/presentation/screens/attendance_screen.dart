import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  bool _loading = true;
  String? _staffId;
  String? _noStaffRecordMessage;
  Map<String, dynamic>? _todayRecord;

  @override
  void initState() { super.initState(); _loadTodayRecord(); }

  Future<void> _loadTodayRecord() async {
    setState(() {
      _loading = true;
      _noStaffRecordMessage = null;
    });

    final String staffId;
    try {
      final staffResponse = await ApiClient.instance.get(ApiConstants.myStaffRecord);
      final staff = staffResponse.data as Map<String, dynamic>;
      staffId = staff['id'] as String;
      _staffId = staffId;
    } catch (_) {
      // /staff/me 404s only when this account genuinely has no linked
      // StaffMember record — that's the one case this message is correct for.
      if (mounted) {
        setState(() {
          _loading = false;
          _noStaffRecordMessage =
              'Your account is not linked to a staff record yet. Ask your branch manager to link it.';
        });
      }
      return;
    }

    try {
      final response = await ApiClient.instance.get(ApiConstants.attendanceToday(staffId));
      // When there's no attendance record yet today, the backend sends a
      // body-less response (no Content-Type header) rather than a JSON
      // `null`, which Dio decodes as an empty string — check the type,
      // not just `== null`, or this misparses as an error every time.
      final data = response.data;
      final todayRecord = data is Map<String, dynamic> ? data : null;
      if (mounted) setState(() { _todayRecord = todayRecord; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _noStaffRecordMessage = 'Could not load today\'s attendance: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).value;
    final checkedIn = _todayRecord != null;
    final checkedOut = _todayRecord?['clock_out'] != null;

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
              child: const Icon(Icons.fingerprint,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text('Attendance',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: AppColors.textPrimary)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _noStaffRecordMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_noStaffRecordMessage!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                          onPressed: _loadTodayRecord,
                        ),
                      ],
                    ),
                  ),
                )
              : Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (checkedOut ? AppColors.textSecondary : (checkedIn ? AppColors.success : AppColors.primary)).withValues(alpha: 0.15),
                        ),
                        child: Icon(
                          Icons.fingerprint_rounded,
                          size: 56,
                          color: checkedOut ? AppColors.textSecondary : (checkedIn ? AppColors.success : AppColors.primary),
                        ),
                      ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                      const SizedBox(height: 32),
                      Text(
                        checkedOut ? 'Shift Completed' : (checkedIn ? 'You are Checked In' : 'Not Checked In Yet'),
                        style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        checkedOut
                            ? 'See you tomorrow!'
                            : (checkedIn
                                ? 'Checked in at: ${DateFormat('hh:mm a').format(DateTime.parse(_todayRecord!['clock_in']))}'
                                : 'Press the button below to mark check-in for today'),
                        style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),
                      if (!checkedIn)
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.login_rounded),
                            label: const Text('Mark Check-In'),
                            onPressed: () => _markAttendance(true, profile),
                          ),
                        )
                      else if (!checkedOut)
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('Mark Check-Out'),
                            onPressed: () => _markAttendance(false, profile),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                              const SizedBox(width: 10),
                              Text('Attendance for today is complete.', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _markAttendance(bool isCheckIn, dynamic profile) async {
    if (_staffId == null) return;
    setState(() => _loading = true);

    try {
      if (isCheckIn) {
        await ApiClient.instance.post(ApiConstants.clockIn(_staffId!));
      } else {
        await ApiClient.instance.post(ApiConstants.clockOut(_staffId!));
      }
      await _loadTodayRecord();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error marking attendance: $e'), backgroundColor: AppColors.error),
        );
      }
      setState(() => _loading = false);
    }
  }
}
