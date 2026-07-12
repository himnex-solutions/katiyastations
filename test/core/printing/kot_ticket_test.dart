import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katiya_station_rms/core/printing/kot_ticket.dart';
import 'package:katiya_station_rms/core/printing/printer_config.dart';

/// What actually lands on the paper: the ESC/POS stream with its control
/// sequences consumed, one entry per printed line.
///
/// Command lengths are those of the sequences this ticket emits (see
/// esc_pos_utils_plus `commands.dart`): `ESC @` is 2 bytes, `ESC $ nL nH` is 4,
/// every other ESC/GS command here carries exactly one argument byte.
List<String> _printedLines(List<int> bytes) {
  const esc = 0x1B, gs = 0x1D, fs = 0x1C, lf = 0x0A;
  final lines = <String>[];
  final line = StringBuffer();

  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b == esc) {
      final cmd = i + 1 < bytes.length ? bytes[i + 1] : 0;
      i += switch (cmd) {
        0x40 => 2, // ESC @  — initialize
        0x24 => 4, // ESC $  — absolute position
        _ => 3, // ESC ! / a / E / M / t / d / - …
      };
    } else if (b == gs) {
      i += 3; // GS ! n, GS B n, GS V 0
    } else if (b == fs) {
      i += 2; // FS & / FS .
    } else if (b == lf) {
      lines.add(line.toString().trimRight());
      line.clear();
      i++;
    } else {
      if (b >= 0x20 && b <= 0x7E) line.writeCharCode(b);
      i++;
    }
  }
  if (line.isNotEmpty) lines.add(line.toString().trimRight());
  return lines.where((l) => l.trim().isNotEmpty).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CapabilityProfile profile;

  setUpAll(() async => profile = await CapabilityProfile.load());

  const kot = {
    'kotNumber': 'KOT-0042',
    'tableNumber': '12',
    'waiterName': 'Ram Bahadur',
    'createdAt': '2026-07-12T08:45:00.000Z', // 02:30 PM in Nepal
    'items': [
      {'name': 'Chicken Momo', 'quantity': 2, 'note': 'extra spicy'},
      {'name': 'Veg Chowmein', 'quantity': 1},
      {'name': 'Cancelled Dish', 'quantity': 9, 'status': 'cancelled'},
    ],
  };

  group('buildKotBytes', () {
    test('prints the table, KOT id, time and items — and no company details', () async {
      final lines = _printedLines(
        await buildKotBytes(const PrinterConfig(paperMm: 80), kot, profile: profile),
      );
      final ticket = lines.join('\n');

      expect(ticket, contains('TABLE 12'));
      expect(ticket, contains('KOT-0042'));
      expect(ticket, contains('12 Jul 2026, 02:30 PM'));
      expect(ticket, contains('2 x CHICKEN MOMO'));
      expect(ticket, contains('>> extra spicy'));
      expect(ticket, contains('1 x VEG CHOWMEIN'));
      expect(ticket, contains('Total items: 3'), reason: 'the cancelled item is not cooked');
      expect(ticket, isNot(contains('CANCELLED DISH')));

      // The whole point of the change: a kitchen ticket names no branch,
      // carries no address and no phone number.
      expect(ticket.toUpperCase(), isNot(contains('KATIYA')));
      expect(ticket.toUpperCase(), isNot(contains('PHONE')));
      expect(ticket.toUpperCase(), isNot(contains('TEL')));
    });

    test('a takeaway ticket still leads with a big header', () async {
      final lines = _printedLines(await buildKotBytes(
        const PrinterConfig(paperMm: 80),
        const {'kotNumber': 'KOT-9', 'items': []},
        profile: profile,
      ));
      expect(lines.first, 'TAKEAWAY');
    });

    test('every line fits 58mm paper (32 columns)', () async {
      final lines = _printedLines(await buildKotBytes(
        const PrinterConfig(paperMm: 58),
        {
          ...kot,
          'items': [
            {
              'name': 'Chicken Sekuwa with Extra Garlic Sauce and Salad',
              'quantity': 12,
              'note': 'no onion no garlic please make it very very spicy',
            },
          ],
        },
        profile: profile,
      ));

      for (final line in lines) {
        // The table header prints double-width, so it only gets half the paper.
        final limit = line.startsWith('TABLE') ? 16 : 32;
        expect(line.length, lessThanOrEqualTo(limit), reason: 'overflows 58mm: "$line"');
      }
      expect(lines.join('\n'), contains('SEKUWA'), reason: 'a long name is wrapped, not cut');
    });
  });

  group('wrapForPaper', () {
    test('breaks on words and indents the continuation', () {
      expect(
        wrapForPaper('2 x CHICKEN SEKUWA WITH GARLIC SAUCE', 32, indent: '    '),
        ['2 x CHICKEN SEKUWA WITH GARLIC', '    SAUCE'],
      );
    });

    test('chops a word longer than the paper instead of losing it', () {
      final lines = wrapForPaper('Supercalifragilisticexpialidocious', 16);
      expect(lines.join(), 'Supercalifragilisticexpialidocious');
      expect(lines.every((l) => l.length <= 16), isTrue);
    });
  });
}
