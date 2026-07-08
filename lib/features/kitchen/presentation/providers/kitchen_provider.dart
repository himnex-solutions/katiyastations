// ============================================================
// KATIYA STATION RMS — KITCHEN PROVIDER
// Realtime KOT management via Socket.IO + REST API
// ============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../orders/domain/entities/order_entities.dart';

// ── All active KOTs for this branch (REST fetch) ───────────
final kitchenKotsProvider = FutureProvider<List<Kot>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile == null) return [];

  final response = await ApiClient.instance.get(
    ApiConstants.kots,
    queryParameters: {
      'branchId': profile.branchId ?? '',
      'status': 'pending,preparing,ready',
      'sort': 'created_at:asc',
      'limit': '100',
    },
  );

  if (response.statusCode == 200) {
    final items = response.data as List<dynamic>? ?? [];
    return items.map((r) => Kot.fromJson(r as Map<String, dynamic>)).toList();
  }
  return [];
});

// ── KOT items for a specific KOT ──────────────────────────
final kotItemsProvider =
    FutureProvider.family<List<KotItem>, String>((ref, kotId) async {
  final response = await ApiClient.instance.get(
    ApiConstants.kotItems(kotId),
  );

  if (response.statusCode == 200) {
    final items = response.data as List<dynamic>? ?? [];
    return items
        .map((r) => KotItem.fromJson(r as Map<String, dynamic>))
        .toList();
  }
  return [];
});

// ── Kitchen Status Notifier ────────────────────────────────
class KitchenNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  KitchenNotifier(this._ref) : super(const AsyncValue.data(null));

  // ── Update KOT status (pending → preparing → ready → served) ──
  Future<void> updateKotStatus(String kotId, String newStatus) async {
    state = const AsyncValue.loading();
    try {
      final response = await ApiClient.instance.patch(
        ApiConstants.updateKotStatus(kotId),
        data: {
          'status': newStatus,
          if (newStatus == 'served')
            'servedAt': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        state = const AsyncValue.data(null);
        // Invalidate to refresh the list
        _ref.invalidate(kitchenKotsProvider);
      } else {
        state = AsyncValue.error(
          'Failed to update KOT status.',
          StackTrace.current,
        );
      }
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
    }
  }

  // ── Mark individual item's own status (pending/preparing/ready/served/cancelled) ──
  // Returns an error message on failure (e.g. the 403 "ask a manager"
  // guard once the KOT has left pending), or null on success, so the UI
  // can show it without relying on this notifier's shared AsyncValue state.
  Future<String?> updateItemStatus(
    String kotId,
    String itemId,
    String newStatus,
  ) async {
    try {
      await ApiClient.instance.patch(
        ApiConstants.updateKotItemStatus(kotId, itemId),
        data: {'status': newStatus},
      );
      _ref.invalidate(kotItemsProvider(kotId));
      _ref.invalidate(kitchenKotsProvider);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Cancel a KOT item ─────────────────────────────────────
  Future<String?> cancelKotItem(String kotId, String itemId) {
    return updateItemStatus(kotId, itemId, 'cancelled');
  }

  // ── Return a served item (post-serve void, no restock) ────
  Future<String?> returnItem(String kotId, String itemId, {String? reason}) async {
    try {
      await ApiClient.instance.post(
        ApiConstants.returnKotItem(kotId, itemId),
        data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
      );
      _ref.invalidate(kotItemsProvider(kotId));
      _ref.invalidate(kitchenKotsProvider);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Record a KOT print (first print or reprint) ───────────
  Future<void> recordPrint(String kotId) async {
    try {
      await ApiClient.instance.post(ApiConstants.printKot(kotId));
      _ref.invalidate(kitchenKotsProvider);
    } catch (_) {
      // Non-critical — the physical print already happened client-side;
      // failing to record the counter shouldn't block the user.
    }
  }
}

final kitchenNotifierProvider =
    StateNotifierProvider<KitchenNotifier, AsyncValue<void>>(
  (ref) => KitchenNotifier(ref),
);
