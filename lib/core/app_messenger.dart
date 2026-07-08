// ============================================================
// KATIYA STATION RMS — GLOBAL SCAFFOLD MESSENGER
// A single app-wide messenger key so background listeners (e.g. the
// realtime low-stock alert) can surface a SnackBar without needing a
// BuildContext from whatever screen the user happens to be on.
// ============================================================

import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
