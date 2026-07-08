// ============================================================
// KATIYA STATION RMS — NETWORK INFO SERVICE
// Monitors connectivity for offline mode support
// ============================================================

import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkInfo {
  NetworkInfo._();
  static final NetworkInfo instance = NetworkInfo._();

  final Connectivity _connectivity = Connectivity();

  Future<bool> get isConnected async {
    final results = await _connectivity.checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }

  Stream<bool> get connectivityStream => _connectivity.onConnectivityChanged
      .map((results) => !results.contains(ConnectivityResult.none));
}
