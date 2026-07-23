// ============================================================
// KATIYA STATION RMS — NETWORK INFO SERVICE
// Monitors connectivity for offline mode support.
//
// "Connected" here means the BACKEND actually answers — not merely that a
// WiFi/Ethernet interface is up. A router with no internet uplink still reports
// its interface as connected, so an interface-only check treated that as online
// and every backend call then hung on its full timeout before falling back to
// the offline path. Every check below is verified against the server.
// ============================================================

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../constants/api_constants.dart';

class NetworkInfo {
  NetworkInfo._();
  static final NetworkInfo instance = NetworkInfo._();

  final Connectivity _connectivity = Connectivity();

  /// Called by the HTTP layer the moment a request proves the backend reachable
  /// (`true`) or unreachable (`false`), so online/offline flips instantly on
  /// real traffic instead of waiting for the next poll. Wired by
  /// ConnectivityController.
  void Function(bool reachable)? onObserved;

  /// True only when an interface is up AND the backend answers.
  Future<bool> get isConnected async {
    final results = await _connectivity.checkConnectivity();
    if (results.contains(ConnectivityResult.none)) return false;
    return _serverReachable();
  }

  /// Emits online/offline on interface changes, each verified against the
  /// backend so "connected to WiFi, no internet" surfaces as offline.
  Stream<bool> get connectivityStream =>
      _connectivity.onConnectivityChanged.asyncMap((results) async {
        if (results.contains(ConnectivityResult.none)) return false;
        return _serverReachable();
      });

  /// Cheap reachability probe: any HTTP answer (even a 404/405) means the
  /// server is reachable; only a connection error or timeout means offline.
  /// Uses its own short timeout so it can never hang the caller.
  Future<bool> _serverReachable() async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
      ));
      await dio.get(
        ApiConstants.baseUrl,
        options: Options(validateStatus: (_) => true),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
