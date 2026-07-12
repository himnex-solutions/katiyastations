// ============================================================
// KATIYA STATION RMS — KOT PRINT QUEUE
// One printer, one ticket at a time. Sits between the `kot:new` socket
// events and the ESC/POS transport so a dinner rush cannot overlap two
// prints on the same device.
// ============================================================

import 'dart:async';
import 'dart:collection';

/// Serialises auto-prints and drops repeats.
///
/// Two things go wrong without it when several waiters send at once:
///
/// * **Overlap.** `Stream.listen` does not wait for an async callback before
///   delivering the next event, so two KOTs arriving milliseconds apart used to
///   run `printKotTicket` concurrently — two `connect()`s and two `send()`s on
///   one printer, and on a network printer the first print's `disconnect()`
///   landing in the middle of the second. The paper came out with both orders
///   mixed together, or one ticket vanished with a connection error.
/// * **Repeats.** The same ticket can reach a station twice — a reconnect that
///   replays an event, or a backend that emits to two rooms the client is both
///   in. A duplicate ticket sends the kitchen a dish nobody ordered, so a KOT
///   that has already been queued is never queued again.
///
/// Tickets print in the order they arrive, which is the order the backend
/// committed them.
class KotPrintQueue {
  KotPrintQueue({
    required this.printKot,
    this.onError,
    this.memory = 500,
  });

  /// Prints one ticket. Must complete before the next one starts.
  final Future<void> Function(Map<String, dynamic> kot) printKot;

  /// Called when a ticket fails to print. The queue moves on to the next one —
  /// a printer that is off or out of paper must not strand every later ticket.
  final void Function(Map<String, dynamic> kot, Object error)? onError;

  /// How many KOT ids to remember for the duplicate check. Bounded so a station
  /// left running for a week does not grow a set of every ticket of the week.
  final int memory;

  final Queue<Map<String, dynamic>> _pending = Queue();
  final Set<String> _seen = <String>{};
  final Queue<String> _seenOrder = Queue();

  bool _printing = false;
  Completer<void>? _idle;

  /// Completes when everything queued so far has been printed (or failed).
  Future<void> get idle => _idle?.future ?? Future.value();

  /// Number of tickets waiting behind the one on the printer.
  int get pending => _pending.length;

  /// Queues [kot], unless this ticket has already been queued.
  void add(Map<String, dynamic> kot) {
    final id = _idOf(kot);
    if (id != null && !_remember(id)) return; // already printed or queued

    _pending.add(kot);
    _idle ??= Completer<void>();
    unawaited(_drain());
  }

  /// Records [id] as seen. Returns false when it was already known — i.e. this
  /// is a duplicate delivery of a ticket the station has handled.
  bool _remember(String id) {
    if (!_seen.add(id)) return false;
    _seenOrder.add(id);
    if (_seenOrder.length > memory) _seen.remove(_seenOrder.removeFirst());
    return true;
  }

  Future<void> _drain() async {
    if (_printing) return;
    _printing = true;

    while (_pending.isNotEmpty) {
      final kot = _pending.removeFirst();
      try {
        await printKot(kot);
      } catch (e) {
        onError?.call(kot, e);
      }
    }

    _printing = false;
    _idle?.complete();
    _idle = null;
  }

  /// The ticket's identity. Falls back to the KOT number when the payload
  /// carries no id, and returns null when it carries neither — an unidentifiable
  /// ticket is printed rather than silently swallowed as a "duplicate".
  static String? _idOf(Map<String, dynamic> kot) {
    for (final key in const ['id', 'kotNumber', 'kot_number']) {
      final value = kot[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }
}
