// ============================================================
// KATIYA STATION RMS — KOT AUTO-PRINT (retired socket station)
// KOT auto-printing now happens on the *sending* device the instant a waiter
// taps "Send KOT to Kitchen": OrderNotifier.sendKot → autoPrintKotToKitchen
// prints straight to the kitchen LAN printer, with no internet round-trip.
//
// The old model printed on a passive station in response to the backend's
// `kot:new` socket event (phone → server → back → printer, so it needed the
// internet). Running both would print every ticket twice on any device that is
// both an order-taker and a station, so the socket path is retired. This
// provider is kept as a harmless no-op so AppShell, which watches it, and any
// other reference keep compiling.
// ============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

final kotAutoPrintProvider = Provider<void>((ref) {});
