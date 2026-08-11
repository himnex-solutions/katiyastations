// ============================================================
// KATIYA STATION RMS — LOCAL HUB CONFIG (per device)
// Which role this device plays in LAN sync, persisted in SharedPreferences.
// Web-safe: imports no dart:io, so the web build compiles even though it can
// never actually take part (see LanSync's platform split).
// ============================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'lan_protocol.dart';

/// How this device is set up for LAN sync.
class LanConfig {
  /// Master switch. On by default: the whole point is that the safety net is
  /// already there when the internet drops, not something someone remembers to
  /// switch on mid-service.
  final bool enabled;

  /// True on the one device that hosts the hub (the cashier PC).
  final bool isHub;

  /// The hub address this device dials. Defaults to [kDefaultHubHost], the
  /// cashier PC's reserved IP, so a tablet connects to a known machine instead
  /// of broadcasting to find one.
  ///
  /// Empty means auto-discover by UDP broadcast. That is now the deliberate
  /// choice rather than the default: a site whose cashier PC has no fixed
  /// address can clear this field and go back to broadcasting.
  final String manualHost;

  final int port;

  /// Stable per-install id, so the hub can tell peers apart and a device can
  /// ignore the echo of its own publishes.
  final String deviceId;

  const LanConfig({
    this.enabled = true,
    this.isHub = false,
    this.manualHost = kDefaultHubHost,
    this.port = kLanHubPort,
    this.deviceId = '',
  });

  bool get hasManualHost => manualHost.trim().isNotEmpty;

  LanConfig copyWith({
    bool? enabled,
    bool? isHub,
    String? manualHost,
    int? port,
    String? deviceId,
  }) =>
      LanConfig(
        enabled: enabled ?? this.enabled,
        isHub: isHub ?? this.isHub,
        manualHost: manualHost ?? this.manualHost,
        port: port ?? this.port,
        deviceId: deviceId ?? this.deviceId,
      );
}

const _kEnabled = 'lan.enabled';
const _kIsHub = 'lan.isHub';
const _kManualHost = 'lan.manualHost';
const _kPort = 'lan.port';
const _kDeviceId = 'lan.deviceId';

class LanConfigNotifier extends StateNotifier<LanConfig> {
  LanConfigNotifier() : super(const LanConfig()) {
    _load();
  }

  /// Completes once the saved config has been read back, so startup code can
  /// wait for the real values instead of acting on the defaults.
  Future<void> get ready => _ready.future;
  final _ready = Completer<void>();

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    var deviceId = p.getString(_kDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await p.setString(_kDeviceId, deviceId);
    }
    state = LanConfig(
      enabled: p.getBool(_kEnabled) ?? true,
      isHub: p.getBool(_kIsHub) ?? false,
      // Absent key → the site default. A key that IS present is honoured even
      // when empty: that is somebody having deliberately cleared the field to
      // go back to broadcast discovery, and a default must not overrule it.
      manualHost: p.getString(_kManualHost) ?? kDefaultHubHost,
      port: p.getInt(_kPort) ?? kLanHubPort,
      deviceId: deviceId,
    );
    if (!_ready.isCompleted) _ready.complete();
  }

  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, value);
  }

  Future<void> setIsHub(bool value) async {
    state = state.copyWith(isHub: value);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kIsHub, value);
  }

  /// Pins the hub address, or clears it (empty string) to go back to
  /// auto-discovery.
  Future<void> setManualHost(String host) async {
    final trimmed = host.trim();
    state = state.copyWith(manualHost: trimmed);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kManualHost, trimmed);
  }

  Future<void> setPort(int port) async {
    state = state.copyWith(port: port);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kPort, port);
  }
}

final lanConfigProvider =
    StateNotifierProvider<LanConfigNotifier, LanConfig>((ref) => LanConfigNotifier());
