// ============================================================
// KATIYA STATION RMS — LOCAL HUB PROTOCOL (platform-neutral)
//
// The wire format for device-to-device sync over the restaurant's own LAN.
//
// WHY THIS EXISTS
// Offline state used to be strictly device-local: a waiter's order lived in
// that tablet's Isar + outbox, and the ONLY route to the cashier's till was
// api.katiyastation.com. When the internet dropped, the KOT still printed
// (the printer is reached directly by LAN IP) but the cashier could not see
// the order to bill it until the connection came back.
//
// This protocol adds the missing route. One device — normally the cashier PC,
// which is always on and at the counter — runs a small HTTP/WebSocket server
// (the "hub"). Every other device finds it by UDP broadcast and publishes the
// same mutations it already queues in its outbox. The hub sequences them into
// a log, mirrors them into its own offline store, and fans them out.
//
// TWO RULES KEEP THIS SAFE
//  1. Every record carries a client-generated UUID (see offline_ids.dart), so
//     the same envelope arriving twice — over the LAN and again over the cloud
//     socket — collapses to one record. Delivery is deliberately at-least-once.
//  2. A device NEVER enqueues a mirrored envelope into its own outbox. The
//     origin device stays the sole uploader of its own work, so a mirror can
//     never cause a duplicate upload or a double-billed session.
//
// Contains no dart:io and no Isar, so the web build can import it freely.
// ============================================================

/// Bumped only on a breaking change to the envelope shape. The hub rejects a
/// client on a different major version rather than misreading its payloads.
const int kLanProtocolVersion = 1;

/// TCP port the hub's HTTP/WebSocket server listens on.
const int kLanHubPort = 8787;

/// UDP port used for hub discovery broadcasts.
const int kLanDiscoveryPort = 8788;

/// Discovery probe a client broadcasts to the subnet. Suffixed with the
/// branchId so two branches sharing a network never adopt each other's hub.
const String kDiscoveryProbePrefix = 'KATIYA_HUB_V1?';

/// Discovery reply a hub unicasts back to the prober.
const String kDiscoveryReplyPrefix = 'KATIYA_HUB_V1!';

/// What a mirrored envelope describes. These map 1:1 onto the offline
/// mutations that already exist in the outbox, so the receiving side can
/// replay them into the very same local structures the screens already read.
class LanKind {
  LanKind._();

  /// A table opened — payload is the session JSON in server shape.
  static const String session = 'session';

  /// An order sent — payload is the KOT plus its line items.
  static const String kot = 'kot';

  /// A session settled — payload identifies the session that was billed.
  static const String bill = 'bill';

  /// A whole order voided — payload identifies the KOT.
  static const String kotVoid = 'kot_void';

  static const List<String> all = [session, kot, bill, kotVoid];
}

/// One replicated mutation travelling over the LAN.
///
/// [seq] is assigned by the hub on receipt and is monotonic per hub run; a
/// client reconnecting passes the highest seq it has seen so the hub can
/// replay only what it missed. [id] is the origin-generated dedup key and is
/// stable across replays — that is what makes at-least-once delivery safe.
class LanEnvelope {
  final int version;
  final int seq;
  final String id;
  final String branchId;
  final String deviceId;
  final String kind;
  final DateTime at;
  final Map<String, dynamic> data;

  const LanEnvelope({
    required this.id,
    required this.branchId,
    required this.deviceId,
    required this.kind,
    required this.at,
    required this.data,
    this.seq = 0,
    this.version = kLanProtocolVersion,
  });

  LanEnvelope withSeq(int newSeq) => LanEnvelope(
        id: id,
        branchId: branchId,
        deviceId: deviceId,
        kind: kind,
        at: at,
        data: data,
        seq: newSeq,
        version: version,
      );

  Map<String, dynamic> toJson() => {
        'v': version,
        'seq': seq,
        'id': id,
        'branchId': branchId,
        'deviceId': deviceId,
        'kind': kind,
        'at': at.toIso8601String(),
        'data': data,
      };

  /// Parses an envelope off the wire, returning null for anything malformed or
  /// from an incompatible protocol version. A hostile or buggy peer on the LAN
  /// must never be able to throw inside the receive loop.
  static LanEnvelope? tryParse(Object? raw) {
    if (raw is! Map) return null;
    try {
      final version = (raw['v'] as num?)?.toInt() ?? 0;
      if (version != kLanProtocolVersion) return null;
      final kind = raw['kind'] as String?;
      if (kind == null || !LanKind.all.contains(kind)) return null;
      final data = raw['data'];
      if (data is! Map) return null;
      return LanEnvelope(
        version: version,
        seq: (raw['seq'] as num?)?.toInt() ?? 0,
        id: raw['id'] as String,
        branchId: raw['branchId'] as String,
        deviceId: raw['deviceId'] as String,
        kind: kind,
        at: DateTime.parse(raw['at'] as String),
        data: Map<String, dynamic>.from(data),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Frame types on the WebSocket, wrapping envelopes with a little control
/// traffic. Kept as bare strings — this is a two-implementation protocol and a
/// sealed hierarchy would cost more than it explains.
class LanFrame {
  LanFrame._();

  /// client → hub: "replicate this mutation"
  static const String publish = 'publish';

  /// hub → client: "here is a mutation" (live, or replayed on catch-up)
  static const String event = 'event';

  /// hub → client: sent once on connect, carries the hub's current head seq.
  static const String hello = 'hello';

  /// Either direction — keeps NAT/idle timeouts from silently dropping the
  /// socket, and lets a client notice a dead hub without waiting on TCP.
  static const String ping = 'ping';
  static const String pong = 'pong';
}

/// How this device currently participates in LAN sync — surfaced in Settings
/// so a manager can see at a glance whether the offline safety net is live.
enum LanRole {
  /// LAN sync is switched off on this device.
  disabled,

  /// This device is the hub; [LanStatus.peerCount] others are connected.
  hub,

  /// Connected to a hub found on the LAN.
  client,

  /// Enabled as a client but no hub is answering yet.
  searching,

  /// This platform can't do LAN sync (web — no server sockets, and a browser
  /// on https can't call a plain-http LAN address).
  unsupported,
}

/// A point-in-time snapshot of LAN sync on this device.
class LanStatus {
  final LanRole role;

  /// Hub address in use ("192.168.1.40:8787"), or empty when not connected.
  final String address;

  /// Devices connected to this hub. Only meaningful for [LanRole.hub].
  final int peerCount;

  /// Envelopes mirrored in since start — the "it's actually working" number.
  final int received;

  final String detail;

  const LanStatus({
    this.role = LanRole.disabled,
    this.address = '',
    this.peerCount = 0,
    this.received = 0,
    this.detail = '',
  });

  bool get isActive => role == LanRole.hub || role == LanRole.client;

  String get headline => switch (role) {
        LanRole.disabled => 'Off',
        LanRole.hub => 'Hub running',
        LanRole.client => 'Connected to hub',
        LanRole.searching => 'Looking for hub…',
        LanRole.unsupported => 'Unavailable',
      };
}
