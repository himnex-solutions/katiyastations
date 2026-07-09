// ============================================================
// KATIYA STATION RMS — FCM DEVICE TOKEN REGISTRATION
// Hands this device's FCM token to the backend so NotificationsService can
// actually push to it. Without this, `device_tokens` stays empty forever and
// FcmService.sendToTokens is always called with an empty list — which is
// exactly the state the app was in before: the endpoint existed, nothing
// ever called it.
//
// Called after a successful login and after a restored session, because the
// POST needs a Bearer token.
// ============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../constants/api_constants.dart';
import '../network/api_client.dart';

/// Web Push needs a VAPID key ("Web Push certificate" in the Firebase console
/// under Cloud Messaging). It is not part of firebase_options.dart, so it has
/// to be supplied at build time:
///
///   flutter build web --dart-define=FCM_VAPID_KEY=BEl...
///
/// Without it `getToken()` throws on web, so we skip registration instead.
const String _webVapidKey = String.fromEnvironment('FCM_VAPID_KEY');

/// firebase_messaging ships no Windows or Linux implementation. Calling
/// getToken() there throws, so the Windows till simply never registers —
/// it still receives everything over Socket.IO.
String? _platformName() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => null,
  };
}

StreamSubscription<String>? _refreshSub;

/// Registers the current FCM token, then keeps it fresh. Safe to call more
/// than once — the backend upserts on the token, and the refresh listener is
/// replaced rather than stacked.
///
/// Never throws: push is a nice-to-have layered on a POS that must keep
/// working, exactly like the Firebase.initializeApp guard in main.dart.
Future<void> registerFcmToken() async {
  final platform = _platformName();
  if (platform == null) return;
  if (kIsWeb && _webVapidKey.isEmpty) {
    if (kDebugMode) {
      debugPrint('[FCM] No FCM_VAPID_KEY supplied — web push not registered.');
    }
    return;
  }

  try {
    final messaging = FirebaseMessaging.instance;
    final token = kIsWeb
        ? await messaging.getToken(vapidKey: _webVapidKey)
        : await messaging.getToken();
    if (token == null || token.isEmpty) return;

    await _send(token, platform);

    // FCM rotates tokens (reinstall, restore, long idle). A stale token is a
    // silent delivery failure, so follow the rotation for this session.
    await _refreshSub?.cancel();
    _refreshSub = messaging.onTokenRefresh.listen(
      (fresh) => _send(fresh, platform),
      onError: (_) {},
    );
  } catch (e) {
    if (kDebugMode) debugPrint('[FCM] Token registration failed: $e');
  }
}

/// Drops the token listener on sign-out. The row is left on the server: there
/// is no delete endpoint, and DeviceToken cascades away with the user anyway.
Future<void> disposeFcmRegistration() async {
  await _refreshSub?.cancel();
  _refreshSub = null;
}

Future<void> _send(String token, String platform) async {
  try {
    await ApiClient.instance.post(
      ApiConstants.fcmToken,
      data: {'token': token, 'platform': platform},
    );
  } catch (e) {
    if (kDebugMode) debugPrint('[FCM] Could not send token to backend: $e');
  }
}
