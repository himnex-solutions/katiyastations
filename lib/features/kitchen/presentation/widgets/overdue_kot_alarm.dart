import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../orders/domain/entities/order_entities.dart';
import '../providers/kitchen_provider.dart';

/// How long a KOT may sit unaccepted before the kitchen gets shouted at.
const Duration kotAcceptDeadline = Duration(minutes: 5);

/// A KOT can cross the deadline with no data changing, so the banner can't
/// wait for a provider to fire — it re-checks the clock on this cadence.
const Duration _tick = Duration(seconds: 2);

/// Looping siren + red banner shown while any KOT has been sitting in
/// `pending` for longer than [kotAcceptDeadline].
///
/// Deliberately a widget rather than a provider: an alarm that outlived the
/// screen would follow the cook to every other page. Mounted only inside the
/// kitchen screen, it stops the moment that screen is disposed — and it stops
/// on its own as soon as every overdue ticket has been accepted (moved to
/// `preparing`) or rejected (`cancelled`), because either one takes the KOT
/// out of the pending list this watches.
class OverdueKotAlarm extends ConsumerStatefulWidget {
  const OverdueKotAlarm({super.key});

  @override
  ConsumerState<OverdueKotAlarm> createState() => _OverdueKotAlarmState();
}

class _OverdueKotAlarmState extends ConsumerState<OverdueKotAlarm> {
  final AudioPlayer _player = AudioPlayer(playerId: 'kitchen_overdue_alarm');
  Timer? _ticker;
  List<Kot> _overdue = const [];

  /// Tracks what we've asked the player to do. `play()` and `stop()` are async
  /// and the ticker fires every two seconds, so without this we'd restart the
  /// clip from the top on every tick.
  bool _ringing = false;

  @override
  void initState() {
    super.initState();
    _player.setReleaseMode(ReleaseMode.loop);
    _player.setVolume(1.0);
    _ticker = Timer.periodic(_tick, (_) => _evaluate());
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // Fire-and-forget: dispose() can't await, and a stray alarm outliving the
    // screen is exactly what this class exists to prevent.
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  void _evaluate() {
    if (!mounted) return;

    final kots = ref.read(kitchenKotsProvider).valueOrNull ?? const <Kot>[];
    final overdue = kots
        .where((k) => k.isPending && k.elapsed >= kotAcceptDeadline)
        .toList();

    if (overdue.length != _overdue.length) {
      setState(() => _overdue = overdue);
    }
    _setRinging(overdue.isNotEmpty);
  }

  Future<void> _setRinging(bool shouldRing) async {
    if (shouldRing == _ringing) return;
    _ringing = shouldRing;
    try {
      if (shouldRing) {
        await _player.play(AssetSource('sounds/kitchen_alarm.wav'));
      } else {
        await _player.stop();
      }
    } catch (e) {
      // A browser that hasn't seen a user gesture yet will refuse to start
      // audio. The banner below is the fallback, so swallow it rather than
      // taking the kitchen display down over a sound.
      _ringing = false;
      debugPrint('[OverdueKotAlarm] could not ${shouldRing ? 'start' : 'stop'} alarm: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Accepting or rejecting a ticket refreshes this provider (as does a new
    // KOT arriving over the socket), so react to it immediately instead of
    // waiting up to two seconds for the next tick.
    ref.listen(kitchenKotsProvider, (_, __) => _evaluate());

    if (_overdue.isEmpty) return const SizedBox.shrink();

    final count = _overdue.length;
    final oldest = _overdue
        .map((k) => k.elapsed.inMinutes)
        .reduce((a, b) => a > b ? a : b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.error,
      child: Row(
        children: [
          const Icon(Icons.notifications_active_rounded,
              color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 1
                      ? '1 order is still waiting to be accepted'
                      : '$count orders are still waiting to be accepted',
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  'Oldest has been pending for ${oldest}m. Start preparing it, or reject it, to stop the alarm.',
                  style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
