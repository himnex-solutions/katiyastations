// ============================================================
// KATIYA STATION RMS — FIREBASE OPTIONS (STUB)
// ============================================================
// IMPORTANT: This is a stub file for compilation.
// Replace this file with the auto-generated firebase_options.dart
// from the FlutterFire CLI:
//
//   flutter pub global activate flutterfire_cli
//   flutterfire configure
//
// This will generate the real file with your Firebase project
// credentials for Android, iOS, Web, and Windows.
// ============================================================

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  // ── REPLACE THESE WITH YOUR REAL FIREBASE CONFIG VALUES ───
  // Obtain from: Firebase Console → Project Settings → Your Apps

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'katiya-station-rms',
    storageBucket: 'katiya-station-rms.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'katiya-station-rms',
    storageBucket: 'katiya-station-rms.appspot.com',
    iosBundleId: 'com.katiyastation.rms',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_WEB_API_KEY',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'katiya-station-rms',
    storageBucket: 'katiya-station-rms.appspot.com',
    authDomain: 'katiya-station-rms.firebaseapp.com',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'YOUR_WEB_API_KEY',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'katiya-station-rms',
    storageBucket: 'katiya-station-rms.appspot.com',
    authDomain: 'katiya-station-rms.firebaseapp.com',
  );
}
