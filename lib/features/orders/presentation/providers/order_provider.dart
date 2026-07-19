import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/offline/connectivity_provider.dart';
import '../../../../core/offline/offline_cache.dart';
import '../../../../core/offline/offline_store.dart';
import '../../../../core/offline/offline_ids.dart';
import '../../../../core/offline/isar_schemas.dart';
import '../../../../core/offline/sync_engine.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../menu/domain/entities/menu_entities.dart';
import '../../../tables/presentation/providers/tables_provider.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../domain/entities/order_entities.dart';

List<MenuCategory> _activeCategories(List<dynamic> rows) => rows
    .map((r) => MenuCategory.fromJson(r as Map<String, dynamic>))
    .where((c) => c.isActive)
    .toList()
  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

List<MenuItem> _availableItems(List<dynamic> rows) => rows
    .map((r) => MenuItem.fromJson(r as Map<String, dynamic>))
    .where((i) => i.isAvailable)
    .toList()
  ..sort((a, b) => a.name.compareTo(b.name));

// Menu categories for ordering (by branchId). Cached on success so the waiter
// can still build an order while offline; falls back to that cache on a
// network failure.
final menuCategoriesProvider =
    FutureProvider.family<List<MenuCategory>, String>((ref, branchId) async {
  final key = CacheKeys.menuCategories(branchId);
  try {
    final response = await ApiClient.instance.get(
      ApiConstants.menuCategories,
      queryParameters: {'branchId': branchId},
    );
    final rows = response.data as List<dynamic>;
    await OfflineCache.instance.put(key, rows);
    return _activeCategories(rows);
  } on NetworkException {
    final cached = await OfflineCache.instance.get(key);
    if (cached is List) return _activeCategories(cached);
    rethrow;
  }
});

// Menu items for ordering (by categoryId).
final menuItemsProvider =
    FutureProvider.family<List<MenuItem>, String>((ref, categoryId) async {
  final key = CacheKeys.menuItemsByCategory(categoryId);
  try {
    final response = await ApiClient.instance.get(
      ApiConstants.menuItems,
      queryParameters: {'categoryId': categoryId},
    );
    final rows = response.data as List<dynamic>;
    await OfflineCache.instance.put(key, rows);
    return _availableItems(rows);
  } on NetworkException {
    final cached = await OfflineCache.instance.get(key);
    if (cached is List) return _availableItems(cached);
    rethrow;
  }
});

// All menu items across every category for a branch — used by menu search.
final allMenuItemsProvider =
    FutureProvider.family<List<MenuItem>, String>((ref, branchId) async {
  final key = CacheKeys.menuItemsByBranch(branchId);
  try {
    final response = await ApiClient.instance.get(
      ApiConstants.menuItems,
      queryParameters: {'branchId': branchId},
    );
    final rows = response.data as List<dynamic>;
    await OfflineCache.instance.put(key, rows);
    return _availableItems(rows);
  } on NetworkException {
    final cached = await OfflineCache.instance.get(key);
    if (cached is List) return _availableItems(cached);
    rethrow;
  }
});

KotWithItems _kotWithItemsFromJson(Map<String, dynamic> json) => KotWithItems(
      id: json['id'] as String,
      branchId: json['branch_id'] as String,
      sessionId: json['session_id'] as String,
      tableId: json['table_id'] as String? ?? '',
      kotNumber: json['kot_number'] as String,
      status: json['status'] as String? ?? 'pending',
      waiterId: json['waiter_id'] as String?,
      waiterName: json['waiter_name'] as String?,
      items: List<Map<String, dynamic>>.from(json['items'] as List? ?? []),
      createdAt: DateTime.parse(json['created_at'] as String),
      notes: json['notes'] as String?,
    );

/// KOTs taken offline for [sessionId] (not yet uploaded), rebuilt from the
/// local Isar copy so they render on the order screen like server ones.
Future<List<KotWithItems>> _offlineKotsFor(String sessionId) async {
  final kots = await OfflineStore.instance.kotsForSession(sessionId);
  final result = <KotWithItems>[];
  for (final k in kots) {
    final items = await OfflineStore.instance.itemsForKot(k.id);
    result.add(KotWithItems(
      id: k.id,
      branchId: k.branchId,
      sessionId: k.sessionId,
      tableId: k.tableId,
      kotNumber: k.kotNumber,
      status: k.status,
      waiterId: k.waiterId,
      waiterName: k.waiterName,
      items: items
          .map((i) => <String, dynamic>{
                'id': i.id,
                'kot_id': k.id,
                'menu_item_id': i.menuItemId,
                'name': i.menuItemName,
                'quantity': i.quantity,
                'unit_price': i.unitPrice,
                'note': i.notes,
                'status': 'pending',
              })
          .toList(),
      createdAt: k.createdAt,
    ));
  }
  return result;
}

// KOTs for a session — server data merged with any offline (pending-sync)
// orders. Offline, the server call fails and only local orders are shown.
final sessionKotsProvider =
    FutureProvider.family<List<KotWithItems>, String>((ref, sessionId) async {
  if (sessionId.isEmpty) return [];
  var serverKots = <KotWithItems>[];
  try {
    final response =
        await ApiClient.instance.get(ApiConstants.kotsBySession(sessionId));
    final rows = response.data as List<dynamic>;
    serverKots = rows
        .map((r) => _kotWithItemsFromJson(r as Map<String, dynamic>))
        .toList();
  } on NetworkException {
    // Offline — fall through to locally-stored orders only.
  }
  final offline = await _offlineKotsFor(sessionId);
  if (offline.isEmpty) return serverKots;
  final serverIds = serverKots.map((k) => k.id).toSet();
  return [...serverKots, ...offline.where((k) => !serverIds.contains(k.id))];
});

/// What a session's kitchen orders allow the waiter to do next.
///
/// The kitchen walks each KOT `pending -> preparing -> ready -> served`, and
/// only `served` means the guest actually has the food. Cancelled KOTs are
/// ignored: they were voided, so nobody is waiting on them and a table left
/// with nothing but cancellations is empty again.
///
/// While the KOTs are still loading, both gates stay shut. Withholding a
/// button for a moment costs nothing; offering "Close & Free Table" on a table
/// with food on the way loses the bill.
class SessionOrderState {
  final bool isLoading;

  /// KOTs that haven't been cancelled.
  final int liveCount;

  /// Of those, how many the kitchen hasn't marked served yet.
  final int unservedCount;

  const SessionOrderState({
    required this.isLoading,
    required this.liveCount,
    required this.unservedCount,
  });

  bool get hasOrders => liveCount > 0;

  /// The food is all out — the guest can be billed.
  bool get canRequestBill => !isLoading && liveCount > 0 && unservedCount == 0;

  /// Nothing was ever ordered — the table can be released without a bill.
  bool get canFreeTable => !isLoading && liveCount == 0;

  /// Why the bill can't be requested, or null when it can. Lives here so the
  /// tables screen and the order screen say the same thing to the waiter.
  String? get billBlockedReason {
    if (canRequestBill) return null;
    if (isLoading) return 'Checking orders…';
    if (liveCount == 0) return 'Nothing ordered yet — use Close & Free Table';
    final s = unservedCount == 1 ? '' : 's';
    return 'Waiting on the kitchen — $unservedCount order$s not served yet';
  }

  /// Why the table can't be freed, or null when it can.
  String? get freeBlockedReason {
    if (canFreeTable) return null;
    if (isLoading) return 'Checking orders…';
    return 'Table has orders — use Request Bill to free it';
  }
}

/// Live view of [sessionKotsProvider]. The realtime layer invalidates that
/// provider on every `kot:new` and `kot:status_changed`, so a waiter watching
/// this sees "Request Bill" unlock the instant the kitchen marks the last
/// order served — no refresh, no reopening the dialog.
final sessionOrderStateProvider =
    Provider.family<SessionOrderState, String>((ref, sessionId) {
  final kots = ref.watch(sessionKotsProvider(sessionId)).valueOrNull;
  if (kots == null) {
    return const SessionOrderState(isLoading: true, liveCount: 0, unservedCount: 0);
  }
  final live = kots.where((k) => k.status != 'cancelled');
  return SessionOrderState(
    isLoading: false,
    liveCount: live.length,
    unservedCount: live.where((k) => k.status != 'served').length,
  );
});

// Cart state for current order
class CartItem {
  final MenuItem item;
  int quantity;
  String? notes;

  CartItem({required this.item, this.quantity = 1, this.notes});

  double get total => item.price * quantity;
}

class OrderNotifier extends StateNotifier<List<CartItem>> {
  final Ref _ref;
  OrderNotifier(this._ref) : super([]);

  void addItem(MenuItem item) {
    final existing = state.where((c) => c.item.id == item.id).toList();
    if (existing.isNotEmpty) {
      state = state.map((c) => c.item.id == item.id
          ? (CartItem(item: c.item, quantity: c.quantity + 1, notes: c.notes))
          : c).toList();
    } else {
      state = [...state, CartItem(item: item)];
    }
  }

  void removeItem(String itemId) {
    state = state.where((c) => c.item.id != itemId).toList();
  }

  void increaseQty(String itemId) {
    state = state.map((c) => c.item.id == itemId
        ? CartItem(item: c.item, quantity: c.quantity + 1, notes: c.notes)
        : c).toList();
  }

  void decreaseQty(String itemId) {
    state = state.map((c) {
      if (c.item.id == itemId) {
        if (c.quantity <= 1) return null;
        return CartItem(item: c.item, quantity: c.quantity - 1, notes: c.notes);
      }
      return c;
    }).whereType<CartItem>().toList();
  }

  void clearCart() => state = [];

  double get subtotal => state.fold(0, (sum, c) => sum + c.total);

  Future<Kot?> sendKot({
    required String sessionId,
    required String tableId,
    required String branchId,
    String? notes,
  }) async {
    if (state.isEmpty) return null;
    final profile = _ref.read(authNotifierProvider).value;
    final waiterId = profile?.id;
    final waiterName = profile?.fullName;

    // One client-generated id, used for both the online call and (if it fails)
    // the offline copy — so a send that times out mid-flight and later replays
    // from the queue is idempotent on the server (never a duplicate ticket).
    final kotId = newOfflineId();
    final cart = List<CartItem>.from(state);
    final itemsPayload = cart
        .map((c) => <String, dynamic>{
              'menuItemId': c.item.id,
              'name': c.item.name,
              'quantity': c.quantity,
              if (c.notes != null) 'note': c.notes,
            })
        .toList();

    if (_ref.read(connectivityProvider)) {
      try {
        final response = await ApiClient.instance.post(
          ApiConstants.kots,
          data: {
            'id': kotId,
            'sessionId': sessionId,
            if (waiterId != null) 'waiterId': waiterId,
            'items': itemsPayload,
          },
        );

        final json = response.data as Map<String, dynamic>;
        final rawItems = json['items'] as List? ?? [];
        final kot = Kot(
          id: json['id'] as String,
          branchId: json['branch_id'] as String,
          sessionId: json['session_id'] as String,
          tableId: json['table_id'] as String? ?? tableId,
          kotNumber: json['kot_number'] as String,
          status: json['status'] as String? ?? 'pending',
          waiterId: json['waiter_id'] as String? ?? waiterId,
          waiterName: json['waiter_name'] as String? ?? waiterName,
          items: rawItems
              .map((i) => KotItem.fromJson(i as Map<String, dynamic>))
              .toList(),
          createdAt: DateTime.parse(json['created_at'] as String),
          notes: notes,
        );

        _ref.invalidate(sessionKotsProvider(sessionId));
        _ref.invalidate(tableSessionProvider(tableId));
        _ref.invalidate(dashboardKotsProvider);
        _ref.invalidate(dashboardSessionsProvider);

        clearCart();
        return kot;
      } on NetworkException {
        // Lost the connection mid-send — fall through and capture it offline.
      }
    }

    return _sendKotOffline(
      kotId: kotId,
      sessionId: sessionId,
      tableId: tableId,
      branchId: branchId,
      notes: notes,
      waiterId: waiterId,
      waiterName: waiterName,
      cart: cart,
      itemsPayload: itemsPayload,
    );
  }

  /// Persists a KOT locally and queues it for upload — used when the device is
  /// offline (or drops mid-send). The returned [Kot] carries a provisional
  /// number so the ticket prints and the UI updates immediately.
  Future<Kot> _sendKotOffline({
    required String kotId,
    required String sessionId,
    required String tableId,
    required String branchId,
    required String? notes,
    required String? waiterId,
    required String? waiterName,
    required List<CartItem> cart,
    required List<Map<String, dynamic>> itemsPayload,
  }) async {
    final now = DateTime.now();
    final kotNumber = provisionalNumber(kotId);

    final offlineKot = OfflineKot()
      ..id = kotId
      ..branchId = branchId
      ..sessionId = sessionId
      ..tableId = tableId
      ..kotNumber = kotNumber
      ..status = 'pending'
      ..waiterId = waiterId
      ..waiterName = waiterName
      ..createdAt = now
      ..isPendingSync = true
      ..syncedAt = now;

    final offlineItems = cart
        .map((c) => OfflineKotItem()
          ..id = newOfflineId()
          ..kotId = kotId
          ..menuItemId = c.item.id
          ..menuItemName = c.item.name
          ..quantity = c.quantity
          ..unitPrice = c.item.price
          ..notes = c.notes
          ..createdAt = now)
        .toList();

    await OfflineStore.instance.saveOfflineKot(offlineKot, offlineItems);
    await OfflineStore.instance.enqueue(
      entityType: 'kot',
      operation: 'create',
      endpoint: ApiConstants.kots,
      method: 'POST',
      payload: {
        'id': kotId,
        'sessionId': sessionId,
        if (waiterId != null) 'waiterId': waiterId,
        'items': itemsPayload,
      },
    );
    await _ref.read(pendingSyncProvider.notifier).refresh();

    _ref.invalidate(sessionKotsProvider(sessionId));
    _ref.invalidate(tableSessionProvider(tableId));

    clearCart();

    return Kot(
      id: kotId,
      branchId: branchId,
      sessionId: sessionId,
      tableId: tableId,
      kotNumber: kotNumber,
      status: 'pending',
      waiterId: waiterId,
      waiterName: waiterName,
      items: offlineItems
          .map((i) => KotItem(
                id: i.id,
                kotId: kotId,
                menuItemId: i.menuItemId,
                menuItemName: i.menuItemName,
                quantity: i.quantity,
                unitPrice: i.unitPrice,
                notes: i.notes,
              ))
          .toList(),
      createdAt: now,
      notes: notes,
    );
  }
}

final orderNotifierProvider = StateNotifierProvider<OrderNotifier, List<CartItem>>(
  (ref) => OrderNotifier(ref),
);
