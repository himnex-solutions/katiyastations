// ============================================================
// KATIYA STATION RMS — LAN PRINT STATION (hub side)
//
// The one device that owns the printers. Every other device publishes a
// LanKind.printJob envelope over the local hub and this turns it into paper.
//
// WHY PRINTING MOVED HERE
// Each tablet used to open its own TCP connection to the printers. A thermal
// print server holds ONE session at a time, so five waiters — plus a status
// probe running on every screen — kept that slot permanently occupied, and both
// printers dropped off the network mid-service. Funnelling every ticket through
// the hub means exactly one process ever connects, one ticket at a time.
// Contention stops being something to tune and stops existing.
//
// THREE THINGS KEEP TICKETS OFF THE FLOOR
//  1. One queue per printer, so a jammed kitchen printer cannot hold up the bar
//     tickets queued behind it.
//  2. Bounded retry — "out of paper" is usually over in ten seconds, and a
//     ticket that needed a second attempt is not a ticket anyone should lose.
//  3. A record of what has already printed that survives a restart. LAN
//     delivery is deliberately at-least-once, so the same job WILL arrive
//     twice; without this, restarting the cashier PC mid-service reprints
//     everything the tablets still hold in their resend buffers.
// ============================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lan/lan_config.dart';
import '../lan/lan_sync.dart';
import 'kot_print_queue.dart';
import 'printer_config.dart';
import 'thermal_printer.dart';

/// Attempts per ticket before it is given up on and reported to the cashier.
const int _kAttempts = 3;

/// Gap between attempts. Long enough for someone to push paper in, short enough
/// that the ticket is not stale by the time it lands at the pass.
const Duration _kRetryGap = Duration(seconds: 4);

/// How many finished job ids are remembered across restarts. A busy service is
/// a few hundred tickets, so this comfortably covers one.
const int _kPrintedMemory = 500;

const String _kPrintedKey = 'lan.printedPrintJobs';

/// What the hub's printers have been doing, for the Settings card.
class LanPrintStationState {
  /// True when this device is the hub and is listening for tickets.
  final bool active;

  final int printed;
  final int failed;

  /// Tickets waiting behind the ones on the printers right now.
  final int pending;

  /// Why the last ticket failed — the thing a cashier actually needs to read.
  final String lastError;

  final DateTime? lastAt;

  const LanPrintStationState({
    this.active = false,
    this.printed = 0,
    this.failed = 0,
    this.pending = 0,
    this.lastError = '',
    this.lastAt,
  });

  LanPrintStationState copyWith({
    bool? active,
    int? printed,
    int? failed,
    int? pending,
    String? lastError,
    DateTime? lastAt,
  }) =>
      LanPrintStationState(
        active: active ?? this.active,
        printed: printed ?? this.printed,
        failed: failed ?? this.failed,
        pending: pending ?? this.pending,
        lastError: lastError ?? this.lastError,
        lastAt: lastAt ?? this.lastAt,
      );

  String get headline {
    if (!active) return 'Printing runs on each device';
    if (failed > 0) return '$printed printed · $failed failed';
    return '$printed printed for the floor';
  }
}

class LanPrintStationNotifier extends StateNotifier<LanPrintStationState> {
  LanPrintStationNotifier(this._ref) : super(const LanPrintStationState()) {
    _ref.listen<LanConfig>(
      lanConfigProvider,
      (_, next) => _applyConfig(next),
      fireImmediately: true,
    );
  }

  final Ref _ref;
  StreamSubscription<LanEnvelope>? _sub;

  /// One queue per printer role. Built lazily — a restaurant with no bar never
  /// creates the receipt queue.
  final Map<String, KotPrintQueue> _queues = {};

  final _PrintedJobs _printed = _PrintedJobs();

  void _applyConfig(LanConfig cfg) {
    // Only the hub owns the printers, and only where a printer can be driven at
    // all (never on web).
    final shouldRun = cfg.enabled && cfg.isHub && thermalPrinter.supported;
    if (shouldRun == (_sub != null)) return;

    if (!shouldRun) {
      _sub?.cancel();
      _sub = null;
      _queues.clear();
      if (mounted) state = const LanPrintStationState();
      return;
    }

    _sub = LanSync.instance.applied.listen(_onEnvelope);
    if (mounted) state = state.copyWith(active: true);
  }

  Future<void> _onEnvelope(LanEnvelope env) async {
    if (env.kind != LanKind.printJob) return;

    final role = env.data['role'] as String?;
    final ticket = env.data['ticket'];
    if (role == null || !LanPrintRole.all.contains(role) || ticket is! Map) {
      return;
    }

    await _printed.load();
    // Already on paper. At-least-once delivery makes this the normal path for a
    // resend after a blip, not an error worth reporting.
    if (_printed.contains(env.id)) return;

    final job = <String, dynamic>{
      ...Map<String, dynamic>.from(ticket),
      // KotPrintQueue dedups on this. It must be the JOB id and not the KOT
      // number: a cancellation slip carries the same KOT number as the order it
      // voids, so keying on that would silently swallow the cancellation.
      'id': env.id,
    };

    _queueFor(role).add(job);
    _touch();
  }

  KotPrintQueue _queueFor(String role) => _queues.putIfAbsent(
        role,
        () => KotPrintQueue(
          printKot: (job) => _print(role, job),
          onError: _recordFailure,
        ),
      );

  /// Prints one ticket, retrying before giving up.
  ///
  /// The job is written to the printed record only once paper has actually come
  /// out — recording it on receipt would mean a ticket that failed is
  /// permanently marked as done and can never be re-sent.
  Future<void> _print(String role, Map<String, dynamic> job) async {
    final cfg = _ref.read(role == LanPrintRole.kitchen
        ? kotPrinterConfigProvider
        : receiptPrinterConfigProvider);

    if (!cfg.configured) {
      // Worth an explicit failure rather than a silent drop: this device has
      // been made the hub, so the floor is relying on it to have the printers.
      throw StateError(
          'This device is the local hub but has no ${_roleLabel(role)} printer '
          'set up — Settings → Thermal Printer.');
    }

    Object? lastError;
    for (var attempt = 1; attempt <= _kAttempts; attempt++) {
      try {
        await thermalPrinter.printKotTicket(config: cfg, kot: job);
        await _printed.add(job['id'] as String);
        if (mounted) {
          state = state.copyWith(
            printed: state.printed + 1,
            pending: _pending,
            lastAt: DateTime.now(),
          );
        }
        return;
      } catch (e) {
        lastError = e;
        if (attempt < _kAttempts) await Future<void>.delayed(_kRetryGap);
      }
    }
    throw Exception(lastError);
  }

  void _recordFailure(Map<String, dynamic> job, Object error) {
    if (!mounted) return;
    final label = (job['kotNumber'] ?? job['kot_number'] ?? '').toString();
    state = state.copyWith(
      failed: state.failed + 1,
      pending: _pending,
      lastError: label.isEmpty ? '$error' : 'KOT $label — $error',
      lastAt: DateTime.now(),
    );
  }

  int get _pending =>
      _queues.values.fold(0, (sum, queue) => sum + queue.pending);

  void _touch() {
    if (mounted) state = state.copyWith(pending: _pending);
  }

  static String _roleLabel(String role) =>
      role == LanPrintRole.kitchen ? 'KOT' : 'receipt';

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Job ids already put on paper, persisted so a hub restart does not reprint
/// everything the tablets still hold in their resend buffers.
class _PrintedJobs {
  final List<String> _order = [];
  final Set<String> _ids = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _order
      ..clear()
      ..addAll(prefs.getStringList(_kPrintedKey) ?? const []);
    _ids
      ..clear()
      ..addAll(_order);
  }

  bool contains(String id) => _ids.contains(id);

  Future<void> add(String id) async {
    if (!_ids.add(id)) return;
    _order.add(id);
    if (_order.length > _kPrintedMemory) {
      final excess = _order.length - _kPrintedMemory;
      for (var i = 0; i < excess; i++) {
        _ids.remove(_order[i]);
      }
      _order.removeRange(0, excess);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kPrintedKey, _order);
  }
}

/// Watched once from AppShell so the hub is listening for tickets the whole
/// session. Inert on every device that is not the hub.
final lanPrintStationProvider =
    StateNotifierProvider<LanPrintStationNotifier, LanPrintStationState>(
  (ref) => LanPrintStationNotifier(ref),
);
