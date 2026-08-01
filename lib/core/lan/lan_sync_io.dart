// ============================================================
// KATIYA STATION RMS — LAN SYNC (native: Windows / Android / iOS / desktop)
//
// The real device-to-device channel. Selected by the conditional import in
// lan_sync.dart wherever dart:io exists. Built entirely on dart:io — no new
// packages, no on-site server to install, nothing to keep patched.
//
// TOPOLOGY
//   Cashier PC ("hub")            waiter tablets ("clients")
//   ├─ HttpServer   :8787  ←──── WebSocket /ws?branch&device&since
//   └─ UDP responder :8788 ←──── broadcast "KATIYA_HUB_V1?<branchId>"
//
// The hub sequences every envelope it receives into a log, mirrors it into its
// own offline store, and fans it out to the other devices. A client that
// reconnects passes the highest seq it has seen, so an app restart mid-outage
// catches up instead of losing the orders it missed.
//
// Everything here is best-effort by design. A blocked port, a firewall prompt
// nobody answered, a hub that is switched off — all of it degrades to exactly
// the behaviour that existed before LAN sync, never to a broken POS.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'lan_config.dart';
import 'lan_mirror.dart';
import 'lan_sync.dart';

/// Factory referenced by the conditional import in lan_sync.dart.
LanSync createLanSync() => NativeLanSync();

/// How many envelopes the hub keeps for catch-up. A busy dinner service is a
/// few hundred, so this comfortably covers a whole shift.
const int _kLogLimit = 2000;

/// How long a published envelope is re-sent for after a reconnect. Covers the
/// case that actually bites: the WiFi blips at the exact moment an order is
/// sent, so the frame goes nowhere and no error is ever reported.
const Duration _kResendWindow = Duration(minutes: 5);

const Duration _kHeartbeat = Duration(seconds: 20);
const Duration _kPeerTimeout = Duration(seconds: 90);
const Duration _kConnectTimeout = Duration(seconds: 5);
const Duration _kDiscoveryTimeout = Duration(seconds: 2);

class NativeLanSync implements LanSync {
  final _statusCtrl = StreamController<LanStatus>.broadcast();
  final _appliedCtrl = StreamController<LanEnvelope>.broadcast();

  LanStatus _status = const LanStatus();
  LanConfig? _config;
  String? _branchId;
  bool _stopping = false;
  int _received = 0;

  // ── Hub state ────────────────────────────────────────────────
  final String _runId = const Uuid().v4();
  HttpServer? _server;
  RawDatagramSocket? _responder;
  final List<_Peer> _peers = [];
  final List<LanEnvelope> _log = [];
  final Set<String> _seenIds = {};
  int _headSeq = 0;
  Timer? _hubTimer;

  // ── Client state ─────────────────────────────────────────────
  WebSocket? _client;
  String _hubAddress = '';
  String? _hubRunId;
  int _lastSeq = 0;
  Timer? _reconnectTimer;
  Timer? _clientTimer;
  int _backoffStep = 0;
  DateTime _lastPong = DateTime.fromMillisecondsSinceEpoch(0);
  final List<_Recent> _recent = [];

  /// True while a connect attempt is in flight. Part of [_isRunning] so a
  /// config/auth rebuild landing inside the connect window can't start a
  /// SECOND attempt alongside the first.
  bool _connecting = false;

  /// Bumped by every [stop]. Async callbacks captured under an older epoch —
  /// a socket's onDone arriving after we already tore it down, a connect that
  /// finally resolves after a restart — check this and do nothing.
  ///
  /// Without it the app flaps: an old socket's onDone fires once `stop()` has
  /// already cleared `_client` and `start()` has reset `_stopping`, so it
  /// clears the NEW live socket and schedules a reconnect. The hub then evicts
  /// the peer that reconnects with the same device id, whose onDone repeats the
  /// whole thing — a loop that never settles.
  int _epoch = 0;

  @override
  LanStatus get status => _status;

  @override
  Stream<LanStatus> get statusStream => _statusCtrl.stream;

  @override
  Stream<LanEnvelope> get applied => _appliedCtrl.stream;

  // ── Lifecycle ────────────────────────────────────────────────

  /// Serialises [start] against itself. Two calls landing together would
  /// otherwise interleave across the `await stop()` below, both conclude
  /// nothing is running, and each open a connection — and since the hub evicts
  /// the older peer holding the same device id, the loser's close handler tore
  /// down the winner and the pair flapped indefinitely.
  Future<void> _startLock = Future<void>.value();

  @override
  Future<void> start({required LanConfig config, required String branchId}) {
    final next = _startLock.then((_) => _start(config, branchId));
    _startLock = next.catchError((Object _) {});
    return next;
  }

  Future<void> _start(LanConfig config, String branchId) async {
    // Re-running with the same settings must not tear a healthy link down —
    // this is called from a Riverpod provider that rebuilds on every auth or
    // config change.
    if (_isRunning && _branchId == branchId && _sameConfig(_config, config)) return;

    await stop();
    _stopping = false;
    _config = config;
    _branchId = branchId;

    if (!config.enabled || branchId.isEmpty) {
      _setStatus(const LanStatus());
      return;
    }

    if (config.isHub) {
      await _startHub();
    } else {
      _setStatus(const LanStatus(
        role: LanRole.searching,
        detail: 'Looking for the local hub…',
      ));
      unawaited(_connect());
    }
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    _epoch++; // everything already in flight becomes a no-op
    _connecting = false;
    _hubTimer?.cancel();
    _clientTimer?.cancel();
    _reconnectTimer?.cancel();
    _hubTimer = _clientTimer = _reconnectTimer = null;

    for (final p in List<_Peer>.from(_peers)) {
      try {
        await p.socket.close();
      } catch (_) {}
    }
    _peers.clear();
    _log.clear();
    _seenIds.clear();
    _headSeq = 0;

    try {
      await _client?.close();
    } catch (_) {}
    _client = null;
    _hubAddress = '';
    _hubRunId = null;
    _backoffStep = 0;

    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;

    _responder?.close();
    _responder = null;

    _setStatus(const LanStatus());
  }

  // _connecting matters as much as the rest: a rebuild arriving during the
  // (up to 5s) connect window would otherwise look like "not running" and
  // start a duplicate attempt.
  bool get _isRunning =>
      _server != null || _client != null || _reconnectTimer != null || _connecting;

  bool _sameConfig(LanConfig? a, LanConfig b) =>
      a != null &&
      a.enabled == b.enabled &&
      a.isHub == b.isHub &&
      a.manualHost == b.manualHost &&
      a.port == b.port &&
      a.deviceId == b.deviceId;

  // ── Publish ──────────────────────────────────────────────────

  @override
  void publish(LanEnvelope envelope) {
    final cfg = _config;
    if (cfg == null || !cfg.enabled || _stopping) return;

    if (cfg.isHub) {
      // We are the hub: sequence it and fan it out. No local apply — the origin
      // already wrote this through the normal offline path.
      unawaited(_ingest(envelope));
      return;
    }

    _recent.add(_Recent(envelope, DateTime.now()));
    _pruneRecent();
    _sendToHub(envelope);
  }

  void _sendToHub(LanEnvelope envelope) {
    final ws = _client;
    if (ws == null) return; // flushed from _recent once reconnected
    _send(ws, {'type': LanFrame.publish, 'envelope': envelope.toJson()});
  }

  void _pruneRecent() {
    final cutoff = DateTime.now().subtract(_kResendWindow);
    _recent.removeWhere((r) => r.at.isBefore(cutoff));
  }

  // ── Hub ──────────────────────────────────────────────────────

  Future<void> _startHub() async {
    final cfg = _config!;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, cfg.port);
    } catch (e) {
      // Port busy, or Windows Firewall refused the listen. Keep retrying —
      // a stale instance shutting down frees it a moment later, and the user
      // answering the firewall prompt should not need an app restart.
      _setStatus(LanStatus(
        role: LanRole.searching,
        detail: 'Port ${cfg.port} unavailable — retrying. ($e)',
      ));
      _hubTimer?.cancel();
      _hubTimer = Timer(const Duration(seconds: 10), () {
        if (!_stopping) unawaited(_startHub());
      });
      return;
    }

    _server!.listen(
      (req) => unawaited(_handleRequest(req)),
      onError: (Object _) {},
      cancelOnError: false,
    );

    await _startDiscoveryResponder();

    _hubTimer?.cancel();
    _hubTimer = Timer.periodic(_kHeartbeat, (_) {
      _sweepPeers();
      // Keep the displayed address honest if DHCP moves this machine.
      unawaited(_refreshHubAddress());
    });

    final ip = await _primaryIpv4();
    _setStatus(LanStatus(
      role: LanRole.hub,
      address: '$ip:${cfg.port}',
      peerCount: _peers.length,
      received: _received,
      detail: 'Other devices sync their offline orders to this device.',
    ));
  }

  /// Answers UDP discovery probes so clients need no configuration. Only
  /// probes naming OUR branch get a reply, so two branches on one network
  /// can never adopt each other's hub.
  Future<void> _startDiscoveryResponder() async {
    try {
      final sock = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kLanDiscoveryPort,
        reuseAddress: true,
      );
      sock.broadcastEnabled = true;
      _responder = sock;
      sock.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = sock.receive();
        if (dg == null) return;
        final msg = utf8.decode(dg.data, allowMalformed: true);
        if (!msg.startsWith(kDiscoveryProbePrefix)) return;
        if (msg.substring(kDiscoveryProbePrefix.length) != _branchId) return;
        try {
          sock.send(
            utf8.encode('$kDiscoveryReplyPrefix${_config!.port}'),
            dg.address,
            dg.port,
          );
        } catch (_) {}
      }, onError: (Object _) {});
    } catch (e) {
      // Discovery is a convenience; a client can still pin the address by hand.
      if (kDebugMode) debugPrint('[LanSync] Discovery responder failed: $e');
    }
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      if (req.uri.path == '/health') {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'ok': true,
            'v': kLanProtocolVersion,
            'branchId': _branchId,
            'runId': _runId,
            'seq': _headSeq,
            'peers': _peers.length,
          }));
        await req.response.close();
        return;
      }

      if (req.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
        if (req.uri.queryParameters['branch'] != _branchId) {
          req.response.statusCode = HttpStatus.forbidden;
          await req.response.close();
          return;
        }
        final device = req.uri.queryParameters['device'] ?? '';
        final since = int.tryParse(req.uri.queryParameters['since'] ?? '0') ?? 0;
        final ws = await WebSocketTransformer.upgrade(req);
        _addPeer(ws, device, since);
        return;
      }

      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (_) {
      // A malformed request from anything else on the LAN must not kill the
      // listen loop.
    }
  }

  void _addPeer(WebSocket ws, String deviceId, int since) {
    // One connection per device: a reconnect after a half-open socket would
    // otherwise leave the corpse counted and fanned out to forever.
    for (final stale in _peers.where((p) => p.deviceId == deviceId).toList()) {
      _peers.remove(stale);
      try {
        stale.socket.close();
      } catch (_) {}
    }

    final peer = _Peer(ws, deviceId);
    _peers.add(peer);

    _send(ws, {
      'type': LanFrame.hello,
      'v': kLanProtocolVersion,
      'runId': _runId,
      'seq': _headSeq,
    });

    // Catch-up: everything this device missed while it was away.
    for (final env in _log.where((e) => e.seq > since)) {
      _send(ws, {'type': LanFrame.event, 'envelope': env.toJson()});
    }

    ws.listen(
      (raw) {
        peer.lastSeen = DateTime.now();
        unawaited(_onHubFrame(peer, raw));
      },
      onDone: () => _dropPeer(peer),
      onError: (Object _) => _dropPeer(peer),
      cancelOnError: true,
    );

    _refreshHubStatus();
  }

  void _dropPeer(_Peer peer) {
    if (_peers.remove(peer)) _refreshHubStatus();
  }

  /// Drops peers that stopped answering. A device carried out of WiFi range
  /// leaves a half-open TCP connection that never fires onDone, so without
  /// this the peer count drifts upward all night.
  void _sweepPeers() {
    final cutoff = DateTime.now().subtract(_kPeerTimeout);
    for (final p in List<_Peer>.from(_peers)) {
      if (p.lastSeen.isBefore(cutoff)) {
        try {
          p.socket.close();
        } catch (_) {}
        _peers.remove(p);
      } else {
        _send(p.socket, {'type': LanFrame.ping});
      }
    }
    _refreshHubStatus();
  }

  Future<void> _onHubFrame(_Peer peer, Object? raw) async {
    final map = _decode(raw);
    if (map == null) return;
    switch (map['type']) {
      case LanFrame.publish:
        final env = LanEnvelope.tryParse(map['envelope']);
        if (env == null || env.branchId != _branchId) return;
        await _ingest(env);
        break;
      case LanFrame.ping:
        _send(peer.socket, {'type': LanFrame.pong});
        break;
      case LanFrame.pong:
        break;
    }
  }

  /// Sequences an envelope into the log, mirrors it locally, and fans it out.
  /// Deduplicated on the envelope id, so the same order arriving twice (a
  /// resend after a blip) is replicated exactly once.
  Future<void> _ingest(LanEnvelope env) async {
    if (!_seenIds.add(env.id)) return;

    _headSeq += 1;
    final stamped = env.withSeq(_headSeq);
    _log.add(stamped);
    _trimLog();

    // Only mirror someone else's work — our own is already stored locally.
    if (env.deviceId != _config?.deviceId) {
      await _applyAndEmit(stamped);
    }

    for (final p in _peers) {
      if (p.deviceId == env.deviceId) continue; // don't echo to the origin
      _send(p.socket, {'type': LanFrame.event, 'envelope': stamped.toJson()});
    }
  }

  void _trimLog() {
    if (_log.length <= _kLogLimit) return;
    _log.removeRange(0, _log.length - _kLogLimit);
    _seenIds
      ..clear()
      ..addAll(_log.map((e) => e.id));
  }

  void _refreshHubStatus() {
    if (_status.role != LanRole.hub) return;
    _setStatus(LanStatus(
      role: LanRole.hub,
      address: _status.address,
      peerCount: _peers.length,
      received: _received,
      detail: _peers.isEmpty
          ? 'No other devices connected yet.'
          : 'Other devices sync their offline orders to this device.',
    ));
  }

  // ── Client ───────────────────────────────────────────────────

  Future<void> _connect() async {
    if (_stopping || _connecting || _config == null || _branchId == null) return;
    final cfg = _config!;
    // Everything below is checked against the epoch we started under, so a
    // restart part-way through abandons this attempt instead of racing it.
    final epoch = _epoch;
    _connecting = true;
    try {
      await _attemptConnect(cfg, epoch);
    } finally {
      if (epoch == _epoch) _connecting = false;
    }
  }

  Future<void> _attemptConnect(LanConfig cfg, int epoch) async {
    final host = cfg.hasManualHost ? cfg.manualHost.trim() : await _discoverHub();
    if (_stopping || epoch != _epoch) return;

    if (host == null) {
      _setStatus(LanStatus(
        role: LanRole.searching,
        received: _received,
        detail: 'No local hub found. Turn on “Act as local hub” on the cashier '
            'PC, or set its address by hand.',
      ));
      _scheduleReconnect();
      return;
    }

    try {
      final url = 'ws://$host:${cfg.port}/ws'
          '?branch=${Uri.encodeQueryComponent(_branchId!)}'
          '&device=${Uri.encodeQueryComponent(cfg.deviceId)}'
          '&since=$_lastSeq';
      final ws = await WebSocket.connect(url).timeout(_kConnectTimeout);

      // Torn down or restarted while the handshake was in flight — drop this
      // socket rather than installing it over whatever is live now.
      if (_stopping || epoch != _epoch) {
        await ws.close();
        return;
      }

      _client = ws;
      _hubAddress = '$host:${cfg.port}';
      _backoffStep = 0;
      _lastPong = DateTime.now();

      _setStatus(LanStatus(
        role: LanRole.client,
        address: _hubAddress,
        received: _received,
        detail: 'Offline orders are shared with the cashier over Wi-Fi.',
      ));

      // Re-send anything published recently: a frame that went out just as the
      // socket died was never acknowledged by anyone. The hub dedupes on id,
      // so re-sending is free.
      _pruneRecent();
      for (final r in _recent) {
        _sendToHub(r.envelope);
      }

      _clientTimer?.cancel();
      _clientTimer = Timer.periodic(_kHeartbeat, (_) => _clientHeartbeat());

      ws.listen(
        (raw) => unawaited(_onClientFrame(raw)),
        onDone: () => _onClientClosed(ws, epoch),
        onError: (Object _) => _onClientClosed(ws, epoch),
        cancelOnError: true,
      );
    } catch (e) {
      if (_stopping || epoch != _epoch) return;
      if (kDebugMode) debugPrint('[LanSync] Connect to $host failed: $e');
      _setStatus(LanStatus(
        role: LanRole.searching,
        received: _received,
        detail: 'Hub at $host is not answering — retrying.',
      ));
      _scheduleReconnect();
    }
  }

  void _clientHeartbeat() {
    final ws = _client;
    if (ws == null) return;
    // Two missed heartbeats means the link is dead even though TCP has not
    // noticed — tear it down so the reconnect loop can find the hub again.
    if (DateTime.now().difference(_lastPong) > _kHeartbeat * 3) {
      try {
        ws.close();
      } catch (_) {}
      return;
    }
    _send(ws, {'type': LanFrame.ping});
  }

  /// [closed] is the socket whose close fired. A socket we have already
  /// replaced must not clear the live one — that is what turned a single
  /// dropped connection into an endless connect/disconnect cycle.
  void _onClientClosed(WebSocket closed, int epoch) {
    if (epoch != _epoch) return; // from a previous run entirely
    if (!identical(_client, closed) && _client != null) return; // stale socket
    _client = null;
    _clientTimer?.cancel();
    _clientTimer = null;
    if (_stopping) return;
    _setStatus(LanStatus(
      role: LanRole.searching,
      received: _received,
      detail: 'Lost the local hub — reconnecting.',
    ));
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_stopping) return;
    _reconnectTimer?.cancel();
    // 2s, 4s, 8s, capped at 15s — fast enough that a hub coming back mid-rush
    // is picked up almost at once, slow enough not to spam the LAN all night.
    final seconds = [2, 4, 8, 15][_backoffStep.clamp(0, 3)];
    if (_backoffStep < 3) _backoffStep++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      unawaited(_connect());
    });
  }

  Future<void> _onClientFrame(Object? raw) async {
    final map = _decode(raw);
    if (map == null) return;
    switch (map['type']) {
      case LanFrame.hello:
        final runId = map['runId'] as String?;
        // A different runId means the hub restarted: its log started over, so
        // our saved position is meaningless and would skip everything.
        if (_hubRunId != null && _hubRunId != runId) _lastSeq = 0;
        _hubRunId = runId;
        break;

      case LanFrame.event:
        final env = LanEnvelope.tryParse(map['envelope']);
        if (env == null || env.branchId != _branchId) return;
        if (env.seq > _lastSeq) _lastSeq = env.seq;
        if (env.deviceId == _config?.deviceId) return; // our own echo
        await _applyAndEmit(env);
        break;

      case LanFrame.ping:
        final ws = _client;
        if (ws != null) _send(ws, {'type': LanFrame.pong});
        break;

      case LanFrame.pong:
        _lastPong = DateTime.now();
        break;
    }
  }

  /// Broadcasts for a hub and returns its IP, or null if nothing answers.
  /// The reply's SOURCE address is used rather than anything the hub reports
  /// about itself — a machine with several interfaces routinely guesses wrong.
  Future<String?> _discoverHub() async {
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = true;
      final found = Completer<String?>();
      final socket = sock;

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket.receive();
        if (dg == null) return;
        final msg = utf8.decode(dg.data, allowMalformed: true);
        if (!msg.startsWith(kDiscoveryReplyPrefix)) return;
        if (!found.isCompleted) found.complete(dg.address.address);
      }, onError: (Object _) {
        if (!found.isCompleted) found.complete(null);
      });

      final probe = utf8.encode('$kDiscoveryProbePrefix$_branchId');
      for (final target in await _broadcastTargets()) {
        try {
          socket.send(probe, target, kLanDiscoveryPort);
        } catch (_) {
          // Some interfaces refuse the global broadcast address; the
          // per-subnet ones below usually get through.
        }
      }

      return await found.future
          .timeout(_kDiscoveryTimeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      sock?.close();
    }
  }

  /// The global broadcast address plus a per-subnet one for every IPv4
  /// interface. Android in particular drops 255.255.255.255 on some builds,
  /// where the derived 192.168.x.255 still works.
  Future<List<InternetAddress>> _broadcastTargets() async {
    final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          final broadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          if (targets.any((t) => t.address == broadcast)) continue;
          try {
            targets.add(InternetAddress(broadcast));
          } catch (_) {}
        }
      }
    } catch (_) {}
    return targets;
  }

  /// Best guess at the address other devices see us on. DISPLAY ONLY — the
  /// server binds every interface, and clients learn the real address from the
  /// source of the discovery reply, so nothing depends on getting this right.
  ///
  /// Still worth getting right: a Windows till routinely carries Hyper-V, WSL
  /// or VPN adapters alongside the real one, and "first non-loopback" picks
  /// those about as often as not — which makes the Settings card, and the
  /// manual-address fallback someone copies it into, actively misleading.
  /// Score instead: real private LAN ranges win, virtual adapters and
  /// link-local (169.254.x, what Windows assigns when DHCP never answered)
  /// lose.
  Future<String> _primaryIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      String? best;
      var bestScore = -1 << 20;
      for (final ni in interfaces) {
        final isVirtual = _virtualAdapter.hasMatch(ni.name);
        for (final addr in ni.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          var score = 0;
          if (ip.startsWith('192.168.')) {
            score = 40; // overwhelmingly what a restaurant router hands out
          } else if (ip.startsWith('10.')) {
            score = 30;
          } else if (_isPrivate172(ip)) {
            score = 20; // also where Docker/WSL like to sit
          }
          if (ip.startsWith('169.254.')) score -= 100; // DHCP never answered
          if (isVirtual) score -= 50;
          if (score > bestScore) {
            bestScore = score;
            best = ip;
          }
        }
      }
      if (best != null) return best;
    } catch (_) {}
    return '0.0.0.0';
  }

  static final RegExp _virtualAdapter = RegExp(
    r'virtual|vethernet|vmware|virtualbox|vbox|hyper-?v|docker|wsl|tap|tun|vpn',
    caseSensitive: false,
  );

  static bool _isPrivate172(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4 || parts[0] != '172') return false;
    final second = int.tryParse(parts[1]) ?? -1;
    return second >= 16 && second <= 31;
  }

  /// Re-resolves the displayed address. DHCP can move the till to a different
  /// IP mid-service, and resolving once at startup would leave Settings
  /// showing an address that no longer exists — misleading exactly when
  /// someone is standing there setting the site up.
  Future<void> _refreshHubAddress() async {
    if (_status.role != LanRole.hub || _config == null) return;
    final address = '${await _primaryIpv4()}:${_config!.port}';
    if (address == _status.address) return;
    _setStatus(LanStatus(
      role: LanRole.hub,
      address: address,
      peerCount: _peers.length,
      received: _received,
      detail: _status.detail,
    ));
  }

  // ── Shared ───────────────────────────────────────────────────

  @override
  Future<String?> probe(String host, int port) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client
          .getUrl(Uri.parse('http://$host:$port/health'))
          .timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return 'Hub answered with HTTP ${res.statusCode}.';
      final body = await res.transform(utf8.decoder).join();
      final map = jsonDecode(body);
      if (map is! Map) return 'Unexpected reply from $host.';
      if (map['branchId'] != _branchId) {
        return 'That hub belongs to a different branch.';
      }
      return null;
    } on TimeoutException {
      return 'No answer from $host:$port. Check the address and the firewall.';
    } catch (e) {
      return 'Could not reach $host:$port ($e).';
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _applyAndEmit(LanEnvelope env) async {
    final changed = await LanMirror.apply(env);
    if (!changed) return;
    _received++;
    if (_status.role == LanRole.hub) {
      _refreshHubStatus();
    } else {
      _setStatus(LanStatus(
        role: _status.role,
        address: _status.address,
        peerCount: _status.peerCount,
        received: _received,
        detail: _status.detail,
      ));
    }
    if (!_appliedCtrl.isClosed) _appliedCtrl.add(env);
  }

  Map<String, dynamic>? _decode(Object? raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void _send(WebSocket ws, Map<String, dynamic> frame) {
    try {
      if (ws.readyState == WebSocket.open) ws.add(jsonEncode(frame));
    } catch (_) {
      // A dead socket surfaces through onDone/onError; nothing to do here.
    }
  }

  void _setStatus(LanStatus next) {
    _status = next;
    if (!_statusCtrl.isClosed) _statusCtrl.add(next);
  }
}

class _Peer {
  final WebSocket socket;
  final String deviceId;
  DateTime lastSeen = DateTime.now();
  _Peer(this.socket, this.deviceId);
}

class _Recent {
  final LanEnvelope envelope;
  final DateTime at;
  const _Recent(this.envelope, this.at);
}
