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
    apiKey: 'AIzaSyBPzcYM8r6bWjrs-1GmapIyWgdBK0d7IYE',
    appId: '1:561556257232:android:00663105e77454f79ae1d5',
    messagingSenderId: '561556257232',
    projectId: 'katiyastation-adf42',
    storageBucket: 'katiyastation-adf42.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAkrhOS0At9IdgLpSbChIROleQDR1nVvGk',
    appId: '1:561556257232:ios:fbfe71e4a384d9b59ae1d5',
    messagingSenderId: '561556257232',
    projectId: 'katiyastation-adf42',
    storageBucket: 'katiyastation-adf42.firebasestorage.app',
    iosBundleId: 'com.katiyastation.katiyaStationRms',
  );
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCAO4R-OBI4HK4U9xU2jtZQolFDVIvjITI',
    appId: '1:561556257232:web:e9849d57397877cb9ae1d5',
    messagingSenderId: '561556257232',
    projectId: 'katiyastation-adf42',
    authDomain: 'katiyastation-adf42.firebaseapp.com',
    storageBucket: 'katiyastation-adf42.firebasestorage.app',
    measurementId: 'G-4XX5S9FBEH',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCAO4R-OBI4HK4U9xU2jtZQolFDVIvjITI',
    appId: '1:561556257232:web:4778872ba454357a9ae1d5',
    messagingSenderId: '561556257232',
    projectId: 'katiyastation-adf42',
    authDomain: 'katiyastation-adf42.firebaseapp.com',
    storageBucket: 'katiyastation-adf42.firebasestorage.app',
    measurementId: 'G-PSKRYP4LWR',
  );
}
