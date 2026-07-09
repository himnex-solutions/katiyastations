// ============================================================
// KATIYA STATION RMS — REFRESH SIGNALS
// A bridge for screens that load their data imperatively (initState →
// _load()) rather than through a Riverpod provider. `ref.invalidate` has
// nothing to invalidate for those, so realtime_sync bumps a counter here
// instead and the screen listens for the change.
//
// Prefer a FutureProvider for new screens — then plain invalidation works
// and none of this is needed.
// ============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Entity keys, matching the `entity` field of the backend's `data:changed`
/// payload (the first path segment after the API prefix).
class RefreshEntity {
  RefreshEntity._();
  static const String customers = 'customers';
  static const String staff = 'staff';
  static const String attendance = 'attendance';
  static const String shiftClosing = 'shift-closing';
}

/// Monotonic tick per entity. Screens watch the entity they render and
/// reload whenever it advances.
final entityRefreshProvider =
    StateProvider.family<int, String>((ref, entity) => 0);

/// Called from the realtime layer when the server reports a write.
void bumpRefresh(Ref ref, String entity) {
  ref.read(entityRefreshProvider(entity).notifier).state++;
}
