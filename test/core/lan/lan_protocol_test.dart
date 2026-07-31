import 'package:flutter_test/flutter_test.dart';
import 'package:katiya_station_rms/core/lan/lan_mirror.dart';
import 'package:katiya_station_rms/core/lan/lan_protocol.dart';

void main() {
  group('LanEnvelope', () {
    LanEnvelope sample() => LanEnvelope(
          id: 'kot:abc-123',
          branchId: 'branch-1',
          deviceId: 'waiter-tablet',
          kind: LanKind.kot,
          at: DateTime.parse('2026-07-31T19:30:00.000'),
          data: {
            'kot': {'id': 'abc-123', 'kotNumber': 'OFF-3F9A'},
            'items': [
              {'menuItemName': 'Chicken Momo', 'quantity': 2}
            ],
          },
        );

    test('round-trips through JSON unchanged', () {
      final parsed = LanEnvelope.tryParse(sample().toJson());

      expect(parsed, isNotNull);
      expect(parsed!.id, 'kot:abc-123');
      expect(parsed.branchId, 'branch-1');
      expect(parsed.deviceId, 'waiter-tablet');
      expect(parsed.kind, LanKind.kot);
      expect(parsed.at, DateTime.parse('2026-07-31T19:30:00.000'));
      expect(parsed.data['kot'], {'id': 'abc-123', 'kotNumber': 'OFF-3F9A'});
    });

    test('withSeq stamps a sequence without disturbing anything else', () {
      final stamped = sample().withSeq(42);

      expect(stamped.seq, 42);
      expect(stamped.id, sample().id);
      expect(stamped.data, sample().data);
    });

    test('rejects a payload from an incompatible protocol version', () {
      final future = sample().toJson()..['v'] = kLanProtocolVersion + 1;

      // Better to ignore an envelope we might misread than to mirror a
      // half-understood order onto the till.
      expect(LanEnvelope.tryParse(future), isNull);
    });

    test('an item void carries the session, so the receiver can find the KOT',
        () {
      // The offline store is only indexed by session, so a bare kotId would
      // leave the mirror unable to locate the order it must trim.
      final env = LanMirror.kotItemVoidEnvelope(
        deviceId: 'cashier-pc',
        branchId: 'branch-1',
        sessionId: 'session-9',
        kotId: 'kot-9',
        menuItemId: 'menu-momo',
      );

      expect(env.kind, LanKind.kotItemVoid);
      expect(env.data['sessionId'], 'session-9');
      expect(env.data['kotId'], 'kot-9');
      expect(env.data['menuItemId'], 'menu-momo');
      // Stable id: voiding the same line twice must not double-apply.
      expect(env.id, LanMirror.kotItemVoidEnvelope(
        deviceId: 'other-device',
        branchId: 'branch-1',
        sessionId: 'session-9',
        kotId: 'kot-9',
        menuItemId: 'menu-momo',
      ).id);
      expect(LanEnvelope.tryParse(env.toJson()), isNotNull);
    });

    test('rejects unknown kinds and malformed payloads', () {
      expect(LanEnvelope.tryParse(sample().toJson()..['kind'] = 'nonsense'), isNull);
      expect(LanEnvelope.tryParse(sample().toJson()..remove('branchId')), isNull);
      expect(LanEnvelope.tryParse(sample().toJson()..['data'] = 'not-a-map'), isNull);
      expect(LanEnvelope.tryParse(sample().toJson()..['at'] = 'not-a-date'), isNull);
      expect(LanEnvelope.tryParse('a bare string'), isNull);
      expect(LanEnvelope.tryParse(null), isNull);
    });
  });
}
