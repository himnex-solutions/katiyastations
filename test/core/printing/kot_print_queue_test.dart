import 'package:flutter_test/flutter_test.dart';
import 'package:katiya_station_rms/core/printing/kot_print_queue.dart';

/// A stand-in printer that records what it was asked to print and, crucially,
/// whether it was ever asked to print two things at once — which is exactly what
/// a real thermal printer cannot survive.
class _FakePrinter {
  final List<String> printed = [];
  final List<String> started = [];
  bool sawOverlap = false;
  int _busy = 0;

  /// How long each ticket takes. The second KOT arrives while the first is
  /// still on the wire, which is the whole point.
  Duration duration = const Duration(milliseconds: 50);

  /// KOT numbers that should blow up instead of printing.
  final Set<String> failOn = {};

  Future<void> call(Map<String, dynamic> kot) async {
    final label = kot['kotNumber'] as String;
    started.add(label);
    if (_busy > 0) sawOverlap = true;
    _busy++;
    try {
      await Future<void>.delayed(duration);
      if (failOn.contains(label)) throw Exception('out of paper');
      printed.add(label);
    } finally {
      _busy--;
    }
  }
}

Map<String, dynamic> _kot(String number, {String? id}) => {
      'id': id ?? 'id-$number',
      'kotNumber': number,
      'tableNumber': '1',
      'items': const [],
    };

void main() {
  // Guards the overlap assertions below: if the fake printer could not notice
  // two concurrent prints, "sawOverlap is false" would pass for the wrong
  // reason. This is the old, un-queued behaviour — fire and don't wait.
  test('the fake printer does notice overlapping prints', () async {
    final printer = _FakePrinter();
    await Future.wait([
      printer.call(_kot('KOT-1')),
      printer.call(_kot('KOT-2')),
    ]);
    expect(printer.sawOverlap, isTrue);
  });

  group('KotPrintQueue', () {
    test('three waiters sending at once print one at a time, in arrival order',
        () async {
      final printer = _FakePrinter();
      final queue = KotPrintQueue(printKot: printer.call);

      // All three land in the same tick — Ram, Sita and Hari all hit Send.
      queue.add(_kot('KOT-1'));
      queue.add(_kot('KOT-2'));
      queue.add(_kot('KOT-3'));

      await queue.idle;

      expect(printer.sawOverlap, isFalse,
          reason: 'two tickets must never be on the printer at the same time');
      expect(printer.printed, ['KOT-1', 'KOT-2', 'KOT-3']);
    });

    test('the same ticket delivered twice prints once', () async {
      final printer = _FakePrinter();
      final queue = KotPrintQueue(printKot: printer.call);

      // What the backend used to do: emit to the kitchen room and the branch
      // room, both of which this station is in.
      queue.add(_kot('KOT-1'));
      queue.add(_kot('KOT-1'));
      await queue.idle;

      // And what a socket reconnect can do: replay it later.
      queue.add(_kot('KOT-1'));
      await queue.idle;

      expect(printer.printed, ['KOT-1']);
    });

    test('a ticket that fails to print does not strand the ones behind it',
        () async {
      final printer = _FakePrinter()..failOn.add('KOT-2');
      final failures = <String>[];

      final queue = KotPrintQueue(
        printKot: printer.call,
        onError: (kot, error) => failures.add(kot['kotNumber'] as String),
      );

      queue.add(_kot('KOT-1'));
      queue.add(_kot('KOT-2')); // printer jams on this one
      queue.add(_kot('KOT-3'));
      await queue.idle;

      expect(printer.printed, ['KOT-1', 'KOT-3']);
      expect(failures, ['KOT-2'], reason: 'the kitchen is told which one failed');
    });

    test('a ticket queued while another is printing still gets printed',
        () async {
      final printer = _FakePrinter();
      final queue = KotPrintQueue(printKot: printer.call);

      queue.add(_kot('KOT-1'));
      // Arrives mid-print, after the drain loop is already running.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      queue.add(_kot('KOT-2'));

      await queue.idle;
      expect(printer.printed, ['KOT-1', 'KOT-2']);
      expect(printer.sawOverlap, isFalse);
      expect(queue.pending, 0);
    });

    test('remembers only the last `memory` tickets, so it cannot grow forever',
        () async {
      final printer = _FakePrinter()..duration = Duration.zero;
      final queue = KotPrintQueue(printKot: printer.call, memory: 2);

      queue.add(_kot('KOT-1'));
      queue.add(_kot('KOT-2'));
      queue.add(_kot('KOT-3')); // pushes KOT-1 out of memory
      await queue.idle;

      queue.add(_kot('KOT-1')); // no longer remembered — prints again
      queue.add(_kot('KOT-3')); // still remembered — skipped
      await queue.idle;

      expect(printer.printed, ['KOT-1', 'KOT-2', 'KOT-3', 'KOT-1']);
    });
  });
}
