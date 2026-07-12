import 'package:flutter_test/flutter_test.dart';
import 'package:katiya_station_rms/core/utils/date_time_utils.dart';

void main() {
  // 2026-07-12 09:15 UTC is 2026-07-12 3:00 PM in Kathmandu (UTC+05:45).
  final utcAfternoon = DateTime.utc(2026, 7, 12, 9, 15);

  group('toNepalTime', () {
    test('shifts a UTC instant onto the Nepal wall clock', () {
      final nepal = toNepalTime(utcAfternoon);
      expect(nepal.hour, 15);
      expect(nepal.minute, 0);
      expect(nepal.day, 12);
    });

    test('is stable when applied to an already-local DateTime', () {
      // A DateTime built from a picker is local, not UTC. Whatever the test
      // machine's zone, formatting it must not lose the instant it names.
      final local = DateTime(2026, 7, 12, 19, 30);
      expect(toNepalTime(local).difference(local.toUtc()),
          const Duration(hours: 5, minutes: 45));
    });
  });

  group('formatting', () {
    test('renders times on a 12-hour clock with a meridiem', () {
      expect(formatTime(utcAfternoon), '03:00 PM');
      expect(formatTime(DateTime.utc(2026, 7, 12, 1, 15)), '07:00 AM');
      // Midnight and noon are where a 24-hour pattern would leak through.
      expect(formatTime(DateTime.utc(2026, 7, 11, 18, 15)), '12:00 AM');
      expect(formatTime(DateTime.utc(2026, 7, 12, 6, 15)), '12:00 PM');
    });

    test('never emits a 24-hour hour field', () {
      for (var h = 0; h < 24; h++) {
        final label = formatTime(DateTime.utc(2026, 7, 12, h));
        final hour = int.parse(label.split(':').first);
        expect(hour, inInclusiveRange(1, 12), reason: 'UTC hour $h → $label');
        expect(label, anyOf(contains('AM'), contains('PM')));
      }
    });

    test('dates and datetimes carry the Nepal day', () {
      expect(formatDateTime(utcAfternoon), '12 Jul 2026, 03:00 PM');
      expect(formatCompactDateTime(utcAfternoon), '12 Jul 26, 03:00 PM');
      expect(formatShortDateTime(utcAfternoon), '12 Jul, 03:00 PM');
      expect(formatDate(utcAfternoon), '12 Jul 2026');

      // 20:00 UTC is already past midnight in Nepal — the date has to roll
      // forward with it, which is exactly what formatting raw UTC gets wrong.
      final lateEvening = DateTime.utc(2026, 7, 12, 20, 0);
      expect(formatDateTime(lateEvening), '13 Jul 2026, 01:45 AM');
    });
  });

  group('isSameNepalDay', () {
    test('compares Nepal calendar days, not UTC ones', () {
      // Both are 12 Jul in Nepal, but 11 vs 12 Jul in UTC.
      expect(
        isSameNepalDay(
            DateTime.utc(2026, 7, 11, 19, 0), DateTime.utc(2026, 7, 12, 5, 0)),
        isTrue,
      );
      expect(
        isSameNepalDay(
            DateTime.utc(2026, 7, 12, 19, 0), DateTime.utc(2026, 7, 12, 5, 0)),
        isFalse,
      );
    });
  });
}
