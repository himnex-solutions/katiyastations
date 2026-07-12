import 'package:intl/intl.dart';

/// Nepal Standard Time is UTC+05:45 and never observes daylight saving.
const Duration _nepalOffset = Duration(hours: 5, minutes: 45);

/// The same instant, expressed as Nepal wall-clock time.
///
/// Supabase hands back `created_at` as a UTC instant, so formatting it raw
/// shows staff a clock 5h45m behind the one on the wall. Normalising through
/// UTC first means this is correct no matter what timezone the machine running
/// the app is set to, and it is safe to apply to a value that is already local.
DateTime toNepalTime(DateTime when) => when.toUtc().add(_nepalOffset);

/// Nepal tells the time on a 12-hour clock, so every timestamp the app shows —
/// on screen, on a receipt, on a kitchen ticket — is rendered through one of
/// these. Formatting inline with `DateFormat` is how 24-hour times crept in.
///
/// `02:30 PM`
String formatTime(DateTime when) =>
    DateFormat('hh:mm a').format(toNepalTime(when));

/// `02:30:45 PM`
String formatTimeWithSeconds(DateTime when) =>
    DateFormat('hh:mm:ss a').format(toNepalTime(when));

/// `12 Jul 2026`
String formatDate(DateTime when) =>
    DateFormat('dd MMM yyyy').format(toNepalTime(when));

/// `12 Jul`
String formatShortDate(DateTime when) =>
    DateFormat('dd MMM').format(toNepalTime(when));

/// `12 Jul 2026, 02:30 PM`
String formatDateTime(DateTime when) =>
    DateFormat('dd MMM yyyy, hh:mm a').format(toNepalTime(when));

/// `12 Jul, 02:30 PM`
String formatShortDateTime(DateTime when) =>
    DateFormat('dd MMM, hh:mm a').format(toNepalTime(when));

/// `12 Jul 26, 02:30 PM`
String formatCompactDateTime(DateTime when) =>
    DateFormat('dd MMM yy, hh:mm a').format(toNepalTime(when));

/// `Sunday, 12 Jul 2026`
String formatDayDate(DateTime when) =>
    DateFormat('EEEE, dd MMM yyyy').format(toNepalTime(when));

/// `Sunday, 12 Jul 2026 · 02:30 PM`
String formatDayDateTime(DateTime when) =>
    DateFormat('EEEE, dd MMM yyyy · hh:mm a').format(toNepalTime(when));

/// Whether two instants land on the same Nepal calendar day.
bool isSameNepalDay(DateTime a, DateTime b) {
  final na = toNepalTime(a);
  final nb = toNepalTime(b);
  return na.year == nb.year && na.month == nb.month && na.day == nb.day;
}
