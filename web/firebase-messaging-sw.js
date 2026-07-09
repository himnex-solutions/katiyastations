// ============================================================
// KATIYA STATION RMS — WEB PUSH SERVICE WORKER
// firebase_messaging looks for this file at the web root and registers it
// automatically. Without it, FirebaseMessaging.onBackgroundMessage does
// nothing in the browser.
//
// Config must match the `web` block of lib/firebase_options.dart. A service
// worker cannot read Dart, so these values are duplicated by necessity — if
// you re-run `flutterfire configure` against a different project, update them.
// They are not secrets: Firebase web config is public by design.
// ============================================================

importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCAO4R-OBI4HK4U9xU2jtZQolFDVIvjITI',
  appId: '1:561556257232:web:e9849d57397877cb9ae1d5',
  messagingSenderId: '561556257232',
  projectId: 'katiyastation-adf42',
  authDomain: 'katiyastation-adf42.firebaseapp.com',
  storageBucket: 'katiyastation-adf42.firebasestorage.app',
  measurementId: 'G-4XX5S9FBEH',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = (payload.notification && payload.notification.title) || 'Katiya Station';
  self.registration.showNotification(title, {
    body: (payload.notification && payload.notification.body) || '',
    icon: '/icons/Icon-192.png',
  });
});
